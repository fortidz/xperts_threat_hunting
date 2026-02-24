###############################################################################
# Required — Infrastructure Identity
###############################################################################

variable "resource_group_name" {
  description = "Name of the Azure Resource Group that contains all lab resources."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be 1-90 characters: letters, numbers, underscores, hyphens, dots, or parentheses."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. eastus, westus2, eastus2)."
  type        = string
  default     = "eastus"

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "centralus", "northcentralus", "southcentralus",
      "westeurope", "northeurope",
      "uksouth", "ukwest",
      "canadacentral", "canadaeast",
      "australiaeast", "australiasoutheast",
      "brazilsouth",
      "southeastasia", "eastasia",
      "japaneast", "japanwest"
    ], var.location)
    error_message = "Provide a valid Azure region slug (e.g. eastus, westeurope, canadacentral)."
  }
}

###############################################################################
# Required — Credentials (sensitive)
###############################################################################

variable "admin_username" {
  description = "Administrator username applied to all VMs (FortiGate, FortiAnalyzer, watchtower)."
  type        = string
  default     = "datalake"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.admin_username))
    error_message = "admin_username must start with a letter/underscore, be lowercase, and be 1-31 characters."
  }
}

variable "admin_password" {
  description = <<-EOT
    Administrator password applied to all VMs.

    Azure complexity requirements:
    - Minimum 12 characters
    - Must include uppercase, lowercase, digit, and special character
    - Cannot contain the username

    Supply via TF_VAR_admin_password env variable or a git-ignored terraform.tfvars.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters."
  }
}

###############################################################################
# Required — FortiGate Network (Static IPs)
###############################################################################

variable "fortigate_port1_ip" {
  description = <<-EOT
    Static private IP for FortiGate port1 NIC (external interface).
    Must be within snet-external: 192.168.27.0/27 (usable .1-.30, Azure reserves .0 .1 .2 .3 .31).
    Example: 192.168.27.4
  EOT
  type = string

  validation {
    condition     = can(regex("^192\\.168\\.27\\.([1-9]|[1-2][0-9]|30)$", var.fortigate_port1_ip))
    error_message = "fortigate_port1_ip must be within 192.168.27.1–192.168.27.30 (snet-external usable range)."
  }
}

variable "fortigate_port2_ip" {
  description = <<-EOT
    Static private IP for FortiGate port2 NIC (internal interface).
    Must be within snet-internal: 192.168.27.32/27 (usable .33-.62, Azure reserves .32 .33 .34 .35 .63).
    Example: 192.168.27.36
    Note: This IP is also the UDR next-hop for snet-internal default route.
  EOT
  type = string

  validation {
    condition     = can(regex("^192\\.168\\.27\\.(3[6-9]|[4-5][0-9]|6[0-2])$", var.fortigate_port2_ip))
    error_message = "fortigate_port2_ip must be within 192.168.27.36–192.168.27.62 (snet-internal usable range, excluding Azure-reserved .32-.35 .63)."
  }
}

variable "fortianalyzer_ip" {
  description = <<-EOT
    Static private IP for the FortiAnalyzer NIC (snet-external).
    Must be within snet-external: 192.168.27.0/27 (usable .1-.30, Azure reserves .0 .1 .2 .3 .31).
    Must not conflict with fortigate_port1_ip.
    Example: 192.168.27.5
    Note: FortiGate log profiles and device registration point to this IP;
    a static address prevents connectivity loss after VM restarts.
  EOT
  type = string

  validation {
    condition     = can(regex("^192\\.168\\.27\\.([1-9]|[1-2][0-9]|30)$", var.fortianalyzer_ip))
    error_message = "fortianalyzer_ip must be within 192.168.27.1–192.168.27.30 (snet-external usable range)."
  }
}

###############################################################################
# Required — Storage
###############################################################################

variable "deploy_date" {
  description = <<-EOT
    Eight-digit date string used as prefix in the storage account name.
    Format: YYYYMMDD (e.g. 20260224).
    Resulting storage account name: <deploy_date>sdatalake (e.g. 20260224sdatalake, 16 chars).
  EOT
  type = string

  validation {
    condition     = can(regex("^[0-9]{8}$", var.deploy_date))
    error_message = "deploy_date must be exactly 8 digits in YYYYMMDD format (e.g. 20260224)."
  }
}

###############################################################################
# Optional — FortiOS / FortiAnalyzer Image Versions
###############################################################################

variable "fortigate_image_version" {
  description = <<-EOT
    FortiOS image version for the FortiGate VM (Azure Marketplace).
    Common values: 7.6.6  |  8.0.0
    Run: az vm image list --publisher fortinet --offer fortinet_fortigate-vm_v5 --all --query "[].version"
  EOT
  type    = string
  default = "7.6.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.fortigate_image_version))
    error_message = "fortigate_image_version must be in semver format (e.g. 7.6.6 or 8.0.0)."
  }
}

variable "fortianalyzer_image_version" {
  description = <<-EOT
    FortiAnalyzer image version (Azure Marketplace).
    Common values: 7.6.6  |  8.0.0
    Run: az vm image list --publisher fortinet --offer fortinet-fortianalyzer --all --query "[].version"
  EOT
  type    = string
  default = "7.6.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.fortianalyzer_image_version))
    error_message = "fortianalyzer_image_version must be in semver format (e.g. 7.6.6 or 8.0.0)."
  }
}

###############################################################################
# Optional — FortiFlex License Bootstrap
###############################################################################

variable "fortiflex_fgt_token" {
  description = <<-EOT
    FortiFlex license token for the FortiGate VM.
    When provided, the VM custom_data injects: execute vm-licence <token>
    This bypasses the FortiCloud registration flow required for private-offer BYOL.
    Leave empty ("") to skip bootstrap injection.
  EOT
  type      = string
  default   = ""
  sensitive = true
}

variable "fortiflex_faz_token" {
  description = <<-EOT
    FortiFlex license token for the FortiAnalyzer VM.
    When provided, the VM custom_data injects: execute vm-licence <token>
    Leave empty ("") to skip bootstrap injection.
  EOT
  type      = string
  default   = ""
  sensitive = true
}

###############################################################################
# Optional — Tags
###############################################################################

variable "tags" {
  description = "Additional tags merged onto all resources. Keys/values follow Azure tag conventions (kebab-case keys)."
  type        = map(string)
  default     = {}
}
