###############################################################################
# FortiGate — Firewall VIP (Destination NAT)
###############################################################################

resource "fortios_firewall_vip" "watchtower_dnat" {
  name  = "WATCHTOWER_DNAT"
  extip = var.fortigate_port1_ip
  mappedip {
    range = local.watchtower_private_ip
  }
  extintf     = "port1"
  portforward = "enable"
  extport     = "622"
  mappedport  = "22"

  depends_on = [fortios_system_interface.interface]
}

###############################################################################
# FortiGate — Firewall Policies
###############################################################################

# Policy 1: Internet Access (port2 → port1, NAT, UTM)
resource "fortios_firewall_policy" "internet_access" {
  policyid         = 1
  name             = "Internet Access"
  action           = "accept"
  nat              = "enable"
  logtraffic       = "all"
  logtraffic_start = "enable"

  srcintf {
    name = "port2"
  }
  dstintf {
    name = "port1"
  }
  srcaddr {
    name = "all"
  }
  dstaddr {
    name = "all"
  }
  service {
    name = "ALL"
  }

  ssl_ssh_profile   = "deep-inspection"
  av_profile        = "default"
  webfilter_profile = fortios_webfilter_profile.monitor_everything.name
  dnsfilter_profile = "default"
  ips_sensor        = fortios_ips_sensor.ips_monitor.name
  application_list  = fortios_application_list.monitor_all.name

  depends_on = [fortios_system_interface.interface]
}

# Policy 2: Remote Access (SSH to Watchtower via DNAT)
resource "fortios_firewall_policy" "remote_access" {
  policyid         = 2
  name             = "Remote Access"
  action           = "accept"
  nat              = "disable"
  logtraffic       = "all"
  logtraffic_start = "enable"

  srcintf {
    name = "port1"
  }
  dstintf {
    name = "port2"
  }
  srcaddr {
    name = "all"
  }
  dstaddr {
    name = fortios_firewall_vip.watchtower_dnat.name
  }
  service {
    name = "SSH"
  }

  depends_on = [fortios_system_interface.interface]
}

# Policy 3: RA_IPSEC_to_LAN
resource "fortios_firewall_policy" "ra_ipsec_to_lan" {
  policyid   = 3
  name       = "RA_IPSEC_to_LAN"
  action     = "accept"
  nat        = "disable"
  logtraffic = "all"

  srcintf {
    name = fortios_vpnipsec_phase1interface.phase1.name
  }
  dstintf {
    name = "port2"
  }
  srcaddr {
    name = "RA_IPSEC_POOL_10.10.100.0_24"
  }
  dstaddr {
    name = "LAN_port2_192.168.27.32_27"
  }
  service {
    name = "ALL"
  }

  depends_on = [
    fortios_firewall_address.ipmask,
    fortios_system_interface.interface,
  ]
}

# Policy 4: LAN_to_RA_IPSEC
resource "fortios_firewall_policy" "lan_to_ra_ipsec" {
  policyid   = 4
  name       = "LAN_to_RA_IPSEC"
  action     = "accept"
  nat        = "disable"
  logtraffic = "all"

  srcintf {
    name = "port2"
  }
  dstintf {
    name = fortios_vpnipsec_phase1interface.phase1.name
  }
  srcaddr {
    name = "LAN_port2_192.168.27.32_27"
  }
  dstaddr {
    name = "RA_IPSEC_POOL_10.10.100.0_24"
  }
  service {
    name = "ALL"
  }

  depends_on = [
    fortios_firewall_address.ipmask,
    fortios_system_interface.interface,
  ]
}

# Policy 5: RA_IPSEC_to_Internet_FullTunnel
resource "fortios_firewall_policy" "ra_ipsec_to_internet" {
  policyid         = 5
  name             = "RA_IPSEC_to_Internet_FullTunnel"
  action           = "accept"
  nat              = "enable"
  logtraffic       = "all"
  logtraffic_start = "enable"

  srcintf {
    name = fortios_vpnipsec_phase1interface.phase1.name
  }
  dstintf {
    name = "port1"
  }
  srcaddr {
    name = "RA_IPSEC_POOL_10.10.100.0_24"
  }
  dstaddr {
    name = "all"
  }
  service {
    name = "ALL"
  }

  ssl_ssh_profile   = "deep-inspection"
  av_profile        = "default"
  webfilter_profile = fortios_webfilter_profile.monitor_all.name
  dnsfilter_profile = "default"
  ips_sensor        = fortios_ips_sensor.ips_monitor.name
  application_list  = "default"

  depends_on = [
    fortios_firewall_address.ipmask,
    fortios_system_interface.interface,
  ]
}

###############################################################################
# FortiGate — Local-In Policy (Threat Feed Block)
###############################################################################

resource "fortios_firewall_localinpolicy" "threat_feed_block" {
  policyid = 1
  action   = "deny"
  intf     = "any"
  schedule = "always"

  dstaddr {
    name = "all"
  }

  srcaddr {
    name = "all"
  }

  service {
    name = "ALL"
  }

  internet_service_src = "enable"

  internet_service_src_name {
    name = "Malicious-Malicious.Server"
  }
  internet_service_src_name {
    name = "Tor-Exit.Node"
  }
  internet_service_src_name {
    name = "Tor-Relay.Node"
  }
}
