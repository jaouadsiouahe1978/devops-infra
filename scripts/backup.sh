#!/usr/bin/env bash
# backup.sh — DevOps infrastructure backup utility
# Usage: backup.sh [--service=<name>] [--verify] [--list] [--cleanup] [--help]
set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Paths ──────────────────────────────────────────────────────────────────────
BACKUP_DIR="$HOME/devops-infra/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="$HOME/devops-infra/logs/backup.log"

# ── Flags ──────────────────────────────────────────────────────────────────────
SERVICE="all"
DO_VERIFY=false
DO_LIST=false
DO_CLEANUP=false

# ── Logging helpers ────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" >> "$LOG"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $*" >> "$LOG"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >> "$LOG"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$LOG"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Backup DevOps infrastructure data and configurations.

Options:
  --service=NAME   Service to backup: all|postgres|mysql|redis|mongodb|configs|k8s|vault
                   (default: all)
  --verify         Verify integrity of backup files after creation
  --list           List existing backup files with sizes and dates
  --cleanup        Remove backup files older than 30 days
  --help           Show this help message

Examples:
  $(basename "$0") --service=all
  $(basename "$0") --service=postgres
  $(basename "$0") --verify
  $(basename "$0") --list
  $(basename "$0") --cleanup
EOF
  exit 0
}

# ── Parse args ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --service=*) SERVICE="${arg#*=}" ;;
    --verify)    DO_VERIFY=true ;;
    --list)      DO_LIST=true ;;
    --cleanup)   DO_CLEANUP=true ;;
    --help)      usage ;;
    *) log_error "Unknown argument: $arg"; usage ;;
  esac
done

# ── Ensure directories ─────────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"/{postgres,mysql,redis,mongodb,configs,k8s,vault} \
         "$(dirname "$LOG")"

# ── Summary tracking ───────────────────────────────────────────────────────────
declare -a SUMMARY_NAMES=()
declare -a SUMMARY_STATUS=()
declare -a SUMMARY_SIZES=()
declare -a SUMMARY_TIMES=()

record_result() {
  local name="$1" status="$2" file="${3:-}" start="$4" end="$5"
  local size="N/A"
  if [[ -f "$file" ]]; then
    size=$(du -sh "$file" 2>/dev/null | awk '{print $1}')
  fi
  local elapsed=$(( end - start ))
  SUMMARY_NAMES+=("$name")
  SUMMARY_STATUS+=("$status")
  SUMMARY_SIZES+=("$size")
  SUMMARY_TIMES+=("${elapsed}s")
}

# ── Container running check ────────────────────────────────────────────────────
container_running() {
  local name="$1"
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"
}

# ── Individual backup functions ────────────────────────────────────────────────
backup_postgres() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/postgres/postgres_${TIMESTAMP}.sql.gz"
  log_info "Starting PostgreSQL backup..."

  if ! container_running "postgres"; then
    log_warn "Container 'postgres' is not running — skipping PostgreSQL backup"
    record_result "postgres" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  if docker exec postgres pg_dumpall -U devops 2>/dev/null | gzip > "$outfile"; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "PostgreSQL backup completed: $outfile ($size)"
    record_result "postgres" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "PostgreSQL backup failed"
    record_result "postgres" "FAILED" "" "$start" "$SECONDS"
  fi
}

backup_mysql() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/mysql/mysql_${TIMESTAMP}.sql.gz"
  log_info "Starting MySQL backup..."

  if ! container_running "mysql"; then
    log_warn "Container 'mysql' is not running — skipping MySQL backup"
    record_result "mysql" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  if docker exec mysql mysqldump --all-databases -u root -pDevOps2024\!Root 2>/dev/null | gzip > "$outfile"; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "MySQL backup completed: $outfile ($size)"
    record_result "mysql" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "MySQL backup failed"
    record_result "mysql" "FAILED" "" "$start" "$SECONDS"
  fi
}

