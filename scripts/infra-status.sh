#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null)

status() {
    if echo "$running_containers" | grep -qx "$1"; then
        echo -e "${GREEN}UP${NC}"
    else
        echo -e "${RED}DOWN${NC}"
    fi
}

pad() {
    printf "%-22s" "$1"
}

section() {
    echo -e "\n${BOLD}${CYAN}$1${NC}"
    echo "────────────────────────────────────────────────────────"
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         DEVOPS-INFRA — ÉTAT DE L'INFRASTRUCTURE      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"

section "MONITORING"
printf "  $(pad 'prometheus')$(status prometheus)   $(pad 'grafana')$(status grafana)\n"
printf "  $(pad 'alertmanager')$(status alertmanager)   $(pad 'blackbox-exporter')$(status blackbox-exporter)\n"
printf "  $(pad 'node-exporter')$(status node-exporter)   $(pad 'cadvisor')$(status cadvisor)\n"
printf "  $(pad 'loki')$(status loki)   $(pad 'promtail')$(status promtail)\n"

section "BASES DE DONNÉES"
printf "  $(pad 'postgres')$(status postgres)   $(pad 'mysql')$(status mysql)\n"
printf "  $(pad 'redis')$(status redis)   $(pad 'mongodb')$(status mongodb)\n"

section "LOGS (ELK)"
printf "  $(pad 'elasticsearch')$(status elasticsearch)   $(pad 'kibana')$(status kibana)\n"
printf "  $(pad 'logstash')$(status logstash)\n"

section "CI/CD"
printf "  $(pad 'jenkins')$(status jenkins)   $(pad 'gitea')$(status gitea)\n"
printf "  $(pad 'argocd')$(status argocd)\n"

section "MESSAGING"
printf "  $(pad 'kafka')$(status kafka)   $(pad 'zookeeper')$(status zookeeper)\n"
printf "  $(pad 'rabbitmq')$(status rabbitmq)\n"

section "NETWORKING"
printf "  $(pad 'traefik')$(status traefik)   $(pad 'nginx-proxy')$(status nginx-proxy)\n"
printf "  $(pad 'haproxy')$(status haproxy)\n"

section "SÉCURITÉ"
printf "  $(pad 'vault')$(status vault)   $(pad 'consul')$(status consul)\n"
printf "  $(pad 'keycloak')$(status keycloak)\n"

section "STOCKAGE"
printf "  $(pad 'minio')$(status minio)   $(pad 'nexus')$(status nexus)\n"
printf "  $(pad 'registry')$(status registry)\n"

section "OUTILS"
printf "  $(pad 'portainer')$(status portainer)   $(pad 'pgadmin')$(status pgadmin)\n"
printf "  $(pad 'sonarqube')$(status sonarqube)   $(pad 'kafka-ui')$(status kafka-ui)\n"
printf "  $(pad 'redisinsight')$(status redisinsight)   $(pad 'adminer')$(status adminer)\n"

echo ""
echo -e "${BOLD}────────────────────────────────────────────────────────${NC}"
total=$(echo "$running_containers" | grep -c . 2>/dev/null || echo 0)
echo -e "  Conteneurs actifs : ${GREEN}${BOLD}${total}${NC}"
echo ""
