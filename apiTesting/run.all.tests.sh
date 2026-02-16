#!/bin/bash

# =============================================================================
# Main Test Runner - Run All API Tests
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source configuration
source "$SCRIPT_DIR/config.sh"

# =============================================================================
# Test Configuration
# =============================================================================

# Test scripts to run (in order)
TEST_SCRIPTS=(
    "test.root.sh"
    "test.health.sh"
    "test.metrics.sh"
    "test.chat.sh"
    "test.streaming.sh"
    "test.memory.sh"
    "test.summarization.sh"
    "test.tokens.sh"
    "test.rate-limit.sh"
    "test.multi-tenancy.sh"
    "test.prompts.sh"
    "test.errors.sh"
)

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=0
FAILED_SCRIPTS=()

# =============================================================================
# Main Header
# =============================================================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                ║${NC}"
echo -e "${CYAN}║           LLM Production App - API Test Suite                  ║${NC}"
echo -e "${CYAN}║                                                                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_info "Base URL: ${BASE_URL:-http://localhost:3000}"
print_info "Test Org ID: $DEFAULT_ORG_ID"
print_info "Test User ID: $DEFAULT_USER_ID"
print_info "Test Admin ID: $DEFAULT_ADMIN_ID"
echo ""

# Check if server is running
if ! check_server; then
    echo ""
    print_failure "Server Check" "Server is not running at $BASE_URL"
    echo ""
    echo -e "${YELLOW}Please start the server before running tests:${NC}"
    echo -e "  npm run dev"
    echo -e "  or"
    echo -e "  npm start"
    echo ""
    exit 1
fi

echo ""

# =============================================================================
# Run Tests
# =============================================================================

print_header "Running Test Suite"

start_time=$(date +%s)

for script in "${TEST_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    
    if [ ! -f "$script_path" ]; then
        print_warning "Script not found: $script"
        continue
    fi
    
    # Make script executable if not already
    chmod +x "$script_path" 2>/dev/null
    
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Running: $script${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    # Run the test script
    if bash "$script_path"; then
        # Script passed
        :
    else
        # Script had failures
        FAILED_SCRIPTS+=("$script")
    fi
    
    # Accumulate results from the script's global counters
    # (Scripts export their counters)
    TOTAL_PASSED=$((TOTAL_PASSED + TESTS_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))
    TOTAL_TESTS=$((TOTAL_TESTS + TESTS_TOTAL))
    
    # Reset counters for next script
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_TOTAL=0
done

end_time=$(date +%s)
duration=$((end_time - start_time))

# =============================================================================
# Final Summary
# =============================================================================

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                     FINAL TEST SUMMARY                         ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "  Total Test Scripts: ${#TEST_SCRIPTS[@]}"
echo -e "  Failed Scripts:     ${#FAILED_SCRIPTS[@]}"
echo -e "  Total Duration:     ${duration}s"
echo ""

if [ ${#FAILED_SCRIPTS[@]} -gt 0 ]; then
    echo -e "${RED}Failed Test Scripts:${NC}"
    for script in "${FAILED_SCRIPTS[@]}"; do
        echo -e "  ${RED}✗ $script${NC}"
    done
    echo ""
fi

echo -e "  Total Tests:  $TOTAL_TESTS"
echo -e "  ${GREEN}Passed:       $TOTAL_PASSED${NC}"
echo -e "  ${RED}Failed:       $TOTAL_FAILED${NC}"
echo ""

if [ $TOTAL_FAILED -eq 0 ] && [ ${#FAILED_SCRIPTS[@]} -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✓ ALL TESTS PASSED SUCCESSFULLY!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                   ✗ SOME TESTS FAILED                          ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi
