###############################################################################
# FortiGate — Firewall Address Objects (ipmask)
###############################################################################

resource "fortios_firewall_address" "ipmask" {
  for_each = local.fgt_address_ipmask

  name                 = each.key
  type                 = "ipmask"
  subnet               = each.value.subnet
  associated_interface = each.value.associated_interface != "" ? each.value.associated_interface : null

  depends_on = [fortios_system_interface.interface]
}

###############################################################################
# FortiGate — Firewall Address Objects (iprange)
###############################################################################

resource "fortios_firewall_address" "iprange" {
  for_each = local.fgt_address_iprange

  name     = each.key
  type     = "iprange"
  start_ip = each.value.start_ip
  end_ip   = each.value.end_ip
}

###############################################################################
# FortiGate — Firewall Address Objects (FQDN)
###############################################################################

resource "fortios_firewall_address" "fqdn" {
  for_each = local.fgt_address_fqdn

  name = each.key
  type = "fqdn"
  fqdn = each.value.fqdn
}

###############################################################################
# FortiGate — Firewall Address Groups
###############################################################################

resource "fortios_firewall_addrgrp" "group" {
  for_each = local.fgt_address_groups

  name = each.key

  dynamic "member" {
    for_each = each.value.members
    content {
      name = member.value
    }
  }

  depends_on = [
    fortios_firewall_address.ipmask,
    fortios_firewall_address.fqdn,
  ]
}
