variable "subscription_id" {
  description = "Target subscription. Empty = current az / OIDC context."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags to apply (optional)."
  type        = map(string)
  default     = {}
}
