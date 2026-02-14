import Anthropic from '@anthropic-ai/sdk';
import config from '../config/env';
import logger from '../infra/logger';
import { Message } from '../models/message.modal';

export interface ClaudeMessage {
  role: 'user' | 'assistant';
  content: string;
}

export interface ClaudeStreamOptions {
  requestId: string;
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
   * Stream a chat completion
   */
  async streamChat(
    messages: ClaudeMessage[],
    options: ClaudeStreamOptions
  ): Promise<void> {
    try {
      logger.info('Starting Claude stream', {
        requestId: options.requestId,
        messageCount: messages.length,
        model: this.model,
        maxTokens: this.maxTokens,
      });

      // Convert to Anthropic format
      const anthropicMessages = messages.map(m => ({
        role: m.role,
        content: m.content,
      }));

      // Create streaming request
      const stream = await this.client.messages.stream({
        model: this.model,
        max_tokens: this.maxTokens,
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

      logger.info('Claude stream completed', {
        requestId: options.requestId,
        inputTokens,
        outputTokens,
        totalTokens: usage.totalTokens,
        responseLength: fullText.length,
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
   * Non-streaming chat completion
   */
  async chat(messages: ClaudeMessage[]): Promise<{ 
    text: string; 
    usage: TokenUsage;
  }> {
    try {
      logger.info('Starting Claude request', {
        messageCount: messages.length,
        model: this.model,
      });

      const anthropicMessages = messages.map(m => ({
        role: m.role,
        content: m.content,
      }));

      const response = await this.client.messages.create({
        model: this.model,
        max_tokens: this.maxTokens,
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

      logger.info('Claude request completed', {
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        totalTokens: usage.totalTokens,
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