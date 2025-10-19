# Lookup the existing public Route 53 hosted zone for your domain
data "aws_route53_zone" "primary" {
  name         = var.dns_zone_name
  private_zone = false
}

# A/ALIAS record for TFE public hostname → ALB
resource "aws_route53_record" "tfe" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "tfe.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.tfe.dns_name
    zone_id                = aws_lb.tfe.zone_id
    evaluate_target_health = false
  }
}