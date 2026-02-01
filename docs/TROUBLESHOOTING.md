# 🔧 Guide de Troubleshooting

## Problèmes courants et solutions

### 1. Cluster Talos

#### Problème: "Talos nodes cannot reach API server"
```bash
# Diagnostic
talosctl -n <ip-node> health

# Solution
# 1. Vérifier la connectivité réseau
ping <ip-control-plane>

# 2. Vérifier les certificats
talosctl -n <ip-cp> kubeconfig

# 3. Redémarrer le service API
talosctl -n <ip-cp> system service restart api
```

#### Problème: "Kernel panic on boot"
```bash
# Vérifier les logs de boot
talosctl -n <ip-node> dmesg

# Rollback si possible
talosctl -n <ip-node> rollback

# Ou redéployer le node
./scripts/deploy.sh --step infrastructure --target <node-id>
```

#### Problème: "Disk full (root filesystem)"
```bash
# Vérifier utilisation disque
talosctl -n <ip-node> df

# Nettoyer les images docker
talosctl -n <ip-node> container prune

# Nettoyer les logs systemd
talosctl -n <ip-node> systemctl status
```

### 2. Gateway API

#### Problème: "Envoy Gateway pods stuck in pending"
```bash
# Vérifier les logs
kubectl logs -n envoy-gateway-system deployment/envoy-gateway -f

# Diagnostic
kubectl describe pod -n envoy-gateway-system <pod-name>

# Solutions possibles
# 1. PVC not available
kubectl get pvc -n envoy-gateway-system

# 2. Insufficient resources
kubectl describe nodes
kubectl top nodes

# 3. Node affinity issues
kubectl get nodes --show-labels
```

#### Problème: "HTTPRoute not recognized or stuck in pending"
```bash
# Vérifier la resource
kubectl get httproute -n <namespace>
kubectl describe httproute <route-name> -n <namespace>

# Vérifier le GatewayClass
kubectl get gatewayclass
kubectl logs -n envoy-gateway-system deployment/envoy-gateway-controller

# Vérifier la référence au backend
kubectl get service -n <namespace>
kubectl get pods -n <namespace> --show-labels

# Test de connectivité
kubectl run -it --rm debug --image=curlimages/curl:latest -- sh
curl -v http://<backend-service>:8080
```

#### Problème: "502 Bad Gateway via Envoy"
```bash
# Étapes de débogage
# 1. Vérifier la Gateway
kubectl get gateway
kubectl describe gateway production

# 2. Vérifier les Envoy pods
kubectl get pods -n envoy-gateway-system
kubectl logs -n envoy-gateway-system <envoy-pod>

# 3. Vérifier l'HTTPRoute
kubectl get httproute
kubectl describe httproute <route-name>

# 4. Vérifier le service backend
kubectl get svc -A | grep app
kubectl get endpoints <service-name>

# 5. Test depuis l'intérieur du cluster
kubectl run -it --rm debug --image=curlimages/curl:latest -- \
  curl -v http://<service-name>:<port>

# 6. Vérifier les logs applicatifs
kubectl logs -n <namespace> deployment/<app-name>
```

#### Problème: "TLS certificate not working"
```bash
# Vérifier les certificats
kubectl get certificate -A
kubectl describe certificate <cert-name>

# Vérifier le secret
kubectl get secret <tls-secret> -o yaml

# Vérifier cert-manager
kubectl logs -n cert-manager deployment/cert-manager

# Tester la connexion TLS
echo | openssl s_client -connect <gateway-ip>:443 -servername example.com

# Solutions
# 1. Renew certificate
kubectl delete certificate <cert-name>

# 2. Check issuer
kubectl get clusterissuer
kubectl describe clusterissuer <issuer-name>

# 3. Restart cert-manager
kubectl rollout restart deployment/cert-manager -n cert-manager
```

### 3. NGINX Ingress (Legacy)

#### Problème: "NGINX Ingress pods not starting"
```bash
# Logs
kubectl logs -n nginx-ingress deployment/nginx-ingress-controller

# Diagnostic
kubectl describe pod -n nginx-ingress <pod-name>

# Vérifier la configuration
kubectl get configmap -n nginx-ingress

# Vérifier les ingress resources
kubectl get ingress -A
```

#### Problème: "Ingress not routing traffic"
```bash
# Vérifier les ingress resources
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>

# Vérifier la configuration NGINX
kubectl exec -n nginx-ingress <nginx-pod> -- nginx -T

# Vérifier les services
kubectl get svc -A
kubectl get endpoints <service-name>

# Test local
kubectl port-forward -n nginx-ingress svc/nginx-ingress 8080:80
curl -H "Host: example.com" http://localhost:8080
```

### 4. Observabilité

#### Problème: "Prometheus ne scrape pas les métriques"
```bash
# Vérifier les targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Aller à http://localhost:9090/targets

# Vérifier la config Prometheus
kubectl get configmap -n monitoring prometheus-config -o yaml

# Vérifier les service monitors
kubectl get servicemonitor -A

# Vérifier la connectivité aux endpoints
kubectl get endpoints -A

# Redémarrer Prometheus
kubectl rollout restart deployment/prometheus -n monitoring
```

#### Problème: "Grafana dashboard vide"
```bash
# Vérifier les data sources
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Accéder à http://localhost:3000 (admin/admin par défaut)

# Vérifier que Prometheus a des données
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# PromQL: gateway_requests_total

# Vérifier les logs Grafana
kubectl logs -n monitoring deployment/grafana

# Redémarrer Grafana
kubectl rollout restart deployment/grafana -n monitoring
```

