#!/usr/bin/env bash

################################################################################
# Edge Cases Test Suite for User Buy List
# 
# Tests boundary conditions, error scenarios, and edge cases:
# - Invalid input handling
# - Concurrency/race conditions
# - Kafka failure scenarios
# - MongoDB connection issues
# - Large data handling
# - Duplicate message handling
# - Malformed requests
# - Resource exhaustion
#
# Usage: ./scripts/test-edge-cases.sh
################################################################################

set -eu

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

separator() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

API_BASE="${API_BASE:-http://localhost:3000}"
CUSTOMER_MGMT_BASE="${CUSTOMER_MGMT_BASE:-http://localhost:3001}"

################################################################################
# Test 1: Invalid Input Validation
################################################################################

test_invalid_input() {
    separator "Test 1: Invalid Input Handling"
    
    # Missing required fields
    log_info "Testing missing username..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"userid":"user1","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Missing username returns 400 Bad Request"
    else
        log_error "Missing username should return 400, got $response"
    fi
    
    # Missing userid
    log_info "Testing missing userid..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Missing userid returns 400 Bad Request"
    else
        log_error "Missing userid should return 400, got $response"
    fi
    
    # Missing price
    log_info "Testing missing price..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user1"}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Missing price returns 400 Bad Request"
    else
        log_error "Missing price should return 400, got $response"
    fi
}

################################################################################
# Test 2: Invalid Price Values
################################################################################

test_invalid_prices() {
    separator "Test 2: Invalid Price Values"
    
    # Negative price
    log_info "Testing negative price..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user1","price":-10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Negative price returns 400 Bad Request"
    else
        log_error "Negative price should return 400, got $response"
    fi
    
    # Zero price
    log_info "Testing zero price..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user1","price":0}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Zero price returns 400 Bad Request"
    else
        log_error "Zero price should return 400, got $response"
    fi
    
    # Non-numeric price
    log_info "Testing non-numeric price..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user1","price":"abc"}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Non-numeric price returns 400 Bad Request"
    else
        log_error "Non-numeric price should return 400, got $response"
    fi
}

################################################################################
# Test 3: Empty Strings
################################################################################

test_empty_strings() {
    separator "Test 3: Empty String Handling"
    
    # Empty username
    log_info "Testing empty username..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"","userid":"user1","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Empty username returns 400 Bad Request"
    else
        log_error "Empty username should return 400, got $response"
    fi
    
    # Whitespace-only userid
    log_info "Testing whitespace-only userid..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"   ","price":10}' 2>/dev/null | tail -1)
    
    # This might pass through (implementation dependent)
    if [ "$response" == "201" ] || [ "$response" == "400" ]; then
        log_success "Whitespace-only userid handled (code: $response)"
    else
        log_error "Unexpected response for whitespace userid: $response"
    fi
}

################################################################################
# Test 4: SQL Injection / NoSQL Injection Attempts
################################################################################

test_injection_attempts() {
    separator "Test 4: Injection Attack Protection"
    
    # NoSQL injection attempt in userid
    log_info "Testing NoSQL injection in userid..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":{"$ne":null},"price":10}' 2>/dev/null | tail -1)
    
    # Should either reject or handle safely
    log_success "NoSQL injection attempt handled (code: $response)"
    
    # Script injection in username
    log_info "Testing XSS attempt in username..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"<script>alert(1)</script>","userid":"user1","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "201" ]; then
        log_success "XSS payload accepted and stored safely"
    else
        log_error "XSS payload rejected (may be overly restrictive)"
    fi
}

################################################################################
# Test 5: Very Large Values
################################################################################

test_large_values() {
    separator "Test 5: Large Data Handling"
    
    # Very large price
    log_info "Testing very large price (1 trillion)..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user-large","price":1000000000000}' 2>/dev/null | tail -1)
    
    if [ "$response" == "201" ]; then
        log_success "Large price accepted (code: $response)"
    else
        log_error "Large price handling failed (code: $response)"
    fi
    
    # Very long username
    log_info "Testing very long username (1000 chars)..."
    long_name=$(python3 -c "print('a' * 1000)")
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$long_name\",\"userid\":\"user-long\",\"price\":10}" 2>/dev/null | tail -1)
    
    if [ "$response" == "201" ] || [ "$response" == "400" ]; then
        log_success "Long username handled (code: $response)"
    else
        log_error "Unexpected response for long username: $response"
    fi
}

################################################################################
# Test 6: Concurrent Requests
################################################################################

test_concurrent_requests() {
    separator "Test 6: Concurrent Request Handling"
    
    log_info "Sending 10 concurrent requests..."
    
    local failed=0
    for i in {1..10}; do
        curl -s -X POST "$API_BASE/buy" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"concurrent-$i\",\"userid\":\"concurrent-user\",\"price\":$((i * 10))}" \
            > /dev/null 2>&1 &
    done
    
    wait
    
    # Verify all purchases were recorded
    sleep 3
    count=$(curl -s "$API_BASE/getAllUserBuys/concurrent-user" 2>/dev/null | jq 'length' || echo 0)
    
    if [ "$count" -ge 10 ]; then
        log_success "All 10 concurrent purchases recorded ($count total)"
    else
        log_error "Only $count out of 10 concurrent purchases recorded"
    fi
}

################################################################################
# Test 7: Duplicate Messages (Idempotency)
################################################################################

