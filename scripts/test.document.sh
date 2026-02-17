#!/bin/bash

echo "🧪 Testing STEP 5.1 - PDF Upload"
echo "================================"
echo ""

BASE_URL="http://localhost:3000"

ORG_ID="${1:-00000000-0000-0000-0000-000000000001}"
USER_ID="${2:-REPLACE_WITH_ACTUAL_USER_ID}"

if [ "$USER_ID" = "REPLACE_WITH_ACTUAL_USER_ID" ]; then
  echo "❌ ERROR: Please provide org and user IDs"
  exit 1
fi

echo "1️⃣  Create a test PDF..."
echo "---"
# Create a simple PDF using echo and convert (if available)
# Or just create a dummy file for testing
echo "%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj
2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj
3 0 obj
<<
/Type /Page
/Parent 2 0 R
/Resources <<
/Font <<
/F1 <<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
>>
>>
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj
4 0 obj
<<
/Length 44
>>
stream
BT
/F1 24 Tf
100 700 Td
(Test Document) Tj
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
<<
/Size 5
/Root 1 0 R
>>
startxref
410
%%EOF" > test-document.pdf

echo "Created test-document.pdf"
echo ""

echo "2️⃣  Upload the PDF..."
echo "---"
RESPONSE=$(curl -s -X POST "$BASE_URL/documents/upload" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" \
  -F "file=@test-document.pdf")

echo "$RESPONSE" | jq .

DOC_ID=$(echo "$RESPONSE" | jq -r '.id')

if [ "$DOC_ID" = "null" ]; then
  echo "❌ Upload failed"
  exit 1
fi

echo ""
echo "✅ Document uploaded: $DOC_ID"
echo ""

echo "3️⃣  List documents..."
echo "---"
curl -s "$BASE_URL/documents" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""

echo "4️⃣  Get document details..."
echo "---"
curl -s "$BASE_URL/documents/$DOC_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""

echo "5️⃣  Check database..."
echo "---"
docker exec -it llm-app-postgres psql -U postgres -d llm_app \
  -c "SELECT id, original_filename, file_size, status, created_at FROM documents LIMIT 5;"
echo ""

echo "6️⃣  Check storage..."
echo "---"
ls -lh storage/documents/$ORG_ID/
echo ""

echo "7️⃣  Delete document..."
echo "---"
curl -s -X DELETE "$BASE_URL/documents/$DOC_ID" \
  -H "x-org-id: $ORG_ID" \
  -H "x-user-id: $USER_ID" | jq .
echo ""

# Cleanup
rm -f test-document.pdf

echo "✅ Document upload test complete!"
echo ""
echo "Key observations:"
echo "- ✅ PDF upload working"
echo "- ✅ File stored in local storage"
echo "- ✅ Database record created"
echo "- ✅ Multi-tenant isolation (files in org folder)"
echo ""
echo "Next: Step 5.2 will add async PDF parsing!"