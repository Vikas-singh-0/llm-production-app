import { readFileSync } from 'fs';
import { join } from 'path';
import db from '../infra/database';
import logger from '../infra/logger';

async function runMigrations() {
  try {
    logger.info('Starting database migration...');

    // Run migrations in order
    const migrations = [
      // '001_initial_schema.sql',
      // '002_chat_tables.sql',
      // '003_prompts.sql',
      // '004_summaries.sql',
      '005_documents.sql',
    ];

    for (const migrationFile of migrations) {
      logger.info(`Running migration: ${migrationFile}`);
      const migrationPath = join(__dirname, 'migrations', migrationFile);
      const migrationSQL = readFileSync(migrationPath, 'utf-8');
      await db.query(migrationSQL);
      logger.info(`Completed migration: ${migrationFile}`);
    }

    logger.info('All migrations completed successfully');

    // Verify data
    const orgsResult = await db.query('SELECT id, name, slug FROM orgs');
    const usersResult = await db.query('SELECT id, email, role, org_id FROM users');
    const chatsResult = await db.query('SELECT COUNT(*) as count FROM chats');
    const messagesResult = await db.query('SELECT COUNT(*) as count FROM messages');
    const promptsResult = await db.query('SELECT name, version, is_active FROM prompts');

    logger.info('Database status', {
      orgs: orgsResult.rows.length,
      users: usersResult.rows.length,
      chats: chatsResult.rows[0].count,
      messages: messagesResult.rows[0].count,
      prompts: promptsResult.rows,
    });

    await db.close();
    process.exit(0);
  } catch (error) {
    logger.error('Migration failed', { error });
    await db.close();
    process.exit(1);
  }
}

runMigrations();