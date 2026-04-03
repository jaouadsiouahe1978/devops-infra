#!/bin/bash
# restore.sh — Script de restauration des backups (PostgreSQL, Redis, fichiers)
# Usage: restore.sh [--service SERVICE] [--file BACKUP_FILE] [--list] [--help]
set -euo pipefail

# ── Couleurs ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Chemins ────────────────────────────────────────────────────────────────────
INFRA_DIR="${HOME}/devops-infra"
BACKUP_DIR="${INFRA_DIR}/backups"
LOG_DIR="${INFRA_DIR}/logs"
LOG_FILE="${LOG_DIR}/restore.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# ── Variables de connexion (surchargeables via env) ────────────────────────────
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-devops}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-DevOps2024!}"
POSTGRES_DB="${POSTGRES_DB:-devopsdb}"

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-DevOps2024!Redis}"

# ── Helpers de log ─────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
log_step()    { echo -e "\n${CYAN}>>> $*${NC}" | tee -a "$LOG_FILE"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Script de restauration des sauvegardes pour l'infrastructure DevOps/SRE.

Options:
  --service SERVICE   Service a restaurer : postgres | redis | files | all
  --file FILE         Fichier de backup specifique a restaurer
  --list              Lister les backups disponibles
  --dry-run           Simuler la restauration sans l'executer
  --help              Afficher cette aide

Services supportes:
  postgres   Restauration d'une base de donnees PostgreSQL
  redis      Restauration d'un dump Redis (RDB)
  files      Restauration d'une archive de fichiers (tar.gz)
  all        Restaurer le dernier backup de chaque service

Exemples:
  $(basename "$0") --list
  $(basename "$0") --service postgres
  $(basename "$0") --service postgres --file backups/postgres/devopsdb_2024-01-01_12-00-00.sql.gz
  $(basename "$0") --service redis --file backups/redis/dump_2024-01-01_12-00-00.rdb
  $(basename "$0") --service files --file backups/files/data_2024-01-01_12-00-00.tar.gz
  $(basename "$0") --service all
  $(basename "$0") --service postgres --dry-run
EOF
  exit 0
}

# ── Parse arguments ────────────────────────────────────────────────────────────
SERVICE=""
BACKUP_FILE=""
DRY_RUN=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)  SERVICE="$2";      shift 2 ;;
    --file)     BACKUP_FILE="$2";  shift 2 ;;
    --dry-run)  DRY_RUN=true;      shift ;;
    --list)     LIST_ONLY=true;    shift ;;
    --help)     usage ;;
    *) log_error "Argument inconnu: $1"; usage ;;
  esac
done

# ── Init ───────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR" "$BACKUP_DIR"/{postgres,redis,files}
echo "=== Restauration demarree le $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"

