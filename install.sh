#!/usr/bin/env bash
# =============================================================================
# DevOps/SRE Infrastructure — Master Installation Script
# Idempotent: safe to run multiple times
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}"
DRY_RUN=false

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
run()         { if [[ "$DRY_RUN" == "true" ]]; then echo -e "${YELLOW}[DRY-RUN]${NC} $*"; else "$@"; fi; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Master installation script for DevOps/SRE infrastructure.

OPTIONS:
  --dry-run     Show what would be done without executing
  --help        Show this help

EXAMPLES:
  $0                  # Full installation
  $0 --dry-run        # Preview only
EOF
}

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --help)    usage; exit 0 ;;
    *)         log_error "Unknown argument: $arg"; usage; exit 1 ;;
  esac
done

# =============================================================================
# PREFLIGHT CHECKS
# =============================================================================
preflight() {
  log_step "Preflight checks"

  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run as root. Use a regular user (sudo is used internally)."
    exit 1
  fi
  log_success "Not running as root"

  # Detect OS
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID="${ID}"
    OS_FAMILY="${ID_LIKE:-$ID}"
    log_success "OS detected: ${PRETTY_NAME}"
  else
    log_warn "Cannot detect OS, assuming Debian-like"
    OS_ID="debian"
    OS_FAMILY="debian"
  fi

  # Check sudo
  if ! sudo -n true 2>/dev/null; then
    log_warn "You will be prompted for sudo password during installation"
  fi

  # Check available disk space (need at least 20GB)
  AVAIL_GB=$(df -BG "${HOME}" | awk 'NR==2 {gsub("G",""); print $4}')
  if [[ "${AVAIL_GB}" -lt 20 ]]; then
    log_warn "Available disk space: ${AVAIL_GB}GB (recommend 20GB+)"
  else
    log_success "Disk space: ${AVAIL_GB}GB available"
  fi

  # Check RAM (recommend 8GB)
  TOTAL_RAM_GB=$(free -g | awk 'NR==2{print $2}')
  if [[ "${TOTAL_RAM_GB}" -lt 4 ]]; then
    log_warn "RAM: ${TOTAL_RAM_GB}GB (recommend 8GB+ for full stack)"
  else
    log_success "RAM: ${TOTAL_RAM_GB}GB"
  fi
}

# =============================================================================
# CREATE DIRECTORY STRUCTURE
# =============================================================================
create_directories() {
  log_step "Creating directory structure"

  local dirs=(
    # Data directories
    "${INFRA_DIR}/data/postgres"
    "${INFRA_DIR}/data/mysql"
    "${INFRA_DIR}/data/redis"
    "${INFRA_DIR}/data/mongodb"
    "${INFRA_DIR}/data/elasticsearch"
    "${INFRA_DIR}/data/kibana"
    "${INFRA_DIR}/data/logstash"
    "${INFRA_DIR}/data/kafka"
    "${INFRA_DIR}/data/zookeeper"
    "${INFRA_DIR}/data/vault"
    "${INFRA_DIR}/data/consul"
    "${INFRA_DIR}/data/minio"
    "${INFRA_DIR}/data/nexus"
    "${INFRA_DIR}/data/registry"
    "${INFRA_DIR}/data/prometheus"
    "${INFRA_DIR}/data/grafana"
    "${INFRA_DIR}/data/alertmanager"
    "${INFRA_DIR}/data/loki"
    "${INFRA_DIR}/data/jenkins"
    "${INFRA_DIR}/data/gitea"
    "${INFRA_DIR}/data/sonarqube"
    "${INFRA_DIR}/data/keycloak"
    "${INFRA_DIR}/data/traefik"
    "${INFRA_DIR}/data/rabbitmq"
    # Log directories
    "${INFRA_DIR}/logs/nginx"
    "${INFRA_DIR}/logs/traefik"
    "${INFRA_DIR}/logs/app"
    "${INFRA_DIR}/logs/k8s"
    "${INFRA_DIR}/logs/ansible"
    "${INFRA_DIR}/logs/cicd"
    "${INFRA_DIR}/logs/security"
    "${INFRA_DIR}/logs/incidents"
    # Backup directories
    "${INFRA_DIR}/backups/postgres"
    "${INFRA_DIR}/backups/mysql"
    "${INFRA_DIR}/backups/redis"
    "${INFRA_DIR}/backups/mongodb"
    "${INFRA_DIR}/backups/configs"
    "${INFRA_DIR}/backups/k8s"
    "${INFRA_DIR}/backups/vault"
    # Certificate directories
    "${INFRA_DIR}/certs/ca"
    "${INFRA_DIR}/certs/nginx"
    "${INFRA_DIR}/certs/postgres"
    "${INFRA_DIR}/certs/redis"
    "${INFRA_DIR}/certs/vault"
    "${INFRA_DIR}/certs/consul"
    "${INFRA_DIR}/certs/traefik"
    # Other
    "${INFRA_DIR}/terraform/generated"
    "/opt/backups"
    "/opt/capacity/reports"
    "/opt/dr"
    "/opt/sample-apps"
  )

  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      run mkdir -p "$dir"
      log_success "Created: $dir"
    else
      log_info "Exists: $dir"
    fi
  done

  # Create sudo-required dirs
  local sudo_dirs=("/opt/vault" "/opt/consul" "/opt/kafka")
  for dir in "${sudo_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      run sudo mkdir -p "$dir"
      run sudo chown "${USER}:${USER}" "$dir"
      log_success "Created: $dir"
    fi
  done
}

