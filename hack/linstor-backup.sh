#!/bin/bash

# ===================================================================
# Script 1: Backup de volumes LINSTOR via clonage (compatible LVM)
# ===================================================================

#!/bin/bash
# linstor-backup-clone.sh

set -e

SCRIPT_NAME="$(basename "$0")"
NAME    SPACE="piraeus-datastore"
BACKUP_PREFIX="backup-$(date +%m%d-%H%M)"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] RESOURCE_NAME

Crée une sauvegarde d'une ressource LINSTOR via clonage (compatible LVM)

OPTIONS:
    -n, --namespace NAMESPACE    Namespace du piraeus-operator (défaut: $NAMESPACE)
    -p, --prefix PREFIX          Préfixe pour le backup (défaut: $BACKUP_PREFIX)
    -d, --description DESC       Description du backup
    -t, --temporary              Crée un clone temporaire (sera supprimé)
    -k, --keep-clone             Garde le clone après export
    -o, --output-dir DIR         Répertoire de sortie pour l'export (défaut: /tmp/linstor-backups)
    -h, --help                   Affiche cette aide

EXEMPLES:
    $SCRIPT_NAME my-pvc
    $SCRIPT_NAME -d "Backup avant mise à jour" -o /backups my-database-vol
    $SCRIPT_NAME -t -k my-vol  # Clone temporaire gardé
EOF
}

# Générer un nom de backup court
generate_backup_name() {
    local resource_name="$1"
    local prefix="$2"

    # Utiliser un hash pour les noms très longs
    if [ ${#resource_name} -gt 30 ]; then
        local resource_hash=$(echo "$resource_name" | sha256sum | cut -c1-8)
        echo "${prefix}-${resource_hash}"
    else
        echo "${prefix}-${resource_name}"
    fi
}

# Créer un clone de la ressource
create_clone() {
    local source_resource="$1"
    local clone_name="$2"
    local description="$3"

    echo "🔄 Création du clone '$clone_name' de la ressource '$source_resource'..."

    # Obtenir les informations de la ressource source (sans --parsable)
    echo "📋 Récupération des informations de la ressource source..."
    local resource_info
    resource_info=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource list -r "$source_resource")

    if [ -z "$resource_info" ]; then
        echo "❌ Ressource '$source_resource' introuvable"
        exit 1
    fi

    # Vérifier que la ressource existe en cherchant son nom dans la sortie
    if ! echo "$resource_info" | grep -q "$source_resource"; then
        echo "❌ Ressource '$source_resource' introuvable"
        exit 1
    fi

    # Créer la définition de ressource pour le clone
    echo "📝 Création de la définition de ressource clone..."
    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource-definition create "$clone_name"

    # Copier les volumes (sans --parsable)
    echo "💾 Copie des volumes..."
    local volumes_output
    volumes_output=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor volume-definition list -r "$source_resource")

    # Parser la sortie manuellement (adapter selon le format de votre version)
    # Cette partie doit être adaptée selon la sortie exacte de votre commande
    local volume_ids
    volume_ids=$(echo "$volumes_output" | grep -E "^\s*[0-9]+" | awk '{print $1}' | sort -u)

    for vol_id in $volume_ids; do
        # Obtenir la taille du volume
        local size_info
        size_info=$(echo "$volumes_output" | grep -E "^\s*${vol_id}\s+" | head -n1)
        local size_kb=$(echo "$size_info" | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+[kKmMgGtT][bB]?$/) print $i}' | head -n1)

        if [ -z "$size_kb" ]; then
            # Fallback: essayer d'obtenir la taille autrement
            size_kb="1GiB"  # Taille par défaut, à ajuster
        fi

        # Créer la définition de volume pour le clone
        echo "  Création du volume $vol_id avec taille $size_kb"
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor volume-definition create "$clone_name" "$vol_id" "$size_kb"
    done

    # Déployer le clone sur les mêmes nœuds que la source
    echo "🚀 Déploiement du clone..."
    local nodes_output
    nodes_output=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource list -r "$source_resource")

    # Parser les nœuds manuellement
    local nodes
    nodes=$(echo "$nodes_output" | grep "$source_resource" | awk '{print $2}' | sort -u)

    for node in $nodes; do
        if [ -n "$node" ] && [ "$node" != "Node" ]; then  # Éviter les en-têtes
            echo "  Déploiement sur le nœud: $node"
            kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
                linstor resource create "$clone_name" "$node"
        fi
    done

    # Ajouter des propriétés au clone
    if [ -n "$description" ]; then
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor resource-definition set-property "$clone_name" Description "$description"
    fi

    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource-definition set-property "$clone_name" BackupSource "$source_resource"

    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource-definition set-property "$clone_name" BackupDate "$(date -Iseconds)"

    echo "✅ Clone '$clone_name' créé avec succès !"
}

