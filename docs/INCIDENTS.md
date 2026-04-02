# Incident Playbooks

> Detailed runbooks for 20 common incident scenarios in the DevOps/SRE local infrastructure.
> Last updated: 2026-04-01

---

## Table of Contents

1. [Pod CrashLoopBackOff](#1-pod-crashloopbackoff)
2. [Disk Full](#2-disk-full)
3. [Memory Leak](#3-memory-leak)
4. [Database Deadlock (PostgreSQL)](#4-database-deadlock-postgresql)
5. [Network Timeout / High Latency](#5-network-timeout--high-latency)
6. [Certificate Expired](#6-certificate-expired)
7. [PVC Mount Failed](#7-pvc-mount-failed)
8. [Stale Lock File](#8-stale-lock-file)
9. [API Rate Limit Exceeded](#9-api-rate-limit-exceeded)
10. [DNS Resolution Failed](#10-dns-resolution-failed)
11. [TLS Handshake Timeout](#11-tls-handshake-timeout)
12. [Registry Pull Rate Limit](#12-registry-pull-rate-limit)
13. [Quorum Loss (Consul/etcd)](#13-quorum-loss-consuletcd)
14. [Leader Election Failure](#14-leader-election-failure)
15. [Cache Invalidation Storm](#15-cache-invalidation-storm)
16. [Resource Quota Exceeded](#16-resource-quota-exceeded)
17. [Deployment Rollback Needed](#17-deployment-rollback-needed)
18. [Orchestrator Failure (K3s Down)](#18-orchestrator-failure-k3s-down)
19. [Node Cordon and Drain](#19-node-cordon-and-drain)
20. [Chaos Engineering Test](#20-chaos-engineering-test)

---
[Post-Incident Review Template](#post-incident-review-template) |
[Incident Timeline Template](#incident-timeline-template) |
[MTTR/MTBF Tracking](#mttrmtbf-tracking-table)

---

## 1. Pod CrashLoopBackOff

### Scenario
A Kubernetes pod enters `CrashLoopBackOff` status, meaning the container repeatedly starts, crashes, and is restarted by the kubelet.

### Symptoms
- `kubectl get pods -A` shows `CrashLoopBackOff` or `Error` in STATUS column
- High restart count in RESTARTS column
- Alertmanager fires `KubePodCrashLooping`

### Detection
- **Alert**: `KubePodCrashLooping` (restart rate > 0 over 15m)
- **Metric**: `kube_pod_container_status_restarts_total` spikes
- **Visual**: Grafana "K8s Pod Restarts" panel shows sustained upward trend

### Impact
- Service is unavailable or degraded
- Downstream services depending on this pod may time out
- May consume restart budget and block other deployments

### Investigation

```bash
# Step 1: Identify the crashing pod
kubectl get pods -A | grep -E "CrashLoop|Error"

# Step 2: Get pod details
kubectl describe pod <pod-name> -n <namespace>
# Look for: Last State, Exit Code, Reason, Events section

# Step 3: View current logs
kubectl logs <pod-name> -n <namespace>

# Step 4: View logs from the PREVIOUS (crashed) container
kubectl logs <pod-name> -n <namespace> --previous

# Step 5: Check exit code
kubectl get pod <pod-name> -n <namespace> \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
# Exit code 0 = graceful exit (likely misconfiguration)
# Exit code 1 = application error
# Exit code 137 = OOM Killed (SIGKILL)
# Exit code 139 = Segfault

# Step 6: Check resource limits
kubectl describe pod <pod-name> -n <namespace> | grep -A10 "Limits:"

# Step 7: Check recent events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

### Resolution

```bash
# OOM kill: increase memory limits
kubectl patch deployment <deployment> -n <namespace> \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"512Mi"}}}]}}}}'

# Configuration error: check and fix ConfigMap/Secret
kubectl get configmap <name> -n <namespace> -o yaml
kubectl edit configmap <name> -n <namespace>

# Image error: force image pull and recreate
kubectl rollout restart deployment/<deployment> -n <namespace>

# Temporary: delete the pod to force a fresh start
kubectl delete pod <pod-name> -n <namespace>

# If caused by bad deployment, rollback
kubectl rollout undo deployment/<deployment> -n <namespace>
```

### Prevention
- Set realistic resource requests AND limits for all containers
- Implement readiness and liveness probes
- Use `kubectl diff` before applying changes
- Test images locally before deploying to cluster

### SLO Impact
**Yes** — if this is a critical service, a CrashLoopBackOff triggers error budget consumption. Duration > 5 minutes = P2 incident.

---

## 2. Disk Full

### Scenario
A disk volume (`/tmp`, `/var`, `/home`, or a Docker data volume) reaches 100% capacity, causing service failures.

### Symptoms
- Write errors in service logs: `No space left on device`
- PostgreSQL, Elasticsearch, or Kafka stop accepting writes
- Docker cannot pull new images or write logs
- Jenkins builds fail with I/O errors

### Detection
- **Alert**: `HostDiskSpaceLow` (> 85%) or `HostDiskSpaceCritical` (> 95%)
- **Metric**: `node_filesystem_avail_bytes` drops to near zero
- **Visual**: Grafana "Node Exporter Full" → Disk Space Used

### Impact
- **P1** if affects databases or Kubernetes state
- **P2** if affects build systems or log ingestion
- **P3** if affects non-critical temp directories

### Investigation

```bash
# Step 1: Check overall disk usage
df -h

# Step 2: Find large directories
du -sh /* 2>/dev/null | sort -hr | head -20
du -sh /var/lib/docker/* 2>/dev/null | sort -hr | head -10

# Step 3: Docker-specific space usage
docker system df -v

# Step 4: Find large files
find / -xdev -type f -size +500M 2>/dev/null | sort -k5 -hr

# Step 5: Check log sizes
du -sh /var/log/* 2>/dev/null | sort -hr | head -10

# Step 6: Check K8s persistent volumes
kubectl get pv -A
kubectl df-pv  # requires krew plugin: kubectl krew install df-pv
```

### Resolution

```bash
# Immediate: Free Docker space (safe)
docker system prune -f           # Remove stopped containers, dangling images, unused networks
docker image prune -a -f         # Remove ALL unused images (reclaims most space)
docker volume prune -f           # Remove unused volumes (CAREFUL: verify first)

# Remove old container logs
sudo find /var/lib/docker/containers -name "*.log" -size +100M -exec truncate -s 0 {} \;

# Clear package cache
sudo apt-get clean
sudo apt-get autoremove -y

# Remove old kernel versions
sudo apt-get purge $(dpkg -l 'linux-image-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | head -n -1) 2>/dev/null

# Rotate and compress old log files
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=500M

# Clear /tmp
sudo find /tmp -type f -atime +7 -delete
sudo find /tmp -type d -empty -delete
```

### Prevention
- Configure Docker log rotation: `"max-size": "50m", "max-file": "3"` in daemon.json
- Set up automated cleanup cron: `0 2 * * * docker system prune -f`
- Monitor disk usage with Prometheus alert at 80% threshold
- Use Elasticsearch ILM policies to auto-delete old indices

### SLO Impact
**Yes** — disk full on database volumes = P1. Disk full on `/tmp` = P3.

---

## 3. Memory Leak

### Scenario
A service consumes progressively more memory over time, eventually reaching system limits and causing OOM kills or service degradation.

### Symptoms
- Service RAM usage climbs steadily over hours/days
- System becomes unresponsive, swap usage spikes
- OOM killer kills processes: visible in `dmesg`
- Container is OOM-killed (exit code 137)

### Detection
- **Alert**: `ContainerMemoryUsageHigh` (> 95% of limit)
- **Metric**: `container_memory_usage_bytes` shows monotonic increase
- **Visual**: Grafana memory graph shows "sawtooth" pattern (grows then drops on restart)

### Impact
- Service degradation as GC pressure increases
- Other services starved of memory (noisy neighbour problem)
- System instability if swap is exhausted

### Investigation

```bash
# Step 1: Check system memory
free -h
vmstat -s | head -10

# Step 2: Find memory-hungry processes
ps aux --sort=-%mem | head -15
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | sort -k3 -hr

# Step 3: Check OOM kill history
dmesg | grep -i "killed process\|out of memory" | tail -20
sudo journalctl -k | grep -i "oom" | tail -20

# Step 4: Check container memory growth over time (Prometheus query)
# rate(container_memory_usage_bytes{name="my-service"}[1h])
# Open: http://localhost:9090/graph

# Step 5: For JVM services, check heap
docker exec elasticsearch curl -s http://localhost:9200/_nodes/stats/jvm | \
  jq '.nodes | to_entries[0].value.jvm.mem | {heap_used: .heap_used_in_bytes, heap_max: .heap_max_in_bytes}'

# Step 6: For Node.js/Go services
docker exec my-service /bin/sh -c "cat /proc/1/status | grep VmRSS"
```

### Resolution

```bash
# Short-term: Restart the leaking service
docker compose restart my-service
kubectl rollout restart deployment/my-service -n production

# Increase memory limit temporarily
kubectl patch deployment my-service -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"my-service","resources":{"limits":{"memory":"2Gi"}}}]}}}}'

# For JVM: trigger GC
# Elasticsearch:
curl -X POST http://localhost:9200/_nodes/hot_threads
# Find the PID and send SIGTERM for graceful restart with heap dump:
docker exec elasticsearch kill -3 1  # JVM thread dump to stdout

# Drop Linux page cache to reclaim memory (does NOT help with heap leaks)
sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

### Prevention
- Always set container memory limits
- Enable JVM GC logging for Java services
- Set up memory alerting at 70% and 90% thresholds
- Schedule regular restarts for known-leaky services until root cause is fixed
- Use heap profilers (async-profiler, pprof) to identify leak location

### SLO Impact
**Yes** if memory exhaustion causes request failures. P2 at 90% usage, P1 at OOM kill.

---

## 4. Database Deadlock (PostgreSQL)

### Scenario
Two or more transactions are waiting for each other to release locks, causing a deadlock that PostgreSQL resolves by aborting one transaction.

### Symptoms
- Application errors: `ERROR: deadlock detected`
- Increased query latency
- Alert fires for high lock wait times

### Detection
- **Alert**: `PostgreSQLDeadlockDetected` (custom alert on `pg_stat_activity` or log parsing)
- **Metric**: `pg_stat_database_deadlocks` counter increments
- **Log**: `ERROR: deadlock detected` in PostgreSQL logs

### Impact
- Some transactions fail and must be retried by application
- Sustained deadlocks cause request pile-up and service degradation

### Investigation

```bash
# Step 1: Check current deadlock count
docker exec postgres psql -U postgres -c "
  SELECT datname, deadlocks FROM pg_stat_database WHERE deadlocks > 0;"

# Step 2: Find currently waiting queries
docker exec postgres psql -U postgres -c "
  SELECT pid, now() - query_start AS wait_time, state, wait_event_type, wait_event, query
  FROM pg_stat_activity
  WHERE wait_event_type = 'Lock'
  ORDER BY wait_time DESC;"

# Step 3: View lock details
docker exec postgres psql -U postgres -c "
  SELECT pid, locktype, relation::regclass, mode, granted, query
  FROM pg_locks l
  JOIN pg_stat_activity a USING (pid)
  WHERE NOT granted
  ORDER BY pid;"

# Step 4: Check PostgreSQL log for deadlock details
docker logs postgres 2>&1 | grep -A10 "deadlock"

# Step 5: Find blocking PID
docker exec postgres psql -U postgres -c "
  SELECT pid, pg_blocking_pids(pid) AS blocked_by, query
  FROM pg_stat_activity
  WHERE cardinality(pg_blocking_pids(pid)) > 0;"
```

### Resolution

```bash
# Terminate blocking query (replace <pid>)
docker exec postgres psql -U postgres -c "SELECT pg_terminate_backend(<pid>);"

# Terminate all locks held by a specific application
docker exec postgres psql -U postgres -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE application_name = 'my-app' AND state = 'idle in transaction';"

# If application is stuck: restart the application container
docker compose restart my-app
```

### Prevention
- Use `SELECT ... FOR UPDATE` with `NOWAIT` or `SKIP LOCKED` to avoid waiting
- Keep transactions short; commit as early as possible
- Access tables in a consistent order within transactions
- Set `lock_timeout = '5s'` and `idle_in_transaction_session_timeout = '30s'`
- Add `deadlock_timeout = 1s` in postgresql.conf for faster detection

### SLO Impact
Intermittent deadlocks with retry: P3. Sustained deadlock storm causing user-visible errors: P2.

---

## 5. Network Timeout / High Latency

### Scenario
Services experience elevated response times or connection timeouts, causing cascading failures.

### Symptoms
- Increased HTTP 504/503 error rates
- Service response times > SLO threshold
- TCP connection refused or reset errors

### Detection
- **Alert**: `HighResponseLatency` (p99 latency > 1s)
- **Metric**: `http_request_duration_seconds` histogram
- **Visual**: Grafana request latency dashboards

### Impact
- User-facing requests time out
- Health checks fail, triggering unnecessary pod restarts
- Circuit breakers open, causing cascading failures

### Investigation

```bash
# Step 1: Check network latency between containers
docker exec prometheus ping -c 10 grafana
docker exec my-app ping -c 10 postgres

# Step 2: Test TCP connectivity
docker exec my-app nc -zv postgres 5432
docker exec my-app nc -zv redis 6379

# Step 3: Check for packet loss
docker exec my-app mtr --report --report-cycles 20 postgres

# Step 4: Check DNS resolution time
docker exec my-app time nslookup postgres

# Step 5: Check network interface stats
ip -s link show eth0
cat /proc/net/dev

# Step 6: Check for conntrack table full
sudo sysctl net.netfilter.nf_conntrack_count
sudo sysctl net.netfilter.nf_conntrack_max
# If count is close to max, you'll get silent packet drops

# Step 7: Check Docker network
docker network ls
docker network inspect bridge
```

### Resolution

```bash
# Increase conntrack table size (if that's the issue)
sudo sysctl -w net.netfilter.nf_conntrack_max=524288
echo "net.netfilter.nf_conntrack_max=524288" | sudo tee -a /etc/sysctl.conf

# Restart Docker networking
sudo systemctl restart docker

# If container DNS is slow: check /etc/resolv.conf inside container
docker exec my-app cat /etc/resolv.conf
# Add ndots:1 to reduce DNS lookup chain
# Add options in docker-compose.yml:
# dns_opt:
#   - ndots:1
```

### Prevention
- Set connection timeouts at the application level (never wait indefinitely)
- Implement retry logic with exponential backoff
- Use health checks to detect degraded backends early
- Monitor connection pool utilisation metrics

### SLO Impact
**Yes** — latency SLO breach. P2 if widespread, P3 if isolated.

---

## 6. Certificate Expired

### Scenario
A TLS certificate expires, causing HTTPS connections to fail with certificate validation errors.

### Symptoms
- Browser shows `NET::ERR_CERT_DATE_INVALID`
- `curl` returns: `SSL certificate problem: certificate has expired`
- K3s API server unreachable due to expired kubeconfig cert

### Detection
- **Alert**: `CertificateExpiresIn30Days` → `CertificateExpired`
- **Metric**: `ssl_cert_not_after` (custom metric from blackbox exporter)
- **Manual**: `echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -enddate`

### Impact
- All HTTPS traffic to affected service fails
- API clients cannot authenticate
- If K8s certs expire: entire cluster is inaccessible

### Investigation

```bash
# Check certificate expiry for all HTTPS services
for host_port in localhost:443 localhost:8083 localhost:8085 localhost:8200; do
  expiry=$(echo | openssl s_client -connect $host_port 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  echo "$host_port: $expiry"
done

# Check Kubernetes certificate expiry
sudo kubeadm certs check-expiration 2>/dev/null || \
  kubectl get csr -A  # For K3s, check manually

# Check K3s server cert
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/server-ca.crt -noout -enddate

# Check certificate details
openssl s_client -connect localhost:443 < /dev/null 2>&1 | openssl x509 -noout -text | \
  grep -E "Subject:|Issuer:|Not Before|Not After"
```

### Resolution

```bash
# Regenerate self-signed certificate for Nginx
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ~/devops-infra/certs/server.key \
  -out ~/devops-infra/certs/server.crt \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

# Restart affected services
docker compose restart nginx traefik

# For K3s: rotate certificates
sudo k3s certificate rotate
sudo systemctl restart k3s

# For ArgoCD: renew TLS secret
kubectl -n argocd create secret tls argocd-server-tls \
  --cert=~/devops-infra/certs/server.crt \
  --key=~/devops-infra/certs/server.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/argocd-server -n argocd
```

### Prevention
- Set up Alertmanager alert 30 days before expiry
- Use cert-manager in Kubernetes for automatic renewal
- Document all certificate locations and expiry dates
- Schedule quarterly certificate audit

### SLO Impact
**Yes** — P1 if K3s API cert expires. P2 for user-facing HTTPS services.

---

## 7. PVC Mount Failed

### Scenario
A Kubernetes pod cannot mount its PersistentVolumeClaim (PVC), preventing it from starting.

### Symptoms
- Pod stuck in `Pending` or `ContainerCreating` state
- Event: `Unable to mount volumes for pod`
- PVC status shows `Lost` or `Bound` but node cannot access it

### Detection
- **Alert**: `KubePersistentVolumeFillingUp` or pod pending > 5 minutes
- **Event**: `FailedMount` in kubectl describe pod

### Impact
- Stateful application cannot start
- Data may be temporarily inaccessible

### Investigation

```bash
# Step 1: Check pod status and events
kubectl describe pod <pod-name> -n <namespace> | tail -30

# Step 2: Check PVC status
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Step 3: Check PV status
kubectl get pv
kubectl describe pv <pv-name>

# Step 4: Check storage class
kubectl get storageclass

# Step 5: Verify local path exists (for local-path provisioner)
ls -la /var/lib/rancher/k3s/storage/

# Step 6: Check K3s local-path provisioner logs
kubectl logs -n kube-system -l app=local-path-provisioner -f
```

### Resolution

```bash
# If PV is Released (previous PVC deleted): recreate binding
kubectl patch pv <pv-name> --type=merge \
  -p '{"spec":{"claimRef":{"name":"<pvc-name>","namespace":"<namespace>"}}}'

# If local path directory doesn't exist: create it
sudo mkdir -p /var/lib/rancher/k3s/storage/<pvc-uid>
sudo chmod 777 /var/lib/rancher/k3s/storage/<pvc-uid>

# Force delete stuck terminating PVC
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"metadata":{"finalizers":null}}'
kubectl delete pvc <pvc-name> -n <namespace> --force --grace-period=0

# Recreate PVC
kubectl apply -f pvc.yaml
```

### Prevention
- Monitor PVC capacity with Prometheus
- Use StorageClass with `allowVolumeExpansion: true`
- Back up PVC data regularly
- Test PVC restore procedure quarterly

### SLO Impact
**Yes** — stateful service unavailable. P2 severity.

---

## 8. Stale Lock File

### Scenario
A service fails to start because a lock file from a previous unclean shutdown still exists.

### Symptoms
- Service logs: `lock file exists`, `Another process is running`, `pid file already exists`
- Service fails to start after host reboot or crash

### Detection
- Service health check fails
- Docker container exits immediately (exit code 1)
- Service logs show lock file error

### Impact
- Service cannot start until lock file is removed
- Manual intervention required

### Investigation

```bash
# Check service logs
docker logs <container-name> 2>&1 | head -20

# Find lock files
find ~/devops-infra/data -name "*.lock" -o -name "*.pid" 2>/dev/null
find /tmp -name "*.lock" -mtime +1 2>/dev/null

# PostgreSQL lock file
docker exec postgres ls -la /var/run/postgresql/

# MySQL lock file  
docker exec mysql ls -la /var/lib/mysql/*.pid 2>/dev/null

# Redis lock file (in data directory)
docker exec redis ls -la /data/

# Check if original process is actually running
docker exec postgres pgrep -f postgres || echo "No postgres process"
```

### Resolution

```bash
# PostgreSQL: remove postmaster.pid if no process is running
docker exec postgres rm -f /var/run/postgresql/postmaster.pid
docker compose restart postgres

# MySQL: remove pid file
docker exec mysql rm -f /var/run/mysqld/mysqld.pid
docker compose restart mysql

# Generic: remove lock file and restart
docker exec <container> rm -f /path/to/lock/file
docker compose restart <service>

# If container can't start: use a temporary container to remove the file
docker run --rm -v <volume-name>:/data busybox rm -f /data/lockfile
```

### Prevention
- Use Docker health checks to detect failed starts
- Ensure containers have proper signal handling (SIGTERM → graceful shutdown)
- Configure `restart: unless-stopped` to auto-recover
- Implement startup scripts that check for and clean stale locks

### SLO Impact
P3 — service down, but recoverable quickly with simple intervention.

---

## 9. API Rate Limit Exceeded

### Scenario
A service or client has exceeded the rate limit of an external or internal API, causing 429 errors.

### Symptoms
- HTTP 429 Too Many Requests responses
- `rate limit exceeded` in application logs
- Docker Hub pull failures: `You have reached your pull rate limit`

### Detection
- **Alert**: Increase in HTTP 429 response codes
- **Log pattern**: `rate limit`, `429`, `too many requests`
- **Metric**: `http_response_status_code{code="429"}` counter

### Impact
- Service cannot complete operations requiring the rate-limited API
- May cause cascading failures if the API is critical

### Investigation

```bash
# Check Docker Hub rate limit status
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
curl -s --head -H "Authorization: Bearer $TOKEN" \
  https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest | \
  grep -E "RateLimit"

# Check application logs for 429 errors
docker logs my-app 2>&1 | grep -i "429\|rate limit" | tail -20

# Check Prometheus for rate-limited requests
# Query: rate(http_requests_total{status_code="429"}[5m])
```

### Resolution

```bash
# Docker Hub: authenticate to increase rate limit (100 → 200 pulls/6h)
docker login
# Or use a personal access token:
echo "$DOCKER_PAT" | docker login --username myuser --password-stdin

# Use local registry mirror to cache images
# Add to /etc/docker/daemon.json:
sudo tee -a /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["http://localhost:5000"]
}
EOF
sudo systemctl restart docker

# For internal API rate limits: implement request queuing / back-off
# Temporary: reduce polling frequency in consuming service config
```

### Prevention
- Authenticate to Docker Hub (or use Docker Hub paid plan)
- Cache images in local Docker Registry (port 5000)
- Implement exponential backoff in all API clients
- Monitor rate limit headers and alert before exhaustion

### SLO Impact
P3 if only affecting non-critical pull operations. P2 if blocking CI/CD pipeline.

---

## 10. DNS Resolution Failed

### Scenario
Services cannot resolve hostnames, causing connection failures to databases, external services, or other containers.

### Symptoms
- `getaddrinfo: Name or service not known`
- `could not resolve host: postgres`
- CoreDNS logs show resolution failures
- Intermittent connection failures to services accessed by hostname

### Detection
- **Alert**: CoreDNS error rate increase
- **Metric**: `coredns_dns_response_rcode_count_total{rcode="NXDOMAIN"}`
- **Log**: DNS SERVFAIL or NXDOMAIN entries

### Impact
- Services cannot communicate with each other via hostname
- External API calls fail

### Investigation

```bash
# Step 1: Test DNS from within a container
docker exec my-app nslookup postgres
docker exec my-app nslookup google.com

# Step 2: Check /etc/resolv.conf inside container
docker exec my-app cat /etc/resolv.conf

# Step 3: Test from K8s pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup grafana.monitoring.svc.cluster.local

# Step 4: Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Step 5: Check CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml

# Step 6: Check host DNS
cat /etc/resolv.conf
resolvectl status
```

### Resolution

```bash
# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Fix WSL2 DNS issue
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
sudo chattr +i /etc/resolv.conf

# Restart Docker to pick up new DNS settings
sudo systemctl restart docker

# For K8s: check that CoreDNS can reach upstream resolver
kubectl exec -n kube-system -it $(kubectl get pod -n kube-system -l k8s-app=kube-dns -o name | head -1) \
  -- nslookup google.com 8.8.8.8
```

### Prevention
- Set explicit DNS servers in Docker daemon.json
- Use static /etc/hosts entries for frequently accessed services
- Monitor CoreDNS availability

### SLO Impact
**Yes** — DNS failure is broadly impactful. P1 if service-wide, P2 if isolated.

---

## 11. TLS Handshake Timeout

### Scenario
TLS connections fail to complete the handshake within the timeout period, causing connection failures.

### Symptoms
- `TLS handshake timeout`
- `i/o timeout during TLS handshake`
- Intermittent connection failures to HTTPS endpoints

### Detection
- **Alert**: HTTP error rate increase on HTTPS endpoints
- **Log**: TLS handshake timeout messages
- **Metric**: `probe_ssl_earliest_cert_expiry` from blackbox exporter

### Impact
- HTTPS services inaccessible
- API clients fail with SSL errors

### Investigation

```bash
# Step 1: Test TLS handshake manually
openssl s_client -connect localhost:443 -debug 2>&1 | head -50

# Step 2: Check TLS version and cipher support
nmap --script ssl-enum-ciphers -p 443 localhost

# Step 3: Check nginx TLS config
docker exec nginx nginx -T | grep -A10 "ssl"

# Step 4: Check for certificate chain issues
openssl s_client -connect localhost:443 -showcerts 2>&1 | grep "subject\|issuer"

# Step 5: Check system time (TLS is time-sensitive)
date
timedatectl status

# Step 6: Network congestion causing timeout
ping -c 20 localhost | tail -3
```

### Resolution

```bash
# Fix time sync issues
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Fix Nginx SSL config
cat > /tmp/nginx-ssl.conf <<EOF
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
EOF
# Apply to nginx config and restart
docker compose restart nginx
```

### Prevention
- Monitor certificate expiry 30+ days in advance
- Keep system time synchronised
- Use TLS 1.2/1.3 only; disable TLS 1.0/1.1

### SLO Impact
P2 — HTTPS service unavailable.

---

## 12. Registry Pull Rate Limit

### Scenario
Docker image pulls from Docker Hub fail due to rate limiting (unauthenticated: 100 pulls/6h; authenticated free: 200 pulls/6h).

### Symptoms
- `docker: Error response from daemon: toomanyrequests: Too Many Requests`
- CI/CD pipeline failures at image pull step
- `You have reached your pull rate limit`

### Detection
- **Alert**: Docker pull failures in CI pipeline
- **Log**: `toomanyrequests` in Docker daemon logs or pipeline output

### Impact
- CI/CD pipelines fail
- New pod deployments fail if image not cached

### Investigation

```bash
# Check current rate limit status
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
REMAINING=$(curl -s --head -H "Authorization: Bearer $TOKEN" \
  https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest | \
  grep -i "ratelimit-remaining" | awk '{print $2}')
echo "Pulls remaining: $REMAINING"

# Check which images are being pulled most
docker events --filter type=image --filter event=pull --since 6h
```

### Resolution

```bash
# Log in to Docker Hub
docker login -u <username>

# Mirror images to local registry
docker pull nginx:alpine
docker tag nginx:alpine localhost:5000/nginx:alpine
docker push localhost:5000/nginx:alpine

# Update docker-compose.yml to use local registry
# Change: image: nginx:alpine
# To:     image: localhost:5000/nginx:alpine

# Pre-pull all required images during off-peak hours
cat ~/devops-infra/scripts/pull-all-images.sh | bash
```

### Prevention
- Store all images in local Docker Registry (port 5000)
- Authenticate all CI/CD runners to Docker Hub
- Use `imagePullPolicy: IfNotPresent` in K8s for local dev
- Maintain a `pull-all-images.sh` script and run weekly

### SLO Impact
P2 — CI/CD blocked, new deployments may fail.

---

## 13. Quorum Loss (Consul/etcd)

### Scenario
A distributed consensus system (Consul or K3s's embedded etcd) loses quorum, preventing leader election and blocking all state changes.

### Symptoms
- Consul: all nodes show as `failed` or `leader election in progress`
- K3s API server returns 503 for all write operations
- `etcdctl endpoint status` shows no healthy members with quorum

### Detection
- **Alert**: `ConsulClusterHealthCritical`
- **Metric**: `consul_health_node_status` all showing degraded

### Impact
- **P1** — Consul: service mesh, KV store, and service discovery unavailable
- **P1** — etcd: K8s cluster cannot schedule pods or accept API writes

### Investigation

```bash
# Consul health
curl -s http://localhost:8500/v1/status/leader
curl -s http://localhost:8500/v1/status/peers
curl -s http://localhost:8500/v1/agent/self | jq '.Stats.raft'

# K3s etcd (embedded)
sudo k3s etcd-snapshot list
sudo /var/lib/rancher/k3s/data/current/bin/etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert /var/lib/rancher/k3s/server/tls/etcd/client.crt \
  --key /var/lib/rancher/k3s/server/tls/etcd/client.key \
  endpoint status --write-out=table
```

### Resolution

```bash
# For single-node setup (this lab): restart the service
docker compose restart consul
sudo systemctl restart k3s

# Restore K3s from etcd snapshot
sudo k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot.db

# Consul: force new election
curl -X POST http://localhost:8500/v1/operator/raft/configuration
```

### Prevention
- In production: always run 3 or 5 nodes for quorum
- Take regular etcd snapshots
- Monitor Raft term and leader changes

### SLO Impact
**P1** — immediate escalation required.

---

## 14. Leader Election Failure

### Scenario
A distributed system component (e.g., ArgoCD, Consul agent) fails to elect a new leader after the current leader disappears.

### Symptoms
- Service is unresponsive but containers are running
- Log shows repeated `waiting for leadership` or `election in progress`
- API requests return 503

### Detection
- **Alert**: Pod is running but health check failing
- **Metric**: `leader_election_master_status` is 0

### Investigation

```bash
# ArgoCD leader election
kubectl get lease -n argocd
kubectl describe lease argocd-application-controller -n argocd

# Check which pods think they are leader
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller | \
  grep -i "leader\|election"
```

### Resolution

```bash
# Delete the Lease object to force re-election
kubectl delete lease argocd-application-controller -n argocd

# Restart the deployment
kubectl rollout restart deployment/argocd-application-controller -n argocd

# If multiple replicas are split-brain: scale down to 1, then back up
kubectl scale deployment argocd-application-controller -n argocd --replicas=0
sleep 10
kubectl scale deployment argocd-application-controller -n argocd --replicas=1
```

### Prevention
- Monitor leader election metrics
- Ensure consistent network connectivity between replicas

### SLO Impact
P2 — GitOps / orchestration blocked.

---

## 15. Cache Invalidation Storm

### Scenario
A large number of cache keys expire simultaneously (thundering herd), causing all requests to hit the database directly.

### Symptoms
- Redis: sudden drop in cache hit rate
- PostgreSQL/MySQL: spike in concurrent connections and query load
- Increased response times across all services

### Detection
- **Metric**: `redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)` drops sharply
- **Metric**: PostgreSQL `pg_stat_activity` shows sudden connection spike
- **Visual**: Grafana shows correlated Redis miss spike + DB CPU spike

### Investigation

```bash
# Redis hit rate
docker exec redis redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Keys with TTL (check for clustering)
docker exec redis redis-cli --scan | head -100 | xargs -I{} docker exec redis redis-cli TTL {}

# DB connection count
docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

### Resolution

```bash
# Add jitter to cache TTLs (fix in application code)
# Instead of: cache.set(key, value, ttl=3600)
# Use:        cache.set(key, value, ttl=3600 + random.randint(0, 300))

# Temporarily increase Redis maxmemory-policy to keep more keys
docker exec redis redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Warm the cache manually for hot keys
# Application-specific: trigger a cache warm-up script
bash ~/devops-infra/scripts/cache-warmup.sh
```

### Prevention
- Add random jitter to all cache TTLs
- Use cache stampede protection (mutex / probabilistic early expiration)
- Monitor cache hit rate and alert if it drops below 80%

### SLO Impact
P2 during the storm — response times degrade for all users.

---

## 16. Resource Quota Exceeded

### Scenario
A Kubernetes namespace has reached its ResourceQuota limit, preventing new pod creation.

### Symptoms
- Pod creation fails: `Error from server (Forbidden): pods ... exceeded quota`
- Deployments stuck with `0/1 replicas`
- `kubectl describe quota` shows limits at 100%

### Detection
- **Alert**: `KubeQuotaAlmostFull` (> 90%)
- **Event**: `exceeded quota` in namespace events

### Investigation

```bash
# Check all resource quotas
kubectl get resourcequota -A

# Detailed quota usage
kubectl describe resourcequota -n <namespace>

# Find resource-hungry pods
kubectl top pods -n <namespace> --sort-by=memory
kubectl top pods -n <namespace> --sort-by=cpu

# Check LimitRange settings
kubectl get limitrange -n <namespace>
kubectl describe limitrange -n <namespace>
```

### Resolution

```bash
# Increase quota temporarily
kubectl patch resourcequota <quota-name> -n <namespace> \
  --type=merge \
  -p '{"spec":{"hard":{"requests.memory":"8Gi","limits.memory":"16Gi"}}}'

# Delete unused pods/deployments to free quota
kubectl delete pods -n <namespace> -l environment=staging

# Scale down non-critical deployments
kubectl scale deployment non-critical-app -n <namespace> --replicas=0
```

### Prevention
- Set quotas with 20% headroom above expected usage
- Review and adjust quotas quarterly
- Alert at 80% quota utilisation, not 100%

### SLO Impact
P2 — deployments and scaling blocked.

---

## 17. Deployment Rollback Needed

### Scenario
A new deployment introduces a regression (errors, performance degradation, broken functionality) and must be reverted.

### Symptoms
- Error rate spikes after deployment
- Latency increases above SLO threshold
- Health checks start failing for new pods

### Detection
- **Metric**: `http_request_errors_total` spikes after deployment event
- **Correlation**: Error spike coincides with `kube_deployment_metadata_generation` increase

### Investigation

```bash
# Check deployment history
kubectl rollout history deployment/<name> -n <namespace>

# Compare current vs previous deployment config
kubectl rollout history deployment/<name> -n <namespace> --revision=N -o yaml | diff - \
  <(kubectl rollout history deployment/<name> -n <namespace> --revision=$((N-1)) -o yaml)

# Check pod logs for errors
kubectl logs -l app=<name> -n <namespace> --tail=50 | grep -i "error\|exception\|fatal"

# Check error rate (Prometheus)
# Query: rate(http_requests_total{status_code=~"5.."}[5m])
```

### Resolution

```bash
# Rollback to previous version immediately
kubectl rollout undo deployment/<name> -n <namespace>

# Monitor rollback progress
kubectl rollout status deployment/<name> -n <namespace>

# Rollback to specific revision
kubectl rollout undo deployment/<name> -n <namespace> --to-revision=<N>

# Helm rollback
helm rollback <release-name> <revision> -n <namespace>
helm history <release-name> -n <namespace>  # Find revision number

# Verify rollback succeeded
kubectl get pods -n <namespace> -l app=<name>
kubectl logs -l app=<name> -n <namespace> --tail=20
```

### Prevention
- Implement progressive delivery (canary/blue-green) for production
- Automate rollback on error rate threshold breach
- Maintain immutable image tags (never use `latest`)
- Run integration tests before deploying

### SLO Impact
**Yes** — error budget consumed during the incident window.

---

## 18. Orchestrator Failure (K3s Down)

### Scenario
The K3s Kubernetes control plane is unavailable, preventing pod scheduling, scaling, and API access.

### Symptoms
- `kubectl` returns: `The connection to the server localhost:6443 was refused`
- All pod operations fail
- ArgoCD shows cluster as unreachable

### Detection
- **Alert**: `KubeAPIServerDown`
- **Probe**: `probe_success{job="kubernetes-api"}` is 0

### Impact
- **P1** — No new deployments, no pod scheduling, no ConfigMap/Secret updates
- Existing running pods continue (kubelet is independent of API server for existing pods)

### Investigation

```bash
# Check K3s service status
sudo systemctl status k3s

# View K3s logs
sudo journalctl -u k3s --since "10 minutes ago" -f

# Check if port 6443 is listening
ss -tlnp | grep 6443

# Check available resources
free -h
df -h /var/lib/rancher/

# Check if etcd is healthy (K3s embedded)
sudo /var/lib/rancher/k3s/data/current/bin/etcdctl \
  --endpoints https://127.0.0.1:2379 \
  --cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert /var/lib/rancher/k3s/server/tls/etcd/client.crt \
  --key /var/lib/rancher/k3s/server/tls/etcd/client.key \
  endpoint health
```

### Resolution

```bash
# Restart K3s
sudo systemctl restart k3s

# Wait for API server to be ready
until kubectl cluster-info; do
  echo "Waiting for K3s API..."; sleep 5
done

# If K3s won't start: check disk space (etcd is sensitive to disk pressure)
df -h /var/lib/rancher/k3s/

# If etcd is corrupted: restore from snapshot
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=$(ls -t ~/devops-infra/backups/k3s-snapshot-*.db | head -1)

# Verify all system pods are running
kubectl get pods -n kube-system
```

### Prevention
- Take etcd snapshots daily: `k3s etcd-snapshot save`
- Monitor K3s API availability with blackbox exporter
- Ensure sufficient disk space on `/var/lib/rancher/` volume
- Set up K3s as a systemd service with `Restart=always`

### SLO Impact
**P1** — immediate escalation, all K8s-dependent services affected.

---

## 19. Node Cordon and Drain

### Scenario
Planned maintenance requires evacuating all pods from a node before taking it offline.

### Symptoms
- This is a **planned operation**, not a failure scenario
- Pods are rescheduled to other nodes during the drain

### Detection
- N/A — initiated by operator

### Impact
- Temporary pod disruption during drain
- Workloads with `PodDisruptionBudget` may block drain

### Investigation

```bash
# Check node status and pod count
kubectl get nodes
kubectl get pods -A -o wide | grep <node-name>

# Check for PodDisruptionBudgets that may block drain
kubectl get pdb -A
kubectl describe pdb -A
```

### Resolution (Procedure)

```bash
# Step 1: Cordon the node (prevent new scheduling)
kubectl cordon <node-name>

# Step 2: Drain the node (evict all pods)
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=300s

# Step 3: Verify no non-daemonset pods remain
kubectl get pods -A -o wide | grep <node-name> | grep -v DaemonSet

# Step 4: Perform maintenance
# (OS updates, hardware replacement, etc.)

# Step 5: Uncordon when ready to return to service
kubectl uncordon <node-name>

# Step 6: Verify node is scheduling again
kubectl get nodes
kubectl run test-pod --image=busybox --rm -it --restart=Never -- echo "Node is ready"
```

### Prevention
- Document all planned maintenance in the change management log
- Notify team before cordoning nodes
- Ensure cluster has sufficient capacity to absorb evicted pods

### SLO Impact
**Planned** — should not impact SLO if capacity is available. Use maintenance window + silence alerts.

---

## 20. Chaos Engineering Test

### Scenario
Intentionally injecting failures to validate system resilience and incident response procedures.

### Symptoms
- This is a **controlled experiment**, not an unplanned incident
- Failures are introduced intentionally to observe system behaviour

### Experiment Design

```bash
# ─── Experiment 1: Kill a pod and verify auto-recovery ───────────
# Hypothesis: K8s will restart the pod within 60 seconds
kubectl delete pod -l app=grafana -n monitoring
watch kubectl get pods -n monitoring -l app=grafana

# ─── Experiment 2: Fill disk and verify alert fires ──────────────
# WARNING: Use a test partition, not your main disk
dd if=/dev/zero of=/tmp/chaos-disk-fill bs=1M count=1000
# Observe: Alertmanager should fire DiskSpaceLow within 1 minute
rm /tmp/chaos-disk-fill

# ─── Experiment 3: Network partition between services ────────────
# Add iptables rules to block postgres from app container
POSTGRES_IP=$(docker inspect postgres --format '{{.NetworkSettings.IPAddress}}')
sudo iptables -A OUTPUT -d $POSTGRES_IP -p tcp --dport 5432 -j DROP
# Observe: application should show DB connection errors within timeout period
# Cleanup:
sudo iptables -D OUTPUT -d $POSTGRES_IP -p tcp --dport 5432 -j DROP

# ─── Experiment 4: Memory pressure ───────────────────────────────
# Run a memory-consuming process
docker run --rm --memory=2g progrium/stress stress --vm 1 --vm-bytes 1800M --timeout 120s
# Observe: cAdvisor and Grafana show memory pressure

# ─── Experiment 5: CPU spike ─────────────────────────────────────
docker run --rm progrium/stress stress --cpu 4 --timeout 60s
# Observe: Node Exporter metric spikes, Grafana alert fires

# ─── Experiment 6: DNS failure ───────────────────────────────────
sudo systemctl stop systemd-resolved
# Observe: Docker container DNS failures
sudo systemctl start systemd-resolved
```

### Chaos Test Checklist

| Test | Expected Outcome | Alert Should Fire? | Pass/Fail |
|------|-----------------|-------------------|-----------|
| Kill pod | Auto-restart < 60s | Yes: KubePodCrashLooping | |
| Disk 90% full | Alert at 85% threshold | Yes: HostDiskSpaceLow | |
| DB network cut | App shows DB error | No (if properly handled) | |
| Memory pressure | Grafana shows spike | Yes: HighMemoryUsage | |
| CPU spike | CPU alert fires | Yes: HighCPUUsage | |
| DNS failure | Errors in dependent services | Yes | |

### Prevention
- Always run chaos tests in a time-boxed window
- Ensure monitoring is working BEFORE running chaos tests
- Have a clear rollback plan for each experiment
- Document results in the MTTR/MTBF table

### SLO Impact
**Planned** — silence non-critical alerts during chaos tests. Record error budget impact.

---

## Post-Incident Review Template

```markdown
## Post-Incident Review — INC-YYYY-NNN

| Field | Value |
|-------|-------|
| Incident ID | INC-YYYY-NNN |
| Date | YYYY-MM-DD |
| Start Time | HH:MM UTC |
| End Time | HH:MM UTC |
| Duration | Xh Ym |
| Severity | P1 / P2 / P3 |
| Author | <name> |
| Reviewers | <names> |
| SLO Breached | Yes / No |

### Executive Summary
<2–3 sentences: what happened, impact, how resolved>

### Timeline
| Time (UTC) | Actor | Event |
|-----------|-------|-------|
| HH:MM | System | Alert fired: <alert name> |
| HH:MM | <engineer> | Investigation started |
| HH:MM | <engineer> | Root cause identified |
| HH:MM | <engineer> | Fix deployed |
| HH:MM | System | Service restored |

### Root Cause Analysis
<5-Why analysis or detailed technical explanation>

**Why did this happen?**
1. Because...
2. Because...
3. Because...

### What Went Well
- Detection was fast (alert fired within X minutes)
- Runbook was accurate and actionable
- Communication was clear

### What Could Be Improved
- Alert threshold was too high (fired too late)
- Runbook step 3 was unclear
- Missing monitoring for <component>

### Action Items
| # | Action | Owner | Due | Priority | Issue Link |
|---|--------|-------|-----|----------|------------|
| 1 | Add monitoring for X | <name> | YYYY-MM-DD | P1 | |
| 2 | Update runbook step 3 | <name> | YYYY-MM-DD | P3 | |

### SLO Impact
- **SLO**: 99.9% availability (4.38 hours error budget/month)
- **Downtime**: Xm Ys
- **Error Budget Consumed**: X%
- **Remaining Budget This Month**: X%
```

---

## Incident Timeline Template

```
INCIDENT TIMELINE — INC-YYYY-NNN
==================================
Severity  : P1 / P2 / P3
Service   : <affected service>
Date      : YYYY-MM-DD

TIME (UTC)  ACTOR           EVENT
──────────────────────────────────────────────────────────────────
HH:MM       Alertmanager    Alert fired: <AlertName> — <description>
HH:MM       <engineer>      Acknowledged alert, began investigation
HH:MM       <engineer>      Identified symptom: <what was observed>
HH:MM       <engineer>      Ran: <command> — output: <result>
HH:MM       <engineer>      Hypothesis: <root cause theory>
HH:MM       <engineer>      Applied fix: <action taken>
HH:MM       <engineer>      Verified: service responding normally
HH:MM       <engineer>      Incident resolved, monitoring for recurrence
HH:MM       <engineer>      Post-incident review scheduled

TOTAL DURATION: Xh Ym
TTD (Time to Detect): Xm
TTR (Time to Resolve from detection): Xh Ym
```

---

## MTTR/MTBF Tracking Table

| # | Date | Incident | Severity | TTD | TTR | Root Cause Category | Recurrence |
|---|------|----------|----------|-----|-----|---------------------|------------|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |

**Root Cause Categories:**
- `INFRA` — Hardware or OS level
- `CONFIG` — Misconfiguration
- `CAPACITY` — Resource exhaustion (disk, memory, CPU)
- `NETWORK` — Network failure or misconfiguration
- `DEPENDENCY` — External service or upstream failure
- `DEPLOY` — Caused by a new deployment
- `CERT` — Certificate expiry
- `HUMAN` — Human error
- `UNKNOWN` — Root cause not identified

**Metrics Definitions:**
- **TTD** (Time to Detect): Alert fire time → engineer acknowledgement
- **TTR** (Time to Resolve): Detection → service restoration
- **MTTR** (Mean TTR): Average TTR across all incidents
- **MTBF** (Mean Time Between Failures): Average time between incidents of same type

---

*Return to [OPERATIONS.md](./OPERATIONS.md) for service management commands.*
*See [LEARNING-PATH.md](./LEARNING-PATH.md) for SRE practices study plan.*
