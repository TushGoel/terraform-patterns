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

# Customer-managed key for state bucket + lock table — shared because both
# exist solely to support this same bootstrap, not because of a general rule.
resource "aws_kms_key" "state" {
  description         = "CMK for ${var.project} Terraform state bucket and lock table"
  enable_key_rotation = true

  tags = {
    Purpose = "terraform-state-encryption"
    Project = var.project
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "state" {
  bucket      = aws_s3_bucket.state.id
  eventbridge = true
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

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Purpose = "terraform-state-lock"
    Project = var.project
  }
}
