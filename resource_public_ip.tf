resource "azurerm_public_ip" "pip" {
  for_each = local.public_ips

  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  sku                 = each.value.sku
  allocation_method   = each.value.allocation_method
  tags                = each.value.tags

  depends_on = [azurerm_resource_group.rg]
}
