terraform {
  backend "s3" {
    # bucket and endpoints come from backend.hcl (gitignored):
    #   terraform init -backend-config=backend.hcl
    key    = "02-bootstrap/terraform.tfstate"
    region = "us-east-1"

    # DigitalOcean Spaces is S3-compatible but is not AWS.
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = false
  }
}
