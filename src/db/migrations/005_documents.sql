-- Migration: Documents table
-- Version: 005
-- Description: Store uploaded documents and their metadata

-- Documents table
CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  
  -- File info
  filename VARCHAR(255) NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  mime_type VARCHAR(100) NOT NULL,
  file_size BIGINT NOT NULL,  -- bytes
  
  -- Storage
  storage_path TEXT NOT NULL,  -- S3 key or local path
  storage_type VARCHAR(50) DEFAULT 's3',  -- 's3' or 'local'
  
  -- Status
  status VARCHAR(50) DEFAULT 'uploaded',  -- 'uploaded', 'processing', 'parsed', 'failed'
  error_message TEXT,
  
  -- Processing metadata
  page_count INTEGER,
  parsed_at TIMESTAMP WITH TIME ZONE,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  deleted_at TIMESTAMP WITH TIME ZONE,
  
  -- Metadata
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_documents_org_id ON documents(org_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_documents_user_id ON documents(user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at DESC);

-- Apply updated_at trigger
CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();