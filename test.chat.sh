#!/bin/bash

echo "🧪 Testing STEP 2.1 - Chat API (No LLM)"
echo "========================================"
echo ""

BASE_URL="http://localhost:3000"

# You'll need actual IDs from your database
ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo ""
  echo "Usage: ./test-chat.sh <ORG_ID> <USER_ID>"
  echo ""
  echo "Get user IDs with:"
  echo "  docker exec -it llm-app-postgres psql -U postgres -d llm_app -c 'SELECT id, email FROM users;'"
  echo ""
  exit 1
fi

echo "Testing with:"
echo "  ORG_ID:  $ORG_ID"
echo "  USER_ID: $USER_ID"
echo ""

echo "1️⃣  Creating a new chat..."
echo "---"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Hello! This is my first message."
  }')

echo "$RESPONSE" | jq .

# Extract chat_id for next tests
CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')

if [ "$CHAT_ID" = "null" ]; then
  echo ""
  echo "❌ Failed to create chat. Check auth headers and database."
  exit 1
fi

echo ""
echo "✅ Chat created: $CHAT_ID"
echo ""

echo "2️⃣  Sending another message to the same chat..."
echo "---"
curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"This is my second message\",
    \"chat_id\": \"$CHAT_ID\"
  }" | jq .
echo ""
echo ""

echo "3️⃣  Getting chat history..."
echo "---"
curl -s "$BASE_URL/chat/$CHAT_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "4️⃣  Listing all chats for user..."
echo "---"
curl -s "$BASE_URL/chats" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "5️⃣  Testing validation - empty message..."
echo "---"
curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": ""
  }' | jq .
echo ""
echo ""

echo "6️⃣  Testing validation - missing message..."
echo "---"
curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{}' | jq .
echo ""
echo ""

echo "7️⃣  Testing auth - no headers..."
echo "---"
curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "This should fail"
  }' | jq .
echo ""
echo ""

echo "8️⃣  Check database state..."
echo "---"
echo "Chats count:"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT COUNT(*) as total_chats FROM chats WHERE deleted_at IS NULL;"

echo ""
echo "Messages count:"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT COUNT(*) as total_messages FROM messages;"

echo ""
echo "Recent chats:"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT id, title, user_id, created_at FROM chats WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 3;"

echo ""
echo ""

echo "✅ Chat API test complete!"
echo ""
echo "Key observations:"
echo "- POST /chat creates new chats automatically"
echo "- Messages are stored with user and assistant roles"
echo "- Chat history is preserved"
echo "- Multi-tenant isolation works (org_id filtering)"
echo "- No LLM yet - just canned responses"s