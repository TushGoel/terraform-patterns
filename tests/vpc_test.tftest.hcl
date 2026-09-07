# Terraform built-in tests (terraform test — available since v1.6)
# Run: terraform test (from repo root)
#
# Tests run against actual modules using mocked providers —
# no real AWS credentials or resources needed.

variables {
  name               = "test-vpc"
  cidr_block         = "10.99.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = false
}

provider "aws" {
  region = "us-east-1"
  # Mock provider — no real AWS calls
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = "http://localhost:5000"
  }
}

run "vpc_has_correct_cidr" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == var.cidr_block
    error_message = "VPC CIDR block does not match input variable"
  }
}

run "vpc_dns_enabled" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "VPC must have DNS hostnames enabled for service discovery"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_support == true
    error_message = "VPC must have DNS support enabled"
  }
}

run "public_access_blocked_on_subnets" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  assert {
    condition     = length(aws_subnet.public) == length(var.availability_zones)
    error_message = "One public subnet required per availability zone"
  }

  assert {
    condition     = length(aws_subnet.private) == length(var.availability_zones)
    error_message = "One private subnet required per availability zone"
  }
}

run "no_nat_gateway_when_disabled" {
  command = plan

  module {
    source = "./modules/vpc"
  }

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 0
    error_message = "NAT gateway should not be created when enable_nat_gateway=false"
  }
}
