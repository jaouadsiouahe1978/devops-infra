#!/bin/bash
# generate-certs.sh — Generateur de certificats SSL self-signed pour les services DevOps
# Usage: generate-certs.sh [--service SERVICE] [--all] [--ca-only] [--help]
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
CERTS_DIR="${INFRA_DIR}/certs"
CA_DIR="${CERTS_DIR}/ca"
LOG_DIR="${INFRA_DIR}/logs"
LOG_FILE="${LOG_DIR}/generate-certs.log"

# ── Parametres des certificats ─────────────────────────────────────────────────
CERT_COUNTRY="${CERT_COUNTRY:-FR}"
CERT_STATE="${CERT_STATE:-Ile-de-France}"
CERT_CITY="${CERT_CITY:-Paris}"
CERT_ORG="${CERT_ORG:-DevOps Lab}"
CERT_OU="${CERT_OU:-Infrastructure}"
CERT_DAYS="${CERT_DAYS:-825}"         # Duree de validite des certificats de service
CA_DAYS="${CA_DAYS:-3650}"            # Duree de validite de la CA (10 ans)
KEY_SIZE="${KEY_SIZE:-4096}"          # Taille de la cle RSA

# ── Liste des services et leurs SANs ──────────────────────────────────────────
# Format: "nom_service:cn:san1,san2,san3"
declare -a SERVICES=(
  "grafana:grafana.devops.local:grafana.devops.local,localhost,127.0.0.1"
  "prometheus:prometheus.devops.local:prometheus.devops.local,localhost,127.0.0.1"
  "alertmanager:alertmanager.devops.local:alertmanager.devops.local,localhost,127.0.0.1"
  "jenkins:jenkins.devops.local:jenkins.devops.local,localhost,127.0.0.1"
  "gitea:gitea.devops.local:gitea.devops.local,localhost,127.0.0.1"
  "argocd:argocd.devops.local:argocd.devops.local,localhost,127.0.0.1"
  "vault:vault.devops.local:vault.devops.local,localhost,127.0.0.1"
  "consul:consul.devops.local:consul.devops.local,localhost,127.0.0.1"
  "keycloak:keycloak.devops.local:keycloak.devops.local,localhost,127.0.0.1"
  "minio:minio.devops.local:minio.devops.local,localhost,127.0.0.1"
  "nexus:nexus.devops.local:nexus.devops.local,localhost,127.0.0.1"
  "traefik:traefik.devops.local:traefik.devops.local,localhost,127.0.0.1"
  "portainer:portainer.devops.local:portainer.devops.local,localhost,127.0.0.1"
  "elasticsearch:elasticsearch.devops.local:elasticsearch.devops.local,localhost,127.0.0.1"
  "kibana:kibana.devops.local:kibana.devops.local,localhost,127.0.0.1"
  "sonarqube:sonarqube.devops.local:sonarqube.devops.local,localhost,127.0.0.1"
  "registry:registry.devops.local:registry.devops.local,localhost,127.0.0.1"
  "wildcard:*.devops.local:*.devops.local,devops.local,localhost,127.0.0.1"
)

# ── Helpers ────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
log_step()    { echo -e "\n${CYAN}>>> $*${NC}" | tee -a "$LOG_FILE"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generateur de certificats SSL self-signed pour l'infrastructure DevOps/SRE.
Cree une CA locale et des certificats signes par celle-ci.

Options:
  --service SERVICE   Generer un certificat pour un service specifique
  --all               Generer les certificats pour tous les services
  --ca-only           Generer uniquement la CA
  --list              Lister les services disponibles
  --show SERVICE      Afficher les infos d'un certificat existant
  --verify SERVICE    Verifier un certificat contre la CA
  --days N            Duree de validite (defaut: 825 jours)
  --help              Afficher cette aide

Services disponibles:
$(for s in "${SERVICES[@]}"; do echo "  ${s%%:*}"; done)

Exemples:
  $(basename "$0") --ca-only
  $(basename "$0") --service grafana
  $(basename "$0") --all
  $(basename "$0") --show vault
  $(basename "$0") --verify consul
  $(basename "$0") --service myapp --days 365
EOF
  exit 0
}

