# ===================================================================
# Script 2: Restoration de volumes LINSTOR
# ===================================================================

#!/bin/bash
# linstor-restore.sh

set -e

SCRIPT_NAME="$(basename "$0")"
NAMESPACE="piraeus-datastore"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] RESOURCE_NAME SNAPSHOT_NAME [NEW_RESOURCE_NAME]

Restaure une ressource LINSTOR depuis un snapshot

OPTIONS:
    -n, --namespace NAMESPACE    Namespace du piraeus-operator (défaut: $NAMESPACE)
    -f, --force                  Force la restauration même si la ressource existe
    -h, --help                   Affiche cette aide

ARGUMENTS:
    RESOURCE_NAME               Nom de la ressource source
    SNAPSHOT_NAME              Nom du snapshot à restaurer
    NEW_RESOURCE_NAME          Nom de la nouvelle ressource (optionnel)

EXEMPLES:
    $SCRIPT_NAME my-pvc backup-20241227-my-pvc
    $SCRIPT_NAME my-db backup-20241227-my-db my-db-restored
    $SCRIPT_NAME -f my-vol weekly-backup-my-vol
EOF
}

restore_from_snapshot() {
    local source_resource="$1"
    local snapshot_name="$2"
    local target_resource="$3"
    local force="$4"

    echo "🔄 Restauration depuis le snapshot '$snapshot_name'..."

    # Vérifier si le snapshot existe
    echo "🔍 Vérification de l'existence du snapshot..."
    if ! kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor snapshot list "$source_resource" | grep -q "$snapshot_name"; then
        echo "❌ Snapshot '$snapshot_name' introuvable pour la ressource '$source_resource'"
        exit 1
    fi

    # Vérifier si la ressource cible existe déjà
    if [ "$force" != "true" ]; then
        if kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor resource list | grep -q "^| $target_resource "; then
            echo "❌ La ressource '$target_resource' existe déjà. Utilisez -f pour forcer."
            exit 1
        fi
    fi

    # Restaurer depuis le snapshot
    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor snapshot volume-definition restore \
        --from-resource "$source_resource" \
        --from-snapshot "$snapshot_name" \
        --to-resource "$target_resource"

    if [ $? -eq 0 ]; then
        echo "✅ Restauration réussie !"
        echo "📋 Informations de la ressource restaurée :"
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor resource list-volumes "$target_resource"
    else
        echo "❌ Erreur lors de la restauration"
        exit 1
    fi
}

# Parsing des arguments
FORCE="false"
RESOURCE_NAME=""
SNAPSHOT_NAME=""
NEW_RESOURCE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE="true"
            shift
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
            elif [ -z "$SNAPSHOT_NAME" ]; then
                SNAPSHOT_NAME="$1"
            elif [ -z "$NEW_RESOURCE_NAME" ]; then
                NEW_RESOURCE_NAME="$1"
            else
                echo "Trop d'arguments" >&2
                usage >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$RESOURCE_NAME" ] || [ -z "$SNAPSHOT_NAME" ]; then
    echo "❌ Nom de ressource et nom de snapshot requis" >&2
    usage >&2
    exit 1
fi

# Si pas de nouveau nom spécifié, utiliser le nom original avec suffixe
if [ -z "$NEW_RESOURCE_NAME" ]; then
    NEW_RESOURCE_NAME="${RESOURCE_NAME}-restored-$(date +%Y%m%d-%H%M%S)"
fi

echo "🚀 Démarrage de la restauration LINSTOR"
echo "   Ressource source: $RESOURCE_NAME"
echo "   Snapshot: $SNAPSHOT_NAME"
echo "   Ressource cible: $NEW_RESOURCE_NAME"
echo "   Namespace: $NAMESPACE"
echo ""

restore_from_snapshot "$RESOURCE_NAME" "$SNAPSHOT_NAME" "$NEW_RESOURCE_NAME" "$FORCE"
