###############################################################################
# FortiGate — IPsec VPN Phase 1 (Remote Access Dialup)
###############################################################################

resource "fortios_vpnipsec_phase1interface" "phase1" {
  name              = local.fgt_vpn_phase1.name
  type              = local.fgt_vpn_phase1.type
  interface         = local.fgt_vpn_phase1.interface
  ike_version       = local.fgt_vpn_phase1.ike_version
  proposal          = local.fgt_vpn_phase1.proposal
  dhgrp             = local.fgt_vpn_phase1.dhgrp
  keylife           = local.fgt_vpn_phase1.keylife
  dpd               = local.fgt_vpn_phase1.dpd
  dpd_retryinterval = local.fgt_vpn_phase1.dpd_retryinterval
  mode_cfg          = local.fgt_vpn_phase1.mode_cfg
  net_device        = local.fgt_vpn_phase1.net_device
  ipv4_start_ip     = local.fgt_vpn_phase1.ipv4_start_ip
  ipv4_end_ip       = local.fgt_vpn_phase1.ipv4_end_ip
  ipv4_dns_server1  = local.fgt_vpn_phase1.ipv4_dns_server1
  ipv4_dns_server2  = local.fgt_vpn_phase1.ipv4_dns_server2
  eap               = local.fgt_vpn_phase1.eap
  authusrgrp        = local.fgt_vpn_phase1.authusrgrp
  localid           = local.fgt_vpn_phase1.localid
  psksecret         = var.ipsec_psk
  peertype          = local.fgt_vpn_phase1.peertype

  depends_on = [
    fortios_system_interface.interface,
    fortios_user_group.group,
  ]
}

###############################################################################
# FortiGate — IPsec VPN Phase 2
###############################################################################

resource "fortios_vpnipsec_phase2interface" "phase2" {
  name           = local.fgt_vpn_phase2.name
  phase1name     = fortios_vpnipsec_phase1interface.phase1.name
  proposal       = local.fgt_vpn_phase2.proposal
  dhgrp          = local.fgt_vpn_phase2.dhgrp
  keylifeseconds = local.fgt_vpn_phase2.keylifeseconds
}
