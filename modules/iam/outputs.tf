output "role_arn" {
  description = "ARN of the created IAM role"
  value       = aws_iam_role.main.arn
}

output "role_name" {
  description = "Name of the created IAM role"
  value       = aws_iam_role.main.name
}

output "role_id" {
  description = "Unique ID of the IAM role"
  value       = aws_iam_role.main.unique_id
}
