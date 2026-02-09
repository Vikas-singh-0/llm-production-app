import { readFileSync } from 'fs';
import { join } from 'path';
import db from '../infra/database';
import logger from '../infra/logger';

async function runMigrations() {
  try {
    logger.info('Starting database migration...');

    const migrationPath = join(__dirname, 'migrations', '001_initial_schema.sql');
    const migrationSQL = readFileSync(migrationPath, 'utf-8');

    await db.query(migrationSQL);

    logger.info('Migration completed successfully');

    // Verify data
    const orgsResult = await db.query('SELECT id, name, slug FROM orgs');
    const usersResult = await db.query('SELECT id, email, role, org_id FROM users');

    logger.info('Database seeded', {
      orgs: orgsResult.rows,
      users: usersResult.rows,
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