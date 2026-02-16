import redis from '../infra/redis';
import logger from '../infra/logger';
import { Message } from '../models/message.model';
import { SummaryModel, Summary } from '../models/summary.model';
import { GeminiMessage } from './gemini.service';
import { llmFactory } from './llm.factory';
import config from '../config/env';

export interface MemoryWindow {
  messages: Message[];
  summary: Summary | null;
  totalTokens: number;
  truncated: boolean;
}

/**
 * Memory Service
 * 
 * Manages conversation context with token limits:
 * - Sliding window (recent N messages)
 * - Token budget enforcement
 * - Redis caching for fast retrieval
 * - Automatic summarization for long conversations
 */
export class MemoryService {
  private maxContextTokens: number;
  private summaryTokenBudget: number;

  constructor() {
    // Reserve tokens for response
    this.maxContextTokens = 8000;  // Safe limit for context
    this.summaryTokenBudget = 500; // Reserve for summary
  }

  /**
   * Get messages within token budget (sliding window)
   * Now includes summary if available
   */
  async getContextWindow(
    messages: Message[],
    chatId: string,
    maxTokens?: number
  ): Promise<MemoryWindow> {
    const limit = maxTokens || this.maxContextTokens;
    
    // Check if we have a summary
    const summary = await SummaryModel.getLatest(chatId);
    
    // If summary exists, reserve space for it
    const availableTokens = summary 
      ? limit - (summary.summary_tokens || 0)
      : limit;
    
    // Start from most recent and work backwards
    const recentMessages: Message[] = [];
    let totalTokens = 0;
    let truncated = false;

    // Always include the most recent user message
    if (messages.length > 0) {
      const lastMessage = messages[messages.length - 1];
      recentMessages.unshift(lastMessage);
      totalTokens += lastMessage.token_count || this.estimateTokens(lastMessage.content);
    }

    // Add earlier messages until we hit token limit
    for (let i = messages.length - 2; i >= 0; i--) {
      const message = messages[i];
      const messageTokens = message.token_count || this.estimateTokens(message.content);

      if (totalTokens + messageTokens > availableTokens) {
        truncated = true;
        logger.debug('Context window truncated', {
          totalMessages: messages.length,
          includedMessages: recentMessages.length,
          totalTokens,
          availableTokens,
          hasSummary: !!summary,
        });
        break;
      }

      recentMessages.unshift(message);
      totalTokens += messageTokens;
    }

    // Add summary tokens to total
    if (summary) {
      totalTokens += summary.summary_tokens;
    }

    logger.debug('Context window built', {
      totalMessages: messages.length,
      windowSize: recentMessages.length,
      totalTokens,
      truncated,
      hasSummary: !!summary,
      summaryTokens: summary?.summary_tokens || 0,
    });

    return {
      messages: recentMessages,
      summary,
      totalTokens,
      truncated,
    };
  }

  /**
   * Generate summary of conversation using gemini
   */
  async summarizeConversation(
    messages: Message[],
    chatId: string
  ): Promise<Summary> {
    try {
      logger.info('Starting conversation summarization', {
        chatId,
        messageCount: messages.length,
      });

      // Format messages for summarization
      const conversationText = messages
        .map(m => `${m.role.toUpperCase()}: ${m.content}`)
        .join('\n\n');

      // Calculate original tokens
      const originalTokens = messages.reduce(
        (sum, m) => sum + (m.token_count || this.estimateTokens(m.content)),
        0
      );

      // Use LLM factory to generate summary (supports local and external providers)
      const provider = llmFactory.getProvider();
      const result = await provider.chat(
        [{ role: 'user', content: `Please provide a concise summary of this conversation, focusing on the main topics discussed, key decisions made, and important context. Keep it brief but comprehensive. Conversation:
${conversationText} Summary:` }], 'summarization'
      );

      const summaryContent = result.text;
      const summaryTokens = result.usage.outputTokens;

      // Store summary in database
      const summary = await SummaryModel.create({
        chat_id: chatId,
        content: summaryContent,
        start_message_id: messages[0]?.id,
        end_message_id: messages[messages.length - 1]?.id,
        message_count: messages.length,
        original_tokens: originalTokens,
        summary_tokens: summaryTokens,
      });

      const compressionRatio = originalTokens / summaryTokens;

      logger.info('Summarization completed', {
        chatId,
        messageCount: messages.length,
        originalTokens,
        summaryTokens,
        compressionRatio: compressionRatio.toFixed(2),
        tokensSaved: originalTokens - summaryTokens,
      });

      return summary;
    } catch (error) {
      logger.error('Summarization failed', {
        chatId,
        error,
      });
      throw error;
    }
  }

