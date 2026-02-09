import { Request, Response, NextFunction } from 'express';
import { defaultRateLimiter } from '../services/rateLimiter.service';
import logger from '../infra/logger';

/**
 * Rate Limiting Middleware
 * 
 * Enforces per-org rate limits using token bucket algorithm.
 * 
 * - Skips /health and /metrics endpoints
 * - Requires authentication (needs req.context.orgId)
 * - Returns 429 when limit exceeded
 * - Adds rate limit headers to all responses
 */
export async function rateLimitMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  // Skip rate limiting for health/metrics
  if (req.path === '/health' || req.path === '/metrics') {
    return next();
  }

  // If no context (unauthenticated), let auth middleware handle it
  if (!req.context || !req.context.orgId) {
    return next();
  }

  try {
    const result = await defaultRateLimiter.checkLimit(req.context.orgId);

    // Set rate limit headers
    res.setHeader('X-RateLimit-Limit', result.limit.toString());
    res.setHeader('X-RateLimit-Remaining', result.remaining.toString());
    res.setHeader('X-RateLimit-Reset', result.resetAt.toISOString());

    if (!result.allowed) {
      // Rate limit exceeded
      logger.warn('Request rate limited', {
        requestId: req.requestId,
        orgId: req.context.orgId,
        userId: req.context.userId,
        path: req.path,
        resetAt: result.resetAt.toISOString(),
      });

      res.status(429).json({
        error: 'Too Many Requests',
        message: 'Rate limit exceeded. Please try again later.',
        limit: result.limit,
        remaining: result.remaining,
        resetAt: result.resetAt.toISOString(),
      });
      return;
    }

    // Request allowed - log for monitoring
    logger.debug('Rate limit check passed', {
      requestId: req.requestId,
      orgId: req.context.orgId,
      remaining: result.remaining,
    });

    next();
  } catch (error) {
    // On error, fail open (allow request) but log the issue
    logger.error('Rate limit middleware error', {
      requestId: req.requestId,
      orgId: req.context?.orgId,
      error,
    });
    next();
  }
}

export default rateLimitMiddleware;