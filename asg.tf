/*
 * Auto Scaling Group for Terraform Enterprise
 * 
 * Deploys TFE instances in private subnets behind the ALB.
 * Active/Active configuration with minimum 2 nodes.
 * Uses ELB health checks with generous grace period for first boot.
 */

resource "aws_autoscaling_group" "tfe" {
  name = "${var.project_name}-asg"

  # Capacity configuration - single instance for stability during testing
  min_size         = 1
  desired_capacity = 1
  max_size         = 4

  # Network configuration - deploy in private subnets across AZs
  vpc_zone_identifier = module.vpc.private_subnet_ids

  # Launch Template configuration
  launch_template {
    id      = aws_launch_template.tfe.id
    version = "$Latest" # Always use latest version (best for dev/workshop; consider pinning in prod)
  }

  # Load Balancer integration
  target_group_arns = [aws_lb_target_group.tfe.arn]

  # Health check configuration
  # Use EC2 health checks initially - instances won't be healthy for ELB until TFE is fully installed (~20-30 min)
  # Switch to ELB after first successful deployment
  health_check_type         = "EC2"
  health_check_grace_period = 300 # 5 minutes for instance to boot (not waiting for TFE)

  # Scaling behavior
  default_cooldown     = 300                 # 5 minutes between scaling events
  capacity_rebalance   = true                # Proactively replace at-risk instances
  termination_policies = ["OldestInstance"]  # Predictable instance rotation
  force_delete         = true                # Allow deletion even if instances are stuck (safe for workshop/dev)

  # Instance refresh configuration for automated rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50            # Keep at least 1 of 2 instances healthy during refresh
      instance_warmup        = 120           # Wait 2 min after instance ready before considering it healthy
      checkpoint_percentages = [50, 100]     # Pause at 50% and 100% for validation
    }
    triggers = ["launch_template"]           # Auto-refresh when Launch Template changes
  }

  # Deployment timeouts
  # Don't wait for ELB capacity during initial deployment - TFE takes 20-30 min to install
  # Instances will register to target group but won't be healthy until TFE is running
  wait_for_capacity_timeout = "0" # Don't wait for instances to become healthy

  # Instance tags (propagated to EC2 instances at launch)
  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "service"
    value               = "tfe"
    propagate_at_launch = true
  }

  tag {
    key                 = "layer"
    value               = "application"
    propagate_at_launch = true
  }

  # ASG resource tags (applied to the ASG itself, not instances)
  # Note: These don't propagate to instances; use separate tag blocks above for that
  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg"
    propagate_at_launch = false
  }
}
