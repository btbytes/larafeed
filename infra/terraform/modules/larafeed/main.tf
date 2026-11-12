locals {
  worker_name = coalesce(var.worker_name, var.name)
  source_dir  = abspath(coalesce(var.source_dir, "${path.module}/../../../.."))
  origin_host = regex("^https://([^:/]+)", var.auth_origin)[0]
  workers_dev = coalesce(var.workers_dev, length(var.custom_domains) == 0)

  queue_names = {
    feed_refresh    = "${var.name}-feed-refresh"
    opml_import     = "${var.name}-opml-import"
    favicon_refresh = "${var.name}-favicon-refresh"
  }

  ai_gateway_name   = coalesce(var.ai_summary.gateway_name, var.name)
  create_ai_gateway = var.ai_summary.enabled && var.ai_summary.create_gateway

  create_turnstile_widget = var.turnstile.enabled && var.turnstile.site_key == null
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

resource "cloudflare_d1_database" "main" {
  account_id            = var.account_id
  name                  = var.name
  primary_location_hint = var.d1_primary_location_hint

  read_replication = {
    mode = var.d1_read_replication ? "auto" : "disabled"
  }
}

resource "cloudflare_workers_kv_namespace" "full_content" {
  account_id = var.account_id
  title      = "${var.name}-full-content"
}

# Stores MCP OAuth clients, grants, and token hashes.
resource "cloudflare_workers_kv_namespace" "oauth" {
  account_id = var.account_id
  title      = "${var.name}-oauth"
}

# ---------------------------------------------------------------------------
# Queues (consumers are attached by the Wrangler deploy)
# ---------------------------------------------------------------------------

resource "cloudflare_queue" "this" {
  for_each = local.queue_names

  account_id = var.account_id
  queue_name = each.value
}

# ---------------------------------------------------------------------------
# Optional integrations
# ---------------------------------------------------------------------------

resource "cloudflare_ai_gateway" "this" {
  count = local.create_ai_gateway ? 1 : 0

  account_id                 = var.account_id
  id                         = local.ai_gateway_name
  collect_logs               = var.ai_summary.collect_logs
  cache_ttl                  = var.ai_summary.cache_ttl
  cache_invalidate_on_update = true
  rate_limiting_limit        = var.ai_summary.rate_limiting_limit
  rate_limiting_interval     = var.ai_summary.rate_limiting_interval
  rate_limiting_technique    = var.ai_summary.rate_limiting_technique
}

resource "cloudflare_turnstile_widget" "this" {
  count = local.create_turnstile_widget ? 1 : 0

  account_id = var.account_id
  name       = local.worker_name
  domains    = distinct(concat([local.origin_host], var.custom_domains))
  mode       = var.turnstile.mode
}

resource "random_password" "operator_secret" {
  count = var.auth_operator_secret == null ? 1 : 0

  length  = 64
  special = false
}

locals {
  auth_operator_secret = coalesce(var.auth_operator_secret, one(random_password.operator_secret[*].result))

  turnstile_site_key   = local.create_turnstile_widget ? cloudflare_turnstile_widget.this[0].sitekey : var.turnstile.site_key
  turnstile_secret_key = local.create_turnstile_widget ? cloudflare_turnstile_widget.this[0].secret : var.turnstile_secret_key
}
