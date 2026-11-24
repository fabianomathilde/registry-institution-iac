# Components: the things apps use. One block per YAML file; nothing here knows about identities.
#   databases.yaml  -> Firestore databases, Cloud SQL instances (+ databases, users, password secrets),
#                      Spanner trial
#   messages.yaml   -> BigQuery dataset, Pub/Sub topics (optionally streamed into BigQuery)
#   secrets.yaml    -> Secret Manager secrets
#   registries.yaml -> Artifact Registry repositories
#
# Who can use each component is decided only in service_accounts.yaml (stacks/identities).
# The one exception is registries.yaml external_readers: principals of ANOTHER project
# (e.g. prod's CI reading dev images) that can't be described as service accounts of this one.

locals {
  allow_destroy_data = !local.s.project.deletion_protection
}

# ---------------------------------------------------------------- databases.yaml: Firestore

module "firestore" {
  source   = "../../modules/firestore"
  for_each = local.s.firestore

  project_id          = local.project
  database_id         = each.value.database_id
  location            = each.value.location
  indexes             = each.value.indexes
  deletion_protection = local.s.project.deletion_protection
}

# ---------------------------------------------------------------- databases.yaml: Cloud SQL

module "cloudsql" {
  source   = "../../modules/cloudsql-postgres"
  for_each = local.s.cloudsql

  project_id             = local.project
  region                 = local.region
  name                   = each.key
  network_id             = data.terraform_remote_state.foundation.outputs.network_id
  database_version       = each.value.database_version
  tier                   = each.value.tier
  availability_type      = each.value.availability_type
  activation_policy      = each.value.activation_policy
  point_in_time_recovery = each.value.point_in_time_recovery
  deletion_protection    = local.s.project.deletion_protection
  labels                 = local.s.labels
}

locals {
  # One database + one user with the same name per entry of cloudsql.<instance>.databases.
  sql_databases = merge([
    for instance, sql in local.s.cloudsql : {
      for db in sql.databases : "${instance}/${db}" => {
        instance = instance
        database = db
        secret   = "cloudsql-${instance}-${db}-password"
      }
    }
  ]...)
}

resource "google_sql_database" "this" {
  for_each = local.sql_databases

  instance = module.cloudsql[each.value.instance].instance_name
  name     = each.value.database
}

resource "random_password" "sql" {
  for_each = local.sql_databases

  length  = 32
  special = false
}

resource "google_sql_user" "this" {
  for_each = local.sql_databases

  instance = module.cloudsql[each.value.instance].instance_name
  name     = each.value.database
  password = random_password.sql[each.key].result
}

resource "google_secret_manager_secret" "sql" {
  for_each = local.sql_databases

  secret_id = each.value.secret
  labels    = merge(local.s.labels, { cloudsql-instance = each.value.instance })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "sql" {
  for_each = local.sql_databases

  secret      = google_secret_manager_secret.sql[each.key].id
  secret_data = random_password.sql[each.key].result
}

# ---------------------------------------------------------------- databases.yaml: Spanner

module "spanner_trial" {
  count  = local.s.spanner_trial ? 1 : 0
  source = "../../modules/spanner-trial"

  project_id = local.project
  region     = local.region
  labels     = local.s.labels
}

# ---------------------------------------------------------------- messages.yaml

resource "google_bigquery_dataset" "events" {
  count = anytrue([for t in values(local.s.topics) : t.bigquery]) ? 1 : 0

  dataset_id                 = local.s.bigquery.dataset
  location                   = local.s.bigquery.location
  delete_contents_on_destroy = local.allow_destroy_data
  labels                     = local.s.labels
}

# The Pub/Sub service agent writes BigQuery subscriptions into the dataset.
resource "google_bigquery_dataset_iam_member" "pubsub_writer" {
  count = anytrue([for t in values(local.s.topics) : t.bigquery]) ? 1 : 0

  dataset_id = google_bigquery_dataset.events[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.terraform_remote_state.foundation.outputs.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

module "topics" {
  source   = "../../modules/eventing"
  for_each = local.s.topics

  project_id         = local.project
  topic_name         = each.key
  bigquery           = each.value.bigquery
  dataset_id         = local.s.bigquery.dataset
  table_id           = each.value.table_id
  allow_destroy_data = local.allow_destroy_data
  labels             = local.s.labels

  depends_on = [google_bigquery_dataset_iam_member.pubsub_writer, google_bigquery_dataset.events]
}

# ---------------------------------------------------------------- secrets.yaml

resource "google_secret_manager_secret" "this" {
  for_each = local.s.secrets

  secret_id = each.key
  labels    = local.s.labels

  replication {
    auto {}
  }
}

resource "random_password" "secret" {
  for_each = { for name, s in local.s.secrets : name => s if s.generate }

  length  = 32
  special = false
}

# generate: false -> the secret is created empty; add the value outside Terraform:
#   printf '%s' 'the-value' | gcloud secrets versions add <name> --data-file=-
resource "google_secret_manager_secret_version" "this" {
  for_each = random_password.secret

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = each.value.result
}

# ---------------------------------------------------------------- registries.yaml

module "registry" {
  source   = "../../modules/artifact-registry"
  for_each = local.s.registries

  project_id     = local.project
  region         = local.region
  repository_id  = each.key
  immutable_tags = each.value.immutable_tags
  keep_count     = each.value.keep_count
  labels         = local.s.labels
}

resource "google_artifact_registry_repository_iam_member" "external_reader" {
  for_each = merge([
    for name, r in local.s.registries : {
      for m in r.external_readers : "${name}|${m}" => { registry = name, member = m }
    }
  ]...)

  location   = module.registry[each.value.registry].location
  repository = module.registry[each.value.registry].name
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}
