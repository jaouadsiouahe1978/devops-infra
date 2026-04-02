terraform {
  required_version = ">= 1.5"
  required_providers {
    local  = { source = "hashicorp/local",  version = ">= 2.4" }
    null   = { source = "hashicorp/null",   version = ">= 3.2" }
    docker = { source = "kreuzwerker/docker", version = ">= 3.0" }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  tags = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "devops-infra"
  }
  infra_dir = var.infra_dir
}

module "directories" {
  source    = "./modules/directories"
  infra_dir = var.infra_dir
  data_dir  = var.data_dir
}

module "docker_networks" {
  source         = "./modules/docker_networks"
  network_prefix = var.network_prefix
}

module "docker_volumes" {
  source = "./modules/docker_volumes"
}
