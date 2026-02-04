# ==========================================
# Outputs - Informations du cluster
# ==========================================

output "cluster_name" {
  description = "Nom du cluster Kubernetes"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint de l'API Kubernetes"
  value       = "https://${var.control_plane_vip}:6443"
}

output "control_plane_nodes" {
  description = "Informations des nœuds control plane"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.talos_control_plane : idx => {
      name = vm.name
      ip   = vm.initialization[0].ip_config[0].ipv4[0].address
      id   = vm.vm_id
    }
  }
}

output "worker_nodes" {
  description = "Informations des nœuds workers"
  value = {
    for idx, vm in proxmox_virtual_environment_vm.talos_worker : idx => {
      name = vm.name
      ip   = vm.initialization[0].ip_config[0].ipv4[0].address
      id   = vm.vm_id
    }
  }
}

output "talosconfig_save_command" {
  description = "Commande pour sauvegarder talosconfig"
  value       = "terraform output -raw talosconfig > ~/.talos/config"
}

output "kubeconfig_save_command" {
  description = "Commande pour sauvegarder kubeconfig"
  value       = "terraform output -raw kubeconfig > ~/.kube/config"
}

output "next_steps" {
  description = "Prochaines étapes après le déploiement"
  value = <<-EOT
  
  Infrastructure Proxmox déployée avec succès !
  
  Prochaines étapes :
  
  1. Sauvegarder les configurations :
     terraform output -raw talosconfig > ~/.talos/config
     terraform output -raw kubeconfig > ~/.kube/config
  
  2. Vérifier le cluster :
     talosctl health --nodes ${join(",", [for vm in proxmox_virtual_environment_vm.talos_control_plane : vm.initialization[0].ip_config[0].ipv4[0].address])}
     kubectl get nodes
  
  3. Déployer Gateway API :
     cd ../ansible
     ansible-playbook -i inventory/hosts playbooks/02-deploy-gateway-api.yml
  
  4. Déployer les applications de démo :
     ansible-playbook -i inventory/hosts playbooks/03-deploy-apps.yml
  
  5. Migrer de NGINX Ingress vers Gateway API :
     ansible-playbook -i inventory/hosts playbooks/04-migrate-ingress.yml
  
  Accéder au cluster :
     export KUBECONFIG=~/.kube/config
     kubectl cluster-info
  
  EOT
}

# Outputs sensibles (ne pas afficher par défaut)
output "talosconfig" {
  description = "Configuration Talos client (YAML)"
  value       = yamlencode(talos_machine_secrets.this.client_configuration)
  sensitive   = true
}

output "kubeconfig" {
  description = "Configuration Kubernetes (sensible)"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}
