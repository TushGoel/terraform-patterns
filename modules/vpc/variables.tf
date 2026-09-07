variable "name" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 32
    error_message = "Name must be between 2 and 32 characters."
  }
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR notation."
  }
}

variable "availability_zones" {
  description = "List of availability zones for subnet distribution"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required for high availability."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway for private subnet egress. Costs ~$32/month."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
