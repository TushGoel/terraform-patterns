# Production environment — composes all modules
#
# This is the top-level configuration for production.
# It calls reusable modules and wires their outputs together.
# No resource blocks here — only module calls and data sources.
#
# Design principle: environments differ only in variable values,
# not in resource definitions. Differences in modules = bug.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — use outputs from remote_state/
  backend "s3" {
    bucket         = "REPLACE_WITH_STATE_BUCKET"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_WITH_LOCK_TABLE"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = "${var.project}-prod"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  enable_nat_gateway = true

  tags = local.common_tags
}

module "state_storage" {
  source = "../../modules/storage"

  bucket_name       = "${var.project}-prod-artifacts"
  enable_versioning = true
  kms_key_id        = null

  lifecycle_rules = [{
    id     = "archive-old-versions"
    status = "Enabled"
    transitions = [{
      days          = 90
      storage_class = "STANDARD_IA"
    }]
    noncurrent_version_expiration_days = 365
  }]

  tags = local.common_tags
}

module "ai_infra" {
  source = "../../modules/ai_infra"

  name = "${var.project}-prod"

  allowed_bedrock_model_arns = [
    "arn:aws:bedrock:${var.region}::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
  ]

  sagemaker_autoscaling_enabled = true
  sagemaker_max_capacity        = 4

  model_config_parameters = {
    "max-tokens"    = "4096"
    "temperature"   = "0.0"
    "system-prompt" = "You are a production AI assistant."
  }

  tags = local.common_tags
}

locals {
  common_tags = {
    Environment = "prod"
    Project     = var.project
    ManagedBy   = "terraform"
  }
}
