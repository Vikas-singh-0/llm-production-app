import { Response } from 'express';
import logger from '../infra/logger';

export interface StreamOptions {
  requestId: string;
  onToken?: (token: string) => void;
  onComplete?: () => void;
  onError?: (error: Error) => void;
}

/**
 * Streaming Service
 * 
 * Simulates token-by-token streaming for testing infrastructure.
 * Later, this will be replaced with actual LLM streaming.
 */
export class StreamingService {
  /**
   * Stream a response token-by-token using Server-Sent Events
   */
  async streamResponse(
    res: Response,
    text: string,
    options: StreamOptions
  ): Promise<void> {
    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx buffering

    logger.info('Starting stream', {
      requestId: options.requestId,
      textLength: text.length,
    });

    try {
      // Split text into words (simulating tokens)
      const words = text.split(' ');
      let streamedText = '';

      for (let i = 0; i < words.length; i++) {
        const word = words[i];
        const token = i === words.length - 1 ? word : word + ' ';

        // Check if client disconnected
        if (res.writableEnded) {
          logger.warn('Client disconnected during stream', {
            requestId: options.requestId,
            tokensStreamed: i,
            totalTokens: words.length,
          });
          break;
        }

        // Send token as SSE event
        const eventData = JSON.stringify({
          token,
          done: false,
        });
        res.write(`data: ${eventData}\n\n`);

        streamedText += token;

        // Callback
        if (options.onToken) {
          options.onToken(token);
        }

        // Simulate delay between tokens (10-30ms per token)
        // This mimics real LLM streaming latency
        const delay = 10 + Math.random() * 20;
        await this.sleep(delay);
      }

      // Send completion event
      if (!res.writableEnded) {
        const completeEvent = JSON.stringify({
          token: '',
          done: true,
          fullText: streamedText,
        });
        res.write(`data: ${completeEvent}\n\n`);

        logger.info('Stream completed', {
          requestId: options.requestId,
          tokensStreamed: words.length,
          totalLength: streamedText.length,
        });

        if (options.onComplete) {
          options.onComplete();
        }
      }

      res.end();
    } catch (error) {
      logger.error('Stream error', {
        requestId: options.requestId,
        error,
      });

      if (!res.writableEnded) {
        const errorEvent = JSON.stringify({
          error: 'Stream failed',
          message: error instanceof Error ? error.message : 'Unknown error',
        });
        res.write(`data: ${errorEvent}\n\n`);
        res.end();
      }

      if (options.onError && error instanceof Error) {
        options.onError(error);
      }

      throw error;
    }
  }

  /**
   * Stream with abort support
   */
  async streamWithAbort(
    res: Response,
    text: string,
    options: StreamOptions,
    abortSignal?: AbortSignal
  ): Promise<void> {
    // Set up abort handler
    const abortHandler = () => {
      logger.info('Stream aborted by client', {
        requestId: options.requestId,
      });
      if (!res.writableEnded) {
        res.end();
      }
    };

    if (abortSignal) {
      abortSignal.addEventListener('abort', abortHandler);
    }

    // Set up client disconnect detection
    res.on('close', () => {
      logger.info('Client connection closed', {
        requestId: options.requestId,
      });
    });

    try {
      await this.streamResponse(res, text, options);
    } finally {
      if (abortSignal) {
        abortSignal.removeEventListener('abort', abortHandler);
      }
    }
  }

  /**
   * Helper to simulate async delay
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

export const streamingService = new StreamingService();
export default streamingService;