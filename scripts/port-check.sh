#!/usr/bin/env bash
# =============================================================================
# port-check.sh - Quick port availability checker
# Usage: ./port-check.sh [--used|--free|--service=NAME]
# =============================================================================
set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# Service port map: "SERVICE:PORT:DESCRIPTION"
declare -a SERVICES=(
  "k3s-api:6443:Kubernetes API Server"
  "docker-registry:5000:Docker Registry"
  "postgres:5432:PostgreSQL 15"
  "mysql:3306:MySQL 8.0"
  "redis:6379:Redis 7"
  "mongodb:27017:MongoDB 6"
  "prometheus:9090:Prometheus"
  "grafana:3000:Grafana"
  "alertmanager:9093:Alertmanager"
  "node-exporter:9100:Node Exporter"
  "cadvisor:8088:cAdvisor"
  "elasticsearch:9200:Elasticsearch 8"
  "kibana:5601:Kibana"
  "logstash-beats:5044:Logstash Beats"
  "logstash-syslog:5000:Logstash Syslog"
  "nginx-http:80:Nginx HTTP"
  "nginx-https:443:Nginx HTTPS"
  "apache:8080:Apache HTTP"
  "jenkins:8081:Jenkins"
  "gitlab-http:8082:GitLab CE"
  "gitlab-ssh:2222:GitLab SSH"
  "argocd:8083:ArgoCD"
  "sonarqube:9000:SonarQube"
  "vault:8200:HashiCorp Vault"
  "consul:8500:Consul"
  "rabbitmq-amqp:5672:RabbitMQ AMQP"
  "rabbitmq-mgmt:15672:RabbitMQ Management"
  "kafka:9092:Apache Kafka"
  "zookeeper:2181:Zookeeper"
  "nexus:8084:Nexus Repository"
  "keycloak:8085:Keycloak"
  "traefik-http:8086:Traefik HTTP"
  "traefik-dashboard:8090:Traefik Dashboard"
  "minio-api:9001:MinIO API"
  "minio-console:9002:MinIO Console"
  "pg-exporter:9187:PostgreSQL Exporter"
  "mysql-exporter:9104:MySQL Exporter"
  "redis-exporter:9121:Redis Exporter"
  "kafka-exporter:9308:Kafka Exporter"
  "nginx-exporter:9113:Nginx Exporter"
)

MODE="${1:-all}"
FILTER_SERVICE=""

if [[ "$1" == "--service="* ]]; then
  FILTER_SERVICE="${1#--service=}"
  MODE="service"
fi

check_port() {
  local port="$1"
  timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null && echo "OPEN" || echo "CLOSED"
}

print_header() {
  echo -e "\n${BOLD}${CYAN}DevOps Infrastructure Port Status${RESET}"
  echo -e "${CYAN}$(printf '%.0s=' {1..70})${RESET}"
  printf "${BOLD}%-25s %-8s %-10s %s${RESET}\n" "SERVICE" "PORT" "STATUS" "DESCRIPTION"
  echo -e "${CYAN}$(printf '%.0s-' {1..70})${RESET}"
}

count_open=0
count_closed=0

print_header

for entry in "${SERVICES[@]}"; do
  IFS=':' read -r name port desc <<< "$entry"

  # Filter if --used or --free or --service
  if [[ "$MODE" == "--used" ]] || [[ "$MODE" == "--free" ]] || [[ "$MODE" == "service" ]]; then
    if [[ "$MODE" == "service" ]] && [[ "$name" != *"$FILTER_SERVICE"* ]]; then
      continue
    fi
  fi

  status=$(check_port "$port")

  if [[ "$MODE" == "--used" ]] && [[ "$status" != "OPEN" ]]; then continue; fi
  if [[ "$MODE" == "--free" ]] && [[ "$status" != "CLOSED" ]]; then continue; fi

  if [[ "$status" == "OPEN" ]]; then
    status_colored="${GREEN}OPEN   ${RESET}"
    ((count_open++))
  else
    status_colored="${RED}CLOSED ${RESET}"
    ((count_closed++))
  fi

  printf "%-25s %-8s %b %s\n" "$name" "$port" "$status_colored" "$desc"
done

echo -e "${CYAN}$(printf '%.0s-' {1..70})${RESET}"
echo -e "Open: ${GREEN}${count_open}${RESET} | Closed/Free: ${RED}${count_closed}${RESET} | Total checked: $((count_open + count_closed))"
echo ""
echo -e "Usage: $0 [--used|--free|--service=NAME]"
echo -e "  --used    Show only ports in use"
echo -e "  --free    Show only free ports"
echo -e "  --service=postgres  Filter by service name"
