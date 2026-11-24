# Workload Identity Federation for GitHub Actions: GitHub workflows get short-lived Google tokens
# from their OIDC token, so no service account key is ever stored in GitHub.
#
# This module creates only the pool and the provider, trusting tokens of one GitHub owner
# (user or organization). Which repository can impersonate which service account is decided in
# stacks/identities, from service_accounts.yaml (type: github, repo: <name>).

variable "project_id" {
  type = string
}

variable "github_owner" {
  description = "GitHub user or organization whose repositories may authenticate."
  type        = string
}

variable "pool_id" {
  type    = string
  default = "github"
}

variable "provider_id" {
  type    = string
  default = "github-oidc"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Tokens of any other GitHub owner are rejected before any IAM check.
  attribute_condition = "assertion.repository_owner == \"${var.github_owner}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

output "pool_name" {
  description = "projects/<number>/locations/global/workloadIdentityPools/github"
  value       = google_iam_workload_identity_pool.github.name
}

output "provider_name" {
  description = "Value of the GitHub variable WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}
