#!/bin/bash

###############################################################################
# Script de préparation du template Talos Linux sur Proxmox
# À exécuter DIRECTEMENT sur le serveur Proxmox
# Usage: ssh root@proxmox 'bash -s' < prepare-talos-template.sh
###############################################################################

set -euo pipefail

# Configuration
TALOS_VERSION="${TALOS_VERSION:-v1.9.3}"
TEMPLATE_VM_ID="${TEMPLATE_VM_ID:-9001}"
TEMPLATE_NAME="talos-${TALOS_VERSION}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "
╔════════════════════════════════════════════════════════════════╗
║      Préparation du template Talos Linux pour Proxmox          ║
╚════════════════════════════════════════════════════════════════╝
"

# Vérifier si on est sur Proxmox
if ! command -v qm &> /dev/null; then
    log_error "Ce script doit être exécuté sur un serveur Proxmox"
    exit 1
fi

# Vérifier si le template existe déjà
if qm status $TEMPLATE_VM_ID &>/dev/null; then
    log_warning "Template VM ID $TEMPLATE_VM_ID existe déjà"
    read -p "Voulez-vous le supprimer et recréer? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Suppression de l'ancien template..."
        qm destroy $TEMPLATE_VM_ID --purge
    else
        log_error "Opération annulée"
        exit 1
    fi
fi

# Télécharger l'image Talos
log_info "Téléchargement de Talos Linux ${TALOS_VERSION}..."
TALOS_IMAGE="nocloud-amd64.raw.xz"
SCHEMATIC_ID="376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
TALOS_URL="https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/nocloud-amd64.raw.xz"

cd /tmp

log_info "Nettoyage des anciens fichiers..."
rm -f "$TALOS_IMAGE" "${TALOS_IMAGE%.xz}"

log_info "Téléchargement depuis GitHub (cela peut prendre quelques minutes)..."
curl -L -f -o "$TALOS_IMAGE" "$TALOS_URL" --progress-bar || {
    log_error "Téléchargement échoué"
    exit 1
}

# Vérifier que le fichier est bien un .xz
log_info "Vérification du fichier téléchargé..."
if ! file "$TALOS_IMAGE" | grep -q "XZ compressed data"; then
    log_error "Le fichier téléchargé n'est pas un fichier XZ valide"
    exit 1
fi

log_success "Fichier téléchargé et vérifié"

# Décompresser l'image
log_info "Décompression de l'image (cela peut prendre quelques minutes)..."
TALOS_IMAGE_RAW="${TALOS_IMAGE%.xz}"
xz -d -v "$TALOS_IMAGE"

log_success "Image décompressée"

# Créer la VM template
log_info "Création de la VM template..."
qm create $TEMPLATE_VM_ID \
    --name "$TEMPLATE_NAME" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single \
    --ostype l26 \
    --cpu host \
    --agent enabled=1 \
    --machine q35

# Configuration du BIOS et de la console série
qm set $TEMPLATE_VM_ID \
    --bios ovmf \
    --efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=0 \
    --serial0 socket \
    --vga serial0

log_success "VM template créée"

# Importer le disque
log_info "Import du disque Talos..."
qm importdisk $TEMPLATE_VM_ID "$TALOS_IMAGE_RAW" $STORAGE

# Récupérer proprement le disque importé
DISK_ID=$(qm config $TEMPLATE_VM_ID | grep "unused0" | awk '{print $2}')

# Attacher le disque
log_info "Attachement du disque à la VM..."
qm set $TEMPLATE_VM_ID --scsi0 "${DISK_ID},discard=on"

# Configurer le boot
log_info "Configuration du boot..."
qm set $TEMPLATE_VM_ID --boot order=scsi0

# Ajouter le cloud-init drive (pour compatibilité)
log_info "Configuration cloud-init..."
qm set $TEMPLATE_VM_ID --ide2 ${STORAGE}:cloudinit

# Convertir en template
log_info "Conversion en template..."
qm template $TEMPLATE_VM_ID

log_success "Template Talos créé avec succès !"

# Nettoyage
log_info "Nettoyage des fichiers temporaires..."
rm -f "/tmp/$TALOS_IMAGE_RAW"

# Résumé
echo "
╔════════════════════════════════════════════════════════════════╗
║                   Template créé avec succès !                  ║
╚════════════════════════════════════════════════════════════════╝

Informations du template:
   ID: $TEMPLATE_VM_ID
   Nom: $TEMPLATE_NAME
   Version Talos: $TALOS_VERSION
   Storage: $STORAGE
   Bridge: $BRIDGE

Prochaines étapes:
   1. Configurer terraform.tfvars avec:
      talos_template_vm_id = $TEMPLATE_VM_ID
   
   2. Déployer le cluster:
      cd terraform
      terraform init
      terraform apply

   3. Bootstrap Talos:
      Les configurations seront générées automatiquement

Documentation Talos:
   https://www.talos.dev/

"

log_success "Préparation terminée !"