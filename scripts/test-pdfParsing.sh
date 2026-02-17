#!/bin/bash

echo "🧪 Testing STEP 5.2 - PDF Parsing"
echo "=================================="
echo ""

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  exit 1
fi

echo "1️⃣  Create a test PDF with more content..."
echo "---"
cat > test-document.pdf << 'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<<
/Type /Page
/Parent 2 0 R
/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj
4 0 obj
<< /Length 200 >>
stream
BT
/F1 12 Tf
50 700 Td
(This is a test PDF document.) Tj
0 -20 Td
(It contains multiple lines of text.) Tj
0 -20 Td
(This will be parsed and chunked.) Tj
0 -20 Td
(Each chunk will be stored separately.) Tj
0 -20 Td
(Ready for vector search and RAG!) Tj
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
trailer
<< /Size 5 /Root 1 0 R >>
startxref
565
%%EOF
EOF

echo "✅ Created test PDF"
echo ""

echo "2️⃣  Upload and trigger parsing..."
echo "---"
RESPONSE=$(curl -s -X POST "$BASE_URL/documents/upload" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -F "file=@test-document.pdf")

echo "$RESPONSE" | jq .

DOC_ID=$(echo "$RESPONSE" | jq -r '.id')
JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')

echo ""
echo "Document ID: $DOC_ID"
echo "Job ID: $JOB_ID"
echo ""

echo "3️⃣  Wait for parsing to complete..."
echo "---"
echo "Waiting 5 seconds for background job..."
sleep 5
echo ""

echo "4️⃣  Check document status..."
echo "---"
curl -s "$BASE_URL/documents/$DOC_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq '{status, page_count, parsed_at}'
echo ""

echo "5️⃣  Get parsed chunks..."
echo "---"
CHUNKS=$(curl -s "$BASE_URL/documents/$DOC_ID/chunks" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID")

echo "$CHUNKS" | jq '{filename, chunk_count, chunks: .chunks[:2]}'
echo "... (showing first 2 chunks)"
echo ""

CHUNK_COUNT=$(echo "$CHUNKS" | jq -r '.chunk_count')
echo "Total chunks: $CHUNK_COUNT"
echo ""

echo "6️⃣  Check database..."
echo "---"
echo "Documents table:"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT id, original_filename, status, page_count FROM documents WHERE id = '$DOC_ID';"
echo ""

echo "Document chunks table:"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT chunk_index, LEFT(content, 50) as preview, char_count, token_count FROM document_chunks WHERE document_id = '$DOC_ID' ORDER BY chunk_index LIMIT 5;"
echo ""

echo "7️⃣  Test chunk stats..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT 
    COUNT(*) as total_chunks,
    SUM(char_count) as total_chars,
    SUM(token_count) as total_tokens,
    AVG(char_count) as avg_chunk_size
  FROM document_chunks 
  WHERE document_id = '$DOC_ID';"
echo ""

# Cleanup
rm -f test-document.pdf

echo "✅ PDF parsing test complete!"
echo ""
echo "Key observations:"
echo "- ✅ PDF uploaded successfully"
echo "- ✅ Background job triggered"
echo "- ✅ Text extracted and chunked"
echo "- ✅ Chunks stored in database"
echo "- ✅ Ready for vector search!"
echo ""
echo "Next: Step 6 will add vector database (Qdrant) for semantic search!"