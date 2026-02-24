# Xperts Threat Hunting Lab — Azure Infrastructure

Terraform deployment for the Xperts Threat Hunting lab environment on Azure. Deploys a FortiGate NVA, FortiAnalyzer, a simulated workload VM, and a log archival storage account — all inside a single resource group and dual-subnet virtual network.

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  Resource Group: <resource_group_name>                  │
│                                                         │
│  threathunt-vnet (192.168.27.0/24)                      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  snet-external  192.168.27.0/27                  │   │
│  │  NSG: Allow 443 80 622 541 8080 / Deny-All        │   │
│  │                                                  │   │
│  │  ┌─────────────────┐   ┌─────────────────────┐  │   │
│  │  │  DL-FG (port1)  │   │  DL-FAZ             │  │   │
│  │  │  Static IP       │   │  Dynamic IP          │  │   │
│  │  │  DL-FG-PIP ──►  │   │  DL-FAZ-PIP ──►     │  │   │
│  │  └────────┬────────┘   └─────────────────────┘  │   │
│  └───────────│────────────────────────────────────┘    │
│              │ (FortiGate port2)                        │
│  ┌───────────▼────────────────────────────────────┐    │
│  │  snet-internal  192.168.27.32/27               │    │
│  │  NSG: Allow 22 / Deny-All                      │    │
│  │  UDR: 0.0.0.0/0 → fortigate_port2_ip           │    │
│  │                                                │    │
│  │  ┌─────────────────┐                           │    │
│  │  │  watchtower      │ 192.168.27.37            │    │
│  │  │  Ubuntu 24.04    │                           │    │
│  │  └─────────────────┘                           │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  Storage Account: <deploy_date>sdatalake                │
│  Container: fazdatalake  (accessible from snet-external)│
└─────────────────────────────────────────────────────────┘
```

**Traffic flow**: All egress from `snet-internal` is routed through FortiGate port2 via UDR before reaching the internet or other subnets. FortiAnalyzer collects FortiGate logs and archives them to the Blob Storage container.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Terraform | 1.5+ |
| AzureRM provider | ~> 4.0 |
| Azure CLI | 2.x (for auth) |

### Azure Marketplace Terms

FortiGate and FortiAnalyzer are marketplace images. Accept the terms **once per subscription** before deploying:

```bash
# FortiGate
az vm image terms accept \
  --publisher fortinet \
  --offer fortinet_fortigate-vm_v5 \
  --plan fortinet_fg-vm

# FortiAnalyzer
az vm image terms accept \
  --publisher fortinet \
  --offer fortinet-fortianalyzer \
  --plan fortinet-fortianalyzer
```

### Authentication

```bash
az login
az account set --subscription "<subscription-id>"
```

---

## Quick Start

```bash
# 1. Clone and enter the repo
git clone https://github.com/fortidz/xperts_threat_hunting.git
cd xperts_threat_hunting

# 2. Copy example vars and fill in values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 3. Set sensitive values as env variables (recommended — avoids writing secrets to disk)
export TF_VAR_admin_password="YourStr0ng!Pass"
export TF_VAR_fortiflex_fgt_token="FGT_TOKEN"   # optional
export TF_VAR_fortiflex_faz_token="FAZ_TOKEN"   # optional

# 4. Initialize, plan, apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `resource_group_name` | yes | — | Azure Resource Group name |
| `location` | no | `eastus` | Azure region |
| `admin_username` | no | `datalake` | Admin user for all VMs |
| `admin_password` | yes | — | Admin password (sensitive) |
| `fortigate_port1_ip` | yes | — | Static IP for FortiGate port1 (snet-external, .1–.30) |
| `fortigate_port2_ip` | yes | — | Static IP for FortiGate port2 (snet-internal, .36–.62) |
| `deploy_date` | yes | — | 8-digit date prefix for storage account (YYYYMMDD) |
| `fortigate_image_version` | no | `7.6.6` | FortiOS image version |
| `fortianalyzer_image_version` | no | `7.6.6` | FortiAnalyzer image version |
| `fortiflex_fgt_token` | no | `""` | FortiFlex token for FortiGate (sensitive) |
| `fortiflex_faz_token` | no | `""` | FortiFlex token for FortiAnalyzer (sensitive) |
| `tags` | no | `{}` | Additional tags for all resources |