# ── Verification de prerequis ─────────────────────────────────────────────────
check_prereqs() {
  if ! command -v openssl &>/dev/null; then
    log_error "openssl n'est pas installe. Installez-le : sudo apt-get install openssl"
    exit 1
  fi
  log_info "openssl $(openssl version | awk '{print $2}') detecte"
}

# ── Initialiser les repertoires ────────────────────────────────────────────────
init_dirs() {
  mkdir -p "$CA_DIR" "$CERTS_DIR"
  chmod 700 "$CA_DIR"
  log_info "Repertoire CA : $CA_DIR"
  log_info "Repertoire certs : $CERTS_DIR"
}

# ── Generer la CA ──────────────────────────────────────────────────────────────
generate_ca() {
  log_step "Generation de l'autorite de certification (CA)"

  if [[ -f "${CA_DIR}/ca.crt" ]] && [[ -f "${CA_DIR}/ca.key" ]]; then
    log_warn "CA deja existante dans $CA_DIR"
    local expiry
    expiry=$(openssl x509 -enddate -noout -in "${CA_DIR}/ca.crt" 2>/dev/null | cut -d= -f2)
    log_info "Expiration CA : $expiry"
    read -rp "Regenerer la CA ? Cela invalidera tous les certificats existants [oui/non] : " confirm
    if [[ ! "$confirm" =~ ^(oui|yes|o|y)$ ]]; then
      log_info "CA conservee."
      return 0
    fi
    # Backup de l'ancienne CA
    local backup_ts
    backup_ts=$(date '+%Y%m%d_%H%M%S')
    cp "${CA_DIR}/ca.crt" "${CA_DIR}/ca.crt.${backup_ts}.bak"
    cp "${CA_DIR}/ca.key" "${CA_DIR}/ca.key.${backup_ts}.bak"
    log_info "Ancienne CA sauvegardee (*.bak)"
  fi

  log_info "Generation de la cle privee CA (${KEY_SIZE} bits)..."
  openssl genrsa -out "${CA_DIR}/ca.key" "$KEY_SIZE" 2>>"$LOG_FILE"
  chmod 600 "${CA_DIR}/ca.key"

  log_info "Generation du certificat CA auto-signe (${CA_DAYS} jours)..."
  openssl req -new -x509 \
    -key "${CA_DIR}/ca.key" \
    -out "${CA_DIR}/ca.crt" \
    -days "$CA_DAYS" \
    -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=DevOps Lab Root CA" \
    -extensions v3_ca \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "subjectKeyIdentifier=hash" \
    -addext "authorityKeyIdentifier=keyid:always,issuer" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    2>>"$LOG_FILE"

  chmod 644 "${CA_DIR}/ca.crt"

  log_success "CA generee avec succes"
  log_info "Cle CA     : ${CA_DIR}/ca.key"
  log_info "Cert CA    : ${CA_DIR}/ca.crt"

  # Afficher le fingerprint
  local fingerprint
  fingerprint=$(openssl x509 -fingerprint -sha256 -noout -in "${CA_DIR}/ca.crt" 2>/dev/null | cut -d= -f2)
  log_info "SHA256 fingerprint : $fingerprint"

  echo ""
  echo -e "${YELLOW}Pour faire confiance a cette CA sur votre systeme :${NC}"
  echo "  sudo cp ${CA_DIR}/ca.crt /usr/local/share/ca-certificates/devops-lab-ca.crt"
  echo "  sudo update-ca-certificates"
  echo ""
  echo -e "${YELLOW}Pour les navigateurs, importer :${NC}"
  echo "  ${CA_DIR}/ca.crt"
}

