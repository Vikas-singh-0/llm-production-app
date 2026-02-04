import { Request, Response, Router } from 'express';
import config from '../config/env';

const router = Router();

router.get('/health', (req: Request, res: Response) => {
  res.status(200).json({
    status: 'ok',
    env: config.nodeEnv,
    timestamp: new Date().toISOString(),
    requestId: req.requestId,
  });
});

export default router;