import db from '../infra/database';

export interface Chat {
  id: string;
  org_id: string;
  user_id: string;
  title: string | null;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
  metadata: Record<string, any>;
}

export class ChatModel {
  static async findById(id: string, orgId: string): Promise<Chat | null> {
    const result = await db.query<any>(
      `SELECT * FROM chats 
       WHERE id = $1 AND org_id = $2 AND deleted_at IS NULL`,
      [id, orgId]
    );
    return result.rows[0] || null;
  }

  static async findByUserId(userId: string, orgId: string, limit: number = 50): Promise<Chat[]> {
    const result = await db.query<any>(
      `SELECT * FROM chats 
       WHERE user_id = $1 AND org_id = $2 AND deleted_at IS NULL 
       ORDER BY updated_at DESC 
       LIMIT $3`,
      [userId, orgId, limit]
    );
    return result.rows;
  }

  static async findByOrgId(orgId: string, limit: number = 100): Promise<Chat[]> {
    const result = await db.query<any>(
      `SELECT * FROM chats 
       WHERE org_id = $1 AND deleted_at IS NULL 
       ORDER BY updated_at DESC 
       LIMIT $2`,
      [orgId, limit]
    );
    return result.rows;
  }

  static async create(data: {
    org_id: string;
    user_id: string;
    title?: string;
  }): Promise<Chat> {
    const result = await db.query<any>(
      `INSERT INTO chats (org_id, user_id, title)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [data.org_id, data.user_id, data.title || null]
    );
    return result.rows[0];
  }

  static async updateTitle(id: string, orgId: string, title: string): Promise<Chat | null> {
    const result = await db.query<any>(
      `UPDATE chats 
       SET title = $1, updated_at = NOW()
       WHERE id = $2 AND org_id = $3 AND deleted_at IS NULL
       RETURNING *`,
      [title, id, orgId]
    );
    return result.rows[0] || null;
  }

  static async delete(id: string, orgId: string): Promise<boolean> {
    const result = await db.query(
      `UPDATE chats 
       SET deleted_at = NOW()
       WHERE id = $1 AND org_id = $2 AND deleted_at IS NULL`,
      [id, orgId]
    );
    return result.rowCount ? result.rowCount > 0 : false;
  }
}

export default ChatModel;