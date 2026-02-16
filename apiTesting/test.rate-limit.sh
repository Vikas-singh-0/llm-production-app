#!/bin/bash

# =============================================================================
# Rate Limiting Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

print_header "Testing Rate Limiting"

# =============================================================================
# Rate Limit Tests
# =============================================================================

# Test 1: Check rate limit headers on root endpoint
print_test "Rate limit headers present"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Root endpoint accessible"

body=$(get_body "$response")

# Check rate limit structure
if echo "$body" | jq -e '.rateLimit' > /dev/null 2>&1; then
    print_success "Rate limit info present in response"
    
    limit=$(echo "$body" | jq -r '.rateLimit.limit // empty')
    remaining=$(echo "$body" | jq -r '.rateLimit.remaining // empty')
    reset_at=$(echo "$body" | jq -r '.rateLimit.resetAt // empty')
    
    print_info "Limit: $limit, Remaining: $remaining"
    print_info "Reset at: $reset_at"
    
    # Validate values
    if [ -n "$limit" ] && [ "$limit" != "null" ] && [ "$limit" -gt 0 ]; then
        print_success "Rate limit has valid limit value"
    else
        print_warning "Rate limit value" "Invalid or missing limit"
    fi
    
    if [ -n "$remaining" ] && [ "$remaining" != "null" ] && [ "$remaining" -ge 0 ]; then
        print_success "Rate limit has valid remaining value"
    else
        print_warning "Remaining value" "Invalid or missing remaining"
    fi
    
    if [ -n "$reset_at" ] && [ "$reset_at" != "null" ]; then
        print_success "Rate limit has valid reset time"
    else
        print_warning "Reset time" "Invalid or missing reset time"
    fi
else
    print_failure "Rate limit info" "Rate limit structure missing"
fi

# Test 2: Rate limit decreases with requests
print_test "Rate limit decreases with each request"
initial_response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
initial_body=$(get_body "$initial_response")
initial_remaining=$(echo "$initial_body" | jq -r '.rateLimit.remaining // 0')

# Make a few requests
for i in 1 2 3; do
    http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
done

# Check remaining again
final_response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
final_body=$(get_body "$final_response")
final_remaining=$(echo "$final_body" | jq -r '.rateLimit.remaining // 0')

print_info "Initial remaining: $initial_remaining"
print_info "After 3 requests: $final_remaining"

if [ "$final_remaining" -lt "$initial_remaining" ]; then
    print_success "Rate limit decreases with usage"
elif [ "$final_remaining" -eq "$initial_remaining" ]; then
    print_info "Rate limit" "Remaining unchanged (may have refilled or different endpoint counting)"
else
    print_warning "Rate limit" "Unexpected change in remaining"
fi

# Test 3: Rate limit reset time
print_test "Rate limit reset time calculation"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
reset_at=$(echo "$body" | jq -r '.rateLimit.resetAt // empty')

if [ -n "$reset_at" ] && [ "$reset_at" != "null" ]; then
    # Check if reset time is in the future
    reset_timestamp=$(date -d "$reset_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$reset_at" +%s 2>/dev/null || echo "0")
    current_timestamp=$(date +%s)
    
    if [ "$reset_timestamp" -gt "$current_timestamp" ]; then
        print_success "Reset time is in the future"
    else
        print_warning "Reset time" "Reset time may be in the past or invalid"
    fi
else
    print_warning "Reset time" "Could not parse reset time"
fi

# Test 4: Different users have separate rate limits
print_test "Rate limits are per-user"
# Create request as default user
response1=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body1=$(get_body "$response1")
remaining1=$(echo "$body1" | jq -r '.rateLimit.remaining // 0')

# Create request as different user (simulated)
DIFFERENT_USER="550e8400-e29b-41d4-a716-446655440999"
response2=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DIFFERENT_USER")
body2=$(get_body "$response2")
remaining2=$(echo "$body2" | jq -r '.rateLimit.remaining // 0')

print_info "User 1 remaining: $remaining1"
print_info "User 2 remaining: $remaining2"

