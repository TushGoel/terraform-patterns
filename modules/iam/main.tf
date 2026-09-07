# IAM module — least-privilege role and policy patterns
#
# Enforces least-privilege by default:
# - No wildcard actions without explicit justification
# - Condition blocks scoped to specific resources
# - Separate roles per workload (never shared service accounts)
# - Policy versioning tracked in outputs for audit

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_iam_role" "main" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = var.principal_type
      identifiers = var.principal_identifiers
    }

    dynamic "condition" {
      for_each = var.assume_role_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }
}

resource "aws_iam_role_policy" "inline" {
  count  = length(var.inline_policies) > 0 ? 1 : 0
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.main.id
  policy = data.aws_iam_policy_document.inline[0].json
}

data "aws_iam_policy_document" "inline" {
  count = length(var.inline_policies) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.inline_policies
    content {
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.main.name
  policy_arn = each.value
}
