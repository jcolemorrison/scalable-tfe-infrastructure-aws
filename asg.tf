/*
 * Auto Scaling Group for Terraform Enterprise
 * 
 * Deploys TFE instances in private subnets behind the ALB.
 * Active/Active configuration with minimum 2 nodes.
 * Uses ELB health checks with generous grace period for first boot.
 */

resource "aws_autoscaling_group" "tfe" {
  name = "${var.project_name}-asg"

  # Capacity configuration
  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  # Network configuration - deploy in private subnets across AZs
  vpc_zone_identifier = module.vpc.private_subnet_ids

  # Launch Template configuration
  launch_template {
    id      = aws_launch_template.tfe.id
    version = tostring(aws_launch_template.tfe.latest_version) # Track LT version explicitly (update_default_version = true in LT)
  }

  # Load Balancer integration
  target_group_arns = [aws_lb_target_group.tfe.arn]

  # Health check configuration
  # ELB health checks ensure instances are actually serving traffic
  health_check_type         = "ELB"
  health_check_grace_period = 900 # 15 minutes for TFE boot + Replicated + first health check

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
  wait_for_capacity_timeout = "15m" # Match grace period for initial deployment
  wait_for_elb_capacity     = 2     # Wait for 2 instances to pass ELB health checks before apply completes

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