# ── Generer un certificat de service ──────────────────────────────────────────
generate_service_cert() {
  local service_name="$1"
  local cn="$2"
  local sans_str="$3"

  local service_dir="${CERTS_DIR}/${service_name}"
  mkdir -p "$service_dir"

  log_step "Generation du certificat pour : $service_name"
  log_info "CN : $cn"
  log_info "SANs : $sans_str"

  # Verifier que la CA existe
  if [[ ! -f "${CA_DIR}/ca.crt" ]] || [[ ! -f "${CA_DIR}/ca.key" ]]; then
    log_warn "CA non trouvee. Generation de la CA d'abord..."
    generate_ca
  fi

  # Generer la cle privee
  log_info "Generation de la cle privee (${KEY_SIZE} bits)..."
  openssl genrsa -out "${service_dir}/${service_name}.key" "$KEY_SIZE" 2>>"$LOG_FILE"
  chmod 600 "${service_dir}/${service_name}.key"

  # Construire la liste des SANs pour le fichier de config
  local san_section="subjectAltName = "
  local san_entries=()
  IFS=',' read -ra SANS <<< "$sans_str"
  for san in "${SANS[@]}"; do
    san=$(echo "$san" | tr -d ' ')
    if [[ "$san" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      san_entries+=("IP:${san}")
    else
      san_entries+=("DNS:${san}")
    fi
  done
  local san_value
  san_value=$(IFS=','; echo "${san_entries[*]}")

  # Fichier de configuration openssl
  local openssl_conf="${service_dir}/${service_name}.cnf"
  cat > "$openssl_conf" <<OPENSSLCONF
[req]
default_bits        = ${KEY_SIZE}
distinguished_name  = req_distinguished_name
req_extensions      = v3_req
prompt              = no

[req_distinguished_name]
C                   = ${CERT_COUNTRY}
ST                  = ${CERT_STATE}
L                   = ${CERT_CITY}
O                   = ${CERT_ORG}
OU                  = ${CERT_OU}
CN                  = ${cn}

[v3_req]
basicConstraints    = CA:FALSE
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth, clientAuth
subjectAltName      = ${san_value}

[v3_ext]
basicConstraints    = CA:FALSE
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth, clientAuth
subjectAltName      = ${san_value}
authorityKeyIdentifier = keyid,issuer
OPENSSLCONF

  # Generer la CSR
  log_info "Generation de la CSR..."
  openssl req -new \
    -key "${service_dir}/${service_name}.key" \
    -out "${service_dir}/${service_name}.csr" \
    -config "$openssl_conf" \
    2>>"$LOG_FILE"

  # Signer avec la CA
  log_info "Signature du certificat par la CA (${CERT_DAYS} jours)..."
  openssl x509 -req \
    -in "${service_dir}/${service_name}.csr" \
    -CA "${CA_DIR}/ca.crt" \
    -CAkey "${CA_DIR}/ca.key" \
    -CAcreateserial \
    -out "${service_dir}/${service_name}.crt" \
    -days "$CERT_DAYS" \
    -extensions v3_ext \
    -extfile "$openssl_conf" \
    2>>"$LOG_FILE"

  chmod 644 "${service_dir}/${service_name}.crt"

  # Creer le bundle (cert + chain)
  cat "${service_dir}/${service_name}.crt" "${CA_DIR}/ca.crt" > \
      "${service_dir}/${service_name}.bundle.crt"

  # Creer le fichier PEM complet (key + cert) pour certains services
  cat "${service_dir}/${service_name}.key" "${service_dir}/${service_name}.crt" > \
      "${service_dir}/${service_name}.pem"
  chmod 600 "${service_dir}/${service_name}.pem"

  # Creer des symlinks pratiques
  ln -sf "${service_dir}/${service_name}.crt" "${CERTS_DIR}/${service_name}.crt" 2>/dev/null || true
  ln -sf "${service_dir}/${service_name}.key" "${CERTS_DIR}/${service_name}.key" 2>/dev/null || true

  # Nettoyer la CSR
  rm -f "${service_dir}/${service_name}.csr"

  # Afficher les infos du certificat
  local expiry
  expiry=$(openssl x509 -enddate -noout -in "${service_dir}/${service_name}.crt" 2>/dev/null | cut -d= -f2)
  log_success "Certificat $service_name genere avec succes"
  log_info "Expiration : $expiry"
  log_info "Fichiers generes :"
  echo "    Cle privee   : ${service_dir}/${service_name}.key"
  echo "    Certificat   : ${service_dir}/${service_name}.crt"
  echo "    Bundle       : ${service_dir}/${service_name}.bundle.crt"
  echo "    PEM complet  : ${service_dir}/${service_name}.pem"
  echo "    Config       : ${service_dir}/${service_name}.cnf"
}

# ── Generer tous les certificats ───────────────────────────────────────────────
generate_all() {
  log_step "Generation de tous les certificats"
  generate_ca

  local success=0
  local failed=0

  for entry in "${SERVICES[@]}"; do
    local service_name="${entry%%:*}"
    local rest="${entry#*:}"
    local cn="${rest%%:*}"
    local sans="${rest#*:}"

    if generate_service_cert "$service_name" "$cn" "$sans"; then
      success=$((success + 1))
    else
      log_error "Echec pour : $service_name"
      failed=$((failed + 1))
    fi
  done

  echo ""
  log_success "Generation terminee : $success succes, $failed echecs"
  generate_summary
}

# ── Afficher les infos d'un certificat ────────────────────────────────────────
show_cert_info() {
  local service_name="$1"
  local cert_file="${CERTS_DIR}/${service_name}/${service_name}.crt"

  if [[ ! -f "$cert_file" ]]; then
    cert_file="${CERTS_DIR}/${service_name}.crt"
  fi

  if [[ ! -f "$cert_file" ]]; then
    log_error "Certificat non trouve pour : $service_name"
    log_info "Fichiers cherches :"
    echo "  ${CERTS_DIR}/${service_name}/${service_name}.crt"
    echo "  ${CERTS_DIR}/${service_name}.crt"
    exit 1
  fi

  log_step "Informations du certificat : $service_name"
  openssl x509 -noout -text -in "$cert_file" 2>/dev/null | grep -E \
    "Subject:|Issuer:|Not Before:|Not After:|Subject Alternative|DNS:|IP Address:|Serial Number:"
  echo ""
  local sha256
  sha256=$(openssl x509 -fingerprint -sha256 -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
  log_info "SHA256 : $sha256"
}

# ── Verifier un certificat contre la CA ───────────────────────────────────────
verify_cert() {
  local service_name="$1"
  local cert_file="${CERTS_DIR}/${service_name}/${service_name}.crt"

  if [[ ! -f "$cert_file" ]]; then
    cert_file="${CERTS_DIR}/${service_name}.crt"
  fi

  if [[ ! -f "$cert_file" ]]; then
    log_error "Certificat non trouve pour : $service_name"
    exit 1
  fi

  log_step "Verification du certificat : $service_name"

  if openssl verify -CAfile "${CA_DIR}/ca.crt" "$cert_file" 2>>"$LOG_FILE"; then
    log_success "Certificat VALIDE et signe par la CA DevOps Lab"
  else
    log_error "Certificat INVALIDE ou non signe par la CA"
    exit 1
  fi

  # Verifier la date d'expiration
  local expiry
  expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
  local days_left
  days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))

  if [[ $days_left -lt 30 ]]; then
    log_warn "Certificat expire dans ${days_left} jours !"
  elif [[ $days_left -lt 90 ]]; then
    log_warn "Certificat expire dans ${days_left} jours (renouvellement recommande)"
  else
    log_success "Expiration dans ${days_left} jours ($expiry)"
  fi
}

# ── Afficher un resume de tous les certs ──────────────────────────────────────
generate_summary() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║              RESUME DES CERTIFICATS GENERES                     ║${NC}"
  echo -e "${BLUE}╠════════════════════╦════════════════════════╦═══════════════════╣${NC}"
  echo -e "${BLUE}║ SERVICE            ║ EXPIRATION             ║ STATUS            ║${NC}"
  echo -e "${BLUE}╠════════════════════╬════════════════════════╬═══════════════════╣${NC}"

  for entry in "${SERVICES[@]}"; do
    local service_name="${entry%%:*}"
    local cert_file="${CERTS_DIR}/${service_name}/${service_name}.crt"

    if [[ -f "$cert_file" ]]; then
      local expiry
      expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || echo "inconnu")
      local days_left
      days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
      local status_str
      if [[ $days_left -lt 30 ]]; then
        status_str="${RED}EXPIRE BIENTOT${NC}"
      else
        status_str="${GREEN}OK (${days_left}j)${NC}"
      fi
      printf "${BLUE}║${NC} %-18s ${BLUE}║${NC} %-22s ${BLUE}║${NC} ${status_str}%-1s${BLUE}║${NC}\n" \
        "$service_name" "${expiry:0:22}" ""
    else
      printf "${BLUE}║${NC} %-18s ${BLUE}║${NC} %-22s ${BLUE}║${NC} ${YELLOW}MANQUANT${NC}           ${BLUE}║${NC}\n" \
        "$service_name" "-"
    fi
  done

  echo -e "${BLUE}╚════════════════════╩════════════════════════╩═══════════════════╝${NC}"
  echo ""
  log_info "CA : ${CA_DIR}/ca.crt"
  log_info "Certs : ${CERTS_DIR}/"
}

