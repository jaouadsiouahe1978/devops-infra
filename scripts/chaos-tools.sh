#!/usr/bin/env bash
# =============================================================================
# chaos-tools.sh - Chaos engineering utilities
# Standalone chaos functions for SRE training
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

LOCK_FILE="/tmp/chaos-active.lock"

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"; }
warn() { echo -e "${YELLOW}[CHAOS]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }

require_confirm() {
  warn "This will create a REAL disruption. Type 'yes' to confirm:"
  read -r confirm
  [[ "$confirm" == "yes" ]] || { log "Aborted."; exit 0; }
}

# Network chaos: add latency
add_latency() {
  local ms="${1:-500}"
  warn "Adding ${ms}ms latency to loopback interface"
  sudo tc qdisc add dev lo root netem delay "${ms}ms" 2>/dev/null || \
    sudo tc qdisc change dev lo root netem delay "${ms}ms"
  success "Latency added. Remove with: $0 remove-latency"
  echo "tc qdisc del dev lo root" > "$LOCK_FILE"
}

remove_latency() {
  sudo tc qdisc del dev lo root 2>/dev/null && success "Latency removed" || warn "No latency rule found"
  rm -f "$LOCK_FILE"
}

# CPU stress
stress_cpu() {
  local cores="${1:-4}"
  local duration="${2:-60}"
  warn "Stressing ${cores} CPU cores for ${duration}s"
  command -v stress-ng &>/dev/null || { error "Install stress-ng: sudo apt install stress-ng"; exit 1; }
  stress-ng --cpu "$cores" --timeout "${duration}s" --metrics-brief &
  echo $! > /tmp/stress-cpu.pid
  success "CPU stress started (PID $(cat /tmp/stress-cpu.pid)). Duration: ${duration}s"
}

stop_stress_cpu() {
  if [[ -f /tmp/stress-cpu.pid ]]; then
    kill "$(cat /tmp/stress-cpu.pid)" 2>/dev/null && success "CPU stress stopped"
    rm -f /tmp/stress-cpu.pid
  fi
}

# Memory pressure
stress_memory() {
  local size="${1:-4G}"
  local duration="${2:-60}"
  warn "Creating ${size} memory pressure for ${duration}s"
  command -v stress-ng &>/dev/null || { error "Install stress-ng: sudo apt install stress-ng"; exit 1; }
  stress-ng --vm 1 --vm-bytes "$size" --timeout "${duration}s" &
  echo $! > /tmp/stress-mem.pid
  success "Memory stress started. Duration: ${duration}s"
}

# Fill disk
fill_disk() {
  local target="${1:-/tmp}"
  local size="${2:-1G}"
  warn "Filling ${size} of ${target}"
  local fill_file="${target}/chaos-fill-$(date +%s).dat"
  dd if=/dev/zero of="$fill_file" bs=1M count=$((${size%G} * 1024)) 2>/dev/null
  echo "$fill_file" > /tmp/chaos-disk-fill.path
  success "Disk filled: $fill_file. Remove with: $0 free-disk"
}

free_disk() {
  if [[ -f /tmp/chaos-disk-fill.path ]]; then
    local f
    f=$(cat /tmp/chaos-disk-fill.path)
    rm -f "$f" && success "Removed $f"
    rm -f /tmp/chaos-disk-fill.path
  else
    warn "No chaos disk fill found"
  fi
}

# DNS chaos: break resolution
break_dns() {
  local domain="${1:-example.com}"
  warn "Breaking DNS for $domain"
  echo "0.0.0.0 $domain" | sudo tee -a /etc/hosts > /dev/null
  echo "$domain" >> /tmp/chaos-dns-entries.txt
  success "DNS broken for $domain. Fix with: $0 fix-dns"
}

fix_dns() {
  if [[ -f /tmp/chaos-dns-entries.txt ]]; then
    while read -r domain; do
      sudo sed -i "/0\.0\.0\.0 ${domain}/d" /etc/hosts
      success "DNS restored for $domain"
    done < /tmp/chaos-dns-entries.txt
    rm -f /tmp/chaos-dns-entries.txt
  fi
}

# Kill random container
kill_random_container() {
  local namespace="${1:-production}"
  local containers
  containers=$(docker ps --format "{{.Names}}" | grep -v "devops-infra" | shuf | head -1)
  if [[ -n "$containers" ]]; then
    warn "Killing container: $containers"
    docker kill "$containers"
    success "Container killed: $containers"
  else
    warn "No containers to kill"
  fi
}

# K8s chaos: delete random pod
delete_random_pod() {
  local namespace="${1:-production}"
  local pod
  pod=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | shuf | head -1 | awk '{print $1}')
  if [[ -n "$pod" ]]; then
    warn "Deleting pod: $pod in namespace: $namespace"
    kubectl delete pod "$pod" -n "$namespace" --grace-period=0
    success "Pod deleted: $pod"
  else
    warn "No pods found in namespace: $namespace"
  fi
}