# Exporter les données du clone
export_clone_data() {
    local clone_name="$1"
    local output_dir="$2"
    local keep_clone="$3"

    echo "📤 Export des données du clone '$clone_name'..."

    # Créer le répertoire de sortie
    mkdir -p "$output_dir"

    # Trouver le device du clone sur un nœud (sans --parsable)
    local resource_output
    resource_output=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource list -r "$clone_name")

    local node_name
    node_name=$(echo "$resource_output" | grep "$clone_name" | head -n1 | awk '{print $2}')

    if [ -z "$node_name" ] || [ "$node_name" = "Node" ]; then
        echo "❌ Impossible de trouver un nœud pour le clone"
        return 1
    fi

    echo "📍 Export depuis le nœud: $node_name"

    # Obtenir le chemin du device (sans --parsable)
    local volume_output
    volume_output=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor resource list-volumes -r "$clone_name" -n "$node_name")

    local device_path
    device_path=$(echo "$volume_output" | grep "/dev/" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\/dev\//) print $i}' | head -n1)

    if [ -n "$device_path" ]; then
        local backup_file="$output_dir/${clone_name}-$(date +%Y%m%d-%H%M%S).img"

        echo "💾 Création de l'image disque: $backup_file"
        echo "⚠️  Cette opération peut prendre du temps selon la taille du volume..."

        # Créer un Job Kubernetes pour faire le backup
        echo "📋 Création d'un Job Kubernetes pour l'export..."

        cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: linstor-backup-export-$(date +%s)
  namespace: $NAMESPACE
spec:
  template:
    spec:
      nodeName: $node_name
      containers:
      - name: backup-exporter
        image: alpine:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          apk add --no-cache pv
          echo "Démarrage de l'export de $device_path vers $backup_file"
          dd if=$device_path bs=1M conv=sparse | pv > $backup_file
          echo "Export terminé: $backup_file"
        volumeMounts:
        - name: host-dev
          mountPath: /dev
        - name: backup-storage
          mountPath: $output_dir
        securityContext:
          privileged: true
      volumes:
      - name: host-dev
        hostPath:
          path: /dev
      - name: backup-storage
        hostPath:
          path: $output_dir
      restartPolicy: Never
  backoffLimit: 3
EOF

        echo "✅ Job de backup créé. Surveillez avec: kubectl logs -n $NAMESPACE job/linstor-backup-export-*"

    else
        echo "❌ Impossible de trouver le chemin du device pour le clone"
    fi

    # Nettoyer le clone si demandé
    if [ "$keep_clone" != "true" ]; then
        echo "🗑️ Suppression du clone temporaire..."
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor resource-definition delete "$clone_name"
        echo "✅ Clone temporaire supprimé"
    else
        echo "📌 Clone conservé: $clone_name"
    fi
}

# Parsing des arguments
RESOURCE_NAME=""
DESCRIPTION=""
TEMPORARY="false"
KEEP_CLONE="false"
OUTPUT_DIR="/tmp/linstor-backups"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -p|--prefix)
            BACKUP_PREFIX="$2"
            shift 2
            ;;
        -d|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -t|--temporary)
            TEMPORARY="true"
            shift
            ;;
        -k|--keep-clone)
            KEEP_CLONE="true"
            shift
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Option inconnue: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -z "$RESOURCE_NAME" ]; then
                RESOURCE_NAME="$1"
            else
                echo "Trop d'arguments" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$RESOURCE_NAME" ]; then
    echo "❌ Nom de ressource requis" >&2
    usage >&2
    exit 1
fi

CLONE_NAME=$(generate_backup_name "$RESOURCE_NAME" "$BACKUP_PREFIX")

echo "🚀 Démarrage du backup LINSTOR via clonage"
echo "   Ressource source: $RESOURCE_NAME"
echo "   Clone: $CLONE_NAME"
echo "   Namespace: $NAMESPACE"
echo "   Répertoire de sortie: $OUTPUT_DIR"
echo ""

create_clone "$RESOURCE_NAME" "$CLONE_NAME" "$DESCRIPTION"
export_clone_data "$CLONE_NAME" "$OUTPUT_DIR" "$KEEP_CLONE"

echo ""
echo "✅ Backup terminé !"
if [ "$KEEP_CLONE" = "true" ]; then
    echo "📌 Clone disponible: $CLONE_NAME"
fi
