# Facilitator runbook — adopt your FIRST resource group (live, together)

A hand-holding, do-it-together guide for the **Crawl** phase: take **one** existing
resource group under Terraform and run one change through the pipeline. Plan ~60–90 min.

Goal for the session: the customer sees the full loop — **code → PR → plan → approve
→ apply** — working against **one real resource group they already own**.

> Values in `<angle brackets>` are customer-specific — fill them in before you start.

---

## 0. Before the session (facilitator prep — do this solo)

**Pick the pilot RG with the customer's input, but pre-vet it. Good first RG =**
- Low blast radius (networking, logging, a non-prod app).
- Small (5–20 resources), few interdependencies.
- Not currently changing daily.

**Confirm the private CI/CD platform exists** (from `cicd-private/`). You need:
- [ ] Private state storage account name → `<STATE_SA>`
- [ ] CI/CD platform RG → `<CICD_RG>` (e.g. `rg-netops-cicd`)
- [ ] Managed DevOps Pool name → `<MDP_POOL>`
- [ ] OIDC service connection name → `<SVC_CONN>`
- [ ] The service-connection identity has **Contributor** on the sub (or pilot RG)
      and **Storage Blob Data Contributor** on `<STATE_SA>`.

If any are missing, do the one-time setup in [`../cicd-private/README.md`](../cicd-private/README.md) first.

**Gather these values:**
| Value | Placeholder | Where to get it |
|---|---|---|
| Subscription id | `<SUB_ID>` | `az account show --query id -o tsv` |
| Pilot resource group | `<RG>` | agreed with customer |
| Azure DevOps org/project/repo | `<ORG>/<PROJECT>/<REPO>` | the repo holding the stacks |

---

## 1. Frame it (5 min, whiteboard)
Say: *"We're going to take one resource group and put it under code — no changes to
your resources, just describing what already exists. Then we'll make one small change
through a pull request so you see the whole loop."*

Draw the 4 boxes: **Code → Pull Request → Approval → Pipeline applies.**

Reassure: **read-only import first; nothing gets modified until we choose to.**

---

## 2. Create the stack folder (5 min — screen-share)
From the repo (using the scaffold):
```powershell
git checkout -b adopt/<RG>
Copy-Item -Recurse brownfield-scaffold/stacks/_template brownfield-scaffold/stacks/<RG>
```
Edit `brownfield-scaffold/stacks/<RG>/backend.tf`:
- `storage_account_name = "<STATE_SA>"`
- `key = "<RG>.tfstate"`   ← unique per RG

**Show the customer:** "This folder now *represents* that resource group. The `key` is
its own private save-file."

---

## 3. Inventory what's there (5 min)
```powershell
az resource list -g <RG> -o table
```
**Talking point:** "This is everything we're about to bring under management — nothing
more, nothing less."

---

## 4. Import the RG with aztfexport (15–25 min)
Run from a **VNet-connected host or the MDP agent** (the state is private).
```powershell
cd brownfield-scaffold/stacks/<RG>
aztfexport resource-group `
  --backend-type azurerm `
  --backend-config="resource_group_name=<CICD_RG>" `
  --backend-config="storage_account_name=<STATE_SA>" `
  --backend-config="container_name=tfstate" `
  --backend-config="key=<RG>.tfstate" `
  --backend-config="use_azuread_auth=true" `
  <RG>
