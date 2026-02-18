#!/bin/bash
# Smoke Tests - Tests de base pour valider le déploiement

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Couleurs pour l'output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test functions
test_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

pass_test() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

# 1. Santé du Cluster
test_header "Santé du Cluster"

if kubectl cluster-info &>/dev/null; then
    pass_test "Cluster accessible"
else
    fail_test "Cluster not accessible"
    exit 1
fi

# Vérifier les nœuds
READY_NODES=$(kubectl get nodes -o jsonpath='{range .items[?(@.status.conditions[?(@.type=="Ready")].status=="True")]}{.metadata.name}{"\n"}{end}' | wc -l)
if [ "$READY_NODES" -gt 0 ]; then
    pass_test "Found $READY_NODES ready nodes"
else
    fail_test "No ready nodes found"
    exit 1
fi

# 2. Disponibilité des Namespaces
test_header "Disponibilité des Namespaces"

for ns in default kube-system kube-public monitoring envoy-gateway-system demo-app-v1 demo-app-v2; do
    if kubectl get namespace "$ns" &>/dev/null; then
        pass_test "Namespace '$ns' exists"
    else
        fail_test "Namespace '$ns' not found"
    fi
done

# 3. Pod Status
test_header "Pod Status"

# CoreDNS
if kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q "Running"; then
    pass_test "CoreDNS running"
else
    fail_test "CoreDNS not running"
fi

# 4. Gateway API
test_header "Gateway API"

if kubectl get gatewayclass envoy &>/dev/null; then
    pass_test "GatewayClass 'envoy' exists"
else
    fail_test "GatewayClass 'envoy' not found"
fi

if kubectl get gateway production &>/dev/null; then
    pass_test "Gateway 'production' exists"
else
    fail_test "Gateway 'production' not found"
fi

# 5. Services
test_header "Services"

# Vérifier le service Envoy Gateway
if kubectl get svc -n envoy-gateway-system | grep -q "envoy"; then
    pass_test "Envoy Gateway service exists"
else
    fail_test "Envoy Gateway service not found"
fi

# Vérifier le service NGINX Ingress
if kubectl get svc -n nginx-ingress | grep -q "nginx"; then
    pass_test "NGINX Ingress service exists"
else
    fail_test "NGINX Ingress service not found"
fi

# 6. DNS Resolution
test_header "DNS Resolution"

if kubectl run -it --rm dnstester --image=busybox:latest --restart=Never -- nslookup kubernetes.default 2>/dev/null | grep -q "kubernetes.default"; then
    pass_test "DNS resolution working"
else
    fail_test "DNS resolution failed"
fi

# 7. Monitoring Stack
test_header "Monitoring Stack"

if kubectl get svc -n monitoring prometheus &>/dev/null; then
    pass_test "Prometheus service exists"
else
    fail_test "Prometheus service not found"
fi

if kubectl get svc -n monitoring grafana &>/dev/null; then
    pass_test "Grafana service exists"
else
    fail_test "Grafana service not found"
fi

# 8. Application Deployments
test_header "Application Deployments"

if kubectl get deployment -n demo-app-v1 demo-app-v1 &>/dev/null; then
    pass_test "Demo App v1 deployment exists"
else
    fail_test "Demo App v1 deployment not found"
fi

if kubectl get deployment -n demo-app-v2 demo-app-v2 &>/dev/null; then
    pass_test "Demo App v2 deployment exists"
else
    fail_test "Demo App v2 deployment not found"
fi

# 9. Network Connectivity
test_header "Network Connectivity"

# Test pod-to-service communication
TEST_POD=$(kubectl run -it --rm nettest --image=curlimages/curl:latest --restart=Never -- curl -s http://kubernetes.default 2>/dev/null | head -1)
if [ ! -z "$TEST_POD" ]; then
    pass_test "Pod-to-service communication works"
else
    fail_test "Pod-to-service communication failed"
fi

# 10. Summary
test_header "Test Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED/$TOTAL_TESTS"
echo -e "${RED}Failed:${NC} $TESTS_FAILED/$TOTAL_TESTS"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All smoke tests passed!${NC}\n"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}\n"
    exit 1
fi
