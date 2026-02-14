#!/bin/bash

echo "🧪 Testing STEP 2.2 - Streaming Infrastructure"
echo "=============================================="
echo ""

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-27bc8096-2f47-4eef-8655-42cef0885f7a}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo ""
  echo "Usage: ./test-streaming.sh <ORG_ID> <USER_ID>"
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

echo "1️⃣  Testing regular (non-streaming) endpoint..."
echo "---"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Hello from regular endpoint"
  }')

echo "$RESPONSE" | jq .
CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')
echo ""
echo "Chat ID: $CHAT_ID"
echo ""

echo "2️⃣  Testing streaming endpoint..."
echo "---"
echo "Watch for tokens arriving one at a time:"
echo ""

curl -N -X POST "$BASE_URL/chat/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"Hello from streaming endpoint\",
    \"chat_id\": \"$CHAT_ID\"
  }" 2>/dev/null | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
      # Extract JSON from "data: {...}" format
      json="${line#data: }"
      
      # Parse token and done fields
      token=$(echo "$json" | jq -r '.token // empty')
      done=$(echo "$json" | jq -r '.done // false')
      
      if [ "$done" = "true" ]; then
        echo ""
        echo ""
        echo "✅ Stream complete!"
        full_text=$(echo "$json" | jq -r '.fullText // empty')
        if [ -n "$full_text" ]; then
          echo "Full text: $full_text"
        fi
      elif [ -n "$token" ]; then
        # Print token without newline to see streaming effect
        echo -n "$token"
      fi
    fi
done

echo ""
echo ""

echo "3️⃣  Verify messages were stored..."
echo "---"
curl -s "$BASE_URL/chat/$CHAT_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq '.message_count, .messages[-2:] | .[] | {role, content: .content[:60]}'

echo ""
echo ""

echo "4️⃣  Test streaming with longer message..."
echo "---"
echo "This should take a few seconds to stream:"
echo ""

curl -N -X POST "$BASE_URL/chat/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{
    \"message\": \"Tell me a longer story about the importance of good software architecture and why we should build foundations before adding complex features like AI\",
    \"chat_id\": \"$CHAT_ID\"
  }" 2>/dev/null | while IFS= read -r line; do
    if [[ $line == data:* ]]; then
      json="${line#data: }"
      token=$(echo "$json" | jq -r '.token // empty')
      done=$(echo "$json" | jq -r '.done // false')
      
      if [ "$done" = "true" ]; then
        echo ""
        echo "✅ Stream complete!"
      elif [ -n "$token" ]; then
        echo -n "$token"
      fi
    fi
done

echo ""
echo ""

echo "5️⃣  Open HTML test page..."
echo "---"
echo "For interactive testing, open: file://$(pwd)/test-streaming.html"
echo ""
echo "Or start a simple HTTP server:"
echo "  python3 -m http.server 8080"
echo "  Then open: http://localhost:8080/test-streaming.html"
echo ""

echo "✅ Streaming test complete!"
echo ""
echo "Key observations:"
echo "- Tokens arrive word-by-word (simulating LLM)"
echo "- Each token is sent as SSE event"
echo "- Messages are stored after stream completes"
echo "- No LLM yet - just infrastructure testing"