```
- It maps each resource → generates `.tf` here → writes remote state.
- Review the interactive list; **skip** anything you don't want managed.

**Show the customer:** the generated `.tf` files. "This code was written *from your
existing environment* — we didn't hand-write it."

---

## 5. Get to a clean plan (15–30 min — the real work)
```powershell
terraform plan
```
**Aim: "No changes."** First pass usually shows diffs because the export doesn't capture
every property. Fix them:
- Add missing attributes the export skipped.
- Add `lifecycle { ignore_changes = [...] }` for Azure-injected fields (tags, `ip_tags`, etc.).
- For cross-RG references, use `data "terraform_remote_state"` (example is in `main.tf`).

**Talking point:** *"A clean plan with zero changes is our proof the code is a faithful
mirror of what you have. Now — and only now — is it safe to hand over to the pipeline."*

Commit when clean:
```powershell
git add brownfield-scaffold/stacks/<RG>
git commit -m "Adopt <RG> under Terraform (import, plan clean)"
git push -u origin adopt/<RG>
```

---

## 6. Wire the pipeline + approval gate (10 min — portal/ADO)
1. Copy the example consumer:
   ```powershell
   Copy-Item brownfield-scaffold/pipelines/rg-example.yml brownfield-scaffold/pipelines/<RG>.yml
   ```
   Edit `<RG>.yml`: set `stackPath: brownfield-scaffold/stacks/<RG>`, `environment: <RG>`,
   `subscriptionId: <SUB_ID>`, and update the `paths` filter to the stack folder.
2. In **Azure DevOps → Pipelines → Environments → New** → name it **`<RG>`** →
   add an **Approval** check (the customer as approver).
3. **Pipelines → New pipeline** → your repo → **Existing YAML** → `pipelines/<RG>.yml`.
4. On first run, **Permit** the pool + service connection + environment.

**Talking point:** *"The approval you just added is the gate — nothing applies to Azure
until a human clicks approve."*

---

## 7. The "aha" — make one change through a PR (15 min)
Pick something tiny and safe to prove the loop (e.g. add a `tag`).
1. Branch, edit one resource (add `tags = { managed_by = "terraform" }` or similar), push.
2. Open a **Pull Request**.
3. The **Plan** stage runs automatically → open it → **show the `terraform plan` diff**:
   *"This is exactly what will change — reviewed before anything happens."*
4. **Merge** → the **Apply** stage pauses at the **approval** → have the **customer click
   approve** → `terraform apply` runs.
5. Refresh the portal → show the tag applied.

**Land the message:** *"That's the whole model. Every future change looks like this —
proposed, reviewed, approved, applied, and logged. No portal clicking."*

---

## 8. Close the loop (5 min)
- **Drift demo (optional, powerful):** change that tag **in the portal**, then re-run the
  pipeline's plan → it shows the drift → *"the code is the source of truth; the portal
  isn't."*
- **Next steps:** *"We just did one resource group. We repeat this per RG — copy the
  folder, import, clean plan, pipeline. One at a time, no downtime."*
- Add a **scheduled nightly `plan`** later for automatic drift alerts.

---

## Troubleshooting quick-reference (if something goes red live)
| Symptom | Cause | Fix |
|---|---|---|
| `terraform init` hangs/403 on state | Agent not in the VNet, or missing Blob Data role | Run on MDP/VNet host; grant **Storage Blob Data Contributor** on `<STATE_SA>` |
| `KeyBasedAuthenticationNotPermitted` | Policy: shared-key off | Backend already uses `use_azuread_auth = true`; ensure you're not using access keys |
| Pipeline job stuck "acquiring agent" | MDP cold start | Wait a few min (first run); it scales from zero |
| `unzip` / `az` not found | Bare MDP image | Tooling install step handles it, or use the **Azure Pipelines** agent image |
| `plan` never reaches "No changes" | Export didn't capture a property | Add the attribute or `ignore_changes`; iterate |
| Apply can't find `tfplan` | Artifact nesting | Path is `$(Pipeline.Workspace)/tfplan/tfplan` (already fixed in templates) |

---

## Facilitator mindset
- **Import is read-only.** Repeat this early and often — it calms nerves.
- **Zero-diff plan is the milestone**, not the apply. Celebrate it.
- Keep the deep plumbing (MDP, private endpoints, OIDC, azapi) **in your back pocket** —
  only surface it if an engineer asks "how does this work in our locked-down setup?"
- One RG. Prove it. Repeat. Don't boil the ocean.
