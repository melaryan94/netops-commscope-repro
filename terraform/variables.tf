variable "subscription_id" {
  description = "Target subscription id. Leave empty to use the current az CLI context."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralus"
}

variable "prefix" {
  description = "Short name prefix for resources."
  type        = string
  default     = "netops-cs"
}

variable "custom_domain" {
  description = "Internal custom domain served by App Gateway (self-signed cert CN)."
  type        = string
  default     = "netops.commscope.com"
}

variable "tls_pfx_base64" {
  description = "Base64 of a PFX for the App Gateway HTTPS listener. Produced by scripts/gen-tls-cert.ps1."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tls_pfx_password" {
  description = "Password for the App Gateway PFX."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pg_admin_login" {
  description = "PostgreSQL administrator login."
  type        = string
  default     = "pgadmin"
}

variable "pg_admin_password" {
  description = "PostgreSQL administrator password. Leave empty to auto-generate a strong random password (repro default)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "demo_user" {
  description = "Dummy app login username."
  type        = string
  default     = "netops"
}

variable "demo_password" {
  description = "Dummy app login password."
  type        = string
  default     = "P@ssw0rd!"
  sensitive   = true
}

variable "vpn_root_cert_name" {
  description = "Name for the P2S VPN root certificate."
  type        = string
  default     = "netops-p2s-root"
}

variable "vpn_root_cert_data" {
  description = "Base64 (single-line, no PEM headers) public data of the P2S VPN root cert. Produced by scripts/gen-vpn-certs.ps1."
  type        = string
  default     = ""
}

variable "vpn_client_address_pool" {
  description = "Address pool handed to P2S VPN clients."
  type        = string
  default     = "172.16.100.0/24"
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default = {
    project = "netops-command-center-repro"
    owner   = "mo"
  }
}
