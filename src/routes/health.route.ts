import { Request, Response, Router } from 'express';
import config from '../config/env';
import db from '../infra/database';
import redis from '../infra/redis';

const router = Router();

router.get('/health', async (req: Request, res: Response) => {
  // Check database and Redis health
  const [dbHealthy, redisHealthy] = await Promise.all([
    db.healthCheck(),
    redis.healthCheck(),
  ]);

  const allHealthy = dbHealthy && redisHealthy;

  const response: any = {
    status: allHealthy ? 'ok' : 'degraded',
    env: config.nodeEnv,
    timestamp: new Date().toISOString(),
    requestId: req.requestId,
    services: {
      database: dbHealthy ? 'connected' : 'disconnected',
      redis: redisHealthy ? 'connected' : 'disconnected',
    },
  };

  // Include org context if authenticated
  if (req.context) {
    response.org = req.context.orgId;
    response.user = {
      id: req.context.userId,
      email: req.context.email,
      role: req.context.role,
    };
  }

  res.status(allHealthy ? 200 : 503).json(response);
});

export default router;