#!/bin/bash

###############################################################################
# Script de validation du cluster et de la migration
# Usage: ./validate.sh [--check-ingress|--compare <app>|--full]
###############################################################################

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Compteurs de résultats
PASSED=0
FAILED=0
WARNINGS=0

check() {
    local description=$1
    local command=$2
    
    echo -n "  Vérification: $description ... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((FAILED++))
        return 1
    fi
}

check_cluster() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  VALIDATION DU CLUSTER KUBERNETES"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    check "kubectl accessible" "kubectl cluster-info"
    check "Cluster opérationnel" "kubectl get nodes | grep -q Ready"
    
    # Vérifier le nombre de nœuds Kubernetes
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    echo -n "  Vérification: Nombre de nœuds Kubernetes (attendu: 3) ... "
    if [ "$node_count" -eq 3 ]; then
        echo -e "${GREEN}✓${NC} ($node_count nœuds)"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} ($node_count nœuds, attendu: 3)"
        ((WARNINGS++))
    fi
    
    # Vérifier les control planes
    local cp_count=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l)
    echo -n "  Vérification: Control planes (attendu: 1) ... "
    if [ "$cp_count" -eq 1 ]; then
        echo -e "${GREEN}✓${NC} ($cp_count nœud)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} ($cp_count nœuds, attendu: 1)"
        ((FAILED++))
    fi
    
    # Vérifier les workers
    local worker_count=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l)
    echo -n "  Vérification: Workers (attendu: 2) ... "
    if [ "$worker_count" -eq 2 ]; then
        echo -e "${GREEN}✓${NC} ($worker_count nœuds)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} ($worker_count nœuds, attendu: 2)"
        ((FAILED++))
    fi
    
    check "Tous les nœuds Ready" "kubectl get nodes | grep -v NotReady | grep -q Ready"
    
    echo ""
}

check_gateway_api() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  VALIDATION DE GATEWAY API"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Vérifier les CRDs
    check "CRD GatewayClass" "kubectl get crd gatewayclasses.gateway.networking.k8s.io"
    check "CRD Gateway" "kubectl get crd gateways.gateway.networking.k8s.io"
    check "CRD HTTPRoute" "kubectl get crd httproutes.gateway.networking.k8s.io"
    
    # Vérifier Envoy Gateway
    check "Namespace envoy-gateway-system" "kubectl get namespace envoy-gateway-system"
    check "Déploiement Envoy Gateway" "kubectl get deployment envoy-gateway -n envoy-gateway-system"
    check "Pods Envoy Gateway running" "kubectl get pods -n envoy-gateway-system -l app=envoy-gateway | grep -q Running"
    
    # Vérifier GatewayClass
    check "GatewayClass 'eg' existe" "kubectl get gatewayclass eg"
    
    # Vérifier Gateway principal
    check "Gateway 'main-gateway' existe" "kubectl get gateway main-gateway -n gateway-system"
    
    # Vérifier le statut du Gateway
    echo -n "  Vérification: Gateway Programmed ... "
    local gateway_status=$(kubectl get gateway main-gateway -n gateway-system -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "Unknown")
    if [ "$gateway_status" = "True" ]; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} (Status: $gateway_status)"
        ((WARNINGS++))
    fi
    
    # Vérifier l'adresse du Gateway
    echo -n "  Vérification: Gateway a une adresse ... "
    local gateway_address=$(kubectl get gateway main-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "$gateway_address" ]; then
        echo -e "${GREEN}✓${NC} ($gateway_address)"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} (Adresse en attente)"
        ((WARNINGS++))
    fi
    
    echo ""
}

