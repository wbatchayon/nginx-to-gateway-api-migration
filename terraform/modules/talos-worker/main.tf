# Talos Worker Module - Main
# Placeholder pour l'implémentation complète du module

resource "null_resource" "talos_workers" {
  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = "echo 'Talos Workers deployment configured'"
  }
}
