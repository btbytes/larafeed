locals {
  generated_dir = abspath(coalesce(var.generated_dir, "${path.root}/.terraform/larafeed/${local.worker_name}"))

  secrets = merge(
    { AUTH_OPERATOR_SECRET = local.auth_operator_secret },
    var.turnstile.enabled ? {
      TURNSTILE_SITE_KEY   = local.turnstile_site_key
      TURNSTILE_SECRET_KEY = local.turnstile_secret_key
    } : {},
  )

  secret_names = concat(
    ["AUTH_OPERATOR_SECRET"],
    var.turnstile.enabled ? ["TURNSTILE_SECRET_KEY", "TURNSTILE_SITE_KEY"] : [],
  )

  # Mirrors the portable default environment in wrangler.jsonc, with every
  # resource ID and tunable taken from Terraform.
  wrangler_config = merge(
    {
      "$schema"           = "${local.source_dir}/node_modules/wrangler/config-schema.json"
      name                = local.worker_name
      main                = "${local.source_dir}/src/worker/index.ts"
      compatibility_date  = var.compatibility_date
      compatibility_flags = ["nodejs_compat", "global_fetch_strictly_public"]
      workers_dev         = local.workers_dev
      preview_urls        = var.preview_urls
      secrets             = { required = local.secret_names }

      vars = {
        AUTH_ENVIRONMENT           = "production"
        AUTH_ORIGIN                = var.auth_origin
        AUTH_RP_NAME               = var.auth_rp_name
        AUTH_CHALLENGE_TTL_SECONDS = tostring(var.auth_challenge_ttl_seconds)
        AUTH_SESSION_TTL_SECONDS   = tostring(var.auth_session_ttl_seconds)
        TURNSTILE_ENABLED          = tostring(var.turnstile.enabled)
        AI_SUMMARY_ENABLED         = tostring(var.ai_summary.enabled)
        AI_GATEWAY_NAME            = local.ai_gateway_name
        AI_MODEL                   = var.ai_summary.model
        FULL_CONTENT_ENABLED       = tostring(var.full_content_enabled)
        REFRESH_SCHEDULER_ENABLED  = tostring(var.refresh_scheduler_enabled)
        REFRESH_DISPATCH_ENABLED   = tostring(var.refresh_dispatch_enabled)
        REFRESH_DUE_LIMIT          = tostring(var.refresh_due_limit)
        OPML_IMPORT_ENABLED        = tostring(var.opml_import_enabled)
        FAVICON_REFRESH_ENABLED    = tostring(var.favicon_refresh_enabled)
        IMAGES_ENABLED             = tostring(var.images_enabled)
        FEED_REFRESH_QUEUE_NAME    = local.queue_names.feed_refresh
        OPML_IMPORT_QUEUE_NAME     = local.queue_names.opml_import
        FAVICON_REFRESH_QUEUE_NAME = local.queue_names.favicon_refresh
      }

      assets = {
        not_found_handling = "single-page-application"
        run_worker_first = [
          "/api/*",
          "/export",
          "/up",
          "/mcp",
          "/authorize",
          "/oauth/*",
          "/.well-known/oauth-*",
        ]
      }

      images = { binding = "IMAGES" }

      kv_namespaces = [
        { binding = "FULL_CONTENT_KV", id = cloudflare_workers_kv_namespace.full_content.id },
        { binding = "OAUTH_KV", id = cloudflare_workers_kv_namespace.oauth.id },
      ]

      d1_databases = [{
        binding        = "DB"
        database_name  = cloudflare_d1_database.main.name
        database_id    = cloudflare_d1_database.main.id
        migrations_dir = "${local.source_dir}/migrations"
      }]

      ratelimits = [
        {
          name         = "AUTH_RATE_LIMITER"
          namespace_id = var.auth_rate_limit.namespace_id
          simple       = { limit = var.auth_rate_limit.limit, period = var.auth_rate_limit.period }
        },
        {
          name         = "COMPAT_RATE_LIMITER"
          namespace_id = var.compat_rate_limit.namespace_id
          simple       = { limit = var.compat_rate_limit.limit, period = var.compat_rate_limit.period }
        },
      ]

      queues = {
        producers = [
          { binding = "FEED_REFRESH_QUEUE", queue = cloudflare_queue.this["feed_refresh"].queue_name },
          { binding = "OPML_IMPORT_QUEUE", queue = cloudflare_queue.this["opml_import"].queue_name },
          { binding = "FAVICON_REFRESH_QUEUE", queue = cloudflare_queue.this["favicon_refresh"].queue_name },
        ]
        consumers = [
          for key, settings in var.queue_consumers : merge(
            { queue = cloudflare_queue.this[key].queue_name },
            settings,
          )
        ]
      }

      triggers = { crons = var.cron_schedules }

      observability = {
        enabled = var.observability.enabled
        logs = {
          enabled            = var.observability.enabled
          head_sampling_rate = var.observability.logs_head_sampling_rate
          invocation_logs    = true
          persist            = true
        }
        traces = {
          enabled            = var.observability.traces_enabled
          head_sampling_rate = var.observability.traces_head_sampling_rate
          persist            = true
        }
      }
    },
    var.smart_placement ? { placement = { mode = "smart" } } : {},
    var.ai_summary.enabled ? { ai = { binding = "AI" } } : {},
    length(var.custom_domains) > 0 ? {
      routes = [for domain in var.custom_domains : { pattern = domain, custom_domain = true }]
    } : {},
  )

  source_patterns = [
    "src/**", "migrations/**", "public/**", "scripts/*.ts",
    "index.html", "package.json", "bun.lock", "vite.config.ts",
  ]
  source_hash = coalesce(var.source_version, sha1(join("", [
    for file in sort(setunion([for p in local.source_patterns : fileset(local.source_dir, p)]...)) :
    filesha1("${local.source_dir}/${file}")
  ])))
}

