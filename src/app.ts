import rootRoute from './routes/root.route';
import express, { Application } from "express";
import healthRoute from "./routes/health.route";
import metricsRoute from "./routes/metrics.route";
import chatRoute from "./routes/chat.route";
import requestIdMiddleware from "./middleware/requestid.middleware";
import metricsMiddleware from "./middleware/metrics.middleware";
import fakeAuthMiddleware from "./middleware/fakeAuth.middleware";
import rateLimitMiddleware from "./middleware/rateLimit.middleware";

export function createApp(): Application {
  const app = express();

  // Middleware
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

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

  return app;
}

export default createApp;
