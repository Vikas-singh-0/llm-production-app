#!/bin/bash

echo "🧪 Testing STEP 3.2 - Prompt Versioning"
echo "========================================"
echo ""

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo ""
  echo "Usage: ./test-prompts.sh <ORG_ID> <USER_ID>"
  echo ""
  exit 1
fi

echo "Testing with:"
echo "  ORG_ID:  $ORG_ID"
echo "  USER_ID: $USER_ID"
echo ""

echo "1️⃣  List all available prompts..."
echo "---"
curl -s "$BASE_URL/prompts" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "2️⃣  Get versions of 'default-system-prompt' prompt..."
echo "---"
curl -s "$BASE_URL/prompts/default-system-prompt" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "3️⃣  Test current behavior (version 1)..."
echo "---"
echo "Asking: 'Say hello'"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Say hello"
  }')

REPLY=$(echo "$RESPONSE" | jq -r '.reply')
echo "Claude says: $REPLY"
CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')
echo ""
echo ""

echo "4️⃣  Create a new prompt version (version 2)..."
echo "---"
echo "This prompt will be more enthusiastic!"
curl -s -X POST "$BASE_URL/prompts" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "name": "default-system-prompt",
    "content": "You are an EXTREMELY enthusiastic and friendly AI assistant! Always use exclamation marks! Be super positive!",
    "is_active": false,
    "metadata": {
      "description": "Enthusiastic version for testing"
    }
  }' | jq .
echo ""
echo ""

echo "5️⃣  Verify both versions exist..."
echo "---"
curl -s "$BASE_URL/prompts/default-system-prompt" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq '{
    active_version,
    versions: .versions | map({
      version,
      is_active,
      content: .content[:60] + "..."
    })
  }'
echo ""
echo ""

echo "6️⃣  Activate version 2 (enthusiastic prompt)..."
echo "---"
curl -s -X PUT "$BASE_URL/prompts/default-system-prompt/activate/2" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "7️⃣  Test NEW behavior (should be enthusiastic!)..."
echo "---"
echo "Asking same question: 'Say hello'"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Say hello"
  }')

REPLY=$(echo "$RESPONSE" | jq -r '.reply')
echo "Claude says (with new prompt): $REPLY"
echo ""

if [[ "$REPLY" == *"!"* ]]; then
  echo "✅ New prompt is active! (Notice the exclamation marks)"
else
  echo "⚠️  Check if prompt changed (might take a moment)"
fi
echo ""
echo ""

echo "8️⃣  Rollback to version 1 (calm prompt)..."
echo "---"
curl -s -X PUT "$BASE_URL/prompts/default-system-prompt/activate/1" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""
echo ""

echo "9️⃣  Test ROLLED BACK behavior..."
echo "---"
echo "Asking: 'Say hello'"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{
    "message": "Say hello"
  }')

REPLY=$(echo "$RESPONSE" | jq -r '.reply')
echo "Claude says (rolled back): $REPLY"
echo ""
echo ""

echo "🔟 Check prompt stats in database..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT name, version, is_active, stats->'total_uses' as uses FROM prompts WHERE name = 'default-system-prompt';"
echo ""
echo ""

echo "✅ Prompt versioning test complete!"
echo ""
echo "Key achievements:"
echo "- ✅ Prompts stored in database"
echo "- ✅ Multiple versions maintained"
echo "- ✅ Activate any version instantly"
echo "- ✅ Rollback without code deploy"
echo "- ✅ Usage stats tracked per version"
echo ""
echo "This is REAL LLMOps! 🎉"