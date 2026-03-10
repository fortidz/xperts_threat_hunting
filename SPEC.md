# Xperts Threat Hunting Lab — Azure Architecture Specification

## Overview

A single-resource-group Azure deployment providing a threat hunting lab environment. It consists of a dual-subnet virtual network hosting a FortiGate NVA (firewall), a FortiAnalyzer (log aggregation), a workload VM (simulated target), and a Blob Storage account for log archiving.

---

## Terraform Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `student_number` | `number` | — | Student identifier (1–999). Drives unique DNS names: `dl-fg-<n>.dl.sxroomec.net`, `dl-faz-<n>.dl.sxroomec.net` |
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
| `aws_access_key` | `string` | — | AWS Access Key ID for Route 53 DNS record management (sensitive) |
| `aws_secret_key` | `string` | — | AWS Secret Access Key for Route 53 DNS record management (sensitive) |
| `fortigate_api_token` | `string` | — | REST API token for the `fortios` Terraform provider (sensitive) |
| `ipsec_psk` | `string` | — | Pre-shared key for IPsec VPN phase1 (sensitive) |
| `vpnuser1_password` | `string` | — | Password for local user `vpnuser1` (sensitive) |
| `guest_password` | `string` | — | Password for local user `guest` (sensitive) |
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
| 105 | Allow-Admin-HTTPS | 10443 | TCP | Inbound | Allow | FortiGate admin HTTPS (admin-sport) and fortios provider API |
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

### Bootstrap (`custom_data`)

