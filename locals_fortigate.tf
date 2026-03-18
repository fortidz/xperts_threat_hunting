locals {
  ###########################################################################
  # FortiGate — System Global
  ###########################################################################

  fgt_hostname          = "DL-fgt"
  fgt_alias             = "DL-fgt"
  fgt_admin_sport       = 10443
  fgt_admintimeout      = 60
  fgt_timezone          = "04" # US/Pacific (FortiOS timezone code)
  fgt_gui_theme         = "mariner"

  ###########################################################################
  # FortiGate — DNS
  ###########################################################################

  fgt_dns_primary              = "96.45.45.45"
  fgt_dns_secondary            = "96.45.46.46"
  fgt_dns_server_select_method = "failover"

  ###########################################################################
  # FortiGate — Network Interfaces
  ###########################################################################

  fgt_interfaces = {
    "port1" = {
      name        = "port1"
      ip          = "${var.fortigate_port1_ip} 255.255.255.224"
      allowaccess = "ping https ssh"
      alias       = "external"
      description = "external"
    }
    "port2" = {
      name        = "port2"
      ip          = "${var.fortigate_port2_ip} 255.255.255.224"
      allowaccess = "ping https ssh"
      alias       = "internal"
      description = "internal"
    }
  }

  ###########################################################################
  # FortiGate — Static Routes
  ###########################################################################

  fgt_static_routes = {
    "1" = {
      dst     = "0.0.0.0 0.0.0.0"
      gateway = "192.168.27.1"
      device  = "port1"
    }
    "2" = {
      dst     = "192.168.27.0 255.255.255.0"
      gateway = "192.168.27.33"
      device  = "port2"
    }
  }

  ###########################################################################
  # FortiGate — Firewall Address Objects
  ###########################################################################

  fgt_address_ipmask = {
    "WATCHTOWER" = {
      subnet               = "192.168.27.37 255.255.255.255"
      associated_interface = "port2"
    }
    "LAN_port2_192.168.27.32_27" = {
      subnet               = "192.168.27.32 255.255.255.224"
      associated_interface = ""
    }
    "RA_IPSEC_POOL_10.10.100.0_24" = {
      subnet               = "10.10.100.0 255.255.255.0"
      associated_interface = ""
    }
  }

  fgt_address_iprange = {
    "SSLVPN_TUNNEL_ADDR1" = {
      start_ip = "10.212.134.200"
      end_ip   = "10.212.134.210"
    }
  }

  fgt_address_fqdn = {
    "login.microsoftonline.com" = { fqdn = "login.microsoftonline.com" }
    "login.microsoft.com"       = { fqdn = "login.microsoft.com" }
    "login.windows.net"         = { fqdn = "login.windows.net" }
    "gmail.com"                 = { fqdn = "gmail.com" }
    "wildcard.google.com"       = { fqdn = "*.google.com" }
    "wildcard.dropbox.com"      = { fqdn = "*.dropbox.com" }
  }

  ###########################################################################
  # FortiGate — Firewall Address Groups
  ###########################################################################

  fgt_address_groups = {
    "G Suite" = {
      members = ["gmail.com", "wildcard.google.com"]
    }
    "Microsoft Office 365" = {
      members = ["login.microsoftonline.com", "login.microsoft.com", "login.windows.net"]
    }
  }

  ###########################################################################
  # FortiGate — Firewall Service Groups
  ###########################################################################

  fgt_service_groups = {
    "Email Access" = {
      members = ["DNS", "IMAP", "IMAPS", "POP3", "POP3S", "SMTP", "SMTPS"]
    }
    "Web Access" = {
      members = ["DNS", "HTTP", "HTTPS"]
    }
    "Windows AD" = {
      members = ["DCE-RPC", "DNS", "KERBEROS", "LDAP", "LDAP_UDP", "SAMBA", "SMB"]
    }
    "Exchange Server" = {
      members = ["DCE-RPC", "DNS", "HTTPS"]
    }
  }

  ###########################################################################
  # FortiGate — IPsec VPN
  ###########################################################################

  fgt_vpn_phase1 = {
    name              = "phase1"
    type              = "dynamic"
    interface         = "port1"
    ike_version       = "2"
    proposal          = "aes256-sha256"
    dhgrp             = "14"
    keylife           = 28800
    dpd               = "on-idle"
    dpd_retryinterval = 60
    mode_cfg          = "enable"
    net_device        = "enable"
    ipv4_start_ip     = "10.10.100.1"
    ipv4_end_ip       = "10.10.100.200"
    ipv4_dns_server1  = "1.1.1.1"
    ipv4_dns_server2  = "8.8.8.8"
    eap               = "enable"
    authusrgrp        = "RA_IPSEC_USERS"
    localid           = "vpnuser1"
    peertype          = "any"
    transport         = "auto"
  }

  fgt_vpn_phase2 = {
    name           = "phase2"
    phase1name     = "phase1"
    proposal       = "aes256-sha256"
    dhgrp          = "14"
    keylifeseconds = 3600
  }

  ###########################################################################
  # FortiGate — Local Users
  ###########################################################################

  fgt_local_users = {
    "guest" = {
      type     = "password"
      password = var.guest_password
    }
    "vpnuser1" = {
      type     = "password"
      password = var.vpnuser1_password
    }
  }

  ###########################################################################
  # FortiGate — User Groups
  ###########################################################################

  fgt_user_groups = {
    "SSO_Guest_Users" = {
      members = []
    }
    "Guest-group" = {
      members = ["guest"]
    }
    "RA_IPSEC_USERS" = {
      members = ["vpnuser1"]
    }
  }
}