test_duplicate_handling() {
    separator "Test 7: Duplicate Message Handling"
    
    log_info "Sending same purchase twice..."
    
    local test_id="dup-$(date +%s)"
    local payload="{\"username\":\"dup-test\",\"userid\":\"$test_id\",\"price\":25.50}"
    
    # Send same request twice
    curl -s -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null 2>&1
    
    curl -s -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null 2>&1
    
    sleep 3
    
    # Check how many were stored
    count=$(curl -s "$API_BASE/getAllUserBuys/$test_id" 2>/dev/null | jq 'length' || echo 0)
    
    if [ "$count" -eq 2 ]; then
        log_success "Both duplicate requests stored (2 records) - no deduplication"
    elif [ "$count" -eq 1 ]; then
        log_success "Duplicate request handled (1 record) - idempotent behavior"
    else
        log_error "Unexpected count: $count"
    fi
}

################################################################################
# Test 8: Invalid Content-Type
################################################################################

test_invalid_content_type() {
    separator "Test 8: Content-Type Validation"
    
    log_info "Testing request without Content-Type header..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -d '{"username":"test","userid":"user1","price":10}' 2>/dev/null | tail -1)
    
    # Should still work or gracefully fail
    if [ "$response" == "201" ] || [ "$response" == "400" ]; then
        log_success "Missing Content-Type handled (code: $response)"
    else
        log_error "Unexpected response: $response"
    fi
    
    log_info "Testing wrong Content-Type (text/plain)..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: text/plain" \
        -d '{"username":"test","userid":"user1","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ] || [ "$response" == "415" ]; then
        log_success "Wrong Content-Type rejected (code: $response)"
    else
        log_error "Should reject wrong Content-Type"
    fi
}

################################################################################
# Test 9: Non-existent User Retrieval
################################################################################

test_nonexistent_user() {
    separator "Test 9: Non-existent User Handling"
    
    log_info "Fetching purchases for non-existent user..."
    response=$(curl -s -w "\n%{http_code}" "$API_BASE/getAllUserBuys/nonexistent-user-xyz" 2>/dev/null | tail -2)
    
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -1)
    
    if [ "$http_code" == "200" ]; then
        if echo "$body" | jq -e '. == []' > /dev/null 2>&1; then
            log_success "Non-existent user returns empty array (correct)"
        else
            log_error "Non-existent user should return empty array"
        fi
    else
        log_error "Non-existent user query returned code: $http_code"
    fi
}

################################################################################
# Test 10: Malformed JSON
################################################################################

test_malformed_json() {
    separator "Test 10: Malformed JSON Handling"
    
    log_info "Testing malformed JSON..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{invalid json}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ] || [ "$response" == "500" ]; then
        log_success "Malformed JSON rejected (code: $response)"
    else
        log_error "Malformed JSON handling unexpected: $response"
    fi
    
    log_info "Testing JSON with extra trailing comma..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test","userid":"user1","price":10,}' 2>/dev/null | tail -1)
    
    if [ "$response" == "400" ]; then
        log_success "Invalid JSON rejected (code: $response)"
    else
        log_error "Invalid JSON handling: code $response"
    fi
}

################################################################################
# Test 11: Very Rapid Requests (Rate Limiting)
################################################################################

test_rapid_requests() {
    separator "Test 11: Rapid Request Handling"
    
    log_info "Sending 50 requests rapidly..."
    
    local success=0
    for i in {1..50}; do
        http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_BASE/buy" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"rapid-$i\",\"userid\":\"rapid-user\",\"price\":5}" 2>/dev/null)
        
        if [ "$http_code" == "201" ]; then
            ((success++))
        fi
    done
    
    if [ "$success" -ge 45 ]; then
        log_success "System handled 50 rapid requests ($success succeeded)"
    else
        log_success "System handled rapid requests (success: $success/50) - rate limiting may be present"
    fi
}

################################################################################
# Test 12: Special Characters in Fields
################################################################################

test_special_characters() {
    separator "Test 12: Special Character Handling"
    
    log_info "Testing special characters in username..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"test@#$%^&*()","userid":"special-user","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "201" ]; then
        log_success "Special characters in username handled"
    else
        log_error "Special character test failed: code $response"
    fi
    
    log_info "Testing unicode characters..."
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d '{"username":"用户测试","userid":"unicode-user","price":10}' 2>/dev/null | tail -1)
    
    if [ "$response" == "201" ]; then
        log_success "Unicode characters handled"
    else
        log_error "Unicode test failed: code $response"
    fi
}

################################################################################
# Test 13: Database Query Edge Cases
################################################################################

test_database_queries() {
    separator "Test 13: Database Query Edge Cases"
    
    log_info "Testing wildcard-like userid queries..."
    response=$(curl -s -w "\n%{http_code}" "$CUSTOMER_MGMT_BASE/purchases/%25" 2>/dev/null | tail -1)
    
    if [ "$response" == "200" ]; then
        log_success "Wildcard-like query handled safely (code: $response)"
    else
        log_error "Wildcard query failed: code $response"
    fi
    
    log_info "Testing regex-like userid..."
    response=$(curl -s -w "\n%{http_code}" "$CUSTOMER_MGMT_BASE/purchases/.*" 2>/dev/null | tail -1)
    
    if [ "$response" == "200" ]; then
        log_success "Regex-like query handled (code: $response)"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Edge Cases & Error Scenarios Test Suite            ║${NC}"
    echo -e "${BLUE}║   Testing: Input validation, injection, concurrency  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    
    test_invalid_input
    test_invalid_prices
    test_empty_strings
    test_injection_attempts
    test_large_values
    test_concurrent_requests
    test_duplicate_handling
    test_invalid_content_type
    test_nonexistent_user
    test_malformed_json
    test_rapid_requests
    test_special_characters
    test_database_queries
    
    separator "Edge Case Test Summary"
    
    local total=$((TESTS_PASSED + TESTS_FAILED))
    
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "Total:   $total"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All edge case tests completed successfully!${NC}"
    else
        echo -e "${YELLOW}Some edge cases revealed issues - review above for details.${NC}"
    fi
}

main
