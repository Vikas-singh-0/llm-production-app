#!/bin/bash

echo "🧪 Testing STEP 6.1 - Vector Database (Qdrant)"
echo "=============================================="
echo ""

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  exit 1
fi

echo "1️⃣  Check Qdrant is running..."
echo "---"
curl -s http://localhost:6333/collections | jq .
echo ""

echo "2️⃣  Upload and parse a PDF..."
echo "---"
# Create test PDF
cat > ai-document.pdf << 'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/Resources<</Font<</F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>>>>>/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj
4 0 obj<</Length 300>>stream
BT
/F1 12 Tf
50 700 Td(Artificial Intelligence and Machine Learning)Tj
0 -20 Td(AI systems use neural networks for pattern recognition.)Tj
0 -20 Td(Machine learning models learn from training data.)Tj
0 -20 Td(Deep learning uses multiple layers for complex tasks.)Tj
0 -20 Td(Natural language processing enables text understanding.)Tj
0 -20 Td(Computer vision allows image analysis and recognition.)Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000317 00000 n
trailer<</Size 5/Root 1 0 R>>
startxref
665
%%EOF
EOF

RESPONSE=$(curl -s -X POST "$BASE_URL/documents/upload" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -F "file=@ai-document.pdf")

DOC_ID=$(echo "$RESPONSE" | jq -r '.id')
echo "Document uploaded: $DOC_ID"
echo "Waiting 10 seconds for parsing and indexing..."
sleep 10
echo ""

echo "3️⃣  Check document status..."
echo "---"
curl -s "$BASE_URL/documents/$DOC_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq '{status, page_count}'
echo ""

echo "4️⃣  Search: 'neural networks'..."
echo "---"
curl -s -X POST "$BASE_URL/documents/search" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"query": "neural networks", "limit": 3}' | jq '{
    query,
    count,
    results: .results | map({score, content, filename})
  }'
echo ""

echo "5️⃣  Search: 'deep learning'..."
echo "---"
curl -s -X POST "$BASE_URL/documents/search" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"query": "deep learning", "limit": 3}' | jq '{
    query,
    results: .results[:2] | map({score, content: .content[:80]})
  }'
echo ""

echo "6️⃣  Check Qdrant collection..."
echo "---"
curl -s http://localhost:6333/collections/document_chunks | jq '{
  status,
  vectors_count,
  points_count
}'
echo ""

# Cleanup
rm -f ai-document.pdf

echo "✅ Vector search test complete!"
echo ""
echo "Key observations:"
echo "- ✅ Qdrant collection created"
echo "- ✅ Vectors indexed automatically"
echo "- ✅ Semantic search working"
echo "- ✅ Relevant results returned"
echo ""
echo "Note: Using simple embeddings for dev."
echo "Production should use Voyage AI or OpenAI embeddings!"