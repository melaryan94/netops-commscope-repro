# Adopt Terraform for an existing (ClickOps) environment with Azure DevOps CI/CD

Take portal-built resources under Terraform management (no downtime), then manage
them via Azure DevOps pipelines. Start in **dev**, then repeat per environment.

> **Locked-down / private subscription?** The steps below use Microsoft-hosted
> agents and a reachable remote-state account. If your subscription enforces
> **private-only storage** and **shared-key-off** (as the deployed NetOps stack
> does), use the fully-private variant in [`../cicd-private/`](../cicd-private/)
> instead — it runs on **Managed DevOps Pools** (VNet-injected agents) with an
> **azapi/AAD** private state account. See
> [`../cicd-private/README.md`](../cicd-private/README.md).
>
> **Existing resources across multiple resource groups?** For a brownfield,
> import-and-adopt playbook (aztfexport per RG, one state per RG, refactor to a
> clean plan, then wire the private pipeline), see
> [BROWNFIELD-ADOPTION.md](BROWNFIELD-ADOPTION.md).

## Phase 0 — Plan & prerequisites
- Inventory what exists per resource group (App Service, SWA, Key Vault, PostgreSQL,
  networking, App Gateway, etc.).
- Agree that once a resource group is imported, **no more portal edits** to those
  resources (or you get drift).
- Tools: Azure CLI, Terraform >= 1.6, **`aztfexport`**, an Azure DevOps project + Git repo.

## Phase 1 — Remote state (one-time bootstrap)
Run `cicd/bootstrap-remote-state.ps1` (creates a hardened storage account + container,
AAD-only). Grant yourself **and the pipeline identity** `Storage Blob Data Contributor`
on that storage account.

## Phase 2 — Repo layout
```
infra/
  backend.tf        # from cicd/backend.tf.example
  providers.tf
  *.tf              # resources (after import + refactor)
  variables.tf
  envs/{dev,test,prod}.tfvars
azure-pipelines.yml # from cicd/azure-pipelines.yml
```

## Phase 3 — Import existing resources (aztfexport)
```powershell
winget install Microsoft.Azure.AztfExport
cd infra
aztfexport resource-group --backend-type=azurerm `
  --backend-config="resource_group_name=rg-tfstate" `
  --backend-config="storage_account_name=<sa>" `
  --backend-config="container_name=tfstate" `
  --backend-config="key=netops-dev.tfstate" `
  rg-netops-dev
```
For surgical additions later, use native `import {}` blocks + `terraform plan -generate-config-out=gen.tf`.

## Phase 4 — Refactor generated code
- Parameterize names/locations into variables + `*.tfvars`.
- Split into logical files; factor repeated patterns into modules.
- Add `lifecycle { ignore_changes = [...] }` for Azure-injected drift (e.g. `ip_tags`,
  `zones` on public IPs — see the repo's `network.tf` / `appgateway.tf` / `vpn.tf`).
- Align policy-managed properties (e.g. private Key Vault `publicNetworkAccess`).

## Phase 5 — Acceptance gate: plan shows no changes
```powershell
terraform init
terraform plan   # iterate until: "No changes. Your infrastructure matches the configuration."
```
Do not proceed until the plan is clean. Then **stop portal edits** on those resources.

## Phase 6 — Azure DevOps identity & permissions
1. Service connection: **Azure Resource Manager → Workload identity federation (automatic)**
   (OIDC, no secrets). Name it e.g. `sc-netops-oidc`.
2. Grant its identity RBAC:
   - `Contributor` on the target subscription/RG.
   - `Storage Blob Data Contributor` on the **state storage account**.
   - `User Access Administrator` **only if** your Terraform creates role assignments.
3. Create ADO Environments `dev`, `test`, `prod` with **approval checks** on test/prod.

## Phase 7 — Pipeline
Use `cicd/azure-pipelines.yml`: **plan on PR**, **apply on merge to main** (gated by the
Environment approval). Blob lease provides state locking automatically.

## Phase 8 — Governance & guardrails
- Branch policy on `main`: require PR + passing Plan build before merge.
- Approvals on `test`/`prod` Environments.
- `*.tfstate` gitignored; state only in the storage account.
- Least-privilege RBAC.
- Optional `tflint`/`checkov` step in the Plan stage.

## Phase 9 — Roll out across environments
Repeat Phases 3–5 per resource group with a separate state `key`
(`netops-test.tfstate`, `netops-prod.tfstate`) and its own `*.tfvars`; promote the same
code through environments via the pipeline.

## Mental model
Bootstrap state (once) → import each RG with `aztfexport` → refactor → plan = zero changes
(freeze portal) → OIDC pipeline does plan-on-PR / apply-on-merge → repeat per environment.
