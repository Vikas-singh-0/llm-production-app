import { Queue, Worker, Job } from 'bullmq';
import { Redis } from 'ioredis';
import config from '../config/env';
import logger from '../infra/logger';
import { pdfParserService } from './pdfParser.service';

// Create Redis connection for BullMQ
const connection = new Redis(config.redis.url, {
  maxRetriesPerRequest: null,
});

// Job types
interface ParseDocumentJob {
  documentId: string;
  orgId: string;
}

/**
 * Document Processing Queue
 * 
 * Handles async PDF parsing in the background
 */
export class DocumentQueue {
  private queue: Queue<ParseDocumentJob>;
  private worker: Worker<ParseDocumentJob>;

  constructor() {
    // Create queue
    this.queue = new Queue<ParseDocumentJob>('document-processing', {
      connection,
      defaultJobOptions: {
        attempts: 3,
        backoff: {
          type: 'exponential',
          delay: 2000,
        },
        removeOnComplete: {
          age: 24 * 3600, // Keep completed jobs for 24 hours
          count: 1000,
        },
        removeOnFail: {
          age: 7 * 24 * 3600, // Keep failed jobs for 7 days
        },
      },
    });

    // Create worker to process jobs
    this.worker = new Worker<ParseDocumentJob>(
      'document-processing',
      async (job: Job<ParseDocumentJob>) => {
        logger.info('Processing document job', {
          jobId: job.id,
          documentId: job.data.documentId,
        });

        try {
          await pdfParserService.processDocument(job.data.documentId);
          
          logger.info('Document job completed', {
            jobId: job.id,
            documentId: job.data.documentId,
          });

          return { success: true };
        } catch (error) {
          logger.error('Document job failed', {
            jobId: job.id,
            documentId: job.data.documentId,
            error,
          });
          throw error;
        }
      },
      {
        connection,
        concurrency: 2, // Process 2 documents at a time
      }
    );

    // Worker event handlers
    this.worker.on('completed', (job) => {
      logger.info('Job completed', { jobId: job.id });
    });

    this.worker.on('failed', (job, err) => {
      logger.error('Job failed', {
        jobId: job?.id,
        error: err,
      });
    });

    logger.info('Document processing queue initialized');
  }

  /**
   * Add document to processing queue
   */
  async addDocument(documentId: string, orgId: string): Promise<string> {
    const job = await this.queue.add(
      'parse-pdf',
      { documentId, orgId },
      {
        jobId: `doc-${documentId}`, // Prevent duplicate jobs
      }
    );

    logger.info('Document queued for processing', {
      jobId: job.id,
      documentId,
    });

    return job.id!;
  }

  /**
   * Get job status
   */
  async getJobStatus(jobId: string): Promise<{
    status: string;
    progress?: number;
    error?: string;
  }> {
    const job = await this.queue.getJob(jobId);
    
    if (!job) {
      return { status: 'not_found' };
    }

    const state = await job.getState();
    
    return {
      status: state,
      progress: job.progress as number | undefined,
      error: job.failedReason,
    };
  }

  /**
   * Close queue and worker
   */
  async close(): Promise<void> {
    await this.worker.close();
    await this.queue.close();
    logger.info('Document processing queue closed');
  }
}

export const documentQueue = new DocumentQueue();
export default documentQueue;