  /**
   * Check if conversation needs summarization
   */
  shouldSummarize(messages: Message[], existingSummary?: Summary | null): boolean {
    // Don't re-summarize if we just did
    if (existingSummary) {
      const timeSinceLastSummary = Date.now() - new Date(existingSummary.created_at).getTime();
      const hoursSince = timeSinceLastSummary / (1000 * 60 * 60);
      
      // Only re-summarize if more than 24 hours and 20+ new messages
      if (hoursSince < 24 || messages.length < 20) {
        return false;
      }
    }

    // Summarize if more than 50 messages
    if (messages.length > 5) {
      return true;
    }

    // Or if total tokens exceed threshold
    const totalTokens = messages.reduce(
      (sum, m) => sum + (m.token_count || this.estimateTokens(m.content)),
      0
    );

    return totalTokens > 1500;  // Well over context window
  }

  /**
   * Cache recent messages in Redis for fast access
   */
  async cacheRecentMessages(chatId: string, messages: Message[]): Promise<void> {
    try {
      const key = `chat:${chatId}:recent`;
      const value = JSON.stringify(messages);
      
      // Cache for 1 hour
      await redis.set(key, value, 3600);
      
      logger.debug('Messages cached', {
        chatId,
        messageCount: messages.length,
      });
    } catch (error) {
      logger.error('Failed to cache messages', {
        chatId,
        error,
      });
      // Non-critical, continue without cache
    }
  }

  /**
   * Get cached messages from Redis
   */
  async getCachedMessages(chatId: string): Promise<Message[] | null> {
    try {
      const key = `chat:${chatId}:recent`;
      const value = await redis.get(key);
      
      if (!value) {
        return null;
      }

      const messages = JSON.parse(value) as Message[];
      
      logger.debug('Messages retrieved from cache', {
        chatId,
        messageCount: messages.length,
      });

      return messages;
    } catch (error) {
      logger.error('Failed to get cached messages', {
        chatId,
        error,
      });
      return null;
    }
  }

  /**
   * Invalidate cache when new message added
   */
  async invalidateCache(chatId: string): Promise<void> {
    try {
      const key = `chat:${chatId}:recent`;
      await redis.del(key);
      
      logger.debug('Cache invalidated', { chatId });
    } catch (error) {
      logger.error('Failed to invalidate cache', {
        chatId,
        error,
      });
    }
  }

  /**
   * Estimate tokens (rough approximation)
   */
  private estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  /**
   * Get memory stats for monitoring
   */
  async getMemoryStats(chatId: string, messages: Message[]): Promise<{
    totalMessages: number;
    totalTokens: number;
    oldestMessage: Date | null;
    newestMessage: Date | null;
  }> {
    const totalTokens = messages.reduce(
      (sum, m) => sum + (m.token_count || this.estimateTokens(m.content)),
      0
    );

    return {
      totalMessages: messages.length,
      totalTokens,
      oldestMessage: messages[0]?.created_at || null,
      newestMessage: messages[messages.length - 1]?.created_at || null,
    };
  }

  /**
   * Format messages for gemini (with summary prepended)
   */
  formatForContext(messages: Message[], summary?: Summary | null): GeminiMessage[] {
    const geminiMessages: GeminiMessage[] = [];

    // If summary exists, add it as system context at the beginning
    if (summary) {
      geminiMessages.push({
        role: 'user',
        content: `[Previous conversation summary: ${summary.content}]`,
      });
      
      geminiMessages.push({
        role: 'assistant',
        content: 'I understand. I\'ll keep this context in mind.',
      });
    }

    // Add recent messages
    const recentMessages = messages
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        role: m.role as 'user' | 'assistant',
        content: m.content,
      }));

    geminiMessages.push(...recentMessages);

    return geminiMessages;
  }

  /**
   * Format messages for the current LLM provider (with summary prepended)
   * Returns the appropriate format based on the configured provider
   */
  formatMessagesForProvider(messages: Message[], summary?: Summary | null): any[] {
    const providerName = llmFactory.getProviderName();
    
    // For now, we use a common format that works with all providers
    // Each provider service will convert to its specific format
    const chatMessages: { role: 'user' | 'assistant' | 'system'; content: string }[] = [];

    // If summary exists, add it as system context at the beginning
    if (summary) {
      chatMessages.push({
        role: 'system',
        content: `[Previous conversation summary: ${summary.content}]`,
      });
    }

    // Add recent messages
    const recentMessages = messages
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .map(m => ({
        role: m.role as 'user' | 'assistant',
        content: m.content,
      }));

    chatMessages.push(...recentMessages);

    return chatMessages;
  }

}

export const memoryService = new MemoryService();
export default memoryService;