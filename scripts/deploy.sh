#!/bin/bash

###############################################################################
# Script de déploiement automatisé - Migration NGINX → Gateway API
# Usage: ./deploy.sh [--auto|--step <phase>]
###############################################################################

set -euo pipefail

# Couleurs pour l'output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
K8S_DIR="${PROJECT_ROOT}/kubernetes"

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    local missing_tools=()
    
    # Vérifier les outils requis
    for tool in terraform kubectl ansible-playbook talosctl helm; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Outils manquants: ${missing_tools[*]}"
        log_error "Veuillez installer les outils manquants avant de continuer."
        exit 1
    fi
    
    # Vérifier les versions
    log_info "Terraform: $(terraform version | head -n1)"
    log_info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    log_info "talosctl: $(talosctl version --client --short 2>/dev/null || echo 'version check failed')"
    log_info "Ansible: $(ansible --version | head -n1)"
    log_info "Helm: $(helm version --short)"
    
    log_success "Tous les outils requis sont installés ✓"
}

# Phase 1: Infrastructure Terraform
deploy_infrastructure() {
    log_info "Phase 1: Déploiement de l'infrastructure Proxmox..."
    
    cd "$TERRAFORM_DIR"
    
    # Vérifier si terraform.tfvars existe
    if [ ! -f "terraform.tfvars" ]; then
        log_error "Fichier terraform.tfvars manquant !"
        log_info "Copiez terraform.tfvars.example vers terraform.tfvars et configurez-le."
        exit 1
    fi
    
    # Terraform init
    log_info "Initialisation de Terraform..."
    terraform init
    
    # Terraform plan
    log_info "Planification de l'infrastructure..."
    terraform plan -out=tfplan
    
    # Demander confirmation
    if [ "${AUTO_DEPLOY:-false}" != "true" ]; then
        read -p "Continuer avec le déploiement? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Déploiement annulé."
            exit 0
        fi
    fi
    
    # Terraform apply
    log_info "Application de l'infrastructure..."
    terraform apply tfplan
    
    # Sauvegarder les configs
    log_info "Sauvegarde de talosconfig et kubeconfig..."
    mkdir -p ~/.talos ~/.kube
    terraform output -raw talosconfig > ~/.talos/config
    terraform output -raw kubeconfig > ~/.kube/config
    chmod 600 ~/.talos/config ~/.kube/config
    
    log_success "Infrastructure déployée avec succès ✓"
    
    # Attendre que les nœuds soient prêts
    log_info "Attente de la disponibilité du cluster (jusqu'à 5 minutes)..."
    local timeout=300
    local elapsed=0
    
    while ! kubectl get nodes &>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            log_error "Timeout: le cluster n'est pas disponible après ${timeout}s"
            exit 1
        fi
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo
    
    log_success "Cluster Kubernetes opérationnel ✓"
    kubectl get nodes
}

# Phase 2: Bootstrap Kubernetes
deploy_kubernetes() {
    log_info "Phase 2: Configuration de Kubernetes..."
    
    cd "$ANSIBLE_DIR"
    
    # Vérifier la connexion au cluster
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi
    
    # Exécuter le playbook de prérequis
    log_info "Exécution du playbook de prérequis..."
    ansible-playbook -i inventory/hosts playbooks/00-prerequisites.yml
    
    log_success "Kubernetes configuré avec succès ✓"
}

# Phase 3: Déployer Gateway API
deploy_gateway_api() {
    log_info "Phase 3: Déploiement de Gateway API..."
    
    cd "$ANSIBLE_DIR"
    
    # Déployer Gateway API
    log_info "Installation de Gateway API et Envoy Gateway..."
    ansible-playbook -i inventory/hosts playbooks/02-deploy-gateway-api.yml
    
    # Vérifier le déploiement
    log_info "Vérification du déploiement Gateway API..."
    kubectl get gatewayclass
    kubectl get gateway -n gateway-system
    
    log_success "Gateway API déployé avec succès ✓"
}

# Phase 4: Déployer les applications de démo
deploy_apps() {
    log_info "Phase 4: Déploiement des applications de démonstration..."
    
    cd "$ANSIBLE_DIR"
    
    # Déployer les apps
    log_info "Déploiement des applications v1 (NGINX) et v2 (Gateway API)..."
    ansible-playbook -i inventory/hosts playbooks/03-deploy-apps.yml
    
    # Vérifier les déploiements
    log_info "Vérification des déploiements..."
    kubectl get deployments -n demo-apps
    kubectl get services -n demo-apps
    kubectl get httproute -n demo-apps
    
    log_success "Applications déployées avec succès ✓"
}

# Afficher le résumé final
show_summary() {
    log_success "
╔════════════════════════════════════════════════════════════════╗
║          DÉPLOIEMENT TERMINÉ AVEC SUCCÈS !                     ║
╚════════════════════════════════════════════════════════════════╝
"
    
    echo "Informations du cluster:"
    kubectl cluster-info
    echo
    
    echo "Nœuds déployés:"
    kubectl get nodes -o wide
    echo
    
    echo "Gateway API:"
    kubectl get gateway -n gateway-system
    echo
    
    echo "Applications:"
    kubectl get deployments,services,httproute -n demo-apps
    echo
    
    echo "Accès aux applications:"
    GATEWAY_IP=$(kubectl get svc -n envoy-gateway-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
    echo "  App V2 (Gateway API): curl -H 'Host: app-v2.example.com' http://${GATEWAY_IP}/"
    echo
    
    echo "Prochaines étapes:"
    echo "  1. Tester les applications de démo"
    echo "  2. Migrer vos applications existantes: ./scripts/migrate.sh"
    echo "  3. Consulter les dashboards de monitoring"
    echo
    
    echo "Documentation complète dans docs/"
}

# Main
main() {
    echo "
╔════════════════════════════════════════════════════════════════╗
║    Migration NGINX Ingress → Gateway API - Déploiement        ║
╚════════════════════════════════════════════════════════════════╝
"
    
    # Parser les arguments
    AUTO_DEPLOY=false
    STEP=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_DEPLOY=true
                shift
                ;;
            --step)
                STEP="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --auto              Déploiement automatique sans confirmation"
                echo "  --step <phase>      Exécuter une phase spécifique:"
                echo "                        infrastructure  - Déployer l'infra Proxmox"
                echo "                        kubernetes      - Configurer Kubernetes"
                echo "                        gateway-api     - Déployer Gateway API"
                echo "                        apps            - Déployer les applications"
                echo "  -h, --help          Afficher cette aide"
                exit 0
                ;;
            *)
                log_error "Option inconnue: $1"
                exit 1
                ;;
        esac
    done
    
    # Vérifier les prérequis
    check_prerequisites
    
    # Exécuter les phases
    if [ -z "$STEP" ]; then
        # Déploiement complet
        deploy_infrastructure
        deploy_kubernetes
        deploy_gateway_api
        deploy_apps
        show_summary
    else
        # Déploiement par phase
        case $STEP in
            infrastructure)
                deploy_infrastructure
                ;;
            kubernetes)
                deploy_kubernetes
                ;;
            gateway-api)
                deploy_gateway_api
                ;;
            apps)
                deploy_apps
                ;;
            *)
                log_error "Phase inconnue: $STEP"
                exit 1
                ;;
        esac
    fi
    
    log_success "Terminé !"
}

# Exécuter le script
main "$@"
