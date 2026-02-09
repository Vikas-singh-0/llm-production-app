import { Pool, PoolClient, QueryResult } from 'pg';
import config from '../config/env';
import logger from './logger';

class Database {
  private pool: Pool;

  constructor() {
    this.pool = new Pool({
      connectionString: config.database.url,
      min: config.database.poolMin,
      max: config.database.poolMax,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    this.pool.on('connect', () => {
      logger.info('Database connection established');
    });

    this.pool.on('error', (err) => {
      logger.error('Unexpected database error', { error: err });
    });
  }

  async query<T extends QueryResult = any>(text: string, params?: any[]): Promise<QueryResult<T>> {
    const start = Date.now();
    try {
      const result = await this.pool.query<T>(text, params);
      const duration = Date.now() - start;
      logger.debug('Query executed', {
        query: text,
        duration: `${duration}ms`,
        rows: result.rowCount,
      });
      return result;
    } catch (error) {
      logger.error('Query error', {
        query: text,
        error,
      });
      throw error;
    }
  }

  async getClient(): Promise<PoolClient> {
    return this.pool.connect();
  }

  async healthCheck(): Promise<boolean> {
    try {
      await this.query('SELECT 1');
      return true;
    } catch (error) {
      logger.error('Database health check failed', { error });
      return false;
    }
  }

  async close(): Promise<void> {
    await this.pool.end();
    logger.info('Database connection pool closed');
  }
}

export const db = new Database();
export default db;