# State dans Garage (S3), config partielle : bucket, key, endpoint et credentials dans backend.hcl (gitignoré)
#   terraform init -backend-config=backend.hcl
# Workspace prod => objet home-lab-talos/prod/terraform.tfstate (workspace_key_prefix = "home-lab-talos", key = "terraform.tfstate")
# Toujours travailler dans le workspace prod : le workspace default écrirait à la racine du bucket
terraform {
  backend "s3" {
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true
  }
}
