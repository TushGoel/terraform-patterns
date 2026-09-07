variable "bucket_name" {
  description = "S3 bucket name — globally unique"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters, lowercase alphanumeric and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning for point-in-time recovery"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ARN for SSE-KMS encryption. If null, uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Delete all objects when destroying bucket. Use with caution in production."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "S3 lifecycle rules for cost management"
  type = list(object({
    id     = string
    status = string
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
