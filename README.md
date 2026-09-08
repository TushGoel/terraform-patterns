# terraform-patterns

![CI](https://github.com/TushGoel/terraform-patterns/actions/workflows/terraform.yml/badge.svg)
![Terraform](https://img.shields.io/badge/terraform-1.5%2B-purple)
![License](https://img.shields.io/badge/license-MIT-green)

Production Terraform patterns — reusable modules, remote state with locking, directory-based environments, and CI/CD gates with manual approval for production. Includes AI/ML infrastructure patterns for SageMaker and Bedrock.

---

## The Problem → Solution → Impact

| | |
|---|---|
| **Problem** | Ad-hoc infrastructure definitions aren't reusable. Local state means one engineer's laptop owns your infrastructure. No CI/CD gates means unapproved changes reach production. |
| **Solution** | Composable modules with validated inputs, S3+DynamoDB remote state with locking, directory-based environment management, and a GitHub Actions pipeline with plan-on-PR and manual approval before prod apply. |
| **Impact** | Infrastructure is version-controlled, peer-reviewed, and auditable. Concurrent applies are serialized. Production changes require explicit human approval. |

---

## Patterns

### 1. Remote State with Locking

```hcl
# Bootstrap once per account — remote_state/
terraform {
  backend "s3" {
    bucket         = "my-project-terraform-state-123456789012"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "my-project-terraform-lock"
    encrypt        = true
  }
}
```

**Why:** Local state means the last person to run `terraform apply` owns your infrastructure. S3 backend stores state centrally. DynamoDB locking serializes concurrent applies — without it, two engineers applying simultaneously corrupt state.

---

### 2. Module Composition

```hcl
# environments/prod/main.tf — compose modules, never duplicate resources
module "vpc" {
  source             = "../../modules/vpc"
  name               = "my-app-prod"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  enable_nat_gateway = true
}

module "ai_infra" {
  source = "../../modules/ai_infra"
  name   = "my-app-prod"
  allowed_bedrock_model_arns = [
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0"
  ]
}
```

**Why:** Copy-paste infrastructure = drift. Modules share a definition — prod and dev differ only in variable values. Changes in modules propagate to all environments.

---

### 3. Input Validation

```hcl
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required for high availability."
  }
}

variable "allowed_bedrock_model_arns" {
  type = list(string)
  validation {
    condition     = !contains([for arn in var.allowed_bedrock_model_arns : arn == "*"], true)
    error_message = "Wildcard (*) not allowed — scope to specific model ARNs."
  }
}
```

**Why:** Validate at plan time, not at apply time. Catch misconfiguration before it touches cloud resources.

---

### 4. CI/CD Gate with Manual Approval

```yaml
# Plan runs automatically on every PR — shows what will change
# Apply to prod requires explicit manual approval in GitHub Environments

jobs:
  plan-prod:       # Auto — shows the diff
  apply-prod:      # Blocked until human approves in GitHub UI
    environment: prod-apply   # ← manual approval gate
    needs: plan-prod
```

**Why:** `terraform apply` without a plan review is how production outages happen. Plan on PR = peer-reviewable infrastructure changes. Manual approval gate = no unilateral prod changes.

**Running this against a real AWS account:** the `Plan — Dev`, `Plan — Prod`, `Apply — Prod`, and `Drift Detection` workflows are gated behind a repo variable, `AWS_DEPLOYMENT_ENABLED`, so they skip cleanly instead of failing when no AWS account is wired up (as in this portfolio repo). To activate them against a real account:
1. Set up an AWS IAM OIDC identity provider trusting `token.actions.githubusercontent.com`, with IAM roles scoped to this repo.
2. Add `AWS_ROLE_ARN_DEV` and `AWS_ROLE_ARN_PROD` as repo secrets, and `PROJECT_NAME` as a repo variable.
3. Set the `AWS_DEPLOYMENT_ENABLED` repo variable to `true`.

---

### 5. AI Infrastructure Module

```hcl
module "ai_infra" {
  source = "../../modules/ai_infra"
  name   = "my-app-prod"

  # Scoped Bedrock access — no wildcard model ARNs
  allowed_bedrock_model_arns = [
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0"
  ]

  # SageMaker endpoint with auto-scaling
  sagemaker_model_s3_uri    = "s3://my-bucket/models/my-model.tar.gz"
  sagemaker_instance_type   = "ml.g4dn.xlarge"
  sagemaker_instance_count  = 1
  sagemaker_max_capacity    = 4
  sagemaker_target_invocations_per_instance = 100

  # Model config in Parameter Store — not in state
  model_config_parameters = {
    "max-tokens"  = "4096"
    "temperature" = "0.0"
  }
}
```

**Why auto-scaling:** Without it, a traffic spike causes latency degradation as requests queue. Auto-scaling on invocations/instance scales out before users notice.

**Why Parameter Store for model config:** Terraform state is stored in S3 and may be read by many systems. Model system prompts, config values, and API settings belong in Parameter Store (SecureString), not state.

---

## Project Structure

```
terraform-patterns/
├── modules/
│   ├── vpc/              # VPC, subnets, NAT gateway, route tables
│   ├── iam/              # Least-privilege roles with validated conditions
│   ├── storage/          # S3 with encryption, versioning, lifecycle rules
│   ├── compute/          # Lambda (DLQ, reserved concurrency) + ECS Fargate (autoscaling)
│   └── ai_infra/         # SageMaker endpoint + Bedrock IAM + autoscaling + Parameter Store
├── environments/
│   ├── dev/              # Dev: single AZ, no autoscaling, force_destroy=true
│   └── prod/             # Prod: multi-AZ, autoscaling, KMS encryption
├── remote_state/         # Bootstrap S3 backend + DynamoDB lock table
├── tests/                # terraform test (v1.6+): vpc, storage, IAM assertions
└── .github/workflows/
    ├── terraform.yml     # Plan on PR, apply on merge, manual approval for prod
    ├── security-scan.yml # Checkov + tfsec + Infracost cost estimation
    └── drift-detection.yml # Daily drift check → GitHub Issue on divergence
```

---

## Design Decisions & Trade-offs

**Remote state over local:** Local state works for solo projects. For teams, S3+DynamoDB is the minimum — prevents the "who has the latest state?" problem that causes duplicate resource creation or missed deletions.

**Environments as directories over workspaces:** Directories give complete isolation — separate state files, separate backends, separate variable files. Workspaces share a backend and are harder to isolate for access control. For production systems, directory-per-environment is the safer pattern.

**Module inputs over data sources:** Using data sources to look up resources across modules creates implicit dependencies that are hard to trace. Passing IDs via module outputs makes the dependency graph explicit and visible in `terraform graph`.

**Parameter Store for model config:** SageMaker environment variables and Bedrock system prompts don't belong in Terraform state. State is shared across the team and potentially accessible to CI/CD systems. Parameter Store with SecureString provides encryption, access control, and audit logging.

---

### 6. Security Scanning (Checkov + tfsec)

Every PR is scanned for misconfigurations before `terraform plan` runs:
- **Checkov** — policy-as-code: catches IAM wildcards, unencrypted resources, public access
- **tfsec** — static analysis: catches security anti-patterns in HCL
- **Infracost** — cost estimation: posts monthly cost delta to every PR

### 7. Drift Detection (Daily)

```yaml
# Runs at 6am UTC daily — detects manual AWS console changes
on:
  schedule:
    - cron: "0 6 * * *"
```

If Terraform state diverges from actual infrastructure, a GitHub Issue is automatically created with the plan diff — before the next apply creates a conflict.

### 8. Infrastructure Tests

```hcl
# tests/storage_test.tftest.hcl — terraform test (built-in since v1.6)
run "public_access_always_blocked" {
  command = plan
  assert {
    condition     = aws_s3_bucket_public_access_block.main.block_public_acls == true
    error_message = "Public ACLs must always be blocked"
  }
}
```

Tests run against module plans without real AWS credentials — fast, offline, no cloud cost.

---

## Part of the Infrastructure Stack

| Repo | What It Is |
|------|-----------|
| **[terraform-patterns](https://github.com/TushGoel/terraform-patterns)** | ← You are here: IaC modules, remote state, CI/CD gates |
| **[kafka-patterns](https://github.com/TushGoel/kafka-patterns)** | Event streaming + LLM inference telemetry |
| **[rag-patterns](https://github.com/TushGoel/rag-patterns)** | Multimodal RAG with eval and observability |
| **[workflow-orchestration-patterns](https://github.com/TushGoel/workflow-orchestration-patterns)** | Step Functions + SQS orchestration |

---

## License

MIT
