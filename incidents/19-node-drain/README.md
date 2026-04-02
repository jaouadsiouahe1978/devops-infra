# Incident 19 — Node Cordon and Drain

## Scenario
A worker node needs maintenance (kernel update, hardware issue). You must safely evict all pods before taking the node offline, without causing downtime.

## Symptoms (trigger)
- Node showing high CPU/memory
- Hardware alert on node
- Planned maintenance window

## Simulate
```bash
docker compose up -d
docker logs incident-node-drain -f

# If K3s available:
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

## Procedure
```bash
# 1. Check which pods are on the node
kubectl get pods -o wide | grep <node-name>

# 2. Cordon (prevent new scheduling)
kubectl cordon <node-name>
kubectl get nodes  # STATUS: Ready,SchedulingDisabled

# 3. Drain (evict all pods)
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# 4. Verify pods moved
kubectl get pods -o wide

# 5. Perform maintenance
sudo apt upgrade -y && sudo reboot

# 6. Uncordon when back
kubectl uncordon <node-name>
kubectl get nodes  # STATUS: Ready
```

## Important Notes
- DaemonSets pods are NOT evicted (use `--ignore-daemonsets`)
- Pods with emptyDir data will LOSE data (use `--delete-emptydir-data`)
- Ensure PodDisruptionBudgets allow eviction
- With `kubectl drain`, PDB violations will block the drain

## Prevention
- Set `PodDisruptionBudget` for all critical workloads (min 1 always available)
- Ensure replicas >= 2 for all deployments
- Use `topologySpreadConstraints` to spread across nodes

## Post-Incident
- MTTR target: 0 downtime if PDB and replicas configured correctly
- Root cause: planned maintenance — this is normal operations
