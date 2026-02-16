#!/bin/bash

# =============================================================================
# Memory Management Tests (Sliding Window, Context Limits)
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

print_header "Testing Memory Management (Sliding Window & Context)"

# =============================================================================
# Helper Functions
# =============================================================================

# Create a chat and store ID
create_chat() {
    local title=${1:-"Memory Test $(generate_test_id)"}
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

# Send a message and get response
send_message() {
    local chat_id=$1
    local message=$2
    local response=$(http_request "POST" "/chat" "{\"message\": \"$message\", \"chat_id\": \"$chat_id\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    echo "$response"
}

# Send multiple messages to build conversation history
build_conversation() {
    local chat_id=$1
    local count=$2
    local prefix=${3:-"Message"}
    
    for i in $(seq 1 $count); do
        local msg="$prefix $i: This is test message number $i for memory testing with sufficient length to ensure token counting."
        send_message "$chat_id" "$msg" > /dev/null 2>&1
        sleep 0.5
    done
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
# Sliding Window Tests
# =============================================================================

# Test 1: Create chat and verify initial state
print_test "Create chat for memory tests"
MEMORY_CHAT_ID=$(create_chat "Memory Test Chat")
if [ -n "$MEMORY_CHAT_ID" ]; then
    print_success "Created chat for memory tests: $MEMORY_CHAT_ID"
else
    print_failure "Setup" "Failed to create chat for memory tests"
    print_summary
    exit 1
fi

# Test 2: Send single message and verify context
print_test "Single message context preservation"
response=$(send_message "$MEMORY_CHAT_ID" "My name is TestUser123")
assert_status "$response" "200" "Message sent successfully"

# Get chat to verify message stored
sleep 1
response=$(http_request "GET" "/chat/$MEMORY_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
message_count=$(echo "$body" | jq -r '.message_count // 0')

if [ "$message_count" -ge 2 ]; then
    print_success "Messages stored in chat (count: $message_count)"
else
    print_warning "Message storage" "Expected at least 2 messages, got $message_count"
fi

# Test 3: Build conversation with multiple messages
print_test "Build conversation history (10 messages)"
print_info "Sending 10 messages to test sliding window..."
build_conversation "$MEMORY_CHAT_ID" 10 "Context Message"

sleep 2

# Verify conversation built
response=$(http_request "GET" "/chat/$MEMORY_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
message_count=$(echo "$body" | jq -r '.message_count // 0')

if [ "$message_count" -ge 10 ]; then
    print_success "Conversation built with $message_count messages"
else
    print_warning "Conversation build" "Expected 10+ messages, got $message_count"
fi

# Test 4: Test context reference (can assistant remember earlier context)
print_test "Context reference test"
response=$(send_message "$MEMORY_CHAT_ID" "What was my name that I mentioned earlier?")
assert_status "$response" "200" "Context reference query sent"

body=$(get_body "$response")
reply=$(echo "$body" | jq -r '.reply // empty')

if echo "$reply" | grep -qi "testuser123"; then
    print_success "Assistant remembers context from earlier messages"
else
    print_info "Context reference" "Response: ${reply:0:100}..."
    print_warning "Context reference" "Assistant may not be referencing earlier context"
fi

# Test 5: Large message for token limit testing
print_test "Large message token handling"
large_message=$(generate_long_message 2000)
response=$(send_message "$MEMORY_CHAT_ID" "$large_message")
assert_status "$response" "200" "Large message handled"

body=$(get_body "$response")
input_tokens=$(echo "$body" | jq -r '.usage.input_tokens // 0')

if [ "$input_tokens" -gt 100 ]; then
    print_success "Large message token count: $input_tokens"
else
    print_warning "Token count" "Expected >100 tokens for large message, got $input_tokens"
fi

# Test 6: Multiple large messages to trigger sliding window
print_test "Multiple large messages (sliding window test)"
print_info "Sending 5 large messages to test sliding window..."

for i in $(seq 1 5); do
    msg="Large message $i: $(generate_long_message 1500)"
    send_message "$MEMORY_CHAT_ID" "$msg" > /dev/null 2>&1
    sleep 0.5
done

sleep 2

# Check if messages are still accessible
response=$(http_request "GET" "/chat/$MEMORY_CHAT_ID/messages?limit=50" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
total_messages=$(echo "$body" | jq -r '.message_count // 0')

print_info "Total messages in chat: $total_messages"

# Test 7: Verify token usage tracking in context
print_test "Token usage tracking in responses"
response=$(send_message "$MEMORY_CHAT_ID" "Test message for token tracking")
body=$(get_body "$response")

if echo "$body" | jq -e '.usage.input_tokens' > /dev/null 2>&1; then
    input_tokens=$(echo "$body" | jq -r '.usage.input_tokens')
    output_tokens=$(echo "$body" | jq -r '.usage.output_tokens')
    total_tokens=$(echo "$body" | jq -r '.usage.total_tokens')
    
    print_success "Token usage tracked: Input=$input_tokens, Output=$output_tokens, Total=$total_tokens"
    
    # Verify total is sum of input and output
    expected_total=$((input_tokens + output_tokens))
    if [ "$total_tokens" -eq "$expected_total" ] || [ "$total_tokens" -eq $((expected_total + 1)) ] || [ "$total_tokens" -eq $((expected_total - 1)) ]; then
        print_success "Total tokens calculation is correct"
    else
        print_warning "Token calculation" "Total ($total_tokens) != Input ($input_tokens) + Output ($output_tokens)"
    fi
else
    print_failure "Token tracking" "Token usage not found in response"
fi

# Test 8: Message ordering preservation
print_test "Message ordering preservation"
ORDER_CHAT_ID=$(create_chat "Ordering Test")

if [ -n "$ORDER_CHAT_ID" ]; then
    # Send numbered messages
    for i in 1 2 3 4 5; do
        send_message "$ORDER_CHAT_ID" "This is message number $i in sequence" > /dev/null 2>&1
        sleep 0.3
    done
    
    sleep 1
    
    # Get messages and verify order
    response=$(http_request "GET" "/chat/$ORDER_CHAT_ID/messages" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    body=$(get_body "$response")
    
    # Check if messages are in chronological order
    first_msg=$(echo "$body" | jq -r '.messages[0].content // empty')
    last_msg=$(echo "$body" | jq -r '.messages[-1].content // empty')
    
    if echo "$first_msg" | grep -q "message number 1" && echo "$last_msg" | grep -q "message number 5"; then
        print_success "Message ordering preserved (chronological)"
    else
        print_info "First: ${first_msg:0:50}..."
        print_info "Last: ${last_msg:0:50}..."
        print_warning "Message ordering" "Order may not be strictly chronological"
    fi
else
    print_warning "Ordering test" "Could not create chat for ordering test"
fi

# Test 9: Redis caching verification (indirect)
print_test "Redis caching (performance check)"
# Make same request twice and compare response times

start1=$(date +%s%N)
response1=$(http_request "GET" "/chat/$MEMORY_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
end1=$(date +%s%N)
time1=$(( (end1 - start1) / 1000000 ))

sleep 0.5

start2=$(date +%s%N)
response2=$(http_request "GET" "/chat/$MEMORY_CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
end2=$(date +%s%N)
time2=$(( (end2 - start2) / 1000000 ))

print_info "First request: ${time1}ms, Second request: ${time2}ms"

if [ $time2 -lt $time1 ]; then
    print_success "Second request faster (possible cache hit)"
else
    print_info "Cache performance" "Times: ${time1}ms vs ${time2}ms"
fi

# Test 10: Context window with summary (if applicable)
print_test "Context window with many messages"
MANY_MSG_CHAT=$(create_chat "Many Messages Test")

if [ -n "$MANY_MSG_CHAT" ]; then
    # Send 25 messages to potentially trigger summarization
    print_info "Sending 25 messages..."
    for i in $(seq 1 25); do
        send_message "$MANY_MSG_CHAT" "Message $i: Testing context window behavior with many messages in conversation" > /dev/null 2>&1
    done
    
    sleep 2
    
    # Send a message that requires context
    response=$(send_message "$MANY_MSG_CHAT" "Summarize what we've discussed")
    assert_status "$response" "200" "Context-heavy request handled"
    
    body=$(get_body "$response")
    if echo "$body" | jq -e '.usage.input_tokens > 1000' > /dev/null 2>&1; then
        print_info "Large context processed (input tokens > 1000)"
    fi
else
    print_warning "Context window test" "Could not create chat"
fi

# Print summary
print_summary
exit $?
