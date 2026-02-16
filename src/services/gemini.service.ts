import {
  GoogleGenerativeAI,
  GenerativeModel,
  Content,
  HarmCategory,
  HarmBlockThreshold,
  GenerateContentStreamResult,
} from "@google/generative-ai";
import config from "../config/env";
import logger from "../infra/logger";
import { Message } from "../models/message.model";
import { PromptModel } from "../models/prompt.model";

export interface GeminiMessage {
  role: "user" | "model" | "assistant";
  content: string;
}

export interface GeminiStreamOptions {
  requestId: string;
  promptName?: string; // Which prompt to use
  onToken?: (token: string) => void;
  onComplete?: (fullText: string, usage: TokenUsage) => void;
  onError?: (error: Error) => void;
}

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

/**
 * Gemini Service
 *
 * Handles interactions with Google Gemini API:
 * - Message streaming with safety handling
 * - Token counting (server-side & estimation)
 * - Budget enforcement
 * - Prompt versioning
 */
export class GeminiService {
  private genAI: GoogleGenerativeAI;
  private model: GenerativeModel;
  private maxTokens: number;

  constructor() {
    if (!config.gemini.apiKey) {
      throw new Error("GEMINI_API_KEY is required in config");
    }

    this.genAI = new GoogleGenerativeAI(config.gemini.apiKey);

    // Initialize model with specific safety settings to avoid over-blocking
    this.model = this.genAI.getGenerativeModel({
      model: "models/gemini-2.5-flash",

      // ✅ This nesting is correct for @google/generative-ai
      generationConfig: {
        maxOutputTokens: config.gemini.maxTokens || 2048,
        temperature: 0.9,
        // Removed topP: 1 to allow temperature to work better
      },
      safetySettings: [
        {
          category: HarmCategory.HARM_CATEGORY_HARASSMENT,
          threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
          threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
          threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        },
        {
          category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
          threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
        },
      ],
    });

    this.maxTokens = config.gemini.maxTokens || 2048;

    logger.info("Gemini service initialized", {
      model: config.gemini.model,
      maxTokens: this.maxTokens,
    });
  }

  /**
   * Get system prompt from database
   */
  private async getSystemPrompt(
    promptName: string = "default-system-prompt",
  ): Promise<{
    content: string;
    promptId: string;
  }> {
    const prompt = await PromptModel.getActive(promptName);

    if (!prompt) {
      logger.warn("No active prompt found, using fallback", { promptName });
      return {
        content: "You are a helpful AI assistant.",
        promptId: "fallback",
      };
    }

    logger.debug("Using prompt", {
      name: prompt.name,
      version: prompt.version,
      promptId: prompt.id,
    });

    return {
      content: prompt.content,
      promptId: prompt.id,
    };
  }

  /**
   * Stream a chat completion with versioned prompts
   */
  async streamChat(
    messages: GeminiMessage[],
    options: GeminiStreamOptions,
  ): Promise<void> {
    const startTime = Date.now();

    try {
      if (!messages || messages.length === 0) {
        throw new Error("Message history cannot be empty");
      }

      // Get system prompt from database
      const { content: systemPrompt, promptId } = await this.getSystemPrompt(
        options.promptName,
      );

      logger.info("Starting Gemini stream", {
        requestId: options.requestId,
        messageCount: messages.length,
        model: config.gemini.model,
        promptId,
      });

      // Convert messages to Gemini SDK format
      const history = this.messagesToGeminiContents(messages);

      // Separate history (previous messages) and prompt (last message)
      const chatHistory = history.slice(0, -1);
      const lastMessageContent = messages[messages.length - 1].content;

      // Create chat session with system prompt
      const chat = this.model.startChat({
        history: chatHistory,
        // 👇 WRAP IT LIKE THIS
        systemInstruction: {
          parts: [{ text: systemPrompt }],
        },
      });

      // Stream the response
      const result: GenerateContentStreamResult =
        await chat.sendMessageStream(lastMessageContent);

      let fullText = "";
      let inputTokens = 0;
      let outputTokens = 0;

      // Process the stream
      for await (const chunk of result.stream) {
        try {
          // IMPORTANT: chunk.text() throws if the chunk was blocked by safety filters
          const chunkText = chunk.text();
          fullText += chunkText;

          if (options.onToken) {
            options.onToken(chunkText);
          }
        } catch (e) {
          logger.warn("Gemini stream chunk blocked or empty", {
            requestId: options.requestId,
            reason: "Safety Filter or Empty Chunk",
          });
          // We continue processing to get token usage even if text is blocked
        }

        // Capture usage from chunk if available (SDK v0.13+)
        if (chunk.usageMetadata) {
          inputTokens = chunk.usageMetadata.promptTokenCount;
          outputTokens = chunk.usageMetadata.candidatesTokenCount;
        }
      }

      // Get final response metadata (ensures we have usage even if stream loop missed it)
      const response = await result.response;
      if (response.usageMetadata) {
        inputTokens = response.usageMetadata.promptTokenCount;
        outputTokens = response.usageMetadata.candidatesTokenCount;
      }

      const usage: TokenUsage = {
        inputTokens,
        outputTokens,
        totalTokens: inputTokens + outputTokens,
      };

      const responseTime = Date.now() - startTime;

      // Update prompt stats
      if (promptId !== "fallback") {
        await PromptModel.updateStats(
          promptId,
          usage.totalTokens,
          responseTime,
        );
      }

      logger.info("Gemini stream completed", {
        requestId: options.requestId,
        inputTokens,
        outputTokens,
        totalTokens: usage.totalTokens,
        responseLength: fullText.length,
        responseTimeMs: responseTime,
        promptId,
      });

      if (options.onComplete) {
        options.onComplete(fullText, usage);
      }
    } catch (error) {
      logger.error("Gemini stream error", {
        requestId: options.requestId,
        error: error instanceof Error ? error.message : String(error),
      });

      if (options.onError && error instanceof Error) {
        options.onError(error);
      }

      throw error;
    }
  }

