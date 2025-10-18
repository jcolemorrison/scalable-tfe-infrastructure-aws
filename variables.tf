variable "aws_region" {
  description = "Default AWS region for deploying Terraform Enterprise infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "default_tags" {
  description = "Default tags applied to all AWS resources via the provider's default_tags."
  type        = map(string)
  default = {
    project = "scalable-tfe"
  }
}

variable "dns_zone_name" {
  description = "Public Route 53 hosted zone (no trailing dot), e.g., example.xyz"
  type        = string
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "scalable-tfe"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_count" {
  description = "Number of public subnets (for ALB)"
  type        = number
  default     = 3
}

variable "private_subnet_count" {
  description = "Number of private subnets (for TFE instances, RDS, and ElastiCache)"
  type        = number
  default     = 3
}

