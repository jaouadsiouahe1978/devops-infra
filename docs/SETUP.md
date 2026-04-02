# DevOps/SRE Local Infrastructure — Setup Guide

> Last updated: 2026-04-01 | Tested on WSL2 Ubuntu 22.04 + Linux native

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick Start](#2-quick-start)
3. [Manual Installation Steps](#3-manual-installation-steps)
4. [Post-Installation Validation](#4-post-installation-validation)
5. [First-Day Checklist](#5-first-day-checklist)
6. [Troubleshooting Common Install Issues](#6-troubleshooting-common-install-issues)
7. [WSL2-Specific Configurations](#7-wsl2-specific-configurations)
8. [Performance Tuning for WSL2](#8-performance-tuning-for-wsl2)

---

## 1. Prerequisites

### 1.1 Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM      | 16 GB   | 32 GB       |
| CPU Cores | 8 cores | 16 cores   |
| Disk Space | 200 GB | 500 GB SSD |
| Network | 100 Mbps | 1 Gbps    |

> **Note:** Running all profiles simultaneously (k8s + monitoring + elk + cicd + messaging + security) requires approximately 14–18 GB of RAM. Use profiles selectively on 16 GB systems.

### 1.2 Software Requirements

#### WSL2 (Windows Host)

- Windows 10 version 2004+ or Windows 11
- WSL2 enabled with Ubuntu 22.04 LTS distribution
- Windows Terminal (recommended)
- Docker Desktop for Windows 4.x+ with WSL2 backend enabled

```powershell
# Enable WSL2 on Windows (run as Administrator)
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
wsl --set-version Ubuntu-22.04 2
```

#### Linux Native (Ubuntu 22.04 LTS)

```bash
# Verify OS version
lsb_release -a
# Expected: Ubuntu 22.04.x LTS

# Verify kernel version (5.15+ recommended)
uname -r
```

#### Required Software Packages

| Package | Version | Purpose |
|---------|---------|---------|
| Docker Engine | 24.x+ | Container runtime |
| Docker Compose | v2.x (plugin) | Multi-container orchestration |
| kubectl | 1.28+ | K8s cluster management |
| k3s | v1.28+ | Lightweight K8s |
| Helm | 3.x | K8s package manager |
| git | 2.x | Version control |
| curl / wget | any | HTTP utilities |
| jq | 1.6+ | JSON processor |
| make | 4.x | Task automation |
| ansible | 2.15+ | Configuration management |
| terraform | 1.6+ | Infrastructure as Code |

### 1.3 Network Requirements

- Ports 80, 443, 2222, 3000, 5000–5601, 6379, 6443, 8080–8090, 9000–9308, 15672, 27017 must be free
- No corporate VPN blocking localhost port binding (common issue in enterprise WSL2 setups)

Check for port conflicts before installation:

```bash
# Check all required ports at once
for port in 80 443 2222 3000 5000 5044 5432 5601 5672 6379 6443 8080 8081 8082 8083 8084 8085 8086 8088 8090 9000 9001 9002 9090 9092 9093 9100 9104 9113 9121 9187 9200 9308 15672 27017; do
  if ss -tlnp | grep -q ":${port} "; then
    echo "CONFLICT: Port $port is already in use"
  fi
done
```

---

## 2. Quick Start

```bash
# Clone the repository
git clone https://github.com/your-org/devops-infra.git ~/devops-infra
cd ~/devops-infra

# Make the installer executable and run it
chmod +x install.sh
bash install.sh
```

The `install.sh` script performs the following steps automatically:

1. Detects OS (WSL2 vs native Linux)
2. Installs system dependencies (Docker, kubectl, Helm, etc.)
3. Configures kernel parameters
4. Pulls all Docker images
5. Initialises K3s
6. Starts core infrastructure
7. Runs post-install validation

Expected duration: **15–30 minutes** depending on network speed and hardware.

---

## 3. Manual Installation Steps

Use this section if `install.sh` fails at a specific step or you want to install individual components.

### 3.1 System Dependencies

```bash
# Update package list
sudo apt-get update && sudo apt-get upgrade -y

# Install core utilities
sudo apt-get install -y \
  curl wget git vim htop tmux \
  jq yq make unzip \
  ca-certificates gnupg lsb-release \
  net-tools iproute2 iputils-ping \
  dnsutils nfs-common \
  python3 python3-pip python3-venv \
  build-essential

# Install Ansible
pip3 install --user ansible ansible-lint

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

### 3.2 Docker Engine

```bash
# Remove old Docker versions
sudo apt-get remove -y docker docker-engine docker.io containerd runc

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (log out and back in after this)
sudo usermod -aG docker $USER

# Verify installation
docker --version
docker compose version
```

### 3.3 kubectl and Helm

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Verify
kubectl version --client

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version

# Install useful kubectl plugins via krew
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
kubectl krew install ctx ns stern
```

### 3.4 K3s (Lightweight Kubernetes)

```bash
# Install K3s (single-node, no Traefik — we use our own)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

# Wait for K3s to be ready
sudo systemctl enable k3s
sudo systemctl start k3s
sleep 30
sudo kubectl get nodes

# Configure kubeconfig for current user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
# Replace 127.0.0.1 in config if needed for WSL2
sed -i 's/127.0.0.1/localhost/g' ~/.kube/config

# Verify
kubectl cluster-info
kubectl get nodes
```

### 3.5 Core Databases

```bash
# Start database profile
cd ~/devops-infra
docker compose --profile databases up -d

# Wait for databases to initialise
sleep 20

# Verify PostgreSQL
docker exec postgres pg_isready -U postgres

# Verify MySQL
docker exec mysql mysqladmin ping -h localhost -u root -proot_password

# Verify Redis
docker exec redis redis-cli ping

# Verify MongoDB
docker exec mongodb mongosh --quiet --eval "db.adminCommand('ping')"
```

### 3.6 Monitoring Stack

```bash
# Start monitoring profile
docker compose --profile monitoring up -d

# Wait for services
sleep 30

# Verify Prometheus
curl -s http://localhost:9090/-/healthy

# Verify Grafana
curl -s http://localhost:3000/api/health | jq .

# Verify Alertmanager
curl -s http://localhost:9093/-/healthy
```

### 3.7 ELK Stack

```bash
# ELK requires vm.max_map_count to be set
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Start ELK profile
docker compose --profile elk up -d

# Elasticsearch takes 60-90 seconds to initialise
echo "Waiting for Elasticsearch..."
until curl -s http://localhost:9200/_cluster/health | jq -e '.status != "red"' > /dev/null; do
  sleep 10; echo "Still waiting..."
done
echo "Elasticsearch ready"

# Verify Kibana
curl -s http://localhost:5601/api/status | jq '.status.overall.state'
```

### 3.8 CI/CD Tools

```bash
# Start CI/CD profile
docker compose --profile cicd up -d

# Jenkins initial admin password
echo "Jenkins admin password:"
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# GitLab takes 3-5 minutes to initialise
echo "Waiting for GitLab..."
until curl -s http://localhost:8082/-/health | grep -q "GitLab OK"; do
  sleep 15; echo "Still waiting..."
done

# ArgoCD initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 3.9 Security Services

```bash
# Start security profile
docker compose --profile security up -d

# Initialise Vault (dev mode — skip in production)
export VAULT_ADDR='http://localhost:8200'
vault status

# Consul health check
curl -s http://localhost:8500/v1/agent/self | jq '.Config.NodeName'

# Keycloak admin console available at:
echo "Keycloak: http://localhost:8085 (admin/admin)"
```

### 3.10 Messaging Services

```bash
# Start messaging profile
docker compose --profile messaging up -d

# Verify RabbitMQ
curl -s -u guest:guest http://localhost:15672/api/healthchecks/node | jq .

# Verify Kafka (using kafkacat)
kcat -b localhost:9092 -L

# Verify Zookeeper
echo ruok | nc localhost 2181
```

### 3.11 Storage Services

```bash
# Start storage profile
docker compose --profile storage up -d

# Verify Docker Registry
curl -s http://localhost:5000/v2/_catalog

# Verify Nexus (takes ~2 minutes)
curl -s http://localhost:8084/service/rest/v1/status

# Verify MinIO
curl -s http://localhost:9001/minio/health/live
```

---

## 4. Post-Installation Validation

### 4.1 Automated Validation Script

```bash
cd ~/devops-infra
bash scripts/validate.sh
```

### 4.2 Manual Health Checks

```bash
# Check all running containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check K3s nodes
kubectl get nodes -o wide

# Check all pods across namespaces
kubectl get pods -A

# Check Docker resource usage
docker stats --no-stream

# Check disk usage
df -h
du -sh ~/devops-infra/data/*
```

### 4.3 Service Endpoint Verification

```bash
#!/bin/bash
# Quick health check for all HTTP services
declare -A services=(
  ["Prometheus"]="http://localhost:9090/-/healthy"
  ["Grafana"]="http://localhost:3000/api/health"
  ["Alertmanager"]="http://localhost:9093/-/healthy"
  ["Elasticsearch"]="http://localhost:9200/_cluster/health"
  ["Kibana"]="http://localhost:5601/api/status"
  ["Vault"]="http://localhost:8200/v1/sys/health"
  ["Consul"]="http://localhost:8500/v1/agent/self"
  ["MinIO"]="http://localhost:9001/minio/health/live"
  ["Jenkins"]="http://localhost:8081/login"
  ["ArgoCD"]="http://localhost:8083/healthz"
  ["SonarQube"]="http://localhost:9000/api/system/health"
  ["Nexus"]="http://localhost:8084/service/rest/v1/status"
  ["Keycloak"]="http://localhost:8085/health"
  ["Traefik"]="http://localhost:8086/ping"
  ["RabbitMQ"]="http://localhost:15672/api/healthchecks/node"
)

for name in "${!services[@]}"; do
  url="${services[$name]}"
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url")
  if [[ "$status" == "200" ]]; then
    echo "OK    $name ($url)"
  else
    echo "FAIL  $name ($url) — HTTP $status"
  fi
done
```

---

## 5. First-Day Checklist

### Infrastructure

- [ ] All Docker containers running (`docker ps` shows no "Exited" state)
- [ ] K3s node in Ready state (`kubectl get nodes`)
- [ ] Grafana accessible at http://localhost:3000 (admin/admin)
- [ ] Prometheus showing targets at http://localhost:9090/targets
- [ ] Kibana showing green status at http://localhost:5601
- [ ] Vault unsealed and accessible at http://localhost:8200

### Configuration

- [ ] Change default passwords (Grafana, RabbitMQ, MinIO, Keycloak)
- [ ] Configure Grafana data sources (Prometheus, Elasticsearch, Loki)
- [ ] Import Grafana dashboards (Node Exporter, Docker, K8s)
- [ ] Configure Alertmanager notification channels (email/Slack)
- [ ] Set up Logstash pipelines for application log ingestion
- [ ] Create initial Vault secrets for application use

### Security

- [ ] Rotate Jenkins admin password
- [ ] Configure GitLab with SSH key
- [ ] Set up ArgoCD Git repository connection
- [ ] Review and customise Consul ACL policies
- [ ] Verify TLS certificates for Nginx (http://localhost:443)

### Learning

- [ ] Read ARCHITECTURE.md to understand service relationships
- [ ] Review PORTS.md for complete port reference
- [ ] Browse LEARNING-PATH.md and identify your current phase
- [ ] Try your first kubectl deployment
- [ ] Run a manual Prometheus query in the UI

---

## 6. Troubleshooting Common Install Issues

### 6.1 Docker daemon not starting

```bash
# Check Docker service status
sudo systemctl status docker

# View Docker logs
sudo journalctl -u docker --since "10 minutes ago"

# Common fix: restart Docker
sudo systemctl restart docker

# WSL2 specific: restart Docker Desktop from Windows
# Then in WSL2:
sudo service docker start
```

### 6.2 K3s fails to start

```bash
# Check K3s logs
sudo journalctl -u k3s --since "5 minutes ago" -f

# Common cause: port 6443 already in use
ss -tlnp | grep 6443

# Reset K3s completely
sudo /usr/local/bin/k3s-uninstall.sh
# Then reinstall per section 3.4
```

### 6.3 Elasticsearch fails to start (exit code 78)

```bash
# This is always a vm.max_map_count issue
sudo sysctl vm.max_map_count
# Expected: 262144

# Fix:
sudo sysctl -w vm.max_map_count=262144

# Make permanent (WSL2: add to /etc/sysctl.conf AND .wslconfig)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### 6.4 Port already in use

```bash
# Find which process owns a port
sudo ss -tlnp | grep :8081
# or
sudo lsof -i :8081

# Kill the process (replace PID)
sudo kill -9 <PID>
```

### 6.5 Docker Compose image pull failures

```bash
# Pull images individually for better error reporting
docker pull prom/prometheus:latest
docker pull grafana/grafana:latest

# Configure Docker daemon for retries and mirror
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://mirror.gcr.io"],
  "dns": ["8.8.8.8", "1.1.1.1"],
  "max-concurrent-downloads": 3
}
EOF
sudo systemctl restart docker
```

### 6.6 Insufficient memory

```bash
# Check available memory
free -h

# Check which containers are using most RAM
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | sort -k2 -hr

# Stop non-essential profiles temporarily
docker compose --profile elk stop
docker compose --profile cicd stop
```

### 6.7 GitLab not accessible after startup

GitLab requires 3–5 minutes to fully initialise. Check progress:

```bash
docker logs gitlab -f | grep "GitLab"
# Wait until you see: "GitLab Reconfigured!"

# Check GitLab internal health
docker exec gitlab gitlab-healthcheck
```

---

## 7. WSL2-Specific Configurations

### 7.1 .wslconfig (Windows host, located at C:\Users\<YourUser>\.wslconfig)

```ini
[wsl2]
memory=12GB
processors=6
swap=4GB
swapFile=C:\\Users\\YourUser\\AppData\\Local\\Temp\\wsl-swap.vhdx
localhostForwarding=true
nestedVirtualization=true
kernelCommandLine=vsyscall=emulate

[experimental]
autoMemoryReclaim=dropcache
sparseVhd=true
```

Apply changes by restarting WSL2 from PowerShell:

```powershell
wsl --shutdown
wsl
```

### 7.2 WSL2 /etc/wsl.conf (inside Ubuntu)

```ini
[boot]
systemd=true
command="sysctl -w vm.max_map_count=262144"

[automount]
enabled=true
options="metadata,umask=22,fmask=11"
mountFsTab=true

[network]
generateHosts=true
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=false
```

### 7.3 DNS Configuration for WSL2

If you experience DNS resolution issues inside WSL2:

```bash
# Disable automatic resolv.conf generation
sudo tee /etc/wsl.conf <<EOF
[network]
generateResolvConf=false
EOF

# Set manual DNS
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Make immutable to prevent overwrite
sudo chattr +i /etc/resolv.conf
```

### 7.4 systemd in WSL2

```bash
# Verify systemd is running (requires systemd=true in wsl.conf)
systemctl --no-pager status

# If systemd is not running, services can be managed via init.d
sudo service docker start
sudo service docker status
```

### 7.5 Port Forwarding from Windows to WSL2

Access WSL2 services from Windows browser:

```powershell
# Run in PowerShell as Administrator on Windows host
# Get WSL2 IP address
$wslIp = (wsl hostname -I).Trim()

# Forward ports (run for each port you need)
netsh interface portproxy add v4tov4 listenport=3000 listenaddress=0.0.0.0 connectport=3000 connectaddress=$wslIp
netsh interface portproxy add v4tov4 listenport=9090 listenaddress=0.0.0.0 connectport=9090 connectaddress=$wslIp

# List all forwarded ports
netsh interface portproxy show all

# Remove a forwarding rule
netsh interface portproxy delete v4tov4 listenport=3000 listenaddress=0.0.0.0
```

### 7.6 File System Performance

```bash
# IMPORTANT: Keep all project files inside the WSL2 filesystem
# DO NOT work from /mnt/c/ — it is 5-10x slower due to 9P filesystem overhead

# Good: ~/devops-infra (inside WSL2 ext4)
# Bad: /mnt/c/Users/YourUser/devops-infra (Windows NTFS via 9P)

# Check if you're in the right place
df -h .
# Should show /dev/sdX or similar, NOT drvfs
```

---

## 8. Performance Tuning for WSL2

### 8.1 Kernel Parameters

```bash
# Apply performance tuning (add to /etc/sysctl.conf for persistence)
sudo tee /etc/sysctl.d/99-devops-tuning.conf <<EOF
# Elasticsearch requirement
vm.max_map_count=262144

# Network performance
net.core.somaxconn=65535
net.core.netdev_max_backlog=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15

# Memory management
vm.swappiness=10
vm.dirty_ratio=60
vm.dirty_background_ratio=5
vm.overcommit_memory=1

# File descriptor limits
fs.file-max=2097152
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF

sudo sysctl -p /etc/sysctl.d/99-devops-tuning.conf
```

### 8.2 Docker Daemon Tuning

```bash
sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": ["overlay2.override_kernel_check=true"],
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    }
  },
  "live-restore": true,
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

sudo systemctl restart docker
```

### 8.3 Shell Profile Optimisations

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Kubernetes aliases
alias k='kubectl'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'
alias kgp='kubectl get pods -o wide'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'

# Docker aliases
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dstop='docker stop $(docker ps -q)'
alias dclean='docker system prune -f'
alias dlogs='docker compose logs -f'

# Infrastructure aliases
alias infra-start='cd ~/devops-infra && docker compose --profile monitoring up -d'
alias infra-stop='cd ~/devops-infra && docker compose down'
alias infra-status='cd ~/devops-infra && docker compose ps'

# Useful functions
k8s-context() { kubectl config get-contexts; }
pod-shell() { kubectl exec -it "$1" -- /bin/sh; }
port-forward() { kubectl port-forward svc/"$1" "$2":"$2" &; }
```

### 8.4 Memory Reclamation

```bash
# Drop Linux page cache (useful after heavy Elasticsearch/JVM usage)
sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# Check memory after reclamation
free -h
```

### 8.5 tmpfs for Temporary Data

```bash
# Mount /tmp as tmpfs for faster temp file operations
sudo mount -t tmpfs -o size=2G tmpfs /tmp

# Make permanent — add to /etc/fstab
echo "tmpfs /tmp tmpfs defaults,size=2G 0 0" | sudo tee -a /etc/fstab
```

---

*For operational procedures, see [OPERATIONS.md](./OPERATIONS.md).*
*For architecture overview, see [ARCHITECTURE.md](./ARCHITECTURE.md).*
