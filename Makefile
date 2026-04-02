# =============================================================================
# DevOps Infrastructure Makefile
# Usage: make <target>
# =============================================================================

INFRA_DIR := $(shell pwd)
SCRIPTS   := $(INFRA_DIR)/scripts
COMPOSE   := docker compose -f $(INFRA_DIR)/docker/docker-compose.yml
ANSIBLE   := ansible-playbook -i $(INFRA_DIR)/ansible/inventory.yaml
KUBECTL   := kubectl

.DEFAULT_GOAL := help

.PHONY: help install up down status health port-check logs backup restore
.PHONY: db-start db-stop monitoring-start monitoring-stop elk-start elk-stop
.PHONY: cicd-start cicd-stop security-start messaging-start storage-start
.PHONY: k8s-apply k8s-delete k8s-status incident chaos clean fmt

# =============================================================================
# HELP
# =============================================================================
help: ## Show this help
	@echo ""
	@echo "  DevOps Infrastructure Commands"
	@echo "  ==============================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# INSTALLATION
# =============================================================================
install: ## Run full installation (sudo required)
	@bash $(INFRA_DIR)/install.sh

install-dry-run: ## Dry run installation
	@bash $(INFRA_DIR)/install.sh --dry-run

setup-crons: ## Set up all cron jobs
	@bash $(SCRIPTS)/cron-setup.sh

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================
up: ## Start ALL services (warning: resource intensive)
	@$(COMPOSE) --profile databases --profile monitoring --profile elk \
		--profile cicd --profile security --profile messaging --profile storage up -d

down: ## Stop ALL Docker services
	@$(COMPOSE) down

restart: ## Restart all Docker services
	@$(COMPOSE) restart

db-start: ## Start database services (postgres, mysql, redis, mongodb)
	@$(COMPOSE) --profile databases up -d
	@echo "Databases started: postgres:5432 mysql:3306 redis:6379 mongodb:27017"

db-stop: ## Stop database services
	@$(COMPOSE) --profile databases stop

monitoring-start: ## Start monitoring stack (prometheus, grafana, alertmanager)
	@$(COMPOSE) --profile monitoring up -d
	@echo "Monitoring started: Grafana http://localhost:3000 | Prometheus http://localhost:9090"

monitoring-stop: ## Stop monitoring stack
	@$(COMPOSE) --profile monitoring stop

elk-start: ## Start ELK stack (elasticsearch, kibana, logstash)
	@$(COMPOSE) --profile elk up -d
	@echo "ELK started: Kibana http://localhost:5601 | ES http://localhost:9200"

elk-stop: ## Stop ELK stack
	@$(COMPOSE) --profile elk stop

cicd-start: ## Start CI/CD (jenkins, gitea, argocd)
	@docker compose -f $(INFRA_DIR)/docker/compose/cicd.yml up -d
	@echo "CI/CD started: Jenkins http://localhost:8081 | Gitea http://localhost:3001 | ArgoCD http://localhost:8083"

cicd-stop: ## Stop CI/CD stack
	@docker compose -f $(INFRA_DIR)/docker/compose/cicd.yml down

security-start: ## Start security stack (vault, consul, keycloak)
	@docker compose -f $(INFRA_DIR)/docker/compose/security.yml up -d
	@echo "Security started: Vault http://localhost:8200 | Consul http://localhost:8500 | Keycloak http://localhost:8085"

security-stop: ## Stop security stack
	@docker compose -f $(INFRA_DIR)/docker/compose/security.yml down

messaging-start: ## Start messaging (kafka, zookeeper, rabbitmq)
	@docker compose -f $(INFRA_DIR)/docker/compose/messaging.yml up -d
	@echo "Messaging started: Kafka:9092 | RabbitMQ http://localhost:15672"

messaging-stop: ## Stop messaging stack
	@docker compose -f $(INFRA_DIR)/docker/compose/messaging.yml down

storage-start: ## Start storage (minio, nexus, registry)
	@docker compose -f $(INFRA_DIR)/docker/compose/storage.yml up -d
	@echo "Storage started: MinIO http://localhost:9002 | Nexus http://localhost:8084 | Registry localhost:5000"

storage-stop: ## Stop storage stack
	@docker compose -f $(INFRA_DIR)/docker/compose/storage.yml down

networking-start: ## Start networking (traefik, haproxy, nginx)
	@docker compose -f $(INFRA_DIR)/docker/compose/networking.yml up -d
	@echo "Networking started: Traefik http://localhost:8080 | HAProxy http://localhost:9999 | Nginx http://localhost:8091"

networking-stop: ## Stop networking stack
	@docker compose -f $(INFRA_DIR)/docker/compose/networking.yml down

