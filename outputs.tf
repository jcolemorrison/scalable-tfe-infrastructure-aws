output "route53_zone_id" {
  description = "Public hosted zone ID (use this for future records)"
  value       = data.aws_route53_zone.primary.zone_id
}

output "route53_name_servers" {
  description = "Name servers to configure at the domain registrar"
  value       = data.aws_route53_zone.primary.name_servers
}


output "tfe_acm_certificate_arn" {
  description = "Wildcard ACM certificate ARN to attach to the ALB"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs for TFE instances"
  value       = module.vpc.private_subnet_ids
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = module.vpc.public_route_table_id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = module.vpc.private_route_table_id
}

# Security Group Outputs
output "sg_alb_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "sg_app_id" {
  description = "ID of the TFE application security group"
  value       = aws_security_group.app.id
}

output "sg_rds_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "sg_redis_id" {
  description = "ID of the Redis security group"
  value       = aws_security_group.redis.id
}

# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the TFE objects S3 bucket"
  value       = aws_s3_bucket.tfe_objects.id
}

output "s3_bucket_arn" {
  description = "ARN of the TFE objects S3 bucket"
  value       = aws_s3_bucket.tfe_objects.arn
}

# RDS Outputs
output "tfe_rds_endpoint" {
  description = "RDS PostgreSQL endpoint in host:port format"
  value       = aws_db_instance.tfe.endpoint
}

output "tfe_rds_arn" {
  description = "ARN of the RDS PostgreSQL instance"
  value       = aws_db_instance.tfe.arn
}

output "tfe_rds_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the RDS master password"
  value       = aws_db_instance.tfe.master_user_secret[0].secret_arn
}

# ElastiCache Redis Outputs
output "tfe_redis_primary_endpoint" {
  description = "Primary Redis endpoint address"
  value       = aws_elasticache_replication_group.tfe.primary_endpoint_address
}

output "tfe_redis_reader_endpoint" {
  description = "Reader Redis endpoint address"
  value       = aws_elasticache_replication_group.tfe.reader_endpoint_address
}

# IAM Outputs
output "tfe_instance_profile_name" {
  description = "Name of the IAM instance profile for TFE EC2 instances"
  value       = aws_iam_instance_profile.tfe.name
}

output "tfe_instance_role_arn" {
  description = "ARN of the IAM role for TFE EC2 instances"
  value       = aws_iam_role.tfe_instance.arn
}

# Launch Template Outputs
output "tfe_launch_template_id" {
  description = "ID of the TFE launch template"
  value       = aws_launch_template.tfe.id
}

output "tfe_launch_template_latest_version" {
  description = "Latest version of the TFE launch template"
  value       = aws_launch_template.tfe.latest_version
}

output "tfe_hostname" {
  description = "TFE hostname (FQDN)"
  value       = "tfe.${var.dns_zone_name}"
}

# SSM Parameter Outputs
output "tfe_enc_password_parameter_name" {
  description = "SSM Parameter Store path for TFE encryption password"
  value       = aws_ssm_parameter.tfe_enc_password.name
}

output "tfe_enc_password_parameter_arn" {
  description = "ARN of the SSM parameter containing TFE encryption password"
  value       = aws_ssm_parameter.tfe_enc_password.arn
}

# CloudWatch Outputs
output "tfe_cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for TFE logs"
  value       = aws_cloudwatch_log_group.tfe.name
}

output "tfe_cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for TFE logs"
  value       = aws_cloudwatch_log_group.tfe.arn
}

# ALB Outputs
output "tfe_target_group_arn" {
  description = "ARN of the TFE target group (attach to ASG)"
  value       = aws_lb_target_group.tfe.arn
}

output "tfe_alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.tfe.arn
}

output "tfe_alb_dns_name" {
  description = "DNS name of the ALB (use for Route53 A/ALIAS record)"
  value       = aws_lb.tfe.dns_name
}

output "tfe_alb_zone_id" {
  description = "Zone ID of the ALB (for Route53 ALIAS record)"
  value       = aws_lb.tfe.zone_id
}

output "tfe_alb_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}