# ── Lister les services disponibles ───────────────────────────────────────────
list_services() {
  echo ""
  echo -e "${CYAN}Services disponibles pour la generation de certificats :${NC}"
  echo ""
  for entry in "${SERVICES[@]}"; do
    local name="${entry%%:*}"
    local rest="${entry#*:}"
    local cn="${rest%%:*}"
    printf "  %-18s  CN: %s\n" "$name" "$cn"
  done
  echo ""
}

# ── Trouver un service dans le catalogue ──────────────────────────────────────
find_service() {
  local target="$1"
  for entry in "${SERVICES[@]}"; do
    if [[ "${entry%%:*}" == "$target" ]]; then
      echo "$entry"
      return 0
    fi
  done
  return 1
}

# ── Parse arguments ────────────────────────────────────────────────────────────
TARGET_SERVICE=""
ACTION="help"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)   TARGET_SERVICE="$2"; ACTION="service"; shift 2 ;;
    --all)       ACTION="all";        shift ;;
    --ca-only)   ACTION="ca";         shift ;;
    --list)      ACTION="list";       shift ;;
    --show)      TARGET_SERVICE="$2"; ACTION="show";    shift 2 ;;
    --verify)    TARGET_SERVICE="$2"; ACTION="verify";  shift 2 ;;
    --days)      CERT_DAYS="$2";      shift 2 ;;
    --help|-h)   usage ;;
    *) log_error "Argument inconnu : $1"; usage ;;
  esac