#### Problème: "Logs ne s'affichent pas dans Loki"
```bash
# Vérifier que Loki est up
kubectl get pods -n monitoring -l app=loki

# Vérifier la configuration
kubectl logs -n monitoring <loki-pod>

# Vérifier les labels
kubectl get pods -A --show-labels | grep -E "(app|component)"

# Query Loki directement
kubectl port-forward -n monitoring svc/loki 3100:3100
curl 'http://localhost:3100/loki/api/v1/labels'
```

### 5. Réseau et Connectivité

#### Problème: "Pod cannot resolve DNS"
```bash
# Vérifier le DNS cluster
kubectl run -it --rm debug --image=busybox:latest -- sh
nslookup kubernetes.default

# Vérifier les CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Vérifier les configmaps
kubectl get configmap -n kube-system coredns -o yaml

# Test DNS depuis le node
talosctl -n <ip-node> resolve example.com
```

#### Problème: "Network policies bloquent le trafic"
```bash
# Lister les network policies
kubectl get networkpolicy -A

# Vérifier les labels sur les pods
kubectl get pods -A --show-labels

# Déboguer les policies
kubectl describe networkpolicy -n <namespace> <policy-name>

# Tester la connectivité
kubectl run -it --rm debug --image=curlimages/curl:latest -- \
  curl -v http://<service>:<port>
```

#### Problème: "Service discovery ne fonctionne pas"
```bash
# Vérifier les services
kubectl get svc -A

# Vérifier les endpoints
kubectl get endpoints <service-name> -n <namespace>

# Test de connectivité
kubectl run -it --rm debug --image=curlimages/curl:latest -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local

# Vérifier les labels
kubectl get pods -n <namespace> --show-labels
kubectl describe svc <service-name> -n <namespace>
```

### 6. Stockage

#### Problème: "PVC stuck in pending"
```bash
# Vérifier les PVC
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <namespace>

# Vérifier les storage classes
kubectl get storageclass

# Vérifier les PV
kubectl get pv

# Vérifier l'espace disque disponible
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

#### Problème: "Pod cannot mount volume"
```bash
# Vérifier le volume
kubectl describe pvc <pvc-name> -n <namespace>

# Vérifier le mount dans le pod
kubectl describe pod <pod-name> -n <namespace>

# Vérifier les logs du pod
kubectl logs <pod-name> -n <namespace>

# Vérifier l'espace disque sur le node
talosctl -n <ip-node> df /var/lib/kubelet/pods
```

### 7. Performance et Ressources

#### Problème: "Pods crashlooping avec OOMKilled"
```bash
# Vérifier l'usage mémoire
kubectl top pods -A

# Vérifier les limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits"

# Vérifier les événements
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Augmenter les ressources
kubectl set resources deployment <deployment-name> -n <namespace> \
  --limits=memory=1Gi
```

#### Problème: "High CPU usage"
```bash
# Identifier les pods gourmands
kubectl top pods -A

# Profiler une application
kubectl run -it --rm debug --image=pprof/pprof:latest -- \
  go tool pprof http://<service>:6060/debug/pprof

# Vérifier les configurations
kubectl describe deployment <deployment-name> -n <namespace>

# Analyser les métriques Prometheus
# Query: rate(container_cpu_usage_seconds_total[5m])
```

## Scripts de debugging utiles

### Debug complet du cluster
```bash
#!/bin/bash
set -e

echo "=== Node Status ==="
kubectl get nodes -o wide
talosctl -n <ip-cp> health

echo "=== Pod Status ==="
kubectl get pods -A --field-selector=status.phase!=Running

echo "=== Events ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

echo "=== Resource Usage ==="
kubectl top nodes
kubectl top pods -A | sort -k4 -rn | head -10

echo "=== PVC Status ==="
kubectl get pvc -A

echo "=== Service Endpoints ==="
kubectl get endpoints -A

echo "=== Network Policies ==="
kubectl get networkpolicy -A
```

### Validation Gateway API
```bash
#!/bin/bash
set -e

echo "=== Gateway API Components ==="
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
kubectl get tcproute -A

echo "=== Gateway API Reconciliation ==="
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[0].reason}{"\n"}{end}'

echo "=== Envoy Gateway Logs ==="
kubectl logs -n envoy-gateway-system deployment/envoy-gateway -f --tail=50
```

## Collecte de logs pour support

```bash
#!/bin/bash
# Collecte logs complète pour analysis

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="logs_$TIMESTAMP"
mkdir -p $OUTPUT_DIR

# Cluster info
kubectl cluster-info dump --output-directory=$OUTPUT_DIR --all-namespaces

# Talos logs
for node in $(talosctl get nodes -o json | jq -r '.nodes[].metadata.hostname'); do
  talosctl -n $node dmesg > $OUTPUT_DIR/talos_dmesg_$node.log
  talosctl -n $node systemctl status > $OUTPUT_DIR/talos_systemctl_$node.log
done

# Events
kubectl get events -A -o yaml > $OUTPUT_DIR/events.yaml

# Describe resources
kubectl describe nodes > $OUTPUT_DIR/nodes.yaml
kubectl describe pods -A > $OUTPUT_DIR/pods.yaml

# Gateway API resources
kubectl get gateway -A -o yaml > $OUTPUT_DIR/gateways.yaml
kubectl get httproute -A -o yaml > $OUTPUT_DIR/httproutes.yaml

# Archive
tar -czf $OUTPUT_DIR.tar.gz $OUTPUT_DIR
echo "Logs collected in $OUTPUT_DIR.tar.gz"
```

---

*Pour plus d'aide, consultez la [documentation Talos](https://www.talos.dev), [Kubernetes](https://kubernetes.io/docs) et [Gateway API](https://gateway-api.sigs.k8s.io)*
