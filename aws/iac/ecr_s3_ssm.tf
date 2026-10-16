locals {
  ecr_repos = ["todo-backend", "todo-frontend"]
  ssm_path  = "/${var.project}/prod"
}

# ---------------- ECR ----------------
resource "aws_ecr_repository" "app" {
  for_each             = toset(local.ecr_repos)
  name                 = each.key
  image_tag_mutability = "MUTABLE" # allows re-running a pipeline for the same commit
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

# ---------------- S3 deploy bundle bucket ----------------
resource "aws_s3_bucket" "deploy" {
  bucket        = "${var.project}-deploy-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket                  = aws_s3_bucket.deploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    id     = "expire-old-bundles"
    status = "Enabled"
    filter {
      prefix = "releases/"
    }
    expiration {
      days = 30
    }
  }
}

# ---------------- SSM Parameter Store ----------------
# Non-secret wiring read by scripts/deploy.sh
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "${local.ssm_path}/db_endpoint"
  type  = "String"
  value = aws_db_instance.main.address
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_path}/db_name"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_secret_arn" {
  name  = "${local.ssm_path}/db_secret_arn"
  type  = "String"
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}

# Secrets: created as placeholders; set the real values out-of-band so they never touch
# Terraform state or git:  aws ssm put-parameter --name ... --type SecureString --overwrite --value ...
resource "aws_ssm_parameter" "secret_placeholder" {
  for_each = toset(["cohere_api_key", "slack_webhook_url", "grafana_admin_password"])
  name     = "${local.ssm_path}/${each.key}"
  type     = "SecureString"
  value    = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}
