# DevOps/SRE Learning Path — Junior to Expert

> A structured, hands-on curriculum using this local infrastructure as your lab environment.
> Total duration: 17+ weeks | Last updated: 2026-04-01

---

## Overview

This learning path takes you from basic infrastructure deployment to expert-level SRE practices using the services running in this environment. Every concept is immediately applied in the lab.

**Learning philosophy:**
- Deploy before you theorise — get services running, then understand them deeply
- Break things intentionally — the INCIDENTS.md playbooks are study material
- Automate everything — if you do it twice, script it
- Measure everything — if you can't observe it, you can't operate it

---

## Progress Tracker

| Phase | Weeks | Focus | Status |
|-------|-------|-------|--------|
| 1 | 1–4 | Service Deployment | |
| 2 | 5–8 | Automation | |
| 3 | 9–12 | Kubernetes Deep Dive | |
| 4 | 13–16 | Infrastructure as Code | |
| 5 | 17+ | SRE Practices | |

---

## Phase 1 (Weeks 1–4): Service Deployment

**Goal:** Have all infrastructure services running and be able to explain what each one does and why it exists.

---

### Week 1: Core Infrastructure — Docker, K3s, Databases

#### Daily Tasks

**Day 1 — Docker Fundamentals**

```bash
# Morning: Install and verify Docker
docker --version
docker compose version

# Hands-on: Run your first containers
docker run hello-world
docker run -d --name nginx-test -p 8888:80 nginx:alpine
curl http://localhost:8888

# Understand layers and images
docker history nginx:alpine
docker image inspect nginx:alpine | jq '.[0].Config'

# Cleanup
docker stop nginx-test && docker rm nginx-test
```

**Day 2 — Docker Compose**

```bash
# Start the databases profile
cd ~/devops-infra
docker compose --profile databases up -d

# Connect to each database
docker exec -it postgres psql -U postgres -c "\l"
docker exec -it mysql mysql -u root -proot_password -e "SHOW DATABASES;"
docker exec -it redis redis-cli ping
docker exec -it mongodb mongosh --eval "db.adminCommand('ping')"

# Exercise: Create a database named "learning" in each system
```

**Day 3 — Kubernetes Basics**

```bash
# Verify K3s is running
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# Your first deployment
kubectl create deployment nginx --image=nginx:alpine
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get services nginx

# Scale it
kubectl scale deployment nginx --replicas=3
kubectl get pods -l app=nginx

# Cleanup
kubectl delete deployment nginx
kubectl delete service nginx
```

**Day 4 — Kubernetes YAML**

```bash
# Write your first deployment manifest
cat > /tmp/my-first-app.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello-world
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: hello-world
spec:
  selector:
    app: hello-world
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f /tmp/my-first-app.yaml
kubectl get all -l app=hello-world
kubectl port-forward svc/hello-world 9999:80 &
curl http://localhost:9999
```

**Day 5 — Review and Practice**

```bash
# Run the validation script
bash ~/devops-infra/scripts/validate.sh

# Document what you've learned:
# - What is the difference between docker compose and K8s?
# - When would you use each database (PG vs MySQL vs Redis vs Mongo)?
# - What is a K8s Service and why does it exist?
```

#### Skills to Learn This Week
- Docker image layers and caching
- Docker Compose profiles and dependencies
- K8s core objects: Pod, Deployment, Service, ConfigMap, Secret
- kubectl basic commands
- Database connection strings and client tools

#### Incidents to Simulate
- [ ] Kill a database container and observe what happens: `docker stop postgres`
- [ ] Create a pod with wrong image tag and observe ImagePullBackOff
- [ ] Fill a container's filesystem and observe the error

---

### Week 2: Monitoring Stack — Prometheus, Grafana, ELK

#### Daily Tasks

**Day 1 — Prometheus**

```bash
# Start monitoring
docker compose --profile monitoring up -d

# Explore Prometheus UI: http://localhost:9090

# Basic PromQL queries — try these in the UI:
# All active time series
count({__name__=~".+"})

# CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Docker container CPU
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100
```

