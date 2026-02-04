terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.71.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.8.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = var.proxmox_ssh_user
    password = var.proxmox_ssh_password
  }
}

# ==========================================
# Talos Control Plane Nodes (1x - x.x.x.130)
# ==========================================

resource "proxmox_virtual_environment_vm" "talos_control_plane" {
  count = var.control_plane_count

  name        = "talos-cp-${var.environment}"
  node_name   = var.proxmox_node
  vm_id       = 130
  description = "Talos Kubernetes Control Plane"

  clone {
    vm_id = var.talos_template_vm_id
  }

  cpu {
    cores = var.control_plane_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.control_plane_memory_mb
    floating  = 1024
  }

  # Correction : Utiliser le mode VGA standard pour voir le dashboard Talos
  vga {
    type = "std"
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = var.control_plane_disk_size_gb
    iothread     = true
    file_format  = "raw"
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi1"
    size         = 20
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "x.x.x.130/24"
        gateway = var.network_gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  agent {
    enabled = true
    timeout = "60s"
  }

  tags = ["kubernetes", "talos", "control-plane", var.environment]

  lifecycle {
    ignore_changes = [initialization]
  }
}

# ==========================================
# Talos Worker Nodes (2x - x.x.x.132, x.x.x.133)
# ==========================================

resource "proxmox_virtual_environment_vm" "talos_worker" {
  count = var.worker_count

  name        = "talos-worker-${count.index + 1}-${var.environment}"
  node_name   = var.proxmox_node
  vm_id       = 132 + count.index
  description = "Talos Kubernetes Worker ${count.index + 1}"

  clone {
    vm_id = var.talos_template_vm_id
  }

  cpu {
    cores = var.worker_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_memory_mb
    floating  = 2048
  }

  vga {
    type = "std"
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = var.worker_disk_size_gb
    iothread     = true
    file_format  = "raw"
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi1"
    size         = var.worker_app_disk_size_gb
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "x.x.x.${132 + count.index}/24"
        gateway = var.network_gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  agent {
    enabled = true
    timeout = "60s"
  }

  tags = ["kubernetes", "talos", "worker", var.environment]

  lifecycle {
    ignore_changes = [initialization]
  }
}

# ==========================================
# Ubuntu Observability Node (x.x.x.131)
# ==========================================

resource "proxmox_virtual_environment_vm" "ubuntu_observability" {
  name        = "observability-${var.environment}"
  node_name   = var.proxmox_node
  vm_id       = 131
  description = "Ubuntu VM for Observability Stack"

  clone {
    vm_id = var.observability_template_vm_id
  }

  cpu {
    cores = var.observability_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.observability_memory_mb
    floating  = 512
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = var.observability_disk_size_gb
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.proxmox_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "x.x.x.131/24"
        gateway = var.network_gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
  }

  agent {
    enabled = true
    timeout = "60s"
  }

  tags = ["observability", "monitoring", "ubuntu", var.environment]
}

# ==========================================
# PAUSE DE 5 MINUTES
# ==========================================

resource "time_sleep" "wait_for_vm_boot" {
  depends_on = [
    proxmox_virtual_environment_vm.talos_control_plane,
    proxmox_virtual_environment_vm.talos_worker
  ]
  create_duration = "5m"
}

# ==========================================
# Talos Configuration
# ==========================================

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "control_plane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.control_plane_vip}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

resource "talos_machine_configuration_apply" "control_plane" {
  count = var.control_plane_count

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_plane.machine_configuration
  # Correction : split pour envoyer l'IP sans le /24 au provider Talos
  node                        = split("/", proxmox_virtual_environment_vm.talos_control_plane[count.index].initialization[0].ip_config[0].ipv4[0].address)[0]
  endpoint                    = split("/", proxmox_virtual_environment_vm.talos_control_plane[count.index].initialization[0].ip_config[0].ipv4[0].address)[0]

  depends_on = [time_sleep.wait_for_vm_boot]
}

resource "talos_machine_configuration_apply" "worker" {
  count = var.worker_count

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = split("/", proxmox_virtual_environment_vm.talos_worker[count.index].initialization[0].ip_config[0].ipv4[0].address)[0]
  endpoint                    = split("/", proxmox_virtual_environment_vm.talos_worker[count.index].initialization[0].ip_config[0].ipv4[0].address)[0]

  depends_on = [time_sleep.wait_for_vm_boot]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = split("/", proxmox_virtual_environment_vm.talos_control_plane[0].initialization[0].ip_config[0].ipv4[0].address)[0]
  endpoint             = split("/", proxmox_virtual_environment_vm.talos_control_plane[0].initialization[0].ip_config[0].ipv4[0].address)[0]

  depends_on = [talos_machine_configuration_apply.control_plane]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = split("/", proxmox_virtual_environment_vm.talos_control_plane[0].initialization[0].ip_config[0].ipv4[0].address)[0]
  endpoint             = split("/", proxmox_virtual_environment_vm.talos_control_plane[0].initialization[0].ip_config[0].ipv4[0].address)[0]

  depends_on = [talos_machine_bootstrap.this]
}