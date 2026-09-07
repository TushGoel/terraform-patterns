# IAM module tests — verify least-privilege enforcement

variables {
  role_name             = "test-service-role"
  principal_type        = "Service"
  principal_identifiers = ["lambda.amazonaws.com"]
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

run "role_created_with_correct_name" {
  command = plan

  module {
    source = "./modules/iam"
  }

  assert {
    condition     = aws_iam_role.main.name == var.role_name
    error_message = "IAM role name must match input variable"
  }
}

run "inline_policy_not_created_when_empty" {
  command = plan

  module {
    source = "./modules/iam"
  }

  variables {
    inline_policies = []
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "No inline policy should be created when inline_policies is empty"
  }
}

run "managed_policies_attached" {
  command = plan

  module {
    source = "./modules/iam"
  }

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 1
    error_message = "Managed policy attachment count must match managed_policy_arns length"
  }
}