**Always injected** — provides a complete day-zero configuration so the FortiGate is functional immediately after first boot. FortiFlex token injection is conditional. Inspired by the [40net-cloud/terraform-azure-fortigate](https://github.com/40net-cloud/terraform-azure-fortigate) reference architecture.

The bootstrap configures:

| Section | Detail |
|---|---|
| **Hostname** | `DL-FG` |
| **Admin HTTPS port** | `443` (default, explicit for clarity) |
| **Admin timeout** | 120 minutes |
| **SDN Connector** | Azure type, metadata IAM — enables automatic cloud resource discovery |
| **port1 (external)** | Static IP `var.fortigate_port1_ip` / `/27` mask, allowaccess: ping https ssh fgfm |
| **port2 (internal)** | Static IP `var.fortigate_port2_ip` / `/27` mask, allowaccess: ping |
| **Static route 1** | Default `0.0.0.0/0` via `snet-external` gateway (`cidrhost(snet-external, 1)`) on port1 |
| **Static route 2** | `snet-internal` CIDR via `snet-internal` gateway (`cidrhost(snet-internal, 1)`) on port2 |
| **Auto-update** | Disabled — prevents interference during bootstrap |
| **FortiFlex license** | Conditional: `execute vm-licence <token>` only when `var.fortiflex_fgt_token` is non-empty |

> Gateway addresses are computed using `cidrhost()` from the subnet CIDRs defined in `locals_constants.tf`. For the default `/27` layout: snet-external gateway = `192.168.27.1`, snet-internal gateway = `192.168.27.33`.

```
Content-Type: multipart/mixed; boundary="==FORTIGATE-BOOTSTRAP=="
MIME-Version: 1.0

--==FORTIGATE-BOOTSTRAP==
Content-Type: text/plain; charset="us-ascii"

config system global
    set hostname "DL-FG"
    set admin-sport 443
    set admintimeout 120
    set timezone 12
end
config system sdn-connector
    edit "azuresdn"
        set type azure
        set use-metadata-iam enable
    next
end
config system interface
    edit "port1"
        set alias "external"
        set mode static
        set ip <fortigate_port1_ip> <snet_external_mask>
        set allowaccess ping https ssh fgfm
    next
    edit "port2"
        set alias "internal"
        set mode static
        set ip <fortigate_port2_ip> <snet_internal_mask>
        set allowaccess ping
    next
end
config router static
    edit 1
        set gateway <snet_external_gateway>
        set device "port1"
    next
    edit 2
        set dst <snet_internal_cidr>
        set gateway <snet_internal_gateway>
        set device "port2"
    next
end
config system auto-update
    set status disable
end
# Only if var.fortiflex_fgt_token is non-empty:
execute vm-licence <fortiflex_fgt_token>
--==FORTIGATE-BOOTSTRAP==--
```

### Lifecycle Rule

All VMs use `lifecycle { ignore_changes = [custom_data] }`. This prevents Terraform from destroying and recreating a VM when only the bootstrap configuration changes — custom_data is only evaluated at first boot and has no effect on running instances.

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
| DNS Label | None (DNS managed by Route 53) |

> DNS is managed via Route 53: `dl-faz-<student-number>.dl.sxroomec.net` → FortiAnalyzer public IP. See [DNS (Route 53)](#dns-route-53) section.

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

## DNS (Route 53)

DNS records are managed automatically via the AWS `route53` provider. A records are created in the `dl.sxroomec.net` hosted zone after Azure public IPs are allocated.

| Record | Type | TTL | Target | Purpose |
|---|---|---|---|---|
| `dl-fg-<student-number>.dl.sxroomec.net` | A | 300 | FortiGate public IP (`DL-FG-PIP`) | Admin GUI, fortios provider API, SSL-VPN |
| `dl-faz-<student-number>.dl.sxroomec.net` | A | 300 | FortiAnalyzer public IP (`DL-FAZ-PIP`) | FortiAnalyzer management |

> The `student_number` variable drives unique per-student FQDNs. The hosted zone is looked up via `data.aws_route53_zone` by domain name. A Let's Encrypt wildcard certificate (`*.dl.sxroomec.net`) is injected at FortiGate bootstrap to serve valid TLS on the admin GUI (port 10443).

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
├── versions.tf                   # Terraform >= 1.5, AzureRM ~> 4.0, fortios ~> 1.22, AWS ~> 5.0
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
├── resource_dns.tf              # Route 53 A records (FortiGate + FortiAnalyzer)
│
├── locals_fortigate.tf          # FortiGate config values (system, firewall, VPN, etc.)
├── resource_fortigate_system.tf # FortiGate global settings, DNS, password policy
├── resource_fortigate_interface.tf # FortiGate port1/port2 interface config
├── resource_fortigate_router.tf # FortiGate static routes
├── resource_fortigate_address.tf # Firewall address objects + groups
├── resource_fortigate_service.tf # Firewall service groups
├── resource_fortigate_user.tf   # Local users + user groups
├── resource_fortigate_vpn.tf    # IPsec VPN phase1 + phase2
├── resource_fortigate_security.tf # IPS sensor, app-ctrl, webfilter profiles
├── resource_fortigate_policy.tf # Firewall policies, VIP/DNAT, local-in policy
├── resource_fortigate_log.tf    # FortiAnalyzer logging configuration
│
├── certs/                       # SSL certificates (git-ignored)
│
└── cloud-init/
    ├── fortigate.tpl             # Bootstrap: license, SSL certs, admin-server-cert
    └── fortianalyzer.tpl         # Bootstrap: hostname + FortiFlex license
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
| `fortigate_fqdn` | FortiGate DNS FQDN (`dl-fg-<n>.dl.sxroomec.net`, Route 53 managed) |
| `fortigate_management_url` | `https://dl-fg-<n>.dl.sxroomec.net:10443` |
| `fortianalyzer_public_ip` | Public IP address of `DL-FAZ-PIP` |
| `fortianalyzer_private_ip` | Static private IP of FortiAnalyzer NIC (`snet-external`) |
| `fortianalyzer_fqdn` | FortiAnalyzer DNS FQDN (`dl-faz-<n>.dl.sxroomec.net`, Route 53 managed) |
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
| `aws_access_key` | AWS Access Key ID for Route 53 |
| `aws_secret_key` | AWS Secret Access Key for Route 53 |
| `fortigate_api_token` | REST API token for fortios provider |
| `ipsec_psk` | IPsec VPN pre-shared key |
| `vpnuser1_password` | VPN user password |
| `guest_password` | Local guest user password |
