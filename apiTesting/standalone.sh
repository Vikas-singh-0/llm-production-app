#!/bin/bash

# =============================================================================
# Standalone Streaming Endpoint Tests (SSE)
# =============================================================================

# Base configuration
BASE_URL="${BASE_URL:-http://localhost:3000}"

# Default test user credentials (for fakeAuth middleware)
DEFAULT_ORG_ID="${TEST_ORG_ID:-00000000-0000-0000-0000-000000000001}"
DEFAULT_USER_ID="${TEST_USER_ID:-27bc8096-2f47-4eef-8655-42cef0885f7a}"
DEFAULT_ADMIN_ID="${TEST_ADMIN_ID:-550e8400-e29b-41d4-a716-446655440002}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# =============================================================================
# Utility Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_test() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

print_failure() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "    ${RED}Details: $2${NC}"
    fi
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

print_info() {
    echo -e "  ${YELLOW}ℹ INFO${NC}: $1"
}

print_warning() {
    echo -e "  ${MAGENTA}⚠ WARN${NC}: $1"
}

print_summary() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Test Summary${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "  Total Tests:  ${TESTS_TOTAL}"
    echo -e "  ${GREEN}Passed:       ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:       ${TESTS_FAILED}${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed!${NC}"
        return 1
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

get_status_code() {
    echo "$1" | tail -n1
}

get_body() {
    echo "$1" | sed '$d'
}

generate_test_id() {
    echo "test-$(date +%s)-$RANDOM"
}

# Check if server is running
check_server() {
    print_info "Checking if server is running at $BASE_URL..."

    local response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health" 2>/dev/null)

    if [ "$response" = "200" ] || [ "$response" = "503" ]; then
        print_success "Server is running (status: $response)"
        return 0
    else
        print_failure "Server check" "Server not responding (status: $response)"
        print_warning "Please start the server before running tests"
        return 1
    fi
}

# Make HTTP request with auth headers
http_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local org_id=${4:-$DEFAULT_ORG_ID}
    local user_id=${5:-$DEFAULT_USER_ID}

    local curl_cmd="curl -s -w \"\n%{http_code}\" -X $method"

    curl_cmd="$curl_cmd -H \"Content-Type: application/json\""
    curl_cmd="$curl_cmd -H \"x-org-id: $org_id\""
    curl_cmd="$curl_cmd -H \"x-user-id: $user_id\""
    curl_cmd="$curl_cmd -H \"x-request-id: test-$(date +%s)\""

    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi

    eval "$curl_cmd \"${BASE_URL}${endpoint}\""
}

# =============================================================================
# Streaming Tests
# =============================================================================

print_header "Standalone Streaming Endpoint Tests (/chat/stream)"

print_info "Base URL: $BASE_URL"
print_info "Test Org ID: $DEFAULT_ORG_ID"
print_info "Test User ID: $DEFAULT_USER_ID"

# Dependency check
if ! command -v curl &> /dev/null; then
    print_failure "Dependency check" "curl is not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_warning "jq not installed - JSON validation will be limited"
fi

# Check server
if ! check_server; then
    exit 1
fi

# Store created chat IDs for cleanup
CREATED_CHAT_IDS=()

