#!/bin/bash

# =============================================================================
# Root Endpoint Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

print_header "Testing Root Endpoint (/)"

# Test 1: Root endpoint without auth
print_test "Root endpoint without authentication"
response=$(http_request_no_auth "GET" "/")
assert_status "$response" "200" "Root without auth returns 200"
assert_valid_json "$response" "Root returns valid JSON"
assert_contains "$response" "Welcome" "Root contains welcome message"

# Test 2: Root endpoint with auth
print_test "Root endpoint with authentication"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Root with auth returns 200"
assert_json_field_exists "$response" "org" "Root includes org context"
assert_json_field_exists "$response" "user" "Root includes user context"
assert_json_field_exists "$response" "rateLimit" "Root includes rate limit info"

# Test 3: Verify rate limit structure
print_test "Rate limit structure in response"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
limit=$(echo "$body" | jq -r '.rateLimit.limit // empty')
remaining=$(echo "$body" | jq -r '.rateLimit.remaining // empty')
reset_at=$(echo "$body" | jq -r '.rateLimit.resetAt // empty')

if [ -n "$limit" ] && [ -n "$remaining" ] && [ -n "$reset_at" ]; then
    print_success "Rate limit has all required fields"
    print_info "Limit: $limit, Remaining: $remaining"
else
    print_failure "Rate limit structure" "Missing rate limit fields"
fi

# Test 4: Verify user context structure
print_test "User context structure"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
user_id=$(echo "$body" | jq -r '.user.id // empty')
user_email=$(echo "$body" | jq -r '.user.email // empty')
user_role=$(echo "$body" | jq -r '.user.role // empty')

if [ -n "$user_id" ] && [ -n "$user_email" ] && [ -n "$user_role" ]; then
    print_success "User context has all required fields"
    print_info "User: $user_email (Role: $user_role)"
else
    print_failure "User context structure" "Missing user fields"
fi

# Test 5: Verify timestamp and requestId
print_test "Response metadata"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_json_field_exists "$response" "timestamp" "Response includes timestamp"
assert_json_field_exists "$response" "requestId" "Response includes requestId"

# Test 6: Verify org context matches header
print_test "Org context matches header"
response=$(http_request "GET" "/" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
org_id=$(echo "$body" | jq -r '.org // empty')

if [ "$org_id" = "$DEFAULT_ORG_ID" ]; then
    print_success "Org context matches x-org-id header"
else
    print_failure "Org context mismatch" "Expected $DEFAULT_ORG_ID, got $org_id"
fi

# Print summary
print_summary
exit $?
