# Deploying Larafeed with Terraform
This guide deploys Larafeed to your own Cloudflare account with [Terraform](https://developer.hashicorp.com/terraform/intro). It assumes you have never used Terraform before. If you only want a one-click install, the **Deploy to Cloudflare** button in the [README](./README.md#deploy-to-cloudflare) is simpler; use Terraform when you want the deployment described in files you can review, repeat, and change later.

- [1. What gets deployed](#1-what-gets-deployed)
  
- [2. Terraform in five minutes](#2-terraform-in-five-minutes)
  
- [3. Prerequisites](#3-prerequisites)
  
- [4. Get your Cloudflare account ID](#4-get-your-cloudflare-account-id)
  
- [5. Create a Cloudflare API token](#5-create-a-cloudflare-api-token)
  
- [6. Decide where Terraform keeps its state](#6-decide-where-terraform-keeps-its-state)
  
- [7. Create your deployment directory](#7-create-your-deployment-directory)
  
- [8. Deploy](#8-deploy)
  
- [9. Create the first administrator](#9-create-the-first-administrator)
  
- [10. Verify the deployment](#10-verify-the-deployment)
  
- [11. Common configurations](#11-common-configurations)
  
- [12. Updating Larafeed](#12-updating-larafeed)
  
- [13. Day-to-day operations](#13-day-to-day-operations)
  
- [14. Adopting an existing deployment](#14-adopting-an-existing-deployment)
  
- [15. Tearing down](#15-tearing-down)
  
- [16. Troubleshooting](#16-troubleshooting)
  
- [17. Variable reference](#17-variable-reference)
  
- [18. References](#18-references)
  
## 1. What gets deployed
Larafeed is one Cloudflare Worker plus the services it uses. The Terraform module in `infra/terraform/modules/larafeed` sets all of it up.

| Cloudflare product | Name (with the default `name = "larafeed"`) | Created by |
| --- | --- | --- |
| [Worker](https://developers.cloudflare.com/workers/) with static assets | `larafeed` | Wrangler, run by Terraform |
| [D1 database](https://developers.cloudflare.com/d1/) | `larafeed` | Terraform |
| [Workers KV](https://developers.cloudflare.com/kv/) namespaces | `larafeed-full-content`, `larafeed-oauth` | Terraform |
| [Queues](https://developers.cloudflare.com/queues/) | `larafeed-feed-refresh`, `larafeed-opml-import`, `larafeed-favicon-refresh` | Terraform (consumers attached by Wrangler) |
| [Cron Trigger](https://developers.cloudflare.com/workers/configuration/cron-triggers/) | every 10 minutes | Wrangler |
| [Custom Domain](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/) | your hostname, optional | Wrangler |
| [Rate limiting bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) | auth and reader-client APIs | Wrangler |
| [AI Gateway](https://developers.cloudflare.com/ai-gateway/) | `larafeed`, optional | Terraform |
| [Turnstile](https://developers.cloudflare.com/turnstile/) widget | optional | Terraform |
| Operator secret | random 64-character value, unless you supply one | Terraform |

**Why two tools?** Terraform creates the long-lived resources (database, namespaces, queues). The Worker code itself is built and uploaded with [Wrangler](https://developers.cloudflare.com/workers/wrangler/), Cloudflare's official CLI, which is what the repository already uses. Terraform writes a Wrangler configuration file containing the IDs of the resources it just created, then runs the repository's normal build → migrate → deploy steps. You only ever run `terraform` commands; Terraform calls Wrangler for you.

The repository's `wrangler.jsonc` is never modified.
## 2. Terraform in five minutes
You need these concepts to follow the rest of the guide.

- **Configuration.** Terraform reads every `*.tf` file in the current directory. These files describe the infrastructure you _want_ to exist, not the steps to create it. ([Terraform language](https://developer.hashicorp.com/terraform/language))
  
- **Provider.** A plugin that talks to one platform's API. This deployment uses the [Cloudflare provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs), plus two small utility providers (`local` for writing files and `random` for generating the secret).
  
- **Module.** A reusable bundle of configuration. Larafeed ships one module; your deployment directory contains a short file that _calls_ it with your settings. ([Modules](https://developer.hashicorp.com/terraform/language/modules))
  
- **Variables.** The settings a module accepts, such as your hostname. You put your values in a `terraform.tfvars` file. ([Input variables](https://developer.hashicorp.com/terraform/language/values/variables))
  
- **Outputs.** Values the module reports back after deploying, such as the generated operator secret. ([Outputs](https://developer.hashicorp.com/terraform/language/values/outputs))
  
- **State.** After creating something, Terraform records it in a state file (`terraform.tfstate`) so it knows what it manages. **Do not delete or hand-edit this file.** Losing it means Terraform forgets your resources and will try to create duplicates. ([State](https://developer.hashicorp.com/terraform/language/state))
  
- **The workflow.** Almost everything is three commands:
  
  - `terraform init` downloads providers. Run it once per directory, and again if you change providers or the state location.
    
  - `terraform plan` shows what _would_ change, without changing anything.
    
  - `terraform apply` shows the plan again, asks you to type `yes`, then makes the changes.
    

Reading a plan: `+` means create, `~` means change in place, `-` means delete, and `-/+` means delete and re-create. Always read the plan before typing `yes`, and be especially careful with any `-` next to `cloudflare_d1_database`, because that deletes your data.
## 3. Prerequisites
You need a macOS or Linux machine (on Windows, use [WSL](https://learn.microsoft.com/windows/wsl/install)), because the deploy step runs a Bash script.

| Tool | Version | Install | Check |
| --- | --- | --- | --- |
| Terraform | 1.6 or newer | [Install Terraform](https://developer.hashicorp.com/terraform/install) | `terraform version` |
| Node.js | 24  | [Download Node.js](https://nodejs.org/en/download) | `node --version` |
| Bun | 1.3.14 | [Install Bun](https://bun.sh/docs/installation) | `bun --version` |
| Git | any | [Install Git](https://git-scm.com/downloads) | `git --version` |

[OpenTofu](https://opentofu.org/docs/intro/install/) 1.6+ also works: replace `terraform` with `tofu` in every command.

You also need:

- **A Cloudflare account.** [Sign up](https://dash.cloudflare.com/sign-up) if you don't have one. Check [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) and the [Queues](https://developers.cloudflare.com/queues/platform/pricing/), [D1](https://developers.cloudflare.com/d1/platform/pricing/), and [Workers AI](https://developers.cloudflare.com/workers-ai/platform/pricing/) pricing pages for your expected usage.
  
- **A domain on Cloudflare (optional).** To serve Larafeed from your own hostname such as `reader.example.com`, the domain's zone must be [added to the same Cloudflare account](https://developers.cloudflare.com/fundamentals/manage-domains/add-site/). Without a domain, Larafeed is served from a `*.workers.dev` address.
  
- **A copy of the repository:**
  
  ```bash
  git clone https://github.com/angristan/larafeed.git
  cd larafeed
  ```
  

Every command in this guide is run from the repository root unless it says otherwise.
## 4. Get your Cloudflare account ID
1. Log in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
  
2. Open **Account home**, then select the **⋯** menu next to your account name and choose **Copy account ID**. Alternatively, open any zone's **Overview** page; the account ID is in the **API** section on the right.
  

It is a 32-character hex string such as `0123456789abcdef0123456789abcdef`. See [Find account and zone IDs](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/).
### workers.dev subdomain
If you will serve Larafeed from `workers.dev` rather than your own domain, your account needs a workers.dev subdomain. Open **Workers & Pages** in the dashboard once; it prompts you to choose one if you haven't. Your URL will be `https://<worker name>.<your subdomain>.workers.dev`. See [workers.dev](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/).
## 5. Create a Cloudflare API token
Terraform and Wrangler both authenticate with one [API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

1. Open [**My Profile → API Tokens**](https://dash.cloudflare.com/profile/api-tokens) and select **Create Token**.
  
2. Choose **Create Custom Token**.
  
3. Name it, for example `larafeed-terraform`.
  
4. Add these permissions:
  
  | Scope | Permission | Access | Needed for |
  | --- | --- | --- | --- |
  | Account | Workers Scripts | Edit | Deploying the Worker |
  | Account | D1  | Edit | Database and migrations |
  | Account | Workers KV Storage | Edit | KV namespaces |
  | Account | Queues | Edit | Queues and consumers |
  | Account | AI Gateway | Edit | Only if AI summaries are enabled |
  | Account | Turnstile | Edit | Only if Turnstile is enabled |
  | Account | Account Settings | Read | Wrangler account lookups |
  | Zone | Workers Routes | Edit | Only with a custom domain |
  | Zone | DNS | Edit | Only with a custom domain |
  | Zone | SSL and Certificates | Edit | Only with a custom domain |
  
5. Under **Account Resources**, select your account. Under **Zone Resources**, select the zone that holds your hostname (or **All zones from an account**).
  
6. Select **Continue to summary**, then **Create Token**. Copy the token now; Cloudflare shows it only once. Store it in a password manager.
  
### Make the token available to your shell
Both tools read the token from the `CLOUDFLARE_API_TOKEN` environment variable. To set it without the value landing in your shell history:

```bash
read -rs CLOUDFLARE_API_TOKEN && export CLOUDFLARE_API_TOKEN
# paste the token, press Enter (nothing is echoed)
```

This lasts only for the current terminal session. Repeat it in each new terminal, or load it from your password manager's CLI (for example [1Password's](https://developer.1password.com/docs/cli/secrets-environment-variables/) `op run`).

Never write the token into a `.tf` or `.tfvars` file.
## 6. Decide where Terraform keeps its state
By default Terraform writes `terraform.tfstate` next to your configuration. That is fine for trying things out, but understand two things first:

- **The state contains secrets.** It holds the operator secret and, if enabled, the Turnstile secret key, in plain text. See [Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data).
  
- **The state is the only record of what Terraform manages.** If it is lost, you will have to [import](#14-adopting-an-existing-deployment) every resource again.
  

Choose one:

**Option A: local state (simplest).** Keep the default. Back up `terraform.tfstate` somewhere private after every `apply`, and never commit it (the repository's `infra/terraform/.gitignore` already excludes it).

**Option B: remote state in Cloudflare R2 (recommended for anything long-lived).** R2 is S3-compatible, so Terraform's `s3` [backend](https://developer.hashicorp.com/terraform/language/backend/s3) can store state there.

1. Create a bucket, for example `larafeed-tfstate`, under **R2 Object Storage** in the dashboard.
  
2. Under **R2 → Manage API tokens**, create a token with **Object Read & Write** on that bucket. Note its **Access Key ID** and **Secret Access Key**.
  
3. In your deployment directory (`infra/terraform/deployments/reader/`, created in the [next section](#7-create-your-deployment-directory)), add a file `backend.tf`. **Replace `<ACCOUNT_ID>` with your real account ID** from [section 4](#4-get-your-cloudflare-account-id), for example `https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com`. Type it in literally: Terraform doesn't allow variables in a `backend` block, so `var.account_id` won't work here.
  
  ```hcl
  terraform {
    backend "s3" {
      bucket = "larafeed-tfstate"
      key    = "larafeed/terraform.tfstate"
      region = "auto"
  
      endpoints = {
        s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
      }
  
      skip_credentials_validation = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      skip_metadata_api_check     = true
      skip_s3_checksum            = true
      use_path_style              = true
      use_lockfile                = true # needs Terraform 1.10+; remove for older versions
    }
  }
  ```
  
4. Before `terraform init`, export the R2 credentials the same way as the API token:
  
  ```bash
  read -rs AWS_ACCESS_KEY_ID && export AWS_ACCESS_KEY_ID
  read -rs AWS_SECRET_ACCESS_KEY && export AWS_SECRET_ACCESS_KEY
  ```
  

See Cloudflare's [remote R2 backend guide](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/). [HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs) is another option, but its remote runners don't have Bun installed, so you would need to use its [local execution mode](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings#execution-mode).
## 7. Create your deployment directory
The deployment directory is the folder that holds _your_ deployment's files: your settings, your backend configuration and (with local state) your state. The Larafeed module in `infra/terraform/modules/larafeed` is shared code you don't edit; your deployment directory calls it. Keeping the two separate means updating the repository never overwrites your settings.

```bash
mkdir -p infra/terraform/deployments/reader
cd infra/terraform/deployments/reader
```

The directory must be exactly two levels below `infra/terraform`, because the configuration below refers to the module as `../../modules/larafeed`. You can choose any name instead of `reader`.

When you finish this section it contains:

```
infra/terraform/deployments/reader/
├── main.tf            # providers, variables, and the call to the module
├── backend.tf         # only if you chose remote state (section 6, option B)
└── terraform.tfvars   # your values; ignored by Git
```

Run every `terraform` command from inside this directory. Terraform also creates `.terraform/`, `.terraform.lock.hcl` and (with local state) `terraform.tfstate` here.
### `main.tf`
Create `main.tf` with this content. It declares the providers, the settings you'll fill in, and one call to the Larafeed module.

```hcl
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
```
### `terraform.tfvars`
Create `terraform.tfvars` in the deployment directory, next to `main.tf` (not in the repository root or the module directory):

```bash
touch infra/terraform/deployments/reader/terraform.tfvars   # from the repository root
```

Fill it with your values. Terraform loads this file automatically. It is excluded from Git by `infra/terraform/.gitignore` (`*.tfvars`), which you can confirm with `git check-ignore -v terraform.tfvars`.

**With your own domain:**

```hcl
account_id = "0123456789abcdef0123456789abcdef"
name       = "larafeed"
hostname   = "reader.example.com"
```

**With workers.dev only:**

```hcl
account_id            = "0123456789abcdef0123456789abcdef"
name                  = "larafeed"
workers_dev_subdomain = "my-subdomain"
```
### Choosing `name`
`name` is the prefix for the Worker, D1 database, KV namespaces, Queues, and AI Gateway. These names must be unique **within your account**. Before deploying, check **Workers & Pages**, **D1**, **KV**, and **Queues** in the dashboard for anything already called `larafeed…` (for example, from an earlier Deploy-button install).

Most collisions make `terraform apply` fail safely. **The Worker name is the exception:** deploying a Worker whose name already exists silently replaces that Worker. Pick a fresh `name` if in doubt, or follow [section 14](#14-adopting-an-existing-deployment) to adopt the existing deployment.
## 8. Deploy
Make sure `CLOUDFLARE_API_TOKEN` is exported in this terminal (see [section 5](#make-the-token-available-to-your-shell)), then from your deployment directory:
### 8.1 Initialize
```bash
terraform init
```

This downloads the Cloudflare, local, and random providers into a `.terraform/` directory and creates `.terraform.lock.hcl`, which pins the exact provider versions. Expected ending: `Terraform has been successfully initialized!`
### 8.2 Validate (optional)
```bash
terraform validate
```

Catches typos in your `.tf` files. Expected: `Success! The configuration is valid.`
### 8.3 Review the plan
```bash
terraform plan
```

On a first deployment you should see about 11 resources to add (more if Turnstile is enabled), including `cloudflare_d1_database.main`, two `cloudflare_workers_kv_namespace` resources, three `cloudflare_queue` resources, and `terraform_data.deploy`. Nothing should be changed or destroyed.
### 8.4 Apply
```bash
terraform apply
```

Terraform prints the plan again and asks `Do you want to perform these actions?`. Type `yes`.

What happens next, in order:

1. Terraform creates the D1 database, KV namespaces, Queues, and any optional resources.
  
2. It writes the generated Wrangler config and a secrets file to `.terraform/larafeed/<worker name>/` inside your deployment directory. The secrets file is readable only by your user.
  
3. It runs `scripts/deploy.sh`, which, from the repository root:
  
  1. installs dependencies with `bun install --frozen-lockfile`,
    
  2. builds the app with Vite,
    
  3. runs `wrangler deploy --dry-run` to check the build,
    
  4. applies every pending [D1 migration](https://developers.cloudflare.com/d1/reference/migrations/),
    
  5. deploys the Worker and uploads its secrets.
    

The build output scrolls past in your terminal; a first run takes a few minutes. When it finishes you'll see `Apply complete!` followed by the outputs. A custom domain's TLS certificate can take a few more minutes to be issued.
## 9. Create the first administrator
Larafeed uses passkeys only, so the first administrator is created through a one-time enrollment link signed with the operator secret.

1. Print the operator secret and copy it (this displays it on screen):
  
  ```bash
  terraform output -raw auth_operator_secret; echo
  ```
  
  Store it in your password manager. You'll need it again to recover administrator access.
  
2. Print the enrollment command:
  
  ```bash
  terraform output -raw initial_admin_command; echo
  ```
  
3. Go back to the repository root, then run that command **after replacing** the example username, email, and display name with your own:
  
  ```bash
  cd ../../../..
  bun run auth:access-link -- \
    --url https://reader.example.com/api/auth/operator/access-link \
    --mode initial-admin \
    --username alex \
    --email alex@example.com \
    --display-name "Alex"
  ```
  
4. Paste the operator secret when prompted. Input is hidden.
  
5. Open the printed URL in your browser and register a passkey. The link expires after 30 minutes.
  

Recovery and inviting more users are covered in [docs/deployment.md](./docs/deployment.md#create-the-first-administrator).
## 10. Verify the deployment
Replace the hostname with yours:

```bash
curl -fsS https://reader.example.com/up
curl -fsS https://reader.example.com/api/health
```

Both should succeed. Then sign in and open `/settings/opml` to import your subscriptions.

Unlike the Deploy-button install, you don't need to enable [D1 read replication](https://developers.cloudflare.com/d1/best-practices/read-replication/) by hand; the module turns it on (`d1_read_replication = true`).
## 11. Common configurations
Settings go inside the `module "larafeed" { ... }` block in your `main.tf`. After any change, run `terraform plan` to see the effect, then `terraform apply`. Object-type settings accept only the fields you want to change; the rest keep their defaults.
### Minimal: no AI, no images
```hcl
module "larafeed" {
  source = "../../modules/larafeed"

  account_id     = var.account_id
  name           = var.name
  auth_origin    = "https://${local.origin_host}"
  custom_domains = var.hostname != null ? [var.hostname] : []
}
```
### AI summaries
Uses [Workers AI](https://developers.cloudflare.com/workers-ai/) through an [AI Gateway](https://developers.cloudflare.com/ai-gateway/) created by the module.

```hcl
  ai_summary = {
    enabled      = true
    model        = "@cf/mistralai/mistral-small-3.1-24b-instruct"
    collect_logs = false
  }
```

To use a gateway you already have instead of creating one:

```hcl
  ai_summary = {
    enabled        = true
    gateway_name   = "my-existing-gateway"
    create_gateway = false
  }
```
### Turnstile on sign-in
The module creates a [Turnstile](https://developers.cloudflare.com/turnstile/) widget bound to your hostname:

```hcl
  turnstile = {
    enabled = true
  }
```

To use an existing widget, pass its keys. Keep the secret key out of `main.tf`: declare a variable and set it through the environment.

```hcl
variable "turnstile_secret_key" {
  type      = string
  sensitive = true
}

module "larafeed" {
  # ...
  turnstile = {
    enabled  = true
    site_key = "0x4AAAAAAA..."
  }
  turnstile_secret_key = var.turnstile_secret_key
}
```

```bash
read -rs TF_VAR_turnstile_secret_key && export TF_VAR_turnstile_secret_key
```

Any variable can be set with a `TF_VAR_<name>` environment variable. See [Assigning values to variables](https://developer.hashicorp.com/terraform/language/values/variables#assigning-values-to-root-module-variables).
### Your own operator secret
By default the module generates one. To supply your own (for example, one already stored in a password manager), generate it with `openssl rand -hex 32`, then:

```hcl
variable "auth_operator_secret" {
  type      = string
  sensitive = true
}

module "larafeed" {
  # ...
  auth_operator_secret = var.auth_operator_secret
}
```

```bash
read -rs TF_VAR_auth_operator_secret && export TF_VAR_auth_operator_secret
```
### More refresh capacity
```hcl
  cron_schedules    = ["*/5 * * * *"]
  refresh_due_limit = 10

  queue_consumers = {
    feed_refresh = { max_concurrency = 3 }
  }
```
### Database location
Place the D1 primary near you with a [location hint](https://developers.cloudflare.com/d1/configuration/data-location/). This only takes effect when the database is first created; changing it later re-creates the database and **deletes its data**.

```hcl
  d1_primary_location_hint = "weur"
```
### Several instances in one account
Each instance needs its own deployment directory (and so its own state), a distinct `name`, a distinct hostname, and distinct rate-limit namespace IDs. Rate-limit IDs that collide don't cause an error; the two instances silently share counters.

```hcl
  name = "larafeed-staging"

  auth_rate_limit   = { namespace_id = "9101" }
  compat_rate_limit = { namespace_id = "9102" }
```
## 12. Updating Larafeed
To deploy a newer version of the code:

```bash
cd larafeed                       # repository root
git pull
cd infra/terraform/deployments/reader
terraform plan                    # expect terraform_data.deploy to be replaced
terraform apply
```

Terraform hashes the application sources (`src/`, `migrations/`, `public/`, `package.json`, `bun.lock`, and a few build files). When they change, it re-runs the deploy script, which applies any new migrations before deploying the new code. The same happens when you change a setting or a secret.

Read the plan carefully after a `git pull`: if the module itself changed, the plan may include changes to Cloudflare resources as well.
### In CI
Hashing every source file is slower than necessary in automated pipelines. Pass the commit SHA instead:

```hcl
  source_version = var.git_sha
```

```bash
terraform apply -auto-approve -var "git_sha=$(git rev-parse HEAD)"
```

`-auto-approve` skips the `yes` prompt. Use it only in automation that already reviewed a plan. See [Running Terraform in automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform). The CI runner needs Node.js, Bun, and the repository checkout.
### Upgrading the Cloudflare provider
`.terraform.lock.hcl` pins the provider version. To move to the newest 5.x release:

```bash
terraform init -upgrade
terraform plan
```
## 13. Day-to-day operations
### Read outputs
```bash
terraform output                        # everything except sensitive values
terraform output -raw worker_name
terraform output -raw auth_operator_secret
```
### Use Wrangler directly
The generated Wrangler config works with any Wrangler command. From the repository root:

```bash
CONFIG="$(terraform -chdir=infra/terraform/deployments/reader output -raw wrangler_config_path)"

bunx wrangler tail "$(terraform -chdir=infra/terraform/deployments/reader output -raw worker_name)"   # live logs
bunx wrangler d1 migrations list DB --remote --config "$CONFIG"
bunx wrangler d1 export DB --remote --config "$CONFIG" --output backup.sql
```

Don't change resources that Terraform manages (database, namespaces, queues, Worker settings) through the dashboard or Wrangler; the next `terraform apply` will revert them or fail. Change them in `main.tf` instead. Logs, metrics, and data are fine to inspect anywhere.
### Rotate the operator secret
If the module generated it, force a new one:

```bash
terraform apply -replace='module.larafeed.random_password.operator_secret[0]'
```

If you supply it yourself, change `TF_VAR_auth_operator_secret` and run `terraform apply`. Either way, the Worker is redeployed with the new value and the old one stops working.
### Provision without deploying
Set `deploy_worker = false` to have Terraform create the resources and write the Wrangler config, without building or deploying. You can then deploy with Wrangler yourself, from the repository root:

```bash
export LARAFEED_WRANGLER_CONFIG="$CONFIG"
bun run build
bunx wrangler d1 migrations apply DB --remote --config "$CONFIG"
bunx wrangler deploy --secrets-file "$(dirname "$CONFIG")/secrets.json"
```
## 14. Adopting an existing deployment
If you already run Larafeed (for example, from the Deploy button or the manual steps in [docs/deployment.md](./docs/deployment.md)) and want Terraform to manage it without losing data, tell Terraform about the existing resources with [import blocks](https://developer.hashicorp.com/terraform/language/import) **before** the first `apply`.

1. Set `name` so that the module's names match your existing resources. For a Deploy-button install this is usually `larafeed-template`; check the names in the dashboard.
  
2. Find the IDs: `bunx wrangler d1 list`, `bunx wrangler kv namespace list`, and `bunx wrangler queues list`.
  
3. Create `imports.tf` in your deployment directory:
  
  ```hcl
  import {
    to = module.larafeed.cloudflare_d1_database.main
    id = "<ACCOUNT_ID>/<D1_DATABASE_ID>"
  }
  
  import {
    to = module.larafeed.cloudflare_workers_kv_namespace.full_content
    id = "<ACCOUNT_ID>/<FULL_CONTENT_KV_ID>"
  }
  
  import {
    to = module.larafeed.cloudflare_workers_kv_namespace.oauth
    id = "<ACCOUNT_ID>/<OAUTH_KV_ID>"
  }
  
  import {
    to = module.larafeed.cloudflare_queue.this["feed_refresh"]
    id = "<ACCOUNT_ID>/<FEED_REFRESH_QUEUE_ID>"
  }
  
  import {
    to = module.larafeed.cloudflare_queue.this["opml_import"]
    id = "<ACCOUNT_ID>/<OPML_IMPORT_QUEUE_ID>"
  }
  
  import {
    to = module.larafeed.cloudflare_queue.this["favicon_refresh"]
    id = "<ACCOUNT_ID>/<FAVICON_REFRESH_QUEUE_ID>"
  }
  ```
  
  The expected ID format for each resource is listed under **Import** at the bottom of its page in the provider docs: [D1 database](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/d1_database#import), [KV namespace](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/workers_kv_namespace#import), [Queue](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/queue#import).
  
4. Supply your existing operator secret as shown in [section 11](#your-own-operator-secret), otherwise a new one is generated and replaces it.
  
5. Run `terraform plan`. The resources should show as `will be imported` with no `-` (destroy) or `-/+` (replace). If a database shows as replaced, **stop**: a setting such as `name` or `d1_primary_location_hint` doesn't match, and applying would delete it.
  
6. Run `terraform apply`. The Worker is redeployed in place under the same name, keeping its data. You can delete `imports.tf` afterwards.
  
## 15. Tearing down
**This permanently deletes the database and every feed, entry, and user in it.** Export the data first, from the repository root (`CONFIG` is set as in [section 13](#use-wrangler-directly)):

```bash
bunx wrangler d1 export DB --remote --config "$CONFIG" --output larafeed-backup.sql
```

Then, from your deployment directory:

```bash
terraform destroy
```

Terraform lists everything it will delete and asks you to type `yes`. It deletes the Worker first (so the Queues are released), then the Queues, KV namespaces, D1 database, and optional resources. See `terraform destroy`.

To protect the database against accidental deletion, you can apply a `prevent_destroy` lifecycle rule in a fork of the module.
## 16. Troubleshooting
`Error: ... Authentication error` **or** `403` **from Cloudflare.** `CLOUDFLARE_API_TOKEN` isn't exported in this terminal, or the token is missing a permission from [section 5](#5-create-a-cloudflare-api-token). Check the token with:

```bash
curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
```

`... already exists` **while creating a D1 database, KV namespace, Queue, or AI Gateway.** A resource with that name is already in the account. Choose a different `name`, or adopt the existing resource ([section 14](#14-adopting-an-existing-deployment)).

`bun: command not found` **or** `bunx: command not found` **during apply.** Bun isn't on the `PATH` of the shell that runs Terraform. Open a new terminal after installing Bun, or add `~/.bun/bin` to your `PATH`.

**The deploy step fails at the custom domain.** The hostname's zone must be in the same account and the token needs the zone permissions. If the hostname already has a DNS record or is attached to another Worker, remove that record or attachment first. See [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/).

**The deploy step failed partway.** Fix the cause and run `terraform apply` again. The deploy step is marked as not completed, so Terraform retries it; migrations that already ran are skipped.

`terraform plan` **always shows** `terraform_data.deploy` **being replaced.** Something in the source tree changes between runs, such as an editor rewriting files under `src/`. Pin `source_version` to a commit SHA ([section 12](#in-ci)).

`Failed to get existing workspaces: Unable to list objects in S3 bucket ... tls: handshake failure` **during** `terraform init`**.** The `endpoints.s3` URL in `backend.tf` still contains the literal `<ACCOUNT_ID>` placeholder, so Terraform is connecting to a host that doesn't exist. Replace it with your 32-character account ID ([section 6, option B](#6-decide-where-terraform-keeps-its-state)) and run `terraform init` again. If the URL is correct, check that `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are exported with your R2 token's keys (not the Cloudflare API token) and that the bucket exists in that account.

`Error acquiring the state lock`**.** Another `terraform` command is running against the same state, or a previous one crashed. Wait, or if you are sure nothing is running, use `terraform force-unlock` with the lock ID from the error.

**Rate limits behave oddly across two instances.** They share a rate-limit `namespace_id`. Give each instance distinct values ([section 11](#several-instances-in-one-account)).

**Passkey registration fails with an origin error.** The `auth_origin` must exactly match the URL in your browser's address bar: `https`, no trailing slash, no path, and the same hostname.
## 17. Variable reference
Only `account_id` and `auth_origin` are required. Object-type variables accept any subset of their fields.
### Account and naming
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `account_id` | string | required | Cloudflare account ID |
| `name` | string | `"larafeed"` | Prefix for the Worker, D1 database, KV namespaces, Queues, and AI Gateway. 2–42 lowercase letters, digits, or hyphens |
| `worker_name` | string | value of `name` | Overrides only the Worker name |
### Origin and routing
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `auth_origin` | string | required | Exact public origin, such as `https://reader.example.com`. The passkey relying-party ID is derived from it |
| `custom_domains` | list(string) | `[]` | Hostnames attached as [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/) |
| `workers_dev` | bool | `true` when `custom_domains` is empty | Serve on workers.dev |
| `preview_urls` | bool | `false` | Enable [preview URLs](https://developers.cloudflare.com/workers/configuration/previews/) |
### Runtime
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `compatibility_date` | string | `"2026-07-18"` | [Compatibility date](https://developers.cloudflare.com/workers/configuration/compatibility-dates/) |
| `smart_placement` | bool | `true` | [Smart Placement](https://developers.cloudflare.com/workers/configuration/placement/) |
| `cron_schedules` | list(string) | `["*/10 * * * *"]` | Refresh scheduler [cron expressions](https://developers.cloudflare.com/workers/configuration/cron-triggers/#supported-cron-expressions) |
| `observability` | object | all enabled, sampling `1` | Fields: `enabled`, `logs_head_sampling_rate`, `traces_enabled`, `traces_head_sampling_rate`. See [Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/) |
### Authentication
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `auth_operator_secret` | string, sensitive | generated | Signs administrator enrollment links |
| `auth_rp_name` | string | `"Larafeed"` | Name shown in passkey prompts |
| `auth_challenge_ttl_seconds` | number | `300` | Passkey challenge lifetime |
| `auth_session_ttl_seconds` | number | `2592000` (30 days) | Session lifetime |
| `auth_rate_limit` | object | `{ namespace_id = "9001", limit = 20, period = 60 }` | Sign-in endpoints. `period` must be `10` or `60` |
| `compat_rate_limit` | object | `{ namespace_id = "9002", limit = 300, period = 60 }` | Google Reader and Fever APIs. `period` must be `10` or `60` |
| `turnstile` | object | `{ enabled = false, site_key = null, mode = "managed" }` | Without a `site_key`, the module creates the widget |
| `turnstile_secret_key` | string, sensitive | `null` | Required only with your own `site_key` |
### Features
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `full_content_enabled` | bool | `true` | Full-article extraction |
| `opml_import_enabled` | bool | `true` | OPML import |
| `refresh_scheduler_enabled` | bool | `true` | Scheduled feed refreshes |
| `refresh_dispatch_enabled` | bool | `true` | Send refresh jobs to the Queue |
| `refresh_due_limit` | number | `5` | Feeds dispatched per cron run |
| `images_enabled` | bool | `false` | Article image transforms with [Cloudflare Images](https://developers.cloudflare.com/images/) |
| `favicon_refresh_enabled` | bool | `false` | Favicon discovery |
| `ai_summary` | object | disabled | Fields: `enabled`, `model` (default `@cf/mistralai/mistral-small-3.1-24b-instruct`), `gateway_name` (default `name`), `create_gateway` (`true`), `collect_logs` (`false`), `cache_ttl` (`0`), `rate_limiting_limit` (`0`), `rate_limiting_interval` (`0`), `rate_limiting_technique` (`"fixed"`) |
### Storage and Queues
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `d1_primary_location_hint` | string | `null` | `wnam`, `enam`, `weur`, `eeur`, `apac`, or `oc`. Changing it re-creates the database |
| `d1_read_replication` | bool | `true` | [D1 read replication](https://developers.cloudflare.com/d1/best-practices/read-replication/) |
| `queue_consumers` | object | see description | Keys `feed_refresh`, `opml_import`, `favicon_refresh`; each takes `max_batch_size` (`1`), `max_batch_timeout` (`1`), `max_retries` (`5`), `max_concurrency` (`2` for feed refresh, otherwise `1`). See [consumer settings](https://developers.cloudflare.com/queues/configuration/configure-queues/#consumer) |
### Build and deploy
| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `deploy_worker` | bool | `true` | When `false`, only create resources and write the Wrangler config |
| `source_dir` | string | repository root | Path to the Larafeed checkout |
| `source_version` | string | `null` | Redeploy trigger such as a commit SHA; when `null`, the sources are hashed |
| `install_dependencies` | bool | `true` | Run `bun install --frozen-lockfile` before building |
| `generated_dir` | string | `.terraform/larafeed/<worker>` in your deployment directory | Where the Wrangler config and `secrets.json` are written |
### Outputs
| Output | Description |
| --- | --- |
| `worker_name` | Deployed Worker name |
| `url` | Public origin |
| `d1_database_id`, `d1_database_name` | D1 database |
| `kv_namespace_ids` | KV namespace IDs by binding name |
| `queue_names` | Queue names by purpose |
| `ai_gateway_name` | AI Gateway, or `null` when summaries are off |
| `turnstile_site_key` | Turnstile site key, or `null` when disabled |
| `wrangler_config_path` | Generated Wrangler config |
| `auth_operator_secret` | Operator secret (sensitive) |
| `initial_admin_command` | Template command for creating the first administrator |

Your deployment's `main.tf` re-exports only some of these. To read another, add an `output` block, for example `output "queue_names" { value = module.larafeed.queue_names }`.
## 18. References
**Terraform**

- [What is Terraform?](https://developer.hashicorp.com/terraform/intro)
  
- [Get started tutorials](https://developer.hashicorp.com/terraform/tutorials)
  
- [Install Terraform](https://developer.hashicorp.com/terraform/install)
  
- [CLI commands](https://developer.hashicorp.com/terraform/cli/commands)
  
- [Input variables](https://developer.hashicorp.com/terraform/language/values/variables)
  
- [State](https://developer.hashicorp.com/terraform/language/state) and [sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data)
  
- [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
  
- [Import blocks](https://developer.hashicorp.com/terraform/language/import)
  

**Cloudflare**

- [Cloudflare Terraform provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
  
- [Terraform on Cloudflare](https://developers.cloudflare.com/terraform/)
  
- [Remote R2 backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
  
- [Create an API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
  
- [Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/)
  
- [Workers](https://developers.cloudflare.com/workers/), [D1](https://developers.cloudflare.com/d1/), [Workers KV](https://developers.cloudflare.com/kv/), [Queues](https://developers.cloudflare.com/queues/), [AI Gateway](https://developers.cloudflare.com/ai-gateway/), [Turnstile](https://developers.cloudflare.com/turnstile/)
  

**Larafeed**

- [Module source](./infra/terraform/modules/larafeed) and [module README](./infra/terraform/modules/larafeed/README.md)
  
- [Example root module](./infra/terraform/examples/basic)
  
- [Deployment guide](./docs/deployment.md), [operations guide](./docs/operations.md), [compatibility APIs](./docs/compatibility-apis.md), [MCP](./docs/mcp.md)
