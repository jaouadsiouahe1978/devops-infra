#!/usr/bin/env bash
# health-check.sh — Comprehensive DevOps infrastructure health dashboard
# Usage: health-check.sh [--json] [--help]
set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Paths ──────────────────────────────────────────────────────────────────────
INFRA_DIR="$HOME/devops-infra"
LOG_DIR="$INFRA_DIR/logs"
BACKUP_DIR="$INFRA_DIR/backups"
DATA_DIR="$INFRA_DIR/data"
LOG_FILE="$LOG_DIR/health-check.log"

# ── Flags ──────────────────────────────────────────────────────────────────────
JSON_OUTPUT=false

# ── Logging helpers ────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive health dashboard for the DevOps/SRE learning infrastructure.

Options:
  --json    Output results as machine-readable JSON
  --help    Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --json
EOF
  exit 0
}

# ── Parse args ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --help) usage ;;
    *) log_error "Unknown argument: $arg"; usage ;;
  esac
done

# ── Ensure directories ─────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR" "$DATA_DIR" "$BACKUP_DIR"

# ── Service definitions: "Name:Port" ───────────────────────────────────────────
declare -a SERVICES=(
  "PostgreSQL:5432"
  "MySQL:3306"
  "Redis:6379"
  "MongoDB:27017"
  "Prometheus:9090"
  "Grafana:3000"
  "AlertManager:9093"
  "Loki:3100"
  "Elasticsearch:9200"
  "Kibana:5601"
  "Logstash:5044"
  "Jenkins:8081"
  "Gitea:3001"
  "ArgoCD:8083"
  "Vault:8200"
  "Consul:8500"
  "Keycloak:8085"
  "Kafka:9092"
  "RabbitMQ:5672"
  "RabbitMQ-Mgmt:15672"
  "MinIO:9001"
  "Nexus:8084"
  "Registry:5000"
  "Traefik:8080"
  "HAProxy:9999"
  "Nginx:8091"
  "Node-Exporter:9100"
  "cAdvisor:8088"
  "SonarQube:9000"
  "etcd:2379"
)

# ── Port check ─────────────────────────────────────────────────────────────────
check_port() {
  local host="localhost"
  local port="$1"
  nc -zv "$host" "$port" 2>/dev/null
}

# ── Gather service statuses ────────────────────────────────────────────────────
declare -a STATUS_NAMES=()
declare -a STATUS_PORTS=()
declare -a STATUS_VALUES=()   # UP or DOWN

gather_statuses() {
  for entry in "${SERVICES[@]}"; do
    local name="${entry%%:*}"
    local port="${entry##*:}"
    STATUS_NAMES+=("$name")
    STATUS_PORTS+=("$port")
    if check_port "$port"; then
      STATUS_VALUES+=("UP")
    else
      STATUS_VALUES+=("DOWN")
    fi
  done
}