check_applications() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  VALIDATION DES APPLICATIONS"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    check "Namespace demo-apps" "kubectl get namespace demo-apps"
    
    # App V1 (NGINX Ingress - legacy)
    check "Déploiement demo-app-v1" "kubectl get deployment demo-app-v1 -n demo-apps"
    check "Service demo-app-v1" "kubectl get service demo-app-v1-service -n demo-apps"
    
    # App V2 (Gateway API - modern)
    check "Déploiement demo-app-v2" "kubectl get deployment demo-app-v2 -n demo-apps"
    check "Service demo-app-v2" "kubectl get service demo-app-v2-service -n demo-apps"
    check "HTTPRoute demo-app-v2" "kubectl get httproute demo-app-v2-route -n demo-apps"
    
    # Vérifier que les pods sont running
    echo -n "  Vérification: Pods demo-app-v1 running ... "
    local v1_ready=$(kubectl get deployment demo-app-v1 -n demo-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local v1_desired=$(kubectl get deployment demo-app-v1 -n demo-apps -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$v1_ready" -eq "$v1_desired" ] && [ "$v1_ready" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} ($v1_ready/$v1_desired)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} ($v1_ready/$v1_desired)"
        ((FAILED++))
    fi
    
    echo -n "  Vérification: Pods demo-app-v2 running ... "
    local v2_ready=$(kubectl get deployment demo-app-v2 -n demo-apps -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local v2_desired=$(kubectl get deployment demo-app-v2 -n demo-apps -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$v2_ready" -eq "$v2_desired" ] && [ "$v2_ready" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} ($v2_ready/$v2_desired)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} ($v2_ready/$v2_desired)"
        ((FAILED++))
    fi
    
    # Vérifier HTTPRoute status
    echo -n "  Vérification: HTTPRoute accepté ... "
    local httproute_status=$(kubectl get httproute demo-app-v2-route -n demo-apps -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "Unknown")
    if [ "$httproute_status" = "True" ]; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} (Status: $httproute_status)"
        ((WARNINGS++))
    fi
    
    echo ""
}

test_connectivity() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  TESTS DE CONNECTIVITÉ"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    local gateway_ip=$(kubectl get gateway main-gateway -n gateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    
    if [ -z "$gateway_ip" ]; then
        log_warning "Gateway IP non disponible, tests de connectivité ignorés"
        echo ""
        return
    fi
    
    log_info "Gateway IP: $gateway_ip"
    
    # Test app v2 via Gateway API
    echo -n "  Test HTTP: demo-app-v2 via Gateway API ... "
    if curl -s -H "Host: app-v2.example.com" "http://$gateway_ip/" | grep -q "Demo App V2" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} (Non accessible ou timeout)"
        ((WARNINGS++))
    fi
    
    echo ""
}

security_audit() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  AUDIT DE SÉCURITÉ"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Rechercher des Ingress avec snippets dangereux
    echo -n "  Vérification: Aucun snippet dangereux dans Ingress ... "
    local dangerous_ingress=$(kubectl get ingress --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations | to_entries[] | select(.key | contains("snippet"))) | .metadata.namespace + "/" + .metadata.name' 2>/dev/null)
    
    if [ -z "$dangerous_ingress" ]; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC}"
        log_error "Ingress avec snippets détectés:"
        echo "$dangerous_ingress"
        ((FAILED++))
    fi
    
    # Vérifier que Gateway API utilise TLS
    echo -n "  Vérification: TLS configuré sur Gateway ... "
    local tls_listeners=$(kubectl get gateway main-gateway -n gateway-system -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")]}' 2>/dev/null)
    if [ -n "$tls_listeners" ]; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}!${NC} (Listener HTTPS non configuré)"
        ((WARNINGS++))
    fi
    
    echo ""
}

show_summary() {
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  RÉSUMÉ DE LA VALIDATION"
    log_info "═══════════════════════════════════════════════════════════"
    echo ""
    
    local total=$((PASSED + FAILED + WARNINGS))
    
    echo -e "  ${GREEN}Tests réussis:${NC}    $PASSED / $total"
    echo -e "  ${RED}Tests échoués:${NC}    $FAILED / $total"
    echo -e "  ${YELLOW}Avertissements:${NC}   $WARNINGS / $total"
    echo ""
    
    if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              VALIDATION COMPLÈTE RÉUSSIE !                     ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
        return 0
    elif [ $FAILED -eq 0 ]; then
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║      Validation OK avec quelques avertissements               ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                VALIDATION ÉCHOUÉE                              ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
}

# Main
main() {
    echo "
╔════════════════════════════════════════════════════════════════╗
║          Validation - Migration NGINX → Gateway API            ║
╚════════════════════════════════════════════════════════════════╝
"
    
    # Parser les arguments
    MODE="${1:---full}"
    
    case $MODE in
        --full)
            check_cluster
            check_gateway_api
            check_applications
            test_connectivity
            security_audit
            show_summary
            ;;
        --cluster)
            check_cluster
            show_summary
            ;;
        --gateway)
            check_gateway_api
            show_summary
            ;;
        --apps)
            check_applications
            show_summary
            ;;
        --security)
            security_audit
            show_summary
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --full       Validation complète (défaut)"
            echo "  --cluster    Valider uniquement le cluster"
            echo "  --gateway    Valider uniquement Gateway API"
            echo "  --apps       Valider uniquement les applications"
            echo "  --security   Audit de sécurité uniquement"
            echo "  -h, --help   Afficher cette aide"
            exit 0
            ;;
        *)
            log_error "Option inconnue: $MODE"
            exit 1
            ;;
    esac
}

main "$@"
