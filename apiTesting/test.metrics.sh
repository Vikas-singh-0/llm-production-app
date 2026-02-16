#!/bin/bash

# =============================================================================
# Metrics Endpoint Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

print_header "Testing Metrics Endpoint (/metrics)"

# Test 1: Metrics endpoint without auth
print_test "Metrics endpoint without authentication"
response=$(http_request_no_auth "GET" "/metrics")
assert_status "$response" "200" "Metrics without auth returns 200"

# Test 2: Verify Prometheus format
print_test "Prometheus format validation"
response=$(http_request_no_auth "GET" "/metrics")
body=$(get_body "$response")

# Check for common Prometheus metric types
if echo "$body" | grep -q "^# TYPE"; then
    print_success "Metrics contain TYPE declarations"
else
    print_failure "Prometheus TYPE" "Missing TYPE declarations"
fi

if echo "$body" | grep -q "^# HELP"; then
    print_success "Metrics contain HELP text"
else
    print_failure "Prometheus HELP" "Missing HELP text"
fi

# Test 3: Check for HTTP metrics
print_test "HTTP request metrics"
response=$(http_request_no_auth "GET" "/metrics")
body=$(get_body "$response")

if echo "$body" | grep -q "http_requests_total"; then
    print_success "HTTP request counter present"
else
    print_warning "HTTP request counter" "http_requests_total not found"
fi

if echo "$body" | grep -q "http_request_duration"; then
    print_success "HTTP request duration present"
else
    print_warning "HTTP duration" "http_request_duration not found"
fi

# Test 4: Check for custom application metrics
print_test "Application-specific metrics"
response=$(http_request_no_auth "GET" "/metrics")
body=$(get_body "$response")

# Check for chat-related metrics
if echo "$body" | grep -q "chat_"; then
    print_success "Chat metrics present"
else
    print_warning "Chat metrics" "No chat_ metrics found"
fi

# Check for LLM metrics
if echo "$body" | grep -q "llm_"; then
    print_success "LLM metrics present"
else
    print_warning "LLM metrics" "No llm_ metrics found"
fi

# Test 5: Content-Type header
print_test "Content-Type header"
response=$(curl -s -I -X GET "${BASE_URL}/metrics" 2>/dev/null | grep -i "content-type")
if echo "$response" | grep -qi "text/plain"; then
    print_success "Content-Type is text/plain"
else
    print_warning "Content-Type" "Expected text/plain, got: $response"
fi

# Test 6: Metrics after making requests
print_test "Metrics update after requests"
# Make a request to generate metrics
http_request_no_auth "GET" "/health" > /dev/null 2>&1
sleep 1

response=$(http_request_no_auth "GET" "/metrics")
body=$(get_body "$response")

# Look for any counter that increased
if echo "$body" | grep -q "http_requests_total.*[1-9]"; then
    print_success "Request counters are incrementing"
else
    print_warning "Request counters" "Counters may not be incrementing"
fi

# Test 7: Metric format validation
print_test "Metric format validation"
response=$(http_request_no_auth "GET" "/metrics")
body=$(get_body "$response")

# Check for valid metric lines (name{labels} value)
valid_lines=$(echo "$body" | grep -E "^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})?\s+[0-9.e+-]+$" | wc -l)
total_lines=$(echo "$body" | grep -v "^#" | grep -v "^$" | wc -l)

if [ "$valid_lines" -gt 0 ]; then
    print_success "Found $valid_lines valid metric lines"
else
    print_failure "Metric format" "No valid metric lines found"
fi

# Print summary
print_summary
exit $?
