#!/bin/bash
# ==========================================
# Script de vérification du déploiement
# Architecture: 1 CP + 1 Obs-Ubuntu + 2 Workers
# ==========================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
EXPECTED_NODES=4  # 1 CP + 2 W + 1 Ubuntu
EXPECTED_CP_COUNT=1
EXPECTED_WORKER_COUNT=2
CONTROL_PLANE_IP="x.x.x.130"
WORKER1_IP="x.x.x.132"
WORKER2_IP="x.x.x.133"
OBSERVABILITY_IP="x.x.x.131"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Vérification Architecture Kubernetes                    ║${NC}"
echo -e "${BLUE}║   1 CP Talos + 1 Obs Ubuntu + 2 Workers Talos            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Vérifier connectivité réseau
echo -e "${YELLOW}[1/6] Vérification de la connectivité réseau...${NC}"
check_ip() {
    local ip=$1
    local name=$2
    if ping -c 1 -W 2 "$ip" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $name ($ip): Reachable"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name ($ip): Not reachable"
        return 1
    fi
}

cp_ok=0
w1_ok=0
w2_ok=0
obs_ok=0

check_ip "$CONTROL_PLANE_IP" "Control Plane" && cp_ok=1
check_ip "$WORKER1_IP" "Worker 1" && w1_ok=1
check_ip "$WORKER2_IP" "Worker 2" && w2_ok=1
check_ip "$OBSERVABILITY_IP" "Observability" && obs_ok=1

if [[ $cp_ok -eq 0 ]] || [[ $w1_ok -eq 0 ]] || [[ $w2_ok -eq 0 ]]; then
    echo -e "${RED}✗ Erreur: Nœuds Kubernetes inaccessibles${NC}"
    exit 1
fi

if [[ $obs_ok -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Avertissement: Nœud observabilité inaccessible${NC}"
fi
echo ""

# 2. Vérifier Kubernetes nodes
echo -e "${YELLOW}[2/6] Vérification des nœuds Kubernetes...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "  ${RED}✗${NC} kubectl non trouvé"
    exit 1
fi

nodes=$(kubectl get nodes -o json)
node_count=$(echo "$nodes" | jq '.items | length')

if [[ $node_count -ge 3 ]]; then
    echo -e "  ${GREEN}✓${NC} Nœuds détectés: $node_count"
else
    echo -e "  ${RED}✗${NC} Nombre de nœuds insuffisant: $node_count (attendu: >= 3)"
    exit 1
fi

# Afficher les nœuds
echo ""
echo "  Nœuds:"
kubectl get nodes -o wide | tail -n +2 | while read line; do
    echo "    $line"
done
echo ""

# 3. Vérifier Control Plane
echo -e "${YELLOW}[3/6] Vérification du Control Plane...${NC}"
cp_status=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.roles[] | contains("control-plane")) | .status.conditions[] | select(.type=="Ready") | .status')

if [[ "$cp_status" == "True" ]]; then
    echo -e "  ${GREEN}✓${NC} Control Plane: Ready"
else
    echo -e "  ${RED}✗${NC} Control Plane: Not Ready"
    exit 1
fi
echo ""

# 4. Vérifier Workers
echo -e "${YELLOW}[4/6] Vérification des Workers...${NC}"
workers_ready=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.roles[] | contains("worker")) | .status.conditions[] | select(.type=="Ready") | .status' | grep -c "True" || echo "0")

if [[ $workers_ready -ge 2 ]]; then
    echo -e "  ${GREEN}✓${NC} Workers: $workers_ready/2 Ready"
else
    echo -e "  ${YELLOW}⚠${NC} Workers: $workers_ready/2 Ready (attendu: 2)"
fi
echo ""

# 5. Vérifier Gateway API
echo -e "${YELLOW}[5/6] Vérification du Gateway API...${NC}"
if kubectl get ns gateway-system &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Namespace: gateway-system existe"
    
    gw_pods=$(kubectl get pods -n gateway-system -o json | jq '.items | length')
    echo -e "  ${GREEN}✓${NC} Pods: $gw_pods dans gateway-system"
else
    echo -e "  ${YELLOW}⚠${NC} Namespace: gateway-system non trouvé (déploiement pas encore effectué)"
fi
echo ""

# 6. Vérifier Observabilité
echo -e "${YELLOW}[6/6] Vérification de l'Observabilité...${NC}"
if [[ $obs_ok -eq 1 ]]; then
    echo "  Vérification des services:"
    
    # Prometheus
    if timeout 2 bash -c "echo > /dev/tcp/$OBSERVABILITY_IP/9090" 2> /dev/null; then
        echo -e "    ${GREEN}✓${NC} Prometheus (9090): Accessible"
    else
        echo -e "    ${YELLOW}⚠${NC} Prometheus (9090): Not accessible (peut ne pas être déployé)"
    fi
    
    # Grafana
    if timeout 2 bash -c "echo > /dev/tcp/$OBSERVABILITY_IP/3000" 2> /dev/null; then
        echo -e "    ${GREEN}✓${NC} Grafana (3000): Accessible"
    else
        echo -e "    ${YELLOW}⚠${NC} Grafana (3000): Not accessible (peut ne pas être déployé)"
    fi
    
    # Loki
    if timeout 2 bash -c "echo > /dev/tcp/$OBSERVABILITY_IP/3100" 2> /dev/null; then
        echo -e "    ${GREEN}✓${NC} Loki (3100): Accessible"
    else
        echo -e "    ${YELLOW}⚠${NC} Loki (3100): Not accessible (peut ne pas être déployé)"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Nœud observabilité non accessible"
fi
echo ""

# Résumé
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Résumé de la vérification                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo "  Architecture déployée:"
echo "    • Control Plane Talos: $CONTROL_PLANE_IP"
echo "    • Worker 1 Talos: $WORKER1_IP"
echo "    • Worker 2 Talos: $WORKER2_IP"
echo "    • Observabilité Ubuntu: $OBSERVABILITY_IP"
echo ""

echo "  État du cluster:"
echo -e "    ${GREEN}✓${NC} Kubernetes: Running"
kubectl cluster-info | grep -E "Kubernetes master|Kubernetes control plane"
echo ""

echo "  Étapes suivantes:"
echo "    1. Configurer Kubernetes API VIP (x.x.x.129)"
echo "    2. Déployer les manifestes: kubectl apply -f kubernetes/"
echo "    3. Configurer observabilité: ssh ubuntu@x.x.x.131"
echo "    4. Tester les routes: curl http://app-v2.example.com"
echo ""

echo -e "${GREEN}✓ Vérification complète!${NC}"
