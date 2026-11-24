#!/usr/bin/env bash
# Runs Terraform for one stack of one environment, locally or in CI.
#
# Usage:
#   scripts/tf.sh <dev|prod> <stack> <plan|apply|destroy|output|import|state|force-unlock> [extra terraform args]
#
# Stacks, in apply order (each one reads the outputs of the previous ones):
#   foundation  APIs, GitHub WIF, network, GKE, DNS zone
#   components  Firestore, Cloud SQL, Pub/Sub + BigQuery, secrets, registries
#   identities  service accounts and every IAM grant (service_accounts.yaml)
#   platform    namespaces, Kubernetes service accounts, deployer RBAC, ExternalDNS
#
# Examples:
#   scripts/tf.sh dev foundation plan
#   scripts/tf.sh dev components apply
#   scripts/tf.sh dev identities output access_matrix
#
# Settings come from envs/<env>/*.yaml. Terraform backends can't read variables or YAML,
# so this script derives the backend (bucket "<project_id>-tfstate", prefix "<stack>") from
# project_id in envs/<env>/project.yaml and passes it to terraform init.
#
# CI sets TF_AUTO_APPROVE=1: apply then uses the plan saved by the previous "plan" call.
set -euo pipefail

ENV="${1:?env (dev|prod)}"
STACK="${2:?stack (foundation|components|identities|platform)}"
ACTION="${3:-plan}"
shift $(( $# >= 3 ? 3 : $# ))

USAGE="usage: scripts/tf.sh <dev|prod> <foundation|components|identities|platform> <plan|apply|destroy|output|import|state|force-unlock> [args]"
[[ -d "$(dirname "$0")/../envs/${ENV}" ]] || { echo "unknown environment '${ENV}'" >&2; echo "${USAGE}" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="${ROOT}/envs/${ENV}"
CONFIG="${ENV_DIR}/project.yaml"
[[ -f "${CONFIG}" ]] || { echo "missing ${CONFIG}" >&2; exit 1; }
[[ -d "${ROOT}/stacks/${STACK}" ]] || { echo "unknown stack '${STACK}'" >&2; echo "${USAGE}" >&2; exit 1; }

# project_id: <value>   (optional quotes, optional trailing comment)
PROJECT_ID="$(sed -nE 's/^project_id:[[:space:]]*"?([a-z0-9-]+)"?.*$/\1/p' "${CONFIG}" | head -n1)"
[[ -n "${PROJECT_ID}" ]] || { echo "project_id not found in ${CONFIG}" >&2; exit 1; }

cd "${ROOT}/stacks/${STACK}"
terraform init -input=false -reconfigure \
  -backend-config="bucket=${PROJECT_ID}-tfstate" \
  -backend-config="prefix=${STACK}" >/dev/null

VARS=(-var="env_dir=${ENV_DIR}")

case "${ACTION}" in
  plan)
    terraform plan -input=false -lock-timeout=5m "${VARS[@]}" -out=tfplan "$@"
    ;;
  apply)
    if [[ -n "${TF_AUTO_APPROVE:-}" && -f tfplan ]]; then
      terraform apply -input=false -lock-timeout=5m tfplan
    else
      terraform apply -input=false -lock-timeout=5m "${VARS[@]}" "$@"
    fi
    ;;
  destroy)
    terraform destroy -input=false -lock-timeout=5m "${VARS[@]}" "$@"
    ;;
  output)
    terraform output "$@"
    ;;
  import)
    # Adopt a resource created outside Terraform: import <address> <id>
    terraform import -input=false -lock-timeout=5m "${VARS[@]}" "$@"
    ;;
  state)
    # Inspect or fix state: state list | state show <address> | state rm <address>
    terraform state "$@"
    ;;
  force-unlock)
    # Release a lock left by a killed run: force-unlock <LOCK_ID>
    terraform force-unlock "$@"
    ;;
  *)
    echo "unknown action ${ACTION}" >&2
    exit 1
    ;;
esac
