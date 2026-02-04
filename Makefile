.PHONY: help init template deploy destroy clean validate test

# Variables
TERRAFORM_DIR := terraform
ANSIBLE_DIR := ansible
SCRIPTS_DIR := scripts

# Couleurs
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help: ## Afficher cette aide
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║  Migration NGINX Ingress → Gateway API - Commandes Make       ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

init: ## Initialiser le projet (vérifier les prérequis)
	@echo "$(BLUE)[INFO]$(NC) Vérification des prérequis..."
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)[ERROR]$(NC) terraform n'est pas installé"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)[ERROR]$(NC) kubectl n'est pas installé"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "$(RED)[ERROR]$(NC) ansible n'est pas installé"; exit 1; }
	@command -v talosctl >/dev/null 2>&1 || { echo "$(RED)[ERROR]$(NC) talosctl n'est pas installé"; exit 1; }
	@echo "$(GREEN)[SUCCESS]$(NC) Tous les prérequis sont satisfaits ✓"
	@echo ""
	@echo "$(BLUE)[INFO]$(NC) Initialisation de Terraform..."
	@cd $(TERRAFORM_DIR) && terraform init
	@echo "$(GREEN)[SUCCESS]$(NC) Projet initialisé ✓"

template: ## Préparer le template Talos sur Proxmox (à exécuter sur Proxmox)
	@echo "$(YELLOW)[WARNING]$(NC) Ce script doit être exécuté sur le serveur Proxmox"
	@echo "$(BLUE)[INFO]$(NC) Commande: ssh root@proxmox 'bash -s' < scripts/prepare-talos-template.sh"

plan: ## Planifier le déploiement Terraform
	@echo "$(BLUE)[INFO]$(NC) Planification de l'infrastructure..."
	@cd $(TERRAFORM_DIR) && terraform plan

deploy: init ## Déploiement complet automatique
	@echo "$(BLUE)[INFO]$(NC) Déploiement complet du projet..."
	@$(SCRIPTS_DIR)/deploy.sh --auto

deploy-infra: ## Déployer uniquement l'infrastructure Proxmox
	@echo "$(BLUE)[INFO]$(NC) Déploiement de l'infrastructure..."
	@$(SCRIPTS_DIR)/deploy.sh --step infrastructure

deploy-k8s: ## Configurer Kubernetes
	@echo "$(BLUE)[INFO]$(NC) Configuration de Kubernetes..."
	@$(SCRIPTS_DIR)/deploy.sh --step kubernetes

deploy-gateway: ## Déployer Gateway API
	@echo "$(BLUE)[INFO]$(NC) Déploiement de Gateway API..."
	@$(SCRIPTS_DIR)/deploy.sh --step gateway-api

deploy-apps: ## Déployer les applications de démo
	@echo "$(BLUE)[INFO]$(NC) Déploiement des applications..."
	@$(SCRIPTS_DIR)/deploy.sh --step apps

validate: ## Valider le cluster et les déploiements
	@echo "$(BLUE)[INFO]$(NC) Validation du cluster..."
	@kubectl get nodes
	@echo ""
	@echo "$(BLUE)[INFO]$(NC) Validation de Gateway API..."
	@kubectl get gatewayclass
	@kubectl get gateway -A
	@kubectl get httproute -A
	@echo ""
	@echo "$(BLUE)[INFO]$(NC) Validation des applications..."
	@kubectl get deployments -n demo-apps
	@kubectl get services -n demo-apps

test: ## Exécuter les tests de fumée
	@echo "$(BLUE)[INFO]$(NC) Exécution des tests..."
	@kubectl wait --for=condition=available --timeout=60s deployment/demo-app-v2 -n demo-apps || true
	@echo "$(GREEN)[SUCCESS]$(NC) Tests terminés ✓"

migrate: ## Migrer une application (Usage: make migrate APP=mon-app NAMESPACE=production)
	@if [ -z "$(APP)" ]; then \
		echo "$(RED)[ERROR]$(NC) Spécifiez APP=nom-app"; \
		exit 1; \
	fi
	@echo "$(BLUE)[INFO]$(NC) Migration de l'application $(APP)..."
	@$(SCRIPTS_DIR)/migrate.sh --app $(APP) --namespace $(or $(NAMESPACE),default) --analyze
	@$(SCRIPTS_DIR)/migrate.sh --app $(APP) --namespace $(or $(NAMESPACE),default) --generate
	@$(SCRIPTS_DIR)/migrate.sh --app $(APP) --namespace $(or $(NAMESPACE),default) --dry-run
	@echo ""
	@echo "$(YELLOW)[WARNING]$(NC) Migration préparée. Pour exécuter:"
	@echo "  $(SCRIPTS_DIR)/migrate.sh --app $(APP) --namespace $(or $(NAMESPACE),default) --execute"

