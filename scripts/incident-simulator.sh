#!/bin/bash
# incident-simulator.sh — Simulateur d'incidents SRE pour l'apprentissage
# Simule 20 types d'incidents courants en production
# Usage: incident-simulator.sh [NUMERO] [--stop] [--list] [--help]
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
INCIDENT_LOG="${LOG_DIR}/incidents.log"
PID_DIR="${INFRA_DIR}/tmp/incidents"

mkdir -p "$LOG_DIR" "$PID_DIR"

# ── Helpers ────────────────────────────────────────────────────────────────────
log_incident() { echo -e "${RED}[INCIDENT]${NC} $(date '+%H:%M:%S') — $*" | tee -a "$INCIDENT_LOG"; }
log_info()     { echo -e "${BLUE}[INFO]${NC}     $*"; }
log_success()  { echo -e "${GREEN}[OK]${NC}       $*"; }
log_warn()     { echo -e "${YELLOW}[WARN]${NC}     $*"; }
separator()    { echo -e "${BLUE}$(printf '─%.0s' {1..60})${NC}"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [NUMERO] [OPTIONS]

Simulateur d'incidents SRE pour la pratique et l'apprentissage.

Options:
  [NUMERO]    Numero de l'incident a lancer (1-20)
  --stop      Arreter tous les incidents en cours
  --list      Lister tous les incidents disponibles
  --help      Afficher cette aide

Exemples:
  $(basename "$0") --list
  $(basename "$0") 1          # Lancer l'incident #1
  $(basename "$0") 7          # Lancer l'incident #7
  $(basename "$0") --stop     # Stopper tous les incidents actifs
EOF
  exit 0
}

# ── Catalogue des 20 incidents ─────────────────────────────────────────────────
declare -A INCIDENT_NAMES=(
  [1]="CPU Spike — Processus consommant 100% CPU"
  [2]="Memory Leak — Fuite memoire progressive"
  [3]="Disk Full — Remplissage du disque"
  [4]="Container Crash Loop — Conteneur Docker en boucle de crash"
  [5]="Network Latency — Latence reseau elevee"
  [6]="DNS Failure — Resolution DNS en echec"
  [7]="Database Connection Pool — Epuisement du pool de connexions"
  [8]="Log Flood — Inondation de logs"
  [9]="OOM Kill — Processus tue par le kernel (Out of Memory)"
  [10]="High Load Average — Charge systeme anormalement elevee"
  [11]="SSL Certificate Expiry — Certificat SSL expirant"
  [12]="Zombie Processes — Accumulation de processus zombies"
  [13]="File Descriptor Exhaustion — Epuisement des descripteurs de fichiers"
  [14]="Swap Exhaustion — Utilisation intensive du swap"
  [15]="Cron Job Failure — Echec de tache cron"
  [16]="Service Restart Loop — Service qui redémarre en boucle"
  [17]="High Error Rate — Taux d'erreurs HTTP eleve"
  [18]="Time Drift — Derive d'horloge systeme"
  [19]="Backup Failure — Echec de sauvegarde"
  [20]="Cascade Failure — Panne en cascade multi-services"
)

declare -A INCIDENT_SEVERITY=(
  [1]="CRITIQUE" [2]="HAUTE" [3]="CRITIQUE" [4]="HAUTE"
  [5]="MOYENNE" [6]="CRITIQUE" [7]="HAUTE" [8]="BASSE"
  [9]="CRITIQUE" [10]="HAUTE" [11]="HAUTE" [12]="BASSE"
  [13]="HAUTE" [14]="HAUTE" [15]="MOYENNE" [16]="HAUTE"
  [17]="HAUTE" [18]="MOYENNE" [19]="HAUTE" [20]="CRITIQUE"
)

declare -A INCIDENT_DURATION=(
  [1]="60s" [2]="120s" [3]="permanent" [4]="30s" [5]="90s"
  [6]="60s" [7]="jusqu'a arret" [8]="jusqu'a arret" [9]="immediate"
  [10]="90s" [11]="immediate" [12]="jusqu'a arret" [13]="jusqu'a arret"
  [14]="jusqu'a arret" [15]="immediate" [16]="jusqu'a arret" [17]="jusqu'a arret"
  [18]="immediate" [19]="immediate" [20]="60s"
)

