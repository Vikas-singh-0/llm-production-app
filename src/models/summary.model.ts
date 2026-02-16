import db from '../infra/database';

export interface Summary {
  id: string;
  chat_id: string;
  content: string;
  start_message_id: string | null;
  end_message_id: string | null;
  message_count: number;
  original_tokens: number;
  summary_tokens: number;
  compression_ratio: number | null;
  created_at: Date;
  created_by: string;
  metadata: Record<string, any>;
}

export class SummaryModel {
  /**
   * Get latest summary for a chat
   */
  static async getLatest(chatId: string): Promise<Summary | null> {
    const result = await db.query<Summary>(
      `SELECT * FROM summaries 
       WHERE chat_id = $1 
       ORDER BY created_at DESC 
       LIMIT 1`,
      [chatId]
    );
    return result.rows[0] || null;
  }

  /**
   * Get all summaries for a chat
   */
  static async getAllForChat(chatId: string): Promise<Summary[]> {
    const result = await db.query<Summary>(
      `SELECT * FROM summaries 
       WHERE chat_id = $1 
       ORDER BY created_at DESC`,
      [chatId]
    );
    return result.rows;
  }

  /**
   * Create new summary
   */
  static async create(data: {
    chat_id: string;
    content: string;
    start_message_id?: string;
    end_message_id?: string;
    message_count: number;
    original_tokens: number;
    summary_tokens: number;
    created_by?: string;
    metadata?: Record<string, any>;
  }): Promise<Summary> {
    const result = await db.query<Summary>(
      `INSERT INTO summaries (
        chat_id, content, start_message_id, end_message_id,
        message_count, original_tokens, summary_tokens,
        created_by, metadata
      )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [
        data.chat_id,
        data.content,
        data.start_message_id || null,
        data.end_message_id || null,
        data.message_count,
        data.original_tokens,
        data.summary_tokens,
        data.created_by || 'system',
        data.metadata || {},
      ]
    );
    return result.rows[0];
  }

  /**
   * Delete summaries for a chat (e.g., when chat deleted)
   */
  static async deleteForChat(chatId: string): Promise<number> {
    const result = await db.query(
      'DELETE FROM summaries WHERE chat_id = $1',
      [chatId]
    );
    return result.rowCount || 0;
  }

  /**
   * Get summary stats
   */
  static async getStats(): Promise<{
    total_summaries: number;
    avg_compression_ratio: number;
    total_tokens_saved: number;
  }> {
    const result = await db.query<{
      total_summaries: string;
      avg_compression_ratio: string;
      total_tokens_saved: string;
    }>(
      `SELECT 
        COUNT(*) as total_summaries,
        AVG(compression_ratio) as avg_compression_ratio,
        SUM(original_tokens - summary_tokens) as total_tokens_saved
       FROM summaries`
    );

    const row = result.rows[0];
    return {
      total_summaries: parseInt(row.total_summaries, 10),
      avg_compression_ratio: parseFloat(row.avg_compression_ratio) || 0,
      total_tokens_saved: parseInt(row.total_tokens_saved, 10) || 0,
    };
  }
}

export default SummaryModel;