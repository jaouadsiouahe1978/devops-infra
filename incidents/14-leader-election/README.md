# Incident 14 — Leader Election Failure

## Scenario
The current leader crashes. Followers detect the heartbeat timeout and trigger a new election. During the election window, writes are unavailable.

## Symptoms
- `no leader` errors during election window
- Write operations fail temporarily
- Logs show: `heartbeat timeout`, `starting election`

## Simulate
```bash
docker compose up
# Watch the election happen in real-time
docker logs incident-leader-1 -f &
docker logs incident-leader-2 -f &
docker logs incident-leader-3 -f
```

## Diagnosis
```bash
# K8s: check endpoint leader
kubectl get endpoints -n kube-system kube-scheduler -o yaml | grep -i leader

# Consul: check leader
consul operator raft list-peers

# etcd: check leader
etcdctl endpoint status --cluster -w table

# Check election timeout logs
kubectl logs -n kube-system kube-controller-manager-* | grep -i "leader"
```

## Resolution
```bash
# Usually self-heals within election timeout (150-300ms for Raft)
# If stuck, restart the problematic node

docker restart incident-leader-1

# Force new K8s leader election
kubectl delete lease kube-controller-manager -n kube-system
```

## Prevention
- Tune election timeouts appropriately (not too low = false positives)
- Monitor `etcd_server_leader_changes_seen_total` rate
- Spread nodes across failure domains
- Alert on frequent leader changes (> 3/hour)

## Post-Incident
- MTTR target: < 2 min (auto-recovery)
- Root cause: leader crashed, no graceful handoff
