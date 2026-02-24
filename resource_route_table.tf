resource "azurerm_route_table" "rt" {
  for_each = local.route_tables

  name                          = each.value.name
  location                      = each.value.location
  resource_group_name           = each.value.resource_group_name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = each.value.tags

  dynamic "route" {
    for_each = each.value.routes

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }

  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_subnet_route_table_association" "rt_assoc" {
  for_each = local.route_table_subnet_associations

  subnet_id      = azurerm_subnet.subnet[each.value.subnet_key].id
  route_table_id = azurerm_route_table.rt[each.value.route_table_key].id
}
