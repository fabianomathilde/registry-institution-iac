output "service_account_emails" {
  value = { for n, sa in google_service_account.this : n => sa.email }
}

output "access_matrix" {
  description = "Service account -> component -> Google role. The review view of service_accounts.yaml."
  value = {
    for n, sa in local.s.service_accounts : n => {
      email = google_service_account.this[n].email
      type  = sa.type
      used_by = (sa.type == "github"
        ? "github:${local.s.project.github_owner}/${sa.repo}"
      : "k8s:${sa.namespace}/${sa.ksa_name}")
      access = { for k, g in local.grants : g.ref => "${g.role} (${g.gcp_role})" if g.sa == n }
    }
  }
}

output "ksa" {
  description = "Kubernetes service accounts for stacks/platform: name -> namespace, KSA name, GSA email."
  value = {
    for n, sa in local.s.service_accounts : n => {
      namespace = sa.namespace
      name      = sa.ksa_name
      gsa_email = google_service_account.this[n].email
    } if sa.type == "workload"
  }
}

output "namespace_deployers" {
  description = "Namespace -> emails allowed to deploy into it (stacks/platform turns this into RBAC)."
  value = {
    for ns in distinct([for g in values(local.by_type.namespace) : g.name]) : ns => sort([
      for g in values(local.by_type.namespace) : google_service_account.this[g.sa].email if g.name == ns
    ])
  }
}

output "github_variables" {
  description = "Per GitHub service account: the variables to set in the repository's GitHub Environment."
  value = {
    for n, sa in local.s.service_accounts : n => {
      for k, v in {
        GCP_PROJECT_ID = local.project
        GCP_REGION     = local.region
        WIF_PROVIDER   = local.foundation.wif_provider_name
        DEPLOYER_SA    = google_service_account.this[n].email
        GKE_CLUSTER    = local.foundation.cluster_name
        # The registry this account can push to (the first one, if several).
        ARTIFACT_REPOSITORY = try(local.components.registries[[for g in values(local.by_type.registry) : g.name if g.sa == n && g.role == "writer"][0]].url, null)
      } : k => v if v != null
    } if sa.type == "github"
  }
}

output "github_variables_iac_repo" {
  description = "Variables for the IaC repository's GitHub Environment (the github account whose repo is project.yaml github.iac_repo)."
  value = try({
    GCP_PROJECT_ID = local.project
    WIF_PROVIDER   = local.foundation.wif_provider_name
    TERRAFORM_SA = [
      for n, sa in local.s.service_accounts : google_service_account.this[n].email
      if sa.type == "github" && sa.repo == local.s.project.iac_repo
    ][0]
  }, null)
}
