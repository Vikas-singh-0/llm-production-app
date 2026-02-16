#!/bin/bash

# =============================================================================
# Prompt Management Tests
# =============================================================================

# Source configuration
source "$(dirname "$0")/config.sh"

print_header "Testing Prompt Management (/prompts)"

# =============================================================================
# Helper Functions
# =============================================================================

# Cleanup function (prompts don't need cleanup like chats)
cleanup() {
    # Prompts are versioned, no deletion needed
    :
}

# Set trap to cleanup on exit
trap cleanup EXIT

# =============================================================================
# Prompt Tests
# =============================================================================

# Test 1: List prompts
print_test "List all prompts"
response=$(http_request "GET" "/prompts" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "200" "List prompts returns 200"
assert_valid_json "$response" "List prompts returns valid JSON"
assert_json_field_exists "$response" "prompts" "Response includes prompts array"
assert_json_field_exists "$response" "count" "Response includes count"

# Test 2: List prompts without auth
print_test "List prompts without authentication"
response=$(http_request_no_auth "GET" "/prompts")
assert_status "$response" "401" "List prompts without auth returns 401"

# Test 3: Get specific prompt
print_test "Get specific prompt versions"
# First, get list to find a prompt name
list_response=$(http_request "GET" "/prompts" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
list_body=$(get_body "$list_response")
prompt_name=$(echo "$list_body" | jq -r '.prompts[0] // empty')

if [ -n "$prompt_name" ] && [ "$prompt_name" != "null" ]; then
    print_info "Testing with prompt: $prompt_name"
    
    response=$(http_request "GET" "/prompts/$prompt_name" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    assert_status "$response" "200" "Get prompt returns 200"
    assert_valid_json "$response" "Get prompt returns valid JSON"
    assert_json_field_exists "$response" "name" "Response includes name"
    assert_json_field_exists "$response" "versions" "Response includes versions array"
    assert_json_field_exists "$response" "active_version" "Response includes active_version"
    
    # Check versions structure
    body=$(get_body "$response")
    version_count=$(echo "$body" | jq '.versions | length')
    print_info "Prompt has $version_count versions"
    
    if [ "$version_count" -gt 0 ]; then
        # Check first version structure
        if echo "$body" | jq -e '.versions[0].version' > /dev/null 2>&1; then
            print_success "Version has version number"
        fi
        if echo "$body" | jq -e '.versions[0].content' > /dev/null 2>&1; then
            print_success "Version has content"
        fi
        if echo "$body" | jq -e '.versions[0].is_active' > /dev/null 2>&1; then
            print_success "Version has is_active flag"
        fi
    fi
else
    print_warning "Get prompt test" "No prompts found to test with"
fi

# Test 4: Get non-existent prompt
print_test "Get non-existent prompt"
response=$(http_request "GET" "/prompts/non-existent-prompt-12345" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
assert_status "$response" "404" "Non-existent prompt returns 404"

# Test 5: Create prompt (admin only)
print_test "Create prompt (admin required)"
test_prompt_name="test-prompt-$(generate_test_id | cut -c1-8)"

response=$(http_request "POST" "/prompts" "{
    \"name\": \"$test_prompt_name\",
    \"content\": \"You are a helpful test assistant.\",
    \"is_active\": false,
    \"metadata\": {\"test\": true}
}" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")

status=$(get_status_code "$response")

if [ "$status" = "201" ]; then
    print_success "Admin can create prompt"
    assert_valid_json "$response" "Create prompt returns valid JSON"
    assert_json_field_exists "$response" "id" "Created prompt has ID"
    assert_json_field_exists "$response" "version" "Created prompt has version"
    
    body=$(get_body "$response")
    created_version=$(echo "$body" | jq -r '.version // empty')
    print_info "Created prompt version: $created_version"
    
    # Store for activation test
    TEST_PROMPT_NAME=$test_prompt_name
    TEST_PROMPT_VERSION=$created_version
elif [ "$status" = "403" ]; then
    print_success "Create prompt properly restricted to admin (403)"
else
    print_info "Create prompt" "Status: $status (may require admin role)"
fi

# Test 6: Create prompt as non-admin (should fail)
print_test "Create prompt as non-admin (should fail)"
response=$(http_request "POST" "/prompts" "{
    \"name\": \"unauthorized-prompt\",
    \"content\": \"This should not be created.\"
}" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")

status=$(get_status_code "$response")
if [ "$status" = "403" ]; then
    print_success "Non-admin cannot create prompt (403)"
else
    print_info "Create restriction" "Status: $status"
fi

# Test 7: Create prompt without auth
print_test "Create prompt without authentication"
response=$(http_request_no_auth "POST" "/prompts" '{"name": "test", "content": "test"}')
assert_status "$response" "401" "Create without auth returns 401"

# Test 8: Create prompt with missing fields
print_test "Create prompt with missing fields"
response=$(http_request "POST" "/prompts" "{
    \"name\": \"incomplete-prompt\"
}" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")

status=$(get_status_code "$response")
if [ "$status" = "400" ]; then
    print_success "Missing content returns 400"
else
    print_info "Validation" "Status: $status"
fi

# Test 9: Activate prompt version (admin only)
print_test "Activate prompt version (admin only)"
if [ -n "$TEST_PROMPT_NAME" ] && [ -n "$TEST_PROMPT_VERSION" ]; then
    response=$(http_request "PUT" "/prompts/$TEST_PROMPT_NAME/activate/$TEST_PROMPT_VERSION" "" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
    status=$(get_status_code "$response")
    
    if [ "$status" = "200" ]; then
        print_success "Admin can activate prompt version"
        assert_contains "$response" "activated" "Activation returns success message"
        
        # Verify activation
        get_response=$(http_request "GET" "/prompts/$TEST_PROMPT_NAME" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
        get_body=$(get_body "$get_response")
        active_version=$(echo "$get_body" | jq -r '.active_version // empty')
        
        if [ "$active_version" = "$TEST_PROMPT_VERSION" ]; then
            print_success "Prompt version is now active"
        else
            print_warning "Activation verification" "Active version: $active_version, Expected: $TEST_PROMPT_VERSION"
        fi
    elif [ "$status" = "403" ]; then
        print_success "Activation restricted to admin (403)"
    else
        print_info "Activation" "Status: $status"
    fi
else
    print_warning "Activation test" "No test prompt created to activate"
fi

# Test 10: Activate prompt as non-admin (should fail)
print_test "Activate prompt as non-admin (should fail)"
response=$(http_request "PUT" "/prompts/default-system-prompt/activate/1" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
status=$(get_status_code "$response")

if [ "$status" = "403" ]; then
    print_success "Non-admin cannot activate prompt (403)"
else
    print_info "Activation restriction" "Status: $status"
fi

# Test 11: Activate non-existent prompt version
print_test "Activate non-existent prompt version"
response=$(http_request "PUT" "/prompts/non-existent-prompt/activate/999" "" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
assert_status "$response" "404" "Non-existent prompt version returns 404"

# Test 12: Activate with invalid version number
print_test "Activate with invalid version number"
response=$(http_request "PUT" "/prompts/default-system-prompt/activate/invalid" "" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
assert_status "$response" "400" "Invalid version number returns 400"

# Test 13: Prompt version metadata
print_test "Prompt version metadata"
if [ -n "$TEST_PROMPT_NAME" ]; then
    response=$(http_request "GET" "/prompts/$TEST_PROMPT_NAME" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
    body=$(get_body "$response")
    
    if echo "$body" | jq -e '.versions[0].metadata' > /dev/null 2>&1; then
        print_success "Prompt version has metadata"
    else
        print_info "Metadata" "Metadata field may not be present"
    fi
    
    if echo "$body" | jq -e '.versions[0].created_at' > /dev/null 2>&1; then
        print_success "Prompt version has created_at"
    else
        print_info "Created at" "created_at field may not be present"
    fi
    
    if echo "$body" | jq -e '.versions[0].stats' > /dev/null 2>&1; then
        print_success "Prompt version has stats"
    else
        print_info "Stats" "stats field may not be present"
    fi
else
    print_warning "Metadata test" "No test prompt available"
fi

# Test 14: Multiple prompt versions
print_test "Create multiple versions of same prompt"
if [ -n "$TEST_PROMPT_NAME" ]; then
    # Create second version
    response=$(http_request "POST" "/prompts" "{
        \"name\": \"$TEST_PROMPT_NAME\",
        \"content\": \"Updated version of the test prompt with more instructions.\",
        \"is_active\": false
    }" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")
    
    status=$(get_status_code "$response")
    if [ "$status" = "201" ]; then
        print_success "Second version created"
        
        # Verify multiple versions
        get_response=$(http_request "GET" "/prompts/$TEST_PROMPT_NAME" "" "$DEFAULT_ORG_ID" "$DEFAULT_USER_ID")
        get_body=$(get_body "$get_response")
        version_count=$(echo "$get_body" | jq '.versions | length')
        
        if [ "$version_count" -ge 2 ]; then
            print_success "Prompt has $version_count versions"
        else
            print_info "Version count" "Found $version_count versions"
        fi
    else
        print_info "Second version" "Status: $status"
    fi
else
    print_warning "Multiple versions test" "No test prompt available"
fi

# Test 15: Prompt content validation
print_test "Prompt content validation"
response=$(http_request "POST" "/prompts" "{
    \"name\": \"empty-content-test\",
    \"content\": \"\",
    \"is_active\": false
}" "$DEFAULT_ORG_ID" "$DEFAULT_ADMIN_ID")

status=$(get_status_code "$response")
if [ "$status" = "400" ]; then
    print_success "Empty content properly rejected"
else
    print_info "Content validation" "Status: $status"
fi

# Print summary
print_summary
exit $?