**Day 2 — Grafana**

```bash
# Access Grafana: http://localhost:3000 (admin/admin)

# Step 1: Add Prometheus data source
#   Configuration → Data Sources → Add → Prometheus
#   URL: http://prometheus:9090

# Step 2: Import dashboards
#   Dashboards → Import → ID: 1860 (Node Exporter Full)
#   Dashboards → Import → ID: 893 (Docker monitoring)

# Step 3: Create your first custom panel
# Query: rate(container_cpu_usage_seconds_total{name="prometheus"}[5m]) * 100
# Visualization: Time series
# Title: "Prometheus CPU Usage"
```

**Day 3 — Alertmanager**

```bash
# View current alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[].name'

# Create a test alert rule
cat > /tmp/test-alert.yaml <<'EOF'
groups:
  - name: test-alerts
    rules:
      - alert: HighContainerMemory
        expr: container_memory_usage_bytes{name!=""} > 500000000  # 500MB
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} using {{ $value | humanize }}B memory"
EOF

# Add to Prometheus config and reload
docker kill --signal=HUP prometheus
```

**Day 4 — ELK Stack**

```bash
# Start ELK
docker compose --profile elk up -d

# Wait for Elasticsearch
until curl -s http://localhost:9200/_cluster/health | jq -e '.status != "red"' > /dev/null; do
  echo "Waiting..."; sleep 10
done

# Check cluster health
curl -s http://localhost:9200/_cluster/health | jq .

# Create a test index
curl -X POST http://localhost:9200/test-index/_doc \
  -H "Content-Type: application/json" \
  -d '{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "level": "INFO", "message": "Hello ELK!"}'

# Query it back
curl -s http://localhost:9200/test-index/_search | jq '.hits.hits[0]._source'

# Explore Kibana: http://localhost:5601
```

**Day 5 — Hands-on Monitoring Exercise**

```bash
# Exercise: Create a stress test and observe in Grafana

# Generate CPU load
docker run --rm -d --name stress-test progrium/stress stress --cpu 2 --timeout 120s

# In Grafana:
# 1. Watch the CPU panel spike
# 2. Observe the container appear in cAdvisor dashboard

# Generate log volume
for i in $(seq 1 1000); do
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) level=INFO msg=\"Request $i\" duration=${RANDOM}ms" >> /tmp/test.log
done

# Ship to Logstash (configure filebeat or use HTTP input)
docker stop stress-test
```

#### Skills to Learn This Week
- PromQL: rate(), avg_over_time(), histogram_quantile()
- Grafana: data sources, panels, variables, alerts
- Elasticsearch: indices, mappings, query DSL basics
- Logstash: pipeline configuration (input → filter → output)
- Log levels and structured logging best practices

#### Incidents to Simulate
- [ ] Simulate HighMemoryUsage alert (INC-003)
- [ ] Stop Node Exporter and observe monitoring gap
- [ ] Fill Elasticsearch with junk data and watch disk usage

---

### Week 3: CI/CD — Jenkins, GitLab, ArgoCD

#### Daily Tasks

**Day 1 — Jenkins**

```bash
# Start CI/CD stack
docker compose --profile cicd up -d

# Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# Access Jenkins: http://localhost:8081
# Complete initial setup wizard
# Install plugins: Git, Pipeline, Docker Pipeline, Kubernetes

# Create your first pipeline
# New Item → Pipeline → Script:
```

```groovy
pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                sh 'echo "Checking out code..."'
                sh 'git --version'
            }
        }
        stage('Build') {
            steps {
                sh 'echo "Building..."'
                sh 'docker --version'
            }
        }
        stage('Test') {
            steps {
                sh 'echo "Running tests..."'
                sh 'exit 0'
            }
        }
        stage('Deploy') {
            steps {
                sh 'echo "Deploying..."'
            }
        }
    }
    post {
        success { echo 'Pipeline succeeded!' }
        failure { echo 'Pipeline failed!' }
    }
}
```

**Day 2 — GitLab**

