output "worker_name" {
  description = "Deployed Worker script name."
  value       = local.worker_name
}

output "url" {
  description = "Public origin of the deployment."
  value       = var.auth_origin
}

output "d1_database_id" {
  description = "D1 database ID."
  value       = cloudflare_d1_database.main.id
}

output "d1_database_name" {
  description = "D1 database name."
  value       = cloudflare_d1_database.main.name
}

output "kv_namespace_ids" {
  description = "KV namespace IDs by binding."
  value = {
    FULL_CONTENT_KV = cloudflare_workers_kv_namespace.full_content.id
    OAUTH_KV        = cloudflare_workers_kv_namespace.oauth.id
  }
}

output "queue_names" {
  description = "Queue names by purpose."
  value       = { for key, queue in cloudflare_queue.this : key => queue.queue_name }
}

output "ai_gateway_name" {
  description = "AI Gateway used for summaries, or null when summaries are disabled."
  value       = var.ai_summary.enabled ? local.ai_gateway_name : null
}

output "turnstile_site_key" {
  description = "Turnstile site key, or null when Turnstile is disabled."
  value       = var.turnstile.enabled ? local.turnstile_site_key : null
}

output "wrangler_config_path" {
  description = "Rendered Wrangler config. Pass it to wrangler with --config for manual operations."
  value       = local_file.wrangler_config.filename
}

output "auth_operator_secret" {
  description = "Operator secret for `bun run auth:access-link`."
  value       = local.auth_operator_secret
  sensitive   = true
}

output "initial_admin_command" {
  description = "Command that creates the first administrator enrollment link."
  value       = "bun run auth:access-link -- --url ${var.auth_origin}/api/auth/operator/access-link --mode initial-admin --username admin --email admin@example.com --display-name Admin"
}
