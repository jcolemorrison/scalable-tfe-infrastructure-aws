output "route53_zone_id" {
  description = "Public hosted zone ID (use this for future records)"
  value       = aws_route53_zone.primary.zone_id
}

output "route53_name_servers" {
  description = "Name servers to configure at the domain registrar"
  value       = aws_route53_zone.primary.name_servers
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
