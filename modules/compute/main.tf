# Compute module — Lambda (serverless) and ECS (container) patterns
#
# Two composable patterns:
#   Lambda: event-driven functions with dead-letter queues and reserved concurrency
#   ECS Fargate: containerized services with task auto-scaling and health checks
#
# Design decisions:
# - Lambda gets reserved concurrency to prevent noisy-neighbor throttling
# - DLQ on Lambda prevents silent message loss on invocation failure
# - ECS uses Fargate (serverless containers) — no EC2 fleet to manage
# - Auto-scaling on ECS CPU/memory keeps costs proportional to load

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── Lambda ────────────────────────────────────────────────────────────────────

# CMK for Lambda environment variable encryption — reused for the ECS/Lambda
# CloudWatch log group below since both are scoped to this same workload.
resource "aws_kms_key" "compute" {
  count               = var.lambda_config != null || var.ecs_config != null ? 1 : 0
  description         = "CMK for ${var.name} Lambda env vars and CloudWatch Logs"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_lambda_function" "main" {
  count = var.lambda_config != null ? 1 : 0

  function_name = var.name
  role          = var.execution_role_arn
  runtime       = var.lambda_config.runtime
  handler       = var.lambda_config.handler
  timeout       = var.lambda_config.timeout
  memory_size   = var.lambda_config.memory_mb

  filename         = var.lambda_config.package_path
  source_code_hash = var.lambda_config.package_path != null ? filebase64sha256(var.lambda_config.package_path) : null

  dynamic "image_config" {
    for_each = var.lambda_config.image_uri != null ? [1] : []
    content {
      command = var.lambda_config.image_command
    }
  }

  package_type = var.lambda_config.image_uri != null ? "Image" : "Zip"
  image_uri    = var.lambda_config.image_uri

  # Reserved concurrency: prevents this function from consuming the full account limit
  # Set to -1 to use unreserved concurrency (default)
  reserved_concurrent_executions = var.lambda_config.reserved_concurrency

  environment {
    variables = var.lambda_config.environment_vars
  }

  # Customer-managed key for env var encryption at rest (default is an
  # AWS-managed key, which is fine for most cases but fails a CMK-required policy)
  kms_key_arn = aws_kms_key.compute[0].arn

  # Full request tracing — cheap and makes latency debugging tractable.
  # Requires xray:PutTraceSegments on execution_role_arn.
  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq[0].arn
  }

  # VPC attachment is opt-in: only wire it up if the caller passed subnet IDs,
  # since most event-driven Lambdas (SQS/API triggers, no private resources
  # to reach) don't need VPC egress and gain nothing from NAT cost/latency.
  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # Code signing is opt-in: it requires the caller to run deployment
  # artifacts through an AWS Signer pipeline, which is a deployment-process
  # decision this generic module shouldn't force on every consumer.
  code_signing_config_arn = var.lambda_code_signing_config_arn

  tags = var.tags

  depends_on = [aws_sqs_queue.dlq]
}

# DLQ for failed Lambda invocations — prevents silent message loss
resource "aws_sqs_queue" "dlq" {
  count = var.lambda_config != null ? 1 : 0
  name  = "${var.name}-dlq"

  # Retain failed messages for 14 days (max) for debugging
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = true

  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "sqs" {
  count = var.lambda_config != null && var.lambda_config.sqs_trigger_arn != null ? 1 : 0

  event_source_arn                   = var.lambda_config.sqs_trigger_arn
  function_name                      = aws_lambda_function.main[0].arn
  batch_size                         = var.lambda_config.sqs_batch_size
  maximum_batching_window_in_seconds = 5

  # On failure, route to DLQ and continue processing
  function_response_types = ["ReportBatchItemFailures"]
}

# ── ECS Fargate ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  count = var.ecs_config != null ? 1 : 0
  name  = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "main" {
  count = var.ecs_config != null ? 1 : 0

  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_config.cpu
  memory                   = var.ecs_config.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.ecs_config.task_role_arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.ecs_config.container_image
    essential = true
    portMappings = [{
      containerPort = var.ecs_config.container_port
      protocol      = "tcp"
    }]
    environment = [for k, v in var.ecs_config.environment_vars : { name = k, value = v }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.name}"
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ecs" {
  count             = var.ecs_config != null ? 1 : 0
  name              = "/ecs/${var.name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.compute[0].arn
  tags              = var.tags
}

resource "aws_ecs_service" "main" {
  count           = var.ecs_config != null ? 1 : 0
  name            = var.name
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.main[0].arn
  desired_count   = var.ecs_config.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  tags = var.tags
}

# ECS Auto-scaling on CPU utilization
resource "aws_appautoscaling_target" "ecs" {
  count              = var.ecs_config != null && var.ecs_config.autoscaling_enabled ? 1 : 0
  max_capacity       = var.ecs_config.max_capacity
  min_capacity       = var.ecs_config.desired_count
  resource_id        = "service/${aws_ecs_cluster.main[0].name}/${aws_ecs_service.main[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  count              = var.ecs_config != null && var.ecs_config.autoscaling_enabled ? 1 : 0
  name               = "${var.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
