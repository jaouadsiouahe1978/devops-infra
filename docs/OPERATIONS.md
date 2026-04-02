# Operations Runbook

> DevOps/SRE Local Infrastructure — Day-to-day operational procedures.
> Last updated: 2026-04-01

---

## Table of Contents

1. [Daily Operations Checklist](#1-daily-operations-checklist)
2. [Service Management](#2-service-management)
3. [Kubernetes Operations](#3-kubernetes-operations)
4. [Database Operations](#4-database-operations)
5. [Monitoring Operations](#5-monitoring-operations)
6. [Incident Response](#6-incident-response)
7. [Maintenance Windows](#7-maintenance-windows)
8. [Performance Tuning](#8-performance-tuning)

---

## 1. Daily Operations Checklist

### Morning Routine (5–10 minutes)

#### Step 1: Check Overnight Alerts

```bash
# View active Alertmanager alerts
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {alertname: .labels.alertname, severity: .labels.severity, starts: .startsAt}'

# View alert history (resolved + firing)
curl -s "http://localhost:9093/api/v2/alerts?active=true&silenced=false&inhibited=false" | jq length
```

Open Alertmanager UI: http://localhost:9093

#### Step 2: Review Grafana System Overview

1. Navigate to http://localhost:3000
2. Open dashboard: **Node Exporter Full** — check CPU, RAM, disk I/O
3. Open dashboard: **Docker Container Overview** — check container restarts
4. Open dashboard: **K8s Cluster Overview** — check pod/node health

#### Step 3: Check Backup Logs

```bash
# Check last backup run
ls -lhrt ~/devops-infra/backups/ | tail -10

# Verify yesterday's backup completed
YESTERDAY=$(date -d yesterday +%Y-%m-%d)
ls ~/devops-infra/backups/*${YESTERDAY}* 2>/dev/null || echo "WARNING: No backup found for $YESTERDAY"

# Check backup cron log
sudo grep -i "backup" /var/log/syslog | tail -20
```

#### Step 4: Review K8s Pod Health

```bash
# Check for non-Running pods
kubectl get pods -A | grep -v Running | grep -v Completed

# Check recent pod events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Check node resource pressure
kubectl describe nodes | grep -A5 "Conditions:"
```

#### Step 5: Check Disk Usage

```bash
# Overall disk usage
df -h | grep -E "(Filesystem|/dev/)"

# Docker-specific usage
docker system df

# Data directories
du -sh ~/devops-infra/data/* 2>/dev/null | sort -hr | head -10

# Alert if >80% full
USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
[ "$USAGE" -gt 80 ] && echo "WARNING: Root filesystem is ${USAGE}% full"
```

---

## 2. Service Management

### 2.1 Starting and Stopping Individual Services

```bash
# Start a single service
docker compose start prometheus
docker compose start grafana

# Stop a single service
docker compose stop elasticsearch

# Restart a service (e.g., after config change)
docker compose restart nginx

# Forcefully recreate a container
docker compose up -d --force-recreate logstash

# View logs for a single service
docker compose logs -f prometheus
docker compose logs --tail=100 grafana
```

### 2.2 Starting Service Groups (Profiles)

```bash
# Start monitoring stack
./scripts/service-manager.sh start monitoring-stack
# Equivalent to:
docker compose --profile monitoring up -d

# Start databases
./scripts/service-manager.sh start databases
# Equivalent to:
docker compose --profile databases up -d

# Start everything
./scripts/service-manager.sh start all

# Stop all services
./scripts/service-manager.sh stop all

# Available group aliases:
#   monitoring-stack  → Prometheus, Grafana, Alertmanager, exporters
#   databases         → PostgreSQL, MySQL, Redis, MongoDB
#   elk-stack         → Elasticsearch, Logstash, Kibana
#   cicd              → Jenkins, GitLab, ArgoCD, SonarQube
#   security          → Vault, Consul, Keycloak
#   messaging         → RabbitMQ, Kafka, Zookeeper
#   storage           → Registry, Nexus, MinIO
#   ingress           → Nginx, Traefik, Apache
```

### 2.3 Checking Service Status

```bash
# All containers with status
docker compose ps

# Pretty-printed table
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sort

# Check a specific service
docker inspect --format '{{.State.Status}} (health: {{.State.Health.Status}})' prometheus

# Check all health statuses
docker ps --format "{{.Names}}: {{.Status}}" | grep -v "healthy\|Up " | grep -v "^$"
```

### 2.4 Viewing Service Logs

```bash
# Follow logs in real time
docker compose logs -f --tail=50 prometheus

# Last N lines from multiple services
docker compose logs --tail=100 elasticsearch kibana logstash

# Filter logs by time
docker logs prometheus --since 1h

# Export logs to file
docker logs grafana > /tmp/grafana-$(date +%Y%m%d).log 2>&1

# Kubernetes pod logs
kubectl logs -f <pod-name> -n <namespace>
kubectl logs -f deployment/argocd-server -n argocd
kubectl logs --previous <pod-name>  # Logs from crashed container
```

---

## 3. Kubernetes Operations

### 3.1 kubectl Cheatsheet

```bash
# ─── Context Management ──────────────────────────────────────────
kubectl config get-contexts              # List all contexts
kubectl config use-context k3s-default  # Switch context
kubectl config set-context --current --namespace=staging  # Set default namespace

# ─── Resource Inspection ─────────────────────────────────────────
kubectl get all -A                       # Everything in all namespaces
kubectl get pods -A -o wide              # Pods with node/IP info
kubectl get services -A                  # All services
kubectl get deployments -A               # All deployments
kubectl get nodes -o wide                # Node details
kubectl top nodes                        # Node resource usage
kubectl top pods -A                      # Pod resource usage

# ─── Describe (detailed info) ────────────────────────────────────
kubectl describe pod <pod-name> -n <ns>  # Pod details + events
kubectl describe node <node-name>        # Node conditions, capacity
kubectl describe service <svc-name>      # Service endpoints

# ─── Labels and Selectors ────────────────────────────────────────
kubectl get pods -l app=prometheus       # Filter by label
kubectl get pods --show-labels           # Show all labels

# ─── Resource Status ─────────────────────────────────────────────
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
kubectl get events --field-selector type=Warning -A
```

### 3.2 Checking Pod Status

```bash
# Pods not in Running/Completed state
kubectl get pods -A | grep -vE "Running|Completed|Terminating"

# Pods with high restart counts
kubectl get pods -A | awk 'NR>1 && $5>5 {print $0}'

# Watch pod changes in real time
kubectl get pods -A -w

# Get pod details in YAML
kubectl get pod <pod-name> -n <ns> -o yaml

# Check container image versions
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'
```

### 3.3 Port-Forwarding Services

```bash
# Forward a service port to localhost
kubectl port-forward svc/argocd-server -n argocd 8083:443 &

# Forward a specific pod
kubectl port-forward pod/<pod-name> -n monitoring 9090:9090 &

# Forward deployment
kubectl port-forward deployment/grafana -n monitoring 3000:3000 &

# Kill all port-forwards
pkill -f "kubectl port-forward"

# List active port-forwards
ps aux | grep "kubectl port-forward"
```

### 3.4 Deploying Applications

```bash
# Apply a manifest
kubectl apply -f deployment.yaml

# Apply all manifests in a directory
kubectl apply -f ./k8s/

# Apply with dry run (validate only)
kubectl apply --dry-run=client -f deployment.yaml

# Create from Helm chart
helm install my-app ./charts/my-app -n production --create-namespace

# Upgrade Helm release
helm upgrade my-app ./charts/my-app -n production --reuse-values

# Set specific values
helm upgrade my-app ./charts/my-app -n production \
  --set image.tag=v1.2.3 \
  --set replicaCount=3
```

### 3.5 Rollback Procedure

```bash
# Check rollout history
kubectl rollout history deployment/my-app -n production

# View specific revision details
kubectl rollout history deployment/my-app -n production --revision=3

# Rollback to previous version
kubectl rollout undo deployment/my-app -n production

# Rollback to specific revision
kubectl rollout undo deployment/my-app -n production --to-revision=2

# Monitor rollback
kubectl rollout status deployment/my-app -n production

# Helm rollback
helm rollback my-app 2 -n production          # Rollback to revision 2
helm history my-app -n production              # View Helm release history
```

### 3.6 Node Maintenance (Cordon / Drain / Uncordon)

```bash
# Step 1: Prevent new pods from being scheduled on the node
kubectl cordon <node-name>

# Step 2: Evict all pods from the node (gracefully)
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# Step 3: Perform maintenance (OS update, Docker upgrade, etc.)
# ... do maintenance work here ...

# Step 4: Return node to service
kubectl uncordon <node-name>

# Verify node is schedulable again
kubectl get nodes
kubectl describe node <node-name> | grep -A5 "Taints:"
```

---

## 4. Database Operations

### 4.1 PostgreSQL

```bash
# Connect to PostgreSQL
docker exec -it postgres psql -U postgres

# Connect to a specific database
docker exec -it postgres psql -U postgres -d myapp

# Connect from host using psql client
PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres

# ─── Backup ──────────────────────────────────────────────────────
# Full cluster backup
docker exec postgres pg_dumpall -U postgres > ~/devops-infra/backups/pg_all_$(date +%Y%m%d).sql

# Single database backup
docker exec postgres pg_dump -U postgres myapp | \
  gzip > ~/devops-infra/backups/pg_myapp_$(date +%Y%m%d).sql.gz

# ─── Restore ─────────────────────────────────────────────────────
# Restore from SQL dump
cat backup.sql | docker exec -i postgres psql -U postgres

# Restore compressed dump
gunzip -c pg_myapp_20260401.sql.gz | docker exec -i postgres psql -U postgres -d myapp

# ─── Check Size ──────────────────────────────────────────────────
docker exec postgres psql -U postgres -c "
  SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
  FROM pg_database ORDER BY pg_database_size(datname) DESC;"

# Table sizes within a database
docker exec postgres psql -U postgres -d myapp -c "
  SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
  FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;"

# ─── Vacuum ──────────────────────────────────────────────────────
docker exec postgres psql -U postgres -d myapp -c "VACUUM ANALYZE;"
docker exec postgres psql -U postgres -d myapp -c "VACUUM VERBOSE ANALYZE;"

# ─── Monitoring ──────────────────────────────────────────────────
# Active connections
docker exec postgres psql -U postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Long-running queries
docker exec postgres psql -U postgres -c "
  SELECT pid, now() - query_start AS duration, query
  FROM pg_stat_activity
  WHERE state = 'active' AND query_start < now() - interval '30 seconds'
  ORDER BY duration DESC;"

# Check locks
docker exec postgres psql -U postgres -c "
  SELECT pid, locktype, relation::regclass, mode, granted
  FROM pg_locks WHERE NOT granted;"
```

### 4.2 MySQL

```bash
# Connect to MySQL
docker exec -it mysql mysql -u root -proot_password

# ─── Backup ──────────────────────────────────────────────────────
docker exec mysql mysqldump -u root -proot_password --all-databases \
  --single-transaction --routines --triggers \
  > ~/devops-infra/backups/mysql_all_$(date +%Y%m%d).sql

# Single database
docker exec mysql mysqldump -u root -proot_password --single-transaction myapp \
  | gzip > ~/devops-infra/backups/mysql_myapp_$(date +%Y%m%d).sql.gz

# ─── Restore ─────────────────────────────────────────────────────
cat backup.sql | docker exec -i mysql mysql -u root -proot_password myapp

# ─── Slow Query Analysis ─────────────────────────────────────────
# Enable slow query log
docker exec mysql mysql -u root -proot_password -e "
  SET GLOBAL slow_query_log = 'ON';
  SET GLOBAL long_query_time = 1;
  SET GLOBAL slow_query_log_file = '/var/lib/mysql/slow.log';"

# View slow queries
docker exec mysql tail -50 /var/lib/mysql/slow.log

# Process list
docker exec mysql mysql -u root -proot_password -e "SHOW FULL PROCESSLIST;"

# InnoDB status
docker exec mysql mysql -u root -proot_password -e "SHOW ENGINE INNODB STATUS\G" | head -100
```

### 4.3 Redis

```bash
# Connect to Redis CLI
docker exec -it redis redis-cli

# ─── Monitor Commands in Real Time ───────────────────────────────
docker exec -it redis redis-cli MONITOR

# ─── Key Inspection ──────────────────────────────────────────────
docker exec redis redis-cli INFO keyspace
docker exec redis redis-cli DBSIZE
docker exec redis redis-cli KEYS "session:*" | head -20  # CAUTION: slow on large datasets
docker exec redis redis-cli --scan --pattern "session:*" | head -20  # Preferred

# ─── Memory Usage ────────────────────────────────────────────────
docker exec redis redis-cli INFO memory | grep -E "used_memory_human|maxmemory"
docker exec redis redis-cli MEMORY USAGE mykey

# ─── Flush Operations ────────────────────────────────────────────
docker exec redis redis-cli FLUSHDB        # Flush current database only
docker exec redis redis-cli FLUSHALL       # Flush ALL databases (DESTRUCTIVE)

# ─── Backup RDB ──────────────────────────────────────────────────
# Trigger a background save
docker exec redis redis-cli BGSAVE
# Wait for completion
docker exec redis redis-cli LASTSAVE

# Copy RDB file to backup location
docker cp redis:/data/dump.rdb ~/devops-infra/backups/redis_$(date +%Y%m%d).rdb

# ─── Performance Stats ───────────────────────────────────────────
docker exec redis redis-cli INFO stats | grep -E "total_commands|hits|misses|evicted"
docker exec redis redis-cli INFO clients
```

### 4.4 MongoDB

```bash
# Connect to MongoDB shell
docker exec -it mongodb mongosh

# Connect with credentials
docker exec -it mongodb mongosh "mongodb://mongo:mongopass@localhost:27017/admin"

# ─── Backup ──────────────────────────────────────────────────────
# Full dump
docker exec mongodb mongodump \
  --username mongo --password mongopass \
  --authenticationDatabase admin \
  --out /tmp/mongodump
docker cp mongodb:/tmp/mongodump ~/devops-infra/backups/mongo_$(date +%Y%m%d)

# Single database
docker exec mongodb mongodump \
  --username mongo --password mongopass \
  --authenticationDatabase admin \
  --db myapp --out /tmp/mongodump_myapp
docker cp mongodb:/tmp/mongodump_myapp ~/devops-infra/backups/

# ─── Restore ─────────────────────────────────────────────────────
docker cp ~/devops-infra/backups/mongo_20260401 mongodb:/tmp/restore
docker exec mongodb mongorestore \
  --username mongo --password mongopass \
  --authenticationDatabase admin \
  /tmp/restore

# ─── Health and Status ───────────────────────────────────────────
docker exec mongodb mongosh --quiet --eval "db.adminCommand({ ping: 1 })"
docker exec mongodb mongosh --quiet --eval "db.adminCommand({ serverStatus: 1 }).connections"
docker exec mongodb mongosh --quiet --eval "rs.status()"  # Replica set status

# ─── Collection Stats ────────────────────────────────────────────
docker exec mongodb mongosh --quiet --eval "
  db.getSiblingDB('myapp').stats(1024*1024)"  # Stats in MB
```

---

## 5. Monitoring Operations

### 5.1 Adding New Prometheus Targets

**Method 1: Static configuration in prometheus.yml**

```yaml
# ~/devops-infra/config/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'my-new-service'
    static_configs:
      - targets: ['localhost:9999']
        labels:
          env: 'local'
          service: 'my-new-service'
    scrape_interval: 30s
    metrics_path: '/metrics'
```

```bash
# Reload Prometheus config without restart
curl -X POST http://localhost:9090/-/reload
# Or via Docker:
docker kill --signal=HUP prometheus
```

**Method 2: File-based service discovery**

```yaml
# ~/devops-infra/config/prometheus/targets/my-service.yaml
- targets:
    - "localhost:9999"
  labels:
    job: "my-service"
    env: "local"
```

### 5.2 Creating Grafana Dashboards

```bash
# Import dashboard from Grafana.com by ID
# In Grafana UI: Dashboards → Import → Enter dashboard ID

# Common dashboard IDs:
#   1860  — Node Exporter Full
#   893   — Docker and system monitoring
#   6417  — Kubernetes cluster monitoring
#   763   — Redis Dashboard
#   7362  — PostgreSQL Statistics
#   10991 — RabbitMQ Overview

# Export dashboard as JSON
curl -s -u admin:admin \
  http://localhost:3000/api/dashboards/uid/<dashboard-uid> | \
  jq '.dashboard' > ~/devops-infra/config/grafana/dashboards/my-dashboard.json

# Import dashboard via API
curl -X POST -u admin:admin \
  -H "Content-Type: application/json" \
  -d @dashboard.json \
  http://localhost:3000/api/dashboards/import
```

### 5.3 Managing Alerts

```bash
# View current alerting rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type=="alerting") | {name: .name, state: .state}'

# Check which alerts are currently firing
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'

# Silence an alert for 2 hours (maintenance window)
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "alertname", "value": "HighMemoryUsage", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S)'Z",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%S)'Z",
    "createdBy": "ops-engineer",
    "comment": "Maintenance window"
  }'

# List active silences
curl -s http://localhost:9093/api/v2/silences | jq '.[] | select(.status.state=="active") | {id, comment, endsAt}'

# Delete a silence
curl -X DELETE http://localhost:9093/api/v2/silences/<silence-id>
```

### 5.4 Querying Logs in Kibana

**Using Dev Tools (Console) in Kibana:**

```json
// Find all ERROR logs in last hour
GET /logs-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "level": "ERROR" } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ]
    }
  },
  "sort": [{ "@timestamp": "desc" }],
  "size": 50
}

// Count errors by service in last 24h
GET /logs-*/_search
{
  "query": { "range": { "@timestamp": { "gte": "now-24h" } } },
  "aggs": {
    "by_service": {
      "terms": { "field": "service.name.keyword", "size": 20 }
    }
  },
  "size": 0
}
```

---

## 6. Incident Response

### 6.1 Severity Levels

| Level | Name | Description | Response Time | Examples |
|-------|------|-------------|---------------|---------|
| P1 | Critical | Complete service outage, data loss risk | Immediate | K8s cluster down, DB corruption |
| P2 | High | Major functionality impaired | < 30 minutes | Monitoring blind, CI/CD broken |
| P3 | Medium | Non-critical service degraded | < 4 hours | Single exporter down, slow queries |
| P4 | Low | Minor issue, cosmetic | Next business day | Dashboard formatting, docs out of date |

### 6.2 Escalation Matrix

| Severity | Primary | Secondary | Escalate To |
|----------|---------|-----------|-------------|
| P1 | On-call Engineer | Team Lead | All hands |
| P2 | On-call Engineer | — | Team Lead if > 1h |
| P3 | Next available | — | On-call if blocking |
| P4 | Ticket queue | — | — |

### 6.3 Incident Communication Template

```
INCIDENT REPORT — [P1/P2/P3]
==============================
Time Detected : YYYY-MM-DD HH:MM UTC
Detected By   : [alert name / person]
Services      : [affected services]
Impact        : [user/system impact]
Status        : [Investigating | Mitigating | Resolved]

TIMELINE:
HH:MM — Alert fired: <alert name>
HH:MM — <engineer> began investigation
HH:MM — Root cause identified: <description>
HH:MM — Mitigation applied: <action>
HH:MM — Service restored

ROOT CAUSE: <concise description>
FIX APPLIED: <commands / changes made>
NEXT STEPS: <follow-up actions / tickets>
```

### 6.4 Post-Incident Review Template

```markdown
## Post-Incident Review

**Incident ID**: INC-YYYY-NNN
**Date**: YYYY-MM-DD
**Duration**: Xh Ym (HH:MM–HH:MM UTC)
**Severity**: P1/P2/P3
**Author**: <name>
**Reviewers**: <names>

### Summary
<2–3 sentence description of what happened and impact>

### Timeline
| Time (UTC) | Event |
|-----------|-------|
| HH:MM | Alert fired |
| HH:MM | Investigation started |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |
| HH:MM | Incident resolved |

### Root Cause Analysis
<Detailed technical explanation of root cause>

### What Went Well
- <positive item 1>
- <positive item 2>

### What Could Be Improved
- <improvement item 1>
- <improvement item 2>

### Action Items
| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| <item> | <name> | YYYY-MM-DD | P1/P2/P3 |

### SLO Impact
- SLO Affected: Yes / No
- Error Budget Consumed: X%
```

---

## 7. Maintenance Windows

### 7.1 OS Updates Procedure

```bash
# 1. Notify team / create silence in Alertmanager
curl -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "severity", "value": "warning", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S)'Z",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%S)'Z",
    "createdBy": "ops-engineer",
    "comment": "OS maintenance window"
  }'

# 2. Take a snapshot / backup of critical data
cd ~/devops-infra && bash scripts/backup-all.sh

# 3. Stop non-critical services
docker compose --profile elk stop
docker compose --profile cicd stop

# 4. Update OS packages
sudo apt-get update && sudo apt-get upgrade -y

# 5. Check if reboot required
cat /var/run/reboot-required 2>/dev/null && echo "Reboot required" || echo "No reboot needed"

# 6. Reboot if needed (WSL2: restart from Windows)
# WSL2: wsl --shutdown  (from PowerShell)
# Linux: sudo systemctl reboot

# 7. Verify services came back up
bash ~/devops-infra/scripts/validate.sh

# 8. Remove Alertmanager silence
```

### 7.2 Docker Image Updates

```bash
# Pull latest images for all services
docker compose pull

# Check which images have updates
docker compose pull --dry-run 2>&1 | grep "Pulling"

# Update and restart a specific service
docker compose pull prometheus
docker compose up -d --no-deps prometheus

# Remove old images
docker image prune -f

# Full update cycle
docker compose pull && docker compose up -d
```

### 7.3 K8s (K3s) Upgrade Procedure

```bash
# Check current K3s version
k3s --version

# Check available versions at:
# https://github.com/k3s-io/k3s/releases

# Upgrade K3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.0+k3s1 sh -

# Verify upgrade
k3s --version
kubectl get nodes
kubectl get pods -A
```

### 7.4 Certificate Renewal

```bash
# Check current certificate expiry
echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | \
  openssl x509 -noout -enddate

# Regenerate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ~/devops-infra/certs/server.key \
  -out ~/devops-infra/certs/server.crt \
  -subj "/C=US/ST=Local/L=Local/O=DevOps-Lab/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

# Restart Nginx to load new certificate
docker compose restart nginx

# Verify new expiry
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -enddate
```

---

## 8. Performance Tuning

### 8.1 Linux Kernel Parameters for Production-like Environment

```bash
# Apply all tuning parameters
sudo tee /etc/sysctl.d/99-devops-tuning.conf <<'EOF'
# Network
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Memory
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.max_map_count = 262144

# File descriptors
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF

sudo sysctl -p /etc/sysctl.d/99-devops-tuning.conf
```

### 8.2 PostgreSQL Tuning

```bash
# Connect and apply tuning parameters
docker exec postgres psql -U postgres <<'EOF'
-- Adjust based on available RAM (example: 4GB dedicated to PG)
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';
ALTER SYSTEM SET max_connections = '200';
ALTER SYSTEM SET wal_buffers = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = '0.9';
ALTER SYSTEM SET random_page_cost = '1.1';  -- SSD
ALTER SYSTEM SET effective_io_concurrency = '200';  -- SSD

-- Apply changes (requires restart for some parameters)
SELECT pg_reload_conf();
EOF

# Restart PostgreSQL to apply shared_buffers change
docker compose restart postgres
```

### 8.3 Elasticsearch Tuning

```bash
# Set JVM heap (in docker-compose.yml or environment variable)
# Recommended: half of available RAM, max 32GB
# ES_JAVA_OPTS="-Xms4g -Xmx4g"

# Check current JVM usage
curl -s http://localhost:9200/_nodes/stats/jvm | jq '.nodes | to_entries[0].value.jvm.mem'

# Tune index refresh interval (reduce for write-heavy workloads)
curl -X PUT http://localhost:9200/_settings \
  -H "Content-Type: application/json" \
  -d '{"index.refresh_interval": "30s"}'

# Force segment merge (after bulk indexing)
curl -X POST http://localhost:9200/logs-*/_forcemerge?max_num_segments=1

# Check cluster health and shard distribution
curl -s http://localhost:9200/_cat/shards?v | sort -k4 -hr | head -20
```

### 8.4 JVM Heap Settings Reference

| Service | Default Heap | Recommended (8GB system) | Recommended (16GB system) |
|---------|-------------|--------------------------|--------------------------|
| Elasticsearch | 1g/1g | 2g/2g | 4g/4g |
| Logstash | 256m/1g | 512m/1g | 1g/2g |
| Kibana | 256m/512m | 512m/1g | 1g/1g |
| Jenkins | 256m/512m | 512m/1g | 1g/2g |
| SonarQube | 512m/512m | 1g/2g | 2g/4g |
| Nexus | 512m/1200m | 1g/2g | 2g/3g |
| Kafka | 256m/256m | 512m/1g | 1g/2g |
| Zookeeper | 256m/256m | 256m/512m | 512m/1g |

```bash
# Apply JVM settings via environment variables in docker-compose.yml
# Example for Elasticsearch:
environment:
  - ES_JAVA_OPTS=-Xms4g -Xmx4g

# Example for Logstash:
environment:
  - LS_JAVA_OPTS=-Xms1g -Xmx2g
```

---

*For incident-specific runbooks, see [INCIDENTS.md](./INCIDENTS.md).*
*For architecture decisions, see [ARCHITECTURE.md](./ARCHITECTURE.md).*
