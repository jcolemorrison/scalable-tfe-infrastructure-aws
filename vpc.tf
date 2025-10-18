/*
 * VPC module from HCP Terraform private registry
 * Creates a VPC with public/private subnets, NAT gateway, and internet gateway
 * 
 * Subnet Strategy for TFE:
 * - Public subnets: Application Load Balancer (ALB)
 * - Private subnets: TFE EC2 instances, RDS PostgreSQL, and ElastiCache Redis
 * 
 * Note: Using the same private subnets for compute and data tier is acceptable
 * for TFE deployments. RDS and ElastiCache use subnet groups that can span
 * the same subnets as EC2 instances. They're isolated via security groups.
 */

module "vpc" {
  source = "app.terraform.io/jcolemorrison/aws-base-vpc/aws"
  # version = "0.8.3" # Commented out to test if module is accessible at all

  # Required variables
  name       = var.project_name
  cidr_block = var.vpc_cidr_block

  # Subnet configuration
  public_subnet_count  = var.public_subnet_count
  private_subnet_count = var.private_subnet_count

  # Optional: IPv6 support
  ipv6_enabled = false

  # Instance tenancy
  instance_tenancy = "default"

  # Transit Gateway (optional - leave empty if not using)
  accessible_cidr_blocks = []
  attach_public_subnets  = true
  transit_gateway_id     = null

  # Tags - merged with provider default_tags
  tags = {
    project = "scalable-tfe"
    name    = "${var.project_name}-vpc"
  }
}
