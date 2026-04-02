# Incident 03 — Memory Leak

## Scenario
An application continuously allocates memory without releasing it, eventually causing OOMKill.

## Symptoms
- Container repeatedly restarting (OOMKilled)
- `kubectl describe pod` shows `OOMKilled` reason
- Prometheus `container_memory_usage_bytes` climbing steadily

## Simulate
```bash
docker compose up -d
docker stats incident-memory-leak
docker logs incident-memory-leak -f
```

## Diagnosis
```bash
# Check memory usage
docker stats --no-stream
docker inspect incident-memory-leak | grep -i memory

# Check OOM events
dmesg | grep -i oom
```

## Resolution
```bash
# Immediate: restart container
docker restart incident-memory-leak

# Set memory limits
# mem_limit: 256m in docker-compose.yml

# Long-term: profile the application
# Use memory profiler to find leak
```

## Prevention
- Set `mem_limit` on all containers
- Alert on `container_memory_usage_bytes > 80%`
- Use K8s LimitRange for automatic limits

## Post-Incident
- MTTR target: < 10 min
- Root cause: unbounded in-memory list accumulation
