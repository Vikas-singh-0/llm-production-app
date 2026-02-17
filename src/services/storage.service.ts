import { writeFile, mkdir, readFile, unlink } from 'fs/promises';
import { join } from 'path';
import { existsSync } from 'fs';
import logger from '../infra/logger';

/**
 * Storage Service
 * 
 * Simple local file storage for development.
 * In production, swap this for S3.
 */
export class StorageService {
  private basePath: string;

  constructor() {
    this.basePath = join(process.cwd(), 'storage', 'documents');
    this.ensureStorageDir();
  }

  private async ensureStorageDir(): Promise<void> {
    try {
      if (!existsSync(this.basePath)) {
        await mkdir(this.basePath, { recursive: true });
        logger.info('Storage directory created', { path: this.basePath });
      }
    } catch (error) {
      logger.error('Failed to create storage directory', { error });
    }
  }

  /**
   * Upload file to storage
   */
  async upload(
    filename: string,
    buffer: Buffer,
    orgId: string
  ): Promise<string> {
    try {
      // Organize by org for multi-tenancy
      const orgPath = join(this.basePath, orgId);
      
      if (!existsSync(orgPath)) {
        await mkdir(orgPath, { recursive: true });
      }

      const filePath = join(orgPath, filename);
      await writeFile(filePath, buffer);

      // Return relative path for storage
      const storagePath = `${orgId}/${filename}`;

      logger.info('File uploaded', {
        filename,
        orgId,
        size: buffer.length,
        path: storagePath,
      });

      return storagePath;
    } catch (error) {
      logger.error('File upload failed', { filename, orgId, error });
      throw error;
    }
  }

  /**
   * Download file from storage
   */
  async download(storagePath: string): Promise<Buffer> {
    try {
      const filePath = join(this.basePath, storagePath);
      const buffer = await readFile(filePath);

      logger.debug('File downloaded', { storagePath, size: buffer.length });

      return buffer;
    } catch (error) {
      logger.error('File download failed', { storagePath, error });
      throw error;
    }
  }

  /**
   * Delete file from storage
   */
  async delete(storagePath: string): Promise<void> {
    try {
      const filePath = join(this.basePath, storagePath);
      await unlink(filePath);

      logger.info('File deleted', { storagePath });
    } catch (error) {
      logger.error('File deletion failed', { storagePath, error });
      throw error;
    }
  }

  /**
   * Check if file exists
   */
  exists(storagePath: string): boolean {
    const filePath = join(this.basePath, storagePath);
    return existsSync(filePath);
  }
}

export const storageService = new StorageService();
export default storageService;