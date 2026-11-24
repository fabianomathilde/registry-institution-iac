# Identities: every Google service account and every permission, from service_accounts.yaml.
#
#   type: workload -> GSA sa-<name>, usable by the Kubernetes service account sa-<name> in its
#                     namespace (Workload Identity). The KSA itself is created by stacks/platform.
#   type: github   -> GSA sa-<name>, usable by GitHub Actions workflows of one repository (WIF).
#
#   access: <type>/<component>: <role>  ->  the IAM grant below, on that component only.
#
# Nothing else in the organization grants roles to these accounts: apps never create IAM.

locals {
  foundation = data.terraform_remote_state.foundation.outputs
  components = data.terraform_remote_state.components.outputs

  # Role names of the access vocabulary -> Google predefined roles.
  roles = {
    firestore = { reader = "roles/datastore.viewer", writer = "roles/datastore.user" }
    cloudsql  = { client = "roles/cloudsql.client" }
    secret    = { reader = "roles/secretmanager.secretAccessor" }
    topic     = { publisher = "roles/pubsub.publisher", subscriber = "roles/pubsub.subscriber", viewer = "roles/pubsub.viewer" }
    registry  = { reader = "roles/artifactregistry.reader", writer = "roles/artifactregistry.writer" }
    namespace = { deployer = "roles/container.clusterViewer" } # + Kubernetes RBAC, stacks/platform
    dns       = { admin = "roles/dns.admin" }
    project   = { viewer = "roles/viewer", editor = "roles/editor", owner = "roles/owner" }
  }

  grants = { for g in local.s.grants : g.key => merge(g, { gcp_role = local.roles[g.type][g.role] }) }

  by_type = { for t in keys(local.roles) : t => { for k, g in local.grants : k => g if g.type == t } }
}

# ---------------------------------------------------------------- service accounts

resource "google_service_account" "this" {
  for_each = local.s.service_accounts

  account_id   = each.value.account_id
  display_name = each.key
  description = (each.value.type == "github"
    ? "GitHub Actions of ${local.s.project.github_owner}/${each.value.repo} (service_accounts.yaml)"
  : "Workload ${each.value.namespace}/${each.value.ksa_name} (service_accounts.yaml)")
}

# GitHub repository -> service account (any workflow of that repository).
resource "google_service_account_iam_member" "github" {
  for_each = { for n, sa in local.s.service_accounts : n => sa if sa.type == "github" }

  service_account_id = google_service_account.this[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.foundation.wif_pool_name}/attribute.repository/${local.s.project.github_owner}/${each.value.repo}"
}

# Kubernetes service account -> service account. The Workload Identity pool <project>.svc.id.goog
# exists only once the cluster exists, so these bindings wait for it.
resource "google_service_account_iam_member" "workload" {
  for_each = { for n, sa in local.s.service_accounts : n => sa if sa.type == "workload" && local.foundation.cluster_name != null }

  service_account_id = google_service_account.this[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project}.svc.id.goog[${each.value.namespace}/${each.value.ksa_name}]"
}

# ---------------------------------------------------------------- grants on components

# Firestore has no per-database IAM resource: the grant is on the project, limited to one
# database by an IAM condition. (All apps on the free "(default)" database share its data;
# a named database per app is what isolates them.)
resource "google_project_iam_member" "firestore" {
  for_each = local.by_type.firestore

  project = local.project
  role    = each.value.gcp_role
  member  = google_service_account.this[each.value.sa].member

  condition {
    title      = "firestore-${each.value.name}"
    expression = "resource.name == \"projects/${local.project}/databases/${local.components.firestore[each.value.name].database_id}\""
  }
}

# Same for Cloud SQL: project-level role, condition on the instance.
resource "google_project_iam_member" "cloudsql" {
  for_each = local.by_type.cloudsql

  project = local.project
  role    = each.value.gcp_role
  member  = google_service_account.this[each.value.sa].member

  condition {
    title      = "cloudsql-${each.value.name}"
    expression = "resource.name == \"projects/${local.project}/instances/${each.value.name}\""
  }
}

resource "google_secret_manager_secret_iam_member" "this" {
  for_each = local.by_type.secret

  secret_id = local.components.secrets[each.value.name]
  role      = each.value.gcp_role
  member    = google_service_account.this[each.value.sa].member
}

resource "google_pubsub_topic_iam_member" "this" {
  for_each = local.by_type.topic

  topic  = local.components.topics[each.value.name].id
  role   = each.value.gcp_role
  member = google_service_account.this[each.value.sa].member
}

resource "google_artifact_registry_repository_iam_member" "this" {
  for_each = local.by_type.registry

  location   = local.components.registries[each.value.name].location
  repository = local.components.registries[each.value.name].name
  role       = each.value.gcp_role
  member     = google_service_account.this[each.value.sa].member
}

# Deployers only need to find the cluster and get credentials; what they can do inside it is
# limited to their namespaces by Kubernetes RBAC (stacks/platform). One grant per account.
resource "google_project_iam_member" "cluster_viewer" {
  for_each = toset(distinct([for g in values(local.by_type.namespace) : g.sa]))

  project = local.project
  role    = "roles/container.clusterViewer"
  member  = google_service_account.this[each.key].member
}

resource "google_project_iam_member" "project_roles" {
  for_each = merge(local.by_type.dns, local.by_type.project)

  project = local.project
  role    = each.value.gcp_role
  member  = google_service_account.this[each.value.sa].member
}
