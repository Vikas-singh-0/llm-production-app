-- Migration: Conversation summaries
-- Version: 004
-- Description: Store periodic conversation summaries for long-term context

-- Summaries table (condensed conversation history)
CREATE TABLE IF NOT EXISTS summaries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  
  -- Summary content
  content TEXT NOT NULL,
  
  -- Which messages are covered by this summary
  start_message_id UUID REFERENCES messages(id),
  end_message_id UUID REFERENCES messages(id),
  message_count INTEGER NOT NULL,
  
  -- Token tracking
  original_tokens INTEGER NOT NULL,   -- Tokens in original messages
  summary_tokens INTEGER NOT NULL,    -- Tokens in summary
  compression_ratio FLOAT,             -- original/summary (higher = better)
  
  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by VARCHAR(50) DEFAULT 'system',  -- 'system' or 'manual'
  
  metadata JSONB DEFAULT '{}'::jsonb
);

-- Indexes for fast summary lookup
CREATE INDEX IF NOT EXISTS idx_summaries_chat_id ON summaries(chat_id);
CREATE INDEX IF NOT EXISTS idx_summaries_created_at ON summaries(created_at DESC);

-- Function to calculate compression ratio
CREATE OR REPLACE FUNCTION calculate_compression_ratio()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.summary_tokens > 0 THEN
    NEW.compression_ratio = NEW.original_tokens::FLOAT / NEW.summary_tokens::FLOAT;
  ELSE
    NEW.compression_ratio = 0;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-calculate compression ratio
DROP TRIGGER IF EXISTS trigger_compression_ratio ON summaries;
CREATE TRIGGER trigger_compression_ratio
  BEFORE INSERT OR UPDATE ON summaries
  FOR EACH ROW
  EXECUTE FUNCTION calculate_compression_ratio();