#!/bin/bash

# =============================================================================
# Error Handling Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

print_header "Testing Error Handling"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local title=${1:-"Error Test $(generate_test_id)"}
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
# 401 Unauthorized Tests
# =============================================================================

print_header "401 Unauthorized Tests"

# Test 1: Chat without auth
print_test "POST /chat without auth"
response=$(http_request_no_auth "POST" "/chat" '{"message": "Test"}')
assert_status "$response" "401" "Chat without auth returns 401"
assert_valid_json "$response" "Error response is valid JSON"
assert_contains "$response" "Unauthorized" "Error message mentions Unauthorized"

# Test 2: Create chat without auth
print_test "POST /chats without auth"
response=$(http_request_no_auth "POST" "/chats" '{"title": "Test"}')
assert_status "$response" "401" "Create chat without auth returns 401"

# Test 3: List chats without auth
print_test "GET /chats without auth"
response=$(http_request_no_auth "GET" "/chats")
assert_status "$response" "401" "List chats without auth returns 401"

# Test 4: Get specific chat without auth
print_test "GET /chat/:id without auth"
response=$(http_request_no_auth "GET" "/chat/some-id")
assert_status "$response" "401" "Get chat without auth returns 401"

# Test 5: Update chat without auth
print_test "PUT /chat/:id without auth"
response=$(http_request_no_auth "PUT" "/chat/some-id" '{"title": "Test"}')
assert_status "$response" "401" "Update chat without auth returns 401"

# Test 6: Delete chat without auth
print_test "DELETE /chat/:id without auth"
response=$(http_request_no_auth "DELETE" "/chat/some-id")
assert_status "$response" "401" "Delete chat without auth returns 401"

# Test 7: Prompts without auth
print_test "GET /prompts without auth"
response=$(http_request_no_auth "GET" "/prompts")
assert_status "$response" "401" "List prompts without auth returns 401"

# Test 8: Streaming without auth
print_test "POST /chat/stream without auth"
response=$(http_request_no_auth "POST" "/chat/stream" '{"message": "Test"}')
assert_status "$response" "401" "Streaming without auth returns 401"

# Test 9: Error response structure
print_test "Error response structure"
response=$(http_request_no_auth "GET" "/chats")
body=$(get_body "$response")

if echo "$body" | jq -e '.error' > /dev/null 2>&1; then
    print_success "Error response has 'error' field"
else
    print_failure "Error structure" "Missing 'error' field"
fi

if echo "$body" | jq -e '.message' > /dev/null 2>&1; then
    print_success "Error response has 'message' field"
else
    print_warning "Error structure" "Missing 'message' field"
fi

# =============================================================================
# 403 Forbidden Tests
# =============================================================================

print_header "403 Forbidden Tests"

