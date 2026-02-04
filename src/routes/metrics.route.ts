import { Request, Response, Router } from 'express';
import metricsService from '../infra/metricsService';

const router = Router();

router.get('/metrics', async (req: Request, res: Response) => {
  try {
    res.set('Content-Type', metricsService.registry.contentType);
    const metrics = await metricsService.getMetrics();
    res.send(metrics);
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate metrics' });
  }
});

export default router;