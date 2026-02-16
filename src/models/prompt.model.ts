import { QueryResult } from 'pg';
import db from '../infra/database';

export interface Prompt extends QueryResult{
  id: string;
  name: string;
  version: number;
  content: string;
  is_active: boolean;
  created_at: Date;
  created_by: string | null;
  metadata: Record<string, any>;
  stats: {
    total_uses: number;
    avg_tokens: number;
    avg_response_time_ms: number;
  };
}

export class PromptModel {
  /**
   * Get active prompt by name
   */
  static async getActive(name: string): Promise<Prompt | null> {
    const result = await db.query<Prompt>(
      `SELECT * FROM prompts 
       WHERE name = $1 AND is_active = true 
       LIMIT 1`,
      [name]
    );
    return result.rows[0] || null;
  }

  /**
   * Get specific version of a prompt
   */
  static async getVersion(name: string, version: number): Promise<Prompt | null> {
    const result = await db.query<Prompt>(
      'SELECT * FROM prompts WHERE name = $1 AND version = $2',
      [name, version]
    );
    return result.rows[0] || null;
  }

  /**
   * Get all versions of a prompt
   */
  static async getAllVersions(name: string): Promise<Prompt[]> {
    const result = await db.query<Prompt>(
      'SELECT * FROM prompts WHERE name = $1 ORDER BY version DESC',
      [name]
    );
    return result.rows;
  }

  /**
   * List all prompt names
   */
  static async listNames(): Promise<string[]> {
    const result = await db.query<any>(
      'SELECT DISTINCT name FROM prompts ORDER BY name'
    );
    return result.rows.map(r => r.name);
  }

  /**
   * Create new prompt version
   */
  static async create(data: {
    name: string;
    content: string;
    created_by?: string;
    is_active?: boolean;
    metadata?: Record<string, any>;
  }): Promise<Prompt> {
    // Get next version number
    const versionResult = await db.query(
      'SELECT COALESCE(MAX(version), 0) as max_version FROM prompts WHERE name = $1',
      [data.name]
    ) as unknown as QueryResult<{ max_version: number }>;
    const nextVersion = versionResult.rows[0].max_version + 1;

    const result = await db.query<Prompt>(
      `INSERT INTO prompts (name, version, content, is_active, created_by, metadata)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        data.name,
        nextVersion,
        data.content,
        data.is_active || false,
        data.created_by || null,
        data.metadata || {},
      ]
    );

    return result.rows[0];
  }

  /**
   * Activate a specific version (and deactivate all others)
   */
  static async activate(name: string, version: number): Promise<Prompt | null> {
    // Use a transaction to ensure atomicity
    const client = await db.getClient();
    
    try {
      await client.query('BEGIN');
      
      // Deactivate all versions of this prompt
      await client.query(
        'UPDATE prompts SET is_active = false WHERE name = $1',
        [name]
      );
      
      // Activate the specified version
      const result = await client.query<Prompt>(
        `UPDATE prompts 
         SET is_active = true 
         WHERE name = $1 AND version = $2
         RETURNING *`,
        [name, version]
      );
      
      await client.query('COMMIT');
      
      return result.rows[0] || null;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }



  /**
   * Update prompt stats
   */
  static async updateStats(
    id: string,
    tokenCount: number,
    responseTimeMs: number
  ): Promise<void> {
    await db.query(
      `UPDATE prompts 
       SET stats = jsonb_set(
         jsonb_set(
           jsonb_set(
             stats,
             '{total_uses}',
             to_jsonb((stats->>'total_uses')::int + 1)
           ),
           '{avg_tokens}',
           to_jsonb(
             ((stats->>'avg_tokens')::float * (stats->>'total_uses')::int + $2) / 
             ((stats->>'total_uses')::int + 1)
           )
         ),
         '{avg_response_time_ms}',
         to_jsonb(
           ((stats->>'avg_response_time_ms')::float * (stats->>'total_uses')::int + $3) / 
           ((stats->>'total_uses')::int + 1)
         )
       )
       WHERE id = $1`,
      [id, tokenCount, responseTimeMs]
    );
  }

  /**
   * Delete a prompt version (soft delete by setting inactive)
   */
  static async delete(name: string, version: number): Promise<boolean> {
    const result = await db.query(
      'UPDATE prompts SET is_active = false WHERE name = $1 AND version = $2',
      [name, version]
    );
    return result.rowCount ? result.rowCount > 0 : false;
  }
}

export default PromptModel;
