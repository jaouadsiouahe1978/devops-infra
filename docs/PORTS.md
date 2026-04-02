# Port Mapping Reference

> Complete port reference for all 40+ services in the DevOps/SRE local infrastructure.
> Last updated: 2026-04-01

---

## Table of Contents

1. [Complete Port Reference Table](#1-complete-port-reference-table)
2. [Quick Access URLs](#2-quick-access-urls)
3. [Profile Groups](#3-profile-groups)
4. [Port Range Legend](#4-port-range-legend)
5. [Conflict Detection](#5-conflict-detection)

---

## 1. Complete Port Reference Table

### Kubernetes

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| K3s API Server | 6443 | HTTPS | k8s | /readyz | `kubectl cluster-info` |
| K3s Metrics | 10250 | HTTPS | k8s | /metrics | kubelet metrics |
| CoreDNS | 53 | TCP/UDP | k8s | N/A | cluster DNS |
| Flannel VXLAN | 8472 | UDP | k8s | N/A | pod networking |

### Databases

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| PostgreSQL | 5432 | TCP | databases | `pg_isready -U postgres` | v15, user: postgres |
| MySQL | 3306 | TCP | databases | `mysqladmin ping -u root` | v8.0, user: root |
| Redis | 6379 | TCP | databases | `redis-cli ping` | v7, no auth (dev) |
| MongoDB | 27017 | TCP | databases | `mongosh --eval "db.ping()"` | v6, user: mongo |

### Monitoring

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| Prometheus | 9090 | HTTP | monitoring | `/-/healthy` | 15-day retention |
| Grafana | 3000 | HTTP | monitoring | `/api/health` | admin/admin (change!) |
| Alertmanager | 9093 | HTTP | monitoring | `/-/healthy` | webhook receiver configured |
| Node Exporter | 9100 | HTTP | monitoring | `/metrics` | host OS metrics |
| cAdvisor | 8088 | HTTP | monitoring | `/healthz` | container resource metrics |
| Prometheus Push Gateway | 9091 | HTTP | monitoring | `/-/healthy` | batch job metrics |
| Postgres Exporter | 9187 | HTTP | monitoring | `/metrics` | pg_stat_* metrics |
| MySQL Exporter | 9104 | HTTP | monitoring | `/metrics` | innodb, query metrics |
| Redis Exporter | 9121 | HTTP | monitoring | `/metrics` | memory, commands/sec |
| Kafka Exporter | 9308 | HTTP | monitoring | `/metrics` | consumer lag, offsets |
| Nginx Exporter | 9113 | HTTP | monitoring | `/metrics` | stub_status required |

### ELK Stack

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| Elasticsearch HTTP | 9200 | HTTP | elk | `/_cluster/health` | v8, single-node |
| Elasticsearch Transport | 9300 | TCP | elk | N/A | internal cluster comms |
| Kibana | 5601 | HTTP | elk | `/api/status` | default space |
| Logstash Beats Input | 5044 | TCP | elk | N/A | Filebeat/Metricbeat |
| Logstash Syslog UDP | 5000 | UDP | elk | N/A | syslog input |
| Logstash HTTP Input | 8089 | HTTP | elk | N/A | HTTP input plugin |

### Web Servers / Ingress

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| Nginx HTTP | 80 | HTTP | ingress | `/` | reverse proxy / load balancer |
| Nginx HTTPS | 443 | HTTPS | ingress | `/` | self-signed TLS cert |
| Apache HTTP | 8080 | HTTP | ingress | `/server-status` | alternative web server |
| Traefik HTTP | 8086 | HTTP | ingress | `/ping` | edge router |
| Traefik HTTPS | 8443 | HTTPS | ingress | `/ping` | TLS termination |
| Traefik Dashboard | 8090 | HTTP | ingress | `/dashboard/` | route visualisation |

### CI/CD

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| Jenkins HTTP | 8081 | HTTP | cicd | `/login` | admin password in logs |
| Jenkins Agent | 50000 | TCP | cicd | N/A | JNLP agent port |
| GitLab HTTP | 8082 | HTTP | cicd | `/-/health` | CE edition |
| GitLab SSH | 2222 | SSH | cicd | N/A | `git clone ssh://git@localhost:2222/...` |
| ArgoCD HTTP | 8083 | HTTP | cicd | `/healthz` | GitOps controller |
| SonarQube | 9000 | HTTP | cicd | `/api/system/health` | code quality gate |

### Security

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| HashiCorp Vault | 8200 | HTTP | security | `/v1/sys/health` | dev mode (not for prod) |
| Consul HTTP | 8500 | HTTP | security | `/v1/agent/self` | service mesh / KV |
| Consul DNS | 8600 | UDP | security | N/A | service discovery DNS |
| Consul gRPC | 8502 | TCP | security | N/A | xDS gRPC API |
| Keycloak HTTP | 8085 | HTTP | security | `/health` | IAM, admin/admin |

### Messaging

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| RabbitMQ AMQP | 5672 | TCP | messaging | N/A | default vhost |
| RabbitMQ Management | 15672 | HTTP | messaging | `/api/healthchecks/node` | guest/guest (change!) |
| RabbitMQ MQTT | 1883 | TCP | messaging | N/A | requires plugin |
| Apache Kafka | 9092 | TCP | messaging | N/A | plaintext listener |
| Apache Zookeeper | 2181 | TCP | messaging | `echo ruok \| nc localhost 2181` | required by Kafka |

### Storage

| Service | Port(s) | Protocol | Profile | Health Endpoint | Notes |
|---------|---------|----------|---------|----------------|-------|
| Docker Registry | 5000 | HTTP | storage | `/v2/_catalog` | local image registry |
| Nexus Repository HTTP | 8084 | HTTP | storage | `/service/rest/v1/status` | Maven, npm, Docker |
| Nexus Docker Hosted | 8085 | HTTP | storage | N/A | hosted Docker repo |
| MinIO S3 API | 9001 | HTTP | storage | `/minio/health/live` | S3-compatible |
| MinIO Console | 9002 | HTTP | storage | N/A | minioadmin/minioadmin |

---

## 2. Quick Access URLs

Copy-paste these into your browser bookmarks:

```
# ─── Dashboards & UIs ────────────────────────────────────────────
Grafana              http://localhost:3000        admin / admin
Prometheus           http://localhost:9090
Alertmanager         http://localhost:9093
Kibana               http://localhost:5601

# ─── CI/CD ───────────────────────────────────────────────────────
Jenkins              http://localhost:8081
GitLab               http://localhost:8082
ArgoCD               http://localhost:8083
SonarQube            http://localhost:9000

# ─── Storage & Registry ──────────────────────────────────────────
Nexus                http://localhost:8084
MinIO Console        http://localhost:9002        minioadmin / minioadmin
Docker Registry      http://localhost:5000/v2/_catalog

# ─── Security ────────────────────────────────────────────────────
Vault UI             http://localhost:8200/ui
Consul UI            http://localhost:8500/ui
Keycloak Admin       http://localhost:8085/admin   admin / admin

# ─── Messaging ───────────────────────────────────────────────────
RabbitMQ Mgmt        http://localhost:15672        guest / guest

# ─── Infrastructure ──────────────────────────────────────────────
Traefik Dashboard    http://localhost:8090/dashboard/
cAdvisor             http://localhost:8088
```

---

## 3. Profile Groups

Start services by profile to manage resource usage:

```bash
# Start a single profile
docker compose --profile <profile> up -d

# Start multiple profiles
docker compose --profile monitoring --profile databases up -d

# Stop a profile
docker compose --profile <profile> down

# Available profiles:
#   k8s         — K3s Kubernetes (managed by systemd, not Compose)
#   databases   — PostgreSQL, MySQL, Redis, MongoDB
#   monitoring  — Prometheus, Grafana, Alertmanager, Exporters, cAdvisor
#   elk         — Elasticsearch, Logstash, Kibana
#   cicd        — Jenkins, GitLab, ArgoCD, SonarQube
#   security    — Vault, Consul, Keycloak
#   messaging   — RabbitMQ, Kafka, Zookeeper
#   storage     — Docker Registry, Nexus, MinIO
#   ingress     — Nginx, Apache, Traefik
```

### Resource Consumption by Profile (approximate)

| Profile | RAM Usage | CPU (idle) | Startup Time |
|---------|----------|------------|--------------|
| databases | ~1.5 GB | low | ~30 sec |
| monitoring | ~1.2 GB | low | ~45 sec |
| elk | ~3.0 GB | medium | ~90 sec |
| cicd | ~4.5 GB | medium | ~5 min |
| security | ~0.8 GB | low | ~30 sec |
| messaging | ~1.0 GB | low | ~30 sec |
| storage | ~1.0 GB | low | ~60 sec |
| ingress | ~0.3 GB | low | ~10 sec |

---

## 4. Port Range Legend

| Range | Usage |
|-------|-------|
| 53, 80, 443 | Standard protocols (DNS, HTTP, HTTPS) |
| 1883 | MQTT (messaging) |
| 2181 | Zookeeper |
| 2222 | GitLab SSH (non-standard to avoid conflict with host SSH) |
| 3000 | Grafana (commonly used by dev frameworks; check for conflicts) |
| 3306 | MySQL/MariaDB (standard) |
| 5000 | Docker Registry / Logstash Syslog |
| 5044 | Logstash Beats (Elastic stack standard) |
| 5432 | PostgreSQL (standard) |
| 5601 | Kibana (Elastic stack standard) |
| 5672 | RabbitMQ AMQP (standard) |
| 6379 | Redis (standard) |
| 6443 | Kubernetes API (K3s standard) |
| 8080–8090 | Web UIs and services (avoid 8080 conflicts with local dev servers) |
| 9000–9009 | SonarQube, MinIO, Prometheus Push Gateway |
| 9090–9099 | Prometheus ecosystem |
| 9100–9199 | Prometheus exporters |
| 9200, 9300 | Elasticsearch (standard) |
| 9308 | Kafka Exporter |
| 9092 | Kafka (standard) |
| 15672 | RabbitMQ Management (standard) |
| 27017 | MongoDB (standard) |
| 50000 | Jenkins agent (standard) |

### Potential Conflicts with Common Dev Tools

| Port | Our Service | Common Conflict |
|------|------------|-----------------|
| 3000 | Grafana | React / Next.js dev server |
| 5000 | Docker Registry | Flask dev server |
| 8080 | Apache | Spring Boot / Tomcat default |
| 9000 | SonarQube | PHP-FPM, some Go apps |
| 9200 | Elasticsearch | — rarely conflicts |

---

## 5. Conflict Detection

### Check All Ports Before Starting

```bash
#!/bin/bash
# Run before starting services to detect conflicts
PORTS=(
  53 80 443 1883 2181 2222 3000 3306 5000 5044 5432 5601 5672
  6379 6443 8080 8081 8082 8083 8084 8085 8086 8088 8089 8090
  8200 8443 8472 8500 8502 8600 9000 9001 9002 9090 9091 9092
  9093 9100 9104 9113 9121 9187 9200 9300 9308 10250 15672 27017 50000
)

echo "Checking for port conflicts..."
CONFLICTS=0
for port in "${PORTS[@]}"; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
     ss -ulnp 2>/dev/null | grep -q ":${port} "; then
    echo "  CONFLICT: port $port is already in use"
    ss -tlnp | grep ":${port} "
    CONFLICTS=$((CONFLICTS + 1))
  fi
done

if [ "$CONFLICTS" -eq 0 ]; then
  echo "No conflicts detected. Safe to start all services."
else
  echo "$CONFLICTS conflict(s) found. Resolve before starting."
fi
```

---

*Back to [README](../README.md) | See [OPERATIONS.md](./OPERATIONS.md) for service management commands.*
