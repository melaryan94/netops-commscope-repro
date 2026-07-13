# Private CI/CD for the NetOps stack (Azure DevOps + Managed DevOps Pools)

This folder is the **fully-private** variant of the CI/CD in [`../cicd/`](../cicd/).
Use it when your subscription is locked down the way the deployed NetOps stack is:
private-only PaaS, Azure Policy forcing storage **public access off** and
**shared-key auth off**.

The plain [`../cicd/azure-pipelines.yml`](../cicd/azure-pipelines.yml) runs on
**Microsoft-hosted public agents** and assumes reachable remote state — that does
**not** work against a private, policy-locked subscription. This variant fixes that.

## Why the public pattern breaks (and how this fixes it)

| Constraint in a locked-down tenant | Symptom with the public pattern | Fix here |
|---|---|---|
| Remote-state storage is **private** (private endpoint only) | Microsoft-hosted agents can't reach it → `terraform init` hangs/fails | **Managed DevOps Pool** with agents **VNet-injected** into a subnet next to the state private endpoint |
| Policy forces storage **shared-key off** | `azurerm` storage resource's post-create data-plane poll → `403 KeyBasedAuthenticationNotPermitted` | State account managed via **azapi** (control-plane only); backend uses **`use_azuread_auth`** (no keys) |
| MDP needs to inject agents into your subnet | Pool creation can't attach to the subnet | Subnet **delegated to `Microsoft.DevOpsInfrastructure/pools`** (created via azapi because the pinned azurerm provider doesn't allow that delegation value yet) |
| Bare agent image | `TerraformInstaller@1` / `AzureCLI@2` fail: `Unable to locate executable file: 'unzip'` / `'az'` | Pipeline installs `unzip` + Azure CLI up front (or use a richer image — see tip below) |

> **Tip (durable fix):** the install steps exist because a **plain Ubuntu marketplace
> image** lacks the standard tooling. For production, point the Managed DevOps Pool at
> the **"Azure Pipelines"** agent image (e.g. `ubuntu-22.04`), which ships with `az`,
> Terraform, `unzip`, etc. preinstalled — then the install steps are unnecessary. Keep
> the install steps only if you must run a hardened custom image without that tooling.

## Layout
- `bootstrap/` — one-time **private CI/CD platform** (run from a laptop with `terraform apply`):
  VNet + **delegated agent subnet** + NAT gateway + **private state storage** (private endpoint + DNS).
- `azure-pipelines.yml` — plan-on-PR / apply-on-merge, OIDC, MDP pool, targets `../terraform`.
- `backend.tf.example` — AAD-auth remote-state backend to copy into `terraform/`.

## Setup (once)

### 1. Bootstrap the private platform
```powershell
az login
az account set -s <your-subscription-id>
cd cicd-private/bootstrap
terraform init
terraform apply
```
Note the outputs:
- `state_storage_account_name` → put it in `backend.tf` (next step).
- `agent_subnet_id`, `vnet_name`, `state_resource_group` → for the MDP wizard.

> The `bootstrap/` state is **local** (gitignored). Keep it with the platform owner.

### 2. Wire the backend
Copy `backend.tf.example` into `terraform/` as `backend.tf`, replace `REPLACE_ME`
with `state_storage_account_name`, commit + push.

### 3. Create the Managed DevOps Pool (portal)
Register the providers once, then grant the MDP first-party app permission to join
the subnet:
```powershell
az provider register --namespace Microsoft.DevOpsInfrastructure
az provider register --namespace Microsoft.DevCenter

$sp = az ad sp list --display-name "DevOpsInfrastructure" --query "[0].id" -o tsv
$rg = az group show -n rg-netops-cicd --query id -o tsv
az role assignment create --assignee-object-id $sp `
  --assignee-principal-type ServicePrincipal `
  --role "Network Contributor" --scope $rg
```
Portal → **Managed DevOps Pools → Create**:
- **Name**: `netops-cicd-pool` (must match the pipeline `mdpPool`).
- **Region**: same as the platform VNet.
- **Dev Center project name**: no spaces (only `A-Z a-z 0-9 - _ .`).
- **Organization**: your Azure DevOps org.
- **Networking → Bring your own virtual network** → `vnet-netops-cicd` / **`snet-agent`**.

### 4. Service connection + RBAC (two different identities!)
- **Service connection** `sc-netops-cicd` (ARM → **Workload identity federation (automatic)**).
- Grant **its** identity: **Contributor** on the subscription + **Storage Blob Data
  Contributor** on the state storage account. (The automatic flow usually adds
  Contributor for you; add the Blob Data role manually.)

> Don't confuse this with the `DevOpsInfrastructure` grant in step 3 — that one only
> lets the **pool inject agents**; this one lets the **pipeline deploy + touch state**.

### 5. Environment, secrets, pipeline
- **Environment** `netops-cicd` with an **Approval** check (the apply gate).
- **Variable group** `netops-cicd-secrets` with the app's secret tfvars as secret
  variables, prefixed `TF_VAR_` (e.g. `TF_VAR_tls_pfx_base64`, `TF_VAR_tls_pfx_password`,
  `TF_VAR_pg_admin_password`). Prefer a Key Vault-backed variable group.
- **Pipeline** from `cicd-private/azure-pipelines.yml`. On first run, **Permit** the
  pool + service connection + environment when prompted.

## Notes
- Container image build/publish (`az acr build`) is out of scope here — it's a separate
  step (see `scripts/deploy.ps1`). This pipeline covers the **infrastructure** IaC loop.
- For the demo narrative: open a PR with a small change → reviewers see the exact
  `terraform plan` diff → merge → approval gate → `terraform apply`.
