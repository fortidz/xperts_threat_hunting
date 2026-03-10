###############################################################################
# FortiGate — Static Routes
###############################################################################

resource "fortios_router_static" "route" {
  for_each = local.fgt_static_routes

  seq_num = tonumber(each.key)
  dst     = each.value.dst
  gateway = each.value.gateway
  device  = each.value.device

  depends_on = [fortios_system_interface.interface]
}
