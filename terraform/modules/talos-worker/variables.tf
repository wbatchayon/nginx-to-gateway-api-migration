# Module Talos Worker
# Crée les nœuds Worker Talos sur Proxmox

variable "proxmox_node" {
  description = "Nœud Proxmox"
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster"
  type        = string
}

variable "count_workers" {
  description = "Nombre de workers"
  type        = number
  default     = 2
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

output "worker_ips" {
  value = ["x.x.x.132", "x.x.x.133"]
}

output "gateway_lb_ip" {
  value = "x.x.x.132"
}
