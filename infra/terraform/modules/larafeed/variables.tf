# ---------------------------------------------------------------------------
# Account and naming
# ---------------------------------------------------------------------------

variable "account_id" {
  description = "Cloudflare account ID that owns every resource."
  type        = string
}

variable "name" {
  description = "Base name for the Worker, D1 database, KV namespaces, and Queues."
  type        = string
  default     = "larafeed"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,40}[a-z0-9]$", var.name))
    error_message = "name must be 2-42 lowercase letters, digits, or hyphens, and must not start or end with a hyphen."
  }
}

variable "worker_name" {
  description = "Worker script name. Defaults to var.name."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Public origin and routing
# ---------------------------------------------------------------------------

variable "auth_origin" {
  description = "Exact public HTTPS origin, without a path or trailing slash (for example https://reader.example.com). The WebAuthn RP ID is derived from it."
  type        = string

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+(:[0-9]+)?$", var.auth_origin))
    error_message = "auth_origin must be an https:// origin with no path or trailing slash."
  }
}

variable "custom_domains" {
  description = "Hostnames to attach as Workers Custom Domains. Each zone must exist in the account. Leave empty to serve from workers.dev."
  type        = list(string)
  default     = []
}

variable "workers_dev" {
  description = "Expose the Worker on workers.dev. Defaults to true only when no custom domain is set."
  type        = bool
  default     = null
}

