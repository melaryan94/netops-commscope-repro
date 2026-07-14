# Stack template

Copy this folder once per resource group you're adopting.

```powershell
# from repo root
Copy-Item -Recurse brownfield-scaffold/stacks/_template brownfield-scaffold/stacks/rg-network
```

Then, in the new folder:
1. **`backend.tf`** — set `storage_account_name` (bootstrap output) and a **unique**
   `key`, e.g. `key = "rg-network.tfstate"`.
2. **Import** the existing RG with `aztfexport` (command is in `main.tf`). It generates
   the resource HCL here and writes remote state.
3. **`terraform plan`** → refactor until it reports **"No changes"**.
4. **Pipeline** — copy `brownfield-scaffold/pipelines/rg-example.yml` to
   `pipelines/rg-network.yml`, set `stackPath`/`environment`, and create an ADO
   pipeline pointing at it.

> Do **not** commit `.terraform/`, `*.tfstate*`, or `tfplan` (already gitignored).