```bash
# GitLab takes ~5 minutes to fully start
# Access: http://localhost:8082
# Default credentials: root / (set during first login or check logs)
docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password

# Set up SSH key for git operations
ssh-keygen -t ed25519 -C "your.email@example.com" -f ~/.ssh/gitlab_local
cat ~/.ssh/gitlab_local.pub
# Add to GitLab: Profile → SSH Keys

# Configure SSH
cat >> ~/.ssh/config <<EOF
Host localhost
  HostName localhost
  Port 2222
  IdentityFile ~/.ssh/gitlab_local
  User git
EOF

# Create a test project and push
mkdir /tmp/test-project && cd /tmp/test-project
git init
echo "# Test Project" > README.md
git add . && git commit -m "Initial commit"
git remote add origin ssh://git@localhost:2222/root/test-project.git
git push -u origin main
```

**Day 3 — ArgoCD**

```bash
# Access ArgoCD: http://localhost:8083
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Login via CLI
argocd login localhost:8083 --username admin --insecure

# Create your first ArgoCD app (GitOps!)
argocd app create my-nginx \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

argocd app sync my-nginx
argocd app get my-nginx
```

**Day 4 — SonarQube Code Quality**

```bash
# Access SonarQube: http://localhost:9000 (admin/admin)
# Generate a project token

# Analyse a sample project
docker run --rm \
  -e SONAR_HOST_URL="http://localhost:9000" \
  -e SONAR_LOGIN="<your-token>" \
  -v "$(pwd):/usr/src" \
  sonarsource/sonar-scanner-cli \
  sonar-scanner \
  -Dsonar.projectKey=my-project \
  -Dsonar.sources=.
```

**Day 5 — End-to-End CI/CD Pipeline**

Design and implement a pipeline that:
1. Triggers on git push to GitLab
2. Jenkins builds and tests the code
3. Pushes Docker image to local registry (port 5000)
4. ArgoCD detects the new image and deploys to K3s
5. SonarQube quality gate must pass

#### Skills to Learn This Week
- Jenkins: Declarative Pipeline syntax, shared libraries, credentials
- GitLab: CI/CD YAML (`.gitlab-ci.yml`), runners, environments
- ArgoCD: App of Apps pattern, sync policies, RBAC
- GitOps principles: declarative, versioned, automated reconciliation

#### Incidents to Simulate
- [ ] Simulate INC-017: Deployment Rollback Needed
- [ ] Simulate INC-012: Registry Pull Rate Limit
- [ ] Break a Jenkins pipeline and debug it

---

### Week 4: Security — Vault, Consul, Keycloak

#### Daily Tasks

**Day 1 — HashiCorp Vault**

```bash
# Start security profile
docker compose --profile security up -d

# Access Vault UI: http://localhost:8200/ui
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='root'  # Dev mode token

# Explore Vault
vault status
vault secrets list

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Write and read a secret
vault kv put secret/my-app db_password="supersecret" api_key="abc123"
vault kv get secret/my-app
vault kv get -field=db_password secret/my-app

# Create a policy
cat > /tmp/my-app-policy.hcl <<EOF
path "secret/data/my-app" {
  capabilities = ["read"]
}
EOF
vault policy write my-app-policy /tmp/my-app-policy.hcl

# Create a token with the policy
vault token create -policy=my-app-policy -ttl=1h
```

**Day 2 — Consul Service Mesh**

```bash
# Explore Consul UI: http://localhost:8500/ui

# Register a service
curl -X PUT http://localhost:8500/v1/agent/service/register \
  -H "Content-Type: application/json" \
  -d '{
    "ID": "my-web-1",
    "Name": "my-web",
    "Tags": ["v1"],
    "Address": "127.0.0.1",
    "Port": 8080,
    "Check": {
      "HTTP": "http://127.0.0.1:8080/",
      "Interval": "10s"
    }
  }'

# Query services
curl -s http://localhost:8500/v1/catalog/services | jq .
curl -s http://localhost:8500/v1/catalog/service/my-web | jq '.[].Address'

# Use Consul KV store
consul kv put config/my-app/log_level INFO
consul kv get config/my-app/log_level
```

**Day 3 — Keycloak Identity and Access**

