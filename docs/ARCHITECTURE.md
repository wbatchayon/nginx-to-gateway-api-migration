# 🏗️ Architecture - Migration NGINX Ingress → Gateway API

## Vue d'ensemble

Cette architecture implémente une migration zéro-downtime de NGINX Ingress vers Gateway API sur un cluster Kubernetes Talos déployé sur Proxmox.

## Flux de trafic

### Scénario 1: Requête HTTP vers App V2 (Gateway API)

```
┌──────────┐
│  Client  │
└────┬─────┘
     │ 1. HTTP GET /api/v2/users
     │    Host: app-v2.example.com
     ▼
┌────────────────────┐
│  LoadBalancer/     │
│  NodePort          │
└────┬───────────────┘
     │ 2. Forward to Gateway Service
     ▼
┌────────────────────┐
│  Envoy Gateway     │
│  (main-gateway)    │
└────┬───────────────┘
     │ 3. Match HTTPRoute
     │    • Hostname: app-v2.example.com
     │    • Path: /api/v2
     ▼
┌────────────────────┐
│  HTTPRoute         │
│  • Filters applied │
│  • Headers added   │
└────┬───────────────┘
     │ 4. Route to backend
     ▼
┌────────────────────┐
│  Service           │
│  app-v2-service    │
└────┬───────────────┘
     │ 5. Load balance
     │    across pods
     ▼
┌────────────────────┐
│  Pod (app-v2)      │
│  • Container       │
│  • Application     │
└────────────────────┘
```

### Scénario 2: Migration progressive (Canary)

```
                    ┌─────────────────┐
                    │  Gateway API    │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │  HTTPRoute      │
                    │  Weighted       │
                    └────────┬────────┘
                             │
            ┌────────────────┴──────────────┐
            │                               │
            ▼ 90%                           ▼ 10%
    ┌──────────────┐                ┌──────────────┐
    │  App V1      │                │  App V2      │
    │  (Stable)    │                │  (Canary)    │
    └──────────────┘                └──────────────┘
```

Configuration HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-route
spec:
  parentRefs:
    - name: main-gateway
  rules:
    - backendRefs:
        - name: app-v1-service
          port: 80
          weight: 90  # 90% du trafic
        - name: app-v2-service
          port: 80
          weight: 10  # 10% du trafic
```

## Sécurité

### Architecture de sécurité multi-couches

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Network Policies                                   │
│ • Ingress/Egress rules                                      │
│ • Pod-to-pod isolation                                      │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Gateway API RBAC                                   │
│ • Infrastructure team → Gateway                             │
│ • App teams → HTTPRoute                                     │
│ • ReferenceGrant for cross-namespace                        │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Policy Enforcement (OPA/Kyverno)                   │
│ • Validation des HTTPRoute                                  │
│ • Deny snippets/annotations dangereuses                     │
│ • Enforce TLS                                               │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│ Layer 4: TLS/mTLS                                           │
│ • Cert-manager pour certificats                             │
│ • Gateway TLS termination                                   │
│ • Optional: Service Mesh (Istio/Linkerd)                    │
└─────────────────────────────────────────────────────────────┘
```

### RBAC: Séparation Infrastructure/Apps

```yaml
# Infrastructure Team (peut gérer Gateway)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gateway-admin
rules:
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gateways", "gatewayclasses"]
    verbs: ["*"]

---
# App Team (peut gérer HTTPRoute uniquement)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: httproute-manager
  namespace: demo-apps
rules:
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes"]
    verbs: ["*"]
```

## Haute disponibilité

### Control Plane HA

- **3 nœuds** control plane (quorum etcd)
- **etcd** distribué sur disques dédiés
- **API server** load-balanced (VIP)
- **Scheduler/Controller Manager** leader election

### Gateway API HA

- **Envoy Gateway** déployé avec 2+ replicas
- **Anti-affinity** pour répartition sur nœuds différents
- **PodDisruptionBudget** pour rolling updates

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: envoy-gateway-pdb
  namespace: envoy-gateway-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: envoy-gateway
```

## Performances

### Dimensionnement

| Composant | CPU (request) | CPU (limit) | Memory (request) | Memory (limit) |
|-----------|---------------|-------------|------------------|----------------|
| Control Plane | 2 cores | 4 cores | 4 GB | 8 GB |
| Worker | 2 cores | 8 cores | 8 GB | 16 GB |
| Envoy Gateway | 100m | 1 core | 256 MB | 1 GB |
| App Pod | 50m | 200m | 64 MB | 256 MB |

### Optimisations

1. **Connection pooling** sur Envoy
2. **Keep-alive** HTTP/2
3. **Compression** gzip/brotli
4. **Caching** au niveau Gateway

## Disaster Recovery

### Backup Strategy

```bash
# Backup etcd
talosctl -n <control-plane-ip> etcd snapshot

# Backup manifests
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml

# Backup Gateway API configs
kubectl get gateway,httproute --all-namespaces -o yaml > gateway-backup.yaml
```

### Recovery Procedure

1. Restaurer l'infrastructure Terraform
2. Restaurer etcd depuis snapshot
3. Re-appliquer les manifests Gateway API
4. Vérifier les routes

## Monitoring et Alertes

### Métriques clés

```promql
# Latence p99 Gateway API
histogram_quantile(0.99, 
  rate(envoy_http_downstream_rq_time_bucket[5m])
)

# Taux d'erreur 5xx
sum(rate(envoy_http_downstream_rq_xx{response_code_class="5"}[5m]))
/
sum(rate(envoy_http_downstream_rq_xx[5m]))

# Throughput
sum(rate(envoy_http_downstream_rq_total[5m]))
```

### Alertes critiques

- Gateway indisponible (>5 min)
- Latence p99 > 500ms
- Taux d'erreur 5xx > 1%
- Saturation CPU/Memory > 80%

## Coûts et ROI

### Réduction des coûts

| Avant (NGINX Ingress) | Après (Gateway API) | Économie |
|-----------------------|---------------------|----------|
| Maintenance manuelle annotations | CRDs auto-validés | -40% temps ops |
| Incidents sécurité | Risque réduit | -80% risque RCE |
| Vendor lock-in | Standard CNCF | Portabilité |

### ROI estimé

- **Temps de migration**: 4-6 semaines
- **Maintenance réduite**: 40% moins de temps ops
- **Sécurité renforcée**: Élimination CVE-2025-1974
- **Évolutivité**: Prêt pour Service Mesh
