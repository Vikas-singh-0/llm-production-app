import { Application } from 'express';
import { Server } from 'http';
import logger from './infra/logger';
import config from './config/env';
import db from './infra/database';
// import redis from './infra/redis';

export class AppServer {
  private server: Server | null = null;

  constructor(private app: Application) {}

  async start(): Promise<void> {
  const isDbHealthy = await db.healthCheck();

      if (!isDbHealthy) {
    logger.error('Database is not reachable. Server not started.');
    process.exit(1);
  }
    // Connect to Redis before starting server
    // await redis.connect();

    this.server = this.app.listen(config.port, () => {
      logger.info(`Server running`, {
        port: config.port,
        env: config.nodeEnv,
      });
    });

    this.setupGracefulShutdown();
  }

  private setupGracefulShutdown(): void {
    const shutdown = async (signal: string) => {
      logger.info(`${signal} received, starting graceful shutdown`);

      if (this.server) {
        this.server.close(async () => {
          logger.info('HTTP server closed');
          
          // Close database and Redis connections
          await Promise.all([
            db.close(),
            // redis.disconnect(),
          ]);
          
          process.exit(0);
        });

        // Force shutdown after 10 seconds
        setTimeout(() => {
          logger.error('Forced shutdown after timeout');
          process.exit(1);
        }, 10000);
      }
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  }
}

export default AppServer;