# Incident 16 — Resource Quota Exceeded

## Scenario
A pod/container hits its CPU or memory quota. In K8s, new pods in the namespace can't be scheduled. In Docker, containers get OOMKilled or CPU-throttled.

## Symptoms
- K8s: `Error creating: pods "app" is forbidden: exceeded quota`
- Docker: Container OOMKilled or heavily throttled
- `kubectl describe resourcequota` shows limits reached

## Simulate
```bash
docker compose up
docker logs incident-quota-exceeded
docker stats incident-quota-exceeded
```

## Diagnosis
```bash
# K8s: check namespace quotas
kubectl describe resourcequota -n <namespace>
kubectl get events -n <namespace> | grep -i quota

# Docker: check resource usage
docker stats --no-stream
docker inspect incident-quota-exceeded | jq '.[0].HostConfig | {Memory, CpuQuota}'

# Check OOM kills
dmesg | grep -i oom | tail -20
```

## Resolution
```bash
# K8s: increase quota
kubectl edit resourcequota <quota-name> -n <namespace>

# Or clean up unused resources
kubectl delete pods --field-selector=status.phase==Succeeded -n <namespace>

# Docker: increase limits
# mem_limit: 256m  (in docker-compose.yml)

# Optimize application memory usage
```

## Prevention
- Set LimitRange defaults in K8s namespaces
- Monitor `kube_resourcequota` vs limits
- Alert when quota usage > 80%
- Use VPA (Vertical Pod Autoscaler) for right-sizing

## Post-Incident
- MTTR target: < 15 min
- Root cause: quota set too low for actual application requirements