---

## Key Outputs

| Output | Description |
|---|---|
| `fortigate_public_ip` | FortiGate management / VPN public IP |
| `fortigate_management_url` | `https://<public-ip>` |
| `fortigate_port1_private_ip` | FortiGate internal port1 IP (snet-external) |
| `fortigate_port2_private_ip` | FortiGate internal port2 IP (snet-internal / UDR next-hop) |
| `fortianalyzer_public_ip` | FortiAnalyzer public IP |
| `fortianalyzer_private_ip` | FortiAnalyzer private IP |
| `watchtower_private_ip` | Workload VM private IP (should be 192.168.27.37) |
| `storage_account_name` | Resolved storage account name |
| `deployment_summary` | Structured summary of all deployed resources |

```bash
terraform output fortigate_management_url
terraform output deployment_summary
```

---

## File Structure

```
xperts_threat_hunting/
├── SPEC.md                      # Architecture specification
├── README.md                    # This file
├── versions.tf                  # Terraform + AzureRM provider version pins
├── variables.tf                 # All input variables with validation
├── outputs.tf                   # All outputs organized by resource type
├── terraform.tfvars.example     # Example values (no secrets)
├── .gitignore                   # Excludes .tfvars, state, .terraform/
│
├── locals_constants.tf          # Named constants — ports, CIDRs, SKUs, names
├── locals_common.tf             # Shared resource_group_name, location, tags
├── locals_network.tf            # VNet, subnet, NSG, UDR configuration maps
├── locals_compute.tf            # Public IP, NIC, VM configuration maps
├── locals_storage.tf            # Storage account and container configuration
│
├── resource_resource_group.tf   # Azure Resource Group
├── resource_virtual_network.tf  # VNet + Subnets
├── resource_security_group.tf   # NSGs + subnet associations
├── resource_route_table.tf      # Route tables (UDR) + subnet associations
├── resource_public_ip.tf        # Public IPs (DL-FG-PIP, DL-FAZ-PIP)
├── resource_network_interface.tf # NICs for all VMs
├── resource_virtual_machine.tf  # FortiGate, FortiAnalyzer, watchtower VMs
├── resource_storage.tf          # Storage account + blob container
│
└── cloud-init/
    ├── fortigate.tpl            # FortiFlex bootstrap template for FortiGate
    └── fortianalyzer.tpl        # FortiFlex bootstrap template for FortiAnalyzer
```

---

## FortiFlex Licensing

When deploying BYOL via a Fortinet private offer (FortiFlex), provide the token so the VM skips the interactive FortiCloud registration:

```bash
export TF_VAR_fortiflex_fgt_token="XXXXXXXXXXXXXXXX"
export TF_VAR_fortiflex_faz_token="YYYYYYYYYYYYYYYY"
```

The token is injected via `custom_data` using a multipart/mixed MIME bootstrap. If tokens are left empty, VMs still deploy but require manual licensing after first boot.

---

## Troubleshooting

**FortiGate not reachable after deploy**
- Verify `fortigate_port1_ip` is within `snet-external` (`192.168.27.1–.30`)
- Check NSG `nsg-snet-external` allows port 443
- FortiGate first-boot can take 5–10 minutes; monitor via serial console

**workload VM cannot reach internet**
- Confirm `fortigate_port2_ip` matches the actual port2 IP shown in `terraform output`
- Verify the UDR `rt-snet-internal` is associated with `snet-internal`
- Ensure FortiGate has a default route policy permitting snet-internal traffic

**Storage account access denied**
- FortiAnalyzer must be in `snet-external` to satisfy the storage network rule
- The `Microsoft.Storage` service endpoint must be enabled on `snet-external` (handled by Terraform)

**Marketplace image error on `terraform apply`**
- Run the `az vm image terms accept` commands listed in Prerequisites
- Terms must be accepted once per subscription, not per deployment

---

## FortiCNAPP

FortiCNAPP integration is **deferred** — it will be specified and implemented in a future phase. No resources are provisioned for FortiCNAPP in this deployment.
