# Incident 08 — Stale Lock File

## Scenario
A process crashed without releasing its lock file. The next startup is blocked waiting for a lock held by a dead process.

## Symptoms
- Application fails to start: `Another instance is running`
- Service stuck waiting, never starts
- Lock file exists but referenced PID is dead

## Simulate
```bash
docker compose up -d
docker logs incident-stale-lock
```

## Diagnosis
```bash
# Find lock files
find /var/lock /tmp /var/run -name "*.lock" -o -name "*.pid" 2>/dev/null

# Check if PID in lock file is alive
LOCKPID=$(cat /var/lock/app/app.lock)
kill -0 $LOCKPID 2>&1 || echo "Process $LOCKPID is dead — stale lock"

# Common stale locks
ls -la /var/lib/dpkg/lock*    # apt/dpkg
ls -la /var/lib/apt/lists/lock
```

## Resolution
```bash
# Remove stale lock
rm -f /var/lock/app/app.lock

# For dpkg/apt stale locks
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/dpkg/lock
dpkg --configure -a

# For PostgreSQL
rm -f /var/run/postgresql/.s.PGSQL.*.lock
```

## Prevention
- Use `flock` with timeout instead of manual lock files
- Implement lock file cleanup in trap handlers
- Use `set -e` and `trap 'rm -f $LOCKFILE' EXIT`

## Post-Incident
- MTTR target: < 5 min
- Root cause: missing cleanup handler on process crash
