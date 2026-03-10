###############################################################################
# FortiGate — IPS Sensor (monitor-only)
###############################################################################

resource "fortios_ips_sensor" "ips_monitor" {
  name = "ips_monitor"

  entries {
    id         = 1
    status     = "enable"
    action     = "pass"
    log_packet = "enable"

    rule {
      id = 0
    }
  }
}

###############################################################################
# FortiGate — Application Control (monitor all)
###############################################################################

resource "fortios_application_list" "monitor_all" {
  name                     = "monitor_all"
  other_application_log    = "enable"
  unknown_application_log  = "enable"
  enforce_default_app_port = "enable"

  entries {
    id     = 1
    action = "pass"

    category {
      id = 2
    }
    category {
      id = 3
    }
    category {
      id = 5
    }
    category {
      id = 6
    }
    category {
      id = 7
    }
    category {
      id = 8
    }
    category {
      id = 12
    }
    category {
      id = 15
    }
    category {
      id = 17
    }
    category {
      id = 21
    }
    category {
      id = 22
    }
    category {
      id = 23
    }
    category {
      id = 25
    }
    category {
      id = 26
    }
    category {
      id = 28
    }
    category {
      id = 29
    }
    category {
      id = 30
    }
    category {
      id = 31
    }
    category {
      id = 32
    }
    category {
      id = 36
    }
  }
}

###############################################################################
# FortiGate — Web Filter Profile: Monitor_Everything
###############################################################################

resource "fortios_webfilter_profile" "monitor_everything" {
  name = "Monitor_Everything"

  ftgd_wf {
    filters {
      id     = 1
      action = "monitor"

      category = 0
    }
  }
}

###############################################################################
# FortiGate — Web Filter Profile: monitor-all
###############################################################################

resource "fortios_webfilter_profile" "monitor_all" {
  name    = "monitor-all"
  comment = "Monitor and log all visited URLs, flow-based."

  ftgd_wf {
    filters {
      id     = 1
      action = "monitor"

      category = 0
    }
  }
}
