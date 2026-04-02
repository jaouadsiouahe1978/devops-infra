#!/usr/bin/env bash
# =============================================================================
# log-viewer.sh - Centralized log viewer for all services
# Usage: ./log-viewer.sh [--service=NAME] [--follow] [--since=1h] [--errors-only]
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

LOGS_ROOT="${HOME}/devops-infra/logs"
SERVICE=""
FOLLOW=false
SINCE="1h"
ERRORS_ONLY=false
LINES=100

usage() {
  cat <<EOF
${BOLD}log-viewer.sh${RESET} - Centralized log viewer

Usage: $0 [OPTIONS]

Options:
  --service=NAME    View logs for specific service (docker/k8s/systemd)
  --follow, -f      Follow log output
  --since=DURATION  Show logs since duration (1h, 30m, 2d) [default: 1h]
  --errors-only     Show only ERROR/WARN/CRIT lines
  --lines=N         Number of lines to show [default: 100]
  --list            List available services
  --help            Show this help

Examples:
  $0 --service=postgres --follow
  $0 --service=prometheus --since=30m --errors-only
  $0 --service=k8s-pods --follow
EOF
}

list_services() {
  echo -e "\n${BOLD}Available Services:${RESET}\n"
  echo -e "${CYAN}Docker Services:${RESET}"
  docker ps --format "  - {{.Names}}" 2>/dev/null || echo "  (Docker not running)"
  echo -e "\n${CYAN}Systemd Services:${RESET}"
  systemctl list-units --type=service --state=running 2>/dev/null | grep -E "(postgres|mysql|redis|nginx|k3s)" | awk '{print "  - "$1}' || true
  echo -e "\n${CYAN}K8s Namespaces:${RESET}"
  kubectl get pods --all-namespaces --no-headers 2>/dev/null | awk '{print "  - "$2" ("$1")"}' | head -20 || echo "  (K3s not running)"
}

get_docker_logs() {
  local svc="$1"
  local args=""
  [[ "$FOLLOW" == "true" ]] && args="$args -f"
  args="$args --since $SINCE --tail $LINES"

  if docker ps --format "{{.Names}}" | grep -q "^${svc}$"; then
    echo -e "${BOLD}${CYAN}=== Docker: ${svc} ===${RESET}"
    if [[ "$ERRORS_ONLY" == "true" ]]; then
      docker logs $args "$svc" 2>&1 | grep -iE "(error|warn|crit|fatal|exception)" \
        | sed "s/error/$(echo -e ${RED}error${RESET})/gi" \
        | sed "s/warn/$(echo -e ${YELLOW}warn${RESET})/gi"
    else
      docker logs $args "$svc" 2>&1
    fi
  else
    echo -e "${RED}Container '${svc}' not running${RESET}"
    return 1
  fi
}

get_systemd_logs() {
  local svc="$1"
  local args="-u $svc --no-pager -n $LINES --since=-${SINCE}"
  [[ "$FOLLOW" == "true" ]] && args="$args -f"

  echo -e "${BOLD}${CYAN}=== Systemd: ${svc} ===${RESET}"
  if [[ "$ERRORS_ONLY" == "true" ]]; then
    journalctl $args 2>/dev/null | grep -iE "(error|warn|crit|fail)" || echo "(no entries)"
  else
    journalctl $args 2>/dev/null || echo "(service not found)"
  fi
}

get_k8s_logs() {
  local pod_pattern="$1"
  echo -e "${BOLD}${CYAN}=== K8s pods matching: ${pod_pattern} ===${RESET}"
  local pods
  pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep "$pod_pattern" | awk '{print $1"/"$2}' | head -5)

  if [[ -z "$pods" ]]; then
    echo -e "${RED}No pods matching '${pod_pattern}'${RESET}"
    return 1
  fi

  while IFS='/' read -r ns pod; do
    echo -e "\n${YELLOW}--- Pod: ${pod} (ns: ${ns}) ---${RESET}"
    local kargs="logs -n $ns $pod --tail=$LINES --since=$SINCE"
    [[ "$FOLLOW" == "true" ]] && kargs="$kargs -f"
    kubectl $kargs 2>/dev/null || true
  done <<< "$pods"
}

# Parse args
for arg in "$@"; do
  case "$arg" in
    --service=*) SERVICE="${arg#--service=}" ;;
    --follow|-f) FOLLOW=true ;;
    --since=*) SINCE="${arg#--since=}" ;;
    --errors-only) ERRORS_ONLY=true ;;
    --lines=*) LINES="${arg#--lines=}" ;;
    --list) list_services; exit 0 ;;
    --help|-h) usage; exit 0 ;;
  esac
done

if [[ -z "$SERVICE" ]]; then
  usage
  echo -e "\n${YELLOW}Tip: Use --list to see available services${RESET}"
  exit 0
fi

# Try docker first, then systemd, then k8s
if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${SERVICE}$"; then
  get_docker_logs "$SERVICE"
elif systemctl is-active "$SERVICE" &>/dev/null || systemctl list-units --type=service | grep -q "$SERVICE"; then
  get_systemd_logs "$SERVICE"
else
  get_k8s_logs "$SERVICE"
fi
