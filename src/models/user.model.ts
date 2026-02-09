import db from '../infra/database';

export interface User {
  id: string;
  org_id: string;
  email: string;
  name: string | null;
  role: 'owner' | 'admin' | 'member';
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
  metadata: Record<string, any>;
}

export class UserModel {
  static async findById(id: string): Promise<User | null> {
    const result = await db.query(
      'SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL',
      [id]
    );
    return result.rows[0] as User | null;
  }

  static async findByEmail(email: string, orgId: string): Promise<User | null> {
    const result = await db.query(
      'SELECT * FROM users WHERE email = $1 AND org_id = $2 AND deleted_at IS NULL',
      [email, orgId]
    );
    return result.rows[0] as User | null;
  }

  static async findByOrgId(orgId: string): Promise<User[]> {
    const result = await db.query(
      'SELECT * FROM users WHERE org_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC',
      [orgId]
    );
    return result.rows as User[];
  }

  static async create(data: {
    org_id: string;
    email: string;
    name?: string;
    role?: 'owner' | 'admin' | 'member';
  }): Promise<User> {
    const result = await db.query(
      `INSERT INTO users (org_id, email, name, role)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [data.org_id, data.email, data.name || null, data.role || 'member']
    );
    return result.rows[0] as User;
  }
}

export default UserModel;