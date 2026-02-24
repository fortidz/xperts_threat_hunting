resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.virtual_machines

  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  size                = each.value.vm_size
  admin_username      = each.value.admin_username
  admin_password      = var.admin_password

  # Password authentication is required for FortiOS / FortiAnalyzer appliances
  # and matches the lab credential model defined in the spec.
  disable_password_authentication = false

  # Build the ordered NIC list from vm_nic_keys.
  # The first NIC is always the primary interface.
  network_interface_ids = [
    for nic_key in local.vm_nic_keys[each.key] :
    azurerm_network_interface.nic[nic_key].id
  ]

  os_disk {
    name                 = "${each.value.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.os_disk_size
  }

  source_image_reference {
    publisher = each.value.publisher
    offer     = each.value.offer
    sku       = each.value.sku
    version   = each.value.image_version
  }

  # Marketplace plan block — required for FortiGate and FortiAnalyzer.
  # Ubuntu (workload VM) does not carry a plan block.
  dynamic "plan" {
    for_each = each.value.has_plan ? [1] : []

    content {
      name      = each.value.sku
      publisher = each.value.publisher
      product   = each.value.offer
    }
  }

  # FortiFlex bootstrap — pre-encoded base64 in locals_compute.tf.
  # null means no custom_data is injected (Ubuntu VM or no token supplied).
  custom_data = each.value.custom_data

  # Managed boot diagnostics (no storage URI = Azure-managed endpoint).
  # Provides serial console and screenshot access for troubleshooting.
  boot_diagnostics {}

  tags = each.value.tags

  depends_on = [azurerm_network_interface.nic]
}
