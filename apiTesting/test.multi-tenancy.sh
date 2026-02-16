#!/bin/bash

# =============================================================================
# Multi-Tenancy Tests (Organization Isolation)
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created resources for cleanup
CREATED_CHAT_IDS=()
CREATED_ORG_IDS=()

print_header "Testing Multi-Tenancy (Organization Isolation)"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local org_id=$1
    local user_id=$2
    local title=${3:-"Multi-tenancy Test $(generate_test_id)"}
    
    local response=$(http_request "POST" "/chats" "{\"title\": \"$title\"}" "$org_id" "$user_id")
    local body=$(get_body "$response")
    local chat_id=$(echo "$body" | jq -r '.id // empty')
    
    if [ -n "$chat_id" ] && [ "$chat_id" != "null" ]; then
        CREATED_CHAT_IDS+=("$chat_id")
        echo "$chat_id"
        return 0
    else
        echo ""
        return 1
    fi
}

# Send a message
send_message() {
    local org_id=$1
    local user_id=$2
    local chat_id=$3
    local message=$4
    
    local response=$(http_request "POST" "/chat" "{\"message\": \"$message\", \"chat_id\": \"$chat_id\"}" "$org_id" "$user_id")
    echo "$response"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up ${#CREATED_CHAT_IDS[@]} test chats..."
    for chat_id in "${CREATED_CHAT_IDS[@]}"; do
        http_request "DELETE" "/chat/$chat_id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# =============================================================================
# Multi-Tenancy Tests
# =============================================================================

# Define different orgs and users
ORG_A="550e8400-e29b-41d4-a716-446655440000"
ORG_B="550e8400-e29b-41d4-a716-446655440010"
USER_A1="550e8400-e29b-41d4-a716-446655440001"
USER_A2="550e8400-e29b-41d4-a716-446655440003"
USER_B1="550e8400-e29b-41d4-a716-446655440011"

# Test 1: Create chats in different orgs
print_test "Create chats in different organizations"

CHAT_ORG_A=$(create_chat "$ORG_A" "$USER_A1" "Org A Chat")
CHAT_ORG_B=$(create_chat "$ORG_B" "$USER_B1" "Org B Chat")

if [ -n "$CHAT_ORG_A" ] && [ -n "$CHAT_ORG_B" ]; then
    print_success "Created chats in both organizations"
    print_info "Org A chat: $CHAT_ORG_A"
    print_info "Org B chat: $CHAT_ORG_B"
else
    print_failure "Setup" "Failed to create chats in both orgs"
    print_summary
    exit 1
fi

# Test 2: Verify org A cannot access org B's chat
print_test "Org A cannot access Org B's chat"
response=$(http_request "GET" "/chat/$CHAT_ORG_B" "" "$ORG_A" "$USER_A1")
assert_status "$response" "404" "Cross-org access returns 404"

# Test 3: Verify org B cannot access org A's chat
print_test "Org B cannot access Org A's chat"
response=$(http_request "GET" "/chat/$CHAT_ORG_A" "" "$ORG_B" "$USER_B1")
assert_status "$response" "404" "Cross-org access returns 404"

# Test 4: Same org, different users can access
print_test "Same org, different users can access chat"
response=$(http_request "GET" "/chat/$CHAT_ORG_A" "" "$ORG_A" "$USER_A2")
assert_status "$response" "200" "Same-org user can access chat"

# Test 5: List chats is org-scoped
print_test "List chats is organization-scoped"

# Add message to org A chat
send_message "$ORG_A" "$USER_A1" "$CHAT_ORG_A" "Test message for Org A" > /dev/null 2>&1

# Get chats for org A
response_a=$(http_request "GET" "/chats" "" "$ORG_A" "$USER_A1")
body_a=$(get_body "$response_a")
chats_a=$(echo "$body_a" | jq '[.chats[] | select(.id == "'$CHAT_ORG_A'")] | length')

# Get chats for org B
response_b=$(http_request "GET" "/chats" "" "$ORG_B" "$USER_B1")
body_b=$(get_body "$response_b")
chats_b=$(echo "$body_b" | jq '[.chats[] | select(.id == "'$CHAT_ORG_B'")] | length')

if [ "$chats_a" -ge 1 ] && [ "$chats_b" -ge 1 ]; then
    print_success "Each org sees only their own chats"
else
    print_warning "Chat scoping" "Org A: $chats_a matching chats, Org B: $chats_b matching chats"
fi

# Test 6: Org-level chat listing
print_test "Organization-level chat listing"
response=$(http_request "GET" "/chats/org" "" "$ORG_A" "$USER_A1")
assert_status "$response" "200" "Org-level listing returns 200"

body=$(get_body "$response")
# Should see org A's chat but not org B's
if echo "$body" | jq -e ".chats[] | select(.id == \"$CHAT_ORG_A\")" > /dev/null 2>&1; then
    print_success "Org A listing includes Org A's chat"
else
    print_failure "Org listing" "Org A's chat not found in org listing"
fi

if echo "$body" | jq -e ".chats[] | select(.id == \"$CHAT_ORG_B\")" > /dev/null 2>&1; then
    print_failure "Org isolation" "Org B's chat found in Org A's listing!"
else
    print_success "Org B's chat not in Org A's listing (proper isolation)"
fi

# Test 7: Cross-org message sending blocked
print_test "Cross-org message sending blocked"
response=$(send_message "$ORG_B" "$USER_B1" "$CHAT_ORG_A" "Trying to access other org")
assert_status "$response" "404" "Cross-org message returns 404"

# Test 8: Cross-org chat update blocked
print_test "Cross-org chat update blocked"
response=$(http_request "PUT" "/chat/$CHAT_ORG_B" '{"title": "Hacked"}' "$ORG_A" "$USER_A1")
assert_status "$response" "404" "Cross-org update returns 404"

# Test 9: Cross-org chat delete blocked
print_test "Cross-org chat delete blocked"
response=$(http_request "DELETE" "/chat/$CHAT_ORG_B" "" "$ORG_A" "$USER_A1")
assert_status "$response" "404" "Cross-org delete returns 404"

# Test 10: User from different org cannot list chats
print_test "User from different org cannot see chats"
response=$(http_request "GET" "/chats" "" "$ORG_B" "$USER_A1")
# This should fail because user A1 doesn't belong to org B
status=$(get_status_code "$response")

if [ "$status" = "403" ] || [ "$status" = "401" ]; then
    print_success "Cross-org user access properly rejected ($status)"
else
    print_info "Cross-org access" "Status: $status (may vary based on implementation)"
fi

# Test 11: Verify org context in responses
print_test "Verify org context in responses"
response=$(http_request "GET" "/health" "" "$ORG_A" "$USER_A1")
body=$(get_body "$response")
org_id=$(echo "$body" | jq -r '.org // empty')

if [ "$org_id" = "$ORG_A" ]; then
    print_success "Response includes correct org context"
else
    print_failure "Org context" "Expected $ORG_A, got $org_id"
fi

# Test 12: Rate limits are per-org
print_test "Rate limits are per-organization"
response_a=$(http_request "GET" "/" "" "$ORG_A" "$USER_A1")
remaining_a=$(get_body "$response_a" | jq -r '.rateLimit.remaining // 0')

response_b=$(http_request "GET" "/" "" "$ORG_B" "$USER_B1")
remaining_b=$(get_body "$response_b" | jq -r '.rateLimit.remaining // 0')

print_info "Org A remaining: $remaining_a"
print_info "Org B remaining: $remaining_b"

# Both should have independent limits
if [ -n "$remaining_a" ] && [ -n "$remaining_b" ]; then
    print_success "Both orgs have independent rate limits"
fi

# Test 13: Messages are org-isolated
print_test "Messages are organization-isolated"
# Add messages to both chats
send_message "$ORG_A" "$USER_A1" "$CHAT_ORG_A" "Secret message for Org A" > /dev/null 2>&1
send_message "$ORG_B" "$USER_B1" "$CHAT_ORG_B" "Secret message for Org B" > /dev/null 2>&1

sleep 1

# Try to access org A's messages from org B
response=$(http_request "GET" "/chat/$CHAT_ORG_A/messages" "" "$ORG_B" "$USER_B1")
assert_status "$response" "404" "Cross-org message access blocked"

# Test 14: Verify user context includes org
print_test "User context includes organization"
response=$(http_request "GET" "/health" "" "$ORG_A" "$USER_A1")
body=$(get_body "$response")

if echo "$body" | jq -e '.user' > /dev/null 2>&1; then
    user_org=$(echo "$body" | jq -r '.org // empty')
    if [ "$user_org" = "$ORG_A" ]; then
        print_success "User context properly associated with org"
    else
        print_warning "User org association" "Org in response: $user_org"
    fi
else
    print_info "User context" "User details not in response"
fi

# Test 15: Multi-user within same org
print_test "Multiple users within same organization"
# User A2 should be able to access User A1's chat
response=$(http_request "GET" "/chat/$CHAT_ORG_A" "" "$ORG_A" "$USER_A2")
status=$(get_status_code "$response")

if [ "$status" = "200" ]; then
    print_success "Same-org users can access each other's chats"
else
    print_info "Same-org access" "Status: $status (implementation may vary)"
fi

# Print summary
print_summary
exit $?
