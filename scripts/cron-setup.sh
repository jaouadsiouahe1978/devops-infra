#!/usr/bin/env bash
# =============================================================================
# cron-setup.sh - Configure all cron jobs for the infrastructure
# Run once after install to activate scheduled tasks
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
INFRA_DIR="${HOME}/devops-infra"
SCRIPTS="${INFRA_DIR}/scripts"
LOGS="${INFRA_DIR}/logs"

log() { echo -e "${CYAN}[CRON]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }

# Make all scripts executable
chmod +x "${SCRIPTS}"/*.sh 2>/dev/null || true

# Build crontab entries
CRONTAB_ENTRIES=$(cat <<EOF
# =============================================================================
# DevOps Infrastructure Cron Jobs
# Managed by: ${SCRIPTS}/cron-setup.sh
# Last updated: $(date)
# =============================================================================

# Health check every 5 minutes
*/5 * * * * ${SCRIPTS}/health-check.sh >> ${LOGS}/health-check.log 2>&1

# Daily backup at 02:00
0 2 * * * ${SCRIPTS}/backup.sh --service=all >> ${LOGS}/backup.log 2>&1

# Backup verification at 03:00
0 3 * * * ${SCRIPTS}/backup.sh --verify >> ${LOGS}/backup-verify.log 2>&1

# Weekly backup cleanup (Sunday 04:00)
0 4 * * 0 ${SCRIPTS}/backup.sh --rotate >> ${LOGS}/backup-rotate.log 2>&1

# Log rotation daily at 01:00
0 1 * * * find ${LOGS} -name "*.log" -size +100M -exec truncate -s 50M {} \;

# Certificate expiry check (daily 09:00)
0 9 * * * ${SCRIPTS}/cert-check.sh >> ${LOGS}/cert-check.log 2>&1

# Disk usage alert (every 30 min)
*/30 * * * * df -h | awk '\$5 > 85 {print \$0}' | grep -q . && echo "DISK ALERT: \$(df -h)" >> ${LOGS}/disk-alerts.log

# K8s pod restart monitor (every 10 min)
*/10 * * * * kubectl get pods --all-namespaces --no-headers 2>/dev/null | awk '\$5 > 5 {print}' >> ${LOGS}/k8s-restarts.log 2>&1 || true

# Clean old docker images (Sunday 05:00)
0 5 * * 0 docker image prune -af --filter "until=168h" >> ${LOGS}/docker-cleanup.log 2>&1

# Clean old containers (daily 00:30)
30 0 * * * docker container prune -f >> ${LOGS}/docker-cleanup.log 2>&1

# Prometheus TSDB compaction check (daily 06:00)
0 6 * * * curl -s -XPOST http://localhost:9090/-/reload >> ${LOGS}/prometheus-reload.log 2>&1

# Archive old health reports (weekly Sunday 03:00)
0 3 * * 0 find ${LOGS} -name "health-*.json" -mtime +7 -exec gzip {} \; 2>/dev/null || true

EOF
)

# Install crontab (preserving existing entries)
log "Installing cron jobs..."

# Get existing crontab (ignore error if empty)
EXISTING=$(crontab -l 2>/dev/null | grep -v "# DevOps Infrastructure Cron Jobs" | grep -v "Managed by:" || true)

# Combine and install
(echo "$EXISTING"; echo "$CRONTAB_ENTRIES") | crontab -

success "Cron jobs installed successfully"
echo ""
log "Current crontab:"
crontab -l | grep -v "^#" | grep -v "^$" | while read -r line; do
  echo "  $line"
done
