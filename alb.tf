/*
 * Application Load Balancer for Terraform Enterprise
 * 
 * Internet-facing ALB with HTTPS listener forwarding to TFE instances.
 * Uses ACM wildcard certificate for TLS termination.
 * Target Group configured for instance targets on port 443.
 */

# Target Group for TFE instances
resource "aws_lb_target_group" "tfe" {
  name                 = "${var.project_name}-tg"
  port                 = 443
  protocol             = "HTTPS"
  vpc_id               = module.vpc.id
  target_type          = "instance"
  deregistration_delay = 120 # Allow TFE to finish running operations gracefully

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = 443
    path                = "/_health_check"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    matcher             = "200"
  }

  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours for TFE sessions
  }

  tags = {
    Name = "${var.project_name}-target-group"
  }
}

# Application Load Balancer
resource "aws_lb" "tfe" {
  name                       = "${var.project_name}-alb"
  load_balancer_type         = "application"
  internal                   = false # Internet-facing
  subnets                    = module.vpc.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  enable_deletion_protection = false # Set to true after testing
  enable_http2               = true
  idle_timeout               = 3600 # 1 hour for long-running Terraform operations

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.tfe.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # Modern TLS 1.3 policy
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tfe.arn
  }

  tags = {
    Name = "${var.project_name}-https-listener"
  }
}
