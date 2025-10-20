/*
 * Launch Template for Terraform Enterprise EC2 Instances
 * 
 * Boots TFE via Replicated on Docker in External Services mode.
 * Fetches RDS credentials at runtime from Secrets Manager using instance role.
 * Configures S3, RDS Postgres, and ElastiCache Redis with TLS.
 */

# Fetch latest Ubuntu 22.04 LTS AMI
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"] # Canonical

#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }

# # Local variables for Launch Template configuration
# locals {
#   instance_type = "t3.medium" # Testing with smaller instance size (2 vCPU, 4 GB RAM - minimum for TFE)
#   hostname      = "tfe.${var.dns_zone_name}"
# }

# # Launch Template for TFE EC2 instances
# resource "aws_launch_template" "tfe" {
#   name                   = "${var.project_name}-launch-template"
#   description            = "Launch template for Terraform Enterprise instances"
#   update_default_version = true

#   # AMI and instance configuration
#   image_id      = data.aws_ami.ubuntu.id
#   instance_type = local.instance_type

#   # T3 instance credit specification for stable CPU performance
#   credit_specification {
#     cpu_credits = "unlimited"
#   }

#   # IAM instance profile for accessing S3, Secrets Manager, SSM
#   iam_instance_profile {
#     name = aws_iam_instance_profile.tfe.name
#   }

#   # Network configuration (security group attached here)
#   vpc_security_group_ids = [aws_security_group.app.id]

#   # Root EBS volume configuration
#   block_device_mappings {
#     device_name = "/dev/sda1"

#     ebs {
#       volume_size           = 50 # TFE recommendation: 40-50 GB minimum
#       volume_type           = "gp3"
#       encrypted             = true
#       delete_on_termination = true
#     }
#   }

#   # IMDSv2 required for security
#   # Hop limit set to 2 to allow access from Docker containers (required for user data script)
#   metadata_options {
#     http_tokens                 = "required"
#     http_put_response_hop_limit = 2
#     http_endpoint               = "enabled"
#   }

#   # User data script to install Docker, Replicated, and configure TFE
#   user_data = base64encode(templatefile("${path.module}/templates/tfe_user_data.sh.tpl", {
#     # AWS region and account context
#     aws_region   = var.aws_region
#     project_name = var.project_name

#     # TFE hostname
#     hostname = local.hostname

#     # S3 configuration
#     s3_bucket = aws_s3_bucket.tfe_objects.id
#     s3_region = var.aws_region

#     # RDS Postgres configuration
#     # Note: Username and password are fetched from Secrets Manager at boot
#     rds_address       = aws_db_instance.tfe.address
#     rds_port          = aws_db_instance.tfe.port
#     rds_database_name = aws_db_instance.tfe.db_name
#     rds_secret_arn    = aws_db_instance.tfe.master_user_secret[0].secret_arn

#     # Redis configuration
#     redis_host     = aws_elasticache_replication_group.tfe.primary_endpoint_address
#     redis_port     = "6379"
#     redis_use_tls  = "1"  # TFE expects "1" for true, "0" for false
#     redis_use_auth = "0"  # No auth token (redis.tf: use_auth_token = false)

#     # TFE license (fetched from Secrets Manager)
#     license_secret_arn = aws_secretsmanager_secret.tfe_license.arn
#   }))

#   # Tag specifications for instances and volumes created from this template
#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name    = "${var.project_name}-instance"
#       service = "tfe"
#       layer   = "application"
#     }
#   }

#   tag_specifications {
#     resource_type = "volume"
#     tags = {
#       Name    = "${var.project_name}-volume"
#       service = "tfe"
#       layer   = "application"
#     }
#   }

#   tags = {
#     Name    = "${var.project_name}-launch-template"
#     service = "tfe"
#     layer   = "application"
#   }
# }
