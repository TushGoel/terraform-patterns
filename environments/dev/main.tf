# Dev environment — same modules as prod, reduced capacity and cost
#
# Key differences from prod:
# - Single AZ (saves NAT gateway cost ~$32/month)
# - No SageMaker autoscaling
# - Shorter lifecycle retention
# - No KMS encryption (SSE-S3 sufficient for dev)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "REPLACE_WITH_STATE_BUCKET"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_LOCK_TABLE"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "${var.project}-dev"
  cidr_block         = "10.1.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = false # Cost optimization for dev

  tags = { Environment = "dev", Project = var.project, ManagedBy = "terraform" }
}

module "storage" {
  source = "../../modules/storage"

  bucket_name       = "${var.project}-dev-artifacts"
  enable_versioning = false
  force_destroy     = true # Dev buckets can be destroyed cleanly

  lifecycle_rules = [{
    id              = "expire-old-objects"
    status          = "Enabled"
    expiration_days = 30
  }]

  tags = { Environment = "dev", Project = var.project, ManagedBy = "terraform" }
}

module "ai_infra" {
  source = "../../modules/ai_infra"

  name = "${var.project}-dev"

  allowed_bedrock_model_arns = [
    "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
  ]

  sagemaker_autoscaling_enabled = false

  tags = { Environment = "dev", Project = var.project, ManagedBy = "terraform" }
}

variable "project" { type = string }
variable "region" { type = string; default = "us-east-1" }
