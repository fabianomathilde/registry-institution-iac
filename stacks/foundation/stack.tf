terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  # Partial configuration: scripts/tf.sh passes bucket=<project_id>-tfstate and prefix=foundation.
  backend "gcs" {}
}

variable "env_dir" {
  description = "Folder with the environment's YAML files (scripts/tf.sh passes envs/<env>)."
  type        = string
}

module "settings" {
  source  = "../../modules/settings"
  env_dir = var.env_dir
}

locals {
  s       = module.settings
  project = module.settings.project.project_id
  region  = module.settings.project.region
}

provider "google" {
  project = local.project
  region  = local.region
}
