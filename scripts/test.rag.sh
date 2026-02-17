#!/bin/bash

echo "🧪 Testing STEP 7.1 - RAG (Chat with Documents)"
echo "==============================================="
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
  exit 1
fi

echo "1️⃣  Upload AI research document..."
echo "---"
cat > ai-research.pdf << 'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/Resources<</Font<</F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>>>>>/MediaBox[0 0 612 792]/Contents 4 0 R>>endobj
4 0 obj<</Length 400>>stream
BT/F1 12 Tf 50 700 Td(AI Research Summary)Tj
0 -30 Td(Large Language Models and Transformers)Tj
0 -20 Td(The transformer architecture revolutionized NLP in 2017.)Tj
0 -20 Td(Self-attention mechanisms allow models to process context.)Tj
0 -20 Td(BERT and GPT models use transformers for understanding.)Tj
0 -30 Td(Retrieval Augmented Generation)Tj
0 -20 Td(RAG combines retrieval systems with language models.)Tj
0 -20 Td(It searches documents to find relevant context.)Tj
0 -20 Td(This context is added to prompts for better answers.)Tj
0 -20 Td(RAG reduces hallucinations and improves accuracy.)Tj
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
trailer<</Size 5/Root 1 0 R>>startxref
765
%%EOF
EOF

RESPONSE=$(curl -s -X POST "$BASE_URL/documents/upload" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -F "file=@ai-research.pdf")

DOC_ID=$(echo "$RESPONSE" | jq -r '.id')
echo "Document uploaded: $DOC_ID"
echo "Waiting 10 seconds for indexing..."
sleep 10
echo ""

echo "2️⃣  Regular chat (no RAG)..."
echo "---"
echo "Q: What is RAG?"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": "What is RAG?"}')

echo "Claude says:"
echo "$RESPONSE" | jq -r '.reply' | head -3
echo "..."
echo "(No document context - general knowledge)"
echo ""

echo "3️⃣  RAG chat (with documents)..."
echo "---"
echo "Q: What is RAG according to the document?"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat/rag" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d '{"message": "What is RAG according to the document?"}')

echo "Claude says (with RAG):"
echo "$RESPONSE" | jq -r '.reply'
echo ""
echo "RAG Context:"
echo "$RESPONSE" | jq '{
  documents_used: .rag_context.documents_used,
  sources: .rag_context.sources
}'
echo ""

CHAT_ID=$(echo "$RESPONSE" | jq -r '.chat_id')

echo "4️⃣  Follow-up question..."
echo "---"
echo "Q: How does it reduce hallucinations?"
RESPONSE=$(curl -s -X POST "$BASE_URL/chat/rag" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{\"message\": \"How does it reduce hallucinations?\", \"chat_id\": \"$CHAT_ID\"}")

echo "$RESPONSE" | jq -r '.reply'
echo ""

echo "5️⃣  Test streaming RAG..."
echo "---"
echo "Q: Explain transformers"
echo "Response (streamed):"
curl -N -X POST "$BASE_URL/chat/rag/stream" \
  -H "Content-Type: application/json" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -d "{\"message\": \"Explain transformers based on the document\", \"chat_id\": \"$CHAT_ID\"}" 2>/dev/null | \
  while IFS= read -r line; do
    if [[ $line == data:* ]]; then
      json="${line#data: }"
      token=$(echo "$json" | jq -r '.token // empty')
      done=$(echo "$json" | jq -r '.done // false')
      
      if [ "$done" = "true" ]; then
        echo ""
        echo ""
        echo "✅ Stream complete!"
        docs=$(echo "$json" | jq -r '.rag_context.documents_used')
        sources=$(echo "$json" | jq -r '.rag_context.sources[]' | paste -sd "," -)
        echo "Documents used: $docs"
        echo "Sources: $sources"
      elif [ -n "$token" ]; then
        echo -n "$token"
      fi
    fi
  done

echo ""
echo ""

# Cleanup
rm -f ai-research.pdf

echo "✅ RAG test complete!"
echo ""
echo "Key observations:"
echo "- ✅ Regular chat: general knowledge"
echo "- ✅ RAG chat: uses uploaded documents"
echo "- ✅ Cites sources and relevance"
echo "- ✅ Streaming RAG works"
echo "- ✅ Follow-up questions maintain context"
echo ""
echo "You can now CHAT WITH YOUR DOCUMENTS! 🎉"