#!/bin/bash

# =============================================================================
# Token Usage Tracking Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

print_header "Testing Token Usage Tracking"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local title=${1:-"Token Test $(generate_test_id)"}
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

# Send a message and return full response
send_message() {
    local chat_id=$1
    local message=$2
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
# Token Usage Tests
# =============================================================================

# Test 1: Create chat for token tests
print_test "Create chat for token tests"
TOKEN_CHAT_ID=$(create_chat "Token Tracking Test")
if [ -n "$TOKEN_CHAT_ID" ]; then
    print_success "Created chat: $TOKEN_CHAT_ID"
else
    print_failure "Setup" "Failed to create chat"
    print_summary
    exit 1
fi

# Test 2: Verify token usage in response
print_test "Token usage in chat response"
response=$(send_message "$TOKEN_CHAT_ID" "Hello, how are you?")
assert_status "$response" "200" "Message sent successfully"

body=$(get_body "$response")

# Check all token fields exist
if echo "$body" | jq -e '.usage.input_tokens' > /dev/null 2>&1; then
    input_tokens=$(echo "$body" | jq -r '.usage.input_tokens')
    print_success "Input tokens present: $input_tokens"
else
    print_failure "Input tokens" "Field missing in response"
fi

if echo "$body" | jq -e '.usage.output_tokens' > /dev/null 2>&1; then
    output_tokens=$(echo "$body" | jq -r '.usage.output_tokens')
    print_success "Output tokens present: $output_tokens"
else
    print_failure "Output tokens" "Field missing in response"
fi

if echo "$body" | jq -e '.usage.total_tokens' > /dev/null 2>&1; then
    total_tokens=$(echo "$body" | jq -r '.usage.total_tokens')
    print_success "Total tokens present: $total_tokens"
else
    print_failure "Total tokens" "Field missing in response"
fi

# Test 3: Token calculation accuracy
print_test "Token calculation accuracy"
response=$(send_message "$TOKEN_CHAT_ID" "Testing token calculation accuracy")
body=$(get_body "$response")

input=$(echo "$body" | jq -r '.usage.input_tokens // 0')
output=$(echo "$body" | jq -r '.usage.output_tokens // 0')
total=$(echo "$body" | jq -r '.usage.total_tokens // 0')

calculated_total=$((input + output))

# Allow small variance (1-2 tokens) due to estimation differences
if [ "$total" -eq "$calculated_total" ] || [ "$total" -eq $((calculated_total + 1)) ] || [ "$total" -eq $((calculated_total - 1)) ]; then
    print_success "Token calculation accurate: $input + $output ≈ $total"
else
    print_warning "Token calculation" "Expected ~$calculated_total, got $total"
fi

# Test 4: Token usage with different message lengths
print_test "Token usage scales with message length"

# Short message
response1=$(send_message "$TOKEN_CHAT_ID" "Hi")
body1=$(get_body "$response1")
tokens1=$(echo "$body1" | jq -r '.usage.input_tokens // 0')

# Medium message
response2=$(send_message "$TOKEN_CHAT_ID" "This is a medium length message for testing token estimation")
body2=$(get_body "$response2")
tokens2=$(echo "$body2" | jq -r '.usage.input_tokens // 0')

# Long message
long_msg="This is a significantly longer message that should consume more tokens than the previous messages combined. $(generate_long_message 500)"
response3=$(send_message "$TOKEN_CHAT_ID" "$long_msg")
body3=$(get_body "$response3")
tokens3=$(echo "$body3" | jq -r '.usage.input_tokens // 0')

print_info "Short message: $tokens1 tokens"
print_info "Medium message: $tokens2 tokens"
print_info "Long message: $tokens3 tokens"

if [ "$tokens3" -gt "$tokens2" ] && [ "$tokens2" -gt "$tokens1" ]; then
    print_success "Token usage scales correctly with message length"
else
    print_warning "Token scaling" "Token scaling may not be linear"
fi

# Test 5: Token tracking in database
print_test "Token tracking in database (via messages endpoint)"
sleep 2

response=$(http_request "GET" "/chat/$TOKEN_CHAT_ID/messages" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")

# Check if messages have token_count field
if echo "$body" | jq -e '.messages[0].token_count' > /dev/null 2>&1; then
    print_success "Messages include token_count field"
    
    # Count messages with token_count
    with_tokens=$(echo "$body" | jq '[.messages[] | select(.token_count != null)] | length')
    total_msgs=$(echo "$body" | jq '.messages | length')
    
    print_info "$with_tokens/$total_msgs messages have token_count"
    
    if [ "$with_tokens" -gt 0 ]; then
        print_success "Token counts stored in database"
    else
        print_warning "Token storage" "No token counts found in messages"
    fi
else
    print_failure "Token storage" "token_count field missing in messages"
fi

# Test 6: Streaming token usage
print_test "Token usage in streaming responses"
STREAM_TOKEN_CHAT=$(create_chat "Streaming Token Test")

if [ -n "$STREAM_TOKEN_CHAT" ]; then
    response=$(curl -s -N \
        -X POST \
        -H "Content-Type: application/json" \
        -H "x-org-id: $DEFAULT_ORG_ID" \
        -H "x-user-id: $DEFAULT_USER_ID" \
        -d "{\"message\": \"Count to five slowly\", \"chat_id\": \"$STREAM_TOKEN_CHAT\"}" \
        "${BASE_URL}/chat/stream" \
        -w "\n%{http_code}" \
        --max-time 30)
    
    body=$(echo "$response" | sed '$d')
    
    # Check for usage in completion event
    if echo "$body" | grep -q '"usage"'; then
        print_success "Streaming includes token usage"
        
        # Extract usage from completion event
        completion_event=$(echo "$body" | grep '"done":true' | tail -1)
        if [ -n "$completion_event" ]; then
            usage_data=$(echo "$completion_event" | sed 's/^data: //' | jq -r '.usage // empty')
            if [ -n "$usage_data" ] && [ "$usage_data" != "null" ]; then
                stream_input=$(echo "$usage_data" | jq -r '.input_tokens // 0')
                stream_output=$(echo "$usage_data" | jq -r '.output_tokens // 0')
                stream_total=$(echo "$usage_data" | jq -r '.total_tokens // 0')
                
                print_info "Streaming tokens - Input: $stream_input, Output: $stream_output, Total: $stream_total"
                
                if [ "$stream_total" -gt 0 ]; then
                    print_success "Streaming token usage valid"
                fi
            fi
        fi
    else
        print_warning "Streaming usage" "No usage data in streaming response"
    fi
else
    print_warning "Streaming token test" "Could not create chat"
fi

# Test 7: Token usage consistency across requests
print_test "Token usage consistency"
CONSISTENT_CHAT=$(create_chat "Consistency Test")

if [ -n "$CONSISTENT_CHAT" ]; then
    # Send same message twice
    msg1="Test message for consistency check"
    
    response_a=$(send_message "$CONSISTENT_CHAT" "$msg1")
    body_a=$(get_body "$response_a")
    tokens_a=$(echo "$body_a" | jq -r '.usage.input_tokens // 0')
    
    sleep 1
    
    response_b=$(send_message "$CONSISTENT_CHAT" "$msg1")
    body_b=$(get_body "$response_b")
    tokens_b=$(echo "$body_b" | jq -r '.usage.input_tokens // 0')
    
    print_info "First request: $tokens_a tokens"
    print_info "Second request: $tokens_b tokens"
    
    # Should be similar (allow small variance due to context growth)
    diff=$((tokens_b - tokens_a))
    if [ $diff -lt 50 ] && [ $diff -gt -50 ]; then
        print_success "Token usage consistent (diff: $diff)"
    else
        print_info "Token difference" "Diff: $diff (may be due to context growth)"
    fi
else
    print_warning "Consistency test" "Could not create chat"
fi

# Test 8: Very long message token handling
print_test "Very long message token handling"
LONG_MSG_CHAT=$(create_chat "Long Message Token Test")

if [ -n "$LONG_MSG_CHAT" ]; then
    very_long_msg=$(generate_long_message 8000)
    response=$(send_message "$LONG_MSG_CHAT" "$very_long_msg")
    
    status=$(get_status_code "$response")
    
    if [ "$status" = "200" ]; then
        body=$(get_body "$response")
        tokens=$(echo "$body" | jq -r '.usage.input_tokens // 0')
        print_success "Long message handled ($tokens tokens)"
        
        if [ "$tokens" -gt 1000 ]; then
            print_info "Large token count: $tokens"
        fi
    elif [ "$status" = "400" ]; then
        print_info "Long message rejected (may have length limit)"
    else
        print_warning "Long message" "Unexpected status: $status"
    fi
else
    print_warning "Long message test" "Could not create chat"
fi

# Test 9: Token usage in message metadata
print_test "Token usage in message metadata"
sleep 2

response=$(http_request "GET" "/chat/$TOKEN_CHAT_ID/messages?limit=5" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")

# Check for token_count in recent messages
if echo "$body" | jq -e '.messages[] | select(.token_count != null)' > /dev/null 2>&1; then
    # Get first message with token_count
    msg_with_tokens=$(echo "$body" | jq '.messages | map(select(.token_count != null)) | first')
    token_count=$(echo "$msg_with_tokens" | jq -r '.token_count // 0')
    role=$(echo "$msg_with_tokens" | jq -r '.role // "unknown"')
    
    print_success "Message has token_count: $token_count (role: $role)"
else
    print_warning "Message metadata" "No token_count found in message metadata"
fi

# Test 10: Aggregate token usage across conversation
print_test "Aggregate token usage tracking"
sleep 1

response=$(http_request "GET" "/chat/$TOKEN_CHAT_ID/messages" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")

# Calculate total tokens from all messages
total_stored_tokens=$(echo "$body" | jq '[.messages[] | .token_count // 0] | add')

if [ "$total_stored_tokens" -gt 0 ]; then
    print_success "Total stored tokens: $total_stored_tokens"
    print_info "Average per message: $((total_stored_tokens / $(echo "$body" | jq '.messages | length')))"
else
    print_warning "Aggregate tokens" "Could not calculate total stored tokens"
fi

# Print summary
print_summary
exit $?
