###############################################################################
# FortiGate — Network Interfaces
###############################################################################

resource "fortios_system_interface" "interface" {
  for_each = local.fgt_interfaces

  name        = each.value.name
  ip          = each.value.ip
  allowaccess = each.value.allowaccess
  alias       = each.value.alias
  description = each.value.description
  vdom        = "root"
  type        = "physical"
}
