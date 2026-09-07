output "lambda_function_arn" {
  description = "Lambda function ARN (null if not created)"
  value       = var.lambda_config != null ? aws_lambda_function.main[0].arn : null
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = var.lambda_config != null ? aws_lambda_function.main[0].function_name : null
}

output "lambda_dlq_arn" {
  description = "DLQ ARN for failed Lambda invocations"
  value       = var.lambda_config != null ? aws_sqs_queue.dlq[0].arn : null
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN (null if not created)"
  value       = var.ecs_config != null ? aws_ecs_cluster.main[0].arn : null
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = var.ecs_config != null ? aws_ecs_service.main[0].name : null
}
