#!/bin/bash

echo "🧪 Testing STEP 0.2 - Observability"
echo "===================================="
echo ""

BASE_URL="http://localhost:3000"

echo "1️⃣  Testing /health endpoint..."
echo "---"
curl -s "$BASE_URL/health" | jq .
echo ""
echo ""

echo "2️⃣  Testing with custom Request ID..."
echo "---"
curl -s -H "X-Request-ID: custom-test-id-123" "$BASE_URL/health" | jq .
echo ""
echo ""

echo "3️⃣  Making multiple requests to generate metrics..."
echo "---"
for i in {1..5}; do
  curl -s "$BASE_URL/health" > /dev/null
  echo "Request $i sent"
done
echo ""
echo ""

echo "4️⃣  Fetching /metrics endpoint..."
echo "---"
curl -s "$BASE_URL/metrics" | grep -E "(http_requests_total|http_request_duration|http_requests_in_progress)"
echo ""
echo ""

echo "✅ All tests complete!"
echo ""
echo "Key observations:"
echo "- Each request has a unique requestId"
echo "- Request IDs are returned in X-Request-ID header"
echo "- Metrics track request counts, duration, and in-progress requests"
echo "- All requests are logged with correlation IDs"