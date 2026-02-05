#!/bin/bash

###############################################################################
# Script de migration NGINX Ingress → Gateway API
# Usage: ./migrate.sh --app <app-name> [--dry-run|--execute]
###############################################################################

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_DIR="${PROJECT_ROOT}/migrations"
mkdir -p "$MIGRATION_DIR"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Analyser un Ingress existant
analyze_ingress() {
    local app_name=$1
    local namespace=${2:-default}
    
    log_info "Analyse de l'Ingress pour l'application: $app_name"
    
    # Récupérer l'Ingress
    if ! kubectl get ingress "$app_name" -n "$namespace" &>/dev/null; then
        log_error "Ingress '$app_name' introuvable dans le namespace '$namespace'"
        return 1
    fi
    
    local ingress_yaml="${MIGRATION_DIR}/${app_name}-ingress-original.yaml"
    kubectl get ingress "$app_name" -n "$namespace" -o yaml > "$ingress_yaml"
    
    log_success "Ingress sauvegardé: $ingress_yaml"
    
    # Extraire les informations clés
    local host=$(kubectl get ingress "$app_name" -n "$namespace" -o jsonpath='{.spec.rules[0].host}')
    local path=$(kubectl get ingress "$app_name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].path}')
    local service=$(kubectl get ingress "$app_name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
    local port=$(kubectl get ingress "$app_name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
    
    echo "
Configuration Ingress détectée:
   Host: $host
   Path: $path
   Service: $service
   Port: $port
"
    
    # Vérifier les annotations à risque
    log_info "Vérification des annotations NGINX..."
    local annotations=$(kubectl get ingress "$app_name" -n "$namespace" -o jsonpath='{.metadata.annotations}')
    
    if echo "$annotations" | grep -q "nginx.ingress.kubernetes.io/configuration-snippet\|nginx.ingress.kubernetes.io/server-snippet"; then
        log_warning "ATTENTION: Snippets détectés (risque CVE-2025-1974)"
        log_warning "    Ces snippets devront être convertis en policies Gateway API"
    fi
    
    # Sauvegarder les métadonnées
    cat > "${MIGRATION_DIR}/${app_name}-metadata.json" <<EOF
{
  "app_name": "$app_name",
  "namespace": "$namespace",
  "host": "$host",
  "path": "$path",
  "service": "$service",
  "port": $port,
  "ingress_yaml": "$ingress_yaml"
}
EOF
    
    log_success "Analyse terminée ✓"
    return 0
}

# Générer HTTPRoute
generate_httproute() {
    local app_name=$1
    local metadata_file="${MIGRATION_DIR}/${app_name}-metadata.json"
    
    if [ ! -f "$metadata_file" ]; then
        log_error "Métadonnées introuvables. Exécutez d'abord l'analyse."
        return 1
    fi
    
    # Lire les métadonnées
    local namespace=$(jq -r '.namespace' "$metadata_file")
    local host=$(jq -r '.host' "$metadata_file")
    local path=$(jq -r '.path' "$metadata_file")
    local service=$(jq -r '.service' "$metadata_file")
    local port=$(jq -r '.port' "$metadata_file")
    
    log_info "Génération de HTTPRoute pour $app_name..."
    
    local httproute_yaml="${MIGRATION_DIR}/${app_name}-httproute.yaml"
    
    cat > "$httproute_yaml" <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${app_name}-route
  namespace: ${namespace}
  annotations:
    description: "Migré depuis NGINX Ingress"
    migration-date: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  labels:
    app: ${app_name}
    routing: gateway-api
    migrated-from: nginx-ingress
spec:
  parentRefs:
    - name: main-gateway
      namespace: gateway-system
      sectionName: http
  hostnames:
    - "${host}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: "${path}"
      backendRefs:
        - name: ${service}
          port: ${port}
          weight: 100
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Routing-Method
                value: gateway-api
EOF
    
    log_success "HTTPRoute généré: $httproute_yaml"
    
    # Afficher un diff conceptuel
    echo "
Comparaison Ingress → HTTPRoute:
┌─────────────────────┬──────────────────────────────────────────┐
│ Ingress (Avant)     │ HTTPRoute (Après)                        │
├─────────────────────┼──────────────────────────────────────────┤
│ Annotations         │ CRDs typés                               │
│ Couplé à NGINX      │ Standard CNCF                            │
│ Snippets (risqué)   │ Policies explicites                      │
│ Configuration mixte │ Séparation Gateway/Route                 │
└─────────────────────┴──────────────────────────────────────────┘
"
}

# Tester la migration (dry-run)
test_migration() {
    local app_name=$1
    local httproute_yaml="${MIGRATION_DIR}/${app_name}-httproute.yaml"
    
    if [ ! -f "$httproute_yaml" ]; then
        log_error "HTTPRoute introuvable. Générez-le d'abord."
        return 1
    fi
    
    log_info "Test de validation (dry-run)..."
    
    # Valider le YAML
    if kubectl apply --dry-run=client -f "$httproute_yaml" &>/dev/null; then
        log_success "✓ YAML valide"
    else
        log_error "✗ YAML invalide"
        return 1
    fi
    
    # Vérifier que le Gateway existe
    if kubectl get gateway main-gateway -n gateway-system &>/dev/null; then
        log_success "✓ Gateway 'main-gateway' disponible"
    else
        log_error "✗ Gateway 'main-gateway' introuvable"
        return 1
    fi
    
    # Vérifier que le service existe
    local metadata_file="${MIGRATION_DIR}/${app_name}-metadata.json"
    local namespace=$(jq -r '.namespace' "$metadata_file")
    local service=$(jq -r '.service' "$metadata_file")
    
    if kubectl get service "$service" -n "$namespace" &>/dev/null; then
        log_success "✓ Service '$service' disponible"
    else
        log_error "✗ Service '$service' introuvable"
        return 1
    fi
    
    log_success "Tous les tests de validation passés !"
    return 0
}

# Exécuter la migration
execute_migration() {
    local app_name=$1
    local httproute_yaml="${MIGRATION_DIR}/${app_name}-httproute.yaml"
    local metadata_file="${MIGRATION_DIR}/${app_name}-metadata.json"
    
    log_warning "Cette opération va appliquer HTTPRoute en production"
    
    if [ "${CONFIRM:-false}" != "true" ]; then
        read -p "Continuer? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Migration annulée"
            return 1
        fi
    fi
    
    # Appliquer HTTPRoute
    log_info "Application de HTTPRoute..."
    if kubectl apply -f "$httproute_yaml"; then
        log_success "✓ HTTPRoute appliqué"
    else
        log_error "✗ Échec de l'application de HTTPRoute"
        return 1
    fi
    
    # Attendre que HTTPRoute soit accepté
    log_info "Attente de la validation par le Gateway..."
    sleep 5
    
    # Vérifier le statut
    local namespace=$(jq -r '.namespace' "$metadata_file")
    local status=$(kubectl get httproute "${app_name}-route" -n "$namespace" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')
    
    if [ "$status" = "True" ]; then
        log_success "✓ HTTPRoute accepté par le Gateway"
    else
        log_warning "HTTPRoute en attente de validation"
    fi
    
    # Instructions post-migration
    echo "
Migration exécutée avec succès !

Étapes de validation recommandées:
1. Tester le routage via Gateway API:
   curl -H 'Host: $(jq -r '.host' "$metadata_file")' http://<GATEWAY-IP>$(jq -r '.path' "$metadata_file")

2. Comparer les réponses (Ingress vs Gateway API)

3. Si OK, désactiver l'ancien Ingress:
   kubectl annotate ingress $app_name -n $namespace kubernetes.io/ingress.class-

4. Après validation complète, supprimer l'Ingress:
   kubectl delete ingress $app_name -n $namespace

Ne supprimez l'Ingress qu'après validation complète !
"
}

# Main
main() {
    echo "
╔════════════════════════════════════════════════════════════════╗
║       Migration NGINX Ingress → Gateway API                    ║
╚════════════════════════════════════════════════════════════════╝
"
    
    # Parser les arguments
    APP_NAME=""
    NAMESPACE="default"
    MODE="analyze"
    CONFIRM=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)
                APP_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --analyze)
                MODE="analyze"
                shift
                ;;
            --generate)
                MODE="generate"
                shift
                ;;
            --dry-run)
                MODE="dry-run"
                shift
                ;;
            --execute)
                MODE="execute"
                shift
                ;;
            --yes)
                CONFIRM=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 --app <app-name> [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --app <name>        Nom de l'application (requis)"
                echo "  --namespace <ns>    Namespace (défaut: default)"
                echo "  --analyze           Analyser l'Ingress existant"
                echo "  --generate          Générer HTTPRoute"
                echo "  --dry-run           Tester la migration"
                echo "  --execute           Exécuter la migration"
                echo "  --yes               Pas de confirmation interactive"
                echo "  -h, --help          Afficher cette aide"
                exit 0
                ;;
            *)
                log_error "Option inconnue: $1"
                exit 1
                ;;
        esac
    done
    
    # Vérifier les paramètres requis
    if [ -z "$APP_NAME" ]; then
        log_error "Le nom de l'application est requis (--app)"
        exit 1
    fi
    
    # Exécuter le mode sélectionné
    case $MODE in
        analyze)
            analyze_ingress "$APP_NAME" "$NAMESPACE"
            log_info "Prochaine étape: $0 --app $APP_NAME --generate"
            ;;
        generate)
            generate_httproute "$APP_NAME"
            log_info "Prochaine étape: $0 --app $APP_NAME --dry-run"
            ;;
        dry-run)
            if test_migration "$APP_NAME"; then
                log_info "Prochaine étape: $0 --app $APP_NAME --execute"
            fi
            ;;
        execute)
            execute_migration "$APP_NAME"
            ;;
    esac
}

# Exécuter
main "$@"
