output "instance_id" {
  value       = aws_instance.app.id
  description = "GitHub secret EC2_INSTANCE_ID"
}

output "app_url" {
  value       = "http://${aws_eip.app.public_ip}"
  description = "GitHub secret APP_URL"
}

output "grafana_url" {
  value = "http://${aws_eip.app.public_ip}:3000"
}

output "github_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "GitHub secret AWS_ROLE_ARN"
}

output "deploy_bucket" {
  value       = aws_s3_bucket.deploy.bucket
  description = "GitHub secret DEPLOY_BUCKET"
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}