done

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  mkdir -p "$LOG_DIR"
  echo "=== generate-certs.sh — $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
  check_prereqs
  init_dirs

  case "$ACTION" in
    ca)
      generate_ca
      ;;
    service)
      if [[ -z "$TARGET_SERVICE" ]]; then
        log_error "--service requiert un nom de service"
        exit 1
      fi
      local entry
      entry=$(find_service "$TARGET_SERVICE") || {
        log_warn "Service '$TARGET_SERVICE' non dans le catalogue. Generation avec CN=localhost..."
        generate_ca
        generate_service_cert "$TARGET_SERVICE" "${TARGET_SERVICE}.devops.local" \
          "${TARGET_SERVICE}.devops.local,localhost,127.0.0.1"
        exit 0
      }
      generate_ca
      local rest="${entry#*:}"
      local cn="${rest%%:*}"
      local sans="${rest#*:}"
      generate_service_cert "$TARGET_SERVICE" "$cn" "$sans"
      ;;
    all)
      generate_all
      ;;
    list)
      list_services
      ;;
    show)
      show_cert_info "$TARGET_SERVICE"
      ;;
    verify)
      verify_cert "$TARGET_SERVICE"
      ;;
    help|*)
      usage
      ;;
  esac

  echo ""
  log_info "Log : $LOG_FILE"
}

main "$@"
