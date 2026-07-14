# Brownfield adoption — existing multi-RG resources → Terraform + private CI/CD

A concrete playbook for taking **existing portal-built (ClickOps) resources spread
across multiple resource groups** under Terraform management, then operating them
through an Azure DevOps CI/CD pipeline.

This assumes a **locked-down / private** subscription (private-only storage,
policy-enforced), so it builds on the private CI/CD pattern in
[`../cicd-private/`](../cicd-private/). For the general (public-agent) adoption
notes, see [ADOPT-TERRAFORM-AZURE-DEVOPS.md](ADOPT-TERRAFORM-AZURE-DEVOPS.md).

> **Doing your first RG with a facilitator?** Follow the step-by-step, do-it-together
> session guide in [FIRST-RG-RUNBOOK.md](FIRST-RG-RUNBOOK.md) — it walks one resource
> group through import → clean plan → pipeline → first change, live.

---

## Phase 0 — Decisions & prep (before touching anything)
1. **Freeze policy**: agree that once an RG is imported, **no more portal edits** to
   those resources (portal changes → drift).
2. **Inventory** each RG: `az resource list -g <rg> -o table` for every target RG.
3. **State layout decision** (important with many RGs): use **one Terraform state per
   resource group** (a "stack" per RG). This keeps blast radius small and lets teams
   own their RG independently. Each stack gets its own state blob key (e.g.
   `rg-network.tfstate`, `rg-app.tfstate`).
4. **Install tools**: Azure CLI, Terraform >= 1.6, **`aztfexport`**
   (`az extension add -n aztfexport`, or the standalone binary), Azure DevOps
   org/project + Git repo.

## Phase 1 — Stand up the private CI/CD platform (one-time)
Use `cicd-private/bootstrap` from this repo:
```powershell
az login; az account set -s <sub-id>
cd cicd-private/bootstrap
terraform init
terraform apply     # VNet + delegated agent subnet + NAT + PRIVATE state storage
```
Then:
- Create the **Managed DevOps Pool** in the portal, injected into `snet-agent`
  (register `Microsoft.DevOpsInfrastructure` + `Microsoft.DevCenter`, and grant the
  `DevOpsInfrastructure` SP **Network Contributor** on the platform RG first).
- Create the **OIDC service connection** + grant **its** identity **Contributor**
  (on the sub or per-RG) and **Storage Blob Data Contributor** on the state account.
- Create the **Environment** with an approval check.

*(All of this is spelled out in [`../cicd-private/README.md`](../cicd-private/README.md).)*

## Phase 2 — Repo structure for multiple RGs

> **Ready-to-copy starter:** a working skeleton for everything below lives in
> [`../brownfield-scaffold/`](../brownfield-scaffold/) — a `stacks/_template/` folder
> to copy per RG, plus a parameterized pipeline template. See its README.

```
terraform/
  stacks/
    rg-network/     backend.tf (key=rg-network.tfstate)  main.tf  ...
    rg-data/        backend.tf (key=rg-data.tfstate)     main.tf  ...
    rg-app/         backend.tf (key=rg-app.tfstate)      main.tf  ...
  modules/          # optional shared modules extracted later
```
Each stack has its own `backend.tf` (copied from
[`../cicd-private/backend.tf.example`](../cicd-private/backend.tf.example)) with a
**unique `key`**, all pointing at the same private state account/container.

## Phase 3 — Import each RG with `aztfexport` (one RG at a time)
Run **from an agent/host that can reach the state account** — i.e. on the MDP agent
or a VNet-connected box (the state is private). For each RG:
```powershell
cd terraform/stacks/rg-network
aztfexport resource-group `
  --backend-type azurerm `
  --backend-config="resource_group_name=rg-<cicd>" `
  --backend-config="storage_account_name=<state-sa>" `
  --backend-config="container_name=tfstate" `
  --backend-config="key=rg-network.tfstate" `
  --backend-config="use_azuread_auth=true" `
  rg-network
```
This generates `main.tf` (+ provider) and **writes state directly into the private
backend** for everything it can map. Review interactively; skip resources you don't
want managed.

## Phase 4 — Get to a clean `plan` (zero changes)
For each stack:
```powershell
terraform init
terraform plan   # goal: "No changes"
```
- Expect some diffs — `aztfexport` doesn't capture every property. **Refactor** the
  generated HCL until `plan` shows **no changes** (adjust attributes, add
  `lifecycle { ignore_changes = [...] }` for Azure-injected fields like `ip_tags`,
  tags, etc.).
- Handle cross-RG references with **`terraform_remote_state`** data sources or `data`
  lookups (e.g. the app stack reads the network stack's subnet IDs).
- **Do not apply** until plan is clean — that's your proof of a faithful import.

## Phase 5 — Wire the pipeline (per stack)
Point [`../cicd-private/azure-pipelines.yml`](../cicd-private/azure-pipelines.yml) at
each stack (`workingDir: terraform/stacks/<rg>`), or parameterize it so one pipeline
template runs per stack. Each pipeline:
- **PR** → `terraform plan` on the MDP (VNet-injected) agent → reviewers see the diff.
- **Merge to main** → **approval gate** → `terraform apply`.

For many stacks, use a **matrix / template** so you don't copy YAML N times. The
scaffold does exactly this: [`../brownfield-scaffold/pipelines/terraform-stack.yml`](../brownfield-scaffold/pipelines/terraform-stack.yml)
is one reusable template, and each RG gets a tiny consumer (see
[`rg-example.yml`](../brownfield-scaffold/pipelines/rg-example.yml)) that `extends` it
with its own `stackPath` / `environment` / `subscriptionId`.

## Phase 6 — Operating model (the governance loop)
- All infra changes are **pull requests** with an automatic `plan`.
- **Required reviewers + environment approval** before apply → auditable.
- Nightly/weekly **drift detection**: a scheduled `plan` per stack; alert if non-empty
  (someone touched the portal).
- Secrets (DB passwords, certs) come from **Key Vault-backed variable groups** as
  `TF_VAR_*`, never in code.

## Phase 7 — Roll out
Do it **one RG at a time**, lowest-risk first (e.g. a networking or logging RG), prove
the loop end-to-end, then repeat. Extract shared **modules** only *after* a few RGs are
imported and you see real duplication — don't over-abstract up front.

---

## Realistic gotchas (all encountered building the reference in this repo)
- **Private state ⇒ agents must run in-VNet** (MDP or self-hosted). Both the import
  (`aztfexport`) and the pipeline need that network path.
- **Policy forcing key-auth-off / public-access-off** on storage → use **azapi + AAD
  backend** (`use_azuread_auth`), not the plain `azurerm_storage_account` resource
  (its post-create data-plane poll fails with `KeyBasedAuthenticationNotPermitted`).
- **Subnet must be delegated** to `Microsoft.DevOpsInfrastructure/pools` before pool
  creation (created via azapi if the pinned azurerm provider rejects the value).
- **Two identities need RBAC**: the MDP injection SP (**Network Contributor**) and the
  pipeline service-connection identity (**Contributor** + **Storage Blob Data
  Contributor**).
- **Bare agent images** may lack `unzip` / `az` → install them in the pipeline, or
  point the pool at the **Azure Pipelines** agent image (preinstalled tooling).
- **Brownfield imports never plan-clean on the first try** — budget time for the
  refactor-to-zero-diff step per RG.
