# Guide de Migration NGINX Ingress → Gateway API

## Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Contexte: CVE-2025-1974](#contexte-cve-2025-1974)
3. [Stratégie de migration](#stratégie-de-migration)
4. [Prérequis](#prérequis)
5. [Phase 1: Infrastructure](#phase-1-infrastructure)
6. [Phase 2: Gateway API](#phase-2-gateway-api)
7. [Phase 3: Migration progressive](#phase-3-migration-progressive)
8. [Phase 4: Validation](#phase-4-validation)
9. [Rollback](#rollback)
10. [Troubleshooting](#troubleshooting)

---

## Vue d'ensemble

Cette migration vous permet de passer de **NGINX Ingress Controller** (avec ses limitations et risques de sécurité) vers **Gateway API**, le standard moderne de la CNCF pour le routage L7 dans Kubernetes.

### Pourquoi migrer ?

| Problème NGINX Ingress | Solution Gateway API |
|------------------------|---------------------|
| Annotations non standardisées | CRDs typés et validés |
| Snippets risqués (CVE-2025-1974) | Policies explicites |
| Configuration monolithique | Séparation Infrastructure/Apps |
| Vendor lock-in | Standard CNCF multi-implémentation |
| Governance limitée | RBAC granulaire natif |

---

## Contexte: CVE-2025-1974

### Détails de la vulnérabilité

- **Score CVSS**: 9.8 (Critical)
- **Type**: Remote Code Execution (RCE)
- **Vecteur d'attaque**: Annotations `configuration-snippet` et `server-snippet`
- **Impact**: Exécution de code arbitraire sur les pods Ingress

### Exemple d'exploitation

```yaml
# DANGEREUX - Ne pas utiliser
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      location /admin {
        return 200 "Backdoor installée";
      }
```

### Pourquoi Gateway API résout ce problème

Gateway API élimine complètement les snippets dynamiques. Toute configuration est explicite via CRDs typés et validés par le serveur API Kubernetes.

---

## Stratégie de migration

### Approche progressive (recommandée)

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 0: État actuel                                        │
│ ┌─────────────┐                                             │
│ │ NGINX       │ → Apps 1-10                                 │
│ │ Ingress     │                                             │
│ └─────────────┘                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Coexistence (2 semaines)                           │
│ ┌─────────────┐                                             │
│ │ NGINX       │ → Apps 1-10 (legacy)                        │
│ │ Ingress     │                                             │
│ └─────────────┘                                             │
│ ┌─────────────┐                                             │
│ │ Gateway API │ → App Test (nouveau)                        │
│ └─────────────┘                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 2: Migration par vagues (4-6 semaines)                │
│ ┌─────────────┐                                             │
│ │ NGINX       │ → Apps 6-10 (50%)                           │
│ │ Ingress     │                                             │
│ └─────────────┘                                             │
│ ┌─────────────┐                                             │
│ │ Gateway API │ → Apps 1-5 + Test (50%)                     │
│ └─────────────┘                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Phase 3: État final (après validation)                      │
│ ┌─────────────┐                                             │
│ │ Gateway API │ → Apps 1-10 + Test (100%)                   │
│ └─────────────┘                                             │
│ ┌─────────────┐                                             │
│ │ NGINX       │ → [Désactivé, conservé pour rollback]       │
│ │ Ingress     │                                             │
│ └─────────────┘                                             │
└─────────────────────────────────────────────────────────────┘
```

### Critères de migration par vagues

**Vague 1** (Semaine 1-2): Applications non-critiques
- Sites de documentation
- Applications internes
- Environnements de dev/staging

**Vague 2** (Semaine 3-4): Applications à criticité moyenne
- APIs internes
- Dashboards
- Outils d'administration

**Vague 3** (Semaine 5-6): Applications critiques
- APIs publiques
- Applications client-facing
- Services de paiement

---

## Prérequis

### Infrastructure

- Cluster Kubernetes 1.28+
- Talos Linux (ou autre OS compatible)
- Stockage disponible (PV/PVC pour logs, metrics)

### Outils

```bash
# Vérifier les versions
terraform --version  # 1.5.0+
kubectl version      # 1.28+
talosctl version     # 1.6+
ansible --version    # 2.14+
helm version         # 3.12+
```

### Permissions

- Accès admin au cluster Kubernetes
- Accès API Proxmox (pour déploiement infra)
- RBAC approprié pour créer Gateway, HTTPRoute

---

## Phase 1: Infrastructure

### Étape 1.1: Configuration Terraform

```bash
# Copier et éditer les variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**Variables critiques à configurer** :

```hcl
proxmox_api_url = "https://votre-proxmox:8006"
proxmox_api_token_id = "terraform@pve!terraform"
proxmox_api_token_secret = "votre-secret"

cluster_name = "talos-gateway-api"
control_plane_count = 1  # Single node (etcd single)
worker_count = 2
```

### Étape 1.2: Déploiement automatique

```bash
# Déploiement complet en une commande
./scripts/deploy.sh --auto

# OU par étape
./scripts/deploy.sh --step infrastructure
./scripts/deploy.sh --step kubernetes
```

### Étape 1.3: Vérification

```bash
# Vérifier les nœuds
kubectl get nodes -o wide

# Devrait afficher:
# NAME            STATUS   ROLES           AGE   VERSION
# talos-cp-1      Ready    control-plane   5m    v1.29.x
# talos-worker-1  Ready    <none>          5m    v1.29.x
# talos-worker-2  Ready    <none>          5m    v1.29.x
# obs-ubuntu-1    Ready    observability   5m    v1.29.x
```

---

## Phase 2: Gateway API

### Étape 2.1: Installation

```bash
# Via script automatique
./scripts/deploy.sh --step gateway-api

# OU manuellement via Ansible
cd ansible
ansible-playbook -i inventory/hosts playbooks/02-deploy-gateway-api.yml
```

### Étape 2.2: Vérification de l'installation

```bash
# Vérifier les CRDs
kubectl get crd | grep gateway
```
Devrait afficher par exemple:
```txt
grpcroutes.gateway.networking.k8s.io           2026-02-01T15:04:40Z
httproutefilters.gateway.envoyproxy.io         2026-02-01T15:07:04Z
httproutes.gateway.networking.k8s.io           2026-02-01T15:04:40Z
referencegrants.gateway.networking.k8s.io      2026-02-01T15:04:41Z
securitypolicies.gateway.envoyproxy.io         2026-02-01T15:07:05Z
tcproutes.gateway.networking.k8s.io            2026-02-01T15:07:03Z
tlsroutes.gateway.networking.k8s.io            2026-02-01T15:07:03Z
udproutes.gateway.networking.k8s.io            2026-02-01T15:07:03Z
```

```bash
# Vérifier le contrôleur Envoy Gateway
kubectl get pods -n envoy-gateway-system

# Vérifier la GatewayClass
kubectl get gatewayclass
# NAME   CONTROLLER                                    AGE
# eg     gateway.envoyproxy.io/gatewayclass-controller 2m

# Vérifier le Gateway
kubectl get gateway -n gateway-system
# NAME           CLASS   ADDRESS         PROGRAMMED   AGE
# main-gateway   eg      10.96.xxx.xxx   True         2m
```

### Étape 2.3: Récupérer l'IP du Gateway

```bash
# L'IP externe du Gateway (pour les tests)
kubectl get svc -n envoy-gateway-system

# Noter l'EXTERNAL-IP ou NodePort
```

---

## Phase 3: Migration progressive

### Étape 3.1: Application de test

**Déployer une application de démo** :

```bash
./scripts/deploy.sh --step apps
```

Cela déploie:
- `demo-app-v1`: Utilise NGINX Ingress (legacy)
- `demo-app-v2`: Utilise Gateway API (moderne)

### Étape 3.2: Migrer une application existante

**Workflow complet** :

```bash
# 1. Analyser l'Ingress existant
./scripts/migrate.sh --app mon-app --namespace production --analyze
```
Affiche:
```text
Configuration Ingress détectée:
  Host: api.example.com
  Path: /v1
  Service: mon-app-service
  Port: 8080
```
```bash
# 2. Générer HTTPRoute équivalent
./scripts/migrate.sh --app mon-app --namespace production --generate

# Crée: migrations/mon-app-httproute.yaml

# 3. Tester (dry-run)
./scripts/migrate.sh --app mon-app --namespace production --dry-run

# Affiche les résultats de validation

# 4. Exécuter la migration
./scripts/migrate.sh --app mon-app --namespace production --execute
```

### Étape 3.3: Exemple de conversion manuelle

**Avant (NGINX Ingress)** :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mon-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /v1(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: mon-app-service
                port:
                  number: 8080
```

**Après (Gateway API)** :

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mon-app-route
spec:
  parentRefs:
    - name: main-gateway
      namespace: gateway-system
  hostnames:
    - "api.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v1
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /
      backendRefs:
        - name: mon-app-service
          port: 8080
```

**Changements clés** :
- Annotations → CRDs typés
- Regex complexe → PathPrefix + filters
- Configuration implicite → Configuration explicite

---

## Phase 4: Validation

### Étape 4.1: Tests de fumée (smoke tests)

```bash
# Tester l'application migrée
GATEWAY_IP=$(kubectl get svc -n envoy-gateway-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

curl -H "Host: api.example.com" http://$GATEWAY_IP/v1/health

# Réponse attendue: {"status": "ok"}
```

### Étape 4.2: Tests de charge

```bash
# Comparer les performances
# Avant (NGINX Ingress)
hey -n 10000 -c 100 http://nginx-ingress-ip/v1/health

# Après (Gateway API)
hey -n 10000 -c 100 -H "Host: api.example.com" http://$GATEWAY_IP/v1/health
```

### Étape 4.3: Vérification des métriques

```bash
# Prometheus queries
# Latence p99
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Taux d'erreur
rate(http_requests_total{status=~"5.."}[5m])
```

### Étape 4.4: Validation fonctionnelle

**Checklist** :

- [ ] Toutes les routes fonctionnent correctement
- [ ] Redirections HTTPS opérationnelles
- [ ] Headers personnalisés transmis
- [ ] Timeouts configurés correctement
- [ ] Retry policies fonctionnelles
- [ ] Métriques collectées dans Prometheus
- [ ] Logs visibles dans Loki/ELK
- [ ] Aucune augmentation des latences
- [ ] Aucune augmentation du taux d'erreur

---

## Rollback

### Rollback d'une application

Si un problème survient après migration:

```bash
# 1. Supprimer HTTPRoute
kubectl delete httproute mon-app-route -n production

# 2. Réactiver l'Ingress (s'il a été désactivé)
kubectl annotate ingress mon-app -n production kubernetes.io/ingress.class=nginx

# 3. Vérifier que l'Ingress fonctionne
kubectl get ingress mon-app -n production
```

### Rollback complet de Gateway API

```bash
# 1. Migrer toutes les apps vers Ingress
for app in $(kubectl get httproute -n production -o name); do
    echo "Rollback $app"
    # Suppression HTTPRoute, réactivation Ingress
done

# 2. Désactiver Gateway API
kubectl delete gateway main-gateway -n gateway-system

# 3. (Optionnel) Désinstaller Envoy Gateway
helm uninstall eg -n envoy-gateway-system
```

---

## Troubleshooting

### Problème: HTTPRoute non accepté

**Symptôme** :
```bash
kubectl get httproute mon-app-route -n production
# STATUS: Accepted=False
```

**Diagnostic** :
```bash
kubectl describe httproute mon-app-route -n production
```

**Causes fréquentes** :
1. Gateway introuvable ou non programmé
2. Service backend inexistant
3. ReferenceGrant manquant pour cross-namespace

**Solution** :
```bash
# Vérifier le Gateway
kubectl get gateway -n gateway-system

# Vérifier le Service
kubectl get svc mon-app-service -n production

# Créer ReferenceGrant si nécessaire
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-from-gateway
  namespace: production
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: gateway-system
  to:
    - group: ""
      kind: Service
EOF
```

### Problème: Gateway sans IP externe

**Symptôme** :
```bash
kubectl get gateway -n gateway-system
# ADDRESS: <pending>
```

**Solution** :

Sur Talos/bare-metal, utiliser MetalLB ou NodePort:

```bash
# Installer MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Configurer une IP pool
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-pool
  namespace: metallb-system
spec:
  addresses:
    - x.x.x.200-x.x.x.210
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: gateway-l2
  namespace: metallb-system
EOF
```

### Problème: Latence élevée après migration

**Diagnostic** :
```bash
# Comparer les latences
kubectl top pods -n envoy-gateway-system
```

**Solutions possibles** :
1. Augmenter les ressources Envoy Gateway
2. Activer le cache
3. Optimiser les health checks

```yaml
# Augmenter les ressources
helm upgrade eg eg/gateway-helm -n envoy-gateway-system --set deployment.pod.resources.limits.cpu=2
```

---

## Ressources supplémentaires

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Envoy Gateway Guide](https://gateway.envoyproxy.io/)
- [CVE-2025-1974 Details](https://nvd.nist.gov/vuln/detail/CVE-2025-1974)
- [Talos Linux Docs](https://www.talos.dev/)

---

**Bon courage pour votre migration !**

Pour toute question, consultez [TROUBLESHOOTING.md](TROUBLESHOOTING.md) ou ouvrez une issue.
