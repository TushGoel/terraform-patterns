variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for Lambda execution or ECS task execution"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS service network configuration"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for ECS service (and Lambda, if lambda_subnet_ids is set)"
  type        = list(string)
  default     = []
}

variable "lambda_subnet_ids" {
  description = "Subnet IDs to attach the Lambda to. Leave empty to skip VPC attachment — only needed if the function must reach private VPC resources."
  type        = list(string)
  default     = []
}

variable "lambda_code_signing_config_arn" {
  description = "ARN of an aws_lambda_code_signing_config to enforce signed deployment packages. Leave null to skip — requires an AWS Signer pipeline."
  type        = string
  default     = null
}

variable "lambda_config" {
  description = "Lambda function configuration. Set to null to skip Lambda."
  type = object({
    runtime              = string
    handler              = string
    timeout              = number
    memory_mb            = number
    package_path         = optional(string)
    image_uri            = optional(string)
    image_command        = optional(list(string))
    reserved_concurrency = optional(number, -1)
    sqs_trigger_arn      = optional(string)
    sqs_batch_size       = optional(number, 10)
    environment_vars     = optional(map(string), {})
  })
  default = null
}

variable "ecs_config" {
  description = "ECS Fargate service configuration. Set to null to skip ECS."
  type = object({
    container_image     = string
    container_port      = number
    cpu                 = number
    memory              = number
    desired_count       = number
    task_role_arn       = optional(string)
    autoscaling_enabled = optional(bool, true)
    max_capacity        = optional(number, 4)
    environment_vars    = optional(map(string), {})
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