# ── Afficher la liste ──────────────────────────────────────────────────────────
list_incidents() {
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${BLUE}║         CATALOGUE DES INCIDENTS SRE — 20 SCENARIOS          ║${NC}"
  echo -e "${BOLD}${BLUE}╠════╦══════════╦═══════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${BLUE}║ ## ║ SEVERITE ║ DESCRIPTION                                  ║${NC}"
  echo -e "${BOLD}${BLUE}╠════╬══════════╬═══════════════════════════════════════════════╣${NC}"

  for i in $(seq 1 20); do
    local severity="${INCIDENT_SEVERITY[$i]}"
    local color="${GREEN}"
    [[ "$severity" == "HAUTE"    ]] && color="${YELLOW}"
    [[ "$severity" == "CRITIQUE" ]] && color="${RED}"
    [[ "$severity" == "BASSE"    ]] && color="${CYAN}"

    printf "${BLUE}║${NC} %02d ${BLUE}║${NC} ${color}%-8s${NC} ${BLUE}║${NC} %-44s ${BLUE}║${NC}\n" \
      "$i" "$severity" "${INCIDENT_NAMES[$i]:0:44}"
  done

  echo -e "${BOLD}${BLUE}╚════╩══════════╩═══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Lancer un incident : ${CYAN}$(basename "$0") [NUMERO]${NC}"
  echo -e "  Arreter tout       : ${CYAN}$(basename "$0") --stop${NC}"
  echo ""
}

# ── Afficher les hints post-incident ──────────────────────────────────────────
show_remediation_hints() {
  local num="$1"
  echo ""
  echo -e "${CYAN}┌─ PISTES DE REMEDIATION ─────────────────────────────────────────┐${NC}"
  case "$num" in
    1)  echo "  • Identifier avec : top, htop, ps aux --sort=-%cpu | head"
        echo "  • Kill si necessaire : kill -9 PID"
        echo "  • Analyser les perf events : perf top" ;;
    2)  echo "  • Observer avec : watch -n1 free -h"
        echo "  • Identifier : ps aux --sort=-%mem | head"
        echo "  • Verifier les leaks : valgrind, /proc/PID/smaps" ;;
    3)  echo "  • Verifier : df -h, du -sh /* 2>/dev/null | sort -rh | head"
        echo "  • Nettoyer : journalctl --vacuum-size=500M"
        echo "  • Docker cleanup : docker system prune -f" ;;
    4)  echo "  • Verifier : docker ps -a, docker logs CONTAINER"
        echo "  • Inspecter : docker inspect CONTAINER"
        echo "  • Corriger la config et recreer le conteneur" ;;
    5)  echo "  • Tester : ping, traceroute, mtr TARGET"
        echo "  • Verifier : ss -tuln, iptables -L"
        echo "  • Analyser : tcpdump -i any -n port PORT" ;;
    6)  echo "  • Tester : nslookup google.com, dig @8.8.8.8 google.com"
        echo "  • Verifier /etc/resolv.conf"
        echo "  • Redemarrer : systemctl restart systemd-resolved" ;;
    7)  echo "  • Verifier les connexions : ss -s, netstat -an | grep :5432"
        echo "  • Inspecter Postgres : SELECT count(*) FROM pg_stat_activity"
        echo "  • Augmenter max_connections ou optimiser les requetes" ;;
    8)  echo "  • Identifier : tail -f /var/log/syslog | grep -c ."
        echo "  • Filtrer : journalctl --since '5 minutes ago'"
        echo "  • Limiter les logs dans docker-compose (max-size)" ;;
    9)  echo "  • Verifier dmesg : dmesg | grep -i 'oom'"
        echo "  • Checker /proc/meminfo"
        echo "  • Ajouter des limits dans docker-compose : mem_limit" ;;
    10) echo "  • Voir : uptime, top, vmstat 1 5"
        echo "  • Identifier les processus lourds : ps aux --sort=-pcpu"
        echo "  • I/O wait : iostat -x 1 5" ;;
    11) echo "  • Verifier : openssl s_client -connect HOST:443 2>/dev/null | openssl x509 -noout -dates"
        echo "  • Renouveler : certbot renew ou re-generer avec openssl"
        echo "  • Alerter avant : cert-check.sh --days 30" ;;
    12) echo "  • Lister zombies : ps aux | awk '\$8==\"Z\"'"
        echo "  • Trouver le parent : ps -o ppid= -p ZOMBIE_PID"
        echo "  • Kill le parent pour liberer les zombies" ;;
    13) echo "  • Verifier : ulimit -n, cat /proc/sys/fs/file-max"
        echo "  • Voir utilisation : ls /proc/PID/fd | wc -l"
        echo "  • Augmenter : ulimit -n 65536 ou modifier /etc/security/limits.conf" ;;
    14) echo "  • Verifier : free -h, swapon --show"
        echo "  • Top consumers : vmstat 1, sar -r 1 10"
        echo "  • Desactiver swap si possible : swapoff -a (apres lib memoire)" ;;
    15) echo "  • Verifier : crontab -l, systemctl list-timers"
        echo "  • Logs cron : journalctl -u cron"
        echo "  • Tester manuellement la commande" ;;
    16) echo "  • Voir : systemctl status SERVICE, journalctl -u SERVICE -f"
        echo "  • Verifier le ExecStart et la config"
        echo "  • Ajuster StartLimitIntervalSec et StartLimitBurst" ;;
    17) echo "  • Analyser les logs : grep 'HTTP/.*\" [45]' access.log | wc -l"
        echo "  • Verifier les endpoints : curl -I http://localhost"
        echo "  • Regarder les erreurs applicatives dans les logs" ;;
    18) echo "  • Verifier : timedatectl, chronyc tracking"
        echo "  • Synchroniser : chronyc makestep"
        echo "  • Configurer : /etc/chrony.conf" ;;
    19) echo "  • Verifier le script de backup et ses logs"
        echo "  • Tester manuellement : ~/devops-infra/scripts/backup.sh"
        echo "  • Verifier l'espace disque et les permissions" ;;
    20) echo "  • Identifier le service root cause (la premiere panne)"
        echo "  • Verifier les dependances entre services"
        echo "  • Utiliser un runbook de recuperation par ordre de priorite" ;;
  esac
  echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
}