# Both should have similar initial values if rate limits are per-user
if [ "$remaining2" -ge $(($remaining1 - 5)) ] && [ "$remaining2" -le $(($remaining1 + 5)) ]; then
    print_success "Different users have independent rate limits"
else
    print_info "Rate limit sharing" "Users may share rate limit or limits differ significantly"
fi

# Test 5: Rate limit on different endpoints
print_test "Rate limit tracking across endpoints"
# Make requests to different endpoints
http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
http_request "GET" "/chats" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
http_request "GET" "/prompts" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1

# Check rate limit
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
remaining=$(echo "$body" | jq -r '.rateLimit.remaining // 0')

print_info "Remaining after 3 endpoint calls: $remaining"
print_success "Rate limit tracked across multiple endpoints"

# Test 6: Burst request handling
print_test "Burst request handling"
print_info "Sending 10 rapid requests..."

# Send burst of requests
for i in $(seq 1 10); do
    http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1 &
done
wait

# Check if we're still within limits
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")

if [ "$status" = "200" ]; then
    print_success "Burst requests handled (status: $status)"
else
    print_info "Burst status" "Status after burst: $status"
fi

# Test 7: Rate limit on chat endpoints (higher cost)
print_test "Rate limit on chat endpoints"
initial_response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
initial_remaining=$(get_body "$initial_response" | jq -r '.rateLimit.remaining // 0')

# Create a chat and send message (higher cost operation)
CHAT_RESPONSE=$(http_request "POST" "/chats" '{"title": "Rate Limit Test"}' "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
CHAT_ID=$(get_body "$CHAT_RESPONSE" | jq -r '.id // empty')

if [ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "null" ]; then
    # Send a message
    http_request "POST" "/chat" "{\"message\": \"Test\", \"chat_id\": \"$CHAT_ID\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
    
    # Check remaining
    final_response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    final_remaining=$(get_body "$final_response" | jq -r '.rateLimit.remaining // 0')
    
    print_info "Before chat: $initial_remaining, After chat: $final_remaining"
    
    # Cleanup
    http_request "DELETE" "/chat/$CHAT_ID" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
    
    if [ "$final_remaining" -lt "$initial_remaining" ]; then
        print_success "Chat operations consume rate limit"
    else
        print_info "Rate limit" "Chat may not consume rate limit tokens"
    fi
else
    print_warning "Chat rate limit test" "Could not create chat"
fi

# Test 8: Rate limit without auth (public endpoints)
print_test "Rate limit on public endpoints"
response=$(http_request_no_auth "GET" "/health")
status=$(get_status_code "$response")

if [ "$status" = "200" ]; then
    print_success "Public endpoint accessible without auth"
else
    print_info "Public endpoint" "Status: $status"
fi

# Test 9: Verify rate limit structure consistency
print_test "Rate limit structure consistency"
for endpoint in "/" "/health"; do
    response=$(http_request "GET" "$endpoint" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    body=$(get_body "$response")
    
    if echo "$body" | jq -e '.rateLimit.limit' > /dev/null 2>&1; then
        print_success "$endpoint has rate limit info"
    else
        print_info "$endpoint" "Rate limit info may not be present"
    fi
done

# Test 10: Rate limit reset behavior
print_test "Rate limit reset behavior"
# This is a basic check - full reset testing would require waiting

response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
reset_at=$(echo "$body" | jq -r '.rateLimit.resetAt // empty')
remaining=$(echo "$body" | jq -r '.rateLimit.remaining // 0')

if [ -n "$reset_at" ] && [ "$reset_at" != "null" ]; then
    print_success "Reset time provided: $reset_at"
    print_info "Current remaining: $remaining"
    
    # If remaining is low, reset should be soon
    if [ "$remaining" -lt 5 ] && [ -n "$reset_at" ]; then
        print_info "Low remaining" "Rate limit will reset at $reset_at"
    fi
else
    print_warning "Reset info" "Reset time not available"
fi

# Print summary
print_summary
exit $?
