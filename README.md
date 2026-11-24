# registry-institution-iac

Terraform for the **registry-institution** organization on Google Cloud. One repository describes,
per environment, every component (databases, topics, secrets, registries, cluster) and every
identity that can use them. Application repositories create nothing in GCP: they only use the
service accounts this repository gives them.

| Environment | GCP project | Branch (gitflow) | Applied |
|---|---|---|---|
| dev | `registry-institution-dev` | `develop` | automatically on every merge |
| prod | `registry-institution-prd` | `main` | after manual approval |

`optin-backend` is the first application.

## The settings: eight YAML files per environment

```
envs/dev/
  project.yaml           project id, region, GitHub owner, deletion protection
  network.yaml           VPC ranges, NAT, static ingress IPs, DNS domain
  kubernetes.yaml        GKE cluster, namespaces and their quotas
  databases.yaml         Firestore databases (+ indexes), Cloud SQL instances, Spanner trial
  messages.yaml          Pub/Sub topics, BigQuery dataset for streamed topics
  secrets.yaml           Secret Manager secrets
  registries.yaml        Artifact Registry repositories
  service_accounts.yaml  EVERY identity and EVERYTHING it can access
```

The first seven files say **what exists**. `service_accounts.yaml` says **who can use what**, and
it is the only place where permissions are granted:

```yaml
optin-backend-ci:                        # GSA sa-optin-backend-ci
  type: github                           # used by GitHub Actions of fabianomathilde/optin-backend
  repo: optin-backend
  access:
    registry/optin-backend: writer       # push images
    namespace/optin-backend: deployer    # deploy into that namespace only

optin-backend:                           # GSA sa-optin-backend + KSA sa-optin-backend
  type: workload                         # used by pods in namespace optin-backend
  namespace: optin-backend
  access:
    firestore/default: writer
    secret/optin-backend-api-password: reader
    topic/optin-backend-events: publisher
```

Access vocabulary (anything else fails the plan with a clear message):

| Reference | Roles | Google role | Scope |
|---|---|---|---|
| `firestore/<key>` | `reader`, `writer` | `datastore.viewer`, `datastore.user` | IAM condition on that database |
| `cloudsql/<instance>` | `client` | `cloudsql.client` | IAM condition on that instance |
| `secret/<name>` | `reader` | `secretmanager.secretAccessor` | the secret |
| `topic/<name>` | `publisher`, `subscriber`, `viewer` | `pubsub.*` | the topic |
| `registry/<name>` | `reader`, `writer` | `artifactregistry.*` | the repository |
| `namespace/<name>` | `deployer` | `container.clusterViewer` + Role `app-deployer` | that namespace |
| `dns` | `admin` | `dns.admin` | project |
| `project` | `viewer`, `editor`, `owner` | basic roles | project |

To review every identity and its roles in one place after an apply:

```bash
./scripts/tf.sh dev identities output access_matrix
```

