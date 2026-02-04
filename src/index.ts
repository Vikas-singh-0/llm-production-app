import { createApp } from './app';
import { AppServer } from './server';
import logger from './infra/logger';

async function main() {
  try {
    logger.info('Starting application...');

    const app = createApp();
    const server = new AppServer(app);

    server.start();
  } catch (error) {
    logger.error('Failed to start application', { error });
    process.exit(1);
  }
}

main();