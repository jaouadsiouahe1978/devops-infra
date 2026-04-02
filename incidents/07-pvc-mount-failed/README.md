# Incident 07 — PVC Mount Failed

## Scenario
A Kubernetes PersistentVolumeClaim or Docker volume fails to mount, preventing the pod/container from starting.

## Symptoms
- Pod stuck in `Pending` or `ContainerCreating`
- `kubectl describe pod` shows `MountVolume.SetUp failed`
- Container exits immediately with mount error

## Simulate
```bash
docker compose up
docker logs incident-pvc-mount
docker logs incident-pvc-readonly
```

## Diagnosis
```bash
# Kubernetes
kubectl describe pod <pod-name> | grep -A 10 Events
kubectl get pvc -A
kubectl describe pvc <pvc-name>

# Docker
docker inspect incident-pvc-mount | jq '.[0].Mounts'
docker volume ls
docker volume inspect <volume-name>
```

## Resolution
```bash
# Fix host path permissions
mkdir -p /nonexistent/path/on/host
chmod 755 /nonexistent/path/on/host

# K8s: delete and recreate PVC
kubectl delete pvc <pvc-name>
kubectl apply -f pvc.yaml

# Check StorageClass availability
kubectl get storageclass
```

## Prevention
- Use `initContainers` to verify mounts before app starts
- Monitor `kube_persistentvolumeclaim_status_phase != Bound`
- Use StorageClass with `WaitForFirstConsumer`

## Post-Incident
- MTTR target: < 20 min
- Root cause: host path doesn't exist / wrong permissions
