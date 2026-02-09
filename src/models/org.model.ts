import db from '../infra/database';

export interface Org {
  id: string;
  name: string;
  slug: string;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
  metadata: Record<string, any>;
}

export class OrgModel {
  static async findById(id: string): Promise<Org | null> {
    const result = await db.query(
      'SELECT * FROM orgs WHERE id = $1 AND deleted_at IS NULL',
      [id]
    );
    return result.rows[0] || null;
  }

  static async findBySlug(slug: string): Promise<Org | null> {
    const result = await db.query(
      'SELECT * FROM orgs WHERE slug = $1 AND deleted_at IS NULL',
      [slug]
    );
    return result.rows[0] || null;
  }

  static async findAll(): Promise<Org[]> {
    const result = await db.query(
      'SELECT * FROM orgs WHERE deleted_at IS NULL ORDER BY created_at DESC'
    );
    return result.rows;
  }

  static async create(data: {
    name: string;
    slug: string;
  }): Promise<Org> {
    const result = await db.query(
      `INSERT INTO orgs (name, slug)
       VALUES ($1, $2)
       RETURNING *`,
      [data.name, data.slug]
    );
    return result.rows[0];
  }
}

export default OrgModel;