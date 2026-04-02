# Incident 18 — Orchestrator Failure (K3s Down)

## Scenario
The Kubernetes/K3s API server crashes. Existing workloads keep running (kubelet is independent), but no new deployments, scaling, or scheduling is possible.

## Symptoms
- `kubectl` returns: `The connection to the server was refused`
- New pods cannot be scheduled
- HPA, controllers, and operators are offline
- Prometheus loses K8s metrics

## Simulate
```bash
docker compose up -d
docker logs incident-k8s-down

# If K3s is installed:
sudo systemctl stop k3s
kubectl get nodes  # connection refused
```

## Diagnosis
```bash
# Check K3s service
sudo systemctl status k3s
sudo journalctl -u k3s -n 100 --no-pager

# Check API server process
ps aux | grep kube-apiserver
ps aux | grep k3s

# Check logs
sudo cat /var/lib/rancher/k3s/server/logs/server-log.txt 2>/dev/null | tail -50

# Check etcd health
sudo k3s etcd-snapshot ls 2>/dev/null

# Check disk space (common cause)
df -h /var/lib/rancher/
```

## Resolution
```bash
# Restart K3s
sudo systemctl restart k3s

# Wait for API server
until kubectl get nodes; do sleep 5; done

# If disk full — clean up
docker system prune -f
crictl rmi --prune

# If etcd corrupted — restore from snapshot
k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>
```

## Prevention
- Monitor `kube_apiserver_up` = 0 alert
- Monitor disk space on K3s data dir
- Regular etcd snapshots (`k3s etcd-snapshot save`)
- Set up K3s HA with embedded etcd (3 server nodes)

## Post-Incident
- MTTR target: < 15 min
- Root cause: API server OOM or disk full on etcd