```bash
# Access Keycloak: http://localhost:8085/admin (admin/admin)

# Create a new Realm
# Admin Console → Master → Add realm → Name: devops-lab

# Create a client (application)
# Realm Settings → Clients → Create
# Client ID: my-app
# Client Protocol: openid-connect
# Access Type: confidential

# Create a user
# Users → Add User → Username: testuser
# Credentials tab → Set Password: testpassword

# Test token retrieval
curl -X POST http://localhost:8085/realms/devops-lab/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=my-app&client_secret=<secret>&username=testuser&password=testpassword&grant_type=password" | jq .access_token
```

**Day 4 — Integrating Vault with Kubernetes**

```bash
# Install Vault Agent Injector (if not already installed)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set "global.externalVaultAddr=http://$(docker inspect vault --format '{{.NetworkSettings.IPAddress}}'):8200"

# Deploy a pod that reads secrets from Vault
cat > /tmp/vault-demo.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vault-demo
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-app"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/my-app"
spec:
  containers:
  - name: app
    image: alpine
    command: ["sh", "-c", "cat /vault/secrets/config && sleep 3600"]
EOF
kubectl apply -f /tmp/vault-demo.yaml
```

**Day 5 — Security Review**

- [ ] Audit all services with default credentials — change them
- [ ] Verify no secrets are stored in environment variables without Vault
- [ ] Review Consul ACL policies
- [ ] Set up Keycloak as SSO for Grafana

#### Skills to Learn This Week
- Vault: secrets engines (KV, PKI, database), auth methods, policies
- Consul: service registration, health checks, KV store, ACLs
- Keycloak: realms, clients, users, roles, OIDC flows
- Kubernetes RBAC: roles, role bindings, service accounts

#### Incidents to Simulate
- [ ] Simulate INC-006: Certificate Expired (rotate a Vault PKI cert)
- [ ] Simulate INC-008: Stale Lock File (Vault sealed after restart)
- [ ] Revoke a Vault token and observe access denied

---

## Phase 2 (Weeks 5–8): Automation

**Goal:** Automate all manual operations from Phase 1 using Ansible and GitOps.

### Week 5: Ansible Foundations

```bash
# Install Ansible
pip3 install --user ansible ansible-lint

# Write your first playbook
cat > ~/devops-infra/ansible/check-services.yml <<'EOF'
---
- name: Check DevOps Infrastructure Health
  hosts: localhost
  connection: local
  tasks:
    - name: Check Prometheus is responding
      uri:
        url: http://localhost:9090/-/healthy
        method: GET
        status_code: 200
      register: prometheus_health

    - name: Check Grafana is responding
      uri:
        url: http://localhost:3000/api/health
        method: GET
        status_code: 200
      register: grafana_health

    - name: Print results
      debug:
        msg: "Prometheus: {{ prometheus_health.status }} | Grafana: {{ grafana_health.status }}"
EOF

ansible-playbook ~/devops-infra/ansible/check-services.yml
```

**Week 5 exercises:**
1. Write a playbook to back up all databases
2. Write a playbook to rotate all service passwords
3. Write a playbook to validate the entire infrastructure (becomes your `validate.sh`)

### Week 6: GitOps Workflows

- Set up ArgoCD to manage ALL K8s deployments
- Move all `kubectl apply` commands into Git repositories
- Implement branch-based environments (main → production, develop → staging)
- Set up automated sync with ArgoCD

**Exercise: App of Apps Pattern**

```yaml
# ~/devops-infra/k8s/apps/app-of-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://localhost:8082/root/k8s-configs.git
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Week 7: Infrastructure as Code Principles

- Document all manual steps as code (Ansible, Helm, Terraform)
- Implement idempotent scripts (can be run multiple times safely)
- Practice: destroy and recreate the monitoring stack 3 times from scratch

**Key principle:** If it's not in Git, it doesn't exist.

### Week 8: Advanced Automation

- Write Ansible roles for each service group
- Implement a complete "fresh install" playbook
- Create automated test suites for infrastructure
- Practice on-call simulation: automated runbook execution

---

## Phase 3 (Weeks 9–12): Kubernetes Deep Dive

### Week 9: Stateful Applications

```bash
# Deploy PostgreSQL as a StatefulSet (not just Docker Compose)
cat > /tmp/postgres-statefulset.yaml <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: databases
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
EOF
```

**Week 9 exercises:**
- Deploy Redis as StatefulSet with PVC
- Implement PodDisruptionBudgets
- Practice node drain + drain procedure (INC-019)

### Week 10: Helm Charts

```bash
# Create your first Helm chart
helm create my-app
tree my-app/

