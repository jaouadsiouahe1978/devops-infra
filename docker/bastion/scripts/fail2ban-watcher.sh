#!/bin/bash
AUTH_LOG="/var/log/bastion/auth.log"
ALERT_LOG="/var/log/bastion/security-alerts.log"

mkdir -p "$(dirname "$ALERT_LOG")"

alert() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SECURITY] $1" | tee -a "$ALERT_LOG"
}

alert "Watcher démarré — surveillance: $AUTH_LOG"

tail -F "$AUTH_LOG" 2>/dev/null | while read -r line; do
    case "$line" in
        *"Failed password"*|*"Invalid user"*|*"authentication failure"*)
            IP=$(echo "$line" | grep -oP '(\d{1,3}\.){3}\d{1,3}' | tail -1)
            alert "BRUTE_FORCE depuis ${IP:-inconnu}: $line"
            ;;
        *"Accepted publickey"*)
            USER=$(echo "$line" | grep -oP 'for \K\S+')
            IP=$(echo "$line" | grep -oP 'from \K[\d.]+')
            alert "CONNEXION_OK user=${USER:-?} depuis=${IP:-?}"
            ;;
    esac
done
