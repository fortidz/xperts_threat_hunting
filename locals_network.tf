locals {
  ###########################################################################
  # Virtual Network
  ###########################################################################

  virtual_networks = {
    (local.vnet_name) = merge(local.common_resource_attributes, {
      name          = local.vnet_name
      address_space = [local.vnet_address_space]
      tags          = local.common_tags
    })
  }

  ###########################################################################
  # Subnets
  ###########################################################################

  subnets = {
    "snet-external" = {
      name                 = "snet-external"
      virtual_network_name = local.vnet_name
      resource_group_name  = local.resource_group_name
      address_prefixes     = [local.snet_external_cidr]
      # Service endpoint required so the storage account network rule
      # can allow traffic from this subnet.
      service_endpoints = ["Microsoft.Storage"]
    }

    "snet-internal" = {
      name                 = "snet-internal"
      virtual_network_name = local.vnet_name
      resource_group_name  = local.resource_group_name
      address_prefixes     = [local.snet_internal_cidr]
      service_endpoints    = []
    }
  }

  ###########################################################################
  # Network Security Groups
  ###########################################################################

  network_security_groups = {
    "nsg-snet-external" = merge(local.common_resource_attributes, {
      name = "nsg-snet-external"
      tags = local.common_tags

      security_rules = [
        {
          name                       = "Allow-HTTPS"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.fgt_port_https
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiGate HTTPS GUI and SSL-VPN"
        },
        {
          name                       = "Allow-HTTP"
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.fgt_port_http
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiGate HTTP and captive portal redirect"
        },
        {
          name                       = "Allow-SSH-Mgmt"
          priority                   = 120
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.fgt_port_ssh_mgmt
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiGate custom SSH management port"
        },
        {
          name                       = "Allow-541"
          priority                   = 130
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.fgt_port_541
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiGate log forwarding and HA heartbeat"
        },
        {
          name                       = "Allow-8080"
          priority                   = 140
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.fgt_port_8080
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiGate alternate HTTP service port"
        },
        {
          name                       = "Allow-514"
          priority                   = 150
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.faz_device_reg_port
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "FortiAnalyzer device registration and syslog inbound from FortiGate"
        },
        {
          name                       = "Deny-All-Inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "Default deny — all other inbound traffic blocked"
        },
      ]
    })

    "nsg-snet-internal" = merge(local.common_resource_attributes, {
      name = "nsg-snet-internal"
      tags = local.common_tags

      security_rules = [
        {
          name                       = "Allow-SSH"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = local.ssh_port
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "SSH access to workload VM (watchtower)"
        },
        {
          name                       = "Deny-All-Inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "Default deny — all other inbound traffic blocked"
        },
      ]
    })
  }

  # Subnet → NSG associations
  nsg_subnet_associations = {
    "snet-external" = {
      subnet_key = "snet-external"
      nsg_key    = "nsg-snet-external"
    }
    "snet-internal" = {
      subnet_key = "snet-internal"
      nsg_key    = "nsg-snet-internal"
    }
  }

  ###########################################################################
  # Route Tables (UDR)
  ###########################################################################

  route_tables = {
    "rt-snet-internal" = merge(local.common_resource_attributes, {
      name = "rt-snet-internal"
      tags = local.common_tags
      # Disable BGP propagation — all routing controlled explicitly via UDR
      bgp_route_propagation_enabled = false

      routes = [
        {
          name                   = "route-default-via-fortigate"
          address_prefix         = "0.0.0.0/0"
          next_hop_type          = "VirtualAppliance"
          # UDR next-hop is the FortiGate internal (port2) static IP,
          # forcing all egress from snet-internal through the NVA.
          next_hop_in_ip_address = var.fortigate_port2_ip
        },
      ]
    })
  }

  # Route table → subnet associations
  route_table_subnet_associations = {
    "rt-snet-internal-assoc" = {
      subnet_key      = "snet-internal"
      route_table_key = "rt-snet-internal"
    }
  }
}
