# Backends configuration for Terraform Cloud

# HCP Terraform Cloud backend configuration
# terraform {
#   cloud {
#     organization = "organization-elvislittle"
#     workspaces {
#       name = "workspace-aws"
#     }
#   }
# }

# S3 backend configuration (full (no partial) backend config here)
terraform {
  backend "s3" {
    bucket       = "terraform-aws-18092025"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

# Partial backend configuration (to be used with -backend-config option or environment-specific files)
# Usage options:
# 1. File:   terraform init -backend-config=dev.s3.tfbackend
# 2. Inline: terraform init -backend-config="bucket=my-bucket-name"
# terraform {
#   backend "s3" {
#     bucket       = ""
#     key          = "terraform.tfstate"
#     region       = "us-east-1"
#     use_lockfile = true
#   }
# }