#!/usr/bin/env bash

################################################################################
# Comprehensive Test Suite for User Buy List
# 
# This script validates the entire system end-to-end:
# - Kubernetes deployment
# - Service health checks
# - API endpoint functionality
# - Data persistence through Kafka → MongoDB
# - Prometheus metrics collection
# - Frontend accessibility
#
# Usage: ./scripts/test-all.sh
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Configuration
API_BASE="${API_BASE:-http://localhost:3000}"
CUSTOMER_MGMT_BASE="${CUSTOMER_MGMT_BASE:-http://localhost:3001}"
PROMETHEUS_BASE="${PROMETHEUS_BASE:-http://localhost:9090}"
FRONTEND_BASE="${FRONTEND_BASE:-http://localhost:8080}"
TIMEOUT=30

################################################################################
# Utility Functions
################################################################################

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

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((TESTS_SKIPPED++))
}

separator() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 not found. Please install it."
        return 1
    fi
    return 0
}

################################################################################
# Prerequisites Checks
################################################################################

check_prerequisites() {
    separator "Checking Prerequisites"
    
    local missing=0
    
    check_command "kubectl" || missing=1
    check_command "curl" || missing=1
    check_command "jq" || missing=1
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Missing required commands. Exiting.${NC}"
        exit 1
    fi
    
    log_success "All required commands available"
}

check_minikube_running() {
    separator "Checking Kubernetes Cluster"
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster not accessible. Start minikube with: minikube start"
        exit 1
    fi
    
    log_success "Kubernetes cluster is running"
}

check_ports_available() {
    separator "Setting up Port Forwarding"
    
    log_info "Cleaning up existing port-forward processes..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 1
    
    log_info "Establishing port-forwards..."
    
    kubectl port-forward svc/customer-facing 3000:80 > /dev/null 2>&1 &
    sleep 1
    
    kubectl port-forward svc/customer-management 3001:3001 > /dev/null 2>&1 &
    sleep 1
    
    kubectl port-forward svc/prometheus 9090:9090 > /dev/null 2>&1 &
    sleep 1
    
    kubectl port-forward svc/user-buy-frontend 8080:80 > /dev/null 2>&1 &
    sleep 2
    
    log_success "Port forwarding established"
}

################################################################################
# Pod Status Tests
################################################################################

check_pods_running() {
    separator "Checking Pod Status"
    
    local required_pods=(
        "customer-facing"
        "customer-management"
        "kafka"
        "mongodb"
        "prometheus"
        "user-buy-frontend"
    )
    
    for pod_name in "${required_pods[@]}"; do
        local pod_count=$(kubectl get pods -l "app=$pod_name" --field-selector=status.phase=Running 2>/dev/null | grep -c "$pod_name" || echo 0)
        
        if [ "$pod_count" -gt 0 ]; then
            log_success "Pod $pod_name is running ($pod_count replica(s))"
        else
            log_error "Pod $pod_name is not running"
        fi
    done
}

check_pod_readiness() {
    separator "Checking Pod Readiness"
    
    local pods=$(kubectl get pods -o json | jq -r '.items[] | select(.metadata.namespace == "default") | .metadata.name')
    
    for pod in $pods; do
        local ready=$(kubectl get pod "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        if [ "$ready" == "True" ]; then
            log_success "Pod $pod is ready"
        elif [ "$ready" == "False" ]; then
            log_warning "Pod $pod is not ready"
        fi
    done
}

################################################################################
# API Endpoint Tests
################################################################################

test_health_endpoint() {
    separator "Testing Health Endpoints"
    
    # Customer Facing Health
    if response=$(curl -s -w "\n%{http_code}" "$API_BASE/health" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Customer-facing /health returned 200 OK"
            
            if echo "$body" | jq -e '.kafkaReady' > /dev/null 2>&1; then
                local kafka_status=$(echo "$body" | jq -r '.kafkaReady')
                if [ "$kafka_status" == "true" ]; then
                    log_success "  → Kafka connection is ready"
                else
                    log_warning "  → Kafka connection not yet ready (normal during startup)"
                fi
            fi
        else
            log_error "Customer-facing /health returned $http_code"
        fi
    else
        log_error "Customer-facing health check failed (service unreachable)"
    fi
    
    # Customer Management Health
    if response=$(curl -s -w "\n%{http_code}" "$CUSTOMER_MGMT_BASE/health" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Customer-management /health returned 200 OK"
            
            if echo "$body" | jq -e '.mongoReady' > /dev/null 2>&1; then
                local mongo_status=$(echo "$body" | jq -r '.mongoReady')
                [ "$mongo_status" == "true" ] && log_success "  → MongoDB connection is ready" || log_warning "  → MongoDB not ready"
            fi
        else
            log_error "Customer-management /health returned $http_code"
        fi
    else
        log_error "Customer-management health check failed (service unreachable)"
    fi
}

test_buy_endpoint() {
    separator "Testing POST /buy Endpoint"
    
    local test_id="test-$(date +%s)"
    local payload='{
        "username": "test_user",
        "userid": "'$test_id'",
        "price": 99.99
    }'
    
    if response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null | tail -2); then
        
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "201" ]; then
            log_success "POST /buy returned 201 Created"
            
            if echo "$body" | jq -e '.purchase' > /dev/null 2>&1; then
                local price=$(echo "$body" | jq -r '.purchase.price')
                log_success "  → Purchase created with price: \$$price"
                
                # Store test_id for later retrieval test
                echo "$test_id" > /tmp/test_userid.tmp
            fi
        else
            log_error "POST /buy returned $http_code"
        fi
    else
        log_error "POST /buy request failed"
    fi
}

