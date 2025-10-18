/*
 * RDS PostgreSQL for Terraform Enterprise (External Services)
 * 
 * Deployed in private subnets with restricted security group access.
 * Password managed by RDS and stored in AWS Secrets Manager (not in Terraform state).
 */

# Sizing configuration - easy to bump for production
locals {
  db_size            = "small" # Options: "small", "medium"
  db_enable_multi_az = false   # Set true for HA (increases cost)

  # Instance class mapping
  db_instance_classes = {
    small  = "db.t4g.small"  # ARM-based Graviton, fallback: db.t3.small
    medium = "db.t4g.medium" # ARM-based Graviton, fallback: db.t3.medium
  }
}

# DB Subnet Group - spans private subnets across AZs
resource "aws_db_subnet_group" "tfe" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Name    = "${var.project_name}-db-subnet-group"
    service = "tfe"
    layer   = "data"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "tfe" {
  identifier = "${var.project_name}-postgres"

  # Engine configuration
  engine               = "postgres"
  engine_version       = "15.10" # Latest PostgreSQL 15.x
  instance_class       = local.db_instance_classes[local.db_size]
  db_name              = "tfe"
  port                 = 5432

  # Credentials - managed by RDS in Secrets Manager
  username                    = "tfe"
  manage_master_user_password = true
  master_user_secret_kms_key_id = null # Use default AWS managed key

  # Storage configuration
  allocated_storage     = 20
  max_allocated_storage = 100 # Enable storage autoscaling up to 100 GiB
  storage_type          = "gp3"
  storage_encrypted     = true

  # Network & security
  db_subnet_group_name   = aws_db_subnet_group.tfe.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = local.db_enable_multi_az

  # Backup & maintenance
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Deletion protection (set to true for production)
  deletion_protection = false
  skip_final_snapshot = true

  # Performance Insights (optional, recommended for production)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name    = "${var.project_name}-postgres"
    service = "tfe"
    layer   = "data"
  }
}
