locals {
  ###########################################################################
  # Network topology
  ###########################################################################

  vnet_name          = "threathunt-vnet"
  vnet_address_space = "192.168.27.0/24"

  # Subnet CIDRs
  snet_external_cidr = "192.168.27.0/27"
  snet_internal_cidr = "192.168.27.32/27"

  # Workload VM static private IP (within snet-internal)
  watchtower_private_ip = "192.168.27.37"

  ###########################################################################
  # Firewall management ports — FortiGate external NIC (port1)
  ###########################################################################

  fgt_port_https    = "443"  # FortiGate HTTPS GUI / SSL-VPN
  fgt_port_http     = "80"   # FortiGate HTTP (redirect / captive portal)
  fgt_port_ssh_mgmt = "622"  # FortiGate custom SSH management port
  fgt_port_541      = "541"  # Log forwarding / HA heartbeat
  fgt_port_8080     = "8080" # Alternate HTTP service port

  # SSH for workload VM (snet-internal)
  ssh_port = "22"

  ###########################################################################
  # OS disk sizes (GB)
  ###########################################################################

  fortigate_disk_size_gb     = 30
  fortianalyzer_disk_size_gb = 500 # FAZ uses large OS disk for log storage
  workload_disk_size_gb      = 30

  ###########################################################################
  # Azure Marketplace image identifiers
  ###########################################################################

  fortigate_publisher = "fortinet"
  fortigate_offer     = "fortinet_fortigate-vm_v5"
  fortigate_sku       = "fortinet_fg-vm"

  fortianalyzer_publisher = "fortinet"
  fortianalyzer_offer     = "fortinet-fortianalyzer"
  fortianalyzer_sku       = "fortinet-fortianalyzer"

  ubuntu_publisher = "Canonical"
  ubuntu_offer     = "ubuntu-24_04-lts"
  ubuntu_sku       = "server"
  ubuntu_version   = "latest"

  ###########################################################################
  # VM sizes
  ###########################################################################

  fortigate_vm_size     = "Standard_D2_v4"
  fortianalyzer_vm_size = "Standard_DS4_v2"
  workload_vm_size      = "Standard_D2s_v3"

  ###########################################################################
  # Resource names (per specification)
  ###########################################################################

  fortigate_vm_name     = "DL-FG"
  fortianalyzer_vm_name = "DL-FAZ"
  workload_vm_name      = "watchtower"

  fortigate_nic1_name    = "DL-FG-NIC1"
  fortigate_nic2_name    = "DL-FG-NIC2"
  fortianalyzer_nic_name = "DL-FAZ-NIC"
  workload_nic_name      = "watchtower-NIC"

  fortigate_pip_name    = "DL-FG-PIP"
  fortianalyzer_pip_name = "DL-FAZ-PIP"

  ###########################################################################
  # Storage
  ###########################################################################

  blob_container_name = "fazdatalake"
}
