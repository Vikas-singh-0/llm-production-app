-- Migration: Prompts table for versioned prompt management
-- Version: 003
-- Description: Create prompts table for storing versioned system prompts

-- Prompts table (versioned prompt management)
CREATE TABLE IF NOT EXISTS prompts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  content TEXT NOT NULL,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by VARCHAR(255),
  
  -- Metadata and stats
  metadata JSONB DEFAULT '{}'::jsonb,
  stats JSONB DEFAULT '{
    "total_uses": 0,
    "avg_tokens": 0,
    "avg_response_time_ms": 0
  }'::jsonb,
  
  -- Constraints
  CONSTRAINT prompts_name_version_unique UNIQUE (name, version)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_prompts_name ON prompts(name);
CREATE INDEX IF NOT EXISTS idx_prompts_is_active ON prompts(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_prompts_name_version ON prompts(name, version);
CREATE INDEX IF NOT EXISTS idx_prompts_created_at ON prompts(created_at DESC);

-- Insert seed data for testing
INSERT INTO prompts (name, version, content, is_active, created_by, metadata) VALUES
  (
    'default-system-prompt', 
    1, 
    'You are a helpful AI assistant. Provide clear, accurate, and helpful responses to user queries.', 
    true, 
    'system',
    '{"description": "Default system prompt for general queries", "category": "system"}'
  ),
  (
    'code-assistant-prompt', 
    1, 
    'You are a code assistant specialized in software development. Help users write, debug, and understand code. Provide code examples and explanations.', 
    true, 
    'system',
    '{"description": "Specialized prompt for code-related queries", "category": "code"}'
  ),
  (
    'creative-writing-prompt', 
    1, 
    'You are a creative writing assistant. Help users with storytelling, creative writing, and content creation. Be imaginative and inspiring.', 
    false, 
    'system',
    '{"description": "Creative writing assistant prompt", "category": "creative"}'
  )
ON CONFLICT (name, version) DO NOTHING;
