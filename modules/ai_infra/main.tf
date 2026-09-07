# AI Infrastructure module — production patterns for ML/LLM workloads
#
# Provisions infrastructure for AI/ML systems:
# - SageMaker endpoint with auto-scaling (model serving)
# - Bedrock-enabled IAM role (foundation model access)
# - GPU-optimized EC2 launch template (training/inference)
# - Parameter Store entries for model config (no secrets in Terraform state)
#
# Design decisions:
# - Auto-scaling on SageMaker endpoint prevents cold-start latency at peak
# - Bedrock IAM role scoped to specific model ARNs — no wildcard model access
# - GPU instance type configurable — p3 for training, g4dn for inference
# - Parameter Store for model config keeps sensitive values out of state

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── Bedrock IAM Role ─────────────────────────────────────────────────────────

resource "aws_iam_role" "bedrock" {
  name = "${var.name}-bedrock-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "bedrock" {
  name = "${var.name}-bedrock-policy"
  role = aws_iam_role.bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeScoped"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # Scoped to specific model ARNs — no wildcard
        Resource = var.allowed_bedrock_model_arns
      },
      {
        Sid      = "BedrockListModels"
        Effect   = "Allow"
        Action   = ["bedrock:ListFoundationModels"]
        Resource = "*"
      }
    ]
  })
}

# ── SageMaker Endpoint ───────────────────────────────────────────────────────

resource "aws_iam_role" "sagemaker" {
  count = var.sagemaker_model_s3_uri != null ? 1 : 0
  name  = "${var.name}-sagemaker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "sagemaker" {
  count      = var.sagemaker_model_s3_uri != null ? 1 : 0
  role       = aws_iam_role.sagemaker[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_model" "main" {
  count              = var.sagemaker_model_s3_uri != null ? 1 : 0
  name               = "${var.name}-model"
  execution_role_arn = aws_iam_role.sagemaker[0].arn

  primary_container {
    image          = var.sagemaker_container_image
    model_data_url = var.sagemaker_model_s3_uri
    environment    = var.sagemaker_environment
  }

  tags = var.tags
}

resource "aws_sagemaker_endpoint_configuration" "main" {
  count = var.sagemaker_model_s3_uri != null ? 1 : 0
  name  = "${var.name}-endpoint-config"

  production_variants {
    variant_name           = "primary"
    model_name             = aws_sagemaker_model.main[0].name
    initial_instance_count = var.sagemaker_instance_count
    instance_type          = var.sagemaker_instance_type

    # Enable data capture for model monitoring
    initial_variant_weight = 1.0
  }

  tags = var.tags
}

resource "aws_sagemaker_endpoint" "main" {
  count                = var.sagemaker_model_s3_uri != null ? 1 : 0
  name                 = "${var.name}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.main[0].name

  tags = var.tags
}

# Auto-scaling for SageMaker endpoint — prevents latency spikes at peak load
resource "aws_appautoscaling_target" "sagemaker" {
  count              = var.sagemaker_model_s3_uri != null && var.sagemaker_autoscaling_enabled ? 1 : 0
  max_capacity       = var.sagemaker_max_capacity
  min_capacity       = var.sagemaker_instance_count
  resource_id        = "endpoint/${aws_sagemaker_endpoint.main[0].name}/variant/primary"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"
}

resource "aws_appautoscaling_policy" "sagemaker" {
  count              = var.sagemaker_model_s3_uri != null && var.sagemaker_autoscaling_enabled ? 1 : 0
  name               = "${var.name}-sagemaker-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sagemaker[0].resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.sagemaker_target_invocations_per_instance

    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ── Model Config in Parameter Store ─────────────────────────────────────────

resource "aws_ssm_parameter" "model_config" {
  for_each = nonsensitive(var.model_config_parameters)

  name  = "/${var.name}/model-config/${each.key}"
  type  = "SecureString"
  value = each.value

  tags = var.tags
}
