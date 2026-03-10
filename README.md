# Xperts Threat Hunting Lab — Azure Infrastructure

Terraform deployment for the Xperts Threat Hunting lab environment on Azure. Deploys a FortiGate NVA, FortiAnalyzer, a simulated workload VM, and a log archival storage account — all inside a single resource group and dual-subnet virtual network. FortiGate device configuration (firewall policies, VPN, security profiles, logging) is managed via the `fortios` Terraform provider.

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
│  │  NSG: Allow 443 10443 80 622 541 8080 / Deny-All │   │
│  │                                                  │   │
│  │  ┌─────────────────┐   ┌─────────────────────┐  │   │
│  │  │  DL-FG (port1)  │   │  DL-FAZ             │  │   │
│  │  │  Static IP       │   │  Static IP           │  │   │
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
| fortios provider | ~> 1.22 |
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

### SSL Certificates

The FortiGate admin GUI is served with a Let's Encrypt wildcard certificate (`*.sxroomec.net`). Before deploying, copy the certificate files into the `certs/` directory:

```bash
cp /path/to/sxroomec.net/fullchain.pem certs/
cp /path/to/sxroomec.net/privkey.pem   certs/
cp /path/to/sxroomec.net/chain.pem     certs/
```

The `certs/` directory is git-ignored — private keys must never be committed.

---

## Quick Start

### Phase 1 — Azure Infrastructure

```bash
# 1. Clone and enter the repo
git clone https://github.com/fortidz/xperts_threat_hunting.git
cd xperts_threat_hunting

# 2. Copy example vars and fill in values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 3. Place SSL certificates
mkdir -p certs
cp /path/to/sxroomec.net/{fullchain,privkey,chain}.pem certs/

# 4. Set sensitive values as env variables (recommended — avoids writing secrets to disk)
export TF_VAR_admin_password="YourStr0ng!Pass"
export TF_VAR_fortiflex_fgt_token="FGT_TOKEN"       # optional
export TF_VAR_fortiflex_faz_token="FAZ_TOKEN"        # optional
export TF_VAR_fortigate_api_token="API_TOKEN"
export TF_VAR_ipsec_psk="YourPSK"
export TF_VAR_vpnuser1_password="VpnUser1Pass!"
export TF_VAR_guest_password="GuestPass!"

# 5. Initialize, plan, apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Phase 2 — FortiGate Configuration

After the Azure infrastructure is deployed and the FortiGate VM is booted:

1. Ensure DNS `dl-fg-<student-number>.sxroomec.net` resolves to the FortiGate public IP
2. Create a REST API admin token on the FortiGate (System > Administrators > REST API Admin)
3. Set `fortigate_api_hostname` in `terraform.tfvars` (e.g., `dl-fg-01.sxroomec.net:10443`)
4. Run `terraform apply` again — the `fortios` provider will configure the device

> The SSL certificate is injected at bootstrap (cloud-init), so the admin GUI
> serves a valid Let's Encrypt cert from first boot. The `fortios` provider
> connects with TLS validation enabled (`insecure = false`).

---

## Variables

### Infrastructure

| Variable | Required | Default | Description |
|---|---|---|---|
| `resource_group_name` | yes | — | Azure Resource Group name |
| `location` | no | `eastus` | Azure region |
| `admin_username` | no | `datalake` | Admin user for all VMs |
| `admin_password` | yes | — | Admin password (sensitive) |
| `fortigate_port1_ip` | yes | — | Static IP for FortiGate port1 (snet-external, .1–.30) |
| `fortigate_port2_ip` | yes | — | Static IP for FortiGate port2 (snet-internal, .36–.62) |
| `fortianalyzer_ip` | yes | — | Static IP for FortiAnalyzer (snet-external, .1–.30) |
| `deploy_date` | yes | — | 8-digit date prefix for storage account (YYYYMMDD) |
| `fortigate_image_version` | no | `7.6.6` | FortiOS image version |
| `fortianalyzer_image_version` | no | `7.6.6` | FortiAnalyzer image version |
| `fortiflex_fgt_token` | no | `""` | FortiFlex token for FortiGate (sensitive) |
| `fortiflex_faz_token` | no | `""` | FortiFlex token for FortiAnalyzer (sensitive) |
| `tags` | no | `{}` | Additional tags for all resources |

### FortiGate Configuration (fortios provider)

| Variable | Required | Default | Description |
|---|---|---|---|
| `fortigate_api_hostname` | yes | — | FortiGate API FQDN (`dl-fg-<student>.sxroomec.net:10443`) |
| `fortigate_api_token` | yes | — | REST API token (sensitive) |
| `ipsec_psk` | yes | — | IPsec VPN pre-shared key (sensitive) |
| `vpnuser1_password` | yes | — | Password for VPN user `vpnuser1` (sensitive) |
| `guest_password` | yes | — | Password for local user `guest` (sensitive) |

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
├── SPEC.md                          # Azure architecture specification
├── SPEC_fortigate_config.md         # FortiGate configuration deployment spec
├── README.md                        # This file
├── versions.tf                      # Terraform + AzureRM + fortios provider version pins
├── variables.tf                     # All input variables with validation
├── outputs.tf                       # All outputs organized by resource type
├── terraform.tfvars.example         # Example values (no secrets)
├── .gitignore                       # Excludes .tfvars, state, .terraform/, certs/
│
├── locals_constants.tf              # Named constants — ports, CIDRs, SKUs, names
├── locals_common.tf                 # Shared resource_group_name, location, tags
├── locals_network.tf                # VNet, subnet, NSG, UDR configuration maps
├── locals_compute.tf                # Public IP, NIC, VM configuration maps
├── locals_storage.tf                # Storage account and container configuration
├── locals_fortigate.tf              # FortiGate config values (system, firewall, VPN, etc.)
│
├── resource_resource_group.tf       # Azure Resource Group
├── resource_virtual_network.tf      # VNet + Subnets
├── resource_security_group.tf       # NSGs + subnet associations
├── resource_route_table.tf          # Route tables (UDR) + subnet associations
├── resource_public_ip.tf            # Public IPs (DL-FG-PIP, DL-FAZ-PIP)
├── resource_network_interface.tf    # NICs for all VMs
├── resource_virtual_machine.tf      # FortiGate, FortiAnalyzer, watchtower VMs
├── resource_storage.tf              # Storage account + blob container
│
├── resource_fortigate_system.tf     # FortiGate global settings, DNS, password policy
├── resource_fortigate_interface.tf  # FortiGate port1/port2 interface config
├── resource_fortigate_router.tf     # FortiGate static routes
├── resource_fortigate_address.tf    # Firewall address objects + groups
├── resource_fortigate_service.tf    # Firewall service groups
├── resource_fortigate_user.tf       # Local users + user groups
├── resource_fortigate_vpn.tf        # IPsec VPN phase1 + phase2
├── resource_fortigate_security.tf   # IPS sensor, app-ctrl, webfilter profiles
├── resource_fortigate_policy.tf     # Firewall policies, VIP/DNAT, local-in policy
├── resource_fortigate_log.tf        # FortiAnalyzer logging configuration
│
├── certs/                           # SSL certificates (git-ignored)
│   ├── fullchain.pem                #   Server cert + intermediate chain
│   ├── privkey.pem                  #   Private key
│   └── chain.pem                    #   Let's Encrypt intermediate CA
│
└── cloud-init/
    ├── fortigate.tpl                # Bootstrap: license, SSL certs, admin-server-cert
    └── fortianalyzer.tpl            # Bootstrap: hostname + FortiFlex license
```

