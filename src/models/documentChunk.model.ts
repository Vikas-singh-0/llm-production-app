import db from '../infra/database';

export interface DocumentChunk {
  id: string;
  document_id: string;
  content: string;
  page_number: number | null;
  chunk_index: number;
  char_count: number;
  token_count: number | null;
  created_at: Date;
  metadata: Record<string, any>;
}

export class DocumentChunkModel {
  static async findByDocumentId(documentId: string): Promise<DocumentChunk[]> {
    const result = await db.query<DocumentChunk>(
      `SELECT * FROM document_chunks 
       WHERE document_id = $1 
       ORDER BY chunk_index ASC`,
      [documentId]
    );
    return result.rows;
  }

  static async create(data: {
    document_id: string;
    content: string;
    page_number?: number;
    chunk_index: number;
    token_count?: number;
    metadata?: Record<string, any>;
  }): Promise<DocumentChunk> {
    const result = await db.query<DocumentChunk>(
      `INSERT INTO document_chunks (
        document_id, content, page_number, chunk_index,
        char_count, token_count, metadata
      )
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        data.document_id,
        data.content,
        data.page_number || null,
        data.chunk_index,
        data.content.length,
        data.token_count || null,
        data.metadata || {},
      ]
    );
    return result.rows[0];
  }

  static async bulkCreate(
    chunks: Array<{
      document_id: string;
      content: string;
      page_number?: number;
      chunk_index: number;
      token_count?: number;
    }>
  ): Promise<void> {
    if (chunks.length === 0) return;

    const values = chunks.map((chunk, idx) => {
      const offset = idx * 6;
      return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6})`;
    }).join(', ');

    const params = chunks.flatMap(chunk => [
      chunk.document_id,
      chunk.content,
      chunk.page_number || null,
      chunk.chunk_index,
      chunk.content.length,
      chunk.token_count || null,
    ]);

    await db.query(
      `INSERT INTO document_chunks (
        document_id, content, page_number, chunk_index, char_count, token_count
      ) VALUES ${values}`,
      params
    );
  }

  static async countByDocumentId(documentId: string): Promise<number> {
    const result = await db.query<{ count: string }>(
      'SELECT COUNT(*) as count FROM document_chunks WHERE document_id = $1',
      [documentId]
    );
    return parseInt(result.rows[0].count, 10);
  }

  static async deleteByDocumentId(documentId: string): Promise<number> {
    const result = await db.query(
      'DELETE FROM document_chunks WHERE document_id = $1',
      [documentId]
    );
    return result.rowCount || 0;
  }
}

export default DocumentChunkModel;