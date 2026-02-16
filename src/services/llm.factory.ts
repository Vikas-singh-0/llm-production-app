import config, { LLMProvider } from '../config/env';
import { geminiService, GeminiMessage, TokenUsage as GeminiTokenUsage } from './gemini.service';
import { claudeService, ClaudeMessage, TokenUsage as ClaudeTokenUsage } from './claude.service';
import { getOllamaService, OllamaMessage, TokenUsage as OllamaTokenUsage } from './ollama.service';
import logger from '../infra/logger';

/**
 * Unified interface for all LLM services
 * This allows switching between providers without changing the rest of the code
 */
export interface LLMService {
  streamChat(
    messages: any[],
    options: {
      requestId: string;
      promptName?: string;
      onToken?: (token: string) => void;
      onComplete?: (fullText: string, usage: any) => void;
      onError?: (error: Error) => void;
    }
  ): Promise<void>;

  chat(
    messages: any[],
    promptName?: string
  ): Promise<{ text: string; usage: any }>;

  estimateTokens(text: string): number;

  wouldExceedBudget(messages: any[]): boolean;
}

/**
 * Token usage types
 */
export type TokenUsage = GeminiTokenUsage | ClaudeTokenUsage | OllamaTokenUsage;

/**
 * LLM Factory
 * 
 * Provides a unified interface for all LLM providers:
 * - Local: Ollama (default)
 * - External: Gemini, Claude
 * 
 * Allows easy switching between providers via config
 */
class LLMFactory {
  private currentProvider: LLMProvider;
  private fallbackProvider: LLMProvider | null = null;

  constructor() {
    this.currentProvider = this.determineProvider();
    
    // Set fallback provider if configured
    if (config.defaultProvider === 'local' && !config.local.enabled) {
      // If local is default but not enabled, try gemini as fallback
      if (config.gemini.apiKey && config.gemini.apiKey !== 'YOUR_API_KEY') {
        this.fallbackProvider = 'gemini';
        logger.info('Local LLM not enabled, using Gemini as fallback');
      } else if (config.claude.apiKey && config.claude.apiKey !== 'YOUR_API_KEY') {
        this.fallbackProvider = 'claude';
        logger.info('Local LLM not enabled, using Claude as fallback');
      }
    }

    logger.info('LLM Factory initialized', {
      currentProvider: this.currentProvider,
      fallbackProvider: this.fallbackProvider,
      localEnabled: config.local.enabled,
    });
  }

  /**
   * Determine which provider to use based on config
   */
  private determineProvider(): LLMProvider {
    // Check if local is enabled and configured
    if (config.local.enabled) {
      return 'local';
    }

    // Check if default provider is configured
    if (config.defaultProvider) {
      return config.defaultProvider;
    }

    // Fallback to gemini if no valid provider configured
    return 'gemini';
  }

  /**
   * Get the current LLM service
   */
  getProvider(): LLMService {
    switch (this.currentProvider) {
      case 'local':
        return getOllamaService();
      case 'gemini':
        return geminiService;
      case 'claude':
        return claudeService;
      default:
        logger.warn('Unknown provider, falling back to Gemini');
        return geminiService;
    }
  }

  /**
   * Get the current provider name
   */
  getProviderName(): LLMProvider {
    return this.currentProvider;
  }

  /**
   * Get the fallback provider (if configured)
   */
  getFallbackProvider(): LLMService | null {
    if (!this.fallbackProvider) {
      return null;
    }

    switch (this.fallbackProvider) {
      case 'local':
        return getOllamaService();
      case 'gemini':
        return geminiService;
      case 'claude':
        return claudeService;
      default:
        return null;
    }
  }

  /**
   * Check if fallback is available
   */
  hasFallback(): boolean {
    return this.fallbackProvider !== null;
  }

  /**
   * Execute a request with automatic fallback
   * If primary fails, tries fallback provider
   */
  async chatWithFallback(
    messages: any[],
    promptName?: string
  ): Promise<{ text: string; usage: TokenUsage; provider: LLMProvider }> {
    try {
      const provider = this.getProvider();
      const result = await provider.chat(messages, promptName);
      
      return {
        text: result.text,
        usage: result.usage,
        provider: this.currentProvider,
      };
    } catch (error) {
      logger.error('Primary LLM provider failed, trying fallback', {
        primaryProvider: this.currentProvider,
        fallbackProvider: this.fallbackProvider,
        error: error instanceof Error ? error.message : String(error),
      });

      const fallback = this.getFallbackProvider();
      if (fallback) {
        try {
          const result = await fallback.chat(messages, promptName);
          
          logger.info('Fallback provider succeeded', {
            fallbackProvider: this.fallbackProvider,
          });

          return {
            text: result.text,
            usage: result.usage,
            provider: this.fallbackProvider!,
          };
        } catch (fallbackError) {
          logger.error('Fallback provider also failed', {
            fallbackProvider: this.fallbackProvider,
            error: fallbackError instanceof Error ? fallbackError.message : String(fallbackError),
          });
        }
      }

      // If all providers failed, throw the original error
      throw error;
    }
  }

  /**
   * Stream with automatic fallback
   */
  async streamChatWithFallback(
    messages: any[],
    options: {
      requestId: string;
      promptName?: string;
      onToken?: (token: string) => void;
      onComplete?: (fullText: string, usage: TokenUsage, provider: LLMProvider) => void;
      onError?: (error: Error) => void;
    }
  ): Promise<void> {
    const primaryProvider = this.getProvider();

    try {
      await primaryProvider.streamChat(messages, {
        ...options,
        onComplete: options.onComplete 
          ? (text, usage) => options.onComplete!(text, usage, this.currentProvider)
          : undefined,
      });
    } catch (error) {
      logger.error('Primary LLM stream failed, trying fallback', {
        primaryProvider: this.currentProvider,
        fallbackProvider: this.fallbackProvider,
        error: error instanceof Error ? error.message : String(error),
      });

      const fallback = this.getFallbackProvider();
      if (fallback) {
        try {
          await fallback.streamChat(messages, {
            ...options,
            onComplete: options.onComplete
              ? (text, usage) => options.onComplete!(text, usage, this.fallbackProvider!)
              : undefined,
          });

          logger.info('Fallback stream provider succeeded', {
            fallbackProvider: this.fallbackProvider,
          });
          return;
        } catch (fallbackError) {
          logger.error('Fallback stream provider also failed', {
            fallbackProvider: this.fallbackProvider,
            error: fallbackError instanceof Error ? fallbackError.message : String(fallbackError),
          });
        }
      }

      // If all providers failed, call the error handler
      if (options.onError && error instanceof Error) {
        options.onError(error);
      }
      throw error;
    }
  }

  /**
   * Check if local LLM is available
   */
  async checkLocalHealth(): Promise<boolean> {
    try {
      const ollama = getOllamaService();
      return await ollama.checkHealth();
    } catch {
      return false;
    }
  }

  /**
   * Get available local models
   */
  async getLocalModels(): Promise<string[]> {
    try {
      const ollama = getOllamaService();
      return await ollama.getAvailableModels();
    } catch {
      return [];
    }
  }

  /**
   * Switch provider dynamically (for admin/debugging)
   */
  setProvider(provider: LLMProvider): void {
    this.currentProvider = provider;
    logger.info('LLM provider switched', { provider });
  }
}

// Export singleton instance
export const llmFactory = new LLMFactory();
export default llmFactory;
