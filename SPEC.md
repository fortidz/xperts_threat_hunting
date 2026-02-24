# Xperts Threat Hunting Lab — Azure Architecture Specification

## Overview

A single-resource-group Azure deployment providing a threat hunting lab environment. It consists of a dual-subnet virtual network hosting a FortiGate NVA (firewall), a FortiAnalyzer (log aggregation), a workload VM (simulated target), and a Blob Storage account for log archiving.

---

## Terraform Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `resource_group_name` | `string` | — | Name of the Azure Resource Group |
| `location` | `string` | `"eastus"` | Azure region |
| `fortigate_image_version` | `string` | `"7.6.6"` | FortiOS image version for FortiGate VM (e.g. `7.6.6`, `8.0.0`) |
| `fortianalyzer_image_version` | `string` | `"7.6.6"` | FortiAnalyzer image version (e.g. `7.6.6`, `8.0.0`) |
| `fortiflex_fgt_token` | `string` | `""` | FortiFlex license token for FortiGate (`execute vm-licence <token>`). Leave empty to skip. |
| `fortiflex_faz_token` | `string` | `""` | FortiFlex license token for FortiAnalyzer (`execute vm-licence <token>`). Leave empty to skip. |
| `admin_username` | `string` | `"datalake"` | Admin username for all VMs |
| `admin_password` | `string` | — | Admin password for all VMs (sensitive) |
| `deploy_date` | `string` | — | Date string used in storage account name (format: `YYYYMMDD`, e.g. `20260224`) |

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

| Name | CIDR | Purpose |
|---|---|---|
| `snet-external` | `192.168.27.0/27` | Internet-facing. Hosts FortiGate port1 NIC, FortiAnalyzer, public-facing resources |
| `snet-internal` | `192.168.27.32/27` | Internal workload subnet. Hosts FortiGate port2 NIC and workload VM |

### User Defined Routes (UDR)

| Route Table | Applied To | Route | Next Hop |
|---|---|---|---|
| `rt-snet-internal` | `snet-internal` | `0.0.0.0/0` | FortiGate port2 private IP (snet-internal NIC) |

> All egress traffic from snet-internal is forced through the FortiGate NVA.

### Network Security Groups

#### NSG — `nsg-snet-external` (applied to snet-external)

| Priority | Name | Port(s) | Protocol | Direction | Access |
|---|---|---|---|---|---|
| 100 | Allow-HTTPS | 443 | TCP | Inbound | Allow |
| 110 | Allow-HTTP | 80 | TCP | Inbound | Allow |
| 120 | Allow-SSH-Mgmt | 622 | TCP | Inbound | Allow |
| 130 | Allow-541 | 541 | TCP | Inbound | Allow |
| 140 | Allow-8080 | 8080 | TCP | Inbound | Allow |
| 4096 | Deny-All | * | * | Inbound | Deny |

#### NSG — `nsg-snet-internal` (applied to snet-internal)

| Priority | Name | Port(s) | Protocol | Direction | Access |
|---|---|---|---|---|---|
| 100 | Allow-SSH | 22 | TCP | Inbound | Allow |
| 4096 | Deny-All | * | * | Inbound | Deny |

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
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |

### NICs

| NIC | Name | Subnet | IP Allocation | Public IP |
|---|---|---|---|---|
| port1 (NIC1) | `DL-FG-NIC1` | `snet-external` | Dynamic | `DL-FG-PIP` (Standard SKU) |
| port2 (NIC2) | `DL-FG-NIC2` | `snet-internal` | Dynamic | None |

> The UDR next-hop for snet-internal points to the private IP of `DL-FG-NIC2`.

### NSG on NIC1

Ports: TCP 443, 80, 622, 541, 8080 (inbound allow).

### FortiFlex Bootstrap (custom_data)

If `var.fortiflex_fgt_token` is non-empty, the following bootstrap config is injected via `custom_data`:

```
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/plain; charset="us-ascii"

config system auto-update
    set status disable
end
execute vm-licence <fortiflex_fgt_token>
--==BOUNDARY==--
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
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |
| Subnet | `snet-external` |
| Public IP Name | `DL-FAZ-PIP` |
| Public IP SKU | Standard |

### FortiFlex Bootstrap (custom_data)

If `var.fortiflex_faz_token` is non-empty, the following bootstrap config is injected via `custom_data`:

```
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/plain; charset="us-ascii"

execute vm-licence <fortiflex_faz_token>
--==BOUNDARY==--
```

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
| Admin Username | `var.admin_username` (`datalake`) |
| Admin Password | `var.admin_password` |
| Subnet | `snet-internal` |
| Private IP | `192.168.27.37` (static) |
| Public IP | None |
| NSG | TCP 22 (SSH) inbound only |

---

## Storage Account

| Property | Value |
|---|---|
| Name | `${var.deploy_date}sdatalake` (e.g. `20260224sdatalake`) |
| Kind | `StorageV2` |
| Performance | `Standard` |
| Replication | `LRS` |
| Access Tier | `Hot` |
| Public Network Access | Enabled |
| Network Rule | Allow from `threathunt-vnet / snet-external` only |
| Default Action | `Deny` |

> Azure storage account names must be lowercase alphanumeric, max 24 characters.
> `deploy_date` must be exactly 8 digits (YYYYMMDD) so the total name length is 16 chars.

### Blob Container

| Property | Value |
|---|---|
| Container Name | `fazdatalake` |
| Access Level | Private (blob-level access via storage account network rules) |

---

## Security Layer

### FortiCNAPP

> **Deferred** — FortiCNAPP integration to be specified and implemented at a later date. No resources will be provisioned for this component in the initial deployment.

---

## File Structure (Terraform)

```
xperts_threat_hunting/
├── SPEC.md                  # This file
├── main.tf                  # Root module — resource group, VNet, subnets
├── variables.tf             # All input variable declarations
├── outputs.tf               # Key outputs (Public IPs, private IPs, storage name)
├── terraform.tfvars.example # Example variable values (no secrets)
├── modules/
│   ├── fortigate/           # FortiGate NVA module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── fortianalyzer/       # FortiAnalyzer module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── workload/            # Workload VM module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── storage/             # Storage account + container module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── .gitignore               # Excludes *.tfvars, .terraform/, tfstate files
```

---

## Outputs

| Output | Description |
|---|---|
| `fortigate_public_ip` | Public IP address of DL-FG-PIP |
| `fortianalyzer_public_ip` | Public IP address of DL-FAZ-PIP |
| `watchtower_private_ip` | Private IP of the workload VM (should be 192.168.27.37) |
| `storage_account_name` | Resolved storage account name |
| `storage_container_name` | Blob container name (`fazdatalake`) |

---

## Sensitive Values Note

> `admin_password`, `fortiflex_fgt_token`, and `fortiflex_faz_token` are **sensitive** variables.
> They must **never** be committed to source control.
> Use `terraform.tfvars` (git-ignored) or environment variables (`TF_VAR_*`) to supply them.
