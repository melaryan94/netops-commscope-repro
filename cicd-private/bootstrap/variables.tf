variable "subscription_id" {
  description = "Target subscription. Empty = current az context."
  type        = string
  default     = ""
}

variable "location" {
  description = "Region for the CI/CD platform. Match (or peer to) your app's region."
  type        = string
  default     = "centralus"
}

variable "prefix" {
  type    = string
  default = "netops-cicd"
}

# --- Azure DevOps (informational; the Managed DevOps Pool is created in the portal) ---
variable "ado_url" {
  description = "Azure DevOps organization URL, e.g. https://dev.azure.com/<your-org>."
  type        = string
  default     = "https://dev.azure.com/<your-org>"
}

variable "ado_pool" {
  description = "Managed DevOps Pool name you will create in the portal and target in the pipeline."
  type        = string
  default     = "netops-cicd-pool"
}

variable "tags" {
  type = map(string)
  default = {
    project = "netops-commscope-cicd"
    purpose = "private-cicd-platform"
  }
}
