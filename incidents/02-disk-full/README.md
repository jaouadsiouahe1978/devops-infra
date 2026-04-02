# Incident 02 — Disk Full

## Scenario
A container fills up the disk volume, causing services to crash or hang due to no available space.

## Symptoms
- `No space left on device` errors in logs
- Services refusing to write logs or data
- Alerts: `DiskSpaceCritical` (usage > 85%)

## Simulate
```bash
docker compose up -d
docker logs incident-disk-full -f
```

## Diagnosis
```bash
df -h
du -sh /var/lib/docker/volumes/*
docker system df
```

## Resolution
```bash
# Identify large files
du -sh /data/* | sort -rh | head -10

# Remove unnecessary files
docker volume prune -f
docker system prune -f

# Expand volume or clean logs
truncate -s 0 /data/bigfile
```

## Prevention
- Set up Prometheus `node_filesystem_avail_bytes` alert at 85%
- Implement log rotation (logrotate)
- Set Docker volume size limits

## Post-Incident
- MTTR target: < 15 min
- Root cause: missing disk usage monitoring
