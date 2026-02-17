import { createApp } from './app';
import { AppServer } from './server';
import { vectorStoreService } from './services/vectorStore.service';
import logger from './infra/logger';

async function main() {
  try {
    logger.info('Starting application...');

    // Initialize vector store
    await vectorStoreService.initializeCollection();

    const app = createApp();
    const server = new AppServer(app);

    await server.start();
  } catch (error) {
    logger.error('Failed to start application', { error });
    process.exit(1);
  }
}

main();