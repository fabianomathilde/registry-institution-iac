# Reads the YAML files of one environment (envs/<env>/*.yaml), applies defaults and validates them,
# including references between files (an access to "firestore/x" needs x in databases.yaml).
# Every stack uses this module, so all of them see exactly the same settings.
#
# Empty files or empty sections (a key with nothing after it) mean "none".

variable "env_dir" {
  description = "Folder with the environment's YAML files, e.g. ../../envs/dev"
  type        = string
}

locals {
  yaml = {
    for f in ["project", "network", "kubernetes", "databases", "messages", "secrets", "registries", "service_accounts"] :
    f => fileexists("${var.env_dir}/${f}.yaml") ? yamldecode(file("${var.env_dir}/${f}.yaml")) : null
  }

  # ---------- project.yaml ----------
  project = {
    project_id          = local.yaml.project.project_id
    environment         = local.yaml.project.environment
    region              = try(local.yaml.project.region, "us-central1")
    github_owner        = local.yaml.project.github.owner
    iac_repo            = try(local.yaml.project.github.iac_repo, "registry-institution-iac")
    deletion_protection = try(local.yaml.project.deletion_protection, true)
  }

  labels = {
    system      = "registry-institution"
    environment = local.project.environment
    managed-by  = "terraform"
  }

  # ---------- network.yaml ----------
  network = {
    subnet_cidr                = local.yaml.network.vpc.subnet_cidr
    pods_cidr                  = local.yaml.network.vpc.pods_cidr
    services_cidr              = local.yaml.network.vpc.services_cidr
    nat_enabled                = try(local.yaml.network.nat.enabled, false)
    ingress_enabled            = try(local.yaml.network.ingress.enabled, false)
    domain                     = try(coalesce(local.yaml.network.dns.domain, ""), "")
    external_dns_chart_version = try(tostring(local.yaml.network.dns.external_dns_chart_version), "1.23.0")
  }

  ingress_ips = try({ for name, v in local.yaml.network.ingress.ips : name => "${name}-ingress-ip" }, {})

  # ---------- kubernetes.yaml ----------
  cluster = {
    name            = "registry-institution"
    enabled         = try(local.yaml.kubernetes.cluster.enabled, true)
    release_channel = try(local.yaml.kubernetes.cluster.release_channel, "REGULAR")
  }

  namespaces = try({
    for name, ns in local.yaml.kubernetes.namespaces : name => {
      quota_cpu    = try(tostring(ns.quota.cpu), "2")
      quota_memory = try(tostring(ns.quota.memory), "4Gi")
    }
  }, {})

  # ---------- databases.yaml ----------
  firestore = try({
    for name, db in local.yaml.databases.firestore : name => {
      database_id = name == "default" ? "(default)" : name
      location    = try(db.location, local.project.region)
      indexes = try([
        for idx in db.indexes : {
          collection = idx.collection
          fields     = [for f in idx.fields : tostring(f)]
        }
      ], [])
    }
  }, {})

  cloudsql = try({
    for name, sql in local.yaml.databases.cloudsql : name => {
      tier                   = try(sql.tier, "db-f1-micro")
      availability_type      = try(sql.availability_type, "ZONAL")
      activation_policy      = try(sql.activation_policy, "ALWAYS")
      point_in_time_recovery = try(sql.point_in_time_recovery, false)
      database_version       = try(sql.database_version, "POSTGRES_17")
      databases              = try([for d in sql.databases : tostring(d)], [])
    }
  }, {})

  # Password secret generated for each Cloud SQL database (user = database name).
  cloudsql_secrets = flatten([
    for instance, sql in local.cloudsql : [for db in sql.databases : "cloudsql-${instance}-${db}-password"]
  ])

  spanner_trial = try(local.yaml.databases.spanner.trial, false)

  # ---------- messages.yaml ----------
  bigquery = {
    dataset  = try(local.yaml.messages.bigquery.dataset, "events")
    location = try(local.yaml.messages.bigquery.location, "US")
  }

  topics = try({
    for name, t in local.yaml.messages.topics : name => {
      bigquery = try(t.bigquery, false)
      table_id = replace(name, "-", "_")
    }
  }, {})

  # ---------- secrets.yaml ----------
  secrets = try({ for name, s in local.yaml.secrets : name => { generate = try(s.generate, true) } }, {})

  # ---------- registries.yaml ----------
  registries = try({
    for name, r in local.yaml.registries : name => {
      immutable_tags   = try(r.immutable_tags, true)
      keep_count       = try(r.keep_count, 20)
      external_readers = try([for m in r.external_readers : tostring(m)], [])
    }
  }, {})

  # ---------- service_accounts.yaml ----------
  service_accounts = try({
    for name, sa in local.yaml.service_accounts : name => {
      type       = try(sa.type, "workload")
      account_id = try(sa.account_id, "sa-${name}")
      repo       = try(sa.repo, null)
      namespace  = try(sa.namespace, null)
      ksa_name   = try(sa.ksa_name, "sa-${name}")
      access     = try({ for ref, role in sa.access : ref => tostring(role) }, {})
    }
  }, {})

  # One entry per (service account, component) pair.
  grants = flatten([
    for sa_name, sa in local.service_accounts : [
      for ref, role in sa.access : {
        key  = "${sa_name}|${ref}"
        sa   = sa_name
        ref  = ref
        type = split("/", ref)[0]
        name = length(split("/", ref)) > 1 ? split("/", ref)[1] : ""
        role = role
      }
    ]
  ])

  # ---------- Validation ----------
  valid_roles = {
    firestore = ["reader", "writer"]
    cloudsql  = ["client"]
    secret    = ["reader"]
    topic     = ["publisher", "subscriber", "viewer"]
    registry  = ["reader", "writer"]
    namespace = ["deployer"]
    dns       = ["admin"]
    project   = ["viewer", "editor", "owner"]
  }

  # Component types that need a name, and the names defined in their files.
  catalogs = {
    firestore = keys(local.firestore)
    cloudsql  = keys(local.cloudsql)
    secret    = concat(keys(local.secrets), local.cloudsql_secrets)
    topic     = keys(local.topics)
    registry  = keys(local.registries)
    namespace = keys(local.namespaces)
  }

  errors = concat(
    contains(["dev", "prod"], local.project.environment) ? [] : ["project.yaml: environment must be dev or prod"],
    local.project.github_owner != "CHANGE-ME" ? [] : ["project.yaml: set github.owner"],
    local.network.domain == "" || local.network.nat_enabled ? [] : ["network.yaml: dns.domain needs nat.enabled: true"],
    local.network.domain == "" || contains(keys(local.service_accounts), "external-dns") ? [] : ["network.yaml: dns.domain needs the external-dns service account (service_accounts.yaml)"],
    [for n, sql in local.cloudsql : "databases.yaml: cloudsql ${n}: availability_type must be ZONAL or REGIONAL" if !contains(["ZONAL", "REGIONAL"], sql.availability_type)],
    [for n, sql in local.cloudsql : "databases.yaml: cloudsql ${n}: activation_policy must be ALWAYS or NEVER" if !contains(["ALWAYS", "NEVER"], sql.activation_policy)],
    [for n in keys(local.secrets) : "secrets.yaml: ${n}: names starting with cloudsql- are reserved for generated Cloud SQL passwords" if startswith(n, "cloudsql-")],
    [for n, sa in local.service_accounts : "service_accounts.yaml: ${n}: name must be 3-27 chars, lowercase letters, digits, dashes" if !can(regex("^[a-z][a-z0-9-]{1,25}[a-z0-9]$", n))],
    [for n, sa in local.service_accounts : "service_accounts.yaml: ${n}: type must be workload or github" if !contains(["workload", "github"], sa.type)],
    [for n, sa in local.service_accounts : "service_accounts.yaml: ${n}: type github needs repo" if sa.type == "github" && sa.repo == null],
    [for n, sa in local.service_accounts : "service_accounts.yaml: ${n}: namespace '${coalesce(sa.namespace, "(none)")}' is not in kubernetes.yaml" if sa.type == "workload" && !contains(keys(local.namespaces), coalesce(sa.namespace, "-"))],
    [for g in local.grants : "service_accounts.yaml: ${g.sa}: unknown component type in '${g.ref}'" if !contains(keys(local.valid_roles), g.type)],
    [for g in local.grants : "service_accounts.yaml: ${g.sa}: role '${g.role}' is not valid for ${g.type} (valid: ${join(", ", try(local.valid_roles[g.type], []))})" if contains(keys(local.valid_roles), g.type) && !contains(try(local.valid_roles[g.type], []), g.role)],
    [for g in local.grants : "service_accounts.yaml: ${g.sa}: '${g.ref}' is not defined in its YAML file" if contains(keys(local.catalogs), g.type) && !contains(try(local.catalogs[g.type], []), g.name)],
  )
}

resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = length(local.errors) == 0
      error_message = "Invalid settings in ${var.env_dir}:\n  - ${join("\n  - ", local.errors)}"
    }
  }
}

output "project" {
  value = local.project
}

output "labels" {
  value = local.labels
}

output "network" {
  value = local.network
}

output "ingress_ips" {
  value = local.ingress_ips
}

output "cluster" {
  value = local.cluster
}

output "namespaces" {
  value = local.namespaces
}

output "firestore" {
  value = local.firestore
}

output "cloudsql" {
  value = local.cloudsql
}

output "spanner_trial" {
  value = local.spanner_trial
}

output "bigquery" {
  value = local.bigquery
}

output "topics" {
  value = local.topics
}

output "secrets" {
  value = local.secrets
}

output "registries" {
  value = local.registries
}

output "service_accounts" {
  value = local.service_accounts
}

output "grants" {
  value = local.grants
}
