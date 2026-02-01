# Migration NGINX Ingress → Gateway API sur Proxmox/Talos

## Vue d'ensemble

Projet complet de migration de NGINX Ingress Controller vers Gateway API (CNCF) sur un cluster Kubernetes Talos déployé sur Proxmox.

**Architecture**: 1 Control Plane Talos + 1 Observability Ubuntu + 2 Workers Talos  
**Contexte CVE-2025-1974**: Migration répondant à la vulnérabilité critique (CVSS 9.8) affectant NGINX Ingress

## Architecture

```
Kubernetes Stack (1 CP + 2 Workers):
├── Gateway API (Envoy Gateway) - NEW
├── NGINX Ingress Controller - LEGACY (canary migration)
├── Applications Demo
│   ├── App v1 (NGINX Ingress route)
│   └── App v2 (Gateway API route)
├── Observability (Ubuntu node: Prometheus, Grafana, Loki)
└── Sécurité (NetworkPolicies, RBAC, TLS)
```

## Objectifs de la migration

1. **Sécurité**: Éliminer les risques liés à CVE-2025-1974 et snippets NGINX
2. **Standardisation**: Adopter Gateway API (CNCF standard)
3. **Gouvernance**: Séparation Infrastructure/App teams
4. **Évolutivité**: Préparer pour Service Mesh et Zero Trust
5. **Zéro downtime**: Migration progressive sans interruption

## Prérequis

### Proxmox
- Proxmox VE 8.x
- Template Talos Linux préparé
- Bridge réseau configuré (vmbr0)
- Storage disponible (local-lvm ou autre)

### Outils locaux
```bash
# Terraform
terraform --version  # >= 1.5.0

# Ansible
ansible --version    # >= 2.14

# talosctl
talosctl version     # >= 1.6

# kubectl
kubectl version      # >= 1.28

# helm (optionnel)
helm version         # >= 3.12
```

## Déploiement rapide

### 1. Configuration initiale

```bash
# Cloner le projet
git clone 
cd nginx-to-gateway-api-migration

# Copier et configurer les variables Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars

# Configurer les variables Ansible
cp ansible/inventory/hosts.example ansible/inventory/hosts
vim ansible/inventory/hosts
```

### 2. Déploiement automatique

```bash
# Option 1: Script tout-en-un (recommandé pour POC)
./scripts/deploy.sh --auto

# Option 2: Étape par étape
./scripts/deploy.sh --step infrastructure  # Terraform
./scripts/deploy.sh --step kubernetes      # Bootstrap Talos
./scripts/deploy.sh --step gateway-api     # Déployer Gateway API
./scripts/deploy.sh --step apps            # Applications de démo
```

### 3. Migration progressive

```bash
# Vérifier l'état actuel
./scripts/validate.sh --check-ingress

# Migrer une application test
./scripts/migrate.sh --app demo-app --dry-run
./scripts/migrate.sh --app demo-app --execute

# Valider la migration
./scripts/validate.sh --compare demo-app

# Rollback si nécessaire
./scripts/rollback.sh --app demo-app
```

## Comparaison NGINX Ingress vs Gateway API

| Critère | NGINX Ingress | Gateway API |
|---------|---------------|-------------|
| **Sécurité** | Annotations, snippets | CRDs typés, policies |
| **Gouvernance** | Couplé | Séparé (Gateway/Route) |
| **Standardisation** | Vendor-specific | CNCF standard |
| **Multi-tenancy** | Limité | Natif |
| **Service Mesh** | Intégration complexe | Compatible natif |
| **Audit** | Difficile | Intégré |

## Considérations de sécurité

### CVE-2025-1974 (NGINX Ingress)
- **Score CVSS**: 9.8 (Critical)
- **Type**: Remote Code Execution
- **Vecteur**: Annotations/snippets malveillants

### Mitigation par Gateway API
- Suppression des snippets dynamiques
- Validation stricte via CRDs
- RBAC granulaire (Infrastructure vs App teams)
- Policies externalisées (OPA, Kyverno)

## Observabilité

Le projet déploie automatiquement:
- **Prometheus**: Métriques Gateway API et applications
- **Grafana**: Dashboards de comparaison Ingress vs Gateway
- **Loki**: Logs centralisés
- **Jaeger**: Tracing distribué (optionnel)

Accès après déploiement:
```bash
# Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

## Tests

```bash
# Tests de fumée (smoke tests)
./tests/smoke-tests.sh

# Tests de charge
./tests/load-tests/run.sh --duration 5m --rps 1000

# Comparaison performance Ingress vs Gateway
./tests/benchmark.sh --compare
```

## 📚 Documentation détaillée

- [Architecture complète](docs/ARCHITECTURE.md)
- [Guide de migration pas-à-pas](docs/MIGRATION_GUIDE.md)
- [Sécurité et conformité](docs/SECURITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## 🤝 Contribution

Ce projet est conçu comme une référence pour la communauté DevOps/SRE.

Contributions bienvenues:
1. Fork le projet
2. Créer une branche (`git checkout -b feature/amélioration`)
3. Commit (`git commit -m 'Ajout: nouvelle fonctionnalité'`)
4. Push (`git push origin feature/amélioration`)
5. Ouvrir une Pull Request

## Licence

MIT License - Voir [LICENSE](LICENSE)

## Remerciements

- **CNCF** pour Gateway API
- **Talos Linux** pour l'OS Kubernetes immutable
- **Envoy Gateway** pour l'implémentation de référence
- La communauté Kubernetes

---

**⚠️ Note importante**: Ce projet est destiné à des environnements de test/POC. 
Pour la production, adaptez les configurations selon vos contraintes de sécurité et conformité.
