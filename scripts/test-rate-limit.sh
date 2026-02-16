 curl -s -X POST http://localhost:3000/chat \
    -H "Content-Type: application/json" \
    -H "x-org-id: 00000000-0000-0000-0000-000000000001" \
    -H "x-user-id: 27bc8096-2f47-4eef-8655-42cef0885f7a" \
    -d "{\"chat_id\":\"649d5de5-6487-4ffd-b2c2-3c0d45b97e5e\",\"message\":\"Message $i: We are discussing LLM memory, summarization, and system architecture.\"}" > /dev/null

curl -s -X POST http://localhost:3000/chat \
  -H "Content-Type: application/json" \
    -H "x-org-id: 00000000-0000-0000-0000-000000000001" \
    -H "x-user-id: 27bc8096-2f47-4eef-8655-42cef0885f7a" \
  -d '{"chat_id":"649d5de5-6487-4ffd-b2c2-3c0d45b97e5e","message":"Summarize everything we discussed so far in 5 bullet points."}' | jq




#!/bin/bash

echo "🧪 Testing STEP 1.2 - Rate Limiting & Abuse Safety"
echo "==================================================="
echo ""

BASE_URL="http://localhost:3000"

# You'll need to replace these with actual values from your database
ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  echo ""
  echo "Usage: ./test-rate-limit.sh <ORG_ID> <USER_ID>"
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

echo "1️⃣  Testing /health (no rate limit)..."
echo "---"
curl -s "$BASE_URL/health" | jq -r '.services.redis'
echo ""
echo ""

echo "2️⃣  Making 5 requests quickly (should succeed)..."
echo "---"
for i in {1..5}; do
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "x-org-id: $ORG_ID" \
    -H "x-user-id: $USER_ID" \
    "$BASE_URL/health")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  REMAINING=$(echo "$RESPONSE" | head -n-1 | jq -r '.services.redis // empty')
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ Request $i: OK"
  else
    echo "  ❌ Request $i: HTTP $HTTP_CODE"
  fi
done
echo ""
echo ""

echo "3️⃣  Rapid fire - 105 requests (should hit rate limit)..."
echo "---"
SUCCESS=0
RATE_LIMITED=0

for i in {1..105}; do
  HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
    -H "x-org-id: $ORG_ID" \
    -H "x-user-id: $USER_ID" \
    "$BASE_URL")
  
  if [ "$HTTP_CODE" = "200" ]; then
    ((SUCCESS++))
  elif [ "$HTTP_CODE" = "429" ]; then
    ((RATE_LIMITED++))
    if [ $RATE_LIMITED -eq 1 ]; then
      echo "  🚫 First rate limit hit at request $i"
    fi
  fi
  
  # Show progress every 20 requests
  if [ $((i % 20)) -eq 0 ]; then
    echo "  Progress: $i/105 (Success: $SUCCESS, Rate Limited: $RATE_LIMITED)"
  fi
done

echo ""
echo "Final results:"
echo "  ✅ Successful:   $SUCCESS"
echo "  🚫 Rate limited: $RATE_LIMITED"
echo ""

if [ $RATE_LIMITED -gt 0 ]; then
  echo "✅ Rate limiting is working!"
else
  echo "⚠️  No rate limiting detected (config may need adjustment)"
fi
echo ""

echo "4️⃣  Check rate limit headers..."
echo "---"
RESPONSE=$(curl -s -i \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  "$BASE_URL" | grep -i "x-ratelimit")

if [ -n "$RESPONSE" ]; then
  echo "$RESPONSE"
else
  echo "No rate limit headers found"
fi
echo ""

echo "5️⃣  Wait 3 seconds for token refill..."
echo "---"
sleep 3
echo "Tokens should have refilled (~30 tokens at 10/sec)"
echo ""

echo "6️⃣  Test after waiting..."
echo "---"
RESPONSE=$(curl -s -i \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  "$BASE_URL")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP" | awk '{print $2}')
echo "HTTP Status: $HTTP_CODE"

REMAINING=$(echo "$RESPONSE" | grep -i "x-ratelimit-remaining" | awk '{print $2}' | tr -d '\r')
echo "Remaining tokens: $REMAINING"
echo ""

echo "✅ Rate limiting test complete!"
echo ""
echo "Key observations:"
echo "- Rate limit: 100 tokens (burst capacity)"
echo "- Refill rate: 10 tokens/second"
echo "- After burst, sustained rate is 10 req/sec"
echo "- Tokens refill even when idle"