backup_redis() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/redis/redis_${TIMESTAMP}.rdb"
  log_info "Starting Redis backup..."

  if ! container_running "redis"; then
    log_warn "Container 'redis' is not running — skipping Redis backup"
    record_result "redis" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  docker exec redis redis-cli -a DevOps2024\!Redis BGSAVE 2>/dev/null || true
  sleep 2

  if docker cp redis:/data/dump.rdb "$outfile" 2>/dev/null; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "Redis backup completed: $outfile ($size)"
    record_result "redis" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "Redis backup failed (could not copy dump.rdb)"
    record_result "redis" "FAILED" "" "$start" "$SECONDS"
  fi
}

backup_mongodb() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/mongodb/mongo_${TIMESTAMP}.gz"
  log_info "Starting MongoDB backup..."

  if ! container_running "mongodb"; then
    log_warn "Container 'mongodb' is not running — skipping MongoDB backup"
    record_result "mongodb" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  if docker exec mongodb mongodump --archive 2>/dev/null | gzip > "$outfile"; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "MongoDB backup completed: $outfile ($size)"
    record_result "mongodb" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "MongoDB backup failed"
    record_result "mongodb" "FAILED" "" "$start" "$SECONDS"
  fi
}

backup_configs() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/configs/configs_${TIMESTAMP}.tar.gz"
  log_info "Starting configs backup..."

  tar czf "$outfile" \
    -C "$HOME" \
    --ignore-failed-read \
    --exclude='*/data/*' \
    --exclude='*/backups/*' \
    --exclude='*/logs/*' \
    devops-infra/ansible \
    devops-infra/monitoring \
    devops-infra/kubernetes \
    devops-infra/terraform \
    devops-infra/docker \
    devops-infra/scripts \
    2>/dev/null || true

  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "Configs backup completed: $outfile ($size)"
    record_result "configs" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_warn "Configs backup produced an empty or missing file (some source dirs may not exist)"
    record_result "configs" "PARTIAL" "$outfile" "$start" "$SECONDS"
  fi
}

backup_k8s() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/k8s/k8s_${TIMESTAMP}.yaml.gz"
  log_info "Starting Kubernetes backup..."

  if ! command -v kubectl &>/dev/null; then
    log_warn "kubectl not available — skipping Kubernetes backup"
    record_result "k8s" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  if kubectl get all --all-namespaces -o yaml 2>/dev/null | gzip > "$outfile"; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "Kubernetes backup completed: $outfile ($size)"
    record_result "k8s" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "Kubernetes backup failed"
    record_result "k8s" "FAILED" "" "$start" "$SECONDS"
  fi
}

backup_vault() {
  local start=$SECONDS
  local outfile="$BACKUP_DIR/vault/vault_${TIMESTAMP}.snap"
  log_info "Starting Vault backup..."

  if ! container_running "vault"; then
    log_warn "Container 'vault' is not running — skipping Vault backup"
    record_result "vault" "SKIPPED" "" "$start" "$SECONDS"
    return 0
  fi

  if docker exec vault vault operator raft snapshot save /tmp/vault.snap 2>/dev/null && \
     docker cp vault:/tmp/vault.snap "$outfile" 2>/dev/null; then
    local size
    size=$(du -sh "$outfile" 2>/dev/null | awk '{print $1}')
    log_success "Vault backup completed: $outfile ($size)"
    record_result "vault" "SUCCESS" "$outfile" "$start" "$SECONDS"
  else
    log_error "Vault backup failed"
    record_result "vault" "FAILED" "" "$start" "$SECONDS"
  fi
}

