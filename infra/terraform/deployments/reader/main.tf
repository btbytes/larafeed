terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
# Authenticates with the CLOUDFLARE_API_TOKEN environment variable.
provider "cloudflare" {}

variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "name" {
  description = "Prefix for every Cloudflare resource. Must be unused in the account."
  type        = string
  default     = "larafeed"
}

variable "hostname" {
  description = "Public hostname such as reader.example.com, or null to use workers.dev."
  type        = string
  default     = null
}

variable "workers_dev_subdomain" {
  description = "Your account's workers.dev subdomain. Only used when hostname is null."
  type        = string
  default     = null
}

locals {
  origin_host = var.hostname != null ? var.hostname : "${var.name}.${var.workers_dev_subdomain}.workers.dev"
}

module "larafeed" {
  source = "../../modules/larafeed"

  account_id     = var.account_id
  name           = var.name
  auth_origin    = "https://${local.origin_host}"
  custom_domains = var.hostname != null ? [var.hostname] : []

  # Add or change settings here. See section 17 for every option.
  images_enabled          = true
  favicon_refresh_enabled = true

  ai_summary = {
    enabled = true
  }
}

output "url" {
  value = module.larafeed.url
}

output "worker_name" {
  value = module.larafeed.worker_name
}

output "wrangler_config_path" {
  value = module.larafeed.wrangler_config_path
}

output "initial_admin_command" {
  value = module.larafeed.initial_admin_command
}

output "auth_operator_secret" {
  value     = module.larafeed.auth_operator_secret
  sensitive = true
}
