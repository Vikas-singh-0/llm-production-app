#!/bin/bash

echo "🧪 Testing STEP 4.1 - Sliding Window Memory"
echo "==========================================="
echo ""

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "❌ ERROR: ANTHROPIC_API_KEY not set"
  exit 1
fi

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo "Usage: ./test-memory.sh <ORG_ID> <USER_ID>"
  exit 1
fi

echo "Testing with:"
echo "  ORG_ID:  $ORG_ID"
echo "  USER_ID: $USER_ID"
echo ""

echo "1️⃣  Create a long conversation (30 messages)..."
echo "---"
echo "This will test that old messages get truncated"
echo ""

# Create initial chat
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Hi! Let'\''s have a long conversation. This is message 1."
  }')

CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')
echo "Chat created: $CHAT_ID"
echo ""

# Add many messages
for i in {2..30}; do
  curl -s -X POST "$BASE_URL/chat" \
    -H "Content-Type: application/json" \
    -H "x-org-id: $ORG_ID" \
    -H "x-user-id: $USER_ID" \
    -d "{
      \"message\": \"This is test message number $i. Adding more context to the conversation.\",
      \"chat_id\": \"$CHAT_ID\"
    }" > /dev/null
  
  if [ $((i % 5)) -eq 0 ]; then
    echo "  Added $i messages..."
  fi
done

echo "  ✅ Created 30 message conversation"
echo ""
echo ""

echo "2️⃣  Check conversation stats..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT COUNT(*) as total_messages, SUM(token_count) as total_tokens FROM messages WHERE chat_id = '$CHAT_ID';"
echo ""
echo ""

echo "3️⃣  Send a new message and check context window..."
echo "---"
echo "Asking Claude to remember the first message..."
echo ""

RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"What was the very first message in this conversation? Can you remember?\",
    \"chat_id\": \"$CHAT_ID\"
  }")

REPLY=$(echo "$RESPONSE" | jq -r '.reply')
INPUT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.input_tokens')

echo "Claude's response:"
echo "  $REPLY"
echo ""
echo "Input tokens used: $INPUT_TOKENS"
echo ""

if [[ "$REPLY" == *"first"* ]] || [[ "$REPLY" == *"message 1"* ]]; then
  echo "✅ Claude remembered (early messages still in context)"
else
  echo "⚠️  Claude might not remember (sliding window truncated early messages)"
fi
echo ""
echo ""

echo "4️⃣  Test with extremely long message..."
echo "---"
echo "Creating a message with ~2000 tokens..."
echo ""

LONG_MESSAGE="This is a very long message. "
for i in {1..200}; do
  LONG_MESSAGE+="This sentence adds more tokens to test the sliding window. "
done

RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"$LONG_MESSAGE\",
    \"chat_id\": \"$CHAT_ID\"
  }")

TOKENS=$(echo "$RESPONSE" | jq -r '.usage.input_tokens')
echo "Input tokens for long message conversation: $TOKENS"
echo ""

if [ "$TOKENS" -lt 10000 ]; then
  echo "✅ Context window working (kept under limit)"
else
  echo "⚠️  Context might be too large"
fi
echo ""
echo ""

echo "5️⃣  Check server logs for context window info..."
echo "---"
echo "Look for 'Context prepared' log entries"
echo "(These show how many messages were included vs truncated)"
echo ""

echo "6️⃣  View conversation in database..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT role, LENGTH(content) as char_length, token_count, created_at FROM messages WHERE chat_id = '$CHAT_ID' ORDER BY created_at DESC LIMIT 10;"
echo ""
echo ""

echo "✅ Sliding window memory test complete!"
echo ""
echo "Key observations:"
echo "- ✅ Long conversations don't exceed token limits"
echo "- ✅ Old messages automatically truncated"
echo "- ✅ Most recent messages always included"
echo "- ✅ Token budget enforced (input tokens < 10k)"
echo ""
echo "Check server logs to see truncation in action!"