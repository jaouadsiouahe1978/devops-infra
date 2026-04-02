# Incident 15 — Cache Invalidation Storm

## Scenario
All cache keys expire simultaneously, causing every request to fall through to the database. The DB gets overwhelmed — this is a "thundering herd" / cache stampede.

## Symptoms
- Database CPU spikes to 100% suddenly
- Response times increase drastically
- Redis `keyspace_hits` drops to zero
- DB connection pool exhausted

## Simulate
```bash
docker compose up -d
docker logs incident-cache-loader -f &
docker logs incident-cache-backend -f
# Watch keys expire simultaneously after 5 seconds
```

## Diagnosis
```bash
# Check cache hit rate
redis-cli -p 16379 INFO stats | grep -E "hits|misses"
redis-cli -p 16379 DBSIZE

# Check key TTLs (should be staggered)
redis-cli -p 16379 DEBUG SLEEP 0
redis-cli -p 16379 TTL key:1

# Monitor DB connections
# watch -n1 'psql -c "SELECT count(*) FROM pg_stat_activity"'
```

## Resolution
```bash
# Immediate: add jitter to cache TTLs
# Instead of TTL=300, use TTL=random(270, 330)

# Implement cache warming before expiry
# Background job refreshes keys before they expire

# Add DB connection pool limit to protect DB
# max_connections = 100
```

## Prevention
- Add random TTL jitter: `TTL = base_ttl + random(0, base_ttl * 0.1)`
- Use cache-aside pattern with background refresh
- Implement circuit breaker on DB layer
- Set DB `max_connections` limit

## Post-Incident
- MTTR target: < 15 min
- Root cause: all keys loaded at same time with identical TTL
