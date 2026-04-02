# Operations Runbook — DevOps/SRE Infrastructure

> 100+ page operational reference. Every procedure is tested and production-ready.
> Last updated: 2026-04-01

---

## Table of Contents

1. [Service Management](#1-service-management)
2. [Database Operations](#2-database-operations)
3. [Kubernetes Operations](#3-kubernetes-operations)
4. [Monitoring & Alerting](#4-monitoring--alerting)
5. [CI/CD Operations](#5-cicd-operations)
6. [Security Operations](#6-security-operations)
7. [Networking Operations](#7-networking-operations)
8. [Backup & Restore](#8-backup--restore)
9. [Capacity Planning](#9-capacity-planning)
10. [Incident Response](#10-incident-response)
11. [Maintenance Procedures](#11-maintenance-procedures)
12. [Troubleshooting Guide](#12-troubleshooting-guide)

---

## 1. Service Management

### 1.1 Starting Individual Services

```bash
# Start all databases
make db-start
# Expected output: "Databases started: postgres:5432 mysql:3306 redis:6379 mongodb:27017"
# Wait time: ~30s for healthchecks to pass

# Start monitoring stack
make monitoring-start
# Expected: Grafana http://localhost:3000 | Prometheus http://localhost:9090

# Start ELK stack (resource heavy: 2GB RAM)
make elk-start
# Wait time: ~2 min for Elasticsearch to be ready

# Start CI/CD stack
make cicd-start

# Start security stack
make security-start

# Start messaging stack
make messaging-start

# Start storage stack
make storage-start
```

### 1.2 Checking Service Health

```bash
# Quick health overview
make health

# Check specific port
nc -zv localhost 5432   # postgres
nc -zv localhost 9090   # prometheus

# Docker container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container logs
docker logs --tail 50 postgres
docker logs --tail 50 --follow prometheus
```

### 1.3 Graceful Service Restart

```bash
# Restart single container
docker restart grafana

# Restart and wait for healthcheck
docker restart grafana && docker wait grafana

# Rolling restart (databases - safe order)
docker restart redis       # stateless, fast
docker restart mongodb     # quick
docker restart postgres    # slowest, wait for pg_isready
docker restart mysql
```

### 1.4 Emergency Stop

```bash
# Stop everything immediately
make down

# Stop specific stack
docker compose -f ~/devops-infra/docker/compose/databases.yml down

# Kill a stuck container
docker kill <container_name>
docker rm <container_name>
```

---

## 2. Database Operations

### 2.1 PostgreSQL

```bash
# Connect
docker exec -it postgres psql -U devops -d devopsdb

# List databases
docker exec postgres psql -U devops -c "\l"

# List connections
docker exec postgres psql -U devops -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Check replication lag (if replica exists)
docker exec postgres psql -U devops -c "SELECT * FROM pg_stat_replication;"

# View slow queries (>100ms)
docker exec postgres psql -U devops -c "
  SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
  FROM pg_stat_activity
  WHERE (now() - pg_stat_activity.query_start) > interval '100 milliseconds'
  AND state = 'active';
"

# Kill long-running query
docker exec postgres psql -U devops -c "SELECT pg_terminate_backend(<pid>);"

# Vacuum analyze (maintenance)
docker exec postgres psql -U devops -c "VACUUM ANALYZE;"

# Check table sizes
docker exec postgres psql -U devops -d devopsdb -c "
  SELECT schemaname, tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
  FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 20;
"

# Backup
make backup-db
# or manually:
docker exec postgres pg_dumpall -U devops | gzip > ~/devops-infra/backups/postgres/manual_$(date +%Y%m%d).sql.gz

# Restore
gunzip < backup.sql.gz | docker exec -i postgres psql -U devops
```

### 2.2 MySQL

```bash
# Connect
docker exec -it mysql mysql -u devops -pDevOps2024! devopsdb

# Check processlist
docker exec mysql mysql -u root -pDevOps2024!Root -e "SHOW PROCESSLIST;"

# Check slow query log
docker exec mysql mysql -u root -pDevOps2024!Root -e "SHOW VARIABLES LIKE 'slow_query%';"

# Backup all databases
docker exec mysql mysqldump --all-databases -u root -pDevOps2024!Root | \
  gzip > ~/devops-infra/backups/mysql/all_$(date +%Y%m%d).sql.gz

# Check InnoDB status
docker exec mysql mysql -u root -pDevOps2024!Root -e "SHOW ENGINE INNODB STATUS\G" | head -50
```

### 2.3 Redis

```bash
# Connect
docker exec -it redis redis-cli -a DevOps2024!Redis

# Check memory usage
docker exec redis redis-cli -a DevOps2024!Redis INFO memory | grep -E "used_memory_human|maxmemory_human"

# Check connected clients
docker exec redis redis-cli -a DevOps2024!Redis CLIENT LIST | wc -l

# Monitor commands in real-time (DEBUG only - impacts performance)
docker exec redis redis-cli -a DevOps2024!Redis MONITOR

# Check key expiration
docker exec redis redis-cli -a DevOps2024!Redis INFO keyspace

# Flush all keys (DANGER - dev only)
docker exec redis redis-cli -a DevOps2024!Redis FLUSHALL

# Create RDB snapshot
docker exec redis redis-cli -a DevOps2024!Redis BGSAVE
docker cp redis:/data/dump.rdb ~/devops-infra/backups/redis/dump_$(date +%Y%m%d).rdb
```

### 2.4 MongoDB

```bash
# Connect
docker exec -it mongodb mongosh -u admin -p DevOps2024!Mongo --authenticationDatabase admin

# List databases
docker exec mongodb mongosh -u admin -p DevOps2024!Mongo --authenticationDatabase admin --eval "show dbs"

# Check replica set status (if configured)
docker exec mongodb mongosh --eval "rs.status()"

# Current operations
docker exec mongodb mongosh --eval "db.currentOp()"

# Kill operation
docker exec mongodb mongosh --eval "db.killOp(<opid>)"

# Backup
docker exec mongodb mongodump --out /tmp/mongodump_$(date +%Y%m%d) \
  -u admin -p DevOps2024!Mongo --authenticationDatabase admin
docker cp mongodb:/tmp/mongodump_$(date +%Y%m%d) ~/devops-infra/backups/mongodb/
```

---

## 3. Kubernetes Operations

### 3.1 Cluster Overview

```bash
# Node status
kubectl get nodes -o wide

# All pods across namespaces
kubectl get pods --all-namespaces -o wide

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory

# Events (recent issues)
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Check component health
kubectl get componentstatuses
```

### 3.2 Pod Operations

```bash
# Describe a failing pod
kubectl describe pod <pod-name> -n <namespace>

# Get logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous   # crashed container
kubectl logs <pod-name> -n <namespace> -f           # follow

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Force delete stuck pod
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# Copy file to/from pod
kubectl cp <pod-name>:/path/to/file ~/local-file -n <namespace>
```

### 3.3 Deployment Operations

```bash
# Rolling update
kubectl set image deployment/<name> <container>=<new-image> -n <namespace>

# Watch rollout
kubectl rollout status deployment/<name> -n <namespace>

# Rollback
kubectl rollout undo deployment/<name> -n <namespace>
kubectl rollout undo deployment/<name> --to-revision=2 -n <namespace>

# Scale
kubectl scale deployment/<name> --replicas=3 -n <namespace>

# Pause/Resume rollout
kubectl rollout pause deployment/<name> -n <namespace>
kubectl rollout resume deployment/<name> -n <namespace>

# Check rollout history
kubectl rollout history deployment/<name> -n <namespace>
```

### 3.4 Node Operations

```bash
# Cordon node (prevent new scheduling)
kubectl cordon <node-name>

# Drain node (evict all pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon
kubectl uncordon <node-name>

# Node resource pressure
kubectl describe node <node-name> | grep -A5 "Conditions:"
kubectl describe node <node-name> | grep -A20 "Allocated resources:"
```

### 3.5 PVC / Storage

```bash
# List PVCs
kubectl get pvc --all-namespaces

# Check PV status
kubectl get pv

# Describe stuck PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Force delete stuck PVC (WARNING: data loss)
kubectl patch pvc <pvc-name> -p '{"metadata":{"finalizers":null}}' -n <namespace>
kubectl delete pvc <pvc-name> -n <namespace>
```

### 3.6 ArgoCD Operations

```bash
# Login (CLI)
argocd login localhost:8083 --username admin --password <password> --insecure

# List applications
argocd app list

# Sync application
argocd app sync <app-name>

# Get app status
argocd app get <app-name>

# Rollback app
argocd app rollback <app-name> <revision>

# Force sync (ignore cache)
argocd app sync <app-name> --force
```

---

## 4. Monitoring & Alerting

### 4.1 Prometheus Queries

```bash
# Check scrape targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}' | head -40

# Query via API
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | {job: .metric.job, up: .value[1]}'

# Check alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state}'

# Useful PromQL snippets
# CPU usage %
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage %
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# Disk usage %
100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})

# HTTP error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Container memory usage
container_memory_usage_bytes{name!=""} / container_spec_memory_limit_bytes{name!=""} * 100
```

### 4.2 AlertManager

```bash
# List active alerts
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {alert: .labels.alertname, severity: .labels.severity}'

# Silence an alert (e.g., during maintenance)
curl -s -X POST http://localhost:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "alertname", "value": "NodeHighCPU", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "comment": "Maintenance window",
    "createdBy": "sre-oncall"
  }'

# List silences
curl -s http://localhost:9093/api/v2/silences | jq '.[] | {id: .id, state: .status.state, comment: .comment}'

# Delete silence
curl -s -X DELETE http://localhost:9093/api/v2/silences/<id>
```

### 4.3 Grafana API

```bash
# List dashboards
curl -s http://admin:admin@localhost:3000/api/search | jq '.[] | {title: .title, uid: .uid}'

# Reload provisioned dashboards
curl -s -X POST http://admin:admin@localhost:3000/api/admin/provisioning/dashboards/reload

# Add datasource via API
curl -s -X POST http://admin:admin@localhost:3000/api/datasources \
  -H 'Content-Type: application/json' \
  -d '{"name":"Loki","type":"loki","url":"http://loki:3100","access":"proxy"}'
```

### 4.4 Loki Queries (LogQL)

```bash
# All logs from last hour
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="devops-infra-logs"}' \
  --data-urlencode 'start='$(date -d '1 hour ago' +%s000000000) \
  --data-urlencode 'end='$(date +%s000000000) | jq '.data.result[0].values[-5:]'

# Filter for errors
# LogQL: {job="system-logs"} |= "ERROR" | logfmt | level = "error"

# Rate of errors per minute
# LogQL: rate({job="system-logs"} |= "ERROR" [1m])
```

---

## 5. CI/CD Operations

### 5.1 Jenkins

```bash
# Trigger build via API
curl -s -X POST http://admin:admin@localhost:8081/job/<job-name>/build \
  --data-urlencode json=''

# Get build status
curl -s http://admin:admin@localhost:8081/job/<job-name>/lastBuild/api/json | \
  jq '{result: .result, duration: .duration, timestamp: .timestamp}'

# View build log
curl -s http://admin:admin@localhost:8081/job/<job-name>/lastBuild/consoleText

# Install plugin
docker exec jenkins jenkins-plugin-cli --plugins <plugin-name>

# Reload config
curl -s -X POST http://admin:admin@localhost:8081/reload
```

### 5.2 Docker Registry

```bash
# List images in registry
curl -s http://localhost:5000/v2/_catalog | jq '.repositories'

# List tags for image
curl -s http://localhost:5000/v2/<image>/tags/list | jq '.tags'

# Push image to local registry
docker tag myapp:latest localhost:5000/myapp:latest
docker push localhost:5000/myapp:latest

# Pull from local registry
docker pull localhost:5000/myapp:latest

# Delete image from registry (requires deletion enabled in config)
DIGEST=$(curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5000/v2/<image>/manifests/<tag> | grep Docker-Content-Digest | awk '{print $2}' | tr -d '\r')
curl -X DELETE http://localhost:5000/v2/<image>/manifests/$DIGEST
```

---

## 6. Security Operations

### 6.1 Vault

```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=dev-root-token

# Check status
vault status

# Write a secret
vault kv put secret/myapp/db password=supersecret user=myapp

# Read a secret
vault kv get secret/myapp/db
vault kv get -field=password secret/myapp/db

# List secrets
vault kv list secret/

# Create policy
cat <<EOF | vault policy write myapp-readonly -
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Create token with policy
vault token create -policy=myapp-readonly -ttl=24h

# Audit log
vault audit enable file file_path=/opt/vault/audit.log

# Initialize (production mode)
vault operator init -key-shares=5 -key-threshold=3

# Unseal (production mode)
vault operator unseal <unseal-key>
```

### 6.2 Consul

```bash
# Check cluster status
consul members

# Register a service
cat <<EOF > /etc/consul.d/services/myapp.json
{
  "service": {
    "name": "myapp",
    "port": 8000,
    "check": {
      "http": "http://localhost:8000/health",
      "interval": "10s"
    }
  }
}
EOF
consul reload

# Query service catalog
curl -s http://localhost:8500/v1/catalog/services | jq 'keys'
curl -s http://localhost:8500/v1/health/service/postgres | jq '.[0].Checks'

# KV operations
consul kv put myapp/config/db_host localhost
consul kv get myapp/config/db_host
consul kv delete myapp/config/db_host

# Backup KV store
consul kv export > /opt/backups/consul_$(date +%Y%m%d).json
```

### 6.3 Certificate Management

```bash
# Check cert expiry
bash ~/devops-infra/scripts/cert-check.sh

# Check specific cert
openssl x509 -in /etc/ssl/devops-certs/nginx/cert.pem -noout -dates

# Generate new cert for service
bash ~/devops-infra/scripts/generate-certs.sh --service=nginx

# Rotate all certs
bash ~/devops-infra/scripts/generate-certs.sh --all

# Verify TLS connection
openssl s_client -connect localhost:443 -servername grafana.devops.local
```

### 6.4 Linux RBAC

```bash
# Check current sudo rules
sudo cat /etc/sudoers.d/devops

# List groups
getent group | grep -E "devops|sre|developers"

# Add user to group
sudo usermod -aG devops newuser

# Check user permissions
sudo -l -U devops-dev

# Review auth logs
sudo grep "sudo:" /var/log/auth.log | tail -20
sudo grep "Failed password" /var/log/auth.log | tail -20
```

---

## 7. Networking Operations

### 7.1 Traefik

```bash
# Check Traefik dashboard
curl -s http://localhost:8080/api/overview | jq '{routers: .http.routers, services: .http.services}'

# List routers
curl -s http://localhost:8080/api/http/routers | jq '.[] | {name: .name, rule: .rule, status: .status}'

# List services  
curl -s http://localhost:8080/api/http/services | jq '.[] | {name: .name, type: .type}'

# Reload config
docker restart traefik

# View Traefik logs
docker logs traefik --tail 50 -f
```

### 7.2 HAProxy

```bash
# Stats page
curl -s http://localhost:9999/stats?csv | head -5

# Check backend health
curl -s "http://localhost:9999/stats;csv" | awk -F, 'NR>2 {print $1,$2,$18}'

# Reload config without downtime
docker kill --signal=HUP haproxy

# HAProxy socket (if unix socket configured)
echo "show stat" | socat stdio /var/run/haproxy/admin.sock
echo "show info" | socat stdio /var/run/haproxy/admin.sock
```

### 7.3 Network Troubleshooting

```bash
# Port connectivity
nc -zv localhost 5432
nc -zv localhost 9090
bash ~/devops-infra/scripts/port-check.sh

# DNS resolution
dig @localhost -p 8600 postgres.service.consul
nslookup grafana.devops.local

# Trace route
traceroute 172.20.1.2

# Capture traffic on docker network
docker network inspect devops-databases
ip route show

# iptables rules
sudo iptables -L INPUT -n --line-numbers
sudo iptables -L OUTPUT -n --line-numbers

# Check fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <ip>
```

---

## 8. Backup & Restore

### 8.1 Run Backups

```bash
# Full backup (all services)
bash ~/devops-infra/scripts/backup.sh --service=all

# Specific service
bash ~/devops-infra/scripts/backup.sh --service=postgres
bash ~/devops-infra/scripts/backup.sh --service=mysql
bash ~/devops-infra/scripts/backup.sh --service=redis
bash ~/devops-infra/scripts/backup.sh --service=mongodb
bash ~/devops-infra/scripts/backup.sh --service=configs
bash ~/devops-infra/scripts/backup.sh --service=k8s

# Verify backups
bash ~/devops-infra/scripts/backup.sh --verify

# List available backups
bash ~/devops-infra/scripts/restore.sh --list-backups

# Cleanup old backups (>30 days)
bash ~/devops-infra/scripts/backup.sh --cleanup
```

### 8.2 Restore Procedures

```bash
# Interactive restore menu
bash ~/devops-infra/scripts/restore.sh

# Restore specific service from specific backup
bash ~/devops-infra/scripts/restore.sh \
  --service=postgres \
  --backup=~/devops-infra/backups/postgres/postgres_20260401_020000.sql.gz

# Verify restore
docker exec postgres psql -U devops -c "\l"
docker exec postgres psql -U devops -d devopsdb -c "SELECT count(*) FROM information_schema.tables;"
```

### 8.3 Disaster Recovery

```bash
# Run DR test (non-destructive validation)
bash /opt/dr/dr-test.sh

# Full DR restore (DESTRUCTIVE - use only in emergency)
bash /opt/dr/full-restore.sh

# Check RTO/RPO compliance
cat /opt/dr/dr-runbook.md | grep -A5 "RTO\|RPO"
```

---

## 9. Capacity Planning

### 9.1 Current Usage

```bash
# System resources
free -h
df -h
iostat -x 1 5
uptime

# Per-container resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# K8s resource usage
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=cpu

# Disk usage breakdown
du -sh ~/devops-infra/data/* | sort -h
du -sh ~/devops-infra/backups/* | sort -h
du -sh ~/devops-infra/logs/* | sort -h
```

### 9.2 Generate Capacity Report

```bash
# Daily report
bash /opt/capacity/capacity-report.sh

# View latest report
cat /opt/capacity/reports/$(date +%Y-%m-%d).json | jq .

# Check thresholds
cat /opt/capacity/thresholds.yaml

# Alert check
bash /opt/capacity/capacity-alert.sh
```

### 9.3 Capacity Thresholds

| Resource | Warning | Critical |
|----------|---------|----------|
| CPU (sustained 5m) | 80% | 90% |
| Memory | 75% | 90% |
| Disk / | 80% | 90% |
| Disk /data | 75% | 85% |
| Disk /backups | 70% | 80% |
| PostgreSQL connections | 70% max_conn | 85% |
| Redis memory | 75% maxmemory | 90% |
| Kafka lag | 10000 msgs | 50000 msgs |

---

## 10. Incident Response

### 10.1 Incident Severity Levels

| Level | Criteria | Response Time | Examples |
|-------|----------|---------------|---------|
| P1 Critical | Complete outage, data loss risk | < 5 min | DB down, K8s cluster unresponsive |
| P2 High | Degraded performance, partial outage | < 15 min | Memory leak, disk 90%+ |
| P3 Medium | Minor degradation, workaround available | < 1 hour | Single service down, high latency |
| P4 Low | Non-critical issue, monitoring gap | < 4 hours | Log rotation needed, cert expiring in 30d |

### 10.2 Incident Response Checklist

```
[ ] 1. DETECT: Identify the alert/symptom
[ ] 2. ASSESS: Determine severity (P1-P4)
[ ] 3. COMMUNICATE: Log incident start time
[ ] 4. INVESTIGATE: Run diagnostic commands
[ ] 5. MITIGATE: Stop the bleeding (not full fix)
[ ] 6. RESOLVE: Fix root cause
[ ] 7. VERIFY: Confirm service restored
[ ] 8. DOCUMENT: Write post-mortem
[ ] 9. FOLLOW-UP: Implement prevention measures
```

### 10.3 Practice Incidents

```bash
# List all incident scenarios
bash ~/devops-infra/scripts/incident-simulator.sh --list

# Run specific scenario
bash ~/devops-infra/scripts/incident-simulator.sh --scenario=1   # pod crash loop
bash ~/devops-infra/scripts/incident-simulator.sh --scenario=2   # disk full
bash ~/devops-infra/scripts/incident-simulator.sh --scenario=3   # memory leak

# Resolve active incident
bash ~/devops-infra/scripts/incident-simulator.sh --resolve

# Daily SRE exercise
bash ~/devops-infra/scripts/sre-daily.sh
```

### 10.4 Post-Incident Review Template

```markdown
## Post-Incident Review — <Title>

**Date:** YYYY-MM-DD
**Duration:** HH:MM
**Severity:** P1/P2/P3/P4
**Affected Services:** 

### Timeline
- HH:MM - Alert fired / issue detected
- HH:MM - Investigation started
- HH:MM - Root cause identified
- HH:MM - Mitigation applied
- HH:MM - Service restored
- HH:MM - Post-mortem started

### Root Cause
<1-2 sentences describing the root cause>

### Impact
- Users/services affected:
- Duration of impact:
- Data loss: Yes/No

### What Went Well
-
-

### What Went Wrong
-
-

### Action Items
| Item | Owner | Due Date | Priority |
|------|-------|----------|----------|
|      |       |          |          |

### MTTR: <duration>
### MTBF: <time since last incident>
```

---

## 11. Maintenance Procedures

### 11.1 Weekly Maintenance Checklist

```bash
# Monday morning
bash ~/devops-infra/scripts/health-check.sh
bash ~/devops-infra/scripts/cert-check.sh
bash ~/devops-infra/scripts/backup.sh --verify
docker images | grep -v "REPOSITORY" | awk '{print $1":"$2}' # review image versions

# Wednesday
du -sh ~/devops-infra/data/*    # check data growth
du -sh ~/devops-infra/logs/*    # check log growth
make clean-logs                  # rotate old logs

# Friday
docker system df                 # Docker disk usage
docker system prune -f           # clean dangling images
bash ~/devops-infra/scripts/backup.sh --service=all  # weekly backup
```

### 11.2 Monthly Maintenance

```bash
# First Sunday of month
bash /opt/dr/dr-test.sh          # DR test
bash ~/devops-infra/scripts/backup.sh --cleanup  # purge old backups

# Certificate review
bash ~/devops-infra/scripts/cert-check.sh
# Renew if < 90 days remaining:
bash ~/devops-infra/scripts/generate-certs.sh --all

# Image updates (check for security patches)
docker compose -f ~/devops-infra/docker/compose/databases.yml pull
docker compose -f ~/devops-infra/docker/compose/monitoring.yml pull
# Then restart updated containers
```

### 11.3 Upgrade Procedures

```bash
# Upgrade PostgreSQL (example: 15.x → 15.y)
# 1. Backup first
bash ~/devops-infra/scripts/backup.sh --service=postgres

# 2. Update image version in databases.yml
# 3. Pull new image
docker compose -f ~/devops-infra/docker/compose/databases.yml pull postgres

# 4. Check migration notes in postgres release notes

# 5. Stop and restart
docker compose -f ~/devops-infra/docker/compose/databases.yml stop postgres
docker compose -f ~/devops-infra/docker/compose/databases.yml up -d postgres

# 6. Verify
docker logs postgres --tail 20
docker exec postgres psql -U devops -c "SELECT version();"
```

---

## 12. Troubleshooting Guide

### 12.1 Container Won't Start

```bash
# Check detailed error
docker logs <container>

# Check resource limits
docker inspect <container> | jq '.[0].HostConfig | {Memory: .Memory, CPUShares: .CpuShares}'

# Check volume mounts
docker inspect <container> | jq '.[0].Mounts'

# Check if port is in use
sudo ss -tlnp | grep :<port>
sudo fuser <port>/tcp

# Remove and recreate
docker stop <container>
docker rm <container>
docker compose -f <file>.yml up -d <service>
```

### 12.2 High CPU/Memory

```bash
# Find top CPU consumers
docker stats --no-stream | sort -k3 -rn | head -10

# Find top memory consumers
docker stats --no-stream | sort -k4 -rn | head -10

# System-level
top -b -n 1 | head -20
ps aux --sort=-%cpu | head -10
ps aux --sort=-%mem | head -10
```

### 12.3 Network Issues

```bash
# Can't connect to service
nc -zv localhost <port>
curl -v http://localhost:<port>/health
docker network ls
docker network inspect devops-databases

# DNS issues
cat /etc/hosts | grep devops
dig grafana.devops.local
nslookup grafana.devops.local 127.0.0.1

# Container can't reach another container
docker network connect devops-databases <container>
```

### 12.4 Disk Full

```bash
# Find large files
find / -xdev -type f -size +100M 2>/dev/null | sort -k5 -rn | head -20
du -sh /var/lib/docker/* | sort -h

# Clean Docker aggressively
docker system prune -a -f --volumes    # WARNING: removes all unused resources
docker volume prune -f

# Rotate logs immediately
find ~/devops-infra/logs -name "*.log" -size +10M -exec gzip {} \;
find ~/devops-infra/logs -name "*.log.gz" -mtime +7 -delete
journalctl --vacuum-size=500M
```

### 12.5 K8s Cluster Issues

```bash
# Node not ready
kubectl describe node <node>
kubectl get events -n kube-system --sort-by='.lastTimestamp' | tail -20

# etcd health
ETCDCTL_API=3 etcdctl \
  --endpoints=https://localhost:2379 \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  endpoint health

# K3s service logs
sudo journalctl -u k3s -f --since "10 minutes ago"

# Restart K3s
sudo systemctl restart k3s
```

---

*End of Runbook. For incident-specific playbooks, see [INCIDENTS.md](INCIDENTS.md).*
*For learning exercises, see [LEARNING-PATH.md](LEARNING-PATH.md).*
*For architecture overview, see [ARCHITECTURE.md](ARCHITECTURE.md).*
