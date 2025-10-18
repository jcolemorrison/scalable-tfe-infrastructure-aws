# Lookup the existing public Route 53 hosted zone for your domain
data "aws_route53_zone" "primary" {
  name         = var.dns_zone_name
  private_zone = false
}