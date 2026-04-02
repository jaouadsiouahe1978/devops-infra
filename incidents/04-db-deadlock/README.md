# Incident 04 — Database Deadlock (PostgreSQL)

## Scenario
Two concurrent transactions lock rows in opposite order, causing a deadlock. PostgreSQL detects and kills one transaction.

## Symptoms
- `ERROR: deadlock detected` in application logs
- Increased query latency
- Prometheus `pg_stat_activity` shows blocked queries

## Simulate
```bash
docker compose up
docker logs incident-deadlock-tx1
docker logs incident-deadlock-tx2
```

## Diagnosis
```bash
# Check for locks
psql -U devops -d incident_db -c "
  SELECT pid, wait_event_type, wait_event, query
  FROM pg_stat_activity
  WHERE wait_event IS NOT NULL;
"

# Check deadlock log
docker logs incident-db-deadlock-pg | grep -i deadlock
```

## Resolution
```bash
# Kill blocking queries
psql -U devops -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE wait_event_type='Lock';"

# Long-term: enforce consistent lock order in application code
```

## Prevention
- Always acquire locks in the same order across transactions
- Use `SELECT ... FOR UPDATE NOWAIT` to fail fast
- Set `lock_timeout = '5s'` in PostgreSQL config
- Alert on `pg_locks` count spikes

## Post-Incident
- MTTR target: < 5 min
- Root cause: inconsistent row lock ordering between transactions
