# ==========================================
# Proxmox Configuration
# ==========================================

variable "proxmox_api_url" {
  description = "URL de l'API Proxmox"
  type        = string
  default     = "https://proxmox.example.com:8006"
}

variable "proxmox_api_token_id" {
  description = "Token ID Proxmox (format: user@realm!token)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Token secret Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_user" {
  description = "Utilisateur SSH Proxmox"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_password" {
  description = "Mot de passe SSH Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Nom du nœud Proxmox"
  type        = string
  default     = "pve"
}

variable "proxmox_storage" {
  description = "Storage Proxmox pour les disques"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_bridge" {
  description = "Bridge réseau Proxmox"
  type        = string
  default     = "vmbr0"
}

variable "talos_template_vm_id" {
  description = "ID du template Talos Linux"
  type        = number
  default     = 9000
}

# ==========================================
# Network Configuration
# ==========================================

variable "network_gateway" {
  description = "Passerelle réseau"
  type        = string
  default     = "x.x.x.1"
}

variable "dns_servers" {
  description = "Serveurs DNS"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "control_plane_base_ip" {
  description = "Base IP pour les control planes (sans le dernier octet)"
  type        = string
  default     = "x.x.x."
}

variable "worker_base_ip" {
  description = "Base IP pour les workers (sans le dernier octet)"
  type        = string
  default     = "x.x.x."
}

variable "control_plane_vip" {
  description = "VIP pour l'API Kubernetes (LoadBalancer virtuel)"
  type        = string
  default     = "x.x.x.129"
}

# ==========================================
# Kubernetes Cluster Configuration
# ==========================================

variable "cluster_name" {
  description = "Nom du cluster Kubernetes"
  type        = string
  default     = "talos-k8s"
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "L'environnement doit être dev, staging ou prod"
  }
}

# ==========================================
# Control Plane Configuration
# ==========================================

variable "control_plane_count" {
  description = "Nombre de nœuds control plane"
  type        = number
  default     = 1
  
  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count <= 3
    error_message = "Le nombre de control planes doit être entre 1 et 3"
  }
}

variable "control_plane_cpu_cores" {
  description = "Nombre de CPU cores par control plane"
  type        = number
  default     = 4
}

variable "control_plane_memory_mb" {
  description = "Mémoire RAM par control plane (MB)"
  type        = number
  default     = 8192
}

variable "control_plane_disk_size_gb" {
  description = "Taille du disque système (GB)"
  type        = number
  default     = 60
}

# ==========================================
# Worker Configuration
# ==========================================

variable "worker_count" {
  description = "Nombre de nœuds workers"
  type        = number
  default     = 2
  
  validation {
    condition     = var.worker_count >= 1
    error_message = "Au moins 1 worker est requis"
  }
}

variable "worker_cpu_cores" {
  description = "Nombre de CPU cores par worker"
  type        = number
  default     = 4
}

variable "worker_memory_mb" {
  description = "Mémoire RAM par worker (MB)"
  type        = number
  default     = 16384
}

variable "worker_disk_size_gb" {
  description = "Taille du disque système (GB)"
  type        = number
  default     = 80
}

variable "worker_app_disk_size_gb" {
  description = "Taille du disque pour les applications (GB)"
  type        = number
  default     = 100
}

# ==========================================
# Ubuntu Observability Node
# ==========================================

variable "observability_template_vm_id" {
  description = "ID du template Ubuntu pour le nœud observabilité"
  type        = number
  default     = 9001
}

variable "observability_cpu_cores" {
  description = "Nombre de CPU cores pour le nœud observabilité"
  type        = number
  default     = 4
}

variable "observability_memory_mb" {
  description = "Mémoire RAM pour le nœud observabilité (MB)"
  type        = number
  default     = 8192
}

variable "observability_disk_size_gb" {
  description = "Taille du disque système pour observabilité (GB)"
  type        = number
  default     = 100
}

# ==========================================
# Tags
# ==========================================

variable "tags" {
  description = "Tags supplémentaires pour les VMs"
  type        = list(string)
  default     = ["gateway-api", "migration"]
}
