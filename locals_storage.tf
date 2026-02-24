locals {
  # Storage account name: <deploy_date>sdatalake  (e.g. 20260224sdatalake = 16 chars)
  # Azure limit: 3-24 lowercase alphanumeric chars — this format satisfies that constraint.
  storage_account_name = lower("${var.deploy_date}sdatalake")

  storage_accounts = {
    (local.storage_account_name) = merge(local.common_resource_attributes, {
      name                     = lower("${var.deploy_date}sdatalake")
      account_kind             = "StorageV2"
      account_tier             = "Standard"
      account_replication_type = "LRS"
      access_tier              = "Hot"
      # Enforce HTTPS and TLS 1.2 — security baseline
      https_traffic_only_enabled = true
      min_tls_version            = "TLS1_2"
      tags                       = local.common_tags
    })
  }

  blob_containers = {
    (local.blob_container_name) = {
      name                  = local.blob_container_name
      storage_account_name  = local.storage_account_name
      container_access_type = "private"
    }
  }
}