All files are block-style YAML (no `{...}` or `[...]`); CI enforces it with `yamllint`
(`.yamllint.yaml`). The YAML is read with `yamldecode` by `modules/settings`, which also applies
defaults and validates cross-file references (e.g. `firestore/payments` must exist in
`databases.yaml`, a workload's namespace must exist in `kubernetes.yaml`).

## Stacks

```
                GitHub Actions ──OIDC──► WIF pool "github" (owner fabianomathilde only)
       registry-institution-iac → sa-terraform-ci       optin-backend → sa-optin-backend-ci

 Your Mac ── kubectl port-forward ──┐                     (public LB + DNS: optional, off)
           ┌────────────────────────▼─────────────────────────────────────────────────┐
           │ VPC registry-institution (Private Google Access, no NAT)                  │
           │  GKE Autopilot (private nodes)                                            │
           │   ns optin-backend (quota; only sa-optin-backend-ci may deploy)           │
           │     pod ── KSA sa-optin-backend ═ GSA sa-optin-backend ──► Firestore (default)
           │                                     ├─► secret optin-backend-api-password │
           │                                     └─► topic optin-backend-events ─► BigQuery events
           │   ns <next-app> ...                                                       │
           └───────────────────────────────────────────────────────────────────────────┘
```

| Stack | Creates | Reads |
|---|---|---|
| `foundation` | APIs, WIF pool + provider, VPC (+ NAT, + PSA when Cloud SQL exists), GKE, static ingress IPs, DNS zone | project, network, kubernetes, databases (Cloud SQL presence) |
| `components` | Firestore databases + indexes, Cloud SQL instances + one database/user/password secret per listed database, Spanner trial, BigQuery dataset, topics, secrets, registries | databases, messages, secrets, registries |
| `identities` | every GSA, their WIF / Workload Identity bindings, every IAM grant | service_accounts (+ components' outputs) |
| `platform` | namespaces + quotas, KSAs annotated with their GSA, `app-deployer` Role/RoleBinding, ExternalDNS | kubernetes, network, identities' outputs |

Each stack has its own state (`gs://<project_id>-tfstate/<stack>`), so a mistake in one can't
destroy another, and IAM changes show up alone in their plan.
Apply order: **foundation → components → identities → platform**.
Decisions: [docs/adr/0001-components-and-identities.md](docs/adr/0001-components-and-identities.md).

## Layout

```
envs/{dev,prod}/*.yaml        settings (above)
modules/
  settings/                   YAML loader, defaults, validation (used by every stack)
  project-apis  network  gke-autopilot  dns-zone  github-wif
  firestore  cloudsql-postgres  spanner-trial  eventing  artifact-registry
stacks/
  foundation/  components/  identities/  platform/
scripts/
  bootstrap.sh   one-time: base APIs + state bucket (+ budget alert)
  tf.sh          scripts/tf.sh <env> <stack> <plan|apply|destroy|output>
  env.sh         start | stop | status: every app and every Cloud SQL instance
.github/workflows/
  ci.yaml        fmt, validate, yamllint on every push; plan of the 4 stacks on PRs
  cd.yaml        apply: develop → dev, main → prod (with approval)
```

## Common changes

**A new app** (e.g. `agenda-service`): one entry in each file it needs, in one PR.

1. `kubernetes.yaml`: namespace `agenda-service` with its quota.
2. `registries.yaml`: registry `agenda-service`. `secrets.yaml` / `messages.yaml`: what it uses.
3. `service_accounts.yaml`: `agenda-service-ci` (type github, `registry/…: writer`,
   `namespace/…: deployer`) and `agenda-service` (type workload, its runtime access).
4. Merge into `develop`, then give the app repo its GitHub Environment variables:
   `./scripts/tf.sh dev identities output -json github_variables | jq '."agenda-service-ci"'`
5. The app's manifests use namespace `agenda-service` and `serviceAccountName: sa-agenda-service`.
   They must not contain a Namespace, ServiceAccount, Role or ResourceQuota (the deployer can't
   create them anyway).

**A paid Firestore database** (isolates an app's data):

```yaml
# databases.yaml
firestore:
  payments:                     # named database "payments", billed per use
    location: us-central1
# service_accounts.yaml
payments-api:
  access:
    firestore/payments: writer  # this database only
```

**A Cloud SQL instance** (billed from creation; foundation then also creates the PSA peering):

```yaml
# databases.yaml
cloudsql:
  shared-pg:
    tier: db-f1-micro
    databases:
      - optin_backend           # database + user optin_backend, secret cloudsql-shared-pg-optin_backend-password
# service_accounts.yaml
optin-backend:
  access:
    cloudsql/shared-pg: client
    secret/cloudsql-shared-pg-optin_backend-password: reader
```

**Removing access**: delete the line in `service_accounts.yaml`. The plan of `identities` shows
exactly which grant disappears.

## Prerequisites (on your Mac)

```bash
brew install terraform kubectl jq yamllint
brew install --cask google-cloud-sdk
gcloud components install gke-gcloud-auth-plugin
```

## First-time setup of dev

**1. Project and billing.** Check the project id (`gcloud projects list`). If it isn't exactly
`registry-institution-dev`, change `project_id` in `envs/dev/project.yaml`.

**2. Log in** (your user is the identity of the first apply)

```bash
gcloud auth login
gcloud auth application-default login
```

**3. Bootstrap** (state bucket, base APIs, budget alert)

```bash
BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX BUDGET_AMOUNT=50 \
  ./scripts/bootstrap.sh registry-institution-dev us-central1
```

**4. Review the eight files** in `envs/dev/` (at least `project.yaml` `github.owner`).

**5. First apply from your machine, in order.** `sa-terraform-ci`, the identity of the pipeline,
is created by the identities stack, so the pipeline can only take over after this.

```bash
./scripts/tf.sh dev foundation plan
./scripts/tf.sh dev foundation apply   # ~15 min: GKE is the slow part
./scripts/tf.sh dev components plan
./scripts/tf.sh dev components apply   # Firestore (default) + indexes, topic + BigQuery, secret, registry
./scripts/tf.sh dev identities plan
./scripts/tf.sh dev identities apply   # sa-terraform-ci, sa-optin-backend-ci, sa-optin-backend + grants
./scripts/tf.sh dev platform plan
./scripts/tf.sh dev platform apply     # namespace, quota, KSA sa-optin-backend, deployer RBAC
./scripts/tf.sh dev identities output access_matrix
```

Commit the generated `stacks/*/.terraform.lock.hcl` files.

**6. GitHub.** Branches `main` and `develop`, both protected (PR required; `ci / validate` and
`ci / plan` required). Environments:

| Repo | Environment | Protection | Variables |
|---|---|---|---|
| IaC | `dev` | none | `./scripts/tf.sh dev identities output github_variables_iac_repo` |
| IaC | `prod-plan` | none (plans PRs into `main`) | same values as `prod` |
| IaC | `prod` | Required reviewers · branch `main` | `./scripts/tf.sh prod identities output github_variables_iac_repo` |
| app | `dev` / `prod` | prod: reviewers · branch `main` | `./scripts/tf.sh <env> identities output -json github_variables \| jq '."<app>-ci"'` |

## How IaC changes are applied (no Atlantis)

```
feature/x ──PR──► develop ──merge──► cd: apply dev (foundation → components → identities → platform)
                     │
               release/x ──PR──► main ──merge──► cd: plan prod ─► approval ─► apply prod
```

1. Branch from `develop`, change YAML or HCL, push: `ci` runs fmt, validate and yamllint.
2. PR into `develop`: `ci` writes the **dev plan** of the four stacks in the checks summary.
3. Merge: `cd` applies dev, stack by stack.
4. PR into `main`: `ci` shows the **prod plan**. Merge: `cd` waits for approval, then applies.

PR plans run each stack against the *current* state of the previous ones. When one PR adds a
component and the access to it, the identities plan fails with an "invalid index" error until components
is applied: apply in two PRs (component first), or apply locally in order.

## Reaching an app

No public IP by default:

```bash
gcloud container clusters get-credentials registry-institution --region us-central1 --project registry-institution-dev
kubectl -n optin-backend port-forward svc/optin-backend 8080:80
curl http://localhost:8080/actuator/health
```

Later, public access: `network.yaml` `ingress.enabled: true` and an entry under `ingress.ips`
(→ static IP `<app>-ingress-ip`). A hostname + HTTPS also needs `nat.enabled: true`, `dns.domain`,
the `external-dns` namespace and the `external-dns` workload account with `dns: admin`
(commented examples are in the files); delegate the domain to the `dns_zone` output of foundation.

## Starting and stopping (saving credit)

```bash
./scripts/env.sh dev stop      # every app → 0 pods (size remembered), every Cloud SQL instance off
./scripts/env.sh dev start
./scripts/env.sh dev status
```

| Component | Running | Stopped |
|---|---|---|
| GKE Autopilot pods | ~$11/month per small app | $0 |
| GKE cluster fee | free tier (one Autopilot cluster per billing account) | free tier |
| Firestore `(default)`, Pub/Sub, BigQuery, Secret Manager | free tier at this volume | free tier |
| Cloud SQL `db-f1-micro` (if any) | ~$10/month each | disk only (~$2/month) |
| Cloud NAT (if enabled) | ~$1–5/month | ~$1/month |

For long breaks: `kubernetes.yaml` `cluster.enabled: false` after destroying the platform stack,
or destroy in reverse order (platform, identities, components, foundation).

## Prod

Prod is the project `registry-institution-prd` (project ids can't be renamed; the older
`registry-institution` project is not managed by this repository). Before the first apply:

1. Check it is empty: `gcloud asset search-all-resources --scope=projects/registry-institution-prd`
   (needs `cloudasset.googleapis.com`). Delete leftovers, or `scripts/tf.sh prod <stack> import`
   those you keep.
2. Run steps 2–5 with `prod`, then create the `prod-plan` and `prod` environments.
3. Uncomment the prod CI account under `external_readers` in `envs/dev/registries.yaml` and merge
   to `develop`, so the app's CD can promote the dev image to prod.

## Security notes (training defaults to revisit for a real fintech)

- `sa-terraform-ci` has `project: owner`; replace with a curated role list.
- Apps on the shared Firestore `(default)` database can read each other's collections: IAM
  conditions stop at the database. Use a named database per app for isolation (paid).
- PR plans run the PR's code with the Terraform identity; in a team, use a read-only plan identity.
- The GKE control plane has a public endpoint (GitHub-hosted runners need it).
- Generated passwords are in Terraform state; the state bucket is private and versioned.
- Next steps: default-deny NetworkPolicies per namespace, Binary Authorization, VPC Service
  Controls, a project per app and environment with a project factory at larger scale.