# Key files to understand:
# Chart.yaml — chart metadata
# values.yaml — default configuration
# templates/ — K8s manifests with Go template syntax

# Lint your chart
helm lint my-app/

# Template rendering (dry run)
helm template my-app my-app/ --set replicaCount=3

# Install
helm install my-release my-app/ -n default \
  --set image.tag=v1.2.3 \
  --set resources.limits.memory=256Mi
```

**Week 10 goal:** Package all infrastructure components as Helm charts stored in Nexus.

### Week 11: Kubernetes Operators

Study the Operator pattern and implement a simple operator:
- Watch for a Custom Resource (`MyApp`)
- Create Deployment + Service when MyApp is created
- Update Deployment when MyApp spec changes
- Clean up when MyApp is deleted

Recommended tools: kubebuilder or Operator SDK.

### Week 12: Service Mesh (Optional)

If resources allow, deploy Linkerd or Istio:
- mTLS between all services
- Traffic splitting (canary deployments)
- Observability (distributed tracing with Jaeger)

```bash
# Linkerd is lightweight — good for this lab
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
linkerd install | kubectl apply -f -
linkerd check

# Inject into a namespace
kubectl annotate namespace default linkerd.io/inject=enabled
kubectl rollout restart deployment -n default
linkerd viz dashboard &
```

---

## Phase 4 (Weeks 13–16): Infrastructure as Code with Terraform

### Week 13: Terraform Basics

```hcl
# ~/devops-infra/terraform/main.tf

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "docker" {}