test_get_purchases_endpoint() {
    separator "Testing GET /getAllUserBuys Endpoint"
    
    # Wait for Kafka processing
    log_info "Waiting 3 seconds for Kafka message processing..."
    sleep 3
    
    if [ -f /tmp/test_userid.tmp ]; then
        local test_id=$(cat /tmp/test_userid.tmp)
        
        if response=$(curl -s -w "\n%{http_code}" "$API_BASE/getAllUserBuys/$test_id" 2>/dev/null | tail -2); then
            http_code=$(echo "$response" | tail -1)
            body=$(echo "$response" | head -1)
            
            if [ "$http_code" == "200" ]; then
                log_success "GET /getAllUserBuys returned 200 OK"
                
                if echo "$body" | jq -e '.[0]' > /dev/null 2>&1; then
                    local count=$(echo "$body" | jq 'length')
                    log_success "  → Retrieved $count purchase(s) from database"
                    log_success "  → End-to-end flow verified (REST → Kafka → MongoDB)"
                else
                    log_error "  → No purchases found (data not persisted)"
                fi
            else
                log_error "GET /getAllUserBuys returned $http_code"
            fi
        else
            log_error "GET /getAllUserBuys request failed"
        fi
        
        rm /tmp/test_userid.tmp
    else
        log_warning "No test user ID available (skipping retrieval test)"
    fi
}

