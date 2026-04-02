#!/usr/bin/env bash
# =============================================================================
# cert-check.sh - TLS certificate expiry checker
# Checks all HTTPS services and local certs
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

WARN_DAYS=30
CRIT_DAYS=7
INFRA_DIR="${HOME}/devops-infra"

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"; }

check_endpoint_cert() {
  local name="$1"
  local host="$2"
  local port="$3"

  local expiry_date
  expiry_date=$(echo | timeout 5 openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2) || {
    echo -e "  ${CYAN}${name}${RESET}: ${YELLOW}No TLS / Cannot connect${RESET}"
    return
  }

  local expiry_epoch
  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
  local now_epoch
  now_epoch=$(date +%s)
  local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

  if [[ $days_left -le $CRIT_DAYS ]]; then
    echo -e "  ${RED}[CRITICAL]${RESET} ${name}: Expires in ${days_left} days (${expiry_date})"
  elif [[ $days_left -le $WARN_DAYS ]]; then
    echo -e "  ${YELLOW}[WARNING]${RESET} ${name}: Expires in ${days_left} days (${expiry_date})"
  else
    echo -e "  ${GREEN}[OK]${RESET} ${name}: Valid for ${days_left} days"
  fi
}

check_file_cert() {
  local name="$1"
  local cert_file="$2"

  [[ -f "$cert_file" ]] || { echo -e "  ${YELLOW}[SKIP]${RESET} ${name}: File not found"; return; }

  local expiry_date
  expiry_date=$(openssl x509 -noout -enddate -in "$cert_file" 2>/dev/null | cut -d= -f2) || return
  local expiry_epoch
  expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
  local days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))

  if [[ $days_left -le $CRIT_DAYS ]]; then
    echo -e "  ${RED}[CRITICAL]${RESET} ${name}: Expires in ${days_left} days"
  elif [[ $days_left -le $WARN_DAYS ]]; then
    echo -e "  ${YELLOW}[WARNING]${RESET} ${name}: Expires in ${days_left} days"
  else
    echo -e "  ${GREEN}[OK]${RESET} ${name}: Valid for ${days_left} days"
  fi
}

echo -e "\n${BOLD}Certificate Expiry Report - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo -e "${CYAN}$(printf '%.0s=' {1..60})${RESET}"

echo -e "\n${BOLD}HTTPS Endpoints:${RESET}"
check_endpoint_cert "Nginx HTTPS" "localhost" "443"
check_endpoint_cert "GitLab" "localhost" "8443"
check_endpoint_cert "Vault" "localhost" "8201"
check_endpoint_cert "Kubernetes API" "localhost" "6443"

echo -e "\n${BOLD}Local Certificate Files:${RESET}"
find "${INFRA_DIR}" -name "*.crt" -o -name "*.pem" 2>/dev/null | while read -r cert; do
  [[ -f "$cert" ]] && check_file_cert "$(basename "$cert")" "$cert"
done

# Check /etc/ssl
find /etc/ssl/certs -name "*.crt" -newer /etc/ssl/certs/ca-certificates.crt 2>/dev/null | head -5 | while read -r cert; do
  check_file_cert "$(basename "$cert")" "$cert"
done

echo -e "\n${CYAN}$(printf '%.0s=' {1..60})${RESET}"
echo "Warn threshold: ${WARN_DAYS} days | Critical threshold: ${CRIT_DAYS} days"
