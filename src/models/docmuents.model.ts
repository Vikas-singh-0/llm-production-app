import db from '../infra/database';

export interface Document {
  id: string;
  org_id: string;
  user_id: string;
  filename: string;
  original_filename: string;
  mime_type: string;
  file_size: number;
  storage_path: string;
  storage_type: string;
  status: 'uploaded' | 'processing' | 'parsed' | 'failed';
  error_message: string | null;
  page_count: number | null;
  parsed_at: Date | null;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
  metadata: Record<string, any>;
}

export class DocumentModel {
  static async findById(id: string, orgId: string): Promise<Document | null> {
    const result = await db.query<Document>(
      `SELECT * FROM documents 
       WHERE id = $1 AND org_id = $2 AND deleted_at IS NULL`,
      [id, orgId]
    );
    return result.rows[0] || null;
  }

  static async findByOrgId(orgId: string, limit: number = 50): Promise<Document[]> {
    const result = await db.query<Document>(
      `SELECT * FROM documents 
       WHERE org_id = $1 AND deleted_at IS NULL 
       ORDER BY created_at DESC 
       LIMIT $2`,
      [orgId, limit]
    );
    return result.rows;
  }

  static async findByUserId(userId: string, orgId: string, limit: number = 50): Promise<Document[]> {
    const result = await db.query<Document>(
      `SELECT * FROM documents 
       WHERE user_id = $1 AND org_id = $2 AND deleted_at IS NULL 
       ORDER BY created_at DESC 
       LIMIT $3`,
      [userId, orgId, limit]
    );
    return result.rows;
  }

  static async create(data: {
    org_id: string;
    user_id: string;
    filename: string;
    original_filename: string;
    mime_type: string;
    file_size: number;
    storage_path: string;
    storage_type?: string;
    metadata?: Record<string, any>;
  }): Promise<Document> {
    const result = await db.query<Document>(
      `INSERT INTO documents (
        org_id, user_id, filename, original_filename, 
        mime_type, file_size, storage_path, storage_type, metadata
      )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [
        data.org_id,
        data.user_id,
        data.filename,
        data.original_filename,
        data.mime_type,
        data.file_size,
        data.storage_path,
        data.storage_type || 's3',
        data.metadata || {},
      ]
    );
    return result.rows[0];
  }

  static async updateStatus(
    id: string,
    status: Document['status'],
    errorMessage?: string
  ): Promise<Document | null> {
    const result = await db.query<Document>(
      `UPDATE documents 
       SET status = $1, error_message = $2, updated_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [status, errorMessage || null, id]
    );
    return result.rows[0] || null;
  }

  static async markParsed(
    id: string,
    pageCount: number
  ): Promise<Document | null> {
    const result = await db.query<Document>(
      `UPDATE documents 
       SET status = 'parsed', page_count = $1, parsed_at = NOW(), updated_at = NOW()
       WHERE id = $2
       RETURNING *`,
      [pageCount, id]
    );
    return result.rows[0] || null;
  }

  static async delete(id: string, orgId: string): Promise<boolean> {
    const result = await db.query(
      `UPDATE documents 
       SET deleted_at = NOW()
       WHERE id = $1 AND org_id = $2 AND deleted_at IS NULL`,
      [id, orgId]
    );
    return result.rowCount ? result.rowCount > 0 : false;
  }
}

export default DocumentModel;