# ── Verify backups ─────────────────────────────────────────────────────────────
verify_backups() {
  log_info "Verifying backup integrity..."
  local pass=0 fail=0

  for dir in "$BACKUP_DIR"/*/; do
    local service
    service=$(basename "$dir")
    local newest
    newest=$(find "$dir" -type f \( -name "*.gz" -o -name "*.rdb" -o -name "*.snap" \) \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')

    if [[ -z "$newest" ]]; then
      log_warn "No backup files found for: $service"
      continue
    fi

    if [[ ! -s "$newest" ]]; then
      log_error "$service: newest backup is empty — $newest"
      fail=$((fail + 1))
      continue
    fi

    if [[ "$newest" == *.gz ]]; then
      if gzip -t "$newest" 2>/dev/null; then
        log_success "$service: OK — $newest"
        pass=$((pass + 1))
      else
        log_error "$service: gzip integrity check FAILED — $newest"
        fail=$((fail + 1))
      fi
    else
      log_success "$service: OK (non-gz) — $newest"
      pass=$((pass + 1))
    fi
  done

  echo ""
  echo -e "  Verify results: ${GREEN}${pass} passed${NC}  ${RED}${fail} failed${NC}"
}

# ── List backups ───────────────────────────────────────────────────────────────
list_backups() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║                        BACKUP INVENTORY                             ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"

  for dir in "$BACKUP_DIR"/*/; do
    local service
    service=$(basename "$dir")
    echo ""
    echo -e "  ${YELLOW}[${service^^}]${NC}"

    local files
    files=$(find "$dir" -type f \( -name "*.gz" -o -name "*.rdb" -o -name "*.snap" \) \
      -printf '%T@ %TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | sort -rn)

    if [[ -z "$files" ]]; then
      echo "    (no backups)"
    else
      while IFS= read -r line; do
        local ts date time bytes path
        read -r ts date time bytes path <<< "$line"
        local size
        size=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")
        printf '    %-12s %-8s  %s\n' "$date $time" "$size" "$(basename "$path")"
      done <<< "$files"
    fi
  done
  echo ""
}

# ── Cleanup old backups ────────────────────────────────────────────────────────
cleanup_old() {
  log_info "Cleaning up backup files older than 30 days..."
  local count=0

  while IFS= read -r -d '' f; do
    log_info "Removing: $f"
    rm -f "$f"
    count=$((count + 1))
  done < <(find "$BACKUP_DIR" \( -name "*.gz" -o -name "*.rdb" -o -name "*.snap" \) -mtime +30 -print0 2>/dev/null)

  log_success "Cleanup complete — removed $count file(s)"
}

# ── Print summary table ────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║                    BACKUP SUMMARY                       ║${NC}"
  echo -e "${BLUE}╠══════════════╦════════════╦══════════╦═══════════════════╣${NC}"
  echo -e "${BLUE}║${NC} $(printf '%-12s' 'SERVICE')   ${BLUE}║${NC} $(printf '%-10s' 'STATUS')   ${BLUE}║${NC} $(printf '%-8s' 'SIZE')   ${BLUE}║${NC} $(printf '%-17s' 'DURATION')   ${BLUE}║${NC}"
  echo -e "${BLUE}╠══════════════╬════════════╬══════════╬═══════════════════╣${NC}"

  for i in "${!SUMMARY_NAMES[@]}"; do
    local status="${SUMMARY_STATUS[$i]}"
    local colour="${NC}"
    case "$status" in
      SUCCESS) colour="${GREEN}" ;;
      FAILED)  colour="${RED}" ;;
      SKIPPED|PARTIAL) colour="${YELLOW}" ;;
    esac
    echo -e "${BLUE}║${NC} $(printf '%-12s' "${SUMMARY_NAMES[$i]}")   ${BLUE}║${NC} ${colour}$(printf '%-10s' "$status")${NC}   ${BLUE}║${NC} $(printf '%-8s' "${SUMMARY_SIZES[$i]}")   ${BLUE}║${NC} $(printf '%-17s' "${SUMMARY_TIMES[$i]}")   ${BLUE}║${NC}"
  done

  echo -e "${BLUE}╚══════════════╩════════════╩══════════╩═══════════════════╝${NC}"
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  mkdir -p "$(dirname "$LOG")"

  if $DO_LIST; then
    list_backups
    exit 0
  fi

  if $DO_CLEANUP; then
    cleanup_old
    exit 0
  fi

  log_info "Backup started at $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  case "$SERVICE" in
    all)
      backup_postgres
      backup_mysql
      backup_redis
      backup_mongodb
      backup_configs
      backup_k8s
      backup_vault
      ;;
    postgres)  backup_postgres ;;
    mysql)     backup_mysql ;;
    redis)     backup_redis ;;
    mongodb)   backup_mongodb ;;
    configs)   backup_configs ;;
    k8s)       backup_k8s ;;
    vault)     backup_vault ;;
    *)
      log_error "Unknown service: $SERVICE"
      usage
      ;;
  esac

  if $DO_VERIFY; then
    echo ""
    verify_backups
  fi

  print_summary
  log_info "Backup session complete."
}

main "$@"
