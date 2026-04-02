# Architecture — DevOps/SRE Local Infrastructure

> Production-like local environment for DevOps/SRE training.
> Last updated: 2026-04-01

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Network Architecture](#2-network-architecture)
3. [Service Map & Ports](#3-service-map--ports)
4. [Data Flow](#4-data-flow)
5. [CI/CD Pipeline](#5-cicd-pipeline)
6. [Monitoring Stack](#6-monitoring-stack)
7. [Security Architecture](#7-security-architecture)
8. [Backup & DR Architecture](#8-backup--dr-architecture)
9. [Kubernetes Architecture](#9-kubernetes-architecture)
10. [Component Dependencies](#10-component-dependencies)

---

## 1. High-Level Overview

```mermaid
graph TB
    subgraph "Entry Points"
        TRAEFIK["Traefik :80/:443/:8080"]
        HAPROXY["HAProxy :8090"]
        NGINX["Nginx RP :8091"]
    end

    subgraph "CI/CD Layer"
        JENKINS["Jenkins :8081"]
        GITEA["Gitea :3001"]
        ARGOCD["ArgoCD :8083"]
    end

    subgraph "Application Layer"
        APP1["app-frontend :8000"]
        APP2["app-backend :8001"]
        APP3["app-worker :8002"]
    end

    subgraph "Orchestration"
        K3S["K3s / Kubernetes :6443"]
    end

    subgraph "Databases"
        PG["PostgreSQL :5432"]
        MYSQL["MySQL :3306"]
        REDIS["Redis :6379"]
        MONGO["MongoDB :27017"]
    end

    subgraph "Messaging"
        KAFKA["Kafka :9092"]
        ZK["ZooKeeper :2181"]
        RABBIT["RabbitMQ :5672/:15672"]
    end

    subgraph "Storage"
        MINIO["MinIO :9001/:9002"]
        NEXUS["Nexus :8084"]
        REGISTRY["Registry :5000"]
    end

    subgraph "Security"
        VAULT["Vault :8200"]
        CONSUL["Consul :8500"]
        KEYCLOAK["Keycloak :8085"]
    end

    subgraph "Monitoring Stack"
        PROM["Prometheus :9090"]
        GRAFANA["Grafana :3000"]
        ALERT["AlertManager :9093"]
        LOKI["Loki :3100"]
        PROMTAIL["Promtail :9080"]
    end

    subgraph "ELK Stack"
        ES["Elasticsearch :9200"]
        KIBANA["Kibana :5601"]
        LOGSTASH["Logstash :5044"]
    end

    subgraph "Code Quality"
        SONAR["SonarQube :9001"]
    end

    TRAEFIK --> APP1
    TRAEFIK --> APP2
    TRAEFIK --> GRAFANA
    HAPROXY --> TRAEFIK
    NGINX --> GRAFANA
    NGINX --> PROM
    NGINX --> KIBANA

    JENKINS --> GITEA
    JENKINS --> NEXUS
    JENKINS --> REGISTRY
    JENKINS --> SONAR
    ARGOCD --> K3S

    APP2 --> PG
    APP2 --> REDIS
    APP2 --> MONGO
    APP3 --> KAFKA
    APP3 --> RABBIT

    K3S --> PG
    K3S --> REDIS

    VAULT --> CONSUL
    KEYCLOAK --> PG

    PROM --> GRAFANA
    PROM --> ALERT
    LOKI --> GRAFANA
    PROMTAIL --> LOKI
    LOGSTASH --> ES
    ES --> KIBANA
```

---

## 2. Network Architecture

```mermaid
graph LR
    subgraph "devops-frontend 172.20.0.0/24"
        TRAEFIK2["Traefik"]
        HAPROXY2["HAProxy"]
        NGINX2["Nginx"]
    end

    subgraph "devops-databases 172.20.1.0/24"
        PG2["PostgreSQL :5432"]
        MYSQL2["MySQL :3306"]
        REDIS2["Redis :6379"]
        MONGO2["MongoDB :27017"]
    end

    subgraph "devops-monitoring 172.20.2.0/24"
        PROM2["Prometheus"]
        GRAFANA2["Grafana"]
        ALERT2["AlertManager"]
        LOKI2["Loki"]
    end

    subgraph "devops-elk 172.20.3.0/24"
        ES2["Elasticsearch"]
        KIBANA2["Kibana"]
        LOGSTASH2["Logstash"]
    end

    subgraph "devops-cicd 172.20.4.0/24"
        JENKINS2["Jenkins"]
        GITEA2["Gitea"]
        ARGOCD2["ArgoCD"]
    end

    subgraph "devops-security 172.20.5.0/24"
        VAULT2["Vault"]
        CONSUL2["Consul"]
        KEYCLOAK2["Keycloak"]
    end

    subgraph "devops-messaging 172.20.6.0/24"
        KAFKA2["Kafka"]
        RABBIT2["RabbitMQ"]
    end

    subgraph "devops-storage 172.20.7.0/24"
        MINIO2["MinIO"]
        NEXUS2["Nexus"]
        REG2["Registry"]
    end

    TRAEFIK2 -.->|routes| PG2
    TRAEFIK2 -.->|routes| GRAFANA2
    GRAFANA2 -->|queries| PROM2
    GRAFANA2 -->|queries| LOKI2
    LOGSTASH2 -->|indexes| ES2
    KEYCLOAK2 -->|stores| PG2
    CONSUL2 -->|service discovery| VAULT2
```

---

## 3. Service Map & Ports

| Service | Port | Network | Category | Status Default |
|---------|------|---------|----------|----------------|
| PostgreSQL | 5432 | databases | DB | stopped |
| MySQL | 3306 | databases | DB | stopped |
| Redis | 6379 | databases | DB | stopped |
| MongoDB | 27017 | databases | DB | stopped |
| Prometheus | 9090 | monitoring | Monitoring | stopped |
| Grafana | 3000 | monitoring | Monitoring | stopped |
| AlertManager | 9093 | monitoring | Monitoring | stopped |
| Loki | 3100 | monitoring | Monitoring | stopped |
| Promtail | 9080 | monitoring | Monitoring | stopped |
| Node Exporter | 9100 | host | Exporter | stopped |
| cAdvisor | 8088 | host | Exporter | stopped |
| PG Exporter | 9187 | databases | Exporter | stopped |
| Redis Exporter | 9121 | databases | Exporter | stopped |
| MySQL Exporter | 9104 | databases | Exporter | stopped |
| MongoDB Exporter | 9216 | databases | Exporter | stopped |
| Nginx Exporter | 9113 | frontend | Exporter | stopped |
| Blackbox Exporter | 9115 | monitoring | Exporter | stopped |
| Elasticsearch | 9200 | elk | ELK | stopped |
| Kibana | 5601 | elk | ELK | stopped |
| Logstash | 5044 | elk | ELK | stopped |
| Jenkins | 8081 | cicd | CI/CD | stopped |
| Gitea | 3001 | cicd | CI/CD | stopped |
| ArgoCD | 8083 | cicd | CI/CD | stopped |
| Vault | 8200 | security | Security | stopped |
| Consul | 8500 | security | Security | stopped |
| Keycloak | 8085 | security | Security | stopped |
| Kafka | 9092 | messaging | Messaging | stopped |
| RabbitMQ AMQP | 5672 | messaging | Messaging | stopped |
| RabbitMQ Mgmt | 15672 | messaging | Messaging | stopped |
| MinIO API | 9001 | storage | Storage | stopped |
| MinIO Console | 9002 | storage | Storage | stopped |
| Nexus | 8084 | storage | Storage | stopped |
| Docker Registry | 5000 | storage | Storage | stopped |
| Traefik HTTP | 80 | frontend | Proxy | stopped |
| Traefik HTTPS | 443 | frontend | Proxy | stopped |
| Traefik Dashboard | 8080 | frontend | Proxy | stopped |
| HAProxy | 8090 | frontend | LB | stopped |
| Nginx RP | 8091 | frontend | Proxy | stopped |
| SonarQube | 9001 | cicd | Quality | stopped |
| K3s API | 6443 | host | K8s | stopped |
| etcd | 2379 | host | K8s | stopped |

---

## 4. Data Flow

### Log Collection Pipeline

```mermaid
sequenceDiagram
    participant App as Applications
    participant Promtail as Promtail
    participant Loki as Loki
    participant Logstash as Logstash
    participant ES as Elasticsearch
    participant Grafana as Grafana
    participant Kibana as Kibana

    App->>Promtail: Write logs to /var/log & /devops-infra/logs
    Promtail->>Loki: Push log streams (HTTP)
    App->>Logstash: Send structured logs (TCP/UDP 5044)
    Logstash->>ES: Index documents
    Grafana->>Loki: Query logs (LogQL)
    Kibana->>ES: Query & visualize (KQL)
```

### Metrics Collection Pipeline

```mermaid
sequenceDiagram
    participant Services as Services
    participant Exporters as Prometheus Exporters
    participant Prom as Prometheus
    participant AlertMgr as AlertManager
    participant Grafana as Grafana
    participant Slack as Slack/File

    Services->>Exporters: Expose /metrics endpoint
    Prom->>Exporters: Scrape every 15s
    Prom->>AlertMgr: Fire alert when rule matches
    AlertMgr->>Slack: Send notification
    Grafana->>Prom: Query (PromQL)
    Prom->>Prom: Evaluate recording rules
```

---

## 5. CI/CD Pipeline

```mermaid
graph LR
    DEV["Developer"] -->|git push| GITEA["Gitea"]
    GITEA -->|webhook| JENKINS["Jenkins"]
    JENKINS -->|checkout| GITEA
    JENKINS -->|build| DOCKER["Docker Build"]
    DOCKER -->|push| REGISTRY["Docker Registry"]
    JENKINS -->|scan| SONAR["SonarQube"]
    JENKINS -->|test| JUNIT["JUnit Tests"]
    JENKINS -->|artifact| NEXUS["Nexus"]
    JENKINS -->|notify| ARGOCD["ArgoCD"]
    ARGOCD -->|sync| K8S["Kubernetes"]
    K8S -->|pull| REGISTRY
    ARGOCD -->|health check| K8S
```

### Pipeline Stages

```mermaid
stateDiagram-v2
    [*] --> Checkout
    Checkout --> Build
    Build --> UnitTest
    UnitTest --> StaticAnalysis
    StaticAnalysis --> ContainerBuild
    ContainerBuild --> SecurityScan
    SecurityScan --> PushArtifacts
    PushArtifacts --> DeployStaging
    DeployStaging --> IntegrationTest
    IntegrationTest --> Approval
    Approval --> DeployProd
    DeployProd --> HealthCheck
    HealthCheck --> [*]
    
    UnitTest --> [*]: FAIL
    StaticAnalysis --> [*]: FAIL (quality gate)
    SecurityScan --> [*]: FAIL (critical CVE)
    IntegrationTest --> [*]: FAIL
    HealthCheck --> Rollback: FAIL
    Rollback --> [*]
```

---

## 6. Monitoring Stack

```mermaid
graph TB
    subgraph "Metrics"
        NE["node_exporter\n:9100"]
        CA["cAdvisor\n:8088"]
        PGE["postgres_exporter\n:9187"]
        RE["redis_exporter\n:9121"]
        ME["mysql_exporter\n:9104"]
        MOE["mongodb_exporter\n:9216"]
        KE["kafka_exporter\n:9308"]
        RMQE["rabbitmq_exporter\n:15692"]
        BB["blackbox_exporter\n:9115"]
        NGE["nginx_exporter\n:9113"]
    end

    subgraph "Collection & Evaluation"
        PROM["Prometheus\n:9090\n15s scrape\n15d retention"]
        REC["Recording Rules\n(pre-computed metrics)"]
        ALR["Alert Rules\n(50+ alerts)"]
    end

    subgraph "Alerting"
        AM["AlertManager\n:9093\nrouting + dedup"]
        SLACK["→ Slack webhook"]
        FILE["→ /logs/alerts.log"]
    end

    subgraph "Visualization"
        GRF["Grafana :3000\n5 dashboards"]
        LOKI["Loki :3100\nlog aggregation"]
        PT["Promtail :9080\nlog shipping"]
    end

    subgraph "Log Indexing"
        LS["Logstash :5044"]
        ES["Elasticsearch :9200"]
        KB["Kibana :5601"]
    end

    NE --> PROM
    CA --> PROM
    PGE --> PROM
    RE --> PROM
    ME --> PROM
    MOE --> PROM
    KE --> PROM
    RMQE --> PROM
    BB --> PROM
    NGE --> PROM

    PROM --> REC
    PROM --> ALR
    ALR --> AM
    AM --> SLACK
    AM --> FILE

    PROM --> GRF
    LOKI --> GRF
    PT --> LOKI

    LS --> ES
    ES --> KB
```

---

## 7. Security Architecture

```mermaid
graph TB
    subgraph "Secret Management"
        VAULT["HashiCorp Vault :8200"]
        VS["KV Secrets Engine\nDB passwords, API keys"]
        VP["PKI Engine\nCertificate authority"]
        VA["Auth Methods\nToken, AppRole, K8s"]
    end

    subgraph "Service Mesh / Discovery"
        CONSUL["Consul :8500"]
        SD["Service Discovery"]
        HC["Health Checks"]
        KV["Key-Value Store"]
    end

    subgraph "Identity & Access"
        KC["Keycloak :8085\nSSO / OIDC"]
        REALM["devops-realm"]
        CLIENTS["Jenkins, Grafana,\nArgoCD clients"]
    end

    subgraph "Network Security"
        IPT["iptables rules\n(allow-listed ports only)"]
        F2B["fail2ban\n(brute-force protection)"]
        NP["K8s NetworkPolicies\n(namespace isolation)"]
        TLS["TLS everywhere\n(self-signed CA)"]
    end

    subgraph "Linux RBAC"
        GADM["devops-admin\n(full sudo)"]
        SRE["sre-oncall\n(limited sudo)"]
        DEV["devops-dev\n(no sudo)"]
        RO["devops-readonly\n(read only)"]
    end

    VAULT --> VS
    VAULT --> VP
    VAULT --> VA
    CONSUL --> SD
    CONSUL --> HC
    KC --> REALM
    KC --> CLIENTS
```

---

## 8. Backup & DR Architecture

```mermaid
graph LR
    subgraph "Sources"
        PG3["PostgreSQL"]
        MY3["MySQL"]
        RD3["Redis"]
        MG3["MongoDB"]
        CFG["Configs\n(ansible/k8s/terraform)"]
        K8S3["K8s state"]
        VLT["Vault secrets"]
    end

    subgraph "Backup Process (02:00 daily)"
        BKP["backup.sh\n--service=all"]
        COMPRESS["gzip compression"]
        VERIFY["integrity check\n(gzip -t)"]
    end

    subgraph "Storage (3-2-1 Strategy)"
        LOCAL["/devops-infra/backups/\n(Copy 1 - local)"]
        MINIO3["MinIO bucket\n(Copy 2 - object store)"]
        NOTE["Copy 3: Manual export\nto USB/NAS monthly"]
    end

    subgraph "Retention Policy"
        D7["Daily: 7 days"]
        W4["Weekly: 4 weeks"]
        M12["Monthly: 12 months"]
    end

    subgraph "DR Testing"
        DRT["dr-test.sh\n(weekly Sunday 03:00)"]
        RPO["RPO target: 24h"]
        RTO["RTO target: 4h"]
    end

    PG3 --> BKP
    MY3 --> BKP
    RD3 --> BKP
    MG3 --> BKP
    CFG --> BKP
    K8S3 --> BKP
    VLT --> BKP

    BKP --> COMPRESS
    COMPRESS --> VERIFY
    VERIFY --> LOCAL
    LOCAL --> MINIO3

    LOCAL --> D7
    LOCAL --> W4
    LOCAL --> M12

    DRT --> RPO
    DRT --> RTO
```

---

## 9. Kubernetes Architecture

```mermaid
graph TB
    subgraph "K3s Cluster (single node)"
        API["kube-apiserver :6443"]
        SCHED["kube-scheduler"]
        CM["controller-manager"]
        ETCD2["etcd :2379"]
        KUBELET["kubelet"]
        KPROXY["kube-proxy"]
    end

    subgraph "Namespaces"
        NS_MON["monitoring\n(prometheus, grafana, loki)"]
        NS_DB["databases\n(postgres, redis, mongodb)"]
        NS_CICD["cicd\n(jenkins, argocd)"]
        NS_SEC["security\n(vault, keycloak)"]
        NS_MSG["messaging\n(kafka, rabbitmq)"]
        NS_STG["storage\n(minio, nexus, registry)"]
        NS_PROD["production"]
        NS_STG2["staging"]
        NS_DEV["development"]
    end

    subgraph "Core Resources"
        SC["StorageClasses\n(local-path, manual)"]
        NP2["NetworkPolicies\n(namespace isolation)"]
        RQ["ResourceQuotas\n(per namespace)"]
        LR["LimitRanges\n(per namespace)"]
        HPA2["HPA\n(auto-scaling rules)"]
        RBAC2["RBAC\n(roles + bindings)"]
    end

    API --> SCHED
    API --> CM
    API --> ETCD2
    KUBELET --> KPROXY

    API --> NS_MON
    API --> NS_DB
    API --> NS_CICD
    API --> NS_SEC
    API --> NS_MSG
    API --> NS_STG
    API --> NS_PROD
    API --> NS_STG2
    API --> NS_DEV
```

---

## 10. Component Dependencies

```mermaid
graph TD
    DOCKER["Docker Engine"] --> PG4["PostgreSQL"]
    DOCKER --> MYSQL4["MySQL"]
    DOCKER --> REDIS4["Redis"]
    DOCKER --> MONGO4["MongoDB"]
    DOCKER --> ES4["Elasticsearch"]
    DOCKER --> PROM4["Prometheus"]
    DOCKER --> LOKI4["Loki"]
    DOCKER --> JENKINS4["Jenkins"]

    K3S4["K3s"] --> DOCKER

    CONSUL4["Consul"] --> VAULT4["Vault"]
    PG4 --> KEYCLOAK4["Keycloak"]
    PG4 --> SONAR4["SonarQube"]
    PG4 --> ARGOCD4["ArgoCD (DB)"]

    ZK4["ZooKeeper"] --> KAFKA4["Kafka"]

    PROM4 --> ALERTMGR4["AlertManager"]
    PROM4 --> GRAFANA4["Grafana"]
    LOKI4 --> GRAFANA4

    ES4 --> KIBANA4["Kibana"]
    LOGSTASH4["Logstash"] --> ES4

    JENKINS4 --> NEXUS4["Nexus"]
    JENKINS4 --> REGISTRY4["Registry"]
    JENKINS4 --> SONAR4
    ARGOCD4 --> K3S4

    TRAEFIK4["Traefik"] --> GRAFANA4
    TRAEFIK4 --> JENKINS4
    TRAEFIK4 --> ARGOCD4

    style DOCKER fill:#0db7ed
    style K3S4 fill:#326ce5,color:#fff
    style VAULT4 fill:#000,color:#fff
    style PROM4 fill:#e6522c,color:#fff
    style GRAFANA4 fill:#f46800,color:#fff
```

---

## Quick Reference

### Start minimal monitoring stack
```bash
cd ~/devops-infra
make db-start
make monitoring-start
```

### Start full stack (resource heavy ~8GB RAM)
```bash
make up
```

### Check what's running
```bash
make status
make health
```

### Access UIs
| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| AlertManager | http://localhost:9093 | - |
| Kibana | http://localhost:5601 | elastic/DevOps2024!ES |
| Jenkins | http://localhost:8081 | admin/admin |
| Vault | http://localhost:8200 | token: dev-root-token |
| Consul | http://localhost:8500 | - |
| Keycloak | http://localhost:8085 | admin/DevOps2024!KC |
| MinIO | http://localhost:9002 | minioadmin/DevOps2024!Minio |
| Nexus | http://localhost:8084 | admin/(first-time setup) |
| Traefik | http://localhost:8080 | - |
| RabbitMQ | http://localhost:15672 | admin/DevOps2024!RMQ |
| Gitea | http://localhost:3001 | (setup on first access) |
| SonarQube | http://localhost:9001 | admin/admin |