# ── Lister les backups disponibles ────────────────────────────────────────────
list_backups() {
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║              BACKUPS DISPONIBLES                        ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"

  for service in postgres redis files; do
    local dir="${BACKUP_DIR}/${service}"
    echo -e "\n${CYAN}--- ${service^^} ---${NC}"
    if ls "${dir}"/* &>/dev/null 2>&1; then
      ls -lht "${dir}"/* 2>/dev/null | awk '{print $6, $7, $8, $9, "("$5")"}'
    else
      echo "  Aucun backup trouve dans ${dir}"
    fi
  done
  echo ""
}

# ── Trouver le dernier backup d'un service ─────────────────────────────────────
find_latest_backup() {
  local service="$1"
  local dir="${BACKUP_DIR}/${service}"
  local latest=""

  case "$service" in
    postgres) latest=$(ls -t "${dir}"/*.sql.gz "${dir}"/*.sql 2>/dev/null | head -1 || true) ;;
    redis)    latest=$(ls -t "${dir}"/*.rdb 2>/dev/null | head -1 || true) ;;
    files)    latest=$(ls -t "${dir}"/*.tar.gz 2>/dev/null | head -1 || true) ;;
  esac

  echo "$latest"
}

# ── Verification de prerequis ─────────────────────────────────────────────────
check_prereqs() {
  local missing=()
  command -v docker   &>/dev/null || missing+=("docker")
  command -v psql     &>/dev/null || command -v docker &>/dev/null || missing+=("psql ou docker")
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Outils manquants (seront utilises via Docker si disponible): ${missing[*]}"
  fi
}

# ── Confirmation utilisateur ───────────────────────────────────────────────────
confirm_restore() {
  local service="$1"
  local file="$2"
  echo -e "\n${YELLOW}[ATTENTION]${NC} Vous allez restaurer :"
  echo -e "  Service : ${CYAN}${service}${NC}"
  echo -e "  Fichier : ${CYAN}${file}${NC}"
  echo -e "${RED}Cette operation peut ecraser les donnees actuelles !${NC}\n"
  read -rp "Continuer ? [oui/non] : " confirm
  [[ "$confirm" =~ ^(oui|yes|o|y)$ ]]
}

# ── Restauration PostgreSQL ────────────────────────────────────────────────────
restore_postgres() {
  local backup_file="${1:-}"

  log_step "Restauration PostgreSQL"

  # Trouver le backup si non specifie
  if [[ -z "$backup_file" ]]; then
    backup_file=$(find_latest_backup postgres)
    if [[ -z "$backup_file" ]]; then
      log_error "Aucun backup PostgreSQL trouve dans ${BACKUP_DIR}/postgres/"
      return 1
    fi
    log_info "Backup le plus recent trouve : $backup_file"
  fi

  [[ -f "$backup_file" ]] || { log_error "Fichier introuvable : $backup_file"; return 1; }

  if ! $DRY_RUN; then
    confirm_restore "PostgreSQL" "$backup_file" || { log_warn "Restauration annulee."; return 0; }
  fi

  log_info "Backup selectionne : $backup_file"
  local filesize
  filesize=$(du -sh "$backup_file" | cut -f1)
  log_info "Taille du fichier : $filesize"

  if $DRY_RUN; then
    log_warn "[DRY-RUN] Simulation : restauration PostgreSQL depuis $backup_file"
    log_warn "[DRY-RUN] Commandes qui seraient executees :"
    echo "  export PGPASSWORD='***'"
    if [[ "$backup_file" == *.gz ]]; then
      echo "  gunzip -c '$backup_file' | psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_DB"
    else
      echo "  psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_DB < '$backup_file'"
    fi
    return 0
  fi

  log_info "Demarrage de la restauration PostgreSQL..."

  # Tentative via psql local
  if command -v psql &>/dev/null; then
    export PGPASSWORD="$POSTGRES_PASSWORD"
    if [[ "$backup_file" == *.gz ]]; then
      if gunzip -c "$backup_file" | psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
          -U "$POSTGRES_USER" "$POSTGRES_DB" 2>>"$LOG_FILE"; then
        log_success "Restauration PostgreSQL reussie (psql local)"
      else
        log_error "Echec de la restauration PostgreSQL"
        return 1
      fi
    else
      if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
          -U "$POSTGRES_USER" "$POSTGRES_DB" < "$backup_file" 2>>"$LOG_FILE"; then
        log_success "Restauration PostgreSQL reussie (psql local)"
      else
        log_error "Echec de la restauration PostgreSQL"
        return 1
      fi
    fi
  # Fallback via Docker
  elif command -v docker &>/dev/null && docker ps | grep -q postgres; then
    local pg_container
    pg_container=$(docker ps --format '{{.Names}}' | grep -i postgres | head -1)
    log_info "Utilisation du conteneur Docker : $pg_container"
    if [[ "$backup_file" == *.gz ]]; then
      gunzip -c "$backup_file" | docker exec -i "$pg_container" \
        psql -U "$POSTGRES_USER" "$POSTGRES_DB" 2>>"$LOG_FILE"
    else
      docker exec -i "$pg_container" \
        psql -U "$POSTGRES_USER" "$POSTGRES_DB" < "$backup_file" 2>>"$LOG_FILE"
    fi
    log_success "Restauration PostgreSQL reussie (via Docker)"
  else
    log_error "psql non trouve et aucun conteneur PostgreSQL en cours d'execution"
    return 1
  fi
}

# ── Restauration Redis ────────────────────────────────────────────────────────
restore_redis() {
  local backup_file="${1:-}"

  log_step "Restauration Redis"

  if [[ -z "$backup_file" ]]; then
    backup_file=$(find_latest_backup redis)
    if [[ -z "$backup_file" ]]; then
      log_error "Aucun backup Redis trouve dans ${BACKUP_DIR}/redis/"
      return 1
    fi
    log_info "Backup le plus recent trouve : $backup_file"
  fi

  [[ -f "$backup_file" ]] || { log_error "Fichier introuvable : $backup_file"; return 1; }

  if ! $DRY_RUN; then
    confirm_restore "Redis" "$backup_file" || { log_warn "Restauration annulee."; return 0; }
  fi

  log_info "Backup selectionne : $backup_file"

  if $DRY_RUN; then
    log_warn "[DRY-RUN] Simulation : restauration Redis depuis $backup_file"
    log_warn "[DRY-RUN] Les etapes seraient :"
    echo "  1. Arret de Redis / BGSAVE"
    echo "  2. Copie du fichier RDB vers /var/lib/redis/dump.rdb"
    echo "  3. Redemarrage de Redis"
    return 0
  fi

  # Restauration via Docker (methode recommandee)
  if command -v docker &>/dev/null && docker ps | grep -q redis; then
    local redis_container
    redis_container=$(docker ps --format '{{.Names}}' | grep -i redis | grep -v exporter | head -1)
    log_info "Conteneur Redis detecte : $redis_container"

    # Recuperer le chemin du datadir Redis
    local redis_datadir
    redis_datadir=$(docker inspect "$redis_container" \
      --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")

    if [[ -n "$redis_datadir" ]]; then
      log_info "Arret de Redis pour la restauration..."
      docker stop "$redis_container" 2>>"$LOG_FILE" || true

      log_info "Copie du fichier RDB : $backup_file -> ${redis_datadir}/dump.rdb"
      cp "$backup_file" "${redis_datadir}/dump.rdb"

      log_info "Redemarrage de Redis..."
      docker start "$redis_container" 2>>"$LOG_FILE"
      sleep 3

      log_success "Restauration Redis reussie"
    else
      log_warn "Impossible de determiner le datadir Redis. Tentative de copie directe..."
      docker cp "$backup_file" "${redis_container}:/data/dump.rdb" 2>>"$LOG_FILE"
      docker restart "$redis_container" 2>>"$LOG_FILE"
      log_success "Restauration Redis reussie (copie directe)"
    fi
  else
    log_warn "Aucun conteneur Redis trouve. Restauration manuelle requise."
    log_info "Copiez manuellement $backup_file vers /var/lib/redis/dump.rdb et redemarrez Redis."
    return 1
  fi
}

# ── Restauration fichiers ──────────────────────────────────────────────────────
restore_files() {
  local backup_file="${1:-}"

  log_step "Restauration des fichiers"

  if [[ -z "$backup_file" ]]; then
    backup_file=$(find_latest_backup files)
    if [[ -z "$backup_file" ]]; then
      log_error "Aucun backup de fichiers trouve dans ${BACKUP_DIR}/files/"
      return 1
    fi
    log_info "Backup le plus recent trouve : $backup_file"
  fi

  [[ -f "$backup_file" ]] || { log_error "Fichier introuvable : $backup_file"; return 1; }

  if ! $DRY_RUN; then
    confirm_restore "fichiers" "$backup_file" || { log_warn "Restauration annulee."; return 0; }
  fi

  log_info "Backup selectionne : $backup_file"
  local filesize
  filesize=$(du -sh "$backup_file" | cut -f1)
  log_info "Taille de l'archive : $filesize"

  # Repertoire de restauration temporaire
  local restore_dir="${INFRA_DIR}/restore_${TIMESTAMP}"
  mkdir -p "$restore_dir"

  if $DRY_RUN; then
    log_warn "[DRY-RUN] Simulation : restauration fichiers depuis $backup_file"
    log_warn "[DRY-RUN] Destination : $restore_dir"
    log_warn "[DRY-RUN] Commande : tar -xzf '$backup_file' -C '$restore_dir'"
    return 0
  fi

  log_info "Extraction de l'archive vers $restore_dir ..."
  if tar -xzf "$backup_file" -C "$restore_dir" 2>>"$LOG_FILE"; then
    log_success "Archive extraite dans $restore_dir"
    log_info "Contenu restaure :"
    ls -la "$restore_dir" | tee -a "$LOG_FILE"
  else
    log_error "Echec de l'extraction de l'archive"
    rm -rf "$restore_dir"
    return 1
  fi
}

# ── Restauration complete ──────────────────────────────────────────────────────
restore_all() {
  log_step "Restauration complete (tous les services)"
  local errors=0

  restore_postgres "" || errors=$((errors + 1))
  restore_redis    "" || errors=$((errors + 1))
  restore_files    "" || errors=$((errors + 1))

  if [[ $errors -eq 0 ]]; then
    log_success "Restauration complete reussie pour tous les services"
  else
    log_warn "Restauration terminee avec $errors erreur(s). Verifiez $LOG_FILE"
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  check_prereqs

  if $LIST_ONLY; then
    list_backups
    exit 0
  fi

  if [[ -z "$SERVICE" ]]; then
    log_error "Vous devez specifier --service ou --list"
    echo ""
    usage
  fi

  case "$SERVICE" in
    postgres) restore_postgres "$BACKUP_FILE" ;;
    redis)    restore_redis    "$BACKUP_FILE" ;;
    files)    restore_files    "$BACKUP_FILE" ;;
    all)      restore_all ;;
    *)
      log_error "Service inconnu : $SERVICE"
      log_info "Services valides : postgres, redis, files, all"
      exit 1
      ;;
  esac

  echo ""
  log_info "Log complet : $LOG_FILE"
}

main "$@"
