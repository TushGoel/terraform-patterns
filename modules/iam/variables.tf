variable "role_name" {
  description = "IAM role name — must be unique per account"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_/-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters: alphanumeric and +=,.@_/-"
  }
}

variable "principal_type" {
  description = "Principal type: Service, AWS, or Federated"
  type        = string

  validation {
    condition     = contains(["Service", "AWS", "Federated"], var.principal_type)
    error_message = "principal_type must be Service, AWS, or Federated."
  }
}

variable "principal_identifiers" {
  description = "List of principal identifiers (service names or ARNs)"
  type        = list(string)
}

variable "assume_role_conditions" {
  description = "Optional conditions for the assume-role policy (e.g. MFA required, source IP)"
  type = list(object({
    test     = string
    variable = string
    values   = list(string)
  }))
  default = []
}

variable "inline_policies" {
  description = "Inline policy statements — prefer managed policies for reuse"
  type = list(object({
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

variable "managed_policy_arns" {
  description = "AWS managed or customer managed policy ARNs to attach"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the role"
  type        = map(string)
  default     = {}
}
