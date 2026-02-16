# STEP 3.2 COMPLETE ✅

## What Was Built

**Real LLMOps** - Database-backed prompt versioning without redeployment:

✅ **Prompts in database** - System prompts stored in PostgreSQL
✅ **Version control** - Multiple versions per prompt
✅ **Active version toggle** - Switch versions instantly
✅ **Rollback capability** - No code deployment needed
✅ **Usage stats** - Track performance per version
✅ **A/B testing ready** - Foundation for prompt experiments

## Why This Matters

### Before (Hard-coded Prompts)

```typescript
// Prompt in code
const systemPrompt = "You are a helpful assistant...";

// To change: Edit code → Git commit → Deploy → Restart
// Downtime: 5-15 minutes
// Risk: High
```

### After (Database Prompts)

```typescript
// Prompt from database
const prompt = await PromptModel.getActive('default-system-prompt');

// To change: API call → Instant
// Downtime: 0 seconds  
// Risk: Low (can rollback instantly)
```

**Production benefits:**
- Test prompts in production safely
- A/B test different versions
- Rollback bad prompts instantly
- No deployment for prompt changes

## New Files Created

```
src/
├── db/
│   └── migrations/
│       └── 003_prompts.sql        # Prompts table + versions
├── models/
│   └── prompt.model.ts            # Prompt CRUD operations
├── routes/
│   └── prompt.route.ts            # Prompt management API
├── services/
│   └── claude.service.ts          # Updated to use DB prompts
test-prompts.sh                     # Test script
```

## Modified Files

- `src/db/migrate.ts` - Added prompts migration
- `src/services/claude.service.ts` - Uses database prompts
- `src/app.ts` - Added prompt routes

## Database Schema

```sql
CREATE TABLE prompts (
  id          UUID PRIMARY KEY,
  name        VARCHAR(255),          -- 'default-system-prompt', 'code_helper'
  version     INTEGER,               -- 1, 2, 3...
  content     TEXT,                  -- The system prompt
  is_active   BOOLEAN,               -- Only one active per name
  created_at  TIMESTAMP,
  created_by  UUID REFERENCES users,
  metadata    JSONB,                 -- Custom fields
  stats       JSONB,                 -- Usage tracking
  
  UNIQUE(name, version)
);

-- Trigger ensures only one active version per name
```

## Setup

### 1. Run Migration

```bash
npm run db:migrate
```

**Expected output:**
```
[info]: Running migration: 003_prompts.sql
[info]: Completed migration: 003_prompts.sql
[info]: Database status {
  prompts: [
    { name: 'default-system-prompt', version: 1, is_active: true },
    { name: 'code_helper', version: 1, is_active: false }
  ]
}
```

### 2. Verify Prompts

```bash
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT * FROM prompts;"
```

## API Endpoints

### GET /prompts

List all prompt names

**Response:**
```json
{
  "prompts": ["default-system-prompt", "code_helper"],
  "count": 2
}
```

### GET /prompts/:name

Get all versions of a prompt

**Response:**
```json
{
  "name": "default-system-prompt",
  "active_version": 1,
  "versions": [
    {
      "version": 1,
      "content": "You are a helpful AI assistant...",
      "is_active": true,
      "created_at": "2024-02-04T10:00:00Z",
      "stats": {
        "total_uses": 150,
        "avg_tokens": 450,
        "avg_response_time_ms": 1200
      }
    }
  ]
}
```

### POST /prompts

Create new prompt version (admin only)

**Request:**
```json
{
  "name": "default-system-prompt",
  "content": "You are an enthusiastic AI assistant!",
  "is_active": false,
  "metadata": {
    "description": "Experimental enthusiastic version"
  }
}
```

**Response:**
```json
{
  "id": "prompt-uuid",
  "name": "default-system-prompt",
  "version": 2,
  "content": "You are an enthusiastic AI assistant!",
  "is_active": false,
  "created_at": "2024-02-04T11:00:00Z"
}
```

### PUT /prompts/:name/activate/:version

Activate a specific version (admin only)

**Response:**
```json
{
  "message": "Prompt activated",
  "name": "default-system-prompt",
  "version": 2,
  "is_active": true
}
```

## Testing Prompt Versioning

### Test 1: Check Current Prompt

```bash
ORG_ID="00000000-0000-0000-0000-000000000001"
USER_ID="<from-database>"

curl -s "$BASE_URL/prompts/default-system-prompt" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
```

### Test 2: Test Current Behavior

```bash
# With version 1 (calm prompt)
curl -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": "Say hello"}' | jq -r '.reply'

# Output: "Hello! How can I help you today?"
```

### Test 3: Create New Version

```bash
curl -X POST "$BASE_URL/prompts" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "name": "default-system-prompt",
    "content": "You are SUPER enthusiastic! Use lots of exclamation marks! Be positive!",
    "is_active": false
  }' | jq .
```

### Test 4: Activate New Version

```bash
curl -X PUT "$BASE_URL/prompts/default-system-prompt/activate/2" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
```

### Test 5: Test NEW Behavior

```bash
# With version 2 (enthusiastic prompt)
curl -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": "Say hello"}' | jq -r '.reply'

# Output: "Hello! I'm so excited to help you today!"
```

**Behavior changed instantly!** No deployment needed.

### Test 6: Rollback

```bash
# Activate version 1 again
curl -X PUT "$BASE_URL/prompts/default-system-prompt/activate/1" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .

# Test - back to calm behavior
curl -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": "Say hello"}' | jq -r '.reply'

# Output: "Hello! How can I help you today?"
```

**Rolled back instantly!**

### Test 7: Run Full Suite

```bash
./test-prompts.sh $ORG_ID $USER_ID
```

## Usage Stats Tracking

Every time a prompt is used, stats are updated:

