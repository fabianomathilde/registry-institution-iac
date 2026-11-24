#!/usr/bin/env bash
# One-time setup of a project before the first Terraform run (Terraform can't create the bucket
# that holds its own state).
#
# Usage:
#   scripts/bootstrap.sh <project-id> [region]
#
# Optional budget alert (strongly recommended on a credit/trial account):
#   BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX BUDGET_AMOUNT=50 scripts/bootstrap.sh <project-id>
#   (BUDGET_AMOUNT is in the billing account's currency: BRL for an account created in Brazil)
#   (find the id with: gcloud billing accounts list)
set -euo pipefail

PROJECT="${1:?usage: bootstrap.sh <project-id> [region]}"
REGION="${2:-us-central1}"
BUCKET="${PROJECT}-tfstate"

echo ">> Enabling bootstrap APIs on ${PROJECT}"
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  --project "${PROJECT}"

echo ">> State bucket gs://${BUCKET}"
if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${PROJECT}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "${PROJECT}" \
    --location "${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi
gcloud storage buckets update "gs://${BUCKET}" --versioning

if [[ -n "${BILLING_ACCOUNT:-}" ]]; then
  AMOUNT="${BUDGET_AMOUNT:-50}"
  # The budget must use the billing account's own currency (e.g. BRL for an account created in
  # Brazil); any other currency is rejected with INVALID_ARGUMENT.
  CURRENCY="$(gcloud billing accounts describe "${BILLING_ACCOUNT}" --format='value(currencyCode)')"
  CURRENCY="${CURRENCY:-USD}"
  echo ">> Budget alert of ${AMOUNT} ${CURRENCY} on billing account ${BILLING_ACCOUNT}"
  gcloud services enable billingbudgets.googleapis.com --project "${PROJECT}"
  if gcloud billing budgets list --billing-account="${BILLING_ACCOUNT}" \
       --filter="displayName='${PROJECT} budget'" --format='value(name)' | grep -q .; then
    echo ">> Budget '${PROJECT} budget' already exists"
  else
    gcloud billing budgets create \
      --billing-account="${BILLING_ACCOUNT}" \
      --display-name="${PROJECT} budget" \
      --budget-amount="${AMOUNT}${CURRENCY}" \
      --filter-projects="projects/${PROJECT}" \
      --threshold-rule=percent=0.5 \
      --threshold-rule=percent=0.9 \
      --threshold-rule=percent=1.0
  fi
fi

echo ">> Done. Next: scripts/tf.sh <env> foundation plan"
