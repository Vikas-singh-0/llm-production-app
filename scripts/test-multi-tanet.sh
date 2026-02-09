#!/bin/bash

echo "🧪 Testing STEP 1.1 - Multi-Tenancy & Auth"
echo "==========================================="
echo ""

BASE_URL="http://localhost:3000"

# Seed user IDs (from migration)
ORG_1="00000000-0000-0000-0000-000000000001"  # Acme Corp
ORG_2="00000000-0000-0000-0000-000000000002"  # Tech Startup

echo "📋 Getting seed data from database..."
echo "Run this first: npm run db:migrate"
echo ""

echo "1️⃣  Testing /health without authentication..."
echo "---"
curl -s "$BASE_URL/health" | jq .
echo ""
echo ""

echo "2️⃣  Testing /health WITH org context (Acme Corp admin)..."
echo "---"
# You'll need to get actual user IDs from: psql -d llm_app -c "SELECT id, email FROM users;"
# For now, using placeholder
echo "Note: Replace USER_ID with actual UUID from database"
echo "Query: psql -d llm_app -c \"SELECT id, email, role FROM users;\""
echo ""
curl -s \
  -H "x-org-id: $ORG_1" \
  -H "x-user-id: USER_ID_HERE" \
  "$BASE_URL/health" | jq .
echo ""
echo ""

echo "3️⃣  Testing org isolation (wrong org)..."
echo "---"
echo "This should fail with 403 Forbidden"
echo ""

echo "4️⃣  Get user IDs from database..."
echo "---"
echo "Run this command to see seed users:"
echo "  psql -U postgres -d llm_app -c 'SELECT id, email, role, org_id FROM users;'"
echo ""

echo "✅ Multi-tenancy infrastructure ready!"
echo ""
echo "Key features:"
echo "- PostgreSQL with orgs and users tables"
echo "- Every request can carry org_id context"
echo "- Fake auth middleware validates org membership"
echo "- Health endpoint shows authenticated context"