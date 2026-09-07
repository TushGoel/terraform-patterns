output "bedrock_role_arn" {
  description = "ARN of the IAM role for Bedrock invocations"
  value       = aws_iam_role.bedrock.arn
}

output "sagemaker_endpoint_name" {
  description = "SageMaker endpoint name (empty if not created)"
  value       = var.sagemaker_model_s3_uri != null ? aws_sagemaker_endpoint.main[0].name : null
}

output "sagemaker_endpoint_arn" {
  description = "SageMaker endpoint ARN (empty if not created)"
  value       = var.sagemaker_model_s3_uri != null ? aws_sagemaker_endpoint.main[0].arn : null
}

output "model_config_parameter_names" {
  description = "SSM Parameter Store paths for model configuration"
  value       = { for k, v in aws_ssm_parameter.model_config : k => v.name }
}
