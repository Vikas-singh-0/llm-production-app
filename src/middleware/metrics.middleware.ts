import { Request, Response, NextFunction } from 'express';
import metricsService from '../infra/metricsService';
import logger from '../infra/logger';

export function metricsMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const start = Date.now();
  const route = req.route?.path || req.path;

  // Track request start
  metricsService.startRequest(req.method, route);

  // Track request completion
  res.on('finish', () => {
    const duration = Date.now() - start;
    
    metricsService.recordRequest(
      req.method,
      route,
      res.statusCode,
      duration
    );

    metricsService.endRequest(req.method, route);

    logger.info('HTTP Request', {
      requestId: req.requestId,
      method: req.method,
      url: req.url,
      route,
      status: res.statusCode,
      duration: `${duration}ms`,
      userAgent: req.headers['user-agent'],
    });
  });

  next();
}

export default metricsMiddleware;