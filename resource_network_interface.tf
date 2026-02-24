resource "azurerm_network_interface" "nic" {
  for_each = local.network_interfaces

  name                  = each.value.name
  location              = each.value.location
  resource_group_name   = each.value.resource_group_name
  ip_forwarding_enabled = each.value.ip_forwarding_enabled
  tags                  = each.value.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet[each.value.subnet_key].id
    private_ip_address_allocation = each.value.private_ip_alloc
    # Only set private_ip_address when allocation is Static
    private_ip_address   = each.value.private_ip_alloc == "Static" ? each.value.private_ip_address : null
    public_ip_address_id = each.value.public_ip_key != null ? azurerm_public_ip.pip[each.value.public_ip_key].id : null
  }

  depends_on = [
    azurerm_subnet.subnet,
    azurerm_public_ip.pip,
  ]
}