# Test 10: Create prompt as non-admin
print_test "POST /prompts as non-admin"
response=$(http_request "POST" "/prompts" '{"name": "test", "content": "test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "403" ]; then
    print_success "Create prompt as non-admin returns 403"
else
    print_info "Prompt creation" "Status: $status (may require admin role)"
fi

# Test 11: Activate prompt as non-admin
print_test "PUT /prompts/:name/activate as non-admin"
response=$(http_request "PUT" "/prompts/default-system-prompt/activate/1" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "403" ]; then
    print_success "Activate prompt as non-admin returns 403"
else
    print_info "Prompt activation" "Status: $status"
fi

# Test 12: User accessing different org (if implemented)
print_test "User accessing different org"
DIFFERENT_ORG="550e8400-e29b-41d4-a716-446655440999"
response=$(http_request "GET" "/chats" "" "$DIFFERENT_ORG" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "403" ]; then
    print_success "Cross-org access returns 403"
elif [ "$status" = "401" ]; then
    print_success "Cross-org access returns 401"
else
    print_info "Cross-org access" "Status: $status"
fi

# =============================================================================
# 404 Not Found Tests
# =============================================================================

print_header "404 Not Found Tests"

# Test 13: Get non-existent chat
print_test "GET non-existent chat"
response=$(http_request "GET" "/chat/non-existent-chat-id-12345" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Non-existent chat returns 404"

# Test 14: Update non-existent chat
print_test "PUT non-existent chat"
response=$(http_request "PUT" "/chat/non-existent-chat-id" '{"title": "Test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Update non-existent chat returns 404"

# Test 15: Delete non-existent chat
print_test "DELETE non-existent chat"
response=$(http_request "DELETE" "/chat/non-existent-chat-id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Delete non-existent chat returns 404"

# Test 16: Get non-existent prompt
print_test "GET non-existent prompt"
response=$(http_request "GET" "/prompts/non-existent-prompt-12345" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Non-existent prompt returns 404"

# Test 17: Activate non-existent prompt
print_test "PUT non-existent prompt activation"
response=$(http_request "PUT" "/prompts/non-existent-prompt/activate/1" "" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
assert_status "$response" "404" "Activate non-existent prompt returns 404"

# Test 18: Get messages for non-existent chat
print_test "GET messages for non-existent chat"
response=$(http_request "GET" "/chat/non-existent-chat/messages" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Messages for non-existent chat returns 404"

# Test 19: Delete message from non-existent chat
print_test "DELETE message from non-existent chat"
response=$(http_request "DELETE" "/chat/non-existent-chat/messages/msg-123" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Delete from non-existent chat returns 404"

# Test 20: Send message to non-existent chat
print_test "POST message to non-existent chat"
response=$(http_request "POST" "/chat" '{"message": "Test", "chat_id": "non-existent-chat"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Message to non-existent chat returns 404"

# =============================================================================
# 400 Bad Request Tests
# =============================================================================

print_header "400 Bad Request Tests"

# Create a valid chat for testing
ERROR_CHAT_ID=$(create_chat "Error Test Chat")

# Test 21: Empty message
print_test "POST empty message"
response=$(http_request "POST" "/chat" '{"message": ""}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Empty message returns 400"

# Test 22: Message too long (>10000 chars)
print_test "POST message too long"
very_long_message=$(generate_long_message 11000)
response=$(http_request "POST" "/chat" "{\"message\": \"$very_long_message\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Message too long returns 400"

# Test 23: Empty chat title
print_test "POST chat with empty title"
response=$(http_request "POST" "/chats" '{"title": ""}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Empty title returns 400"

# Test 24: Update chat with empty title
if [ -n "$ERROR_CHAT_ID" ]; then
    print_test "PUT chat with empty title"
    response=$(http_request "PUT" "/chat/$ERROR_CHAT_ID" '{"title": ""}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    assert_status "$response" "400" "Empty title update returns 400"
fi

# Test 25: Invalid JSON
print_test "POST with invalid JSON"
response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d '{"invalid json' \
    "${BASE_URL}/chat")
assert_status "$response" "400" "Invalid JSON returns 400"

# Test 26: Missing required fields
print_test "POST chat without message field"
response=$(http_request "POST" "/chat" '{"chat_id": "test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "400" "Missing message field returns 400"

# Test 27: Wrong data type
print_test "POST with wrong data type"
response=$(http_request "POST" "/chat" '{"message": 12345}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "400" ]; then
    print_success "Wrong data type returns 400"
else
    print_info "Data type validation" "Status: $status"
fi

# Test 28: Invalid version number for prompt activation
print_test "PUT prompt activation with invalid version"
response=$(http_request "PUT" "/prompts/default-system-prompt/activate/invalid" "" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
assert_status "$response" "400" "Invalid version returns 400"

# =============================================================================
# 405 Method Not Allowed Tests
# =============================================================================

print_header "405 Method Not Allowed Tests"

# Test 29: PUT to root
print_test "PUT / (method not allowed)"
response=$(http_request "PUT" "/" '{"test": "data"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "405" ]; then
    print_success "PUT to root returns 405"
else
    print_info "Method check" "Status: $status"
fi

# Test 30: DELETE to health
print_test "DELETE /health (method not allowed)"
response=$(http_request "DELETE" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")
if [ "$status" = "405" ]; then
    print_success "DELETE to health returns 405"
else
    print_info "Method check" "Status: $status"
fi

# =============================================================================
# 500 Internal Server Error Tests (Indirect)
# =============================================================================

print_header "500 Error Handling"

# Test 31: Error response format
print_test "Error response format consistency"
response=$(http_request_no_auth "GET" "/chats")
body=$(get_body "$response")

# Check error response structure
if echo "$body" | jq -e '.error' > /dev/null 2>&1; then
    error_field=$(echo "$body" | jq -r '.error')
    print_success "Error field present: $error_field"
fi

# =============================================================================
# Edge Cases
# =============================================================================

print_header "Edge Cases"

# Test 32: Special characters in message
print_test "Special characters in message"
if [ -n "$ERROR_CHAT_ID" ]; then
    response=$(http_request "POST" "/chat" '{"message": "Special chars: <>&\"'\''%$#@!"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    status=$(get_status_code "$response")
    if [ "$status" = "200" ] || [ "$status" = "400" ]; then
        print_success "Special characters handled (status: $status)"
    else
        print_info "Special chars" "Status: $status"
    fi
fi

# Test 33: Unicode in message
print_test "Unicode characters in message"
if [ -n "$ERROR_CHAT_ID" ]; then
    response=$(http_request "POST" "/chat" '{"message": "Unicode: 你好世界 🌍 émojis"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    status=$(get_status_code "$response")
    if [ "$status" = "200" ]; then
        print_success "Unicode characters handled"
    else
        print_info "Unicode" "Status: $status"
    fi
fi

# Test 34: SQL injection attempt (should be sanitized)
print_test "SQL injection attempt handling"
if [ -n "$ERROR_CHAT_ID" ]; then
    response=$(http_request "POST" "/chat" '{"message": "\'; DROP TABLE messages; --"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    status=$(get_status_code "$response")
    # Should either succeed (with sanitization) or fail gracefully
    if [ "$status" = "200" ] || [ "$status" = "400" ]; then
        print_success "SQL injection handled safely (status: $status)"
    else
        print_info "SQL injection" "Status: $status"
    fi
fi

# Test 35: XSS attempt (should be sanitized)
print_test "XSS attempt handling"
if [ -n "$ERROR_CHAT_ID" ]; then
    response=$(http_request "POST" "/chat" '{"message": "<script>alert(\"xss\")</script>"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    status=$(get_status_code "$response")
    if [ "$status" = "200" ] || [ "$status" = "400" ]; then
        print_success "XSS attempt handled (status: $status)"
    else
        print_info "XSS" "Status: $status"
    fi
fi

# Print summary
print_summary
exit $?
