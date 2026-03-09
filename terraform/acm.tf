# ─── ACM Certificate ──────────────────────────────────────────────────────────
# DNS validation is the recommended method – no manual email confirmation needed.

resource "aws_acm_certificate" "main" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Allow the certificate to be replaced without destroying the old one first
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.app_name}-cert" }
}

# ─── DNS Validation Records ───────────────────────────────────────────────────
# If you manage your domain in Route 53, uncomment the resources below.
# Otherwise, add the CNAME records shown in `aws_acm_certificate.main.domain_validation_options`
# to your DNS provider manually.

# data "aws_route53_zone" "main" {
#   name         = var.domain_name
#   private_zone = false
# }

# resource "aws_route53_record" "cert_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }

#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = each.value.name
#   type    = each.value.type
#   ttl     = 60
#   records = [each.value.record]
# }

resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn

  # Uncomment when using Route 53 auto-validation:
  # validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "10m"
  }
}
