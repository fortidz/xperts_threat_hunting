###############################################################################
# Route 53 — DNS Records for FortiGate and FortiAnalyzer
###############################################################################

data "aws_route53_zone" "lab" {
  name = local.dns_domain
}

resource "aws_route53_record" "fortigate" {
  zone_id = data.aws_route53_zone.lab.zone_id
  name    = local.fortigate_fqdn
  type    = "A"
  ttl     = 300
  records = [azurerm_public_ip.pip[local.fortigate_pip_name].ip_address]
}

resource "aws_route53_record" "fortianalyzer" {
  zone_id = data.aws_route53_zone.lab.zone_id
  name    = local.fortianalyzer_fqdn
  type    = "A"
  ttl     = 300
  records = [azurerm_public_ip.pip[local.fortianalyzer_pip_name].ip_address]
}
