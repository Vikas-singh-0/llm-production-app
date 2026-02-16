import Anthropic from '@anthropic-ai/sdk';
import config from '../config/env';
import logger from '../infra/logger';
import { Message } from '../models/message.model';
import { PromptModel } from '../models/prompt.model';

export interface ClaudeMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ClaudeStreamOptions {
  requestId: string;
  promptName?: string;  // Which prompt to use
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
 * Claude Service
 * 
 * Handles all interactions with Claude API:
 * - Message streaming
 * - Token counting
 * - Budget enforcement
 * - Prompt versioning
 */
export class ClaudeService {
  private client: Anthropic;
  private model: string;
  private maxTokens: number;

  constructor() {
    if (!config.claude.apiKey) {
      throw new Error('ANTHROPIC_API_KEY is required');
    }

    this.client = new Anthropic({
      apiKey: config.claude.apiKey,
    });

    this.model = config.claude.model;
    this.maxTokens = config.claude.maxTokens;

    logger.info('Claude service initialized', {
      model: this.model,
      maxTokens: this.maxTokens,
    });
  }

  /**
   * Get system prompt from database
   */
  private async getSystemPrompt(promptName: string = 'default-system-prompt'): Promise<{
    content: string;
    promptId: string;
  }> {
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
    messages: ClaudeMessage[],
    options: ClaudeStreamOptions
  ): Promise<void> {
    const startTime = Date.now();

    try {
      // Get system prompt from database
      const { content: systemPrompt, promptId } = await this.getSystemPrompt(
        options.promptName
      );

      logger.info('Starting Claude stream', {
        requestId: options.requestId,
        messageCount: messages.length,
        model: this.model,
        maxTokens: this.maxTokens,
        promptId,
      });

      // Convert to Anthropic format with system prompt
      const anthropicMessages = messages.map(m => ({
        role: m.role,
        content: m.content,
      }));

      // Create streaming request
      const stream = await this.client.messages.stream({
        model: this.model,
        max_tokens: this.maxTokens,
        system: systemPrompt,  // System prompt from database
        messages: anthropicMessages,
      });

      let fullText = '';
      let inputTokens = 0;
      let outputTokens = 0;

      // Handle stream events
      stream.on('text', (text) => {
        fullText += text;
        if (options.onToken) {
          options.onToken(text);
        }
      });

      stream.on('message', (message) => {
        // Extract usage from final message
        if (message.usage) {
          inputTokens = message.usage.input_tokens;
          outputTokens = message.usage.output_tokens;
        }
      });

      // Wait for stream to complete
      const finalMessage = await stream.finalMessage();

      // Get final usage stats
      if (finalMessage.usage) {
        inputTokens = finalMessage.usage.input_tokens;
        outputTokens = finalMessage.usage.output_tokens;
      }

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

      logger.info('Claude stream completed', {
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
      logger.error('Claude stream error', {
        requestId: options.requestId,
        error,
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
    messages: ClaudeMessage[],
    promptName: string = 'default-system-prompt'
  ): Promise<{ 
    text: string; 
    usage: TokenUsage;
  }> {
    const startTime = Date.now();

    try {
      // Get system prompt from database
      const { content: systemPrompt, promptId } = await this.getSystemPrompt(promptName);

      logger.info('Starting Claude request', {
        messageCount: messages.length,
        model: this.model,
        promptId,
      });

      const anthropicMessages = messages.map(m => ({
        role: m.role,
        content: m.content,
      }));

      const response = await this.client.messages.create({
        model: this.model,
        max_tokens: this.maxTokens,
        system: systemPrompt,  // System prompt from database
        messages: anthropicMessages,
      });

      const text = response.content
        .filter(block => block.type === 'text')
        .map(block => block.type === 'text' ? block.text : '')
        .join('');

      const usage: TokenUsage = {
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
        totalTokens: response.usage.input_tokens + response.usage.output_tokens,
      };

      const responseTime = Date.now() - startTime;

      // Update prompt stats
      if (promptId !== 'fallback') {
        await PromptModel.updateStats(promptId, usage.totalTokens, responseTime);
      }

      logger.info('Claude request completed', {
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
        responseTimeMs: responseTime,
        promptId,
      });

      return { text, usage };
    } catch (error) {
      logger.error('Claude request error', { error });
      throw error;
    }
  }

  /**
   * Convert database messages to Claude format
   */
  messagesToClaudeFormat(messages: Message[]): ClaudeMessage[] {
    return messages
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        role: m.role as 'user' | 'assistant',
        content: m.content,
      }));
  }

  /**
   * Estimate token count (rough approximation)
   * Real counting happens server-side
   */
  estimateTokens(text: string): number {
    // Rough estimate: ~4 chars per token for English
    return Math.ceil(text.length / 4);
  }

  /**
   * Check if request would exceed token budget
   */
  wouldExceedBudget(messages: ClaudeMessage[]): boolean {
    const estimatedInputTokens = messages.reduce(
      (sum, m) => sum + this.estimateTokens(m.content),
      0
    );

    // Leave room for response (max_tokens)
    const totalEstimated = estimatedInputTokens + this.maxTokens;

    // Claude Sonnet 4 context: 200k tokens
    const contextLimit = 200000;

    return totalEstimated > contextLimit;
  }
}

export const claudeService = new ClaudeService();
export default claudeService;