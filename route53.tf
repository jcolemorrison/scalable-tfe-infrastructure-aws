# Creates a public Route 53 hosted zone for your domain
resource "aws_route53_zone" "primary" {
  name          = var.dns_zone_name # e.g., example.xyz
  comment       = "Public zone for Terraform Enterprise"
  force_destroy = false
}