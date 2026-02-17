-- Migration: Document chunks table
-- Version: 006
-- Description: Store parsed text chunks from documents

-- Document chunks table
CREATE TABLE IF NOT EXISTS document_chunks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  
  -- Chunk content
  content TEXT NOT NULL,
  page_number INTEGER,
  chunk_index INTEGER NOT NULL,  -- Order within document
  
  -- Metadata
  char_count INTEGER NOT NULL,
  token_count INTEGER,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- For future vector search
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON document_chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_chunk_index ON document_chunks(document_id, chunk_index);
CREATE INDEX IF NOT EXISTS idx_chunks_page_number ON document_chunks(page_number);

-- Add constraint to ensure chunk order is unique per document
ALTER TABLE document_chunks ADD CONSTRAINT unique_chunk_index 
  UNIQUE (document_id, chunk_index);