loki-start: ## Start Loki + Promtail (log aggregation)
	@docker compose -f $(INFRA_DIR)/docker/compose/loki.yml up -d
	@echo "Loki started: http://localhost:3100"

loki-stop: ## Stop Loki stack
	@docker compose -f $(INFRA_DIR)/docker/compose/loki.yml down

sonar-start: ## Start SonarQube (code quality)
	@docker compose -f $(INFRA_DIR)/docker/compose/sonarqube.yml up -d
	@echo "SonarQube started: http://localhost:9000 (admin/admin)"

sonar-stop: ## Stop SonarQube
	@docker compose -f $(INFRA_DIR)/docker/compose/sonarqube.yml down

tools-start: ## Start DevOps UI tools (portainer, redisinsight, pgadmin, kafka-ui)
	@docker compose -f $(INFRA_DIR)/docker/compose/tools.yml up -d
	@echo "Tools: Portainer https://localhost:9443 | pgAdmin http://localhost:5050 | Kafka-UI http://localhost:8089 | RedisInsight http://localhost:8001"

tools-stop: ## Stop DevOps UI tools
	@docker compose -f $(INFRA_DIR)/docker/compose/tools.yml down

etcd-start: ## Start etcd cluster
	@docker compose -f $(INFRA_DIR)/docker/compose/etcd.yml up -d
	@echo "etcd started: localhost:2379"

etcd-stop: ## Stop etcd
	@docker compose -f $(INFRA_DIR)/docker/compose/etcd.yml down

# =============================================================================
# HEALTH & MONITORING
# =============================================================================
status: ## Show all service status
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
	@echo ""
	@$(KUBECTL) get pods --all-namespaces 2>/dev/null || true

health: ## Run health check
	@bash $(SCRIPTS)/health-check.sh

ports: ## Check all port statuses
	@bash $(SCRIPTS)/port-check.sh

ports-used: ## Show only ports in use
	@bash $(SCRIPTS)/port-check.sh --used

logs: ## View logs (SERVICE=name make logs)
	@bash $(SCRIPTS)/log-viewer.sh --service=$(or $(SERVICE),grafana) --since=1h

logs-errors: ## View error logs only
	@bash $(SCRIPTS)/log-viewer.sh --service=$(or $(SERVICE),grafana) --errors-only

certs: ## Check certificate expiry
	@bash $(SCRIPTS)/cert-check.sh

# =============================================================================
# BACKUP & RESTORE
# =============================================================================
backup: ## Run full backup
	@bash $(SCRIPTS)/backup.sh --service=all

backup-db: ## Backup databases only
	@bash $(SCRIPTS)/backup.sh --service=databases

backup-verify: ## Verify latest backups
	@bash $(SCRIPTS)/backup.sh --verify

restore: ## Interactive restore (BACKUP=path SERVICE=name)
	@bash $(SCRIPTS)/restore.sh $(if $(BACKUP),--backup=$(BACKUP)) $(if $(SERVICE),--service=$(SERVICE))

# =============================================================================
# INCIDENTS & CHAOS
# =============================================================================
incident: ## Run incident scenario (N=1-20 make incident)
	@bash $(SCRIPTS)/incident-simulator.sh --scenario=$(or $(N),1)

incident-list: ## List all incident scenarios
	@bash $(SCRIPTS)/incident-simulator.sh --list

incident-resolve: ## Resolve active incident
	@bash $(SCRIPTS)/incident-simulator.sh --resolve

chaos: ## Run chaos tool (CMD=add-latency make chaos)
	@bash $(SCRIPTS)/chaos-tools.sh $(or $(CMD),status)

chaos-cleanup: ## Stop all active chaos
	@bash $(SCRIPTS)/chaos-tools.sh cleanup-all

# =============================================================================
# KUBERNETES
# =============================================================================
k8s-status: ## Show K8s cluster status
	@$(KUBECTL) cluster-info
	@$(KUBECTL) get nodes
	@$(KUBECTL) get pods --all-namespaces

k8s-apply: ## Apply all K8s manifests
	@$(KUBECTL) apply -f $(INFRA_DIR)/kubernetes/namespaces/
	@$(KUBECTL) apply -f $(INFRA_DIR)/kubernetes/manifests/core/
	@$(KUBECTL) apply -f $(INFRA_DIR)/kubernetes/manifests/monitoring/
	@$(KUBECTL) apply -f $(INFRA_DIR)/kubernetes/manifests/databases/

k8s-apply-ns: ## Apply namespace configs only
	@$(KUBECTL) apply -f $(INFRA_DIR)/kubernetes/namespaces/

