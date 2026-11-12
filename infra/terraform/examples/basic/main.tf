terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN, which the Wrangler deploy step also uses.
provider "cloudflare" {}

variable "account_id" {
  type = string
}

variable "hostname" {
  description = "Public hostname, for example reader.example.com. Its zone must be in the account."
  type        = string
}

module "larafeed" {
  source = "../../modules/larafeed"

  account_id     = var.account_id
  name           = "larafeed"
  auth_origin    = "https://${var.hostname}"
  custom_domains = [var.hostname]

  images_enabled          = true
  favicon_refresh_enabled = true

  ai_summary = {
    enabled = true
  }
}

output "url" {
  value = module.larafeed.url
}

output "initial_admin_command" {
  value = module.larafeed.initial_admin_command
}

output "auth_operator_secret" {
  value     = module.larafeed.auth_operator_secret
  sensitive = true
}
