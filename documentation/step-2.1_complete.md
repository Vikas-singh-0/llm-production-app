# STEP 2.1 COMPLETE ✅

## What Was Built

A working chat API that stores messages - **intentionally without any LLM**:

✅ **Database schema** for chats and messages
✅ **POST /chat endpoint** - send messages, get canned responses
✅ **GET /chat/:id** - retrieve chat history
✅ **GET /chats** - list user's chats
✅ **Multi-tenant chat isolation** - chats filtered by org_id
✅ **Message persistence** - all messages stored in PostgreSQL
✅ **Input validation** - message length, required fields
✅ **Auto-titling** - first message becomes chat title

## Why No LLM Yet?

This is **intentional** to avoid "AI-first spaghetti":

❌ **Bad approach:**
```
1. Add Claude SDK
2. Make it work somehow
3. Figure out auth/storage/limits later
4. Spaghetti code
```

✅ **Good approach (what we're doing):**
```
1. Build clean chat API ← WE ARE HERE
2. Add message storage
3. Validate everything works
4. THEN add LLM as a service
5. Clean architecture
```

**Benefits:**
- Chat API is testable without burning API credits
- Can swap LLM providers easily
- Storage layer is independent
- Rate limiting already works
- Multi-tenant isolation already works

## New Files Created

```
src/
├── db/
│   └── migrations/
│       └── 002_chat_tables.sql        # Chats + messages schema
├── models/
│   ├── chat.model.ts                  # Chat CRUD operations
│   └── message.model.ts               # Message CRUD operations
├── routes/
│   └── chat.route.ts                  # POST /chat, GET /chat/:id, GET /chats
test-chat.sh                            # Test script
```

## Modified Files

- `src/db/migrate.ts` - Runs chat migration
- `src/app.ts` - Added chat routes

## Database Schema

### Chats Table

```sql
CREATE TABLE chats (
  id          UUID PRIMARY KEY,
  org_id      UUID REFERENCES orgs(id),
  user_id     UUID REFERENCES users(id),
  title       VARCHAR(255),           -- First message preview
  created_at  TIMESTAMP,
  updated_at  TIMESTAMP,
  deleted_at  TIMESTAMP,
  metadata    JSONB
);

-- Indexes
CREATE INDEX idx_chats_org_id ON chats(org_id);
CREATE INDEX idx_chats_user_id ON chats(user_id);
CREATE INDEX idx_chats_updated_at ON chats(updated_at DESC);
```

### Messages Table

```sql
CREATE TABLE messages (
  id          UUID PRIMARY KEY,
  chat_id     UUID REFERENCES chats(id),
  role        VARCHAR(50),            -- 'user', 'assistant', 'system'
  content     TEXT,                   -- The actual message
  created_at  TIMESTAMP,
  token_count INTEGER,                -- For future LLM tracking
  metadata    JSONB
);

-- Indexes
CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_messages_created_at ON messages(created_at ASC);
```

**Key relationships:**
- Chats belong to orgs (multi-tenant)
- Chats belong to users
- Messages belong to chats
- Cascade delete: delete chat → delete all its messages

## Setup Instructions

### 1. Run New Migration

```bash
npm run db:migrate
```

**Expected output:**
```
[info]: Running migration: 001_initial_schema.sql
[info]: Completed migration: 001_initial_schema.sql
[info]: Running migration: 002_chat_tables.sql
[info]: Completed migration: 002_chat_tables.sql
[info]: All migrations completed successfully
[info]: Database status {
  orgs: 2,
  users: 3,
  chats: 0,
  messages: 0
}
```

### 2. Verify Tables

```bash
docker exec -it llm-app-postgres psql -U postgres -d llm_app

\dt
```

**Expected:**
```
           List of relations
 Schema |   Name    | Type  |  Owner
--------+-----------+-------+----------
 public | chats     | table | postgres
 public | messages  | table | postgres
 public | orgs      | table | postgres
 public | users     | table | postgres
```

### 3. Start Server

```bash
npm run dev
```

## Testing the Chat API

### Test 1: Create New Chat

```bash
ORG_ID="00000000-0000-0000-0000-000000000001"
USER_ID="<from-database>"

curl -X POST http://localhost:3000/chat \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Hello! This is my first message."
  }' | jq .
```

**Expected Response:**
```json
{
  "chat_id": "abc-123-def-456",
  "message_id": "msg-789-xyz-012",
  "reply": "Chat system online. I received your message: \"Hello! This is my first message.\"",
  "created_at": "2024-02-04T10:30:00.000Z"
}
```

### Test 2: Continue Existing Chat

```bash
CHAT_ID="abc-123-def-456"  # From previous response

curl -X POST http://localhost:3000/chat \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"Tell me more\",
    \"chat_id\": \"$CHAT_ID\"
  }" | jq .
```

**Expected Response:**
```json
{
  "chat_id": "abc-123-def-456",
  "message_id": "msg-345-uvw-678",
  "reply": "Chat system online. I received your message: \"Tell me more\"",
  "created_at": "2024-02-04T10:30:05.000Z"
}
```

### Test 3: Get Chat History

```bash
curl http://localhost:3000/chat/$CHAT_ID \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
```

**Expected Response:**
```json
{
  "chat_id": "abc-123-def-456",
  "title": "Hello! This is my first message.",
  "created_at": "2024-02-04T10:30:00.000Z",
  "updated_at": "2024-02-04T10:30:05.000Z",
  "message_count": 4,
  "messages": [
    {
      "id": "msg-1",
      "role": "user",
      "content": "Hello! This is my first message.",
      "created_at": "2024-02-04T10:30:00.000Z"
    },
    {
      "id": "msg-2",
      "role": "assistant",
      "content": "Chat system online. I received your message: \"Hello! This is my first message.\"",
      "created_at": "2024-02-04T10:30:01.000Z"
    },
    {
      "id": "msg-3",
      "role": "user",
      "content": "Tell me more",
      "created_at": "2024-02-04T10:30:05.000Z"
    },
    {
      "id": "msg-4",
      "role": "assistant",
      "content": "Chat system online. I received your message: \"Tell me more\"",
      "created_at": "2024-02-04T10:30:06.000Z"
    }
  ]
}
```

### Test 4: List All Chats

```bash
curl http://localhost:3000/chats \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
```

**Expected Response:**
```json
{
  "chats": [
    {
      "id": "abc-123-def-456",
      "title": "Hello! This is my first message.",
      "created_at": "2024-02-04T10:30:00.000Z",
      "updated_at": "2024-02-04T10:30:05.000Z"
    }
  ],
  "count": 1
}
```

### Test 5: Validation - Empty Message

```bash
curl -X POST http://localhost:3000/chat \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": ""}' | jq .
```

**Expected Response:**
```json
{
  "error": "Bad Request",
  "message": "Message is required and must be a non-empty string"
}
```

### Test 6: Multi-Tenant Isolation

```bash
# Try to access Chat from Org 1 using Org 2's credentials
WRONG_ORG="00000000-0000-0000-0000-000000000002"

curl http://localhost:3000/chat/$CHAT_ID \
  -H "x-org-id: $WRONG_ORG" \
  -H "x-user-id: $USER_ID" | jq .
```

**Expected Response:**
```json
{
  "error": "Not Found",
  "message": "Chat not found"
}
```

### Test 7: Run Full Test Suite

```bash
./test-chat.sh $ORG_ID $USER_ID
```

## API Endpoints

### POST /chat

**Purpose:** Send a message and get a response

**Authentication:** Required (x-org-id, x-user-id headers)

**Rate Limited:** Yes (per-org token bucket)

**Request:**
```json
{
  "message": "string (required, 1-10000 chars)",
  "chat_id": "uuid (optional, omit to create new chat)"
}
```

**Response (200):**
```json
{
  "chat_id": "uuid",
  "message_id": "uuid",
  "reply": "string",
  "created_at": "timestamp"
}
```

**Errors:**
- 400: Invalid input (empty message, too long)
- 401: Unauthorized (missing auth headers)
- 404: Chat not found (invalid chat_id)
- 429: Rate limit exceeded
- 500: Internal server error

### GET /chat/:chatId

**Purpose:** Get full chat history

**Authentication:** Required

**Request:** None (chatId in URL)

**Response (200):**
```json
{
  "chat_id": "uuid",
  "title": "string",
  "created_at": "timestamp",
  "updated_at": "timestamp",
  "message_count": 4,
  "messages": [
    {
      "id": "uuid",
      "role": "user|assistant|system",
      "content": "string",
      "created_at": "timestamp"
    }
  ]
}
```

### GET /chats

**Purpose:** List user's chats

**Authentication:** Required

**Response (200):**
```json
{
  "chats": [
    {
      "id": "uuid",
      "title": "string",
      "created_at": "timestamp",
      "updated_at": "timestamp"
    }
  ],
  "count": 1
}
```

## Multi-Tenant Isolation

Every query filters by `org_id`:

```typescript
// GOOD - always filter by org
ChatModel.findById(chatId, req.context.orgId);

// BAD - would leak data
ChatModel.findById(chatId); // ❌ Missing org filter
```

**Protection layers:**
1. Database foreign keys (org_id required)
2. Model methods require org_id parameter
3. Route handlers use req.context.orgId
4. Indexes on org_id for performance

## Message Flow

```
1. User sends message
   ↓
2. Create user message in DB
   ↓
3. Generate response (canned for now)
   ↓
4. Create assistant message in DB
   ↓
5. Update chat.updated_at
   ↓
6. Return response to user
```

## Database State

Check what's stored:

```bash
# View all chats
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT id, title, user_id, created_at FROM chats;"

# View messages for a chat
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT role, content, created_at FROM messages WHERE chat_id = '<chat-id>' ORDER BY created_at;"

# Count messages by role
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT role, COUNT(*) FROM messages GROUP BY role;"
```

## What's Ready for LLM Integration

When we add Claude in the next step, we'll only need to:

1. Replace this line:
   ```typescript
   const assistantReply = "Chat system online...";
   ```
   
2. With:
   ```typescript
   const assistantReply = await claudeService.chat(message, history);
   ```

Everything else already works:
- ✅ Message storage
- ✅ Chat history retrieval
- ✅ Multi-tenant isolation
- ✅ Rate limiting
- ✅ Authentication
- ✅ Logging
- ✅ Metrics

## Log Examples

**New chat created:**
```json
{
  "level": "info",
  "message": "Chat request received",
  "requestId": "abc-123",
  "orgId": "org-uuid",
  "userId": "user-uuid",
  "chatId": "new",
  "messageLength": 32
}
```

**Response generated:**
```json
{
  "level": "info",
  "message": "Chat response generated",
  "requestId": "abc-123",
  "chatId": "chat-uuid",
  "userMessageId": "msg-1",
  "assistantMessageId": "msg-2"
}
```

---

## 📌 COMMIT CHECKPOINT

You now have:
- Working chat API ✅
- Message persistence ✅
- Chat history ✅
- Multi-tenant isolation ✅
- No LLM yet (intentional) ✅
- Clean architecture ready for AI ✅

**Next Step: STEP 2.2 - Streaming Infrastructure**

We'll add:
- Server-Sent Events (SSE)
- Token-by-token streaming
- Abort/cancel functionality
- Still no LLM - just simulated streaming!

Ready when you are! 🚀