# =============================================================================
# INSTALL SYSTEM PACKAGES
# =============================================================================
install_packages() {
  log_step "Installing system packages"

  local common_packages=(curl wget git vim htop jq make python3 python3-pip
                         net-tools dnsutils openssl ca-certificates gnupg lsb-release
                         apt-transport-https software-properties-common unzip tar gzip
                         iptables fail2ban sysstat)

  if echo "${OS_FAMILY}" | grep -qiE "debian|ubuntu"; then
    log_info "Using apt package manager"
    run sudo apt-get update -qq
    run sudo apt-get install -y -qq "${common_packages[@]}" 2>/dev/null || \
      log_warn "Some packages may not be available, continuing..."

    # yq (YAML processor)
    if ! command -v yq &>/dev/null; then
      log_info "Installing yq..."
      run sudo wget -qO /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
      run sudo chmod +x /usr/local/bin/yq
    fi

  elif echo "${OS_FAMILY}" | grep -qiE "rhel|fedora|centos|rocky|almalinux"; then
    log_info "Using dnf/yum package manager"
    local rhel_packages=(curl wget git vim htop jq make python3 python3-pip
                         net-tools bind-utils openssl ca-certificates gnupg unzip
                         tar gzip iptables fail2ban sysstat)
    run sudo dnf install -y -q "${rhel_packages[@]}" 2>/dev/null || \
    run sudo yum install -y -q "${rhel_packages[@]}" 2>/dev/null || \
      log_warn "Some packages may not be available, continuing..."
  else
    log_warn "Unknown OS family, skipping package installation"
  fi

  log_success "System packages installed"
}

# =============================================================================
# INSTALL ANSIBLE
# =============================================================================
install_ansible() {
  log_step "Installing Ansible"

  if command -v ansible &>/dev/null; then
    log_success "Ansible already installed: $(ansible --version | head -1)"
    return 0
  fi

  if command -v pip3 &>/dev/null; then
    run pip3 install --user ansible ansible-lint
    log_success "Ansible installed via pip3"
  elif echo "${OS_FAMILY}" | grep -qiE "debian|ubuntu"; then
    run sudo apt-get install -y -qq ansible
    log_success "Ansible installed via apt"
  else
    run sudo dnf install -y -q ansible || sudo yum install -y -q ansible
    log_success "Ansible installed via dnf/yum"
  fi
}

# =============================================================================
# INSTALL DOCKER
# =============================================================================
install_docker() {
  log_step "Installing Docker"

  if command -v docker &>/dev/null; then
    log_success "Docker already installed: $(docker --version)"
    # Ensure user is in docker group
    if ! groups | grep -q docker; then
      run sudo usermod -aG docker "${USER}"
      log_warn "Added ${USER} to docker group. Log out and back in to apply."
    fi
    return 0
  fi

  if echo "${OS_FAMILY}" | grep -qiE "debian|ubuntu"; then
    log_info "Installing Docker via official script..."
    run curl -fsSL https://get.docker.com | sudo sh
    run sudo usermod -aG docker "${USER}"
    run sudo systemctl enable docker --now
    log_success "Docker installed"
  else
    log_warn "Please install Docker manually for your OS: https://docs.docker.com/engine/install/"
  fi
}

