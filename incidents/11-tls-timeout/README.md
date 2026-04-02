# Incident 11 — TLS Handshake Timeout

## Scenario
TLS handshake never completes — the server accepts TCP but drops or stalls on the TLS negotiation.

## Symptoms
- `curl: (35) OpenSSL SSL_connect: Connection timed out`
- `openssl s_client` hangs indefinitely
- HTTP works, HTTPS fails

## Simulate
```bash
docker compose up -d
docker logs incident-tls-client -f
```

## Diagnosis
```bash
# Test TLS handshake manually
timeout 5 openssl s_client -connect localhost:18444 2>&1

# Check if TCP layer works
nc -zv localhost 18444

# Capture TLS handshake
tcpdump -i any port 18444 -w /tmp/tls.pcap

# Check cipher compatibility
openssl s_client -connect host:port -tls1_2
openssl s_client -connect host:port -tls1_3
```

## Resolution
```bash
# Check TLS config on server (Nginx example)
nginx -T | grep ssl

# Ensure TLS versions match
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;

# Restart service
docker restart incident-tls-drop

# Check firewall is not blocking TLS
iptables -L | grep 443
```

## Prevention
- Monitor TLS handshake success with Blackbox exporter
- Alert on `probe_ssl_earliest_cert_expiry` and handshake failures
- Test TLS configs with `testssl.sh`

## Post-Incident
- MTTR target: < 20 min
- Root cause: firewall or proxy intercepting/dropping TLS traffic
