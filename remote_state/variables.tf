variable "project" {
  description = "Project name used as prefix for state bucket and lock table"
  type        = string
}

variable "region" {
  description = "AWS region for state bucket"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID — appended to bucket name for global uniqueness"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
