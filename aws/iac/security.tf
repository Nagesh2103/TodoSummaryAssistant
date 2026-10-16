resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "EC2 app host"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-rds-sg"
  description = "RDS MySQL - only reachable from the app security group"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-rds-sg" }
}

# Application port (HTTP via nginx)
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP application"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Grafana - admin IP only
resource "aws_vpc_security_group_ingress_rule" "app_grafana" {
  security_group_id = aws_security_group.app.id
  description       = "Grafana from admin IP"
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
  cidr_ipv4         = var.admin_cidr
}

# SSH - admin IP only (optional; SSM Session Manager is the preferred path)
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  count             = var.enable_ssh ? 1 : 0
  security_group_id = aws_security_group.app.id
  description       = "SSH from admin IP"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

# Egress: image pulls (ECR/Docker Hub/GCR), SSM, S3, Cohere, Slack, RDS
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# RDS accepts MySQL ONLY from the EC2 security group
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "MySQL from app SG"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}
