# Xperts Threat Hunting Lab — Azure Architecture Specification

## Overview

A single-resource-group Azure deployment providing a threat hunting lab environment. It consists of a dual-subnet virtual network hosting a FortiGate NVA (firewall), a FortiAnalyzer (log aggregation), a workload VM (simulated target), and a Blob Storage account for log archiving.

---

## Terraform Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `resource_group_name` | `string` | — | Name of the Azure Resource Group |
| `location` | `string` | `"eastus"` | Azure region |
| `admin_username` | `string` | `"datalake"` | Admin username for all VMs |
| `admin_password` | `string` | — | Admin password for all VMs (sensitive) |
| `fortigate_port1_ip` | `string` | — | Static private IP for FortiGate port1 NIC (must be within `snet-external` — `192.168.27.1–.30`) |
| `fortigate_port2_ip` | `string` | — | Static private IP for FortiGate port2 NIC (must be within `snet-internal` — `192.168.27.36–.62`). Also the UDR next-hop. |
| `fortianalyzer_ip` | `string` | — | Static private IP for FortiAnalyzer NIC (must be within `snet-external` — `192.168.27.1–.30`, must not conflict with `fortigate_port1_ip`) |
| `deploy_date` | `string` | — | 8-digit date prefix for storage account name (`YYYYMMDD`, e.g. `20260224`) |
| `fortigate_image_version` | `string` | `"7.6.6"` | FortiOS image version for FortiGate VM (e.g. `7.6.6`, `8.0.0`) |
| `fortianalyzer_image_version` | `string` | `"7.6.6"` | FortiAnalyzer image version (e.g. `7.6.6`, `8.0.0`) |
| `fortiflex_fgt_token` | `string` | `""` | FortiFlex license token for FortiGate. Injected via `custom_data`. Leave empty to skip. (sensitive) |
| `fortiflex_faz_token` | `string` | `""` | FortiFlex license token for FortiAnalyzer. Injected via `custom_data`. Leave empty to skip. (sensitive) |
| `tags` | `map(string)` | `{}` | Additional tags merged onto all resources |

---

## Resource Group

| Property | Value |
|---|---|
| Name | `var.resource_group_name` |
| Location | `var.location` |

All resources below are deployed into this single resource group.

---

## Networking

### Virtual Network

| Property | Value |
|---|---|
| Name | `threathunt-vnet` |
| Address Space | `192.168.27.0/24` |

### Subnets

| Name | CIDR | Service Endpoints | Purpose |
|---|---|---|---|
| `snet-external` | `192.168.27.0/27` | `Microsoft.Storage` | Internet-facing. Hosts FortiGate port1 NIC, FortiAnalyzer, public-facing resources |
| `snet-internal` | `192.168.27.32/27` | — | Internal workload subnet. Hosts FortiGate port2 NIC and workload VM |

> `snet-external` carries the `Microsoft.Storage` service endpoint so the storage account network rule can scope access to this subnet.

### User Defined Routes (UDR)

| Route Table | Applied To | Route | Next Hop Type | Next Hop |
|---|---|---|---|---|
| `rt-snet-internal` | `snet-internal` | `0.0.0.0/0` | VirtualAppliance | `var.fortigate_port2_ip` |

> All egress traffic from `snet-internal` is forced through the FortiGate NVA. BGP route propagation is disabled on `rt-snet-internal`.

### Network Security Groups

#### NSG — `nsg-snet-external` (applied to snet-external)

| Priority | Name | Port(s) | Protocol | Direction | Access | Description |
|---|---|---|---|---|---|---|
| 100 | Allow-HTTPS | 443 | TCP | Inbound | Allow | FortiGate HTTPS GUI and SSL-VPN |
| 110 | Allow-HTTP | 80 | TCP | Inbound | Allow | FortiGate HTTP / captive portal redirect |
| 120 | Allow-SSH-Mgmt | 622 | TCP | Inbound | Allow | FortiGate custom SSH management port |
| 130 | Allow-541 | 541 | TCP | Inbound | Allow | FortiGate log forwarding and HA heartbeat |
| 140 | Allow-8080 | 8080 | TCP | Inbound | Allow | FortiGate alternate HTTP service port |
| 150 | Allow-514 | 514 | TCP | Inbound | Allow | FortiAnalyzer device registration and syslog inbound from FortiGate |
| 4096 | Deny-All-Inbound | * | * | Inbound | Deny | Default deny — all other inbound traffic blocked |

#### NSG — `nsg-snet-internal` (applied to snet-internal)

| Priority | Name | Port(s) | Protocol | Direction | Access | Description |
|---|---|---|---|---|---|---|
| 100 | Allow-SSH | 22 | TCP | Inbound | Allow | SSH access to workload VM (watchtower) |
| 4096 | Deny-All-Inbound | * | * | Inbound | Deny | Default deny — all other inbound traffic blocked |