# Create a chat and store ID
create_chat() {
    local title=${1:-"Streaming Test $(generate_test_id)"}
    local response=$(http_request "POST" "/chats" "{\"title\": \"$title\"}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    local body=$(get_body "$response")
    local chat_id=$(echo "$body" | jq -r '.id // empty' 2>/dev/null)

    if [ -n "$chat_id" ] && [ "$chat_id" != "null" ]; then
        CREATED_CHAT_IDS+=("$chat_id")
        echo "$chat_id"
        return 0
    else
        echo ""
        return 1
    fi
}

cleanup_chats() {
    if [ ${#CREATED_CHAT_IDS[@]} -gt 0 ]; then
        print_info "Cleaning up ${#CREATED_CHAT_IDS[@]} test chats..."
        for chat_id in "${CREATED_CHAT_IDS[@]}"; do
            http_request "DELETE" "/chat/$chat_id" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID" > /dev/null 2>&1
        done
    fi
}

trap cleanup_chats EXIT

# Create a chat for streaming tests
STREAM_CHAT_ID=$(create_chat "Streaming Test Chat")
if [ -z "$STREAM_CHAT_ID" ]; then
    print_failure "Setup" "Failed to create chat for streaming tests"
    print_summary
    exit 1
fi

print_info "Using chat ID: $STREAM_CHAT_ID"

# Test 1: Basic streaming request
print_test "Basic streaming request"
response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -H "x-request-id: test-stream-$(date +%s)" \
    -d "{\"message\": \"Say hello in one word\", \"chat_id\": \"$STREAM_CHAT_ID\"}" \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 30)

status_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$status_code" = "200" ]; then
    print_success "Streaming request returns 200"
else
    print_failure "Streaming status" "Expected 200, got $status_code"
fi

# Test 2: Verify SSE format
print_test "Verify SSE format"
if echo "$body" | grep -q "^data:"; then
    print_success "Response uses SSE format (data: prefix)"
else
    print_failure "SSE format" "Missing 'data:' prefix in response"
fi

# Test 3: Check for streaming events
print_test "Check for streaming events"
event_count=$(echo "$body" | grep -c "^data:")

if [ "$event_count" -gt 0 ]; then
    print_success "Received $event_count SSE events"
else
    print_failure "Streaming events" "No SSE events received"
fi

# Test 4: Check for completion event
print_test "Check for completion event"
if echo "$body" | grep -q '"done":true'; then
    print_success "Completion event received"
else
    print_warning "Completion event" "No completion event found (may be truncated)"
fi

# Test 5: Verify JSON in events
print_test "Verify JSON in SSE events"
valid_json_count=0
while IFS= read -r line; do
    if [[ $line == data:* ]]; then
        json_data=$(echo "$line" | sed 's/^data: //')
        if echo "$json_data" | jq empty 2>/dev/null; then
            ((valid_json_count++))
        fi
    fi
done <<< "$body"

if [ "$valid_json_count" -gt 0 ]; then
    print_success "$valid_json_count events contain valid JSON"
else
    print_warning "JSON validation" "No valid JSON found in events"
fi

# Test 6: Check for token field in events
print_test "Check for token field"
if echo "$body" | grep -q '"token"'; then
    print_success "Events contain token field"
else
    print_warning "Token field" "No token field in events"
fi

# Test 7: Check for usage data in completion
print_test "Check for usage data in completion"
if echo "$body" | grep -q '"usage"'; then
    print_success "Completion includes usage data"
else
    print_warning "Usage data" "No usage data in completion event"
fi

# Test 8: Streaming without auth (should fail)
print_test "Streaming without authentication"
response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"Test\", \"chat_id\": \"$STREAM_CHAT_ID\"}" \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 5)

status_code=$(echo "$response" | tail -n1)
if [ "$status_code" = "401" ]; then
    print_success "Streaming without auth returns 401"
else
    print_failure "Auth check" "Expected 401, got $status_code"
fi

# Test 9: Streaming with empty message
print_test "Streaming with empty message"
response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d "{\"message\": \"\", \"chat_id\": \"$STREAM_CHAT_ID\"}" \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 5)

status_code=$(echo "$response" | tail -n1)
if [ "$status_code" = "400" ]; then
    print_success "Empty message returns 400"
else
    print_failure "Empty message check" "Expected 400, got $status_code"
fi

# Test 10: Streaming to non-existent chat
print_test "Streaming to non-existent chat"
response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d '{"message": "Test", "chat_id": "non-existent-chat"}' \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 5)

status_code=$(echo "$response" | tail -n1)
if [ "$status_code" = "404" ]; then
    print_success "Non-existent chat returns 404"
else
    print_failure "Non-existent chat" "Expected 404, got $status_code"
fi

# Test 11: Auto-create chat with streaming
print_test "Auto-create chat with streaming"
response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d '{"message": "Create new chat via streaming"}' \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 30)

status_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$status_code" = "200" ]; then
    print_success "Auto-create with streaming returns 200"
else
    print_failure "Auto-create streaming" "Expected 200, got $status_code"
fi

# Test 12: Response headers check
print_test "Verify SSE headers"
headers=$(curl -s -I -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d "{\"message\": \"Test headers\", \"chat_id\": \"$STREAM_CHAT_ID\"}" \
    "${BASE_URL}/chat/stream" \
    --max-time 5)

if echo "$headers" | grep -qi "text/event-stream"; then
    print_success "Content-Type is text/event-stream"
else
    print_warning "Content-Type" "Expected text/event-stream"
fi

if echo "$headers" | grep -qi "no-cache"; then
    print_success "Cache-Control: no-cache present"
else
    print_warning "Cache-Control" "Expected no-cache header"
fi

# Test 13: Long message streaming
print_test "Long message streaming"
long_message="Please provide a detailed explanation of how streaming works in HTTP. Include information about Server-Sent Events, connection handling, and data formatting."

response=$(curl -s -N \
    -X POST \
    -H "Content-Type: application/json" \
    -H "x-org-id: $DEFAULT_ORG_ID" \
    -H "x-user-id: $DEFAULT_USER_ID" \
    -d "{\"message\": \"$long_message\", \"chat_id\": \"$STREAM_CHAT_ID\"}" \
    "${BASE_URL}/chat/stream" \
    -w "\n%{http_code}" \
    --max-time 60)

status_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$status_code" = "200" ]; then
    event_count=$(echo "$body" | grep -c "^data:")
    if [ "$event_count" -gt 5 ]; then
        print_success "Long message produces multiple events ($event_count)"
    else
        print_info "Long message streaming completed ($event_count events)"
    fi
else
    print_failure "Long message streaming" "Expected 200, got $status_code"
fi

# Summary
print_summary
exit $?
