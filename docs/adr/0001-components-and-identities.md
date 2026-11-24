# ADR 0001: Components and identities, owned by the organization IaC

- Status: Accepted
- Date: 2026-11-21

## Context

`registry-institution-iac` serves many application repositories; `optin-backend` is the first.
Earlier designs grouped settings per app (one YAML per app with its database, secrets, topics and
permissions). That made two questions hard to answer, both common in a fintech audit:

1. *Who can access this database / secret / topic?* — needed opening every app file.
2. *What can this identity do?* — permissions were spread across app files and Terraform modules.

It also mixed lifecycles: a paid database shared by several apps has no single app owner.

## Decision

1. **Settings split by component type**, eight block-style YAML files per environment:
   project, network, kubernetes, databases, messages, secrets, registries, service_accounts.
   Each component (a Firestore database, a Cloud SQL instance, a topic...) is declared once, by
   name, independently of who uses it. Free and paid instances are just entries
   (Firestore `default` → the free `(default)` database; any other key → a named paid database).
2. **One file for all identities and permissions**: `service_accounts.yaml`. Each entry is a
   Google service account (`sa-<name>`) of type `workload` (plus the Kubernetes service account
   `sa-<name>` in its namespace, linked by Workload Identity) or `github` (usable by one
   repository through Workload Identity Federation). Its `access` map lists
   `<type>/<component>: <role>` using a small vocabulary mapped to predefined Google roles.
3. **Grants are scoped to the component**: resource-level IAM where it exists (secret, topic,
   registry), IAM conditions on `resource.name` where it doesn't (Firestore database, Cloud SQL
   instance), Kubernetes RBAC for namespaces.
4. **Four stacks with separate state**: foundation → components → identities → platform.
   IAM lives alone in `identities`, so every permission change is a small, reviewable plan.
5. **Apps create nothing in GCP or cluster-level Kubernetes**: no namespaces, service accounts,
   RBAC, quotas or IAM in app repositories. Their CI identity can't create them either.
6. **Validation before any API call**: `modules/settings` rejects unknown types, invalid roles,
   references to undefined components and workloads without a declared namespace.

## Consequences

- One file answers "who can do what"; `identities output access_matrix` shows the applied result.
- Onboarding an app touches several files in one PR; reviewers see its footprint by component.
- The platform team (this repo) becomes a bottleneck for app changes that need new access.
  Accepted at this size; at larger scale, split `service_accounts.yaml` per team with CODEOWNERS,
  or move to a project-per-app factory.
- A component and the access to it added in the same PR can't be planned in one pass (identities
  reads the applied components state); apply in order or in two PRs.
- Shared `(default)` Firestore: isolation stops at the database; collection-level separation is
  by convention only. Named databases fix it at a cost.
- Renaming a component or identity key recreates it (and its grants). Keys are stable names.
