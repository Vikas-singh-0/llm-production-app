#!/bin/bash

# =============================================================================
# Health Endpoint Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

print_header "Testing Health Endpoint (/health)"

# Test 1: Health check without auth
print_test "Health check without authentication"
response=$(http_request_no_auth "GET" "/health")
assert_status "$response" "200" "Health without auth returns 200"
assert_valid_json "$response" "Health returns valid JSON"
assert_json_field "$response" "status" "ok" "Health status is 'ok'"

# Test 2: Health check with auth
print_test "Health check with authentication"
response=$(http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "Health with auth returns 200"
assert_json_field_exists "$response" "services" "Health includes services status"
assert_json_field_exists "$response" "org" "Health with auth includes org"
assert_json_field_exists "$response" "user" "Health with auth includes user"

# Test 3: Verify services structure
print_test "Services status structure"
response=$(http_request_no_auth "GET" "/health")
body=$(get_body "$response")
db_status=$(echo "$body" | jq -r '.services.database // empty')
redis_status=$(echo "$body" | jq -r '.services.redis // empty')

if [ "$db_status" = "connected" ] || [ "$db_status" = "disconnected" ]; then
    print_success "Database status present: $db_status"
else
    print_failure "Database status" "Invalid or missing database status"
fi

if [ "$redis_status" = "connected" ] || [ "$redis_status" = "disconnected" ]; then
    print_success "Redis status present: $redis_status"
else
    print_failure "Redis status" "Invalid or missing Redis status"
fi

# Test 4: Verify environment info
print_test "Environment information"
response=$(http_request_no_auth "GET" "/health")
assert_json_field_exists "$response" "env" "Health includes environment"
assert_json_field_exists "$response" "timestamp" "Health includes timestamp"
assert_json_field_exists "$response" "requestId" "Health includes requestId"

# Test 5: Verify user context with auth
print_test "User context in authenticated health check"
response=$(http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
user_id=$(echo "$body" | jq -r '.user.id // empty')
user_role=$(echo "$body" | jq -r '.user.role // empty')

if [ -n "$user_id" ] && [ "$user_id" != "null" ]; then
    print_success "User ID present in health response"
else
    print_failure "User ID" "Missing user ID in health response"
fi

if [ -n "$user_role" ] && [ "$user_role" != "null" ]; then
    print_success "User role present: $user_role"
else
    print_failure "User role" "Missing user role in health response"
fi

# Test 6: Verify org context with auth
print_test "Org context in authenticated health check"
response=$(http_request "GET" "/health" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
body=$(get_body "$response")
org_id=$(echo "$body" | jq -r '.org // empty')

if [ "$org_id" = "$DEFAULT_ORG_ID" ]; then
    print_success "Org ID matches header"
else
    print_failure "Org ID mismatch" "Expected $DEFAULT_ORG_ID, got $org_id"
fi

# Test 7: Response time check (basic)
print_test "Health endpoint response time"
start_time=$(date +%s%N)
response=$(http_request_no_auth "GET" "/health")
end_time=$(date +s%N)
# Convert to milliseconds (rough)
duration=$(( (end_time - start_time) / 1000000 ))

if [ $duration -lt 2000 ]; then
    print_success "Health endpoint responds quickly (${duration}ms)"
else
    print_warning "Health endpoint slow (${duration}ms)"
fi

# Print summary
print_summary
exit $?