k8s-delete: ## Delete K8s resources (WARNING: destructive)
	@read -p "This will delete K8s resources. Type 'yes' to confirm: " c; \
		[[ "$$c" == "yes" ]] && $(KUBECTL) delete -f $(INFRA_DIR)/kubernetes/manifests/ || echo "Aborted"

k8s-drain: ## Drain the local node (NODE=node-name)
	@$(KUBECTL) cordon $(or $(NODE),$(shell kubectl get nodes -o name | head -1 | cut -d/ -f2))
	@$(KUBECTL) drain $(or $(NODE),$(shell kubectl get nodes -o name | head -1 | cut -d/ -f2)) \
		--ignore-daemonsets --delete-emptydir-data --grace-period=30

k8s-uncordon: ## Uncordon the local node
	@$(KUBECTL) uncordon $(or $(NODE),$(shell kubectl get nodes -o name | head -1 | cut -d/ -f2))

k8s-top: ## Show resource usage
	@$(KUBECTL) top nodes 2>/dev/null || echo "metrics-server not available"
	@$(KUBECTL) top pods --all-namespaces 2>/dev/null || true

# =============================================================================
# ANSIBLE
# =============================================================================
ansible-base: ## Run base installation playbook
	@$(ANSIBLE) $(INFRA_DIR)/ansible/playbooks/01-install-base.yaml

ansible-docker: ## Install Docker via Ansible
	@$(ANSIBLE) $(INFRA_DIR)/ansible/playbooks/02-install-docker.yaml

ansible-k3s: ## Install K3s via Ansible
	@$(ANSIBLE) $(INFRA_DIR)/ansible/playbooks/03-install-k3s.yaml

ansible-databases: ## Configure databases via Ansible
	@$(ANSIBLE) $(INFRA_DIR)/ansible/playbooks/04-install-databases.yaml

ansible-monitoring: ## Configure monitoring via Ansible
	@$(ANSIBLE) $(INFRA_DIR)/ansible/playbooks/05-install-monitoring.yaml

ansible-all: ## Run all playbooks in order
	@for pb in $(INFRA_DIR)/ansible/playbooks/*.yaml; do \
		echo "Running: $$pb"; \
		$(ANSIBLE) "$$pb" || exit 1; \
	done

ansible-validate: ## Validate all playbooks syntax
	@for pb in $(INFRA_DIR)/ansible/playbooks/*.yaml; do \
		ansible-playbook --syntax-check "$$pb" && echo "OK: $$pb" || echo "FAIL: $$pb"; \
	done

# =============================================================================
# TERRAFORM
# =============================================================================
tf-init: ## Initialize Terraform
	@cd $(INFRA_DIR)/terraform && terraform init

tf-plan: ## Plan Terraform changes
	@cd $(INFRA_DIR)/terraform && terraform plan -out=tfplan

tf-apply: ## Apply Terraform changes
	@cd $(INFRA_DIR)/terraform && terraform apply tfplan

tf-destroy: ## Destroy Terraform resources (WARNING)
	@cd $(INFRA_DIR)/terraform && terraform destroy

tf-validate: ## Validate Terraform configs
	@cd $(INFRA_DIR)/terraform && terraform validate

# =============================================================================
# CLEANUP
# =============================================================================
clean-docker: ## Clean Docker resources (images, volumes, networks)
	@docker system prune -f
	@docker volume prune -f
	@echo "Docker cleaned"

clean-logs: ## Rotate and compress old logs
	@find $(INFRA_DIR)/logs -name "*.log" -size +50M -exec gzip {} \;
	@find $(INFRA_DIR)/logs -name "*.log.gz" -mtime +30 -delete
	@echo "Logs cleaned"

clean-backups: ## Remove old backups (older than 30 days)
	@find $(INFRA_DIR)/backups -mtime +30 -name "*.tar.gz" -delete
	@echo "Old backups removed"

clean: clean-docker clean-logs clean-backups ## Clean everything

# =============================================================================
# DOCS
# =============================================================================
docs-serve: ## Serve documentation locally (requires python3)
	@cd $(INFRA_DIR)/docs && python3 -m http.server 8099

# =============================================================================
# META
# =============================================================================
version: ## Show tool versions
	@echo "=== Tool Versions ==="
	@docker --version 2>/dev/null || echo "docker: not installed"
	@kubectl version --client 2>/dev/null | head -1 || echo "kubectl: not installed"
	@helm version --short 2>/dev/null || echo "helm: not installed"
	@ansible --version 2>/dev/null | head -1 || echo "ansible: not installed"
	@terraform version 2>/dev/null | head -1 || echo "terraform: not installed"
	@k9s version 2>/dev/null | head -1 || echo "k9s: not installed"
