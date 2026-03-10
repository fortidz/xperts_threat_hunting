###############################################################################
# FortiGate — Firewall Service Groups
###############################################################################

resource "fortios_firewallservice_group" "group" {
  for_each = local.fgt_service_groups

  name = each.key

  dynamic "member" {
    for_each = each.value.members
    content {
      name = member.value
    }
  }
}
