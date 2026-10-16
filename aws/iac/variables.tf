variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "todoapp"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.10/32). Used for SSH and Grafana. Never use 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "enable_ssh" {
  description = "Open port 22 to admin_cidr. Not required: deployments and shell access use SSM."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "GitHub repo allowed to assume the deploy role, as owner/name"
  type        = string
}

variable "github_branch" {
  description = "Only this branch may deploy"
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "Set to false if the account already has the token.actions.githubusercontent.com OIDC provider"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 type. t3.small (2 GiB) is comfortable for app + monitoring; t3.micro works with swap but is tight."
  type        = string
  default     = "t3.small"
}

variable "root_volume_gb" {
  type    = number
  default = 20
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "todo_db"
}

variable "db_multi_az" {
  description = "Multi-AZ gives automatic failover; costs ~2x. Off by default for the assessment, recommended in real production."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  description = "Set true for a real environment"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
