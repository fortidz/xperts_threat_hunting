locals {
  resource_group_name = var.resource_group_name
  location            = var.location

  # Reusable block merged into every resource map so resource_group_name
  # and location are never duplicated across locals files.
  common_resource_attributes = {
    resource_group_name = var.resource_group_name
    location            = var.location
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