---

## FortiGate NVA — `DL-FG`

| Property | Value |
|---|---|
| VM Name | `DL-FG` |
| Name Prefix | `DL` |
| VM Size | `Standard_D2_v4` |
| Publisher | `fortinet` |
| Offer | `fortinet_fortigate-vm_v5` |
| SKU | `fortinet_fg-vm` |
| Image Version | `var.fortigate_image_version` |
| OS Disk Size | 30 GB |
| OS Disk Type | `Premium_LRS` |
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |
| Managed Identity | None |
| Boot Diagnostics | Enabled (Azure-managed) |

### NICs

| NIC | Name | Subnet | IP Allocation | Private IP | IP Forwarding | Public IP |
|---|---|---|---|---|---|---|
| port1 (NIC1) | `DL-FG-NIC1` | `snet-external` | Static | `var.fortigate_port1_ip` | Enabled | `DL-FG-PIP` (Standard SKU) |
| port2 (NIC2) | `DL-FG-NIC2` | `snet-internal` | Static | `var.fortigate_port2_ip` | Enabled | None |

> IP forwarding is enabled on both NICs — required for NVA packet routing between subnets.
> The UDR next-hop for `snet-internal` points to `var.fortigate_port2_ip`.

### FortiFlex Bootstrap (`custom_data`)

Injected **only when** `var.fortiflex_fgt_token` is non-empty:

```
Content-Type: multipart/mixed; boundary="==FORTIGATE-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIGATE-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system auto-update
    set status disable
end
execute vm-licence <fortiflex_fgt_token>
--==FORTIGATE-BOOTSTRAP==--
```

---

## FortiAnalyzer — `DL-FAZ`

| Property | Value |
|---|---|
| VM Name | `DL-FAZ` |
| Name Prefix | `DL` |
| VM Size | `Standard_DS4_v2` |
| Publisher | `fortinet` |
| Offer | `fortinet-fortianalyzer` |
| SKU | `fortinet-fortianalyzer` |
| Image Version | `var.fortianalyzer_image_version` |
| OS Disk Size | 500 GB |
| OS Disk Type | `Premium_LRS` |
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |
| Managed Identity | `SystemAssigned` |
| Boot Diagnostics | Enabled (Azure-managed) |

### NIC

| NIC | Name | Subnet | IP Allocation | Private IP | IP Forwarding | Public IP |
|---|---|---|---|---|---|---|
| NIC1 | `DL-FAZ-NIC` | `snet-external` | Static | `var.fortianalyzer_ip` | Disabled | `DL-FAZ-PIP` (Standard SKU) |

> Static IP is required: FortiGate log profiles and device registration reference a fixed FAZ address. A dynamic IP would break all connected FortiGates after any VM restart.

### Public IP — `DL-FAZ-PIP`

| Property | Value |
|---|---|
| SKU | Standard |
| Allocation | Static |
| DNS Label | `dl-faz-pip` |
| FQDN | `dl-faz-pip.<region>.cloudapp.azure.com` |

> The DNS label provides a stable hostname for use in FortiGate log profiles and management bookmarks, avoiding hardcoded IP references.

### Bootstrap (`custom_data`)

**Always injected** for FortiAnalyzer — sets hostname at first boot regardless of licensing method. FortiFlex token injection is conditional.

```
Content-Type: multipart/mixed; boundary="==FORTIANALYZER-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIANALYZER-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system global
    set hostname "DL-FAZ"
end
# Only if var.fortiflex_faz_token is non-empty:
execute vm-licence <fortiflex_faz_token>
--==FORTIANALYZER-BOOTSTRAP==--
```

### Managed Identity

A **System-Assigned Managed Identity** is provisioned on the FAZ VM. This allows FortiAnalyzer to authenticate to Azure services (Storage, Key Vault) using Azure AD without storing credentials.

---

## Workload VM — `watchtower`

| Property | Value |
|---|---|
| VM Name | `watchtower` |
| VM Size | `Standard_D2s_v3` |
| OS | Ubuntu 24.04 LTS x64 Gen2 |
| Publisher | `Canonical` |
| Offer | `ubuntu-24_04-lts` |
| SKU | `server` |
| OS Disk Size | 30 GB |
| OS Disk Type | `Premium_LRS` |
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |
| Subnet | `snet-internal` |
| Private IP | `192.168.27.37` (static) |
| Public IP | None |
| NSG | TCP 22 (SSH) inbound only — via `nsg-snet-internal` |
| Managed Identity | None |
| Boot Diagnostics | Enabled (Azure-managed) |

---

## Storage Account