# ── ASCII table helpers ────────────────────────────────────────────────────────
print_table() {
  local up_count=0
  local total=${#STATUS_NAMES[@]}

  echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║       DEVOPS INFRASTRUCTURE HEALTH           ║${NC}"
  echo -e "${BLUE}╠══════════════════╦════════╦══════════════════╣${NC}"
  echo -e "${BLUE}║${NC} $(printf '%-16s' 'SERVICE')   ${BLUE}║${NC} $(printf '%-6s' 'PORT')  ${BLUE}║${NC} $(printf '%-16s' 'STATUS')   ${BLUE}║${NC}"
  echo -e "${BLUE}╠══════════════════╬════════╬══════════════════╣${NC}"

  for i in "${!STATUS_NAMES[@]}"; do
    local name="${STATUS_NAMES[$i]}"
    local port="${STATUS_PORTS[$i]}"
    local status="${STATUS_VALUES[$i]}"

    if [[ "$status" == "UP" ]]; then
      up_count=$((up_count + 1))
      local status_str="${GREEN}✓ UP${NC}            "
    else
      local status_str="${RED}✗ DOWN${NC}          "
    fi

    echo -e "${BLUE}║${NC} $(printf '%-16s' "$name")   ${BLUE}║${NC} $(printf '%-6s' "$port")  ${BLUE}║${NC} ${status_str} ${BLUE}║${NC}"
  done

  echo -e "${BLUE}╚══════════════════╩════════╩══════════════════╝${NC}"
  echo ""
  echo -e "  Services UP: ${GREEN}${up_count}${NC}/${total}"
}

# ── System metrics ─────────────────────────────────────────────────────────────
get_docker_count() {
  if command -v docker &>/dev/null; then
    docker ps -q 2>/dev/null | wc -l || echo "0"
  else
    echo "N/A"
  fi
}

get_disk_usage() {
  if [[ -d "$DATA_DIR" ]]; then
    df -h "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $5, $3"/"$2}' || echo "N/A"
  else
    echo "N/A (data dir missing)"
  fi
}

get_disk_pct() {
  if [[ -d "$DATA_DIR" ]]; then
    df "$DATA_DIR" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || echo "0"
  else
    echo "0"
  fi
}

get_memory() {
  free -h 2>/dev/null | awk 'NR==2 {print "Used: "$3" / Total: "$2" / Free: "$4}' || echo "N/A"
}

get_uptime() {
  uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A"
}

get_last_backup() {
  local newest
  newest=$(find "$BACKUP_DIR" -type f \( -name "*.gz" -o -name "*.rdb" -o -name "*.snap" \) \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
  if [[ -n "$newest" ]]; then
    echo "$(stat -c '%y' "$newest" 2>/dev/null | cut -d'.' -f1) — $newest"
  else
    echo "No backups found"
  fi
}

# ── System info table ──────────────────────────────────────────────────────────
print_system_info() {
  local docker_count
  docker_count=$(get_docker_count)
  local disk_info
  disk_info=$(get_disk_usage)
  local disk_pct
  disk_pct=$(get_disk_pct)
  local mem_info
  mem_info=$(get_memory)
  local uptime_info
  uptime_info=$(get_uptime)
  local last_backup
  last_backup=$(get_last_backup)

  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║                   SYSTEM INFORMATION                    ║${NC}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BLUE}║${NC} Docker containers running : $(printf '%-28s' "$docker_count") ${BLUE}║${NC}"

  if [[ "$disk_pct" -ge 80 ]] 2>/dev/null; then
    echo -e "${BLUE}║${NC} Data disk usage           : ${RED}$(printf '%-28s' "$disk_info")${NC} ${BLUE}║${NC}"
  else
    echo -e "${BLUE}║${NC} Data disk usage           : $(printf '%-28s' "$disk_info") ${BLUE}║${NC}"
  fi

  echo -e "${BLUE}║${NC} Memory                    : $(printf '%-28s' "$mem_info") ${BLUE}║${NC}"
  echo -e "${BLUE}║${NC} Uptime                    : $(printf '%-28s' "$uptime_info") ${BLUE}║${NC}"
  echo -e "${BLUE}║${NC} Last backup               : $(printf '%-28s' "${last_backup:0:28}") ${BLUE}║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
}

# ── JSON output ────────────────────────────────────────────────────────────────
print_json() {
  local up_count=0
  local total=${#STATUS_NAMES[@]}

  echo "{"
  echo "  \"timestamp\": \"$(date -Iseconds)\","
  echo "  \"services\": ["

  for i in "${!STATUS_NAMES[@]}"; do
    local comma=","
    [[ $i -eq $((total - 1)) ]] && comma=""
    local status="${STATUS_VALUES[$i]}"
    [[ "$status" == "UP" ]] && up_count=$((up_count + 1))
    echo "    {\"name\": \"${STATUS_NAMES[$i]}\", \"port\": ${STATUS_PORTS[$i]}, \"status\": \"$status\"}${comma}"
  done

  echo "  ],"
  echo "  \"summary\": {"
  echo "    \"up\": $up_count,"
  echo "    \"down\": $((total - up_count)),"
  echo "    \"total\": $total"
  echo "  },"
  echo "  \"system\": {"
  echo "    \"docker_containers\": \"$(get_docker_count)\","
  echo "    \"disk_usage\": \"$(get_disk_usage)\","
  echo "    \"memory\": \"$(get_memory)\","
  echo "    \"uptime\": \"$(get_uptime)\","
  echo "    \"last_backup\": \"$(get_last_backup)\""
  echo "  }"
  echo "}"
}

# ── Write log ──────────────────────────────────────────────────────────────────
write_log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo "=== Health Check — $timestamp ==="
    for i in "${!STATUS_NAMES[@]}"; do
      printf '%-20s %-6s %s\n' "${STATUS_NAMES[$i]}" "${STATUS_PORTS[$i]}" "${STATUS_VALUES[$i]}"
    done
    echo "Docker containers: $(get_docker_count)"
    echo "Disk: $(get_disk_usage)"
    echo "Memory: $(get_memory)"
    echo "Uptime: $(get_uptime)"
    echo "Last backup: $(get_last_backup)"
    echo ""
  } >> "$LOG_FILE"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  log_info "Running infrastructure health check at $(date '+%Y-%m-%d %H:%M:%S') ..."
  echo ""

  gather_statuses

  if $JSON_OUTPUT; then
    print_json
  else
    print_table
    print_system_info
    echo ""
    log_info "Results logged to $LOG_FILE"
  fi

  write_log
}

main "$@"
