import dotenv from 'dotenv';

dotenv.config();

export type LLMProvider = 'gemini' | 'claude' | 'local';

interface Config {
  nodeEnv: string;
  port: number;
  logLevel: string;
  database: {
    url: string;
    poolMin: number;
    poolMax: number;
  };
  redis: {
    url: string;
    password?: string;
  };
  claude: {
    apiKey: string;
    model: string;
    maxTokens: number;
  };
  gemini: {
    apiKey: string;
    model: string;
    maxTokens: number;
  };
  local: {
    enabled: boolean;
    provider: 'ollama' | 'llama.cpp' | 'lm-studio';
    baseUrl: string;
    model: string;
    maxTokens: number;
  };
  defaultProvider: LLMProvider;
}

export const config: Config = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  logLevel: process.env.LOG_LEVEL || 'info',
  database: {
    url: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/llm-app',
    poolMin: parseInt(process.env.DB_POOL_MIN || '2', 10),
    poolMax: parseInt(process.env.DB_POOL_MAX || '10', 10),
  },
  redis: {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
    password: process.env.REDIS_PASSWORD || undefined,
  },
  claude: {
    apiKey: process.env.ANTHROPIC_API_KEY || 'YOUR_API_KEY',
    model: process.env.CLAUDE_MODEL || 'claude-sonnet-4-20250514',
    maxTokens: parseInt(process.env.CLAUDE_MAX_TOKENS || '4096', 10),
  },
  gemini: {
    apiKey: process.env.GEMINI_API_KEY || 'YOUR_API_KEY',
    model: process.env.GEMINI_MODEL || '',
    maxTokens: parseInt(process.env.GEMINI_MAX_TOKENS || '4096', 10),
  },
  local: {
    enabled: process.env.LOCAL_LLM_ENABLED === 'true',
    provider: (process.env.LOCAL_LLM_PROVIDER as 'ollama' | 'llama.cpp' | 'lm-studio') || 'ollama',
    baseUrl: process.env.LOCAL_LLM_BASE_URL || 'http://localhost:11434',
    model: process.env.LOCAL_LLM_MODEL || 'llama3',
    maxTokens: parseInt(process.env.LOCAL_LLM_MAX_TOKENS || '4096', 10),
  },
  defaultProvider: (process.env.DEFAULT_LLM_PROVIDER as LLMProvider) || 'local',
};

export default config;