resource "local_file" "wrangler_config" {
  filename        = "${local.generated_dir}/wrangler.json"
  content         = jsonencode(local.wrangler_config)
  file_permission = "0644"
}

resource "local_sensitive_file" "secrets" {
  filename        = "${local.generated_dir}/secrets.json"
  content         = jsonencode(local.secrets)
  file_permission = "0600"

  lifecycle {
    precondition {
      condition     = !var.turnstile.enabled || local.turnstile_secret_key != null
      error_message = "turnstile_secret_key is required when turnstile.site_key is set."
    }
  }
}

# Builds with the Cloudflare Vite plugin, applies pending D1 migrations, and
# deploys the built artifact. Re-runs when the config, secrets, or sources change.
resource "terraform_data" "deploy" {
  count = var.deploy_worker ? 1 : 0

  triggers_replace = {
    config  = local_file.wrangler_config.content_sha256
    secrets = local_sensitive_file.secrets.content_sha256
    source  = local.source_hash
  }

  # Kept in state so the destroy provisioner can reach it through self.
  input = {
    account_id  = var.account_id
    worker_name = local.worker_name
    source_dir  = local.source_dir
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/deploy.sh"
    interpreter = ["bash", "-c"]
    environment = {
      CLOUDFLARE_ACCOUNT_ID    = var.account_id
      LARAFEED_SOURCE_DIR      = local.source_dir
      LARAFEED_WRANGLER_CONFIG = local_file.wrangler_config.filename
      LARAFEED_SECRETS_FILE    = local_sensitive_file.secrets.filename
      LARAFEED_INSTALL_DEPS    = tostring(var.install_dependencies)
    }
  }

  # Remove the Worker first so its Queue consumers release the Queues.
  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    command     = "bunx --no-install wrangler delete --name '${self.input.worker_name}' --force"
    working_dir = self.input.source_dir
    environment = {
      CLOUDFLARE_ACCOUNT_ID = self.input.account_id
    }
  }

  depends_on = [
    cloudflare_ai_gateway.this,
  ]
}
