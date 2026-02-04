import express, { Application } from 'express';
import healthRoute from './routes/health.route';
import metricsRoute from './routes/metrics.route'
import requestIdMiddleware from './middleware/requestid.middleware';
import metricsMiddleware from './middleware/metrics.middleware';

export function createApp(): Application {
  const app = express();

  // Middleware
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // Request ID tracking (must be first)
  app.use(requestIdMiddleware);

  // Metrics and logging middleware
  app.use(metricsMiddleware);

  // Routes
  app.use(healthRoute);
  app.use(metricsRoute);

  return app;
}

export default createApp;