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
  description = "Security group IDs for ECS service"
  type        = list(string)
  default     = []
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
