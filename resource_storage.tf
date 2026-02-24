resource "azurerm_storage_account" "storage" {
  for_each = local.storage_accounts

  name                     = each.value.name
  resource_group_name      = each.value.resource_group_name
  location                 = each.value.location
  account_kind             = each.value.account_kind
  account_tier             = each.value.account_tier
  account_replication_type = each.value.account_replication_type
  access_tier              = each.value.access_tier

  # Security baseline: HTTPS only, TLS 1.2 minimum
  https_traffic_only_enabled = each.value.https_traffic_only_enabled
  min_tls_version            = each.value.min_tls_version

  # Restrict access: allow only from snet-external via service endpoint.
  # This allows FortiAnalyzer (deployed in snet-external) to write logs
  # while blocking all other public access.
  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.subnet["snet-external"].id]
    bypass                     = ["AzureServices"]
  }

  tags = each.value.tags

  depends_on = [azurerm_subnet.subnet]
}

resource "azurerm_storage_container" "container" {
  for_each = local.blob_containers

  name                  = each.value.name
  storage_account_name  = each.value.storage_account_name
  container_access_type = each.value.container_access_type

  depends_on = [azurerm_storage_account.storage]
}
