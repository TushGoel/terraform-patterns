output "state_bucket_name" {
  description = "S3 bucket name for Terraform state — use in backend configuration"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking — use in backend configuration"
  value       = aws_dynamodb_table.lock.name
}

output "backend_config" {
  description = "Backend configuration block — copy into your Terraform root module"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "environments/<env>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.lock.name}"
        encrypt        = true
      }
    }
  EOT
}