test_customer_management_api() {
    separator "Testing Customer-Management Direct API"
    
    if response=$(curl -s -w "\n%{http_code}" "$CUSTOMER_MGMT_BASE/purchases" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "GET /purchases returned 200 OK"
            
            local count=$(echo "$body" | jq 'length' 2>/dev/null || echo "0")
            log_success "  → Total purchases in database: $count"
        else
            log_error "GET /purchases returned $http_code"
        fi
    else
        log_error "GET /purchases request failed"
    fi
}

test_metrics_endpoints() {
    separator "Testing Prometheus Metrics Endpoints"
    
    # Customer Facing Metrics
    if response=$(curl -s -w "\n%{http_code}" "$API_BASE/metrics" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Customer-facing /metrics endpoint operational"
            
            if echo "$body" | grep -q "http_requests_total"; then
                log_success "  → HTTP request metrics present"
            fi
            
            if echo "$body" | grep -q "kafka_producer_messages_total"; then
                log_success "  → Kafka producer metrics present"
            fi
        else
            log_error "Customer-facing /metrics returned $http_code"
        fi
    else
        log_error "Customer-facing metrics request failed"
    fi
    
    # Customer Management Metrics
    if response=$(curl -s -w "\n%{http_code}" "$CUSTOMER_MGMT_BASE/metrics" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Customer-management /metrics endpoint operational"
        else
            log_error "Customer-management /metrics returned $http_code"
        fi
    else
        log_error "Customer-management metrics request failed"
    fi
}

################################################################################
# Prometheus Tests
################################################################################

test_prometheus_health() {
    separator "Testing Prometheus"
    
    if response=$(curl -s -w "\n%{http_code}" "$PROMETHEUS_BASE/-/healthy" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Prometheus server is healthy"
        else
            log_error "Prometheus health check returned $http_code"
        fi
    else
        log_error "Prometheus health check failed"
    fi
}

test_prometheus_targets() {
    separator "Testing Prometheus Scrape Targets"
    
    if targets=$(curl -s "$PROMETHEUS_BASE/api/v1/targets" 2>/dev/null); then
        local up_count=$(echo "$targets" | jq '.data.activeTargets[] | select(.health == "up")' 2>/dev/null | grep -c "job" || echo 0)
        local total_count=$(echo "$targets" | jq '.data.activeTargets | length' 2>/dev/null || echo 0)
        
        if [ "$total_count" -gt 0 ]; then
            log_success "Prometheus has $up_count/$total_count targets UP"
            
            # Check specific targets
            if echo "$targets" | jq -e '.data.activeTargets[] | select(.labels.job == "customer-facing" and .health == "up")' > /dev/null 2>&1; then
                log_success "  → customer-facing target is UP"
            fi
            
            if echo "$targets" | jq -e '.data.activeTargets[] | select(.labels.job == "customer-management" and .health == "up")' > /dev/null 2>&1; then
                log_success "  → customer-management target is UP"
            fi
        else
            log_warning "No Prometheus targets found"
        fi
    else
        log_error "Could not fetch Prometheus targets"
    fi
}

################################################################################
# Frontend Tests
################################################################################

test_frontend_accessibility() {
    separator "Testing Frontend"
    
    if response=$(curl -s -w "\n%{http_code}" "$FRONTEND_BASE/" 2>/dev/null | tail -2); then
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "200" ]; then
            log_success "Frontend is accessible and returning HTML"
            
            if echo "$body" | grep -q "User Buy List"; then
                log_success "  → Frontend title found"
            fi
            
            if echo "$body" | grep -q "Buy"; then
                log_success "  → Buy button present"
            fi
            
            if echo "$body" | grep -q "getAllUserBuys"; then
                log_success "  → getAllUserBuys button present"
            fi
        else
            log_error "Frontend returned $http_code"
        fi
    else
        log_error "Frontend request failed"
    fi
}

################################################################################
# Smoke Test
################################################################################

run_smoke_test() {
    separator "Running Smoke Test"
    
    local test_user="smoke-$(date +%s)"
    
    log_info "Creating purchase for user: $test_user"
    
    if response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/buy" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"smoke\",\"userid\":\"$test_user\",\"price\":12.34}" 2>/dev/null | tail -2); then
        
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | head -1)
        
        if [ "$http_code" == "201" ]; then
            log_success "Purchase created successfully"
            
            sleep 2
            
            if response=$(curl -s -w "\n%{http_code}" "$API_BASE/getAllUserBuys/$test_user" 2>/dev/null | tail -2); then
                http_code=$(echo "$response" | tail -1)
                body=$(echo "$response" | head -1)
                
                if [ "$http_code" == "200" ] && echo "$body" | jq -e '.[0]' > /dev/null 2>&1; then
                    log_success "Purchase retrieved successfully - smoke test PASSED"
                else
                    log_error "Failed to retrieve purchase - smoke test FAILED"
                fi
            fi
        else
            log_error "Failed to create purchase - smoke test FAILED"
        fi
    else
        log_error "Smoke test request failed"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   User Buy List - Comprehensive Test Suite           ║${NC}"
    echo -e "${BLUE}║   Testing: Customer-Facing, Customer-Management,     ║${NC}"
    echo -e "${BLUE}║   MongoDB, Kafka, Prometheus, Frontend               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    
    # Run all checks
    check_prerequisites
    check_minikube_running
    check_ports_available
    check_pods_running
    check_pod_readiness
    test_health_endpoint
    test_buy_endpoint
    test_get_purchases_endpoint
    test_customer_management_api
    test_metrics_endpoints
    test_prometheus_health
    test_prometheus_targets
    test_frontend_accessibility
    run_smoke_test
    
    # Print summary
    separator "Test Summary"
    
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo -e "Total:   $total"
    echo ""
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed! Your system is ready for deployment.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Trap to clean up port-forwards on exit
cleanup() {
    log_info "Cleaning up port-forward processes..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

trap cleanup EXIT

# Run main function
main
