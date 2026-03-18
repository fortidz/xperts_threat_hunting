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
| Azure CLI | 2.x (for local auth) |

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

---

## Deployment Options

### Option A — Local CLI

#### Authentication

```bash
az login
az account set --subscription "<subscription-id>"
```

#### Phase 1 — Azure Infrastructure

```bash
# 1. Clone and enter the repo
git clone https://github.com/fortidz/xperts_threat_hunting.git
cd xperts_threat_hunting

# 2. Copy example vars and fill in values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 3. Set sensitive values as env variables (avoids writing secrets to disk)
export TF_VAR_admin_password="YourStr0ng!Pass"
export TF_VAR_fortigate_api_token="API_TOKEN"
export TF_VAR_ipsec_psk="YourPSK"
export TF_VAR_vpnuser1_password="VpnUser1Pass!"
export TF_VAR_guest_password="GuestPass!"
export TF_VAR_fortiflex_fgt_token="FGT_TOKEN"   # optional
export TF_VAR_fortiflex_faz_token="FAZ_TOKEN"    # optional

# 4. Initialize and deploy Azure infrastructure
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

#### Phase 2 — FortiGate Configuration

After the FortiGate VM is booted (~3-5 minutes):

1. Note the FortiGate public IP from the Phase 1 output
2. Set `fortigate_api_hostname` in your `terraform.tfvars` to the public IP
3. Create a REST API admin token on the FortiGate (System > Administrators > REST API Admin)
4. Run `terraform apply` again — the `fortios` provider configures the device

> The `fortios` provider connects with `insecure = true` (FortiGate default self-signed certificate).

---

### Option B — GitHub Actions (CI/CD)

A GitHub Actions workflow (`.github/workflows/terraform.yml`) automates deployment using Azure OIDC authentication.

#### 1. Create an Azure Service Principal with OIDC

```bash
# Create app registration
az ad app create --display-name "github-xperts-terraform"
APP_ID=$(az ad app list --display-name "github-xperts-terraform" --query "[0].appId" -o tsv)

# Create service principal and assign Contributor role
az ad sp create --id $APP_ID
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/<subscription-id>

# Add federated credential for GitHub Actions (main branch)
APP_OBJECT_ID=$(az ad app list --display-name "github-xperts-terraform" --query "[0].id" -o tsv)
az ad app federated-credential create --id $APP_OBJECT_ID --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:fortidz/xperts_threat_hunting:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

#### 2. Create a Terraform State Storage Account

```bash
az group create -n tfstate-rg -l eastus
az storage account create -n yourorgterraformstate -g tfstate-rg -l eastus --sku Standard_LRS
az storage container create -n tfstate --account-name yourorgterraformstate
```

Then uncomment and update the `backend "azurerm"` block in `versions.tf`.

#### 3. Configure GitHub Secrets

Go to **Settings > Secrets and variables > Actions > Secrets**:

| Secret | Description |
|--------|-------------|
| `ARM_CLIENT_ID` | Azure app registration client ID |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |
| `ARM_TENANT_ID` | Azure AD tenant ID |
| `TF_VAR_ADMIN_PASSWORD` | VM admin password |
| `TF_VAR_FORTIGATE_API_TOKEN` | FortiGate REST API token |
| `TF_VAR_IPSEC_PSK` | IPsec VPN pre-shared key |
| `TF_VAR_VPNUSER1_PASSWORD` | vpnuser1 password |
| `TF_VAR_GUEST_PASSWORD` | guest user password |
| `TF_VAR_FORTIFLEX_FGT_TOKEN` | FortiFlex FortiGate token *(optional)* |
| `TF_VAR_FORTIFLEX_FAZ_TOKEN` | FortiFlex FortiAnalyzer token *(optional)* |

#### 4. Configure GitHub Variables

Go to **Settings > Secrets and variables > Actions > Variables**:

| Variable | Example |
|----------|---------|
| `TF_VAR_RESOURCE_GROUP_NAME` | `xperts-lab-rg` |
| `TF_VAR_STUDENT_NUMBER` | `1` |
| `TF_VAR_LOCATION` | `eastus` |
| `TF_VAR_CREATE_RESOURCE_GROUP` | `true` |
| `TF_VAR_FORTIGATE_PORT1_IP` | `192.168.27.5` |
| `TF_VAR_FORTIGATE_PORT2_IP` | `192.168.27.36` |
| `TF_VAR_FORTIANALYZER_IP` | `192.168.27.6` |
| `TF_VAR_DEPLOY_DATE` | `20260318` |
| `TF_VAR_FORTIGATE_API_HOSTNAME` | *(set after Phase 1)* |

