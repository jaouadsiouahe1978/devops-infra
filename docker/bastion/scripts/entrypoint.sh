#!/bin/bash
set -euo pipefail

LOG=/var/log/bastion
AUDIT_LOG=$LOG/audit/commands.log

# 1. Initialiser les répertoires
mkdir -p "$LOG/audit" /run/sshd /run/fail2ban
touch "$AUDIT_LOG" "$LOG/fail2ban.log" "$LOG/auth.log"
chown -R devops:devops "$LOG/audit"
ln -sf "$LOG/auth.log" /var/log/auth.log 2>/dev/null || true

# 2. Setup authorized_keys
DEVOPS_HOME=$(getent passwd devops | cut -d: -f6)
mkdir -p "$DEVOPS_HOME/.ssh"
chmod 700 "$DEVOPS_HOME/.ssh"

if [[ -n "${SSH_AUTHORIZED_KEYS:-}" ]]; then
    echo "$SSH_AUTHORIZED_KEYS" > "$DEVOPS_HOME/.ssh/authorized_keys"
elif [[ -f /authorized_keys ]]; then
    cp /authorized_keys "$DEVOPS_HOME/.ssh/authorized_keys"
fi
chmod 600 "$DEVOPS_HOME/.ssh/authorized_keys" 2>/dev/null || true
chown -R devops:devops "$DEVOPS_HOME/.ssh"

# 3. Configurer kubectl
if [[ -f /k3s-kubeconfig/k3s.yaml ]]; then
    mkdir -p "$DEVOPS_HOME/.kube"
    DOCKER_HOST_IP="${DOCKER_HOST_IP:-172.17.0.1}"
    sed "s|https://127.0.0.1:6443|https://${DOCKER_HOST_IP}:6443|g" \
        /k3s-kubeconfig/k3s.yaml > "$DEVOPS_HOME/.kube/config"
    chmod 600 "$DEVOPS_HOME/.kube/config"
    chown -R devops:devops "$DEVOPS_HOME/.kube"
    echo "[bastion] kubectl -> https://${DOCKER_HOST_IP}:6443"
fi

# 4. Démarrer fail2ban
if command -v fail2ban-server &>/dev/null; then
    if ! iptables -L &>/dev/null 2>&1; then
        sed -i 's/banaction = iptables-multiport/banaction = dummy/' /etc/fail2ban/jail.local 2>/dev/null || true
        echo "[bastion] fail2ban: mode logging (iptables non dispo sur WSL2)"
    fi
    fail2ban-server -b -s /run/fail2ban/fail2ban.sock \
        -p /run/fail2ban/fail2ban.pid \
        -l "$LOG/fail2ban.log" 2>/dev/null \
        && echo "[bastion] fail2ban démarré" \
        || echo "[bastion] fail2ban non disponible"
fi

# 5. Démarrer le watcher sécurité
/usr/local/bin/fail2ban-watcher.sh &

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       BASTION HOST DÉMARRÉ               ║"
echo "║  SSH     : port 22 (clé + MFA)           ║"
echo "║  Audit   : $AUDIT_LOG"
echo "╚══════════════════════════════════════════╝"
echo ""

# 6. Lancer sshd en foreground (PID 1)
exec /usr/sbin/sshd -D -e
