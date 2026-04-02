# Incident 12 — Registry Pull Rate Limit

## Scenario
Docker Hub rate limits anonymous image pulls (100/6h). CI/CD pipelines start failing with `toomanyrequests`.

## Symptoms
- `Error: toomanyrequests: You have reached your pull rate limit`
- CI/CD jobs fail at image pull step
- `docker pull` returns 429

## Simulate
```bash
docker compose up -d
docker logs incident-registry-ratelimit
```

## Diagnosis
```bash
# Check rate limit status
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
curl -s --head -H "Authorization: Bearer $TOKEN" \
  https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest \
  2>&1 | grep -i ratelimit

# Check your IP's remaining pulls
# RateLimit-Remaining: 76;w=21600
```

## Resolution
```bash
# Option 1: Authenticate with Docker Hub
docker login -u <username> -p <password>

# Option 2: Use local Nexus/Registry mirror
# In /etc/docker/daemon.json:
{
  "registry-mirrors": ["http://localhost:5000"]
}

# Option 3: Pull and cache images in local registry
docker pull nginx:alpine
docker tag nginx:alpine localhost:5000/nginx:alpine
docker push localhost:5000/nginx:alpine

# Option 4: Use alternative registries
# gcr.io, quay.io, ghcr.io
```

## Prevention
- Run a local registry mirror (Nexus/Harbor/Registry)
- Authenticate in CI/CD pipelines (Docker Hub login)
- Cache base images in your private registry
- Use `imagePullPolicy: IfNotPresent` in K8s

## Post-Incident
- MTTR target: < 30 min
- Root cause: no local registry mirror, anonymous pulls exhausted
