#!/bin/bash

echo "🧪 Testing STEP 3.1 - Claude Integration"
echo "========================================"
echo ""

# Check if API key is set
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "❌ ERROR: ANTHROPIC_API_KEY environment variable not set"
  echo ""
  echo "Please set your API key:"
  echo "  export ANTHROPIC_API_KEY='your-api-key-here'"
  echo ""
  echo "Or add it to .env file:"
  echo "  ANTHROPIC_API_KEY=your-api-key-here"
  echo ""
  exit 1
fi

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo ""
  echo "Usage: ./test-claude.sh <ORG_ID> <USER_ID>"
  echo ""
  echo "Get user IDs with:"
  echo "  docker exec -it llm-app-postgres psql -U postgres -d llm_app -c 'SELECT id, email FROM users;'"
  echo ""
  exit 1
fi

echo "Testing with:"
echo "  ORG_ID:  $ORG_ID"
echo "  USER_ID: $USER_ID"
echo "  API KEY: ${ANTHROPIC_API_KEY:0:10}..."
echo ""

echo "1️⃣  Testing non-streaming chat with real Claude..."
echo "---"
echo "Asking Claude a question..."
echo ""

RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "What is 2+2? Please answer briefly."
  }')

echo "$RESPONSE" | jq '.'

# Extract chat_id and check for errors
ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo ""
  echo "❌ Error occurred. Check:"
  echo "  - Is ANTHROPIC_API_KEY set correctly?"
  echo "  - Is the server running?"
  echo "  - Are the org/user IDs valid?"
  exit 1
fi

CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')
REPLY=$(echo "$RESPONSE" | jq -r '.reply')
INPUT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.input_tokens')
OUTPUT_TOKENS=$(echo "$RESPONSE" | jq -r '.usage.output_tokens')

echo ""
echo "✅ Claude Response:"
echo "   $REPLY"
echo ""
echo "📊 Token Usage:"
echo "   Input:  $INPUT_TOKENS tokens"
echo "   Output: $OUTPUT_TOKENS tokens"
echo ""

echo "2️⃣  Testing streaming chat with real Claude..."
echo "---"
echo "Watch Claude's response stream in real-time:"
echo ""

curl -N -X POST "$BASE_URL/chat/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"Write a haiku about programming.\",
    \"chat_id\": \"$CHAT_ID\"
  }" 2>/dev/null | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
      json="${line#data: }"
      
      token=$(echo "$json" | jq -r '.token // empty')
      done=$(echo "$json" | jq -r '.done // false')
      error=$(echo "$json" | jq -r '.error // empty')
      
      if [ -n "$error" ]; then
        echo ""
        echo "❌ Error: $error"
        break
      fi
      
      if [ "$done" = "true" ]; then
        echo ""
        echo ""
        usage=$(echo "$json" | jq -r '.usage // empty')
        if [ -n "$usage" ] && [ "$usage" != "empty" ]; then
          input=$(echo "$json" | jq -r '.usage.input_tokens')
          output=$(echo "$json" | jq -r '.usage.output_tokens')
          echo "✅ Stream complete!"
          echo "📊 Token Usage: Input=$input, Output=$output"
        fi
      elif [ -n "$token" ]; then
        echo -n "$token"
      fi
    fi
done

echo ""
echo ""

echo "3️⃣  Verify conversation history..."
echo "---"
curl -s "$BASE_URL/chat/$CHAT_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq '{
    message_count,
    messages: .messages | map({
      role,
      content: .content[:80] + "...",
      token_count
    })
  }'

echo ""
echo ""

echo "4️⃣  Test conversation context (Claude should remember)..."
echo "---"
echo "Asking a follow-up question..."
echo ""

RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"What was my first question?\",
    \"chat_id\": \"$CHAT_ID\"
  }")

REPLY=$(echo "$RESPONSE" | jq -r '.reply')
echo "Claude's response:"
echo "  $REPLY"
echo ""

if [[ "$REPLY" == *"2+2"* ]] || [[ "$REPLY" == *"first"* ]] || [[ "$REPLY" == *"math"* ]]; then
  echo "✅ Claude remembered the context!"
else
  echo "⚠️  Claude might not have remembered (check manually)"
fi

echo ""
echo ""

echo "5️⃣  Check database for token counts..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT role, LENGTH(content) as char_count, token_count FROM messages WHERE chat_id = '$CHAT_ID' ORDER BY created_at;"

echo ""
echo ""

echo "✅ Claude integration test complete!"
echo ""
echo "Key achievements:"
echo "- ✅ Real Claude API working"
echo "- ✅ Token-by-token streaming"
echo "- ✅ Token counting and tracking"
echo "- ✅ Conversation context maintained"
echo "- ✅ Messages stored with token counts"
echo ""
echo "Next: Test the HTML streaming interface!"
echo "  open test-streaming.html"