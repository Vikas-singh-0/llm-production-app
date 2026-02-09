import { createClient, RedisClientType } from 'redis';
import config from '../config/env';
import logger from './logger';

class RedisClient {
  private client: RedisClientType;
  private isConnected: boolean = false;

  constructor() {
    this.client = createClient({
      url: config.redis.url,
      password: config.redis.password,
    });

    this.client.on('connect', () => {
      logger.info('Redis connection established');
      this.isConnected = true;
    });

    this.client.on('error', (err) => {
      logger.error('Redis error', { error: err });
      this.isConnected = false;
    });

    this.client.on('ready', () => {
      logger.info('Redis client ready');
    });

    this.client.on('reconnecting', () => {
      logger.warn('Redis reconnecting...');
    });
  }

  async connect(): Promise<void> {
    if (!this.isConnected) {
      await this.client.connect();
    }
  }

  async disconnect(): Promise<void> {
    if (this.isConnected) {
      await this.client.quit();
      this.isConnected = false;
      logger.info('Redis connection closed');
    }
  }

  async healthCheck(): Promise<boolean> {
    try {
      const result = await this.client.ping();
      return result === 'PONG';
    } catch (error) {
      logger.error('Redis health check failed', { error });
      return false;
    }
  }

  /**
   * Get value from Redis
   */
  async get(key: string): Promise<string | null> {
    try {
      return await this.client.get(key);
    } catch (error) {
      logger.error('Redis GET error', { key, error });
      throw error;
    }
  }

  /**
   * Set value in Redis with optional expiration
   */
  async set(key: string, value: string, expirySeconds?: number): Promise<void> {
    try {
      if (expirySeconds) {
        await this.client.setEx(key, expirySeconds, value);
      } else {
        await this.client.set(key, value);
      }
    } catch (error) {
      logger.error('Redis SET error', { key, error });
      throw error;
    }
  }

  /**
   * Increment a key (creates if doesn't exist)
   */
  async incr(key: string): Promise<number> {
    try {
      return await this.client.incr(key);
    } catch (error) {
      logger.error('Redis INCR error', { key, error });
      throw error;
    }
  }

  /**
   * Decrement a key
   */
  async decr(key: string): Promise<number> {
    try {
      return await this.client.decr(key);
    } catch (error) {
      logger.error('Redis DECR error', { key, error });
      throw error;
    }
  }

  /**
   * Set expiration on a key
   */
  async expire(key: string, seconds: number): Promise<boolean> {
    try {
      return await this.client.expire(key, seconds);
    } catch (error) {
      logger.error('Redis EXPIRE error', { key, error });
      throw error;
    }
  }

  /**
   * Delete a key
   */
  async del(key: string): Promise<number> {
    try {
      return await this.client.del(key);
    } catch (error) {
      logger.error('Redis DEL error', { key, error });
      throw error;
    }
  }

  /**
   * Get TTL of a key
   */
  async ttl(key: string): Promise<number> {
    try {
      return await this.client.ttl(key);
    } catch (error) {
      logger.error('Redis TTL error', { key, error });
      throw error;
    }
  }

  getClient(): RedisClientType {
    return this.client;
  }
}

export const redis = new RedisClient();
export default redis;