---

## FortiGate Configuration Overview

The `fortios` provider manages the full FortiGate device configuration:

| Category | Resources |
|----------|-----------|
| **System** | Global settings (hostname, admin-sport 10443, admin-server-cert), DNS, password policy, access profile |
| **SSL Certificates** | Let's Encrypt wildcard cert (`*.sxroomec.net`) injected at bootstrap for admin GUI TLS |
| **Interfaces** | port1 (external), port2 (internal) with static IPs and access control |
| **Routing** | Default route via port1, internal subnet route via port2 |
| **Firewall Objects** | Address objects (ipmask, iprange, FQDN), address groups, service groups |
| **Firewall Policies** | 5 policies: Internet access, remote access (SSH DNAT), IPsec-to-LAN, LAN-to-IPsec, IPsec-to-Internet |
| **VIP/DNAT** | WATCHTOWER_DNAT — port1:622 maps to watchtower:22 |
| **Security Profiles** | IPS (monitor-only), app-ctrl (monitor all), webfilter (monitor all) |
| **IPsec VPN** | Remote access dialup (IKEv2, AES256-SHA256, EAP, mode-cfg pool 10.10.100.0/24) |
| **Users** | Local users (guest, vpnuser1), user groups (RA_IPSEC_USERS) |
| **Logging** | FortiAnalyzer integration (realtime upload, reliable transport) |
| **Local-In Policy** | Blocks inbound from Tor exit/relay nodes and malicious servers |

See `SPEC_fortigate_config.md` for the full configuration specification.

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
- Check NSG `nsg-snet-external` allows ports 443 and 10443
- FortiGate first-boot can take 5–10 minutes; monitor via serial console

**fortios provider connection error**
- Ensure DNS `dl-fg-<student-number>.sxroomec.net` resolves to the FortiGate public IP
- Verify the REST API token is valid and has the correct admin profile
- Confirm the SSL certificate files are present in `certs/` (fullchain.pem, privkey.pem, chain.pem)
- Check that port 10443 is reachable (NSG Allow-Admin-HTTPS rule at priority 105)

**TLS certificate validation error on fortios provider**
- The `fortios` provider uses `insecure = false` — requires a valid cert matching the hostname
- Verify the FQDN in `fortigate_api_hostname` matches the cert SAN (`*.sxroomec.net`)
- Ensure cert files in `certs/` are current (Let's Encrypt certs expire every 90 days)

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
