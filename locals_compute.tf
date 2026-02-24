locals {
  ###########################################################################
  # Public IPs
  ###########################################################################

  public_ips = {
    (local.fortigate_pip_name) = merge(local.common_resource_attributes, {
      name              = local.fortigate_pip_name
      sku               = "Standard"
      allocation_method = "Static"
      domain_name_label = null
      tags              = local.common_tags
    })

    (local.fortianalyzer_pip_name) = merge(local.common_resource_attributes, {
      name              = local.fortianalyzer_pip_name
      sku               = "Standard"
      allocation_method = "Static"
      # DNS label provides a stable FQDN for FortiGate log profiles and management bookmarks:
      # <prefix>-faz-pip.<region>.cloudapp.azure.com
      domain_name_label = lower("${local.deployment_prefix}-faz-pip")
      tags              = local.common_tags
    })
  }

  ###########################################################################
  # Network Interfaces
  ###########################################################################

  network_interfaces = {
    # FortiGate port1 — external-facing, carries management traffic and internet
    (local.fortigate_nic1_name) = merge(local.common_resource_attributes, {
      name                 = local.fortigate_nic1_name
      subnet_key           = "snet-external"
      private_ip_address   = var.fortigate_port1_ip
      private_ip_alloc     = "Static"
      public_ip_key        = local.fortigate_pip_name
      # ip_forwarding_enabled is required on both NICs for NVA packet routing
      ip_forwarding_enabled = true
      tags                  = local.common_tags
    })

    # FortiGate port2 — internal-facing; UDR next-hop points to this IP
    (local.fortigate_nic2_name) = merge(local.common_resource_attributes, {
      name                  = local.fortigate_nic2_name
      subnet_key            = "snet-internal"
      private_ip_address    = var.fortigate_port2_ip
      private_ip_alloc      = "Static"
      public_ip_key         = null
      ip_forwarding_enabled = true
      tags                  = local.common_tags
    })

    # FortiAnalyzer — single NIC in snet-external, static private IP.
    # Static IP is required: FortiGate log profiles and device registration
    # point to a fixed FAZ address; dynamic IPs break all connected FortiGates
    # after any VM restart.
    (local.fortianalyzer_nic_name) = merge(local.common_resource_attributes, {
      name                  = local.fortianalyzer_nic_name
      subnet_key            = "snet-external"
      private_ip_address    = var.fortianalyzer_ip
      private_ip_alloc      = "Static"
      public_ip_key         = local.fortianalyzer_pip_name
      ip_forwarding_enabled = false
      tags                  = local.common_tags
    })

    # Workload VM — single NIC in snet-internal, static private IP
    (local.workload_nic_name) = merge(local.common_resource_attributes, {
      name                  = local.workload_nic_name
      subnet_key            = "snet-internal"
      private_ip_address    = local.watchtower_private_ip
      private_ip_alloc      = "Static"
      public_ip_key         = null
      ip_forwarding_enabled = false
      tags                  = local.common_tags
    })
  }

  ###########################################################################
  # NIC key lists per VM (order matters — first NIC is the primary interface)
  ###########################################################################

  vm_nic_keys = {
    (local.fortigate_vm_name)     = [local.fortigate_nic1_name, local.fortigate_nic2_name]
    (local.fortianalyzer_vm_name) = [local.fortianalyzer_nic_name]
    (local.workload_vm_name)      = [local.workload_nic_name]
  }

  ###########################################################################
  # Virtual Machines
  ###########################################################################

  virtual_machines = {
    (local.fortigate_vm_name) = merge(local.common_resource_attributes, {
      name           = local.fortigate_vm_name
      vm_size        = local.fortigate_vm_size
      admin_username = var.admin_username
      publisher      = local.fortigate_publisher
      offer          = local.fortigate_offer
      sku            = local.fortigate_sku
      image_version  = var.fortigate_image_version
      os_disk_size   = local.fortigate_disk_size_gb
      has_plan       = true
      has_identity   = false

      # Inject FortiFlex bootstrap when token is provided.
      # The multipart/mixed MIME envelope is the format FortiOS expects.
      custom_data = var.fortiflex_fgt_token != "" ? base64encode(templatefile(
        "${path.module}/cloud-init/fortigate.tpl",
        { var_fortiflex_token = var.fortiflex_fgt_token }
      )) : null

      tags = local.common_tags
    })

    (local.fortianalyzer_vm_name) = merge(local.common_resource_attributes, {
      name           = local.fortianalyzer_vm_name
      vm_size        = local.fortianalyzer_vm_size
      admin_username = var.admin_username
      publisher      = local.fortianalyzer_publisher
      offer          = local.fortianalyzer_offer
      sku            = local.fortianalyzer_sku
      image_version  = var.fortianalyzer_image_version
      os_disk_size   = local.fortianalyzer_disk_size_gb
      has_plan       = true
      # System-assigned identity enables Azure AD authentication for the FAZ VM,
      # allowing it to access Azure services (Storage, Key Vault) without credentials.
      has_identity = true

      # Always inject custom_data for FAZ: sets hostname at first boot and
      # optionally applies the FortiFlex token. Hostname config is required
      # regardless of licensing method.
      custom_data = base64encode(templatefile(
        "${path.module}/cloud-init/fortianalyzer.tpl",
        {
          var_faz_vm_name     = local.fortianalyzer_vm_name
          var_fortiflex_token = var.fortiflex_faz_token
        }
      ))

      tags = local.common_tags
    })

    (local.workload_vm_name) = merge(local.common_resource_attributes, {
      name           = local.workload_vm_name
      vm_size        = local.workload_vm_size
      admin_username = var.admin_username
      publisher      = local.ubuntu_publisher
      offer          = local.ubuntu_offer
      sku            = local.ubuntu_sku
      image_version  = local.ubuntu_version
      os_disk_size   = local.workload_disk_size_gb
      has_plan       = false
      has_identity   = false
      custom_data    = null
      tags           = local.common_tags
    })
  }
}
