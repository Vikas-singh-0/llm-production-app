import redis from '../infra/redis';
import logger from '../infra/logger';

export interface RateLimitConfig {
  maxTokens: number;      // Maximum tokens in the bucket
  refillRate: number;     // Tokens added per second
  windowSeconds: number;  // Time window for refill
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: Date;
  limit: number;
}

/**
 * Token Bucket Rate Limiter
 * 
 * Algorithm:
 * 1. Each org has a bucket with max tokens
 * 2. Each request consumes 1 token
 * 3. Tokens refill at a constant rate
 * 4. If bucket empty, request is rejected
 * 
 * Example: 100 tokens, refill 10/sec
 * - Can burst up to 100 requests instantly
 * - Sustained rate: 10 req/sec
 * - Bucket refills completely in 10 seconds
 */
export class RateLimiter {
  private config: RateLimitConfig;

  constructor(config: RateLimitConfig) {
    this.config = config;
  }

  /**
   * Check if request is allowed for given org
   */
  async checkLimit(orgId: string): Promise<RateLimitResult> {
    const now = Date.now();
    const key = `ratelimit:${orgId}`;
    const tokensKey = `${key}:tokens`;
    const lastRefillKey = `${key}:lastRefill`;

    try {
      // Get current tokens and last refill time
      const [tokensStr, lastRefillStr] = await Promise.all([
        redis.get(tokensKey),
        redis.get(lastRefillKey),
      ]);

      let tokens = tokensStr ? parseFloat(tokensStr) : this.config.maxTokens;
      let lastRefill = lastRefillStr ? parseInt(lastRefillStr) : now;

      // Calculate tokens to add based on time elapsed
      const timeSinceRefill = (now - lastRefill) / 1000; // seconds
      const tokensToAdd = timeSinceRefill * this.config.refillRate;
      tokens = Math.min(this.config.maxTokens, tokens + tokensToAdd);

      // Try to consume 1 token
      if (tokens >= 1) {
        tokens -= 1;

        // Update Redis
        await Promise.all([
          redis.set(tokensKey, tokens.toString(), this.config.windowSeconds),
          redis.set(lastRefillKey, now.toString(), this.config.windowSeconds),
        ]);

        // Calculate when bucket will be full
        const secondsToFull = (this.config.maxTokens - tokens) / this.config.refillRate;
        const resetAt = new Date(now + secondsToFull * 1000);

        logger.debug('Rate limit check - allowed', {
          orgId,
          tokens: tokens.toFixed(2),
          remaining: Math.floor(tokens),
        });

        return {
          allowed: true,
          remaining: Math.floor(tokens),
          resetAt,
          limit: this.config.maxTokens,
        };
      } else {
        // Not enough tokens - rate limited
        const secondsToRefill = (1 - tokens) / this.config.refillRate;
        const resetAt = new Date(now + secondsToRefill * 1000);

        logger.warn('Rate limit exceeded', {
          orgId,
          tokens: tokens.toFixed(2),
        });

        return {
          allowed: false,
          remaining: 0,
          resetAt,
          limit: this.config.maxTokens,
        };
      }
    } catch (error) {
      logger.error('Rate limiter error', { orgId, error });
      
      // Fail open - allow request if Redis is down
      return {
        allowed: true,
        remaining: this.config.maxTokens,
        resetAt: new Date(now + this.config.windowSeconds * 1000),
        limit: this.config.maxTokens,
      };
    }
  }

  /**
   * Get current rate limit status without consuming a token
   */
  async getStatus(orgId: string): Promise<RateLimitResult> {
    const now = Date.now();
    const key = `ratelimit:${orgId}`;
    const tokensKey = `${key}:tokens`;
    const lastRefillKey = `${key}:lastRefill`;

    try {
      const [tokensStr, lastRefillStr] = await Promise.all([
        redis.get(tokensKey),
        redis.get(lastRefillKey),
      ]);

      let tokens = tokensStr ? parseFloat(tokensStr) : this.config.maxTokens;
      const lastRefill = lastRefillStr ? parseInt(lastRefillStr) : now;

      // Calculate current tokens (without consuming)
      const timeSinceRefill = (now - lastRefill) / 1000;
      const tokensToAdd = timeSinceRefill * this.config.refillRate;
      tokens = Math.min(this.config.maxTokens, tokens + tokensToAdd);

      const secondsToFull = (this.config.maxTokens - tokens) / this.config.refillRate;
      const resetAt = new Date(now + secondsToFull * 1000);

      return {
        allowed: tokens >= 1,
        remaining: Math.floor(tokens),
        resetAt,
        limit: this.config.maxTokens,
      };
    } catch (error) {
      logger.error('Rate limiter status error', { orgId, error });
      return {
        allowed: true,
        remaining: this.config.maxTokens,
        resetAt: new Date(now + this.config.windowSeconds * 1000),
        limit: this.config.maxTokens,
      };
    }
  }

  /**
   * Reset rate limit for an org (admin function)
   */
  async reset(orgId: string): Promise<void> {
    const key = `ratelimit:${orgId}`;
    await Promise.all([
      redis.del(`${key}:tokens`),
      redis.del(`${key}:lastRefill`),
    ]);
    logger.info('Rate limit reset', { orgId });
  }
}

// Default rate limiter instance
// 100 requests burst, refills at 10/second (600/min)
export const defaultRateLimiter = new RateLimiter({
  maxTokens: 20,
  refillRate: 1,      // 10 tokens per second
  windowSeconds: 60,   // 1 minute window
});

export default defaultRateLimiter;