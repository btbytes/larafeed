terraform {
  backend "s3" {
    bucket = "larafeed-tfstate"
    key    = "larafeed/terraform.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://c73bb63a5f11d0117a15a149fe3e131f.r2.cloudflarestorage.com"
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
