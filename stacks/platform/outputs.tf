output "namespaces" {
  value = keys(kubernetes_namespace_v1.this)
}

output "kubernetes_service_accounts" {
  description = "namespace/KSA -> Google service account it acts as."
  value       = { for k, sa in kubernetes_service_account_v1.this : "${sa.metadata[0].namespace}/${sa.metadata[0].name}" => sa.metadata[0].annotations["iam.gke.io/gcp-service-account"] }
}

output "deployers" {
  value = local.identities.namespace_deployers
}
