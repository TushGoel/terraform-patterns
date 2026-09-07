# Remote State Bootstrap — S3 backend + DynamoDB state locking
#
# Run this ONCE per AWS account before any other Terraform.
# Creates the S3 bucket and DynamoDB table that all other configs use as backend.
#
# Why remote state matters:
#   - Local state means one engineer's laptop owns your infrastructure
#   - S3 backend + DynamoDB locking means concurrent applies are serialized
#   - State encryption means no sensitive values in plaintext
#
# Apply manually (not via CI/CD — chicken-and-egg):
#   terraform init && terraform apply
#
# Then configure other modules with:
#   terraform {
#     backend "s3" {
#       bucket         = "<state_bucket_name output>"
#       key            = "environments/prod/terraform.tfstate"
#       region         = "us-east-1"
#       dynamodb_table = "<lock_table_name output>"
#       encrypt        = true
#     }
#   }

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "state" {
  bucket        = "${var.project}-terraform-state-${var.account_id}"
  force_destroy = false

  tags = {
    Purpose = "terraform-state"
    Project = var.project
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB for state locking — prevents concurrent applies from corrupting state
resource "aws_dynamodb_table" "lock" {
  name         = "${var.project}-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Purpose = "terraform-state-lock"
    Project = var.project
  }
}
