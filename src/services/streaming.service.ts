import { Response } from 'express';
import logger from '../infra/logger';

interface StreamOptions {
  requestId: string;
  onToken?: (token: string) => void;
  onComplete?: () => Promise<void> | void;
  onError?: (error: Error) => void;
}

/**
 * Streaming service for Server-Sent Events (SSE)
 * Handles token-by-token streaming of responses
 */
export const streamingService = {
  /**
   * Stream a response using Server-Sent Events (SSE)
   * @param res Express Response object
   * @param text The full text to stream
   * @param options Streaming options including callbacks
   */
  async streamResponse(
    res: Response,
    text: string,
    options: StreamOptions
  ): Promise<void> {
    const { requestId, onToken, onComplete, onError } = options;

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    // Make sure response isn't compressed
    res.removeHeader('Content-Encoding');

    try {
      // Split text into words/tokens for streaming simulation
      const tokens = text.split(/(\s+)/);
      
      for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        
        // Skip empty tokens
        if (!token || token.trim() === '') {
          continue;
        }

        // Check if this is the last token
        const isLastToken = i === tokens.length - 1;

        // Create SSE data
        const sseData = {
          token: token,
          done: isLastToken,
          ...(isLastToken ? { fullText: text } : {})
        };

        // Send the token
        res.write(`data: ${JSON.stringify(sseData)}\n\n`);

        // Call the onToken callback if provided
        if (onToken) {
          onToken(token);
        }

        // Small delay between tokens to simulate streaming (50ms)
        if (!isLastToken) {
          await new Promise(resolve => setTimeout(resolve, 50));
        }
      }

      // Signal completion
      res.write(`data: ${JSON.stringify({ token: '', done: true, fullText: text })}\n\n`);

      // Call the onComplete callback if provided
      if (onComplete) {
        await onComplete();
      }

      // End the response
      res.end();

      logger.info('Streaming completed', {
        requestId,
        textLength: text.length,
      });

    } catch (error) {
      logger.error('Streaming failed', {
        requestId,
        error,
      });

      // Send error to client if possible
      if (!res.writableEnded) {
        res.write(`data: ${JSON.stringify({ error: 'Streaming error occurred', done: true })}\n\n`);
        res.end();
      }

      // Call the onError callback if provided
      if (onError && error instanceof Error) {
        onError(error);
      }
    }
  },
};
