/*
 * Security Groups for Terraform Enterprise
 * 
 * Architecture:
 * - ALB (public) -> App (private) -> RDS/Redis (private)
 * - Each tier isolated by security group rules
 * - Least privilege access between tiers
 */

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for TFE Application Load Balancer"
  vpc_id      = module.vpc.id

  tags = {
    Name    = "${var.project_name}-alb-sg"
    service = "tfe"
    layer   = "network"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# App Security Group (TFE EC2 instances)
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for TFE application EC2 instances"
  vpc_id      = module.vpc.id

  tags = {
    Name    = "${var.project_name}-app-sg"
    service = "tfe"
    layer   = "application"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id
  description       = "Allow HTTPS from ALB only"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Allow all outbound traffic for S3, SSM, OS updates, and responses"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for TFE RDS PostgreSQL database"
  vpc_id      = module.vpc.id

  tags = {
    Name    = "${var.project_name}-rds-sg"
    service = "tfe"
    layer   = "data"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow PostgreSQL from TFE app instances only"

  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound traffic for responses"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# Redis Security Group (ElastiCache)
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for TFE ElastiCache Redis"
  vpc_id      = module.vpc.id

  tags = {
    Name    = "${var.project_name}-redis-sg"
    service = "tfe"
    layer   = "data"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_app" {
  security_group_id = aws_security_group.redis.id
  description       = "Allow Redis from TFE app instances only"

  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id
  description       = "Allow all outbound traffic for responses"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
