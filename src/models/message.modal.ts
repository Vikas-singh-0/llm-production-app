import db from '../infra/database';

export interface Message {
  id: string;
  chat_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  created_at: Date;
  token_count: number | null;
  metadata: Record<string, any>;
}

export class MessageModel {
  static async findById(id: string): Promise<Message | null> {
    const result = await db.query<Message | any>(
      'SELECT * FROM messages WHERE id = $1',
      [id]
    );
    return result.rows[0] || null;
  }

  static async findByChatId(chatId: string, limit: number = 100): Promise<Message[]> {
    const result = await db.query<Message | any>(
      `SELECT * FROM messages 
       WHERE chat_id = $1 
       ORDER BY created_at ASC 
       LIMIT $2`,
      [chatId, limit]
    );
    return result.rows;
  }

  static async findRecentByChatId(chatId: string, limit: number = 10): Promise<Message[]> {
    const result = await db.query<Message|any>(
      `SELECT * FROM messages 
       WHERE chat_id = $1 
       ORDER BY created_at DESC 
       LIMIT $2`,
      [chatId, limit]
    );
    // Reverse to get chronological order
    return result.rows.reverse();
  }

  static async create(data: {
    chat_id: string;
    role: 'user' | 'assistant' | 'system';
    content: string;
    token_count?: number;
  }): Promise<Message> {
    const result = await db.query<Message | any>(
      `INSERT INTO messages (chat_id, role, content, token_count)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [data.chat_id, data.role, data.content, data.token_count || null]
    );

    // Update chat's updated_at timestamp
    await db.query(
      'UPDATE chats SET updated_at = NOW() WHERE id = $1',
      [data.chat_id]
    );

    return result.rows[0];
  }

  static async countByChatId(chatId: string): Promise<number> {
    const result = await db.query<any>(
      'SELECT COUNT(*) as count FROM messages WHERE chat_id = $1',
      [chatId]
    );
    return parseInt(result.rows[0].count, 10);
  }

  static async deleteByChatId(chatId: string): Promise<number> {
    const result = await db.query<any>(
      'DELETE FROM messages WHERE chat_id = $1',
      [chatId]
    );
    return result.rowCount || 0;
  }
}

export default MessageModel;