  /**
   * Non-streaming chat completion with versioned prompts
   */
  async chat(
    messages: GeminiMessage[],
    promptName: string = "default-system-prompt",
  ): Promise<{
    text: string;
    usage: TokenUsage;
  }> {
    const startTime = Date.now();

    try {
      if (!messages || messages.length === 0) {
        throw new Error("Message history cannot be empty");
      }

      // Get system prompt from database
      const { content: systemPrompt, promptId } =
        await this.getSystemPrompt(promptName);

      logger.info("Starting Gemini request", {
        messageCount: messages.length,
        model: config.gemini.model,
        promptId,
      });

      const history = this.messagesToGeminiContents(messages);
      const chatHistory = history.slice(0, -1);
      const lastMessageContent = messages[messages.length - 1].content;

      const chat = this.model.startChat({
        history: chatHistory,
        // 👇 WRAP IT LIKE THIS
        systemInstruction: {
          parts: [{ text: systemPrompt }],
        },
      });

      const result = await chat.sendMessage(lastMessageContent);
      const response = await result.response;

      // Handle blocked responses safely
      let text = "";
      try {
        text = response.text();
      } catch (e) {
        logger.warn("Gemini chat response blocked", { error: e });
        text = "[Content Blocked by Safety Filters]";
      }

      const usage: TokenUsage = {
        inputTokens: response.usageMetadata?.promptTokenCount || 0,
        outputTokens: response.usageMetadata?.candidatesTokenCount || 0,
        totalTokens:
          (response.usageMetadata?.promptTokenCount || 0) +
          (response.usageMetadata?.candidatesTokenCount || 0),
      };

      const responseTime = Date.now() - startTime;

      // Update prompt stats
      if (promptId !== "fallback") {
        await PromptModel.updateStats(
          promptId,
          usage.totalTokens,
          responseTime,
        );
      }

      logger.info("Gemini request completed", {
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
        responseTimeMs: responseTime,
        promptId,
      });

      return { text, usage };
    } catch (error) {
      logger.error("Gemini request error", { error });
      throw error;
    }
  }

  /**
   * Convert internal messages to Gemini SDK contents format
   */
  private messagesToGeminiContents(messages: GeminiMessage[]): Content[] {
    return messages.map((m) => ({
      role: m.role === "model" ? "model" : "user",
      parts: [{ text: m.content }],
    }));
  }

  /**
   * Convert database messages to Gemini Service format
   */
  messagesToGeminiFormat(messages: Message[]): GeminiMessage[] {
    return messages
      .filter((m) => m.role === "user" || m.role === "assistant")
      .map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        content: m.content,
      }));
  }

  /**
   * Estimate token count (rough approximation)
   * 1 token ~= 4 chars in English
   */
  estimateTokens(text: string): number {
    if (!text) return 0;
    return Math.ceil(text.length / 4);
  }

  /**
   * Check if request would exceed token budget
   */
  wouldExceedBudget(messages: GeminiMessage[]): boolean {
    const estimatedInputTokens = messages.reduce(
      (sum, m) => sum + this.estimateTokens(m.content),
      0,
    );

    // Leave room for response
    const totalEstimated = estimatedInputTokens + this.maxTokens;

    // Gemini 1.5 Flash context window is huge (1M), so this is rarely hit
    // Adjust this limit based on your specific needs or tier constraints
    const contextLimit = 1000000;

    return totalEstimated > contextLimit;
  }
}

export const geminiService = new GeminiService();
export default geminiService;
