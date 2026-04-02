# Incident 10 — DNS Resolution Failed

## Scenario
DNS server is unreachable or misconfigured, causing all hostname-based connections to fail.

## Symptoms
- `curl: Could not resolve host`
- `nslookup: connection timed out; no servers could be reached`
- Services can connect via IP but not hostname

## Simulate
```bash
docker compose up -d
docker logs incident-dns-failed
docker logs incident-dns-working  # compare with working DNS
```

## Diagnosis
```bash
# Check DNS config
cat /etc/resolv.conf

# Test resolution
nslookup google.com
dig google.com @8.8.8.8

# Test if DNS port is reachable
nc -zv 1.2.3.4 53

# Check if issue is DNS vs network
ping 8.8.8.8  # works = network ok, DNS broken
ping google.com  # fails = DNS broken
```

## Resolution
```bash
# Fix resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Docker: fix DNS in daemon.json
cat > /etc/docker/daemon.json << EOF
{"dns": ["8.8.8.8", "1.1.1.1"]}
EOF
systemctl restart docker

# K8s: check CoreDNS
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

## Prevention
- Configure redundant DNS servers (primary + fallback)
- Monitor DNS resolution with Blackbox exporter
- Alert on `probe_dns_lookup_time_seconds > 1`

## Post-Incident
- MTTR target: < 10 min
- Root cause: single DNS server configured, no fallback
