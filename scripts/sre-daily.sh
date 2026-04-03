#!/bin/bash
# sre-daily.sh — Checklist SRE quotidienne : disk, memory, services, certificats, backups
# Usage: sre-daily.sh [--json] [--slack-webhook URL] [--help]
set -euo pipefail

# ── Couleurs ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ── Chemins ────────────────────────────────────────────────────────────────────
INFRA_DIR="${HOME}/devops-infra"
LOG_DIR="${INFRA_DIR}/logs"
BACKUP_DIR="${INFRA_DIR}/backups"
CERTS_DIR="${INFRA_DIR}/certs"
DATA_DIR="${INFRA_DIR}/data"
LOG_FILE="${LOG_DIR}/sre-daily.log"
REPORT_FILE="${LOG_DIR}/sre-daily-report-$(date '+%Y-%m-%d').txt"

# ── Seuils ─────────────────────────────────────────────────────────────────────
DISK_WARN_PCT="${DISK_WARN_PCT:-75}"
DISK_CRIT_PCT="${DISK_CRIT_PCT:-90}"
MEM_WARN_PCT="${MEM_WARN_PCT:-80}"
MEM_CRIT_PCT="${MEM_CRIT_PCT:-95}"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"
CERT_CRIT_DAYS="${CERT_CRIT_DAYS:-7}"
BACKUP_MAX_AGE_H="${BACKUP_MAX_AGE_H:-26}"   # Alerter si pas de backup depuis N heures

# ── Compteurs de resultats ─────────────────────────────────────────────────────
CHECKS_OK=0
CHECKS_WARN=0
CHECKS_CRIT=0
CHECKS_TOTAL=0

# ── Flags ──────────────────────────────────────────────────────────────────────
JSON_OUTPUT=false
SLACK_WEBHOOK=""

# ── Helpers ────────────────────────────────────────────────────────────────────
log_ok()   {
  CHECKS_OK=$((CHECKS_OK + 1)); CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  echo -e "  ${GREEN}[OK]${NC}   $*" | tee -a "$REPORT_FILE"
}
log_warn() {
  CHECKS_WARN=$((CHECKS_WARN + 1)); CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  echo -e "  ${YELLOW}[WARN]${NC} $*" | tee -a "$REPORT_FILE"
}
log_crit() {
  CHECKS_CRIT=$((CHECKS_CRIT + 1)); CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  echo -e "  ${RED}[CRIT]${NC} $*" | tee -a "$REPORT_FILE"
}
log_info() { echo -e "  ${BLUE}[INFO]${NC} $*" | tee -a "$REPORT_FILE"; }
section() {
  echo "" | tee -a "$REPORT_FILE"
  echo -e "${CYAN}${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Checklist SRE quotidienne — Verifie la sante de l'infrastructure DevOps.

Verifications effectuees :
  - Espace disque (seuils: warn ${DISK_WARN_PCT}%, crit ${DISK_CRIT_PCT}%)
  - Memoire (seuils: warn ${MEM_WARN_PCT}%, crit ${MEM_CRIT_PCT}%)
  - Services Docker (tous les conteneurs)
  - Ports des services critiques
  - Certificats SSL (warn < ${CERT_WARN_DAYS}j, crit < ${CERT_CRIT_DAYS}j)
  - Backups (alerter si rien depuis ${BACKUP_MAX_AGE_H}h)
  - Load average
  - Processus zombies
  - Connectivite reseau

Options:
  --json               Sortie en JSON
  --slack-webhook URL  Envoyer le rapport sur Slack
  --no-color           Desactiver les couleurs
  --help               Afficher cette aide

Exemples:
  $(basename "$0")
  $(basename "$0") --json
  $(basename "$0") --slack-webhook https://hooks.slack.com/services/xxx/yyy/zzz
EOF
  exit 0
}

# ── Parse args ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --json)          JSON_OUTPUT=true ;;
    --slack-webhook) shift; SLACK_WEBHOOK="$1" ;;
    --no-color)      RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; NC=''; BOLD='' ;;
    --help|-h)       usage ;;
    *) ;;
  esac
done

# ── Init ───────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "" > "$REPORT_FILE"
{
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║              RAPPORT SRE QUOTIDIEN — ${TIMESTAMP}  ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
} | tee -a "$REPORT_FILE"

