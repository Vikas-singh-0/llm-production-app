import { Request, Response, Router } from 'express';
import { defaultRateLimiter } from '../services/rateLimiter.service';

const router = Router();

router.get('/', async (req: Request, res: Response) => {
  const response: any = {
    message: 'Welcome to the LLM Production App',
    timestamp: new Date().toISOString(),
    requestId: req.requestId,
  };

  // Include org context if authenticated
  if (req.context) {
    response.org = req.context.orgId;
    response.user = {
      id: req.context.userId,
      email: req.context.email,
      role: req.context.role,
    };

    // Include rate limit status
    try {
      const rateLimitStatus = await defaultRateLimiter.getStatus(req.context.orgId);
      response.rateLimit = {
        limit: rateLimitStatus.limit,
        remaining: rateLimitStatus.remaining,
        resetAt: rateLimitStatus.resetAt.toISOString(),
      };
    } catch (error) {
      // If rate limiter fails, don't include it
      console.error('Failed to get rate limit status:', error);
    }
  }

  return res.status(200).json(response);
});

export default router;
