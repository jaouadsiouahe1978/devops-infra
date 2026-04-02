#!/bin/bash
# Audit logger — chargé pour toutes les sessions SSH interactives
AUDIT_LOG="/var/log/bastion/audit/commands.log"

[[ -z "${SSH_CONNECTION:-}" ]] && return 0
[[ $- != *i* ]] && return 0

CLIENT_IP=$(echo "${SSH_CONNECTION}" | awk '{print $1}')
SESSION_ID="${SSH_TTY:-unknown_tty}"

_bastion_audit_log() {
    local exit_code=$?
    local cmd
    cmd=$(history 1 | sed 's/^[ ]*[0-9]*[ ]*//')
    [[ -z "$cmd" ]] && return
    [[ "$cmd" == "$_LAST_CMD" ]] && return
    _LAST_CMD="$cmd"
    printf '%s | user=%s | src=%s | tty=%s | pwd=%s | exit=%d | cmd=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "${USER}" "${CLIENT_IP}" "${SESSION_ID}" \
        "${PWD}" "${exit_code}" "${cmd}" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

printf '%s | user=%s | src=%s | event=SESSION_OPEN\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${USER}" "${CLIENT_IP}" \
    >> "$AUDIT_LOG" 2>/dev/null || true

trap 'printf "%s | user=%s | src=%s | event=SESSION_CLOSE\n" \
    "$(date +%Y-%m-%d\ %H:%M:%S)" "${USER}" "${CLIENT_IP}" \
    >> '"$AUDIT_LOG"' 2>/dev/null || true' EXIT

export PROMPT_COMMAND="_bastion_audit_log${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
export HISTTIMEFORMAT="%Y-%m-%d %T "
export HISTSIZE=10000
