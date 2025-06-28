
# ===================================================================
# Script 3: Gestion et nettoyage des snapshots
# ===================================================================

#!/bin/bash
# linstor-snapshot-manager.sh

set -e

SCRIPT_NAME="$(basename "$0")"
NAMESPACE="piraeus-datastore"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] COMMAND [ARGS...]

Gestion avancée des snapshots LINSTOR

COMMANDS:
    list [RESOURCE]              Liste tous les snapshots (ou d'une ressource)
    clean RESOURCE DAYS          Supprime les snapshots plus anciens que X jours
    delete RESOURCE SNAPSHOT     Supprime un snapshot specific
    info RESOURCE SNAPSHOT       Affiche les détails d'un snapshot

OPTIONS:
    -n, --namespace NAMESPACE    Namespace du piraeus-operator (défaut: $NAMESPACE)
    -y, --yes                    Confirme automatiquement les suppressions
    -h, --help                   Affiche cette aide

EXEMPLES:
    $SCRIPT_NAME list
    $SCRIPT_NAME list my-pvc
    $SCRIPT_NAME clean my-pvc 7
    $SCRIPT_NAME delete my-pvc backup-20241220-my-pvc
    $SCRIPT_NAME info my-pvc backup-20241227-my-pvc
EOF
}

list_snapshots() {
    local resource="$1"

    echo "📋 Liste des snapshots LINSTOR"
    echo "================================"

    if [ -n "$resource" ]; then
        echo "Ressource: $resource"
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor snapshot list "$resource"
    else
        echo "Toutes les ressources:"
        kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
            linstor snapshot list
    fi
}

clean_old_snapshots() {
    local resource="$1"
    local days="$2"
    local auto_confirm="$3"

    echo "🧹 Nettoyage des snapshots de '$resource' plus anciens que $days jours"

    # Récupérer la liste des snapshots avec dates
    local snapshots
    snapshots=$(kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor snapshot list "$resource" --parsable | tail -n +2)

    if [ -z "$snapshots" ]; then
        echo "ℹ️ Aucun snapshot trouvé pour la ressource '$resource'"
        return
    fi

    local cutoff_date
    cutoff_date=$(date -d "$days days ago" +%s)

    echo "$snapshots" | while IFS='|' read -r res_name snap_name created_date rest; do
        # Nettoyer les espaces
        snap_name=$(echo "$snap_name" | tr -d ' ')
        created_date=$(echo "$created_date" | tr -d ' ')

        # Convertir la date du snapshot en timestamp
        local snap_timestamp
        snap_timestamp=$(date -d "$created_date" +%s 2>/dev/null || echo "0")

        if [ "$snap_timestamp" -lt "$cutoff_date" ] && [ "$snap_timestamp" -gt "0" ]; then
            echo "🗑️ Snapshot à supprimer: $snap_name (créé le $created_date)"

            if [ "$auto_confirm" = "true" ]; then
                delete_snapshot "$resource" "$snap_name"
            else
                read -p "Supprimer ce snapshot ? (y/N): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    delete_snapshot "$resource" "$snap_name"
                fi
            fi
        fi
    done
}

delete_snapshot() {
    local resource="$1"
    local snapshot="$2"

    echo "🗑️ Suppression du snapshot '$snapshot' de la ressource '$resource'..."

    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor snapshot delete "$resource" "$snapshot"

    if [ $? -eq 0 ]; then
        echo "✅ Snapshot supprimé avec succès"
    else
        echo "❌ Erreur lors de la suppression"
    fi
}

snapshot_info() {
    local resource="$1"
    local snapshot="$2"

    echo "📋 Informations détaillées du snapshot"
    echo "======================================"
    echo "Ressource: $resource"
    echo "Snapshot: $snapshot"
    echo ""

    kubectl exec -n "$NAMESPACE" deployment/linstor-controller -- \
        linstor snapshot list "$resource" "$snapshot"
}

# Parsing des arguments
AUTO_CONFIRM="false"
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_CONFIRM="true"
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
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    echo "❌ Commande requise" >&2
    usage >&2
    exit 1
fi

case "$COMMAND" in
    list)
        list_snapshots "${ARGS[0]}"
        ;;
    clean)
        if [ ${#ARGS[@]} -lt 2 ]; then
            echo "❌ 'clean' nécessite RESOURCE et DAYS" >&2
            usage >&2
            exit 1
        fi
        clean_old_snapshots "${ARGS[0]}" "${ARGS[1]}" "$AUTO_CONFIRM"
        ;;
    delete)
        if [ ${#ARGS[@]} -lt 2 ]; then
            echo "❌ 'delete' nécessite RESOURCE et SNAPSHOT" >&2
            usage >&2
            exit 1
        fi
        delete_snapshot "${ARGS[0]}" "${ARGS[1]}"
        ;;
    info)
        if [ ${#ARGS[@]} -lt 2 ]; then
            echo "❌ 'info' nécessite RESOURCE et SNAPSHOT" >&2
            usage >&2
            exit 1
        fi
        snapshot_info "${ARGS[0]}" "${ARGS[1]}"
        ;;
    *)
        echo "❌ Commande inconnue: $COMMAND" >&2
        usage >&2
        exit 1
        ;;
esac
