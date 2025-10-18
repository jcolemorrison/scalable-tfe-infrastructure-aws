/*
 * ElastiCache Redis for Terraform Enterprise (Active/Active coordination)
 * 
 * Deployed in private subnets with encryption at rest and in transit.
 * Single-AZ by default (cheapest); toggle Multi-AZ for HA.
 * 
 * Auth Token Trade-off:
 * - When use_auth_token = false: Relies on security groups + encryption (no token in state)
 * - When use_auth_token = true:  Token stored in Terraform state as sensitive value
 *   (acceptable for demo, but not ideal for strict secret hygiene in production)
 */

# Sizing and HA configuration - easy to bump for production
locals {
  redis_size            = "small" # Options: "small", "medium"
  redis_enable_multi_az = false   # Set true for HA with automatic failover (increases cost)
  use_auth_token        = false   # Set true to use auth token from Secrets Manager (token will be in state)

  # Node type mapping
  redis_node_types = {
    small  = "cache.t3.small"
    medium = "cache.t3.medium"
  }
}

# Optional: Auth token from Secrets Manager (only used if local.use_auth_token = true)
data "aws_secretsmanager_secret" "redis_auth" {
  count = local.use_auth_token ? 1 : 0
  name  = "/tfe/redis/auth"
}

data "aws_secretsmanager_secret_version" "redis_auth" {
  count     = local.use_auth_token ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.redis_auth[0].id
}

# ElastiCache Subnet Group - spans private subnets across AZs
resource "aws_elasticache_subnet_group" "tfe" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = module.vpc.private_subnet_ids

  tags = {
    Name    = "${var.project_name}-redis-subnet-group"
    service = "tfe"
    layer   = "data"
  }
}

# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "tfe" {
  # ElastiCache replication group IDs must be ≤ 40 characters, start with a letter,
  # and contain only letters, numbers, and hyphens.
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis cluster for Terraform Enterprise Active/Active coordination"

  # Engine configuration
  # Note: engine_version "7.1" may not be available in all regions yet.
  # If apply fails with "version not available," relax to "7.0" which is widely available.
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = local.redis_node_types[local.redis_size]
  port                 = 6379
  parameter_group_name = "default.redis7"

  # Cluster configuration
  # Multi-AZ behavior controlled by automatic_failover_enabled and replicas_per_node_group
  num_node_groups            = 1
  replicas_per_node_group    = local.redis_enable_multi_az ? 1 : 0
  automatic_failover_enabled = local.redis_enable_multi_az

  # Network & security
  subnet_group_name  = aws_elasticache_subnet_group.tfe.name
  security_group_ids = [aws_security_group.redis.id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"

  # Optional: Auth token
  # WARNING: Setting auth_token here stores the token in Terraform state as a sensitive value.
  # For stricter secret hygiene, leave auth_token unset (null) and have TFE instances
  # retrieve the token directly from Secrets Manager at boot time using their IAM role.
  auth_token                 = local.use_auth_token ? data.aws_secretsmanager_secret_version.redis_auth[0].secret_string : null
  auth_token_update_strategy = local.use_auth_token ? "ROTATE" : null

  # Maintenance & backup (demo-friendly settings)
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = 0 # No snapshots for demo (set to 7+ for production)
  apply_immediately        = true

  # Notifications (optional, add SNS topic ARN if needed)
  # notification_topic_arn = ""

  # Auto minor version upgrades
  auto_minor_version_upgrade = true

  tags = {
    Name    = "${var.project_name}-redis"
    service = "tfe"
    layer   = "data"
  }
}
