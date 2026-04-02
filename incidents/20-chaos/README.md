# Incident 20 — Chaos Engineering Test

## Scenario
Intentional injection of failures to test system resilience: pod kills, network delays, CPU/memory spikes, dependency failures.

## Goals
- Verify services auto-recover
- Find hidden single points of failure
- Validate monitoring and alerting
- Measure MTTR under controlled conditions

## Simulate
```bash
docker compose up -d
docker logs incident-chaos-engine -f
```

## Chaos Experiments

### 1. Pod Kill
```bash
# K8s: kill a pod, verify it restarts
kubectl delete pod -l app=myapp
watch kubectl get pods  # should restart within 30s
```

### 2. CPU Spike
```bash
# Inject CPU load
docker run --rm -it --cpus=0.5 alpine sh -c "while true; do :; done" &
# Monitor: docker stats, Grafana dashboard
```

### 3. Memory Pressure
```bash
# Inject memory pressure
docker run --rm -it --memory=128m alpine sh -c "
cat /dev/zero | head -c 200m | tail
" || echo "OOMKilled as expected"
```

### 4. Network Partition
```bash
# Disconnect a container from its network
docker network disconnect <network> <container>
sleep 30
docker network connect <network> <container>
```

### 5. Disk I/O Saturation
```bash
# Fill disk with writes
dd if=/dev/zero of=/tmp/chaos-test bs=1M count=500
rm /tmp/chaos-test
```

### 6. Kill Dependencies
```bash
# Kill Redis, see how app behaves
docker stop redis-prod
sleep 10
docker start redis-prod
```

## Tools
- **Chaos Monkey** — random pod termination
- **Pumba** — Docker chaos tool (network, stress, kill)
- **LitmusChaos** — K8s chaos framework
- `~/devops-infra/scripts/chaos-tools.sh`

## Metrics to Watch
- Pod restart count
- Error rate (5xx)
- P99 latency
- MTTR (time to self-heal)

## Post-Chaos Report
| Test | Expected | Actual | MTTR |
|------|----------|--------|------|
| Pod kill | Auto-restart < 30s | | |
| CPU spike | Throttled, no crash | | |
| Memory OOM | OOMKill + restart | | |
| Network partition | Reconnect on restore | | |

## Post-Incident
- Run monthly in staging
- Run quarterly in production (with approval)
- Document all findings in post-mortem
