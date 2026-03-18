###############################################################################
# FortiGate — System Global Settings
###############################################################################

resource "fortios_system_global" "global" {
  hostname          = local.fgt_hostname
  alias             = local.fgt_alias
  admin_sport       = local.fgt_admin_sport
  admintimeout      = local.fgt_admintimeout
  timezone          = local.fgt_timezone
  gui_theme         = local.fgt_gui_theme
}

###############################################################################
# FortiGate — DNS
###############################################################################

resource "fortios_system_dns" "dns" {
  primary   = local.fgt_dns_primary
  secondary = local.fgt_dns_secondary
}

###############################################################################
# FortiGate — System Password Policy
###############################################################################

resource "fortios_system_passwordpolicy" "policy" {
  status         = "enable"
  reuse_password = "disable"
}

###############################################################################
# FortiGate — Admin Access Profile
###############################################################################

resource "fortios_system_accprofile" "prof_admin" {
  name                  = "prof_admin"
  secfabgrp             = "read-write"
  ftviewgrp             = "read-write"
  authgrp               = "read-write"
  sysgrp                = "read-write"
  netgrp                = "read-write"
  loggrp                = "read-write"
  fwgrp                 = "read-write"
  vpngrp                = "read-write"
  utmgrp                = "read-write"
  wanoptgrp             = "read-write"
  wifi                  = "read-write"
  admintimeout_override = "disable"
}
