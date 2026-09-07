variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "allowed_bedrock_model_arns" {
  description = "List of Bedrock model ARNs the role can invoke. Never use wildcard in production."
  type        = list(string)
  default = [
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
    "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0",
  ]

  validation {
    condition     = !contains([for arn in var.allowed_bedrock_model_arns : arn == "*"], true)
    error_message = "Wildcard (*) not allowed in model ARNs — scope to specific models."
  }
}

# SageMaker endpoint (optional — set to null to skip)
variable "sagemaker_model_s3_uri" {
  description = "S3 URI of model artifacts. Set to null to skip SageMaker endpoint."
  type        = string
  default     = null
}

variable "sagemaker_container_image" {
  description = "SageMaker container image URI (from ECR or AWS deep learning containers)"
  type        = string
  default     = ""
}

variable "sagemaker_environment" {
  description = "Environment variables passed to the SageMaker container"
  type        = map(string)
  default     = {}
}

variable "sagemaker_instance_type" {
  description = "SageMaker instance type. ml.g4dn.xlarge for inference, ml.p3.2xlarge for training."
  type        = string
  default     = "ml.g4dn.xlarge"

  validation {
    condition     = can(regex("^ml\\.", var.sagemaker_instance_type))
    error_message = "SageMaker instance types must start with 'ml.'"
  }
}

variable "sagemaker_instance_count" {
  description = "Initial number of instances behind the endpoint"
  type        = number
  default     = 1

  validation {
    condition     = var.sagemaker_instance_count >= 1
    error_message = "At least 1 instance required."
  }
}

variable "sagemaker_autoscaling_enabled" {
  description = "Enable auto-scaling for the SageMaker endpoint"
  type        = bool
  default     = true
}

variable "sagemaker_max_capacity" {
  description = "Maximum instances for auto-scaling"
  type        = number
  default     = 4
}

variable "sagemaker_target_invocations_per_instance" {
  description = "Target invocations per instance for auto-scaling trigger"
  type        = number
  default     = 100
}

variable "model_config_parameters" {
  description = "Model configuration stored in Parameter Store (SecureString). Keys become parameter names."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