# =============================================================================
# INSTALL KUBECTL
# =============================================================================
install_kubectl() {
  log_step "Installing kubectl"

  if command -v kubectl &>/dev/null; then
    log_success "kubectl already installed: $(kubectl version --client --short 2>/dev/null | head -1)"
    return 0
  fi

  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "v1.29.0")
  run curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  run sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  run rm -f kubectl
  log_success "kubectl ${KUBECTL_VERSION} installed"
}

# =============================================================================
# SETUP ENVIRONMENT FILE
# =============================================================================
setup_env() {
  log_step "Setting up environment file"

  if [[ ! -f "${INFRA_DIR}/.env" ]]; then
    run cp "${INFRA_DIR}/.env.example" "${INFRA_DIR}/.env"
    log_success "Created .env from .env.example"
    log_warn "Review and customize ${INFRA_DIR}/.env before starting services"
  else
    log_info ".env already exists, skipping"
  fi
}

# =============================================================================
# MAKE SCRIPTS EXECUTABLE
# =============================================================================
setup_scripts() {
  log_step "Making scripts executable"

  find "${INFRA_DIR}/scripts" -name "*.sh" -type f | while read -r script; do
    run chmod +x "$script"
    log_success "chmod +x $(basename "$script")"
  done

  [[ -f "${INFRA_DIR}/install.sh" ]] && run chmod +x "${INFRA_DIR}/install.sh"
}

# =============================================================================
# SETUP CRON JOBS
# =============================================================================
setup_crons() {
  log_step "Setting up cron jobs"
  if [[ -f "${INFRA_DIR}/scripts/cron-setup.sh" ]]; then
    run bash "${INFRA_DIR}/scripts/cron-setup.sh"
  else
    log_warn "cron-setup.sh not found, skipping"
  fi
}

# =============================================================================
# OPTIONAL: RUN ANSIBLE BASE PLAYBOOK
# =============================================================================
run_ansible() {
  log_step "Ansible base configuration"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would run: ansible-playbook 01-install-base.yaml"
    return 0
  fi

  if ! command -v ansible-playbook &>/dev/null; then
    log_warn "ansible-playbook not found, skipping"
    return 0
  fi

  read -r -p "Run Ansible base playbook now? (y/N) " answer
  if [[ "${answer,,}" == "y" ]]; then
    ansible-playbook -i "${INFRA_DIR}/ansible/inventory.yaml" \
      "${INFRA_DIR}/ansible/playbooks/01-install-base.yaml"
    log_success "Ansible base playbook completed"
  else
    log_info "Skipping Ansible. Run manually: make ansible-base"
  fi
}

# =============================================================================
# PRINT SUMMARY
# =============================================================================
print_summary() {
  cat <<EOF

${BOLD}${GREEN}
╔══════════════════════════════════════════════════════════════╗
║       DevOps/SRE Infrastructure — Installation Complete      ║
╚══════════════════════════════════════════════════════════════╝${NC}

${BOLD}Quick Start:${NC}
  cd ${INFRA_DIR}
  make db-start          # Start databases
  make monitoring-start  # Start Prometheus + Grafana
  make health            # Check service status

${BOLD}Available UIs (after starting services):${NC}
  Grafana:     http://localhost:3000  (admin/admin)
  Prometheus:  http://localhost:9090
  Kibana:      http://localhost:5601
  Jenkins:     http://localhost:8081
  Vault:       http://localhost:8200

${BOLD}Next steps:${NC}
  1. Review: ${INFRA_DIR}/.env
  2. Run:     make help
  3. Read:    ${INFRA_DIR}/docs/LEARNING-PATH.md
  4. Start:   bash ${INFRA_DIR}/scripts/sre-daily.sh

${BOLD}Full documentation:${NC}
  ${INFRA_DIR}/docs/

EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     DevOps/SRE Infrastructure — Master Installer             ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  [[ "$DRY_RUN" == "true" ]] && log_warn "DRY RUN MODE — no changes will be made"

  preflight
  create_directories
  install_packages
  install_ansible
  install_docker
  install_kubectl
  setup_env
  setup_scripts
  setup_crons
  run_ansible
  print_summary
}

main "$@"
