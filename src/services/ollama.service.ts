import config from '../config/env';
import logger from '../infra/logger';
import { Message } from '../models/message.model';
import { PromptModel } from '../models/prompt.model';

export interface OllamaMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface OllamaStreamOptions {
  requestId: string;
  promptName?: string;
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
 * Ollama Service
 * 
 * Handles all interactions with local Ollama API:
 * - Message streaming
 * - Token counting (estimation)
 * - Support for various models (llama3, mistral, codellama, etc.)
 * - Fallback to external APIs if needed
 */
export class OllamaService {
  private baseUrl: string;
  private model: string;
  private maxTokens: number;

  constructor() {
    this.baseUrl = config.local.baseUrl;
    this.model = config.local.model;
    this.maxTokens = config.local.maxTokens;

    logger.info('Ollama service initialized', {
      baseUrl: this.baseUrl,
      model: this.model,
      maxTokens: this.maxTokens,
    });
  }

  /**
   * Check if Ollama is available
   */
  async checkHealth(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/api/tags`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });
      return response.ok;
    } catch (error) {
      logger.warn('Ollama health check failed', {
        error: error instanceof Error ? error.message : String(error),
      });
      return false;
    }
  }

  /**
   * Get available models from Ollama
   */
  async getAvailableModels(): Promise<string[]> {
    try {
      const response = await fetch(`${this.baseUrl}/api/tags`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });
      
      if (!response.ok) {
        throw new Error(`Ollama API error: ${response.status}`);
      }
      
      const data = await response.json() as { models: Array<{ name: string }> };
      return data.models.map(m => m.name);
    } catch (error) {
      logger.error('Failed to get Ollama models', {
        error: error instanceof Error ? error.message : String(error),
      });
      return [];
    }
  }

  /**
   * Get system prompt from database
   */
  private async getSystemPrompt(
    promptName: string = 'default-system-prompt',
  ): Promise<{ content: string; promptId: string }> {
    const prompt = await PromptModel.getActive(promptName);

    if (!prompt) {
      logger.warn('No active prompt found, using fallback', { promptName });
      return {
        content: 'You are a helpful AI assistant.',
        promptId: 'fallback',
      };
    }

    logger.debug('Using prompt', {
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
    messages: OllamaMessage[],
    options: OllamaStreamOptions,
  ): Promise<void> {
    const startTime = Date.now();

    try {
      if (!messages || messages.length === 0) {
        throw new Error('Message history cannot be empty');
      }

      // Get system prompt from database
      const { content: systemPrompt, promptId } = await this.getSystemPrompt(
        options.promptName,
      );

      logger.info('Starting Ollama stream', {
        requestId: options.requestId,
        messageCount: messages.length,
        model: this.model,
        promptId,
      });

      // Prepare messages for Ollama format
      const ollamaMessages = this.messagesToOllamaFormat(messages, systemPrompt);

      // Calculate estimated input tokens
      const inputContent = JSON.stringify(ollamaMessages);
      const inputTokens = this.estimateTokens(inputContent);

      // Make streaming request to Ollama
      const response = await fetch(`${this.baseUrl}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: this.model,
          messages: ollamaMessages,
          stream: true,
          options: {
            num_predict: this.maxTokens,
            temperature: 0.9,
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Ollama API error: ${response.status} - ${errorText}`);
      }

      if (!response.body) {
        throw new Error('No response body from Ollama');
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let fullText = '';
      let outputTokens = 0;

      // Read the stream
      while (true) {
        const { done, value } = await reader.read();
        
        if (done) {
          break;
        }

        const chunk = decoder.decode(value);
        const lines = chunk.split('\n').filter(line => line.trim());

        for (const line of lines) {
          try {
            const data = JSON.parse(line);
            
            if (data.message?.content) {
              const token = data.message.content;
              fullText += token;
              outputTokens += this.estimateTokens(token);

              if (options.onToken) {
                options.onToken(token);
              }
            }

            // Check for done signal
            if (data.done) {
              break;
            }
          } catch (e) {
            // Skip invalid JSON lines
            logger.debug('Skipping invalid JSON line in stream', { line });
          }
        }
      }

      const usage: TokenUsage = {
        inputTokens,
        outputTokens,
        totalTokens: inputTokens + outputTokens,
      };

      const responseTime = Date.now() - startTime;

      // Update prompt stats
      if (promptId !== 'fallback') {
        await PromptModel.updateStats(
          promptId,
          usage.totalTokens,
          responseTime,
        );
      }

      logger.info('Ollama stream completed', {
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
      logger.error('Ollama stream error', {
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
   * Non-streaming chat completion
   */
  async chat(
    messages: OllamaMessage[],
    promptName: string = 'default-system-prompt',
  ): Promise<{ text: string; usage: TokenUsage }> {
    const startTime = Date.now();

    try {
      if (!messages || messages.length === 0) {
        throw new Error('Message history cannot be empty');
      }

      // Get system prompt from database
      const { content: systemPrompt, promptId } = await this.getSystemPrompt(promptName);

      logger.info('Starting Ollama request', {
        messageCount: messages.length,
        model: this.model,
        promptId,
      });

      // Prepare messages for Ollama format
      const ollamaMessages = this.messagesToOllamaFormat(messages, systemPrompt);

      // Calculate estimated input tokens
      const inputContent = JSON.stringify(ollamaMessages);
      const inputTokens = this.estimateTokens(inputContent);

      // Make request to Ollama
      const response = await fetch(`${this.baseUrl}/api/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: this.model,
          messages: ollamaMessages,
          stream: false,
          options: {
            num_predict: this.maxTokens,
            temperature: 0.9,
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Ollama API error: ${response.status} - ${errorText}`);
      }

      const data = await response.json() as {
        message: { content: string };
        done: boolean;
      };

      const text = data.message?.content || '';
      const outputTokens = this.estimateTokens(text);

      const usage: TokenUsage = {
        inputTokens,
        outputTokens,
        totalTokens: inputTokens + outputTokens,
      };

      const responseTime = Date.now() - startTime;

      // Update prompt stats
      if (promptId !== 'fallback') {
        await PromptModel.updateStats(promptId, usage.totalTokens, responseTime);
      }

      logger.info('Ollama request completed', {
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
        responseTimeMs: responseTime,
        promptId,
      });

      return { text, usage };
    } catch (error) {
      logger.error('Ollama request error', {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  /**
   * Convert messages to Ollama format with system prompt
   */
  private messagesToOllamaFormat(
    messages: OllamaMessage[],
    systemPrompt: string,
  ): OllamaMessage[] {
    // Add system prompt as first message
    const ollamaMessages: OllamaMessage[] = [
      {
        role: 'system',
        content: systemPrompt,
      },
    ];

    // Add conversation messages
    for (const msg of messages) {
      ollamaMessages.push({
        role: msg.role === 'assistant' ? 'assistant' : 'user',
        content: msg.content,
      });
    }

    return ollamaMessages;
  }

  /**
   * Convert database messages to Ollama format
   */
  messagesToOllamaMessageFormat(messages: Message[]): OllamaMessage[] {
    return messages
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        role: m.role as 'user' | 'assistant',
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
  wouldExceedBudget(messages: OllamaMessage[]): boolean {
    const estimatedInputTokens = messages.reduce(
      (sum, m) => sum + this.estimateTokens(m.content),
      0,
    );

    // Leave room for response
    const totalEstimated = estimatedInputTokens + this.maxTokens;

    // Ollama models typically have 4k-8k context windows
    // Adjust based on your specific model
    const contextLimit = 8192;

    return totalEstimated > contextLimit;
  }

  /**
   * Generate embeddings for text using nomic-embed-text
   */
  async generateEmbedding(text: string): Promise<number[]> {
    try {
      logger.debug('Generating embedding', {
        textLength: text.length,
        model: 'nomic-embed-text',
      });

      const response = await fetch(`${this.baseUrl}/api/embeddings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'nomic-embed-text',
          prompt: text,
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Ollama embedding error: ${response.status} - ${errorText}`);
      }

      const data = await response.json() as { embedding: number[] };

      if (!data.embedding || !Array.isArray(data.embedding)) {
        throw new Error('Invalid embedding response from Ollama');
      }

      logger.debug('Embedding generated', {
        dimensions: data.embedding.length,
      });

      return data.embedding;
    } catch (error) {
      logger.error('Failed to generate embedding', {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }
}

// Export a lazy-initialized singleton

let ollamaServiceInstance: OllamaService | null = null;

export function getOllamaService(): OllamaService {
  if (!ollamaServiceInstance) {
    ollamaServiceInstance = new OllamaService();
  }
  return ollamaServiceInstance;
}

export default getOllamaService();