# ══════════════════════════════════════════════════════════════════════════════
# 1. VERIFICATIONS DISQUE
# ══════════════════════════════════════════════════════════════════════════════
check_disk() {
  section "ESPACE DISQUE"

  # Verifier tous les points de montage significatifs
  while IFS= read -r line; do
    local filesystem pct mount
    filesystem=$(echo "$line" | awk '{print $1}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')

    # Ignorer les pseudo-systemes de fichiers
    [[ "$filesystem" =~ ^(tmpfs|devtmpfs|udev|overlay|shm)$ ]] && continue
    [[ "$mount" =~ ^(/dev|/sys|/proc|/run) ]] && continue

    local usage_human
    usage_human=$(echo "$line" | awk '{print $3"/"$2" ("$5")"}')

    if [[ "$pct" -ge "$DISK_CRIT_PCT" ]]; then
      log_crit "Disque ${mount} : ${usage_human} — CRITIQUE"
    elif [[ "$pct" -ge "$DISK_WARN_PCT" ]]; then
      log_warn "Disque ${mount} : ${usage_human} — attention"
    else
      log_ok   "Disque ${mount} : ${usage_human}"
    fi
  done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

  # Verifier le repertoire data specifiquement
  if [[ -d "$DATA_DIR" ]]; then
    local data_size
    data_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1 || echo "inconnu")
    log_info "Taille du repertoire data ($DATA_DIR) : $data_size"
  fi

  # Verifier les iNodes
  local inode_pct
  inode_pct=$(df -i / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || echo "0")
  if [[ "$inode_pct" -ge 90 ]]; then
    log_crit "iNodes / : ${inode_pct}% utilises — CRITIQUE"
  elif [[ "$inode_pct" -ge 75 ]]; then
    log_warn "iNodes / : ${inode_pct}% utilises"
  else
    log_ok   "iNodes / : ${inode_pct}% utilises"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. MEMOIRE
# ══════════════════════════════════════════════════════════════════════════════
check_memory() {
  section "MEMOIRE RAM ET SWAP"

  # RAM
  local total_kb used_kb free_kb available_kb
  total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  used_kb=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print t-a}' /proc/meminfo)
  available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  local mem_pct=$(( used_kb * 100 / total_kb ))
  local total_gb=$(( total_kb / 1024 / 1024 ))
  local used_gb_x10=$(( used_kb * 10 / 1024 / 1024 ))
  local used_gb="${used_gb_x10:0:-1}.${used_gb_x10: -1}"

  if [[ "$mem_pct" -ge "$MEM_CRIT_PCT" ]]; then
    log_crit "RAM : ${used_gb}GB / ${total_gb}GB (${mem_pct}%) — CRITIQUE"
  elif [[ "$mem_pct" -ge "$MEM_WARN_PCT" ]]; then
    log_warn "RAM : ${used_gb}GB / ${total_gb}GB (${mem_pct}%) — attention"
  else
    log_ok   "RAM : ${used_gb}GB / ${total_gb}GB (${mem_pct}%)"
  fi

  # SWAP
  local swap_total swap_used swap_pct
  swap_total=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  swap_used=$(awk '/^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2} END {print t-f}' /proc/meminfo)

  if [[ "$swap_total" -eq 0 ]]; then
    log_info "Swap : non configure"
  else
    swap_pct=$(( swap_used * 100 / swap_total ))
    local swap_total_mb=$(( swap_total / 1024 ))
    local swap_used_mb=$(( swap_used / 1024 ))
    if [[ "$swap_pct" -ge 80 ]]; then
      log_warn "Swap : ${swap_used_mb}MB / ${swap_total_mb}MB (${swap_pct}%) — utilisation elevee"
    else
      log_ok   "Swap : ${swap_used_mb}MB / ${swap_total_mb}MB (${swap_pct}%)"
    fi
  fi

  # Top 5 processus par consommation memoire
  log_info "Top 5 processus par memoire :"
  ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | \
    awk '{printf "    %-20s  %5s%%  %s\n", $11, $4, $1}' | \
    tee -a "$REPORT_FILE"
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. LOAD AVERAGE ET CPU
# ══════════════════════════════════════════════════════════════════════════════
check_load() {
  section "LOAD AVERAGE ET CPU"

  local ncpus
  ncpus=$(nproc 2>/dev/null || echo 1)
  local load1 load5 load15
  read -r load1 load5 load15 _ < /proc/loadavg

  local load1_int
  load1_int=$(echo "$load1" | cut -d. -f1)
  local threshold_warn=$ncpus
  local threshold_crit=$((ncpus * 2))

  if [[ "$load1_int" -ge "$threshold_crit" ]]; then
    log_crit "Load average : ${load1} ${load5} ${load15} (CPU: $ncpus) — CRITIQUE"
  elif [[ "$load1_int" -ge "$threshold_warn" ]]; then
    log_warn "Load average : ${load1} ${load5} ${load15} (CPU: $ncpus) — eleve"
  else
    log_ok   "Load average : ${load1} ${load5} ${load15} (CPU: $ncpus)"
  fi

  # Uptime
  local uptime_str
  uptime_str=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "inconnu")
  log_info "Uptime : $uptime_str"

  # Zombies
  local zombie_count
  zombie_count=$(ps aux 2>/dev/null | awk '$8=="Z"' | wc -l)
  if [[ "$zombie_count" -gt 10 ]]; then
    log_warn "Processus zombies : $zombie_count (>10)"
  else
    log_ok   "Processus zombies : $zombie_count"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. SERVICES DOCKER
