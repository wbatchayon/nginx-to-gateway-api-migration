# ⚡ Quick Start - Migration NGINX Ingress → Gateway API

## 🎯 Objectif

Déployer en **moins de 30 minutes** un cluster Kubernetes Talos sur Proxmox avec Gateway API opérationnel et applications de démonstration.

## ✅ Prérequis

### Infrastructure
- [ ] Proxmox VE 8.x accessible
- [ ] 150GB d'espace disque disponible
- [ ] 4 adresses IP disponibles (192.168.1.130-133)
- [ ] Accès SSH root sur Proxmox

### Outils locaux (à installer)
```bash
# macOS
brew install terraform kubectl ansible talosctl helm

# Linux (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y terraform kubectl ansible

# talosctl (tous OS)
curl -sL https://talos.dev/install | sh
```

### Token API Proxmox
```bash
# Sur Proxmox: Datacenter → API Tokens → Add
# Créer: terraform@pve!terraform avec privilèges
```

## 🚀 Déploiement en 5 étapes

### Étape 1: Cloner et configurer (2 min)

```bash
# Cloner le projet
git clone
cd nginx-to-gateway-api-migration

# Initialiser
make init
```

### Étape 2: Préparer le template Talos sur Proxmox (5 min)

```bash
# Sur votre machine locale
ssh root@PROXMOX_IP 'bash -s' < scripts/prepare-talos-template.sh

# ✅ Template créé avec ID 9000
```

### Étape 3: Configurer les variables (3 min)

```bash
# Copier l'exemple
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Éditer avec vos valeurs
vim terraform.tfvars
```

**Minimum à modifier** :
```hcl
proxmox_api_url          = "https://192.168.1.10:8006"  # Votre IP Proxmox
proxmox_api_token_id     = "votre-user@realm!token_id"
proxmox_api_token_secret = "VOTRE-SECRET-ICI"
proxmox_ssh_password     = "votre-mot-de-passe-root"
```

### Étape 4: Déployer automatiquement (15 min)

```bash
# Retour à la racine
cd ..

# Déploiement complet automatique
make deploy

# OU étape par étape:
# make deploy-infra      # 10 min - VMs Proxmox
# make deploy-k8s        # 2 min  - Bootstrap Talos
# make deploy-gateway    # 2 min  - Gateway API
# make deploy-apps       # 1 min  - Applications démo
```

**☕ Pendant le déploiement** :
- Les VMs se créent sur Proxmox (6 VMs)
- Talos bootstrap automatiquement
- Gateway API s'installe
- Applications de démo se déploient

### Étape 5: Valider (2 min)

```bash
# Validation complète
make validate

# Afficher le statut
make status

# Tester les applications
GATEWAY_IP=$(kubectl get svc -n envoy-gateway-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
curl -H "Host: app-v2.example.com" http://$GATEWAY_IP/
```

## ✅ Résultat attendu

```
╔════════════════════════════════════════════════════════════════╗
║           ✅ VALIDATION COMPLÈTE RÉUSSIE ! ✅                  ║
╚════════════════════════════════════════════════════════════════╝

Cluster:
  • 1 control planes (talos-cp-1)
  • 2 workers (talos-worker-1/2)
  • Kubernetes 1.29+

Gateway API:
  • Envoy Gateway déployé
  • GatewayClass 'eg' configurée
  • Gateway 'main-gateway' programmé

Applications:
  • demo-app-v1 (NGINX Ingress - legacy)
  • demo-app-v2 (Gateway API - moderne) ✅
```

## 🧪 Tester la migration

### Scénario: Migrer une application fictive

```bash
# 1. Créer un Ingress de test
kubectl create namespace test-migration

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test-migration
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-app-svc
  namespace: test-migration
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-app
  namespace: test-migration
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app-svc
            port:
              number: 80
EOF

# 2. Migrer vers Gateway API
make migrate APP=test-app NAMESPACE=test-migration

# 3. Vérifier
kubectl get httproute -n test-migration
```

## 📊 Dashboards et Monitoring

```bash
# Accéder à Grafana (si déployé)
kubectl port-forward -n monitoring svc/grafana 3000:80

# Ouvrir: http://localhost:3000
# Credentials: admin/admin (à changer)
```

## 🔄 Prochaines étapes

### Pour un usage en production

1. **Sécurité** :
   ```bash
   # Installer cert-manager pour TLS
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

   # Configurer Let's Encrypt
   # Voir: docs/SECURITY.md
   ```

2. **Observabilité** :
   ```bash
   # Déployer Prometheus/Grafana
   helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack
   ```

3. **Migration progressive** :
   - Tester avec apps non-critiques
   - Monitorer les métriques
   - Migrer par vagues
   - Désactiver NGINX Ingress après validation

4. **Governance** :
   - Implémenter RBAC Gateway API
   - Policies OPA/Kyverno
   - Network Policies

## 🆘 Troubleshooting rapide

### Problème: VMs ne démarrent pas

```bash
# Vérifier sur Proxmox
ssh root@PROXMOX_IP
qm list

# Logs d'une VM
qm status 130
```

### Problème: Gateway n'a pas d'IP

```bash
# Installer MetalLB pour bare-metal
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Configurer IP pool
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.210
EOF
```

### Problème: HTTPRoute non accepté

```bash
# Diagnostiquer
kubectl describe httproute  -n

# Vérifier que le Gateway existe
kubectl get gateway -n gateway-system

# Créer ReferenceGrant si besoin
# Voir: docs/MIGRATION_GUIDE.md#troubleshooting
```

## 📞 Support

- **Documentation complète** : `docs/MIGRATION_GUIDE.md`
- **Architecture** : `docs/ARCHITECTURE.md`
- **Sécurité** : `docs/SECURITY.md`
- **Issues** : Ouvrir une issue sur GitHub

## 🎉 Félicitations !

Vous avez maintenant :
- ✅ Un cluster Kubernetes Talos production-ready
- ✅ Gateway API (standard CNCF) opérationnel
- ✅ Éliminé les risques de CVE-2025-1974
- ✅ Une base pour migrer vos applications

**Prochaine étape** : Consulter `docs/MIGRATION_GUIDE.md` pour migrer vos vraies applications.

---

**Temps total**: ~30 minutes
**Difficulté**: 🟢 Débutant (avec les bons outils)
