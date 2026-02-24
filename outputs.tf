###############################################################################
# Resource Group
###############################################################################

output "resource_group_name" {
  description = "Name of the deployed resource group."
  value       = azurerm_resource_group.rg.name
}

output "resource_group_id" {
  description = "Resource ID of the deployed resource group."
  value       = azurerm_resource_group.rg.id
}

###############################################################################
# Networking
###############################################################################

output "virtual_network_id" {
  description = "Resource ID of threathunt-vnet."
  value       = azurerm_virtual_network.vnet[local.vnet_name].id
}

output "subnet_ids" {
  description = "Map of subnet name → resource ID."
  value = {
    for key, subnet in azurerm_subnet.subnet :
    subnet.name => subnet.id
  }
}

output "route_table_id" {
  description = "Resource ID of the internal subnet route table (rt-snet-internal)."
  value       = azurerm_route_table.rt["rt-snet-internal"].id
}

###############################################################################
# FortiGate NVA
###############################################################################

output "fortigate_public_ip" {
  description = "Public IP address of DL-FG-PIP (FortiGate management / VPN)."
  value       = azurerm_public_ip.pip[local.fortigate_pip_name].ip_address
}

output "fortigate_port1_private_ip" {
  description = "Static private IP of FortiGate port1 (snet-external)."
  value       = azurerm_network_interface.nic[local.fortigate_nic1_name].private_ip_address
}

output "fortigate_port2_private_ip" {
  description = "Static private IP of FortiGate port2 (snet-internal) — UDR next-hop."
  value       = azurerm_network_interface.nic[local.fortigate_nic2_name].private_ip_address
}

output "fortigate_management_url" {
  description = "FortiGate HTTPS management URL."
  value       = "https://${azurerm_public_ip.pip[local.fortigate_pip_name].ip_address}"
}

###############################################################################
# FortiAnalyzer
###############################################################################

output "fortianalyzer_public_ip" {
  description = "Public IP address of DL-FAZ-PIP."
  value       = azurerm_public_ip.pip[local.fortianalyzer_pip_name].ip_address
}

output "fortianalyzer_private_ip" {
  description = "Dynamic private IP of FortiAnalyzer NIC (snet-external)."
  value       = azurerm_network_interface.nic[local.fortianalyzer_nic_name].private_ip_address
}

###############################################################################
# Workload VM
###############################################################################

output "watchtower_private_ip" {
  description = "Static private IP of the watchtower workload VM (snet-internal)."
  value       = azurerm_network_interface.nic[local.workload_nic_name].private_ip_address
}

###############################################################################
# Storage
###############################################################################

output "storage_account_name" {
  description = "Deployed storage account name (e.g. 20260224sdatalake)."
  value       = azurerm_storage_account.storage[local.storage_account_name].name
}

output "storage_container_name" {
  description = "Blob container used for FortiAnalyzer log archival."
  value       = azurerm_storage_container.container[local.blob_container_name].name
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account."
  value       = azurerm_storage_account.storage[local.storage_account_name].primary_blob_endpoint
}

###############################################################################
# Deployment Summary
###############################################################################

output "deployment_summary" {
  description = "High-level summary of the deployed lab environment."
  value = {
    resource_group   = azurerm_resource_group.rg.name
    location         = azurerm_resource_group.rg.location
    vnet             = local.vnet_name
    fortigate = {
      vm_name          = local.fortigate_vm_name
      public_ip        = azurerm_public_ip.pip[local.fortigate_pip_name].ip_address
      port1_private_ip = azurerm_network_interface.nic[local.fortigate_nic1_name].private_ip_address
      port2_private_ip = azurerm_network_interface.nic[local.fortigate_nic2_name].private_ip_address
      image_version    = var.fortigate_image_version
    }
    fortianalyzer = {
      vm_name     = local.fortianalyzer_vm_name
      public_ip   = azurerm_public_ip.pip[local.fortianalyzer_pip_name].ip_address
      private_ip  = azurerm_network_interface.nic[local.fortianalyzer_nic_name].private_ip_address
      image_version = var.fortianalyzer_image_version
    }
    workload = {
      vm_name    = local.workload_vm_name
      private_ip = azurerm_network_interface.nic[local.workload_nic_name].private_ip_address
    }
    storage_account = azurerm_storage_account.storage[local.storage_account_name].name
  }
}
