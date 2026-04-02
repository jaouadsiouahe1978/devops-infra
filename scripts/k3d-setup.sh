#!/usr/bin/env bash
# =============================================================================
# k3d-setup.sh — Multi-cluster k3d management for DevOps/SRE learning infra
# Usage: ./scripts/k3d-setup.sh [OPTIONS]
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}==> $*${RESET}"; }

# ---------------------------------------------------------------------------
# Script root (directory where this script lives, regardless of cwd)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLUSTERS_DIR="${REPO_ROOT}/kubernetes/clusters"
KUBECONFIG_DIR="${HOME}/.kube"

VALID_CLUSTERS=(dev staging prod)

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=0

    for cmd in docker curl kubectl; do
        if command -v "$cmd" &>/dev/null; then
            log_success "$cmd found: $(command -v "$cmd")"
        else
            log_warn "$cmd not found — please install it before proceeding"
            missing=1
        fi
    done

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Start Docker Desktop (WSL2) or run 'sudo service docker start'."
        exit 1
    fi

    return $missing
}

# ---------------------------------------------------------------------------
# Install k3d
# ---------------------------------------------------------------------------
install_k3d() {
    log_step "Installing k3d"

    if command -v k3d &>/dev/null; then
        log_success "k3d already installed: $(k3d version | head -1)"
        return 0
    fi

    log_info "Downloading and installing k3d via official install script..."
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

    if command -v k3d &>/dev/null; then
        log_success "k3d installed successfully: $(k3d version | head -1)"
    else
        log_error "k3d installation failed. Check the output above."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Validate cluster name
# ---------------------------------------------------------------------------
validate_cluster_name() {
    local name="$1"
    for valid in "${VALID_CLUSTERS[@]}"; do
        [[ "$name" == "$valid" ]] && return 0
    done
    log_error "Unknown cluster name '${name}'. Valid names: ${VALID_CLUSTERS[*]}"
    exit 1
}

# ---------------------------------------------------------------------------
# Create a single cluster
# ---------------------------------------------------------------------------
create_cluster() {
    local name="$1"
    validate_cluster_name "$name"

    local config_file="${CLUSTERS_DIR}/${name}-cluster.yaml"

    if [[ ! -f "$config_file" ]]; then
        log_error "Cluster config not found: ${config_file}"
        exit 1
    fi

    log_step "Creating cluster: ${name}"

    if k3d cluster list | grep -q "^${name}\b"; then
        log_warn "Cluster '${name}' already exists — skipping creation."
        return 0
    fi

    k3d cluster create --config "${config_file}"
    log_success "Cluster '${name}' created."

    get_kubeconfig "$name"
}

# ---------------------------------------------------------------------------
# Create all clusters
# ---------------------------------------------------------------------------
create_all_clusters() {
    log_step "Creating all clusters (dev, staging, prod)"
    for name in "${VALID_CLUSTERS[@]}"; do
        create_cluster "$name"
    done
    merge_kubeconfigs
    log_success "All clusters created and kubeconfigs merged."
}

# ---------------------------------------------------------------------------
# Delete a cluster
# ---------------------------------------------------------------------------
delete_cluster() {
    local name="$1"
    validate_cluster_name "$name"

    log_step "Deleting cluster: ${name}"

    if ! k3d cluster list | grep -q "^${name}\b"; then
        log_warn "Cluster '${name}' does not exist — nothing to delete."
        return 0
    fi

    k3d cluster delete "${name}"
    log_success "Cluster '${name}' deleted."

    local kc_file="${KUBECONFIG_DIR}/config-${name}"
    if [[ -f "$kc_file" ]]; then
        rm -f "$kc_file"
        log_info "Removed kubeconfig: ${kc_file}"
    fi
}

# ---------------------------------------------------------------------------
# List clusters
# ---------------------------------------------------------------------------
list_clusters() {
    log_step "k3d cluster list"
    k3d cluster list
}

# ---------------------------------------------------------------------------
# Export kubeconfig for a single cluster
# ---------------------------------------------------------------------------
get_kubeconfig() {
    local name="$1"
    validate_cluster_name "$name"

    mkdir -p "${KUBECONFIG_DIR}"
    local dest="${KUBECONFIG_DIR}/config-${name}"

    log_info "Exporting kubeconfig for '${name}' -> ${dest}"
    k3d kubeconfig get "${name}" > "${dest}"
    chmod 600 "${dest}"
    log_success "Kubeconfig written to ${dest}"
}

# ---------------------------------------------------------------------------
# Merge all available cluster kubeconfigs into ~/.kube/config
# ---------------------------------------------------------------------------
merge_kubeconfigs() {
    log_step "Merging cluster kubeconfigs into ${KUBECONFIG_DIR}/config"

    local configs=()

    for name in "${VALID_CLUSTERS[@]}"; do
        local kc="${KUBECONFIG_DIR}/config-${name}"
        if [[ -f "$kc" ]]; then
            configs+=("$kc")
            log_info "Found kubeconfig: ${kc}"
        else
            log_warn "Kubeconfig not found for cluster '${name}' — skipping (${kc})"
        fi
    done

    if [[ ${#configs[@]} -eq 0 ]]; then
        log_error "No kubeconfigs found to merge."
        exit 1
    fi

    local merged_file="${KUBECONFIG_DIR}/config"

    # Back up existing config if present
    if [[ -f "$merged_file" ]]; then
        local backup="${merged_file}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$merged_file" "$backup"
        log_info "Backed up existing config to: ${backup}"
    fi

    # Build the KUBECONFIG env var with all files separated by ':'
    local kubeconfig_env
    kubeconfig_env=$(IFS=':'; echo "${configs[*]}")

    KUBECONFIG="${kubeconfig_env}" kubectl config view --flatten > "${merged_file}"
    chmod 600 "${merged_file}"

    log_success "Merged kubeconfig written to ${merged_file}"
    log_info "Available contexts:"
    kubectl --kubeconfig="${merged_file}" config get-contexts
}

# ---------------------------------------------------------------------------
# Print help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF

${BOLD}k3d-setup.sh${RESET} — Multi-cluster k3d management for DevOps/SRE infrastructure

${BOLD}USAGE${RESET}
  ./scripts/k3d-setup.sh [OPTIONS]

${BOLD}OPTIONS${RESET}
  --install                  Install k3d (uses official install script)
  --create=<name|all>        Create a cluster by name, or all clusters at once
                               Valid names: dev, staging, prod, all
  --delete=<name>            Delete a named cluster (also removes its kubeconfig)
  --list                     List all k3d clusters
  --kubeconfig=<name>        Export kubeconfig for a cluster to ~/.kube/config-<name>
  --merge                    Merge all cluster kubeconfigs into ~/.kube/config
  -h, --help                 Show this help message

${BOLD}EXAMPLES${RESET}
  # Install k3d, then create all three clusters and merge kubeconfigs
  ./scripts/k3d-setup.sh --install
  ./scripts/k3d-setup.sh --create=all

  # Create a single cluster
  ./scripts/k3d-setup.sh --create=dev

  # List running clusters
  ./scripts/k3d-setup.sh --list

  # Export kubeconfig for staging, then switch context
  ./scripts/k3d-setup.sh --kubeconfig=staging
  kubectl config use-context k3d-staging

  # Delete the dev cluster
  ./scripts/k3d-setup.sh --delete=dev

  # Re-merge after adding a new cluster
  ./scripts/k3d-setup.sh --merge

${BOLD}CONTEXT SWITCHING${RESET}
  kubectl config use-context k3d-dev
  kubectl config use-context k3d-staging
  kubectl config use-context k3d-prod

  # Or inline for a single command
  kubectl --context=k3d-prod get nodes

${BOLD}NOTES${RESET}
  - Requires Docker to be running (docker info should succeed)
  - On WSL2: ensure Docker Desktop WSL2 integration is enabled
  - Cluster configs live in: kubernetes/clusters/<name>-cluster.yaml
  - Kubeconfigs are stored in: ~/.kube/config-<name>
  - Merged config lives in:   ~/.kube/config

EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --install)
            check_prerequisites || true
            install_k3d
            ;;
        --create=all)
            check_prerequisites
            create_all_clusters
            ;;
        --create=*)
            check_prerequisites
            cluster_name="${arg#--create=}"
            create_cluster "$cluster_name"
            ;;
        --delete=*)
            cluster_name="${arg#--delete=}"
            delete_cluster "$cluster_name"
            ;;
        --list)
            list_clusters
            ;;
        --kubeconfig=*)
            cluster_name="${arg#--kubeconfig=}"
            get_kubeconfig "$cluster_name"
            ;;
        --merge)
            merge_kubeconfigs
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: ${arg}"
            usage
            exit 1
            ;;
    esac
done
