locals {
  resource_group_name = var.resource_group_name
  location            = var.create_resource_group ? var.location : data.azurerm_resource_group.existing[0].location

  # Unified references — resolve to either the created or existing resource group.
  rg_name = (
    var.create_resource_group
    ? azurerm_resource_group.rg[0].name
    : data.azurerm_resource_group.existing[0].name
  )
  rg_id = (
    var.create_resource_group
    ? azurerm_resource_group.rg[0].id
    : data.azurerm_resource_group.existing[0].id
  )
  rg_location = (
    var.create_resource_group
    ? azurerm_resource_group.rg[0].location
    : data.azurerm_resource_group.existing[0].location
  )

  # Reusable block merged into every resource map so resource_group_name
  # and location are never duplicated across locals files.
  common_resource_attributes = {
    resource_group_name = local.rg_name
    location            = local.rg_location
  }

  common_tags = merge(
    var.tags,
    {
      "managed-by"  = "terraform"
      "environment" = "threat-hunting"
      "project"     = "xperts-threat-hunting"
    }
  )
}