# ── Stopper tous les incidents ────────────────────────────────────────────────
stop_all_incidents() {
  log_info "Arret de tous les incidents en cours..."
  local stopped=0

  if ls "${PID_DIR}"/*.pid &>/dev/null 2>&1; then
    for pidfile in "${PID_DIR}"/*.pid; do
      local pid
      pid=$(cat "$pidfile" 2>/dev/null || echo "")
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        log_success "Processus $pid termine ($(basename "$pidfile" .pid))"
        stopped=$((stopped + 1))
      fi
      rm -f "$pidfile"
    done
  fi

  # Nettoyer les stress-ng ou processus de simulation
  pkill -f "stress-ng"    2>/dev/null || true
  pkill -f "incident-sim" 2>/dev/null || true
  pkill -f "dd if=/dev/zero" 2>/dev/null || true
  pkill -f "nc -l.*incident" 2>/dev/null || true

  log_success "Nettoyage termine. $stopped processus arretes."
}

# ══════════════════════════════════════════════════════════════════════════════
# INCIDENTS
# ══════════════════════════════════════════════════════════════════════════════

incident_01_cpu_spike() {
  log_incident "CPU SPIKE — Lancement d'une charge CPU de 60 secondes"
  log_info "Simulation : 1 processus stress sur 1 CPU pendant 60s"
  log_info "Commandes de diagnostic :"
  echo "  top -bn1 | head -20"
  echo "  ps aux --sort=-%cpu | head -5"
  echo "  htop (si installe)"

  if command -v stress-ng &>/dev/null; then
    stress-ng --cpu 1 --timeout 60s --quiet &
    echo $! > "${PID_DIR}/cpu_spike.pid"
    log_success "stress-ng lance (PID: $!). Duree: 60s"
  elif command -v stress &>/dev/null; then
    stress --cpu 1 --timeout 60 &
    echo $! > "${PID_DIR}/cpu_spike.pid"
    log_success "stress lance (PID: $!). Duree: 60s"
  else
    # Fallback: boucle infinie bash
    (while true; do :; done) &
    echo $! > "${PID_DIR}/cpu_spike.pid"
    local pid=$!
    log_warn "stress-ng non installe. Boucle bash lancee (PID: $pid)"
    log_info "Elle sera automatiquement stoppee dans 60s..."
    (sleep 60; kill "$pid" 2>/dev/null || true) &
  fi
}

incident_02_memory_leak() {
  log_incident "MEMORY LEAK — Consommation progressive de memoire"
  log_info "Simulation : allocation memoire croissante sur 120s"
  log_info "Commandes de diagnostic :"
  echo "  watch -n2 free -h"
  echo "  ps aux --sort=-%mem | head -5"

  # Allouer de la memoire progressivement via /dev/shm ou tmpfs
  (
    TMPFILE=$(mktemp /tmp/memleak_XXXXXX)
    echo $$ > "${PID_DIR}/memory_leak.pid"
    for i in $(seq 1 12); do
      dd if=/dev/zero bs=10M count=1 >> "$TMPFILE" 2>/dev/null
      sleep 10
    done
    rm -f "$TMPFILE"
  ) &
  log_success "Simulation memory leak lancee (PID: $!). Duree: ~120s"
}

incident_03_disk_full() {
  log_incident "DISK FULL — Remplissage progressif d'un fichier de test"
  log_info "ATTENTION : Simulation securisee dans /tmp/incident_disk_test"
  log_info "Commandes de diagnostic :"
  echo "  df -h"
  echo "  du -sh /tmp/incident_disk_test"
  echo "  Supprimer avec : rm -f /tmp/incident_disk_test"

  local test_file="/tmp/incident_disk_test"
  local free_kb
  free_kb=$(df /tmp | awk 'NR==2 {print $4}')
  local fill_kb=$(( free_kb / 10 ))  # Remplir 10% de /tmp

  log_warn "Creation d'un fichier de $(( fill_kb / 1024 )) MB dans /tmp..."
  (dd if=/dev/zero of="$test_file" bs=1M count=$(( fill_kb / 1024 )) 2>/dev/null; \
   echo $$ > "${PID_DIR}/disk_full.pid") &
  log_success "Fichier de remplissage cree. Supprimez-le avec : rm -f $test_file"
}

incident_04_container_crash() {
  log_incident "CONTAINER CRASH LOOP — Simulation d'un crash loop Docker"
  log_info "Simulation : lancement d'un conteneur qui crash immediatement"
  log_info "Commandes de diagnostic :"
  echo "  docker ps -a"
  echo "  docker logs incident-crash-loop"
  echo "  docker inspect incident-crash-loop"

  if command -v docker &>/dev/null; then
    docker rm -f incident-crash-loop 2>/dev/null || true
    docker run -d --name incident-crash-loop \
      --restart on-failure:5 \
      alpine sh -c "echo 'Starting...'; sleep 2; echo 'CRASH'; exit 1" 2>/dev/null
    log_success "Conteneur incident-crash-loop lance en crash loop"
    log_warn "Le conteneur va redemarrer 5 fois puis s'arreter"
    log_info "Nettoyage : docker rm -f incident-crash-loop"
  else
    log_warn "Docker non disponible. Simulation de logs uniquement."
    for i in $(seq 1 5); do
      echo "[$(date '+%H:%M:%S')] Conteneur 'app' demo en crash loop (tentative $i/5)"
      sleep 2
    done
  fi
}

incident_05_network_latency() {
  log_incident "NETWORK LATENCY — Simulation de latence reseau elevee"
  log_info "Simulation : 500ms de latence ajoutee sur lo (si tc disponible)"
  log_info "Commandes de diagnostic :"
  echo "  ping -c 5 localhost"
  echo "  tc qdisc show dev lo"
  echo "  mtr --report localhost"

  if command -v tc &>/dev/null; then
    log_warn "Ajout de 500ms de latence sur l'interface loopback..."
    sudo tc qdisc add dev lo root netem delay 500ms 2>/dev/null || \
      log_warn "Permission insuffisante. Simuler avec : sudo tc qdisc add dev lo root netem delay 500ms"
    (sleep 90; sudo tc qdisc del dev lo root 2>/dev/null || true) &
    echo $! > "${PID_DIR}/network_latency.pid"
    log_success "Latence ajoutee. Suppression automatique dans 90s"
    log_info "Suppression manuelle : sudo tc qdisc del dev lo root"
  else
    log_warn "tc (iproute2) non disponible. Affichage des commandes de simulation :"
    echo "  sudo tc qdisc add dev eth0 root netem delay 500ms"
    echo "  sudo tc qdisc del dev eth0 root  # Pour supprimer"
  fi
}

incident_06_dns_failure() {
  log_incident "DNS FAILURE — Simulation d'une panne DNS"
  log_info "Simulation : modification temporaire de /etc/resolv.conf"
  log_info "Commandes de diagnostic :"
  echo "  nslookup google.com"
  echo "  dig @8.8.8.8 google.com"
  echo "  cat /etc/resolv.conf"

  log_warn "Sauvegarde de /etc/resolv.conf..."
  sudo cp /etc/resolv.conf /tmp/resolv.conf.bak 2>/dev/null || \
    cp /etc/resolv.conf /tmp/resolv.conf.bak 2>/dev/null || true

  log_warn "Remplacement du DNS par une IP invalide (simulation)..."
  echo "Commande qui serait executee (avec sudo) :"
  echo "  echo 'nameserver 192.0.2.1' | sudo tee /etc/resolv.conf"
  echo "  # Restoration : sudo cp /tmp/resolv.conf.bak /etc/resolv.conf"
  log_warn "SIMULATION SANS EXECUTION pour eviter de casser la connectivite DNS"
  log_info "En conditions reelles, executer : sudo bash -c 'echo nameserver 192.0.2.1 > /etc/resolv.conf'"
  log_info "Restoration : sudo cp /tmp/resolv.conf.bak /etc/resolv.conf"
}

incident_07_db_connection_pool() {
  log_incident "DB CONNECTION POOL — Epuisement du pool de connexions"
  log_info "Simulation : ouverture de multiples connexions TCP vers PostgreSQL"
  log_info "Commandes de diagnostic :"
  echo "  ss -s | grep -i estab"
  echo "  SELECT count(*) FROM pg_stat_activity;  # Dans psql"
  echo "  watch -n2 'ss -tn | grep :5432 | wc -l'"

  local pids=()
  for i in $(seq 1 50); do
    (nc -z localhost 5432 &>/dev/null; sleep 30) &
    pids+=($!)
  done

  printf '%s\n' "${pids[@]}" > "${PID_DIR}/db_pool.pid"
  log_success "50 connexions simulees vers le port 5432. Duree: 30s"
  log_warn "Nettoyage : $(basename "$0") --stop"
}

incident_08_log_flood() {
  log_incident "LOG FLOOD — Generation massive de logs"
  log_info "Simulation : ecriture rapide dans le fichier de log"
  log_info "Commandes de diagnostic :"
  echo "  tail -f ${INCIDENT_LOG}"
  echo "  journalctl -f"
  echo "  du -sh ${LOG_DIR}"

  local flood_log="${LOG_DIR}/flood_test.log"
  (
    echo $$ > "${PID_DIR}/log_flood.pid"
    local count=0
    while [[ $count -lt 10000 ]]; do
      echo "[$(date '+%H:%M:%S.%N')] ERROR app.service - Simulated error flood event #${count} - NullPointerException at com.example.Service.process(Service.java:142)" >> "$flood_log"
      count=$((count + 1))
    done
    echo "Log flood termine. $count lignes ecrites dans $flood_log"
  ) &
  log_success "Flood de logs lance. Fichier : $flood_log"
  log_info "Nettoyage : rm -f $flood_log"
}

incident_09_oom() {
  log_incident "OOM KILL — Simulation d'un evenement Out of Memory"
  log_info "Simulation informative — affichage des evenements OOM passes"
  log_info "Commandes de diagnostic :"
  echo "  dmesg | grep -i 'oom'"
  echo "  journalctl -k | grep -i 'oom'"
  echo "  cat /proc/meminfo"
  echo "  grep -i oom /var/log/syslog 2>/dev/null || true"

  log_warn "Lecture des evenements OOM du kernel..."
  if dmesg 2>/dev/null | grep -qi "oom"; then
    log_warn "Evenements OOM trouves :"
    dmesg 2>/dev/null | grep -i "oom" | tail -5
  else
    log_info "Aucun evenement OOM recent dans dmesg"
  fi

  log_info "Pour simuler un OOM reel (DANGEREUX), on utiliserait :"
  echo "  # Allouer toute la memoire disponible :"
  echo "  python3 -c \"a = []; [(a.append('x' * 1024 * 1024)) for _ in range(99999)]\""
  echo "  # NE PAS executer sur un systeme de production !"
}

incident_10_high_load() {
  log_incident "HIGH LOAD AVERAGE — Simulation d'une charge elevee"
  log_info "Simulation : lancement de multiples processus CPU-intensifs (90s)"
  log_info "Commandes de diagnostic :"
  echo "  uptime"
  echo "  top"
  echo "  vmstat 1 5"
  echo "  iostat -x 1 5"

  local ncpus
  ncpus=$(nproc 2>/dev/null || echo 2)
  local stress_count=$((ncpus * 2))

  if command -v stress-ng &>/dev/null; then
    stress-ng --cpu "$stress_count" --timeout 90s --quiet &
    echo $! > "${PID_DIR}/high_load.pid"
    log_success "stress-ng lance avec $stress_count workers CPU. Duree: 90s"
  else
    log_warn "stress-ng non installe. Simulation avec boucles bash..."
    for i in $(seq 1 "$stress_count"); do
      (end=$((SECONDS + 90)); while [[ $SECONDS -lt $end ]]; do :; done) &
      echo $! >> "${PID_DIR}/high_load.pid"
    done
    log_success "$stress_count boucles CPU lancees. Duree: 90s"
  fi
}

incident_11_ssl_expiry() {
  log_incident "SSL CERTIFICATE EXPIRY — Verification des certificats expirants"
  log_info "Simulation : affichage des certificats proches de l'expiration"
  log_info "Commandes de diagnostic :"
  echo "  openssl s_client -connect HOST:443 2>/dev/null | openssl x509 -noout -dates"
  echo "  ~/devops-infra/scripts/cert-check.sh"

  local cert_dir="${INFRA_DIR}/certs"
  if ls "${cert_dir}"/*.crt &>/dev/null 2>&1; then
    for cert in "${cert_dir}"/*.crt; do
      local expiry
      expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2 || echo "Inconnu")
      local days_left
      days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
      if [[ $days_left -lt 30 ]]; then
        log_warn "CERTIFICAT EXPIRANT : $(basename "$cert") - Expire dans ${days_left}j (${expiry})"
      else
        log_info "OK : $(basename "$cert") - Expire dans ${days_left}j"
      fi
    done
  else
    log_warn "Aucun certificat trouve dans $cert_dir"
    log_info "Generer des certificats : ~/devops-infra/scripts/generate-certs.sh"

    # Simuler un certificat expire
    local fake_cert
    fake_cert=$(openssl req -x509 -newkey rsa:2048 -keyout /tmp/fake.key \
      -out /tmp/fake.crt -days 1 -nodes \
      -subj "/CN=expiring-soon.local" 2>/dev/null && echo "/tmp/fake.crt" || echo "")
    if [[ -n "$fake_cert" ]]; then
      local expiry
      expiry=$(openssl x509 -enddate -noout -in "$fake_cert" 2>/dev/null | cut -d= -f2 || echo "")
      log_warn "Certificat test genere — expire le : $expiry"
      rm -f /tmp/fake.crt /tmp/fake.key
    fi
  fi
}

incident_12_zombie_processes() {
  log_incident "ZOMBIE PROCESSES — Creation de processus zombies"
  log_info "Simulation : creation de 5 processus zombies"
  log_info "Commandes de diagnostic :"
  echo "  ps aux | awk '\$8==\"Z\"'"
  echo "  ps -eo pid,ppid,stat,comm | grep Z"

  (
    echo $$ > "${PID_DIR}/zombies.pid"
    for i in $(seq 1 5); do
      (exit 0) &   # Enfant qui termine sans wait() du parent = zombie temporaire
    done
    sleep 30       # Garder le parent vivant pour maintenir les zombies
  ) &
  log_success "Processus zombies crees. Ils disparaitront dans 30s ou avec --stop"
}

incident_13_fd_exhaustion() {
  log_incident "FILE DESCRIPTOR EXHAUSTION — Epuisement des descripteurs"
  log_info "Simulation : affichage de l'utilisation actuelle des FD"
  log_info "Commandes de diagnostic :"
  echo "  ulimit -n"
  echo "  cat /proc/sys/fs/file-max"
  echo "  ls /proc/\$(pgrep -f 'myapp' | head -1)/fd | wc -l"
  echo "  lsof | wc -l"

  local current_max
  current_max=$(ulimit -n 2>/dev/null || echo "inconnu")
  local sys_max
  sys_max=$(cat /proc/sys/fs/file-max 2>/dev/null || echo "inconnu")
  local current_open
  current_open=$(ls /proc/self/fd 2>/dev/null | wc -l || echo "inconnu")

  log_info "Limite FD du shell actuel : $current_max"
  log_info "Limite FD systeme : $sys_max"
  log_info "FD ouverts par ce processus : $current_open"
  log_warn "Pour simuler l'epuisement : ulimit -n 50 && for i in \$(seq 1 100); do exec {fd}<>/dev/null; done"
}

incident_14_swap_exhaustion() {
  log_incident "SWAP EXHAUSTION — Utilisation intensive du swap"
  log_info "Simulation : affichage de l'utilisation du swap et generation de pression memoire"
  log_info "Commandes de diagnostic :"
  echo "  free -h"
  echo "  swapon --show"
  echo "  vmstat 1 5"
  echo "  cat /proc/meminfo | grep -i swap"

  log_info "Etat actuel du swap :"
  free -h 2>/dev/null | grep -i swap || log_warn "Swap non configure"
  swapon --show 2>/dev/null || log_warn "Aucun swap actif"

  log_warn "Pour stresser le swap (simulation legere):"
  echo "  Si stress-ng disponible : stress-ng --vm 2 --vm-bytes 80% --timeout 30s"
}

incident_15_cron_failure() {
  log_incident "CRON JOB FAILURE — Simulation d'un echec de tache planifiee"
  log_info "Simulation : creation d'un cron job qui echoue et suppression"
  log_info "Commandes de diagnostic :"
  echo "  crontab -l"
  echo "  journalctl -u cron"
  echo "  grep CRON /var/log/syslog 2>/dev/null | tail -20"

  local fake_script="/tmp/incident_cron_fail.sh"
  cat > "$fake_script" <<'CRONSCRIPT'
#!/bin/bash
# Script de test qui echoue intentionnellement
echo "[$(date)] CRON: Demarrage de la tache de backup..."
sleep 2
echo "[$(date)] CRON: ERREUR - Connexion a la base de donnees echouee" >&2
exit 1
CRONSCRIPT
  chmod +x "$fake_script"

  bash "$fake_script" 2>/dev/null || true
  log_warn "Tache cron simulee : ECHEC (code retour: 1)"
  log_info "Script de test : $fake_script"
  log_info "Dans un vrai cron, cela enverrait un email a root@localhost"
}

incident_16_service_restart_loop() {
  log_incident "SERVICE RESTART LOOP — Service qui redémarre en boucle"
  log_info "Simulation : logs d'un service en restart loop"
  log_info "Commandes de diagnostic :"
  echo "  systemctl status myapp.service"
  echo "  journalctl -u myapp.service -f"
  echo "  systemctl is-failed myapp.service"

  local loop_log="${LOG_DIR}/service_restart_loop.log"
  (
    echo $$ > "${PID_DIR}/restart_loop.pid"
    for attempt in $(seq 1 10); do
      echo "[$(date '+%H:%M:%S')] [myapp.service] Starting (attempt $attempt/10)..." >> "$loop_log"
      sleep 1
      echo "[$(date '+%H:%M:%S')] [myapp.service] FAILED: Cannot connect to database" >> "$loop_log"
      echo "[$(date '+%H:%M:%S')] [myapp.service] Restarting in 5s..." >> "$loop_log"
      sleep 3
    done
    echo "[$(date '+%H:%M:%S')] [myapp.service] Start request repeated too quickly, refusing to start." >> "$loop_log"
  ) &
  log_success "Simulation restart loop lancee. Logs : $loop_log"
  log_info "Suivre en temps reel : tail -f $loop_log"
}

incident_17_high_error_rate() {
  log_incident "HIGH ERROR RATE — Simulation d'un taux d'erreurs HTTP eleve"
  log_info "Simulation : generation de logs d'acces avec erreurs HTTP 500"
  log_info "Commandes de diagnostic :"
  echo "  grep '\" 5' /var/log/nginx/access.log | wc -l"
  echo "  awk '\$9>=500' access.log | wc -l"

  local error_log="${LOG_DIR}/http_errors.log"
  (
    echo $$ > "${PID_DIR}/error_rate.pid"
    local count=0
    while [[ $count -lt 200 ]]; do
      local ip="10.0.$(( RANDOM % 256 )).$(( RANDOM % 256 ))"
      local ts
      ts=$(date '+%d/%b/%Y:%H:%M:%S +0000')
      local status
      if [[ $(( RANDOM % 10 )) -lt 7 ]]; then
        status=500
      else
        status=200
      fi
      echo "${ip} - - [${ts}] \"GET /api/v1/users HTTP/1.1\" ${status} 1234 \"-\" \"Mozilla/5.0\"" >> "$error_log"
      count=$((count + 1))
      sleep 0.1
    done
  ) &
  log_success "200 requetes HTTP simulees (70% d'erreurs 500). Logs : $error_log"
  log_info "Taux d'erreur : grep '\" 500' $error_log | wc -l"
}

incident_18_time_drift() {
  log_incident "TIME DRIFT — Verification de la derive d'horloge"
  log_info "Simulation : affichage de l'etat NTP/chrony"
  log_info "Commandes de diagnostic :"
  echo "  timedatectl"
  echo "  chronyc tracking"
  echo "  ntpdate -q pool.ntp.org 2>/dev/null"
  echo "  date"

  timedatectl 2>/dev/null | grep -E "Local time|NTP|Time zone" || \
    log_warn "timedatectl non disponible"

  if command -v chronyc &>/dev/null; then
    log_info "Etat Chrony :"
    chronyc tracking 2>/dev/null | grep -E "Reference|Offset|RMS" || true
  else
    log_warn "chrony non installe. Verifier ntpd : systemctl status ntp 2>/dev/null || true"
  fi
}

incident_19_backup_failure() {
  log_incident "BACKUP FAILURE — Simulation d'un echec de sauvegarde"
  log_info "Simulation : backup PostgreSQL vers une destination invalide"
  log_info "Commandes de diagnostic :"
  echo "  ls -lht ~/devops-infra/backups/postgres/ | head -5"
  echo "  tail -50 ~/devops-infra/logs/backup.log"

  local backup_log="${LOG_DIR}/backup_failure.log"
  {
    echo "[$(date '+%H:%M:%S')] INFO  Demarrage du backup PostgreSQL..."
    echo "[$(date '+%H:%M:%S')] INFO  Connexion a postgres://localhost:5432/devopsdb"
    sleep 1
    echo "[$(date '+%H:%M:%S')] ERROR pg_dump: error: connection to server on socket..."
    echo "[$(date '+%H:%M:%S')] ERROR FATAL: password authentication failed for user 'backup'"
    echo "[$(date '+%H:%M:%S')] ERROR Backup ECHOUE - code retour: 1"
    echo "[$(date '+%H:%M:%S')] WARN  Aucune sauvegarde creee pour devopsdb"
  } | tee "$backup_log"

  log_warn "Backup simule en echec. Log : $backup_log"
  log_info "Pour tester le vrai backup : ~/devops-infra/scripts/backup.sh"
}

incident_20_cascade_failure() {
  log_incident "CASCADE FAILURE — Panne en cascade multi-services"
  log_info "Simulation : affichage d'une sequence de pannes en cascade"
  log_info "Commandes de diagnostic :"
  echo "  ~/devops-infra/scripts/health-check.sh"
  echo "  docker ps -a"
  echo "  journalctl --since '10 minutes ago'"

  echo ""
  log_warn "=== DEBUT DE PANNE EN CASCADE ==="

  local events=(
    "PostgreSQL: Connexions max atteintes (100/100)"
    "API Gateway: Timeout sur les requetes DB (>30s)"
    "Cache Redis: Cache-miss 100% - PostgreSQL inaccessible"
    "Microservice Auth: 503 Service Unavailable"
    "Microservice Orders: Echec d'authentification en cascade"
    "Load Balancer: 80% des backends en erreur"
    "Monitoring: Alertes Prometheus declenchees (15 alertes)"
    "Queue Kafka: Accumulation de messages (lag: 50000)"
    "Workers: Arret des consumers Kafka (echec d'auth)"
  )

  for event in "${events[@]}"; do
    sleep 1
    echo -e "  ${RED}[$(date '+%H:%M:%S')]${NC} INCIDENT: $event" | tee -a "${LOG_DIR}/cascade.log"
  done

  echo ""
  log_warn "=== ANALYSE ROOT CAUSE ==="
  echo -e "  La cause racine est ${CYAN}PostgreSQL${NC} (connexions epuisees)"
  echo -e "  Ordre de remediation recommande :"
  echo "    1. Redemarrer PostgreSQL et liberer les connexions"
  echo "    2. Verifier et scaler le connection pooler (PgBouncer)"
  echo "    3. Redemarrer le service Auth"
  echo "    4. Verifier que l'API Gateway recupere"
  echo "    5. Relancer les consumers Kafka"
  echo ""
  log_info "Log de la cascade : ${LOG_DIR}/cascade.log"
}

# ══════════════════════════════════════════════════════════════════════════════
# MENU INTERACTIF
# ══════════════════════════════════════════════════════════════════════════════

interactive_menu() {
  while true; do
    echo ""
    echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${MAGENTA}║         SIMULATEUR D'INCIDENTS SRE — MENU               ║${NC}"
    echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}[l]${NC} Lister tous les incidents"
    echo -e "  ${CYAN}[1-20]${NC} Lancer un incident par numero"
    echo -e "  ${CYAN}[s]${NC} Stopper tous les incidents actifs"
    echo -e "  ${CYAN}[q]${NC} Quitter"
    echo ""
    read -rp "Votre choix : " choice

    case "$choice" in
      l|L|list) list_incidents ;;
      s|S|stop) stop_all_incidents ;;
      q|Q|quit) log_info "Au revoir !"; exit 0 ;;
      [0-9]|[1-9][0-9])
        if [[ "$choice" -ge 1 && "$choice" -le 20 ]]; then
          launch_incident "$choice"
        else
          log_warn "Numero invalide. Choisissez entre 1 et 20."
        fi
        ;;
      *) log_warn "Choix invalide : '$choice'" ;;
    esac
  done
}

launch_incident() {
  local num="$1"
  separator
  echo -e "${RED}${BOLD}INCIDENT #${num} : ${INCIDENT_NAMES[$num]}${NC}"
  echo -e "Severite : ${YELLOW}${INCIDENT_SEVERITY[$num]}${NC}  |  Duree : ${CYAN}${INCIDENT_DURATION[$num]}${NC}"
  separator
  log_incident "Lancement de l'incident #${num} — ${INCIDENT_NAMES[$num]}"

  case "$num" in
    1)  incident_01_cpu_spike ;;
    2)  incident_02_memory_leak ;;
    3)  incident_03_disk_full ;;
    4)  incident_04_container_crash ;;
    5)  incident_05_network_latency ;;
    6)  incident_06_dns_failure ;;
    7)  incident_07_db_connection_pool ;;
    8)  incident_08_log_flood ;;
    9)  incident_09_oom ;;
    10) incident_10_high_load ;;
    11) incident_11_ssl_expiry ;;
    12) incident_12_zombie_processes ;;
    13) incident_13_fd_exhaustion ;;
    14) incident_14_swap_exhaustion ;;
    15) incident_15_cron_failure ;;
    16) incident_16_service_restart_loop ;;
    17) incident_17_high_error_rate ;;
    18) incident_18_time_drift ;;
    19) incident_19_backup_failure ;;
    20) incident_20_cascade_failure ;;
  esac

  show_remediation_hints "$num"
  separator
  echo ""
}

# ── Parse args et dispatch ─────────────────────────────────────────────────────
main() {
  if [[ $# -eq 0 ]]; then
    interactive_menu
    return
  fi

  case "$1" in
    --list|-l)   list_incidents ;;
    --stop|-s)   stop_all_incidents ;;
    --help|-h)   usage ;;
    [0-9]|[1-9][0-9])
      local num="$1"
      if [[ "$num" -ge 1 && "$num" -le 20 ]]; then
        launch_incident "$num"
      else
        log_error "Numero invalide : $num (valide : 1-20)"
        exit 1
      fi
      ;;
    *)
      log_error "Argument inconnu : $1"
      usage
      ;;
  esac
}

main "$@"
