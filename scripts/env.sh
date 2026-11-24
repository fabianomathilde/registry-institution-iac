#!/usr/bin/env bash
# Start or stop the paid runtime of an environment, without Terraform and without losing data.
#
# Usage:
#   scripts/env.sh <dev|prod> stop     # every app scaled to 0 pods, every Cloud SQL instance stopped
#   scripts/env.sh <dev|prod> start    # Cloud SQL started, every app back to its previous size
#   scripts/env.sh <dev|prod> status
#
# Apps are found by the label the platform stack puts on the namespaces it manages
# (registry-institution.io/managed-namespace); Cloud SQL instances by the label managed-by=terraform. Before scaling a deployment to 0, its replica count is saved
# in an annotation, so start restores each app to the size it had.
#
# Why stop is enough:
#   - GKE Autopilot bills the CPU/memory pods request. 0 pods = no compute cost; the cluster fee is
#     covered by the GKE free tier (one Autopilot cluster per billing account).
#   - Cloud SQL with activation policy NEVER is shut down: you pay only its disk (and backups).
#   - Firestore, Pub/Sub, BigQuery and Secret Manager bill per use: idle means (almost) free.
#   - Nothing is deleted: data, secrets, images and the cluster stay; start takes ~1–3 min.
set -euo pipefail

ENV="${1:?env (dev|prod)}"
ACTION="${2:?action (start|stop|status)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/envs/${ENV}/project.yaml"
[[ -f "${CONFIG}" ]] || { echo "missing ${CONFIG}" >&2; exit 1; }

yaml_value() { sed -nE "s/^$1:[[:space:]]*\"?([a-z0-9-]+)\"?.*$/\\1/p" "${CONFIG}" | head -n1; }
PROJECT_ID="$(yaml_value project_id)"
REGION="$(yaml_value region)"; REGION="${REGION:-us-central1}"

# Names fixed in modules/settings and stacks/platform.
CLUSTER="registry-institution"
NAMESPACE_LABEL="registry-institution.io/managed-namespace"
REPLICAS_ANNOTATION="registry-institution.io/replicas-before-stop"

sql_instances() {
  gcloud sql instances list --project "${PROJECT_ID}" --filter="settings.userLabels.managed-by=terraform" \
    --format='value(name)' 2>/dev/null || true
}

cluster_creds() {
  gcloud container clusters get-credentials "${CLUSTER}" --region "${REGION}" --project "${PROJECT_ID}" >/dev/null 2>&1
}

app_namespaces() {
  kubectl get namespaces -l "${NAMESPACE_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

case "${ACTION}" in
  stop)
    if cluster_creds; then
      for ns in $(app_namespaces); do
        for deploy in $(kubectl -n "${ns}" get deployments -o name); do
          current="$(kubectl -n "${ns}" get "${deploy}" -o jsonpath='{.spec.replicas}')"
          if [[ "${current}" != "0" ]]; then
            kubectl -n "${ns}" annotate "${deploy}" --overwrite "${REPLICAS_ANNOTATION}=${current}" >/dev/null
          fi
          echo ">> ${ns}/${deploy#*/}: ${current} → 0"
          kubectl -n "${ns}" scale "${deploy}" --replicas=0 >/dev/null
        done
      done
    else
      echo ">> no cluster: nothing to scale"
    fi
    for sql in $(sql_instances); do
      echo ">> stopping Cloud SQL ${sql} (takes ~1 min)"
      gcloud sql instances patch "${sql}" --project "${PROJECT_ID}" --activation-policy=NEVER --quiet
    done
    ;;

  start)
    for sql in $(sql_instances); do
      echo ">> starting Cloud SQL ${sql} (takes ~1–3 min)"
      gcloud sql instances patch "${sql}" --project "${PROJECT_ID}" --activation-policy=ALWAYS --quiet
    done
    if cluster_creds; then
      for ns in $(app_namespaces); do
        for deploy in $(kubectl -n "${ns}" get deployments -o name); do
          saved="$(kubectl -n "${ns}" get "${deploy}" -o jsonpath="{.metadata.annotations.registry-institution\.io/replicas-before-stop}")"
          target="${saved:-1}"
          echo ">> ${ns}/${deploy#*/}: → ${target}"
          kubectl -n "${ns}" scale "${deploy}" --replicas="${target}" >/dev/null
        done
      done
      for ns in $(app_namespaces); do
        kubectl -n "${ns}" rollout status deployment --timeout=10m 2>/dev/null || true
      done
    else
      echo ">> no cluster"
    fi
    ;;

  status)
    echo "project:   ${PROJECT_ID} (${ENV})"
    instances="$(sql_instances)"
    if [[ -n "${instances}" ]]; then
      for sql in ${instances}; do
        gcloud sql instances describe "${sql}" --project "${PROJECT_ID}" \
          --format='value(name,settings.activationPolicy,state)' | awk '{print "cloud sql: " $1 " policy=" $2 " state=" $3}'
      done
    else
      echo "cloud sql: none"
    fi
    if cluster_creds; then
      for ns in $(app_namespaces); do
        kubectl -n "${ns}" get deployments \
          -o jsonpath='{range .items[*]}{"app:       "}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.status.readyReplicas}{"/"}{.spec.replicas}{" ready\n"}{end}'
      done
    else
      echo "gke:       cluster not found"
    fi
    ;;

  *)
    echo "unknown action ${ACTION} (start|stop|status)" >&2
    exit 1
    ;;
esac
