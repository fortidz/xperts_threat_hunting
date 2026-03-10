###############################################################################
# FortiGate — FortiAnalyzer Logging
###############################################################################

resource "fortios_log_fortianalyzer_setting" "faz" {
  status        = "enable"
  server        = var.fortianalyzer_ip
  upload_option = "realtime"
  reliable      = "enable"
}
