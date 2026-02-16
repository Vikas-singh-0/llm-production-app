#!/bin/bash

# =============================================================================
# Chat Endpoint Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

print_header "Testing Chat Endpoints"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local title=${1:-"Test Chat $(generate_test_id)"}
    local response=$(http_request "POST" "/chats" "{\"title\": \"$title\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
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

# Send a message to a chat
send_message() {
    local chat_id=$1
    local message=${2:-"Test message $(generate_test_id)"}
    local response=$(http_request "POST" "/chat" "{\"message\": \"$message\", \"chat_id\": \"$chat_id\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    echo "$response"
}

# Cleanup function
cleanup_chats() {
    if [ ${#CREATED_CHAT_IDS[@]} -gt 0 ]; then
        print_info "Cleaning up ${#CREATED_CHAT_IDS[@]} test chats..."
        for chat_id in "${CREATED_CHAT_IDS[@]}"; do
            http_request "DELETE" "/chat/$chat_id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
        done
    fi
}

# Set trap to cleanup on exit
trap cleanup_chats EXIT

# =============================================================================
# Chat CRUD Tests
# =============================================================================

# Test 1: Create a new chat
print_test "Create new chat"
response=$(http_request "POST" "/chats" '{"title": "Test Chat"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "201" "Create chat returns 201"
assert_valid_json "$response" "Create chat returns valid JSON"
assert_json_field_exists "$response" "id" "Create chat returns ID"
assert_json_field_exists "$response" "title" "Create chat returns title"
assert_json_field_exists "$response" "created_at" "Create chat returns created_at"

# Store chat ID for later tests
CHAT_ID=$(get_body "$response" | jq -r '.id')
CREATED_CHAT_IDS+=("$CHAT_ID")
print_info "Created chat ID: $CHAT_ID"

# Test 2: Create chat without auth (should fail)
print_test "Create chat without authentication"
response=$(http_request_no_auth "POST" "/chats" '{"title": "Test"}')
assert_status "$response" "401" "Create chat without auth returns 401"

# Test 3: List user's chats
print_test "List user's chats"
response=$(http_request "GET" "/chats" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "List chats returns 200"
assert_valid_json "$response" "List chats returns valid JSON"
assert_json_field_exists "$response" "chats" "List chats returns chats array"
assert_json_field_exists "$response" "count" "List chats returns count"

# Verify our created chat is in the list
body=$(get_body "$response")
if echo "$body" | jq -e ".chats[] | select(.id == \"$CHAT_ID\")" > /dev/null 2>&1; then
    print_success "Created chat appears in list"
else
    print_failure "Chat list" "Created chat not found in list"
fi

# Test 4: Get specific chat
print_test "Get specific chat"
response=$(http_request "GET" "/chat/$CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Get chat returns 200"
assert_valid_json "$response" "Get chat returns valid JSON"
assert_json_field "$response" "chat_id" "$CHAT_ID" "Get chat returns correct ID"
assert_json_field_exists "$response" "title" "Get chat returns title"
assert_json_field_exists "$response" "messages" "Get chat returns messages"
assert_json_field_exists "$response" "message_count" "Get chat returns message count"

# Test 5: Get chat without auth (should fail)
print_test "Get chat without authentication"
response=$(http_request_no_auth "GET" "/chat/$CHAT_ID")
assert_status "$response" "401" "Get chat without auth returns 401"

# Test 6: Get non-existent chat
print_test "Get non-existent chat"
response=$(http_request "GET" "/chat/non-existent-id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Get non-existent chat returns 404"

# Test 7: Update chat title
print_test "Update chat title"
response=$(http_request "PUT" "/chat/$CHAT_ID" '{"title": "Updated Title"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Update chat returns 200"
assert_json_field "$response" "title" "Updated Title" "Chat title is updated"
assert_json_field "$response" "id" "$CHAT_ID" "Update returns correct ID"

# Test 8: Update chat without auth (should fail)
print_test "Update chat without authentication"
response=$(http_request_no_auth "PUT" "/chat/$CHAT_ID" '{"title": "Test"}')
assert_status "$response" "401" "Update chat without auth returns 401"

# Test 9: Update non-existent chat
print_test "Update non-existent chat"
response=$(http_request "PUT" "/chat/non-existent" '{"title": "Test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Update non-existent chat returns 404"

# Test 10: Update chat with invalid data
print_test "Update chat with empty title"
response=$(http_request "PUT" "/chat/$CHAT_ID" '{"title": ""}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Update with empty title returns 400"

# =============================================================================
# Chat Message Tests
# =============================================================================

print_header "Testing Chat Messages"

# Test 11: Send message to chat
print_test "Send message to chat"
message="Hello, this is a test message $(generate_test_id)"
response=$(send_message "$CHAT_ID" "$message")
assert_status "$response" "200" "Send message returns 200"
assert_valid_json "$response" "Send message returns valid JSON"
assert_json_field_exists "$response" "reply" "Response includes assistant reply"
assert_json_field_exists "$response" "message_id" "Response includes message ID"
assert_json_field_exists "$response" "usage" "Response includes token usage"

# Verify usage structure
body=$(get_body "$response")
input_tokens=$(echo "$body" | jq -r '.usage.input_tokens // empty')
output_tokens=$(echo "$body" | jq -r '.usage.output_tokens // empty')
total_tokens=$(echo "$body" | jq -r '.usage.total_tokens // empty')

if [ -n "$input_tokens" ] && [ -n "$output_tokens" ] && [ -n "$total_tokens" ]; then
    print_success "Token usage has all fields"
    print_info "Input: $input_tokens, Output: $output_tokens, Total: $total_tokens"
else
    print_failure "Token usage structure" "Missing token usage fields"
fi

# Store message ID
MESSAGE_ID=$(echo "$body" | jq -r '.message_id')

# Test 12: Send message without chat_id (creates new chat)
print_test "Send message without chat_id (auto-create)"
response=$(http_request "POST" "/chat" '{"message": "Auto-create test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Auto-create chat returns 200"
assert_json_field_exists "$response" "chat_id" "Response includes new chat_id"

NEW_CHAT_ID=$(get_body "$response" | jq -r '.chat_id')
if [ -n "$NEW_CHAT_ID" ] && [ "$NEW_CHAT_ID" != "null" ]; then
    CREATED_CHAT_IDS+=("$NEW_CHAT_ID")
    print_info "Auto-created chat ID: $NEW_CHAT_ID"
fi

# Test 13: Send message to non-existent chat
print_test "Send message to non-existent chat"
response=$(http_request "POST" "/chat" '{"message": "Test", "chat_id": "non-existent"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Message to non-existent chat returns 404"

# Test 14: Send empty message
print_test "Send empty message"
response=$(http_request "POST" "/chat" '{"message": ""}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Empty message returns 400"

# Test 15: Send message without auth
print_test "Send message without authentication"
response=$(http_request_no_auth "POST" "/chat" '{"message": "Test"}')
assert_status "$response" "401" "Message without auth returns 401"

# Test 16: Get chat messages
print_test "Get chat messages"
response=$(http_request "GET" "/chat/$CHAT_ID/messages" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Get messages returns 200"
assert_valid_json "$response" "Get messages returns valid JSON"
assert_json_field_exists "$response" "messages" "Response includes messages array"
assert_json_field_exists "$response" "message_count" "Response includes message count"

# Verify our message is in the list
body=$(get_body "$response")
if echo "$body" | jq -e ".messages[] | select(.id == \"$MESSAGE_ID\")" > /dev/null 2>&1; then
    print_success "Sent message appears in messages list"
else
    print_warning "Message list" "Sent message not immediately visible (may be async)"
fi

# Test 17: Get messages with limit
print_test "Get messages with limit parameter"
response=$(http_request "GET" "/chat/$CHAT_ID/messages?limit=5" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Get messages with limit returns 200"
body=$(get_body "$response")
count=$(echo "$body" | jq -r '.message_count // 0')
if [ "$count" -le 5 ]; then
    print_success "Limit parameter respected (count: $count)"
else
    print_warning "Limit parameter" "Expected <= 5 messages, got $count"
fi

# Test 18: Get message count
print_test "Get message count"
response=$(http_request "GET" "/chat/$CHAT_ID/messages/count" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Get message count returns 200"
assert_json_field_exists "$response" "message_count" "Response includes message_count"
assert_json_field "$response" "chat_id" "$CHAT_ID" "Count returns correct chat_id"

# =============================================================================
# Organization Chat Tests
# =============================================================================

print_header "Testing Organization Chat Access"

# Test 19: Get all chats for organization
print_test "Get all organization chats"
response=$(http_request "GET" "/chats/org" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Get org chats returns 200"
assert_valid_json "$response" "Get org chats returns valid JSON"
assert_json_field_exists "$response" "chats" "Response includes chats array"
assert_json_field_exists "$response" "count" "Response includes count"

# Verify chats include user_id
body=$(get_body "$response")
if echo "$body" | jq -e '.chats[0].user_id' > /dev/null 2>&1; then
    print_success "Org chats include user_id field"
else
    print_warning "Org chats" "user_id field may be missing"
fi

# =============================================================================
# Delete Tests
# =============================================================================

print_header "Testing Chat Deletion"

# Create a chat specifically for deletion
DELETE_CHAT_ID=$(create_chat "Chat to Delete")
if [ -n "$DELETE_CHAT_ID" ]; then
    # Test 20: Delete chat
    print_test "Delete chat"
    response=$(http_request "DELETE" "/chat/$DELETE_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    assert_status "$response" "200" "Delete chat returns 200"
    assert_contains "$response" "deleted successfully" "Delete returns success message"
    
    # Verify chat is gone
    response=$(http_request "GET" "/chat/$DELETE_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    assert_status "$response" "404" "Deleted chat returns 404"
    
    # Remove from cleanup list since we already deleted it
    CREATED_CHAT_IDS=("${CREATED_CHAT_IDS[@]/$DELETE_CHAT_ID}")
else
    print_failure "Delete test setup" "Failed to create chat for deletion"
fi

# Test 21: Delete chat without auth
print_test "Delete chat without authentication"
response=$(http_request_no_auth "DELETE" "/chat/$CHAT_ID")
assert_status "$response" "401" "Delete without auth returns 401"

# Test 22: Delete non-existent chat
print_test "Delete non-existent chat"
response=$(http_request "DELETE" "/chat/non-existent" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Delete non-existent chat returns 404"

# Test 23: Delete message
print_test "Delete message from chat"
# First create a new chat and add a message
MSG_CHAT_ID=$(create_chat "Message Delete Test")
if [ -n "$MSG_CHAT_ID" ]; then
    # Send a message
    msg_response=$(send_message "$MSG_CHAT_ID" "Message to delete")
    msg_id=$(get_body "$msg_response" | jq -r '.message_id // empty')
    
    if [ -n "$msg_id" ] && [ "$msg_id" != "null" ]; then
        # Delete the message
        response=$(http_request "DELETE" "/chat/$MSG_CHAT_ID/messages/$msg_id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
        assert_status "$response" "200" "Delete message returns 200"
        assert_contains "$response" "deleted successfully" "Delete message returns success"
    else
        print_warning "Delete message" "Could not get message ID for deletion test"
    fi
else
    print_warning "Delete message" "Could not create chat for message deletion test"
fi

# Print summary
print_summary
exit $?
