# Incident 06 — Certificate Expired

## Scenario
An SSL/TLS certificate expires, causing HTTPS connections to fail with SSL errors.

## Symptoms
- `curl: (60) SSL certificate problem: certificate has expired`
- Browser shows `NET::ERR_CERT_DATE_INVALID`
- Blackbox exporter `probe_ssl_earliest_cert_expiry` fires

## Simulate
```bash
docker compose up -d
# Check cert dates
docker exec incident-cert-expired openssl x509 -in /certs/cert.pem -noout -dates
# Try connecting (will fail SSL)
curl -k https://localhost:18443/
```

## Diagnosis
```bash
# Check certificate expiry
openssl s_client -connect localhost:18443 2>/dev/null | openssl x509 -noout -dates

# Check all certs in directory
for cert in /etc/ssl/certs/*.pem; do
  echo "$cert:"; openssl x509 -in "$cert" -noout -enddate 2>/dev/null
done

# Use cert-check script
~/devops-infra/scripts/cert-check.sh
```

## Resolution
```bash
# Generate new certificate
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj '/CN=devops-lab.local'

# Or use Let's Encrypt (certbot)
certbot renew

# Reload nginx
docker exec incident-nginx-tls nginx -s reload
```

## Prevention
- Monitor `probe_ssl_earliest_cert_expiry < 30 days`
- Automate renewal with certbot/cert-manager
- Alert 30 days before expiry

## Post-Incident
- MTTR target: < 30 min
- Root cause: no automated certificate renewal