kubeconfig: ## Extraire le kubeconfig
	@echo "$(BLUE)[INFO]$(NC) Extraction du kubeconfig..."
	@cd $(TERRAFORM_DIR) && terraform output -raw kubeconfig > ~/.kube/config
	@chmod 600 ~/.kube/config
	@echo "$(GREEN)[SUCCESS]$(NC) Kubeconfig sauvegardé dans ~/.kube/config ✓"

talosconfig: ## Extraire le talosconfig
	@echo "$(BLUE)[INFO]$(NC) Extraction du talosconfig..."
	@mkdir -p ~/.talos
	@cd $(TERRAFORM_DIR) && terraform output -raw talosconfig > ~/.talos/config
	@chmod 600 ~/.talos/config
	@echo "$(GREEN)[SUCCESS]$(NC) Talosconfig sauvegardé dans ~/.talos/config ✓"

status: ## Afficher le statut du cluster
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo "$(BLUE)                    STATUT DU CLUSTER                          $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Cluster Info:$(NC)"
	@kubectl cluster-info | head -n 2 || echo "$(RED)Cluster non accessible$(NC)"
	@echo ""
	@echo "$(YELLOW)Nœuds:$(NC)"
	@kubectl get nodes -o wide || echo "$(RED)Impossible de récupérer les nœuds$(NC)"
	@echo ""
	@echo "$(YELLOW)Gateway API:$(NC)"
	@kubectl get gateway -A || echo "$(RED)Gateway API non déployé$(NC)"
	@echo ""
	@echo "$(YELLOW)Applications:$(NC)"
	@kubectl get deployments,services,httproute -n demo-apps || echo "$(RED)Applications non déployées$(NC)"
	@echo ""

dashboard: ## Lancer le dashboard Kubernetes
	@echo "$(BLUE)[INFO]$(NC) Lancement du dashboard..."
	@echo "$(YELLOW)[INFO]$(NC) Accès: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
	@kubectl proxy

destroy: ## Détruire toute l'infrastructure
	@echo "$(RED)[WARNING]$(NC) Vous êtes sur le point de détruire toute l'infrastructure !"
	@read -p "Êtes-vous sûr? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "$(BLUE)[INFO]$(NC) Suppression des applications..."; \
		kubectl delete namespace demo-apps --ignore-not-found; \
		echo "$(BLUE)[INFO]$(NC) Suppression de Gateway API..."; \
		kubectl delete namespace gateway-system --ignore-not-found; \
		kubectl delete namespace envoy-gateway-system --ignore-not-found; \
		echo "$(BLUE)[INFO]$(NC) Destruction de l'infrastructure Terraform..."; \
		cd $(TERRAFORM_DIR) && terraform destroy -auto-approve; \
		echo "$(GREEN)[SUCCESS]$(NC) Infrastructure détruite ✓"; \
	else \
		echo "$(YELLOW)[INFO]$(NC) Opération annulée"; \
	fi

clean: ## Nettoyer les fichiers temporaires
	@echo "$(BLUE)[INFO]$(NC) Nettoyage des fichiers temporaires..."
	@cd $(TERRAFORM_DIR) && rm -f tfplan .terraform.lock.hcl
	@rm -rf $(TERRAFORM_DIR)/.terraform
	@rm -rf migrations/
	@echo "$(GREEN)[SUCCESS]$(NC) Nettoyage terminé ✓"

docs: ## Afficher la documentation
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║                      DOCUMENTATION                             ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Documentation disponible:$(NC)"
	@echo "  • README.md                  - Vue d'ensemble du projet"
	@echo "  • docs/ARCHITECTURE.md       - Architecture détaillée"
	@echo "  • docs/MIGRATION_GUIDE.md    - Guide de migration pas-à-pas"
	@echo "  • docs/SECURITY.md           - Considérations de sécurité"
	@echo ""
	@echo "$(YELLOW)Quick Start:$(NC)"
	@echo "  1. make init                 - Initialiser le projet"
	@echo "  2. make template             - Préparer le template Talos (sur Proxmox)"
	@echo "  3. make deploy               - Déployer le cluster complet"
	@echo "  4. make validate             - Valider le déploiement"
	@echo "  5. make migrate APP=mon-app  - Migrer une application"
	@echo ""

logs: ## Afficher les logs d'Envoy Gateway
	@echo "$(BLUE)[INFO]$(NC) Logs Envoy Gateway..."
	@kubectl logs -n envoy-gateway-system -l app=envoy-gateway --tail=50 -f

.DEFAULT_GOAL := help
