# Module Talos Control Plane
# Créé les nœuds Control Plane Talos sur Proxmox

variable "proxmox_node" {
  description = "Nœud Proxmox"
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster"
  type        = string
}

variable "replicas" {
  description = "Nombre de replicas Control Plane"
  type        = number
  default     = 1
}

variable "vm_config" {
  description = "Configuration des VMs"
  type = object({
    memory    = number
    cores     = number
    sockets   = number
    template  = string
  })
}

variable "network_config" {
  description = "Configuration réseau"
  type = object({
    gateway      = string
    dns_servers  = list(string)
    ip_addresses = list(string)
  })
}

variable "storage_config" {
  description = "Configuration stockage"
  type = object({
    datastore = string
    disk_size = number
  })
}

variable "talos_config" {
  description = "Configuration Talos"
  type = object({
    version          = string
    cluster_domain   = string
    pod_subnet       = string
    service_subnet   = string
  })
}

variable "tags" {
  description = "Tags pour les ressources"
  type        = map(string)
  default     = {}
}

output "control_plane_ip" {
  value = "x.x.x.130"
}

output "kubeconfig" {
  value = "generated-kubeconfig"
}

output "talosconfig" {
  value = "generated-talosconfig"
}
