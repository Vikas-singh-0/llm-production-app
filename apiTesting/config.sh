#!/bin/bash

# =============================================================================
# API Testing Configuration
# =============================================================================

# Base configuration
BASE_URL="${BASE_URL:-http://localhost:3000}"
API_VERSION="v1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Default test user credentials (for fakeAuth middleware)
DEFAULT_ORG_ID="${TEST_ORG_ID:-550e8400-e29b-41d4-a716-446655440000}"
DEFAULT_USER_ID="${TEST_USER_ID:-550e8400-e29b-41d4-a716-446655440001}"
DEFAULT_ADMIN_ID="${TEST_ADMIN_ID:-550e8400-e29b-41d4-a716-446655440002}"

# =============================================================================
# Utility Functions
# =============================================================================

# Print section header
print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# Print test name
print_test() {
    echo -e "${BLUE}▶ $1${NC}"
}

# Print success
print_success() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

# Print failure
print_failure() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    if [ -n "$2" ]; then
        echo -e "    ${RED}Details: $2${NC}"
    fi
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

# Print info
print_info() {
    echo -e "  ${YELLOW}ℹ INFO${NC}: $1"
}

# Print warning
print_warning() {
    echo -e "  ${MAGENTA}⚠ WARN${NC}: $1"
}

# Print summary
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
# HTTP Request Functions
# =============================================================================

# Make HTTP request with auth headers
http_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local org_id=${4:-$DEFAULT_ORG_ID}
    local user_id=${5:-$DEFAULT_USER_ID}
    
    local curl_cmd="curl -s -w \"\n%{http_code}\" -X $method"
    
    # Add headers
    curl_cmd="$curl_cmd -H \"Content-Type: application/json\""
    curl_cmd="$curl_cmd -H \"x-org-id: $org_id\""
    curl_cmd="$curl_cmd -H \"x-user-id: $user_id\""
    curl_cmd="$curl_cmd -H \"x-request-id: test-$(date +%s)\""
    
    # Add data if provided
    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi
    
    # Execute request
    eval "$curl_cmd \"${BASE_URL}${endpoint}\""
}

# Make HTTP request without auth (for testing 401)
http_request_no_auth() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    local curl_cmd="curl -s -w \"\n%{http_code}\" -X $method"
    curl_cmd="$curl_cmd -H \"Content-Type: application/json\""
    
    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi
    
    eval "$curl_cmd \"${BASE_URL}${endpoint}\""
}

# Make HTTP request with different org (for multi-tenancy tests)
http_request_different_org() {
    local method=$1
    local endpoint=$2
    local data=$3
    local org_id=$4
    local user_id=$5
    
    http_request "$method" "$endpoint" "$data" "$org_id" "$user_id"
}

# Extract HTTP status code from response
get_status_code() {
    echo "$1" | tail -n1
}

# Extract body from response (remove last line which is status code)
get_body() {
    echo "$1" | sed '$d'
}

# Check if response contains valid JSON
is_valid_json() {
    echo "$1" | jq empty 2>/dev/null
    return $?
}

# Extract field from JSON
get_json_field() {
    local json=$1
    local field=$2
    echo "$json" | jq -r ".$field" 2>/dev/null
}

# =============================================================================
# Validation Functions
# =============================================================================

# Assert status code equals expected
assert_status() {
    local response=$1
    local expected=$2
    local test_name=$3
    
    local actual=$(get_status_code "$response")
    
    if [ "$actual" = "$expected" ]; then
        print_success "$test_name (Status: $actual)"
        return 0
    else
        print_failure "$test_name" "Expected $expected, got $actual"
        return 1
    fi
}

# Assert JSON field equals expected value
assert_json_field() {
    local response=$1
    local field=$2
    local expected=$3
    local test_name=$4
    
    local body=$(get_body "$response")
    local actual=$(get_json_field "$body" "$field")
    
    if [ "$actual" = "$expected" ]; then
        print_success "$test_name ($field = $expected)"
        return 0
    else
        print_failure "$test_name" "Expected '$expected', got '$actual'"
        return 1
    fi
}

# Assert JSON field exists
assert_json_field_exists() {
    local response=$1
    local field=$2
    local test_name=$3
    
    local body=$(get_body "$response")
    local value=$(get_json_field "$body" "$field")
    
    if [ "$value" != "null" ] && [ -n "$value" ]; then
        print_success "$test_name (field '$field' exists)"
        return 0
    else
        print_failure "$test_name" "Field '$field' missing or null"
        return 1
    fi
}

# Assert response contains string
assert_contains() {
    local response=$1
    local pattern=$2
    local test_name=$3
    
    local body=$(get_body "$response")
    
    if echo "$body" | grep -q "$pattern"; then
        print_success "$test_name (contains '$pattern')"
        return 0
    else
        print_failure "$test_name" "Response doesn't contain '$pattern'"
        return 1
    fi
}

# Assert valid JSON response
assert_valid_json() {
    local response=$1
    local test_name=$2
    
    local body=$(get_body "$response")
    
    if is_valid_json "$body"; then
        print_success "$test_name (valid JSON)"
        return 0
    else
        print_failure "$test_name" "Invalid JSON response"
        return 1
    fi
}

# =============================================================================
# Test Data Generators
# =============================================================================

# Generate unique test ID
generate_test_id() {
    echo "test-$(date +%s)-$RANDOM"
}

# Generate test message
generate_test_message() {
    echo "Test message $(generate_test_id)"
}

# Generate long message for token testing
generate_long_message() {
    local length=${1:-1000}
    python3 -c "print('A' * $length)" 2>/dev/null || \
    python -c "print('A' * $length)" 2>/dev/null || \
    head -c $length < /dev/zero | tr '\0' 'A'
}

# Generate multiple messages for memory testing
generate_test_conversation() {
    local count=${1:-5}
    for i in $(seq 1 $count); do
        echo "Message $i: This is test message number $i for conversation testing."
    done
}

# =============================================================================
# Server Check
# =============================================================================

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

# =============================================================================
# Initialization
# =============================================================================

# Initialize test environment
init_tests() {
    print_header "API Testing Suite"
    print_info "Base URL: $BASE_URL"
    print_info "Test Org ID: $DEFAULT_ORG_ID"
    print_info "Test User ID: $DEFAULT_USER_ID"
    print_info "Test Admin ID: $DEFAULT_ADMIN_ID"
    
    # Check for required tools
    if ! command -v curl &> /dev/null; then
        print_failure "Dependency check" "curl is not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed - JSON validation will be limited"
    fi
    
    # Check server
    if ! check_server; then
        exit 1
    fi
    
    echo ""
}

# Export functions for use in other scripts
export -f print_header print_test print_success print_failure print_info print_warning print_summary
export -f http_request http_request_no_auth http_request_different_org
export -f get_status_code get_body is_valid_json get_json_field
export -f assert_status assert_json_field assert_json_field_exists assert_contains assert_valid_json
export -f generate_test_id generate_test_message generate_long_message generate_test_conversation
export -f check_server init_tests

# Export variables
export BASE_URL API_VERSION
export RED GREEN YELLOW BLUE CYAN MAGENTA NC
export TESTS_PASSED TESTS_FAILED TESTS_TOTAL
export DEFAULT_ORG_ID DEFAULT_USER_ID DEFAULT_ADMIN_ID
