# Storage module tests — verify security defaults are enforced

variables {
  bucket_name       = "test-bucket-tftest-12345"
  enable_versioning = true
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    s3 = "http://localhost:5000"
  }
}

run "public_access_always_blocked" {
  command = plan

  module {
    source = "./modules/storage"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.block_public_acls == true
    error_message = "Public ACLs must always be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.block_public_policy == true
    error_message = "Public bucket policies must always be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.main.restrict_public_buckets == true
    error_message = "Public bucket access must always be restricted"
  }
}

run "encryption_always_enabled" {
  command = plan

  module {
    source = "./modules/storage"
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.main.rule : anytrue([
        for default in rule.apply_server_side_encryption_by_default : default.sse_algorithm == "AES256"
      ])
    ])
    error_message = "S3 bucket must always have server-side encryption enabled"
  }
}

run "versioning_enabled_when_requested" {
  command = plan

  module {
    source = "./modules/storage"
  }

  variables {
    enable_versioning = true
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.main.versioning_configuration[0].status == "Enabled"
    )
    error_message = "Versioning must be Enabled when enable_versioning=true"
  }
}
