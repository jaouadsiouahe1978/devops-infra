# Incident 17 — Deployment Rollback Needed

## Scenario
A new deployment (v2) is broken and crashes on startup. You need to quickly roll back to the last stable version (v1).

## Symptoms
- New pods in CrashLoopBackOff after deployment
- Health checks failing on new version
- Error rate spike after deployment

## Simulate
```bash
docker compose up -d
# v1 stays up, v2 crashes
docker logs incident-app-v2-broken
curl http://localhost:18082/  # v1 — works
curl http://localhost:18083/  # v2 — fails
```

## Diagnosis
```bash
# K8s: check rollout status
kubectl rollout status deployment/app
kubectl get pods -l app=myapp
kubectl describe pod <broken-pod>

# Docker: check exit codes
docker ps -a | grep incident-app-v2
docker inspect incident-app-v2-broken | jq '.[0].State'
```

## Resolution
```bash
# K8s rollback
kubectl rollout undo deployment/app
kubectl rollout undo deployment/app --to-revision=2  # specific version

# Check rollout history
kubectl rollout history deployment/app

# Docker rollback
docker stop incident-app-v2-broken
docker start incident-app-v1

# Update image tag back to stable
# In docker-compose: image: nginx:1.24-alpine
```

## Prevention
- Use blue/green or canary deployments
- Set `minReadySeconds` and proper readiness probes
- Never deploy directly to prod without staging
- Tag images with git SHA, never use `latest`

## Post-Incident
- MTTR target: < 5 min (K8s rollback is instant)
- Root cause: broken v2 deployed without proper staging validation