# Status check
status() {
  echo -e "\n${BOLD}Active Chaos:${RESET}"

  # Check latency
  if sudo tc qdisc show dev lo 2>/dev/null | grep -q netem; then
    warn "Network latency is ACTIVE on loopback"
    sudo tc qdisc show dev lo
  fi

  # Check stress processes
  [[ -f /tmp/stress-cpu.pid ]] && warn "CPU stress ACTIVE (PID: $(cat /tmp/stress-cpu.pid))"
  [[ -f /tmp/stress-mem.pid ]] && warn "Memory stress ACTIVE (PID: $(cat /tmp/stress-mem.pid))"
  [[ -f /tmp/chaos-disk-fill.path ]] && warn "Disk fill ACTIVE: $(cat /tmp/chaos-disk-fill.path)"
  [[ -f /tmp/chaos-dns-entries.txt ]] && warn "DNS chaos ACTIVE for: $(cat /tmp/chaos-dns-entries.txt)"
}

# Cleanup all chaos
cleanup_all() {
  log "Cleaning up all chaos..."
  remove_latency 2>/dev/null || true
  stop_stress_cpu 2>/dev/null || true
  [[ -f /tmp/stress-mem.pid ]] && kill "$(cat /tmp/stress-mem.pid)" 2>/dev/null || true
  free_disk 2>/dev/null || true
  fix_dns 2>/dev/null || true
  success "All chaos cleaned up"
}

usage() {
  cat <<EOF
${BOLD}chaos-tools.sh${RESET} - Chaos Engineering Toolkit

Commands:
  add-latency [MS]              Add network latency (default: 500ms)
  remove-latency                Remove network latency
  stress-cpu [CORES] [SECS]    Stress CPU (default: 4 cores, 60s)
  stop-stress-cpu               Stop CPU stress
  stress-memory [SIZE] [SECS]  Stress memory (default: 4G, 60s)
  fill-disk [PATH] [SIZE]       Fill disk (default: /tmp, 1G)
  free-disk                     Free disk fill
  break-dns [DOMAIN]            Break DNS for domain
  fix-dns                       Fix all DNS entries
  kill-random-container         Kill a random Docker container
  delete-random-pod [NS]        Delete random K8s pod (default: production)
  status                        Show active chaos
  cleanup-all                   Stop all chaos

Examples:
  $0 add-latency 1000            # 1 second latency
  $0 stress-cpu 2 120            # 2 cores for 2 minutes
  $0 fill-disk /tmp 500M         # Fill 500MB of /tmp
EOF
}

CMD="${1:-}"
shift || true

case "$CMD" in
  add-latency) add_latency "$@" ;;
  remove-latency) remove_latency ;;
  stress-cpu) stress_cpu "$@" ;;
  stop-stress-cpu) stop_stress_cpu ;;
  stress-memory) stress_memory "$@" ;;
  fill-disk) fill_disk "$@" ;;
  free-disk) free_disk ;;
  break-dns) break_dns "$@" ;;
  fix-dns) fix_dns ;;
  kill-random-container) require_confirm; kill_random_container "$@" ;;
  delete-random-pod) require_confirm; delete_random_pod "$@" ;;
  status) status ;;
  cleanup-all) cleanup_all ;;
  *) usage ;;
esac
