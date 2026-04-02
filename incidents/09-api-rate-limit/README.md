# Incident 09 — API Rate Limit Exceeded

## Scenario
A client sends too many requests, triggering rate limiting (HTTP 429). Services dependent on the API start failing.

## Symptoms
- HTTP 429 Too Many Requests responses
- Application logs show repeated rate limit errors
- Nginx: `limiting requests, excess: X by zone "api"`

## Simulate
```bash
docker compose up -d
docker logs incident-rate-limit-client -f
```

## Diagnosis
```bash
# Check nginx rate limit logs
docker logs incident-rate-limit-api | grep "limiting requests"

# Count 429 responses
docker logs incident-rate-limit-client | grep -c "429"

# Check current request rate
curl -I http://localhost:18081/api/data
```

## Resolution
```bash
# Immediate: implement exponential backoff in client
# Add retry logic with delay

# Nginx: increase rate limit temporarily
# rate=20r/s instead of 5r/s

# Identify abusive clients
docker logs incident-rate-limit-api | awk '{print $1}' | sort | uniq -c | sort -rn
```

## Prevention
- Implement client-side retry with exponential backoff
- Use a request queue to smooth traffic spikes
- Monitor `nginx_http_requests_total` rate
- Set per-user API quotas

## Post-Incident
- MTTR target: < 15 min
- Root cause: no client-side throttling / retry logic