#### 5. Run the Workflow

Go to **Actions > "Terraform Deploy" > Run workflow**:

| Action | What it does |
|--------|-------------|
| **plan** | Runs `terraform plan` (also runs automatically on push to main) |
| **apply-infra** | Phase 1: deploys Azure resources only (VMs, networking, storage) |
| **apply-all** | Phase 2: full apply including FortiGate configuration via `fortios` |
| **destroy** | Tears down all resources |

**Two-phase deployment flow:**

1. Run **`apply-infra`** — deploys all Azure resources. The workflow output shows the FortiGate public IP.
2. Update the `TF_VAR_FORTIGATE_API_HOSTNAME` variable with the FortiGate public IP. Wait ~3-5 minutes for the FortiGate to boot.
3. Run **`apply-all`** — applies the full configuration including all FortiGate settings.

---

## Variables

### Infrastructure

| Variable | Required | Default | Description |
|---|---|---|---|
| `student_number` | yes | — | Student number (1–999) |
| `resource_group_name` | yes | — | Azure Resource Group name |
| `create_resource_group` | no | `true` | `true` = create new RG; `false` = use existing |
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
| `fortigate_api_hostname` | yes | — | Public IP or hostname to reach FortiGate API |
| `fortigate_api_token` | yes | — | REST API token (sensitive) |
| `ipsec_psk` | yes | — | IPsec VPN pre-shared key (sensitive) |
| `vpnuser1_password` | yes | — | Password for VPN user `vpnuser1` (sensitive) |
| `guest_password` | yes | — | Password for local user `guest` (sensitive) |

---

## Key Outputs

| Output | Description |
|---|---|
| `fortigate_public_ip` | FortiGate management / VPN public IP |
| `fortigate_management_url` | `https://<public-ip>:10443` |
| `fortigate_port1_private_ip` | FortiGate port1 IP (snet-external) |
| `fortigate_port2_private_ip` | FortiGate port2 IP (snet-internal / UDR next-hop) |
| `fortianalyzer_public_ip` | FortiAnalyzer public IP |
| `fortianalyzer_private_ip` | FortiAnalyzer private IP |
| `watchtower_private_ip` | Workload VM private IP (192.168.27.37) |
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
├── .github/workflows/
│   └── terraform.yml                # GitHub Actions CI/CD workflow
│
├── locals_constants.tf              # Named constants — ports, CIDRs, SKUs, names
├── locals_common.tf                 # Shared resource_group_name, location, tags
├── locals_network.tf                # VNet, subnet, NSG, UDR configuration maps
├── locals_compute.tf                # Public IP, NIC, VM configuration maps
├── locals_storage.tf                # Storage account and container configuration
├── locals_fortigate.tf              # FortiGate config values (system, firewall, VPN, etc.)
│
├── resource_resource_group.tf       # Azure Resource Group (create or use existing)
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
└── cloud-init/
    ├── fortigate.tpl                # Bootstrap: auto-update disable + FortiFlex license
    └── fortianalyzer.tpl            # Bootstrap: hostname + FortiFlex license
```

---

## FortiGate Configuration Overview

The `fortios` provider manages the full FortiGate device configuration:

| Category | Resources |
|----------|-----------|
| **System** | Global settings (hostname, admin-sport 10443), DNS, password policy, access profile |
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
- Verify `fortigate_api_hostname` is set to the correct FortiGate public IP
- Verify the REST API token is valid and has the correct admin profile
- Check that port 10443 is reachable (NSG Allow-Admin-HTTPS rule at priority 105)

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

**GitHub Actions — `apply-all` fails with fortios provider error**
- Ensure `TF_VAR_FORTIGATE_API_HOSTNAME` is set to the FortiGate public IP (from Phase 1 output)
- Wait at least 3-5 minutes after Phase 1 for the FortiGate to boot and become API-accessible
- Verify the `TF_VAR_FORTIGATE_API_TOKEN` secret is set correctly

---

## FortiCNAPP

FortiCNAPP integration is **deferred** — it will be specified and implemented in a future phase. No resources are provisioned for FortiCNAPP in this deployment.
