# Larafeed Terraform module

Deploys Larafeed to a Cloudflare account. The setup has two parts.

- **Terraform** creates the D1 database (with read replication), both KV namespaces, all three Queues, and, if enabled, the AI Gateway and Turnstile widget. It also generates the operator secret when you don't supply one.
- **Wrangler** builds, migrates, and deploys the Worker from a config that Terraform renders with the real resource IDs. Wrangler attaches Queue consumers, Cron Triggers, Custom Domains, rate limits, static assets, and secrets. The repository's own build and migration tooling stays the single deploy path.

`wrangler.jsonc` is never edited. The build reads the rendered config through the `LARAFEED_WRANGLER_CONFIG` variable in `vite.config.ts`.

## Requirements

- Terraform 1.6 or later
- Node.js 24 and Bun 1.3.14 on the machine that runs `terraform apply`
- `CLOUDFLARE_API_TOKEN` exported. The provider and Wrangler both read it. It needs these Account permissions: Workers Scripts, D1, Workers KV Storage, Queues, AI Gateway, and Turnstile, all with Edit, plus Account Settings Read. For each custom domain zone it also needs Workers Routes Edit, DNS Edit, and SSL and Certificates Edit.

## Usage

```hcl
module "larafeed" {
  source = "./infra/terraform/modules/larafeed"

  account_id     = "0123456789abcdef0123456789abcdef"
  name           = "larafeed"
  auth_origin    = "https://reader.example.com"
  custom_domains = ["reader.example.com"]

  images_enabled          = true
  favicon_refresh_enabled = true
  ai_summary              = { enabled = true }
}
```

A complete root module is in [`examples/basic`](../../examples/basic).

```bash
export CLOUDFLARE_API_TOKEN=...   # from your secret store
cd infra/terraform/examples/basic
cp terraform.tfvars.example terraform.tfvars   # then edit it
terraform init
terraform apply
```

Then create the first administrator:

```bash
terraform output -raw auth_operator_secret   # paste this when the script prompts for it
cd ../../../..
$(terraform -chdir=infra/terraform/examples/basic output -raw initial_admin_command)
```

## Redeploys

The deploy step runs again when the rendered config changes, when a secret changes, or when the application sources change (`src/`, `migrations/`, `public/`, `package.json`, `bun.lock`, and so on). In CI, pass `source_version = "<git sha>"` to skip hashing the source files.

Set `deploy_worker = false` to have Terraform create only the resources and render the config. You can then deploy yourself:

```bash
LARAFEED_WRANGLER_CONFIG="$(terraform output -raw wrangler_config_path)" bun run build
bunx wrangler d1 migrations apply DB --remote --config "$(terraform output -raw wrangler_config_path)"
bunx wrangler deploy
```

## Inputs

| Name | Default | Description |
| --- | --- | --- |
| `account_id` | required | Cloudflare account ID |
| `auth_origin` | required | Exact public HTTPS origin, with no trailing slash |
| `name` | `larafeed` | Prefix for the Worker, D1 database, KV namespaces, and Queues |
| `worker_name` | `name` | Worker script name |
| `custom_domains` | `[]` | Workers Custom Domains. When empty, the Worker is served from workers.dev |
| `workers_dev` / `preview_urls` | auto / `false` | URL exposure |
| `auth_operator_secret` | generated | Operator secret for enrollment links |
| `auth_rp_name`, `auth_*_ttl_seconds` | template values | Passkey settings |
| `auth_rate_limit`, `compat_rate_limit` | 20/60s, 300/60s | `namespace_id` must be unique within the account |
| `turnstile`, `turnstile_secret_key` | disabled | When enabled without a `site_key`, the module creates the widget |
| `ai_summary` | disabled | Model, gateway name, and gateway settings. Set `create_gateway = false` to use an existing gateway |
| `images_enabled`, `favicon_refresh_enabled` | `false` | Cloudflare Images features |
| `full_content_enabled`, `opml_import_enabled` | `true` | Feature flags |
| `refresh_scheduler_enabled`, `refresh_dispatch_enabled`, `refresh_due_limit` | `true`, `true`, `5` | Feed refresh controls |
| `cron_schedules` | `["*/10 * * * *"]` | Scheduler cadence |
| `queue_consumers` | template values | Batch size, timeout, retries, and concurrency for each Queue |
| `d1_primary_location_hint`, `d1_read_replication` | `null`, `true` | D1 placement and replication |
| `compatibility_date`, `smart_placement`, `observability` | template values | Runtime settings |
| `deploy_worker`, `install_dependencies`, `source_dir`, `source_version`, `generated_dir` | | Build and deploy controls |

## Outputs

`worker_name`, `url`, `d1_database_id`, `d1_database_name`, `kv_namespace_ids`, `queue_names`, `ai_gateway_name`, `turnstile_site_key`, `wrangler_config_path`, `auth_operator_secret` (sensitive), and `initial_admin_command`.

## Notes

- Secrets end up in Terraform state and in `secrets.json` (mode 0600) inside `generated_dir`. Use an encrypted remote backend.
- `terraform destroy` deletes the Worker first, then the D1 database and all of its data. If you need to keep the data, export it first with `wrangler d1 export`.
