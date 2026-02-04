import { Application } from 'express';
import { Server } from 'http';
import logger from './infra/logger';
import config from './config/env';

export class AppServer {
  private server: Server | null = null;

  constructor(private app: Application) {}

  start(): void {
    this.server = this.app.listen(config.port, () => {
      logger.info(`Server running`, {
        port: config.port,
        env: config.nodeEnv,
      });
    });

    this.setupGracefulShutdown();
  }

  private setupGracefulShutdown(): void {
    const shutdown = (signal: string) => {
      logger.info(`${signal} received, starting graceful shutdown`);

      if (this.server) {
        this.server.close(() => {
          logger.info('HTTP server closed');
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