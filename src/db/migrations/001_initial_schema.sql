-- Migration: Initial schema for multi-tenant application
-- Version: 001
-- Description: Create orgs and users tables

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Organizations table (multi-tenant isolation)
CREATE TABLE IF NOT EXISTS orgs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  deleted_at TIMESTAMP WITH TIME ZONE,
  
  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,
  
  -- Indexing
  CONSTRAINT orgs_slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

-- Users table (belongs to an org)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  role VARCHAR(50) DEFAULT 'member',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  deleted_at TIMESTAMP WITH TIME ZONE,
  
  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb,
  
  -- Constraints
  CONSTRAINT users_email_org_unique UNIQUE (org_id, email),
  CONSTRAINT users_role_check CHECK (role IN ('owner', 'admin', 'member'))
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_org_id ON users(org_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_orgs_slug ON orgs(slug) WHERE deleted_at IS NULL;

-- Updated timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_orgs_updated_at BEFORE UPDATE ON orgs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert seed data for testing
INSERT INTO orgs (id, name, slug) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Acme Corp', 'acme-corp'),
  ('00000000-0000-0000-0000-000000000002', 'Tech Startup Inc', 'tech-startup')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO users (org_id, email, name, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin@acme.com', 'Alice Admin', 'admin'),
  ('00000000-0000-0000-0000-000000000001', 'user@acme.com', 'Bob User', 'member'),
  ('00000000-0000-0000-0000-000000000002', 'founder@techstartup.com', 'Charlie Founder', 'owner')
ON CONFLICT (org_id, email) DO NOTHING;