| Property | Value |
|---|---|
| Name | `${var.deploy_date}sdatalake` (e.g. `20260224sdatalake`, 16 chars) |
| Kind | `StorageV2` |
| Performance | `Standard` |
| Replication | `LRS` |
| Access Tier | `Hot` |
| HTTPS Only | Enabled |
| Minimum TLS | `TLS1_2` |
| Public Network Access | Enabled (scoped — see network rule) |
| Network Rule Default | `Deny` |
| Network Rule Allow | `snet-external` via service endpoint |
| Bypass | `AzureServices` |

> Azure storage account names must be lowercase alphanumeric, max 24 characters.
> `deploy_date` must be exactly 8 digits (YYYYMMDD) so the total name is 16 chars.

### Blob Container

| Property | Value |
|---|---|
| Container Name | `fazdatalake` |
| Access Level | Private |

---

## Security Layer

### FortiCNAPP

> **Deferred** — FortiCNAPP integration to be specified and implemented at a later date. No resources will be provisioned for this component in the initial deployment.

---

## File Structure (Terraform)

Flat configuration-as-data layout. No sub-modules. `locals_*.tf` files define *what* to create; `resource_*.tf` files define *how* to create it using `for_each`.

```
xperts_threat_hunting/
├── SPEC.md                       # This file
├── README.md                     # Deployment guide and quick start
├── versions.tf                   # Terraform >= 1.5 and AzureRM ~> 4.0
├── variables.tf                  # All input variables with validation
├── outputs.tf                    # All outputs organised by resource type
├── terraform.tfvars.example      # Example variable values (no secrets)
├── .gitignore                    # Excludes *.tfvars, .terraform/, tfstate files
│
├── locals_constants.tf           # Named constants — ports, CIDRs, SKUs, VM names
├── locals_common.tf              # Shared resource_group_name, location, tags
├── locals_network.tf             # VNet, subnet, NSG, UDR configuration maps
├── locals_compute.tf             # Public IP, NIC, VM configuration maps
├── locals_storage.tf             # Storage account and container configuration
│
├── resource_resource_group.tf    # Azure Resource Group
├── resource_virtual_network.tf   # VNet + Subnets
├── resource_security_group.tf    # NSGs + subnet associations
├── resource_route_table.tf       # Route tables (UDR) + subnet associations
├── resource_public_ip.tf         # Public IPs (DL-FG-PIP, DL-FAZ-PIP)
├── resource_network_interface.tf # NICs for all VMs
├── resource_virtual_machine.tf   # FortiGate, FortiAnalyzer, watchtower VMs
├── resource_storage.tf           # Storage account + blob container
│
└── cloud-init/
    ├── fortigate.tpl             # FortiFlex bootstrap template for FortiGate
    └── fortianalyzer.tpl         # Hostname + FortiFlex bootstrap for FortiAnalyzer
```

---

## Outputs

| Output | Description |
|---|---|
| `resource_group_name` | Name of the deployed resource group |
| `resource_group_id` | Resource ID of the deployed resource group |
| `virtual_network_id` | Resource ID of `threathunt-vnet` |
| `subnet_ids` | Map of subnet name → resource ID |
| `route_table_id` | Resource ID of `rt-snet-internal` |
| `fortigate_public_ip` | Public IP address of `DL-FG-PIP` |
| `fortigate_port1_private_ip` | Static private IP of FortiGate port1 (`snet-external`) |
| `fortigate_port2_private_ip` | Static private IP of FortiGate port2 (`snet-internal`) — UDR next-hop |
| `fortigate_management_url` | `https://<fortigate_public_ip>` |
| `fortianalyzer_public_ip` | Public IP address of `DL-FAZ-PIP` |
| `fortianalyzer_private_ip` | Static private IP of FortiAnalyzer NIC (`snet-external`) |
| `fortianalyzer_fqdn` | DNS FQDN of `DL-FAZ-PIP` — use in FortiGate log profiles |
| `watchtower_private_ip` | Static private IP of `watchtower` (should be `192.168.27.37`) |
| `storage_account_name` | Resolved storage account name (e.g. `20260224sdatalake`) |
| `storage_container_name` | Blob container name (`fazdatalake`) |
| `storage_primary_blob_endpoint` | Primary blob endpoint URL |
| `deployment_summary` | Structured map of all key resource details |

---

## Sensitive Values

> The following variables are marked `sensitive = true` and must **never** be committed to source control.
> Supply them via `TF_VAR_*` environment variables or a git-ignored `terraform.tfvars` file.

| Variable | Notes |
|---|---|
| `admin_password` | Applied to all VMs |
| `fortiflex_fgt_token` | FortiGate FortiFlex license token |
| `fortiflex_faz_token` | FortiAnalyzer FortiFlex license token |
