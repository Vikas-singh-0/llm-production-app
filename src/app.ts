import rootRoute from './routes/root.route';
import express, { Application } from 'express';
import healthRoute from './routes/health.route';
import metricsRoute from './routes/metrics.route';
import chatRoute from './routes/chat.route';
import promptRoute from './routes/prompt.route';
import documentRoute from './routes/document.route';
import ragChatRoute from './routes/ragChat.route';
import requestIdMiddleware from './middleware/requestid.middleware';
import metricsMiddleware from './middleware/metrics.middleware';
import fakeAuthMiddleware from './middleware/fakeAuth.middleware';
import rateLimitMiddleware from './middleware/rateLimit.middleware';
import corsMiddleware from './middleware/cors.middleware';

export function createApp(): Application {
  const app = express();

  // Middleware
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // add cors middleware at the start
  app.use(corsMiddleware);

  // Request ID tracking (must be first)
  app.use(requestIdMiddleware);

  // Metrics and logging middleware
  app.use(metricsMiddleware);

  // Fake auth middleware (sets req.context with org_id, user_id, role)
  app.use(fakeAuthMiddleware);

  // Rate limiting (per-org token bucket)
  app.use(rateLimitMiddleware);

  // Routes
  app.use(rootRoute);
  app.use(healthRoute);
  app.use(metricsRoute);
  app.use(chatRoute);
  app.use(promptRoute);
  app.use(documentRoute);
  app.use(ragChatRoute);

  return app;
}

export default createApp;