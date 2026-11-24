# Platform: what lives inside the cluster and belongs to the organization, not to an app.
#   kubernetes.yaml       -> namespaces with resource quotas
#   service_accounts.yaml -> Kubernetes service accounts (type: workload), annotated with their GSA,
#                            and namespace deployers (namespace/<ns>: deployer) as RBAC
#   network.yaml          -> ExternalDNS, when a domain is set
#
# App repositories deploy only Deployments, Services, Ingresses... into their namespace, using
# serviceAccountName: sa-<name>. They never create namespaces, service accounts or RBAC.

locals {
  cluster    = data.terraform_remote_state.foundation.outputs.cluster
  identities = data.terraform_remote_state.identities.outputs
}

resource "terraform_data" "requires_cluster" {
  lifecycle {
    precondition {
      condition     = local.cluster != null
      error_message = "kubernetes.yaml has cluster.enabled: false: there is nothing to apply in the platform stack."
    }
  }
}

data "google_client_config" "this" {}

provider "kubernetes" {
  host                   = local.cluster == null ? null : "https://${local.cluster.endpoint}"
  token                  = data.google_client_config.this.access_token
  cluster_ca_certificate = local.cluster == null ? null : base64decode(local.cluster.ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster == null ? null : "https://${local.cluster.endpoint}"
    token                  = data.google_client_config.this.access_token
    cluster_ca_certificate = local.cluster == null ? null : base64decode(local.cluster.ca_certificate)
  }
}

# ---------------------------------------------------------------- namespaces

resource "kubernetes_namespace_v1" "this" {
  for_each = local.s.namespaces

  metadata {
    name = each.key
    labels = {
      "registry-institution.io/managed-namespace" = "true"
      "app.kubernetes.io/managed-by"              = "terraform"
    }
  }
}

resource "kubernetes_resource_quota_v1" "this" {
  for_each = local.s.namespaces

  metadata {
    name      = "quota"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.quota_cpu
      "requests.memory" = each.value.quota_memory
      "limits.cpu"      = each.value.quota_cpu
      "limits.memory"   = each.value.quota_memory
    }
  }
}

# ---------------------------------------------------------------- Kubernetes service accounts

resource "kubernetes_service_account_v1" "this" {
  for_each = local.identities.ksa

  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace_v1.this[each.value.namespace].metadata[0].name
    annotations = {
      # Workload Identity: pods using this KSA get tokens of this Google service account.
      "iam.gke.io/gcp-service-account" = each.value.gsa_email
    }
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ---------------------------------------------------------------- deployers (RBAC)

# What a CI deployer can do inside its namespace: manage the app's workload objects.
# Not allowed: namespaces, service accounts, roles, quotas, anything cluster-wide.
resource "kubernetes_role_v1" "app_deployer" {
  for_each = local.identities.namespace_deployers

  metadata {
    name      = "app-deployer"
    namespace = kubernetes_namespace_v1.this[each.key].metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "batch", "autoscaling", "policy", "networking.k8s.io"]
    resources = [
      "configmaps", "services", "pods", "pods/log", "events",
      "deployments", "replicasets", "statefulsets", "jobs", "cronjobs",
      "horizontalpodautoscalers", "poddisruptionbudgets", "ingresses",
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["get", "list"]
  }

  # GKE Ingress extras and the Secret Manager CSI mapping used by the app manifests.
  rule {
    api_groups = ["networking.gke.io", "cloud.google.com", "secrets-store.csi.x-k8s.io"]
    resources  = ["managedcertificates", "backendconfigs", "frontendconfigs", "secretproviderclasses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "app_deployer" {
  for_each = local.identities.namespace_deployers

  metadata {
    name      = "app-deployer"
    namespace = kubernetes_role_v1.app_deployer[each.key].metadata[0].namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app_deployer[each.key].metadata[0].name
  }

  # On GKE a Google service account authenticates as a User named by its email.
  dynamic "subject" {
    for_each = each.value
    content {
      kind      = "User"
      name      = subject.value
      api_group = "rbac.authorization.k8s.io"
    }
  }
}

# ---------------------------------------------------------------- ExternalDNS

resource "helm_release" "external_dns" {
  count = local.s.network.domain != "" ? 1 : 0

  name       = "external-dns"
  namespace  = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = local.s.network.external_dns_chart_version

  values = [yamlencode({
    provider      = { name = "google" }
    domainFilters = [local.s.network.domain]
    txtOwnerId    = "registry-institution-${local.s.project.environment}"
    policy        = "sync"
    sources       = ["ingress", "service"]
    extraArgs     = ["--google-project=${local.project}"]
    serviceAccount = {
      create = false
      name   = local.identities.ksa["external-dns"].name
    }
  })]

  depends_on = [kubernetes_service_account_v1.this]

  lifecycle {
    precondition {
      condition     = contains(keys(local.s.namespaces), "external-dns") && try(local.identities.ksa["external-dns"].namespace, "") == "external-dns"
      error_message = "dns.domain is set: add the external-dns namespace (kubernetes.yaml) and the external-dns workload service account in namespace external-dns with access dns: admin (service_accounts.yaml)."
    }
  }
}
