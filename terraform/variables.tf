variable "infra_dir" {
  description = "Root directory for the DevOps infrastructure"
  type        = string
  default     = "/home/jaouad/devops-infra"
}

variable "data_dir" {
  description = "Directory for persistent service data"
  type        = string
  default     = "/home/jaouad/devops-infra/data"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "environment must be one of: development, staging, production."
  }
}

variable "network_prefix" {
  description = "IP prefix for Docker networks (e.g. 172.20)"
  type        = string
  default     = "172.20"
}

variable "postgres_password" {
  description = "Password for the PostgreSQL root user"
  type        = string
  sensitive   = true
  default     = "DevOps2024!"
}

variable "grafana_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
  default     = "admin"
}