# ══════════════════════════════════════════════════════════════════════════════
check_docker_services() {
  section "CONTENEURS DOCKER"

  if ! command -v docker &>/dev/null; then
    log_warn "Docker non installe ou non disponible"
    return
  fi

  if ! docker info &>/dev/null 2>&1; then
    log_crit "Docker daemon inaccessible"
    return
  fi

  local total running exited
  total=$(docker ps -a --format '{{.Names}}' 2>/dev/null | wc -l)
  running=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
  exited=$(docker ps -a --filter "status=exited" --format '{{.Names}}' 2>/dev/null | wc -l)
  local restarting
  restarting=$(docker ps -a --filter "status=restarting" --format '{{.Names}}' 2>/dev/null | wc -l)

  log_ok "Docker daemon : actif"
  log_info "Conteneurs — Total: $total | Running: $running | Exited: $exited | Restarting: $restarting"

  # Lister les conteneurs en erreur
  if [[ "$exited" -gt 0 ]]; then
    log_warn "Conteneurs arretes ($exited) :"
    docker ps -a --filter "status=exited" --format '  {{.Names}} ({{.Status}})' 2>/dev/null | \
      tee -a "$REPORT_FILE"
  fi

  if [[ "$restarting" -gt 0 ]]; then
    log_crit "Conteneurs en restart loop ($restarting) :"
    docker ps -a --filter "status=restarting" --format '  {{.Names}} ({{.Status}})' 2>/dev/null | \
      tee -a "$REPORT_FILE"
  fi

  # Healthcheck status
  local unhealthy
  unhealthy=$(docker ps --filter "health=unhealthy" --format '{{.Names}}' 2>/dev/null | wc -l)
  if [[ "$unhealthy" -gt 0 ]]; then
    log_crit "Conteneurs unhealthy ($unhealthy) :"
    docker ps --filter "health=unhealthy" --format '  {{.Names}}' 2>/dev/null | tee -a "$REPORT_FILE"
  else
    log_ok "Aucun conteneur unhealthy"
  fi

  # Usage ressources Docker
  if [[ "$running" -gt 0 ]]; then
    log_info "Usage ressources des conteneurs :"
    docker stats --no-stream --format \
      "  {{printf \"%-20s\" .Name}} CPU: {{printf \"%-8s\" .CPUPerc}} MEM: {{.MemUsage}}" \
      2>/dev/null | head -15 | tee -a "$REPORT_FILE"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. PORTS DES SERVICES CRITIQUES
# ══════════════════════════════════════════════════════════════════════════════
check_ports() {
  section "SERVICES ET PORTS CRITIQUES"

  # Services critiques a verifier
  declare -A CRITICAL_SERVICES=(
    ["Prometheus"]="9090"
    ["Grafana"]="3000"
    ["AlertManager"]="9093"
    ["PostgreSQL"]="5432"
    ["Redis"]="6379"
    ["Node-Exporter"]="9100"
  )

  declare -A OPTIONAL_SERVICES=(
    ["Jenkins"]="8081"
    ["Gitea"]="3001"
    ["Vault"]="8200"
    ["Consul"]="8500"
    ["Kafka"]="9092"
    ["Elasticsearch"]="9200"
    ["Kibana"]="5601"
    ["MinIO"]="9001"
    ["Traefik"]="8080"
    ["SonarQube"]="9000"
    ["Loki"]="3100"
    ["ArgoCD"]="8083"
  )

  log_info "Services critiques :"
  for service in "${!CRITICAL_SERVICES[@]}"; do
    local port="${CRITICAL_SERVICES[$service]}"
    if nc -z localhost "$port" 2>/dev/null; then
      log_ok "$service (port $port) : UP"
    else
      log_crit "$service (port $port) : DOWN"
    fi
  done

  log_info "Services optionnels :"
  for service in "${!OPTIONAL_SERVICES[@]}"; do
    local port="${OPTIONAL_SERVICES[$service]}"
    if nc -z localhost "$port" 2>/dev/null; then
      log_ok "$service (port $port) : UP"
    else
      log_info "$service (port $port) : non actif"
    fi
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. CERTIFICATS SSL
# ══════════════════════════════════════════════════════════════════════════════
check_certificates() {
  section "CERTIFICATS SSL"

  local cert_found=false

  # Verifier les certificats dans le repertoire certs
  if [[ -d "$CERTS_DIR" ]]; then
    while IFS= read -r cert_file; do
      cert_found=true
      local cert_name
      cert_name=$(basename "$cert_file" .crt)
      local expiry days_left

      expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || echo "")
      if [[ -z "$expiry" ]]; then
        log_warn "Certificat $cert_name : impossible de lire la date d'expiration"
        continue
      fi

      days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))

      if [[ "$days_left" -le 0 ]]; then
        log_crit "Certificat $cert_name : EXPIRE (${expiry})"
      elif [[ "$days_left" -le "$CERT_CRIT_DAYS" ]]; then
        log_crit "Certificat $cert_name : expire dans ${days_left}j — CRITIQUE"
      elif [[ "$days_left" -le "$CERT_WARN_DAYS" ]]; then
        log_warn "Certificat $cert_name : expire dans ${days_left}j — renouveler bientot"
      else
        log_ok   "Certificat $cert_name : valide encore ${days_left}j (${expiry})"
      fi
    done < <(find "$CERTS_DIR" -name "*.crt" -not -path "*/ca/*" 2>/dev/null | sort)
  fi

  # Verifier les endpoints HTTPS locaux
  declare -a HTTPS_ENDPOINTS=(
    "localhost:9443"   # Portainer
    "localhost:8200"   # Vault
  )

  log_info "Verification des endpoints HTTPS :"
  for endpoint in "${HTTPS_ENDPOINTS[@]}"; do
    if timeout 5 openssl s_client -connect "$endpoint" \
        -servername "${endpoint%%:*}" </dev/null 2>/dev/null | \
        openssl x509 -noout -dates 2>/dev/null; then
      local expiry_line
      expiry_line=$(timeout 5 openssl s_client -connect "$endpoint" \
        -servername "${endpoint%%:*}" </dev/null 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
      if [[ -n "$expiry_line" ]]; then
        local days_left=$(( ($(date -d "$expiry_line" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
        log_ok "$endpoint : TLS valide, expire dans ${days_left}j"
      fi
    fi
  done

  if ! $cert_found; then
    log_info "Aucun certificat trouve dans $CERTS_DIR"
    log_info "Generer avec : ~/devops-infra/scripts/generate-certs.sh --all"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. BACKUPS
# ══════════════════════════════════════════════════════════════════════════════
check_backups() {
  section "SAUVEGARDES"

  if [[ ! -d "$BACKUP_DIR" ]]; then
    log_warn "Repertoire de backup inexistant : $BACKUP_DIR"
    return
  fi

  local max_age_secs=$(( BACKUP_MAX_AGE_H * 3600 ))
  local now_secs
  now_secs=$(date +%s)

  for service in postgres redis files; do
    local bk_dir="${BACKUP_DIR}/${service}"
    if [[ ! -d "$bk_dir" ]]; then
      log_warn "$service : repertoire de backup manquant ($bk_dir)"
      continue
    fi

    # Trouver le fichier le plus recent
    local latest_file
    latest_file=$(find "$bk_dir" -type f \( -name "*.gz" -o -name "*.rdb" -o -name "*.tar.gz" -o -name "*.sql" \) \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}' || echo "")

    if [[ -z "$latest_file" ]]; then
      log_crit "$service : aucun backup trouve dans $bk_dir"
      continue
    fi

    local file_mtime
    file_mtime=$(stat -c %Y "$latest_file" 2>/dev/null || echo 0)
    local age_secs=$(( now_secs - file_mtime ))
    local age_h=$(( age_secs / 3600 ))
    local file_size
    file_size=$(du -sh "$latest_file" 2>/dev/null | cut -f1 || echo "?")

    if [[ "$age_secs" -gt "$max_age_secs" ]]; then
      log_crit "$service : dernier backup il y a ${age_h}h (>${BACKUP_MAX_AGE_H}h) — $latest_file ($file_size)"
    elif [[ "$age_secs" -gt $(( max_age_secs / 2 )) ]]; then
      log_warn "$service : dernier backup il y a ${age_h}h — $latest_file ($file_size)"
    else
      log_ok   "$service : backup OK il y a ${age_h}h — $(basename "$latest_file") ($file_size)"
    fi
  done

  # Taille totale des backups
  local total_size
  total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "inconnu")
  log_info "Taille totale des backups : $total_size"
}

# ══════════════════════════════════════════════════════════════════════════════
# 8. CONNECTIVITE RESEAU
# ══════════════════════════════════════════════════════════════════════════════
check_network() {
  section "CONNECTIVITE RESEAU"

  # Ping gateway
  local gateway
  gateway=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}' || echo "")
  if [[ -n "$gateway" ]]; then
    if ping -c 1 -W 2 "$gateway" &>/dev/null; then
      log_ok "Gateway ($gateway) : accessible"
    else
      log_crit "Gateway ($gateway) : inaccessible"
    fi
  else
    log_warn "Impossible de determiner la gateway"
  fi

  # DNS
  if nslookup google.com &>/dev/null 2>&1; then
    log_ok "Resolution DNS : OK"
  elif dig @8.8.8.8 google.com &>/dev/null 2>&1; then
    log_warn "DNS local en echec mais 8.8.8.8 accessible"
  else
    log_crit "Resolution DNS : ECHEC"
  fi

  # Connectivite internet (optionnel)
  if curl -s --connect-timeout 5 https://google.com &>/dev/null; then
    log_ok "Connectivite HTTPS externe : OK"
  else
    log_warn "Connectivite HTTPS externe : non disponible"
  fi

  # Docker network
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    local networks
    networks=$(docker network ls --format '{{.Name}}' 2>/dev/null | wc -l)
    log_ok "Reseaux Docker : $networks reseaux configures"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 9. LOGS RECENTS
# ══════════════════════════════════════════════════════════════════════════════
check_logs() {
  section "LOGS SYSTEME (ERREURS RECENTES)"

  # Erreurs kernel recentes
  local kernel_errors
  kernel_errors=$(dmesg --level=err,crit,emerg 2>/dev/null | tail -3 | wc -l || echo 0)
  if [[ "$kernel_errors" -gt 0 ]]; then
    log_warn "Erreurs kernel recentes ($kernel_errors lignes) :"
    dmesg --level=err,crit,emerg 2>/dev/null | tail -3 | sed 's/^/    /' | tee -a "$REPORT_FILE"
  else
    log_ok "Aucune erreur kernel critique recente"
  fi

  # Verifier les logs des services Docker en erreur
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    local failed_containers
    failed_containers=$(docker ps -a --filter "status=exited" \
      --filter "exited=1" --format '{{.Names}}' 2>/dev/null | head -3)
    if [[ -n "$failed_containers" ]]; then
      log_warn "Derniers logs des conteneurs en echec :"
      for container in $failed_containers; do
        echo "  --- $container ---" | tee -a "$REPORT_FILE"
        docker logs --tail=3 "$container" 2>&1 | sed 's/^/    /' | tee -a "$REPORT_FILE" || true
      done
    fi
  fi

  # Verifier les logs d'infra DevOps
  if [[ -f "${LOG_DIR}/health-check.log" ]]; then
    local last_check
    last_check=$(tail -1 "${LOG_DIR}/health-check.log" 2>/dev/null | head -c 60 || echo "inconnu")
    log_info "Dernier health-check : $last_check"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# RAPPORT FINAL
# ══════════════════════════════════════════════════════════════════════════════
print_summary() {
  section "RESUME DE LA CHECKLIST SRE"

  local overall_status
  if [[ "$CHECKS_CRIT" -gt 0 ]]; then
    overall_status="${RED}CRITIQUE${NC}"
  elif [[ "$CHECKS_WARN" -gt 0 ]]; then
    overall_status="${YELLOW}ATTENTION${NC}"
  else
    overall_status="${GREEN}OK${NC}"
  fi

  echo "" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════╗${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║              BILAN QUOTIDIEN SRE                 ║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}╠═══════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  Statut global : ${overall_status}                          ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  Total verifications : ${CHECKS_TOTAL}                         ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  ${GREEN}OK${NC}       : ${CHECKS_OK}                                   ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  ${YELLOW}WARN${NC}     : ${CHECKS_WARN}                                   ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  ${RED}CRITIQUE${NC} : ${CHECKS_CRIT}                                   ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}║${NC}  Date     : ${TIMESTAMP}      ${BLUE}║${NC}" | tee -a "$REPORT_FILE"
  echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════╝${NC}" | tee -a "$REPORT_FILE"
  echo "" | tee -a "$REPORT_FILE"

  echo -e "  Rapport complet : ${CYAN}${REPORT_FILE}${NC}"
  echo -e "  Log persistant  : ${CYAN}${LOG_FILE}${NC}"

  # Ajouter au log persistant
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK:${CHECKS_OK} WARN:${CHECKS_WARN} CRIT:${CHECKS_CRIT} TOTAL:${CHECKS_TOTAL}" >> "$LOG_FILE"
}

# ── Envoi Slack (optionnel) ────────────────────────────────────────────────────
send_slack() {
  [[ -z "$SLACK_WEBHOOK" ]] && return

  local status_emoji
  if [[ "$CHECKS_CRIT" -gt 0 ]]; then
    status_emoji=":red_circle:"
  elif [[ "$CHECKS_WARN" -gt 0 ]]; then
    status_emoji=":large_yellow_circle:"
  else
    status_emoji=":large_green_circle:"
  fi

  local payload
  payload=$(cat <<JSON
{
  "text": "${status_emoji} *Rapport SRE Quotidien — $(date '+%Y-%m-%d')*",
  "attachments": [
    {
      "color": "$([ $CHECKS_CRIT -gt 0 ] && echo 'danger' || ([ $CHECKS_WARN -gt 0 ] && echo 'warning' || echo 'good'))",
      "fields": [
        {"title": "OK", "value": "${CHECKS_OK}", "short": true},
        {"title": "WARN", "value": "${CHECKS_WARN}", "short": true},
        {"title": "CRITIQUE", "value": "${CHECKS_CRIT}", "short": true},
        {"title": "Total", "value": "${CHECKS_TOTAL}", "short": true}
      ],
      "footer": "DevOps Lab SRE | $(hostname)"
    }
  ]
}
JSON
)

  if curl -s -X POST -H 'Content-type: application/json' \
      --data "$payload" "$SLACK_WEBHOOK" &>/dev/null; then
    log_info "Rapport envoye sur Slack"
  else
    log_warn "Echec de l'envoi Slack"
  fi
}

# ── JSON output ────────────────────────────────────────────────────────────────
print_json() {
  cat <<JSON
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "summary": {
    "ok": ${CHECKS_OK},
    "warn": ${CHECKS_WARN},
    "critical": ${CHECKS_CRIT},
    "total": ${CHECKS_TOTAL},
    "status": "$([ $CHECKS_CRIT -gt 0 ] && echo 'CRITICAL' || ([ $CHECKS_WARN -gt 0 ] && echo 'WARNING' || echo 'OK'))"
  },
  "report_file": "${REPORT_FILE}"
}
JSON
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}${MAGENTA}SRE Daily Checklist — $(date '+%A %d %B %Y %H:%M')${NC}"
  echo ""

  # Executer toutes les verifications
  check_disk
  check_memory
  check_load
  check_docker_services
  check_ports
  check_certificates
  check_backups
  check_network
  check_logs
  print_summary
  send_slack

  if $JSON_OUTPUT; then
    print_json
  fi

  # Code de retour selon la severite
  if [[ "$CHECKS_CRIT" -gt 0 ]]; then
    exit 2
  elif [[ "$CHECKS_WARN" -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
