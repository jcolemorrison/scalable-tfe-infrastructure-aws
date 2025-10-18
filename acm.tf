/*
 * ACM — public wildcard certificate validated via Route 53
 * Issues *.dns_zone_name so any subdomain (e.g., tfe.<zone>) can be used later.
 */

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.dns_zone_name}"
  validation_method = "DNS"

  # Optional: include the apex as a SAN
  subject_alternative_names = [var.dns_zone_name]

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records in the hosted zone you just created
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# Complete ACM validation once the DNS records exist
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]

  timeouts {
    create = "5m"
  }
}