variable "preview_urls" {
  description = "Enable Worker preview URLs."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------

variable "compatibility_date" {
  description = "Workers compatibility date."
  type        = string
  default     = "2026-07-18"
}

variable "smart_placement" {
  description = "Enable Smart Placement."
  type        = bool
  default     = true
}

variable "cron_schedules" {
  description = "Cron Triggers that run the refresh scheduler."
  type        = list(string)
  default     = ["*/10 * * * *"]
}

variable "observability" {
  description = "Workers Logs and traces settings."
  type = object({
    enabled                   = optional(bool, true)
    logs_head_sampling_rate   = optional(number, 1)
    traces_enabled            = optional(bool, true)
    traces_head_sampling_rate = optional(number, 1)
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

variable "auth_operator_secret" {
  description = "Operator secret used to mint administrator enrollment links. Leave null to generate one; read it back from the sensitive auth_operator_secret output."
  type        = string
  default     = null
  sensitive   = true
}

variable "auth_rp_name" {
  description = "WebAuthn relying-party display name."
  type        = string
  default     = "Larafeed"
}

variable "auth_challenge_ttl_seconds" {
  description = "Passkey challenge lifetime."
  type        = number
  default     = 300
}

variable "auth_session_ttl_seconds" {
  description = "Session lifetime."
  type        = number
  default     = 2592000
}

variable "auth_rate_limit" {
  description = "Rate limit for auth endpoints. namespace_id must be a positive integer string unique within the account."
  type = object({
    namespace_id = optional(string, "9001")
    limit        = optional(number, 20)
    period       = optional(number, 60)
  })
  default = {}

  validation {
    condition     = contains([10, 60], var.auth_rate_limit.period)
    error_message = "auth_rate_limit.period must be 10 or 60."
  }
}

variable "compat_rate_limit" {
  description = "Rate limit for the Google Reader and Fever APIs. namespace_id must be a positive integer string unique within the account."
  type = object({
    namespace_id = optional(string, "9002")
    limit        = optional(number, 300)
    period       = optional(number, 60)
  })
  default = {}

  validation {
    condition     = contains([10, 60], var.compat_rate_limit.period)
    error_message = "compat_rate_limit.period must be 10 or 60."
  }
}

variable "turnstile" {
  description = "Turnstile protection for sign-in. When enabled and site_key is null, the module creates a widget bound to the auth_origin hostname and the custom domains."
  type = object({
    enabled  = optional(bool, false)
    site_key = optional(string)
    mode     = optional(string, "managed")
  })
  default = {}
}

variable "turnstile_secret_key" {
  description = "Secret key for an existing Turnstile widget. Required only when turnstile.site_key is set."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------

variable "full_content_enabled" {
  description = "Enable full-content extraction (FULL_CONTENT_ENABLED)."
  type        = bool
  default     = true
}

variable "opml_import_enabled" {
  description = "Enable OPML imports (OPML_IMPORT_ENABLED)."
  type        = bool
  default     = true
}

variable "refresh_scheduler_enabled" {
  description = "Enable the cron refresh scheduler (REFRESH_SCHEDULER_ENABLED)."
  type        = bool
  default     = true
}

variable "refresh_dispatch_enabled" {
  description = "Enable dispatching refresh jobs to the Queue (REFRESH_DISPATCH_ENABLED)."
  type        = bool
  default     = true
}

variable "refresh_due_limit" {
  description = "Maximum number of due feeds dispatched per cron run (REFRESH_DUE_LIMIT)."
  type        = number
  default     = 5
}

variable "images_enabled" {
  description = "Enable Cloudflare Images article image transforms (IMAGES_ENABLED)."
  type        = bool
  default     = false
}

variable "favicon_refresh_enabled" {
  description = "Enable favicon discovery (FAVICON_REFRESH_ENABLED). Requires images_enabled for bitmap normalization."
  type        = bool
  default     = false
}

variable "ai_summary" {
  description = "Workers AI summaries routed through AI Gateway. gateway_name defaults to var.name. Set create_gateway = false to use an existing gateway."
  type = object({
    enabled                 = optional(bool, false)
    model                   = optional(string, "@cf/mistralai/mistral-small-3.1-24b-instruct")
    gateway_name            = optional(string)
    create_gateway          = optional(bool, true)
    collect_logs            = optional(bool, false)
    cache_ttl               = optional(number, 0)
    rate_limiting_limit     = optional(number, 0)
    rate_limiting_interval  = optional(number, 0)
    rate_limiting_technique = optional(string, "fixed")
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Storage and Queues
# ---------------------------------------------------------------------------

variable "d1_primary_location_hint" {
  description = "Optional D1 primary location hint (wnam, enam, weur, eeur, apac, oc)."
  type        = string
  default     = null
}

variable "d1_read_replication" {
  description = "Enable D1 read replication. Larafeed uses D1 Sessions, so replicas are safe."
  type        = bool
  default     = true
}

variable "queue_consumers" {
  description = "Consumer settings for each Queue."
  type = object({
    feed_refresh = optional(object({
      max_batch_size    = optional(number, 1)
      max_batch_timeout = optional(number, 1)
      max_retries       = optional(number, 5)
      max_concurrency   = optional(number, 2)
    }), {})
    opml_import = optional(object({
      max_batch_size    = optional(number, 1)
      max_batch_timeout = optional(number, 1)
      max_retries       = optional(number, 5)
      max_concurrency   = optional(number, 1)
    }), {})
    favicon_refresh = optional(object({
      max_batch_size    = optional(number, 1)
      max_batch_timeout = optional(number, 1)
      max_retries       = optional(number, 5)
      max_concurrency   = optional(number, 1)
    }), {})
  })
  default = {}
}

# ---------------------------------------------------------------------------
# Build and deploy
# ---------------------------------------------------------------------------

variable "deploy_worker" {
  description = "Build, migrate, and deploy the Worker with Wrangler. Set false to only provision resources and render the Wrangler config."
  type        = bool
  default     = true
}

variable "source_dir" {
  description = "Path to the Larafeed repository root. Defaults to the repository containing this module."
  type        = string
  default     = null
}

variable "source_version" {
  description = "Redeploy trigger, such as a git commit SHA. When null, the module hashes the application sources instead."
  type        = string
  default     = null
}

variable "install_dependencies" {
  description = "Run `bun install --frozen-lockfile` before building."
  type        = bool
  default     = true
}

variable "generated_dir" {
  description = "Directory for the rendered Wrangler config and the secrets file (written with 0600 permissions). Defaults to .terraform/larafeed/<worker> under the root module."
  type        = string
  default     = null
}