resource "docker_container" "nginx" {
  name  = "terraform-nginx"
  image = "nginx:alpine"
  ports {
    internal = 80
    external = 8181
  }
}
```

```bash
terraform init
terraform plan
terraform apply
terraform destroy
```

### Week 14: State Management

```bash
# Remote state with MinIO (S3-compatible)
cat > ~/devops-infra/terraform/backend.tf <<'EOF'
terraform {
  backend "s3" {
    bucket                      = "terraform-state"
    key                         = "devops-infra/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://localhost:9001"
    access_key                  = "minioadmin"
    secret_key                  = "minioadmin"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
EOF
```

### Week 15: Module Design

Structure your Terraform code as reusable modules:

```
~/devops-infra/terraform/
├── modules/
│   ├── monitoring/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── databases/
│   └── ingress/
├── environments/
│   ├── local/
│   │   └── main.tf
│   └── staging/
│       └── main.tf
└── main.tf
```

### Week 16: Workspace Strategy

```bash
# Use workspaces for environment isolation
terraform workspace new staging
terraform workspace new production
terraform workspace list
terraform workspace select staging
terraform apply -var-file=staging.tfvars
```

**Week 16 goal:** The entire infrastructure can be created from scratch with:
```bash
terraform init && terraform apply -auto-approve
```

---

## Phase 5 (Week 17+): SRE Practices

**Goal:** Move from "keeping things running" to "engineering reliability at scale."

### Week 17: Error Budgets and SLOs

#### Define SLOs for Each Service

```yaml
# ~/devops-infra/slos/slos.yaml
slos:
  - service: grafana
    slo: "99.9% availability measured over 30 days"
    error_budget_minutes: 43.8  # per month
    measurement: "probe_success{job='grafana'} == 1"

  - service: postgres
    slo: "99.95% availability"
    error_budget_minutes: 21.9
    measurement: "pg_up == 1"

  - service: api-gateway
    slo: "p99 latency < 500ms"
    measurement: "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) < 0.5"
```

#### Calculate Error Budgets

```promql
# Availability over last 30 days
avg_over_time(probe_success{job="grafana"}[30d]) * 100

# Remaining error budget (minutes)
(1 - avg_over_time(probe_success{job="grafana"}[30d])) * 30 * 24 * 60
```

### Week 18: Incident Management

- Run the 20 incident playbooks from INCIDENTS.md
- Conduct at least 3 full post-incident reviews
- Track MTTR and MTBF in the tracking table
- Practice on-call handoff procedures

### Week 19: Chaos Engineering

Use the chaos engineering framework in INC-020 to run structured experiments:

```bash
# Week 19 chaos calendar
# Monday:   Kill random pod every hour for 4 hours
# Tuesday:  Network partition between app and database
# Wednesday: CPU stress (4 cores, 30 minutes)
# Thursday: Fill disk to 90%, observe and recover
# Friday:   Complete chaos gameday — run 3 scenarios back-to-back
```

### Week 20: Capacity Planning

```bash
# Collect baseline metrics for 2 weeks, then project growth

# Example capacity report queries:
# Current memory usage trend
predict_linear(node_memory_MemAvailable_bytes[7d], 30 * 24 * 3600)

# Disk growth rate
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[7d], 30 * 24 * 3600)

# Generate capacity report
cat > /tmp/capacity-report.md <<EOF
# Capacity Report — $(date +%Y-%m)

## Current Resource Usage
| Resource | Current | 30-day Projection | Action Needed |
|----------|---------|-------------------|---------------|
| CPU | X% | X% | |
| RAM | X GB | X GB | |
| Disk | X GB | X GB | |
| Network | X Mbps | X Mbps | |
EOF
```

### Week 21+: On-Call Simulation

Simulate a full month of on-call:
- Daily morning checklist (5 min)
- Weekly infrastructure review (30 min)
- Respond to 2 simulated P2 incidents per week
- Monthly capacity review
- Quarterly disaster recovery drill

---

## Skills Assessment Rubric

### Junior DevOps Engineer (Phase 1 complete)

- [ ] Can deploy any service from docker-compose.yml
- [ ] Can create a K8s deployment and service from a manifest
- [ ] Can read Grafana dashboards and identify obvious anomalies
- [ ] Can connect to and query all 4 databases
- [ ] Can follow a runbook to resolve an incident
- [ ] Knows what each port in PORTS.md is used for

### Mid-level DevOps Engineer (Phase 2–3 complete)

- [ ] Can write Ansible playbooks without referring to docs
- [ ] Can write Helm charts for any application
- [ ] Can implement GitOps workflows with ArgoCD
- [ ] Can design and implement monitoring for a new service
- [ ] Can conduct a post-incident review
- [ ] Can explain the purpose of every service in the infrastructure

### Senior DevOps / SRE Engineer (Phase 4–5 complete)

- [ ] Can define and measure SLOs with error budgets
- [ ] Can design Terraform module structure for team use
- [ ] Can run chaos engineering experiments and draw conclusions
- [ ] Can produce capacity planning reports with projections
- [ ] Can design the architecture for a new service from requirements
- [ ] Can onboard a junior engineer to this entire system

---

## Recommended Reading

| Topic | Resource |
|-------|---------|
| SRE Book | Google Site Reliability Engineering (free online) |
| Kubernetes | "Kubernetes in Action" by Marko Luksa |
| Prometheus | "Prometheus: Up & Running" by Brian Brazil |
| Chaos Engineering | "Chaos Engineering" by Casey Rosenthal |
| Linux Performance | "Systems Performance" by Brendan Gregg |
| Terraform | HashiCorp Learn (learn.hashicorp.com) |
| Ansible | Red Hat Ansible Documentation |
| Security | "The DevSecOps Playbook" |

---

*Start at [SETUP.md](./SETUP.md) to get the infrastructure running.*
*Refer to [INCIDENTS.md](./INCIDENTS.md) for hands-on scenario practice.*
*See [ARCHITECTURE.md](./ARCHITECTURE.md) to understand how everything fits together.*
