# Incident 05 — Network Timeout / High Latency

## Scenario
A backend service becomes slow (simulated 30s response), causing client timeouts and cascading failures.

## Symptoms
- HTTP 504 Gateway Timeout errors
- `curl: (28) Operation timed out`
- Prometheus `http_request_duration_seconds` spikes

## Simulate
```bash
docker compose up -d
docker logs incident-timeout-client -f
```

## Diagnosis
```bash
# Check latency
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:18080/

# Check network between containers
docker exec incident-timeout-client ping slow-backend
docker exec incident-timeout-client traceroute slow-backend

# Check if backend is overwhelmed
docker stats incident-slow-backend
```

## Resolution
```bash
# Immediate: restart slow service
docker restart incident-slow-backend

# Add timeout at load balancer level (Nginx/Traefik)
# proxy_read_timeout 10s;

# Implement circuit breaker in application
```

## Prevention
- Always set client-side timeouts (`--max-time 5`)
- Configure Nginx/Traefik timeouts
- Implement circuit breaker pattern (Hystrix, Resilience4j)
- Alert on `p99 latency > 2s`

## Post-Incident
- MTTR target: < 10 min
- Root cause: no timeout configured, slow downstream dependency
