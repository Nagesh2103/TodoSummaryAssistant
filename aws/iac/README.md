# Terraform for the AWS setup

Creates: VPC, public + private subnets, security groups, EC2 (+ Elastic IP, IAM role/profile, user data),
RDS MySQL (private, encrypted, credentials in Secrets Manager), ECR repositories, S3 deploy bucket,
SSM parameters, and the GitHub OIDC deploy role. See [`../aws-setup.md`](../aws-setup.md).

```bash
cp terraform.tfvars.example terraform.tfvars   # edit admin_cidr + github_repository
terraform init && terraform plan && terraform apply
terraform output          # values for the GitHub secrets
terraform destroy         # when the review is over
```

State is local by default; for a team use an S3 backend with DynamoDB locking.
Works with OpenTofu as well (`tofu` instead of `terraform`).