```sql
SELECT 
  name,
  version,
  is_active,
  stats->>'total_uses' as uses,
  stats->>'avg_tokens' as avg_tokens,
  stats->>'avg_response_time_ms' as avg_response_time
FROM prompts
WHERE name = 'default-system-prompt'
ORDER BY version;
```

**Example output:**
```
name                | version | is_active | uses | avg_tokens | avg_response_time
--------------------+---------+-----------+------+------------+------------------
default-system-prompt   | 1       | true      | 150  | 450        | 1200
default-system-prompt   | 2       | false     | 25   | 520        | 1350
```

**Analysis:**
- Version 1: Used 150 times, 450 avg tokens, 1200ms avg
- Version 2: Used 25 times, 520 avg tokens, 1350ms avg

**Conclusion:** Version 2 is more verbose (higher tokens) but slower.

## Prompt Management Workflow

### Development

```bash
# 1. Create experimental prompt
POST /prompts
{
  "name": "default-system-prompt",
  "content": "New prompt text...",
  "is_active": false
}

# 2. Test in development
# (use specific version in code if needed)

# 3. When ready, activate
PUT /prompts/default-system-prompt/activate/2
```

### Production

```bash
# 1. Monitor stats
GET /prompts/default-system-prompt

# 2. See version 2 performing poorly?
PUT /prompts/default-system-prompt/activate/1  # Instant rollback!

# 3. No downtime, no deployment
```

## Advanced Use Cases

### A/B Testing

```typescript
// Route 50% traffic to each version
const version = Math.random() < 0.5 ? 1 : 2;
const prompt = await PromptModel.getVersion('default-system-prompt', version);
```

### Per-User Prompts

```typescript
// Different prompts for different user segments
const promptName = user.plan === 'enterprise' 
  ? 'enterprise_assistant'
  : 'default-system-prompt';

const prompt = await PromptModel.getActive(promptName);
```

### Prompt Templates

```typescript
// Store templates with variables
const content = "You are helping {user.name} with {task.type}...";

// Replace variables at runtime
const finalPrompt = content
  .replace('{user.name}', user.name)
  .replace('{task.type}', task.type);
```

## Versioning Strategy

### Semantic Versioning

```
Version 1: Initial prompt
Version 2: Minor tweak (more concise)
Version 3: Major change (different personality)
```

### Naming Convention

```
default-system-prompt_v1  - Original
default-system-prompt_v2  - Concise version
default-system-prompt_v3  - Detailed version
```

### Metadata Tracking

```json
{
  "description": "More concise responses",
  "author": "user@example.com",
  "experiment": "conciseness_test",
  "date": "2024-02-04"
}
```

## Database Trigger Magic

The database automatically ensures only one active version:

```sql
-- When you activate version 2...
UPDATE prompts SET is_active = true WHERE version = 2;

-- Trigger automatically deactivates others
-- version 1: is_active = false
-- version 3: is_active = false

-- Only version 2: is_active = true
```

**You can't accidentally have two active versions!**

## Logs

**Prompt loaded:**
```json
{
  "level": "debug",
  "message": "Using prompt",
  "name": "default-system-prompt",
  "version": 2,
  "promptId": "prompt-uuid-123"
}
```

**Prompt activated:**
```json
{
  "level": "info",
  "message": "Prompt activated",
  "userId": "user-uuid",
  "promptId": "prompt-uuid-123",
  "name": "default-system-prompt",
  "version": 2
}
```

**Stats updated:**
```json
{
  "level": "info",
  "message": "Claude request completed",
  "promptId": "prompt-uuid-123",
  "totalTokens": 450,
  "responseTimeMs": 1200
}
```

## Production Best Practices

### 1. Version Control

Keep prompts in Git too (backup):

```
prompts/
├── default-system-prompt/
│   ├── v1.txt
│   ├── v2.txt
│   └── v3.txt
└── code_helper/
    └── v1.txt
```

### 2. Testing Process

```
1. Create new version (inactive)
2. Test manually with specific version
3. Monitor stats for 24 hours
4. Compare with current active version
5. If better: activate
6. If worse: keep inactive or delete
```

### 3. Gradual Rollout

```typescript
// Start with 10% traffic
if (Math.random() < 0.1) {
  prompt = await PromptModel.getVersion('default-system-prompt', 2);
} else {
  prompt = await PromptModel.getActive('default-system-prompt');
}

// Increase gradually: 10% → 25% → 50% → 100%
```

### 4. Monitoring

```sql
-- Daily prompt performance report
SELECT 
  name,
  version,
  stats->>'total_uses' as daily_uses,
  stats->>'avg_tokens' as avg_tokens,
  stats->>'avg_response_time_ms' as avg_response_time
FROM prompts
WHERE is_active = true;
```

---

## 📌 COMMIT CHECKPOINT

You now have:
- Prompts in database ✅
- Version control ✅
- Instant activation/rollback ✅
- Usage stats tracking ✅
- No-downtime updates ✅
- Real LLMOps ✅

**This is production-grade prompt management!** 🎉

---

## What's Next

You've completed **PHASE 3 - LLM Integration**! 

The build plan continues with:
- **PHASE 4:** Memory (sliding window + summarization)
- **PHASE 5:** Document ingestion (PDF upload)
- **PHASE 6:** Vector DB & RAG
- **PHASE 7:** Hybrid search
- **PHASE 8:** Agents
- **PHASE 9:** Failure modes
- **PHASE 10:** Final demo

You now have a **fully functional, production-ready AI chat application** with:
- ✅ Multi-tenant architecture
- ✅ Real-time streaming
- ✅ Token tracking
- ✅ Rate limiting
- ✅ Prompt versioning
- ✅ Full observability

**Congratulations!** This is resume-worthy work. Want to continue? 🚀