#!/bin/bash

# =============================================================================
# Summarization Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

print_header "Testing Summarization Features"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local title=${1:-"Summarization Test $(generate_test_id)"}
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

# Send a message
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
# Summarization Trigger Tests
# =============================================================================

# Test 1: Create chat for summarization tests
print_test "Create chat for summarization tests"
SUMMARY_CHAT_ID=$(create_chat "Summarization Trigger Test")
if [ -n "$SUMMARY_CHAT_ID" ]; then
    print_success "Created chat: $SUMMARY_CHAT_ID"
else
    print_failure "Setup" "Failed to create chat"
    print_summary
    exit 1
fi

# Test 2: Trigger summarization with 20+ messages
print_test "Trigger summarization with 20+ messages"
print_info "Sending 22 messages to trigger summarization..."

for i in $(seq 1 22); do
    msg="Discussion point $i: We are building a comprehensive LLM production platform with features like multi-tenancy, rate limiting, and conversation memory management."
    send_message "$SUMMARY_CHAT_ID" "$msg" > /dev/null 2>&1
    sleep 0.3
done

sleep 3

# Check chat state after potential summarization
response=$(http_request "GET" "/chat/$SUMMARY_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
message_count=$(echo "$body" | jq -r '.message_count // 0')

print_info "Messages after batch: $message_count"

# Test 3: Verify conversation continuity after summarization
print_test "Conversation continuity after summarization"
response=$(send_message "$SUMMARY_CHAT_ID" "What have we been discussing in this conversation?")
assert_status "$response" "200" "Query after many messages handled"

body=$(get_body "$response")
reply=$(echo "$body" | jq -r '.reply // empty')

if [ -n "$reply" ] && [ ${#reply} -gt 20 ]; then
    print_success "Assistant provides coherent response after many messages"
    print_info "Response length: ${#reply} chars"
else
    print_warning "Continuity" "Response may be too short or empty"
fi

# Test 4: High token volume test (6000+ tokens)
print_test "High token volume summarization trigger"
TOKEN_CHAT_ID=$(create_chat "High Token Volume Test")

if [ -n "$TOKEN_CHAT_ID" ]; then
    print_info "Sending large messages to exceed 6000 tokens..."
    
    # Send several very large messages
    for i in $(seq 1 8); do
        large_msg="Detailed technical discussion part $i: $(generate_long_message 2000) This is important context for understanding the system architecture and design decisions."
        send_message "$TOKEN_CHAT_ID" "$large_msg" > /dev/null 2>&1
        sleep 0.5
    done
    
    sleep 3
    
    # Verify system still responds
    response=$(send_message "$TOKEN_CHAT_ID" "Can you summarize the technical details we discussed?")
    assert_status "$response" "200" "High token volume request handled"
    
    body=$(get_body "$response")
    usage=$(echo "$body" | jq -r '.usage.total_tokens // 0')
    print_info "Token usage for summary request: $usage"
else
    print_warning "Token volume test" "Could not create chat"
fi

# Test 5: Compression ratio verification
print_test "Verify summarization compression"
# This is indirect - we check if the system handles large contexts efficiently

COMPRESS_CHAT_ID=$(create_chat "Compression Test")
if [ -n "$COMPRESS_CHAT_ID" ]; then
    # Build up a long conversation
    for i in $(seq 1 15); do
        msg="Topic $i: Machine learning concepts including neural networks, deep learning, natural language processing, and their applications in production systems."
        send_message "$COMPRESS_CHAT_ID" "$msg" > /dev/null 2>&1
    done
    
    sleep 2
    
    # Request that would benefit from summary
    start_time=$(date +%s%N)
    response=$(send_message "$COMPRESS_CHAT_ID" "List all the topics we've covered")
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    assert_status "$response" "200" "Context-heavy request processed"
    print_info "Response time: ${duration}ms"
    
    if [ $duration -lt 30000 ]; then
        print_success "Response time reasonable for large context"
    else
        print_warning "Response time" "Took ${duration}ms (may indicate no summary optimization)"
    fi
else
    print_warning "Compression test" "Could not create chat"
fi

# Test 6: Summary persistence test
print_test "Summary persistence across requests"
PERSIST_CHAT_ID=$(create_chat "Persistence Test")

if [ -n "$PERSIST_CHAT_ID" ]; then
    # Build conversation
    for i in $(seq 1 18); do
        send_message "$PERSIST_CHAT_ID" "Point $i: Testing summary persistence in conversation memory system" > /dev/null 2>&1
    done
    
    sleep 2
    
    # First query
    response1=$(send_message "$PERSIST_CHAT_ID" "What is this conversation about?")
    body1=$(get_body "$response1")
    reply1=$(echo "$body1" | jq -r '.reply // empty')
    
    sleep 1
    
    # Second query (should use same summary)
    response2=$(send_message "$PERSIST_CHAT_ID" "Tell me more about it")
    body2=$(get_body "$response2")
    reply2=$(echo "$body2" | jq -r '.reply // empty')
    
    if [ -n "$reply1" ] && [ -n "$reply2" ]; then
        print_success "Multiple queries handled with summary context"
    else
        print_warning "Persistence" "Responses may be incomplete"
    fi
else
    print_warning "Persistence test" "Could not create chat"
fi

# Test 7: Re-summarization prevention (24-hour window)
print_test "Re-summarization prevention"
# This is hard to test directly, but we can verify the system doesn't break

RERUN_CHAT_ID=$(create_chat "Re-summarization Test")
if [ -n "$RERUN_CHAT_ID" ]; then
    # Trigger initial summarization
    for i in $(seq 1 25); do
        send_message "$RERUN_CHAT_ID" "Content $i for initial summary generation in the conversation" > /dev/null 2>&1
    done
    
    sleep 3
    
    # Add a few more messages (should not re-summarize immediately)
    for i in $(seq 26 28); do
        send_message "$RERUN_CHAT_ID" "Additional content $i after summary" > /dev/null 2>&1
    done
    
    sleep 2
    
    # Verify system still works
    response=$(send_message "$RERUN_CHAT_ID" "What's the latest?")
    assert_status "$response" "200" "System stable after potential re-summarization window"
else
    print_warning "Re-summarization test" "Could not create chat"
fi

# Test 8: Summary with streaming
print_test "Summarization with streaming"
STREAM_SUMMARY_CHAT=$(create_chat "Streaming Summary Test")

if [ -n "$STREAM_SUMMARY_CHAT" ]; then
    # Build conversation
    for i in $(seq 1 20); do
        send_message "$STREAM_SUMMARY_CHAT" "Streaming context $i: Testing how summarization works with Server-Sent Events and token streaming" > /dev/null 2>&1
    done
    
    sleep 2
    
    # Test streaming after summarization
    response=$(curl -s -N \
        -X POST \
        -H "Content-Type: application/json" \
        -H "x-org-id: $DEFAULT_ORG_ID" \
        -H "x-user-id: $DEFAULT_USER_ID" \
        -d "{\"message\": \"Summarize our discussion\", \"chat_id\": \"$STREAM_SUMMARY_CHAT\"}" \
        "${BASE_URL}/chat/stream" \
        -w "\n%{http_code}" \
        --max-time 30)
    
    status_code=$(echo "$response" | tail -n1)
    
    if [ "$status_code" = "200" ]; then
        print_success "Streaming works with summarized context"
    else
        print_failure "Streaming with summary" "Expected 200, got $status_code"
    fi
else
    print_warning "Streaming summary test" "Could not create chat"
fi

# Print summary
print_summary
exit $?
