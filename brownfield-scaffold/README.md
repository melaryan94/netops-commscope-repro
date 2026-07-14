# brownfield-scaffold

A ready-to-copy starting point for the [Brownfield adoption playbook](../docs/BROWNFIELD-ADOPTION.md)
— taking existing resources across many resource groups under Terraform with the
private CI/CD pattern in [`../cicd-private/`](../cicd-private/).

```
brownfield-scaffold/
  stacks/
    _template/            # copy this per resource group
      backend.tf          # azurerm backend, UNIQUE key per stack, AAD auth
      providers.tf        # azurerm + azapi, versions pinned
      variables.tf        # subscription_id, tags
      main.tf             # where aztfexport output lands (+ import command + cross-stack example)
      README.md           # how to instantiate this stack
  pipelines/
    terraform-stack.yml   # ONE reusable plan/apply template (MDP pool, OIDC, tooling, approval gate)
    rg-example.yml        # tiny consumer that `extends` the template with per-RG params
  modules/                # optional shared modules (extract later, only when duplication is real)
```

## How to use it
1. **Once**: stand up the platform with [`../cicd-private/`](../cicd-private/) (private
   state + MDP pool + service connection). See its README.
2. **Per resource group**:
   - Copy `stacks/_template` → `stacks/<rg-name>`; set backend `key` + storage account.
   - Import with `aztfexport` (command in the stack's `main.tf`).
   - `terraform plan` → refactor to **"No changes"**.
   - Copy `pipelines/rg-example.yml` → `pipelines/<rg-name>.yml`; set `stackPath`,
     `environment`, `subscriptionId`; create an ADO pipeline + Environment (with approval).

## Why the split
- **One state per RG** (`key = "<rg>.tfstate"`) → small blast radius, per-team ownership.
- **One pipeline template, many tiny consumers** → fix logic once, every stack benefits.
- **Path-filtered triggers** → each RG's pipeline only runs when that RG's files change.
