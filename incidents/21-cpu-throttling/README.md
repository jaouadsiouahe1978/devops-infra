# Incident 21 — CPU Throttling

## Scenario
A container hits its CPU limit and gets throttled by the kernel cgroups, causing severe latency spikes without the pod crashing. No OOMKill, no restart — just slowness.

## Symptoms
- API response times 10x higher than normal
- `kubectl top pod` shows CPU near limit but pod is Running
- Prometheus `container_cpu_cfs_throttled_seconds_total` spiking
- Grafana shows CPU throttle ratio > 50%
- No restarts, no errors in logs — just slow

## Simulate
```bash
docker compose up -d
docker stats incident-cpu-throttle
# Watch CPU get throttled at the limit
```

## Diagnosis
```bash
# Check CPU usage vs limits
kubectl top pods -A
kubectl describe pod <pod-name> | grep -A5 Limits

# Check throttling metrics (Prometheus)
# container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total

# Live check inside container
kubectl exec -it <pod-name> -- cat /sys/fs/cgroup/cpu/cpu.stat
# Look for: throttled_time (nanoseconds throttled)

# Check recent events
kubectl get events --sort-by='.lastTimestamp' | grep -i throttl
```

## Resolution
```bash
# Option 1: Increase CPU limit
kubectl patch deployment app-backend -p '{"spec":{"template":{"spec":{"containers":[{"name":"app-backend","resources":{"limits":{"cpu":"500m"}}}]}}}}'

# Option 2: Optimize the application (reduce CPU usage)
# Profile with: kubectl exec -it <pod> -- top

# Option 3: Remove CPU limit if appropriate (use requests only)
kubectl edit deployment app-backend
# Remove limits.cpu, keep requests.cpu

# Verify fix
kubectl rollout status deployment/app-backend
kubectl top pods
```

## Prevention
- Set CPU `requests` accurately (based on profiling)
- Set CPU `limits` at 2-3x requests (not too tight)
- Alert on: `container_cpu_cfs_throttled_seconds_total > 0.25`
- Use VPA (Vertical Pod Autoscaler) to auto-tune resources

## Post-Incident
- MTTR target: < 20 min
- Root cause: CPU limit too low relative to actual workload
- Key insight: CPU throttling is silent — no crash, just latency
