# Terraform FortiGate Configuration Deployment Spec

## Source of Truth

- **Configuration file:** `DL-fgt_7-6_3652_202603100437.conf`
- **FortiOS version:** 7.6.6 (build 3652)
- **Device:** FortiGate VM (FGVMAA) — Azure NVA named `DL-FG`

---

## Objective

Extend the existing `xperts_threat_hunting` Terraform project to manage the
FortiGate device configuration using the `fortios` Terraform provider. The
running configuration is reproduced as code so the lab can be torn down and
rebuilt deterministically.

---

## Existing Infrastructure (already managed)

| Resource | Key Detail |
|----------|-----------|
| VNet `threathunt-vnet` | 192.168.27.0/24 |
| snet-external | 192.168.27.0/27 — FortiGate port1, FortiAnalyzer |
| snet-internal | 192.168.27.32/27 — FortiGate port2, Watchtower |
| FortiGate VM `DL-FG` | 2 NICs, public IP, IP forwarding |
| FortiAnalyzer VM `DL-FAZ` | snet-external, public IP with DNS FQDN |
| Watchtower VM | 192.168.27.37, snet-internal |
| NSGs, UDR, Storage | All managed by existing .tf files |

Values already available from existing Terraform:

- `var.fortigate_port1_ip` — FortiGate port1 private IP
- `var.fortigate_port2_ip` — FortiGate port2 private IP
- `var.fortianalyzer_ip` — FortiAnalyzer private IP (used for log server)
- `local.watchtower_private_ip` — Watchtower private IP (192.168.27.37)

### Existing infrastructure changes required

**`locals_constants.tf`** — add new port constant:

| Constant | Value | Purpose |
|----------|-------|---------|
| `fgt_port_admin_https` | `"10443"` | FortiGate custom HTTPS admin port (`admin-sport`) and `fortios` provider API endpoint |

**`locals_network.tf`** — add NSG rule to `nsg-snet-external`:

| Rule | Priority | Port | Description |
|------|----------|------|-------------|
| Allow-Admin-HTTPS | 105 | 10443 | FortiGate admin HTTPS GUI (admin-sport) and Terraform fortios provider API access |

> Port 10443 is required because `admin-sport 10443` moves the FortiGate
> management API off the standard 443. Without this NSG rule, the `fortios`
> Terraform provider cannot reach the FortiGate API and the deployment will
> fail. The existing Allow-HTTPS rule (port 443) remains for SSL-VPN traffic.

**Complete `nsg-snet-external` rule set after change:**

| Priority | Rule | Protocol | Port | Direction | Access | Description |
|----------|------|----------|------|-----------|--------|-------------|
| 100 | Allow-HTTPS | Tcp | 443 | Inbound | Allow | FortiGate HTTPS GUI and SSL-VPN |
| 105 | Allow-Admin-HTTPS | Tcp | 10443 | Inbound | Allow | FortiGate admin HTTPS (admin-sport) and fortios provider API |
| 110 | Allow-HTTP | Tcp | 80 | Inbound | Allow | FortiGate HTTP and captive portal redirect |
| 120 | Allow-SSH-Mgmt | Tcp | 622 | Inbound | Allow | FortiGate custom SSH management port |
| 130 | Allow-541 | Tcp | 541 | Inbound | Allow | FortiGate log forwarding and HA heartbeat |
| 140 | Allow-8080 | Tcp | 8080 | Inbound | Allow | FortiGate alternate HTTP service port |
| 150 | Allow-514 | Tcp | 514 | Inbound | Allow | FortiAnalyzer device registration and syslog inbound from FortiGate |
| 4096 | Deny-All-Inbound | * | * | Inbound | Deny | Default deny — all other inbound traffic blocked |

**`nsg-snet-internal` — no changes required:**

| Priority | Rule | Protocol | Port | Direction | Access | Description |
|----------|------|----------|------|-----------|--------|-------------|
| 100 | Allow-SSH | Tcp | 22 | Inbound | Allow | SSH access to workload VM (watchtower) |
| 4096 | Deny-All-Inbound | * | * | Inbound | Deny | Default deny — all other inbound traffic blocked |

---

## FortiGate Configuration to Deploy

### 1. System Global Settings

| Setting | Value |
|---------|-------|
| hostname | `DL-fgt` |
| alias | `DL-fgt` |
| admin-sport | 10443 |
| admin-server-cert | `fullchain` |
| admintimeout | 60 |
| timezone | `US/Pacific` |
| gui-theme | mariner |
| log-uuid-address | enable |

> `admin-server-cert "fullchain"` binds the custom Let's Encrypt wildcard
> certificate (`*.dl.sxroomec.net`) to the HTTPS admin GUI on port 10443. This
> replaces the factory-default `Fortinet_GUI_Server` self-signed certificate.
> The certificate is injected at bootstrap (see §1a below) so it is available
> on first boot before the `fortios` provider connects.

### 1a. SSL Certificates (Bootstrap)

These certificates are injected via cloud-init at VM creation time so they are
available on first boot — before the `fortios` Terraform provider connects.

**Certificate files (stored in `certs/` within the Terraform project):**

| File | Source | Purpose |
|------|--------|---------|
| `certs/fullchain.pem` | `dl.sxroomec.net/fullchain.pem` | Server certificate + intermediate chain |
| `certs/privkey.pem` | `dl.sxroomec.net/privkey.pem` | Private key for the server certificate |
| `certs/chain.pem` | `dl.sxroomec.net/chain.pem` | Let's Encrypt intermediate CA |

> The certificate is a Let's Encrypt wildcard: CN=`*.dl.sxroomec.net`,
> SAN=`*.dl.sxroomec.net, dl.sxroomec.net`. It covers the FortiGate admin FQDN
> `dl-fg-<student-number>.dl.sxroomec.net`.

**Local certificate — `"fullchain"`:**

Injected into `config vpn certificate local` at bootstrap.

| Setting | Value |
|---------|-------|
| name | `fullchain` |
| certificate | Contents of `certs/fullchain.pem` (read via `file()`) |
| private-key | Contents of `certs/privkey.pem` (read via `file()`) |

**Remote CA certificate — `"LetsEncrypt_CA"`:**

Injected into `config vpn certificate ca` at bootstrap.

| Setting | Value |
|---------|-------|
| name | `LetsEncrypt_CA` |
| ca | Contents of `certs/chain.pem` (read via `file()`) |

**Cloud-init implementation:**

The `cloud-init/fortigate.tpl` template is extended to include the certificate
configuration blocks. Terraform's `templatefile()` function injects the PEM
content using `file()`:

```
templatefile("cloud-init/fortigate.tpl", {
  var_fortiflex_token = var.fortiflex_token
  var_fullchain_pem   = file("certs/fullchain.pem")
  var_privkey_pem     = file("certs/privkey.pem")
  var_chain_pem       = file("certs/chain.pem")
})
```

The template adds the following blocks to the FortiGate bootstrap configuration:

```
config vpn certificate local
    edit "fullchain"
        set private-key "${var_privkey_pem}"
        set certificate "${var_fullchain_pem}"
    next
end
config vpn certificate ca
    edit "LetsEncrypt_CA"
        set ca "${var_chain_pem}"
    next
end
config system global
    set admin-server-cert "fullchain"
end
```

> **Important:** The `set admin-server-cert "fullchain"` in `config system global`
> within the bootstrap ensures the admin GUI serves the custom certificate from
> the very first HTTPS connection. This is critical because the `fortios`
> provider connects with `insecure = false` and requires a valid TLS handshake.

**Files to add to `.gitignore`:**

```
certs/
```

> Certificate private keys must never be committed to version control. The
> `certs/` directory is populated manually (or via CI/CD secret injection)
> before running `terraform apply`.

### 2. System Password Policy

| Setting | Value |
|---------|-------|
| status | enable |
| reuse-password | disable |

### 3. Admin Access Profile

| Profile | Permissions |
|---------|-------------|
| prof_admin | Full read-write on: secfabgrp, ftviewgrp, authgrp, sysgrp, netgrp, loggrp, fwgrp, vpngrp, utmgrp, wanoptgrp, wifi. CLI: get, show, exec, config all enabled. |

### 4. Network Interfaces

| Interface | IP/Mask | Allow Access | Alias | Description |
|-----------|---------|-------------|-------|-------------|
| port1 | 192.168.27.5/27 | ping, https, ssh | external | external |
| port2 | 192.168.27.36/27 | ping, https, ssh | internal | internal |

> Interface IPs must match the Azure NIC static IPs from `var.fortigate_port1_ip`
> and `var.fortigate_port2_ip`.

### 5. DNS

| Setting | Value |
|---------|-------|
| primary | 96.45.45.45 |
| secondary | 96.45.46.46 |
| server-select-method | failover |

### 6. Static Routes

| ID | Destination | Gateway | Interface |
|----|-------------|---------|-----------|
| 1 | 0.0.0.0/0 (default) | 192.168.27.1 | port1 |
| 2 | 192.168.27.0/24 | 192.168.27.33 | port2 |

### 7. Firewall Address Objects

Only custom objects — built-in objects (`all`, `none`, `FIREWALL_AUTH_PORTAL_ADDRESS`,
`FABRIC_DEVICE`, EMS dynamic tags, `FCTEMS_ALL_FORTICLOUD_SERVERS`) are excluded.

**Subnet/Host objects:**

| Name | Type | Value | Associated Interface |
|------|------|-------|---------------------|
| WATCHTOWER | ipmask | 192.168.27.37/32 | port2 |
| LAN_port2_192.168.27.32_27 | ipmask | 192.168.27.32/27 | — |
| RA_IPSEC_POOL_10.10.100.0_24 | ipmask | 10.10.100.0/24 | — |

**IP Range objects:**

| Name | Start IP | End IP |
|------|----------|--------|
| SSLVPN_TUNNEL_ADDR1 | 10.212.134.200 | 10.212.134.210 |

**FQDN objects:**

| Name | FQDN |
|------|------|
| login.microsoftonline.com | login.microsoftonline.com |
| login.microsoft.com | login.microsoft.com |
| login.windows.net | login.windows.net |
| gmail.com | gmail.com |
| wildcard.google.com | *.google.com |
| wildcard.dropbox.com | *.dropbox.com |

### 8. Firewall Address Groups

| Name | Members |
|------|---------|
| G Suite | gmail.com, wildcard.google.com |
| Microsoft Office 365 | login.microsoftonline.com, login.microsoft.com, login.windows.net |

### 9. Firewall Service Groups

Individual service objects (ALL, HTTP, HTTPS, SSH, DNS, etc.) are FortiOS
built-ins — do not recreate them.

| Name | Members |
|------|---------|
| Email Access | DNS, IMAP, IMAPS, POP3, POP3S, SMTP, SMTPS |
| Web Access | DNS, HTTP, HTTPS |
| Windows AD | DCE-RPC, DNS, KERBEROS, LDAP, LDAP_UDP, SAMBA, SMB |
| Exchange Server | DCE-RPC, DNS, HTTPS |

### 10. Firewall VIP (Destination NAT)

| Name | External IP | Mapped IP | Ext Intf | Port Forward | Ext Port | Mapped Port |
|------|------------|-----------|----------|-------------|----------|-------------|
| WATCHTOWER_DNAT | 192.168.27.5 | 192.168.27.37 | port1 | yes | 622 | 22 |

### 11. Security Profiles (custom only)

Built-in profiles (`default`, `sniffer-profile`, `wifi-default`, `all_default`,
`all_default_pass`, `protect_http_server`, `protect_email_server`,
`protect_client`, `high_security`, `block-high-risk`) are excluded.

The `deep-inspection` SSL/SSH profile is a FortiOS read-only built-in —
referenced by name in policies but not managed.

**IPS Sensor — `ips_monitor`:**

| Entry | Status | Action | Log Packet |
|-------|--------|--------|------------|
| 1 (all signatures) | enable | pass | enable |

> Monitor-only mode — logs all IPS events without blocking.

**Application Control — `monitor_all`:**

| Setting | Value |
|---------|-------|
| other-application-log | enable |
| unknown-application-log | enable |
| enforce-default-app-port | enable |
| Entry 1 categories | 2 3 5 6 7 8 12 15 17 21 22 23 25 26 28 29 30 31 32 36 |
| Entry 1 action | pass |

**Webfilter Profile — `Monitor_Everything`:**

| Setting | Value |
|---------|-------|
| FortiGuard Web Filter | All categories monitored (no blocking) |
| options | unset (flow-based) |

**Webfilter Profile — `monitor-all`:**

| Setting | Value |
|---------|-------|
| comment | Monitor and log all visited URLs, flow-based. |
| FortiGuard Web Filter | All categories monitored (no blocking) |
| options | unset (flow-based) |

### 12. Firewall Policies

| ID | Name | Src Intf | Dst Intf | Src Addr | Dst Addr | Service | Action | NAT | UTM Profiles | Log |
|----|------|----------|----------|----------|----------|---------|--------|-----|-------------|-----|
| 1 | Internet Access | port2 | port1 | all | all | ALL | accept | yes | ssl=deep-inspection, av=default, wf=Monitor_Everything, dns=default, ips=ips_monitor, app=monitor_all | all + start |
| 2 | Remote Access | port1 | port2 | all | WATCHTOWER_DNAT | SSH | accept | no | — | all + start |
| 3 | RA_IPSEC_to_LAN | "phase1" | port2 | RA_IPSEC_POOL_10.10.100.0_24 | LAN_port2_192.168.27.32_27 | ALL | accept | no | — | all |
| 4 | LAN_to_RA_IPSEC | port2 | "phase1" | LAN_port2_192.168.27.32_27 | RA_IPSEC_POOL_10.10.100.0_24 | ALL | accept | no | — | all |
| 5 | RA_IPSEC_to_Internet_FullTunnel | "phase1" | port1 | RA_IPSEC_POOL_10.10.100.0_24 | all | ALL | accept | yes | ssl=deep-inspection, av=default, wf=monitor-all, dns=default, ips=ips_monitor, app=default | all + start |

### 13. Local-In Policy (Threat Feed Block)

| ID | Interface | Dst Addr | Internet Service Src | Service | Action |
|----|-----------|----------|---------------------|---------|--------|
| 1 | any | all | Malicious-Malicious.Server, Tor-Exit.Node, Tor-Relay.Node | ALL | deny (implicit default) |

### 14. IPsec VPN (Remote Access Dialup)

**Phase 1 — `"phase1"`:**

| Setting | Value |
|---------|-------|
| type | dynamic (dialup) |
| interface | port1 |
| ike-version | 2 |
| proposal | aes256-sha256 |
| dhgrp | 14 |
| keylife | 28800 |
| dpd | on-idle |
| dpd-retryinterval | 60 |
| mode-cfg | enable |
| net-device | enable |
| ipv4-start-ip | 10.10.100.1 |
| ipv4-end-ip | 10.10.100.200 |
| ipv4-dns-server1 | 1.1.1.1 |
| ipv4-dns-server2 | 8.8.8.8 |
| eap | enable |
| authusrgrp | RA_IPSEC_USERS |
| localid | vpnuser1 |
| psksecret | **(sensitive — via variable `ipsec_psk`)** |
| peertype | any |
| transport | auto |

**Phase 2 — `"phase2"`:**

| Setting | Value |
|---------|-------|
| phase1name | "phase1" |
| proposal | aes256-sha256 |
| dhgrp | 14 |
| keylifeseconds | 3600 |

### 15. Local Users

| Username | Type | Password Source |
|----------|------|----------------|
| guest | password | variable `guest_password` |
| vpnuser1 | password | variable `vpnuser1_password` |

### 16. User Groups

| Group | Members |
|-------|---------|
| SSO_Guest_Users | (empty) |
| Guest-group | guest |
| RA_IPSEC_USERS | vpnuser1 |

### 17. FortiAnalyzer Logging

| Setting | Value | Source |
|---------|-------|-------|
| status | enable | — |
| server | (FortiAnalyzer private IP) | `var.fortianalyzer_ip` (existing) |
| upload-option | realtime | — |
| reliable | enable | — |

> The FortiAnalyzer serial number is **not managed by Terraform**. Device
> authorization is performed on the FortiAnalyzer side (out-of-band) after
> both VMs are deployed and the FortiGate initiates registration.

### 18. SD-WAN Health Checks

| Name | Server | Protocol | Interval | Latency | Jitter | Pkt Loss |
|------|--------|----------|----------|---------|--------|----------|
| Default_DNS | (system-dns) | ping | 1000ms | 250ms | 50ms | 5% |
| Default_Office_365 | www.office.com | https | 120000ms | 250ms | 50ms | 5% |
| Default_Gmail | gmail.com | ping | 1000ms | 250ms | 50ms | 2% |
| Default_Google Search | www.google.com | https | 120000ms | 250ms | 50ms | 5% |
| Default_FortiGuard | fortiguard.com | https | 120000ms | 250ms | 50ms | 5% |

> SD-WAN zone `virtual-wan-link` with health checks only (no SD-WAN rules).
> These are default health checks — include for completeness but may be
> omitted without functional impact.

---

## Excluded from Terraform Scope

| Category | Reason |
|----------|--------|
| Built-in firewall objects (`all`, `none`, `FABRIC_DEVICE`, EMS tags) | Managed by FortiOS |
| Built-in services (HTTP, HTTPS, SSH, DNS, ALL, etc.) | Managed by FortiOS |
| Built-in SSL/SSH profiles (`deep-inspection`, `certificate-inspection`) | Read-only |
| Built-in IPS sensors (`default`, `sniffer-profile`, `high_security`, etc.) | Managed by FortiOS |
| Built-in app-ctrl lists (`default`, `block-high-risk`, etc.) | Managed by FortiOS |
| Built-in AV/webfilter/dnsfilter `default` profiles | Managed by FortiOS |
| Replacement messages | Cosmetic / FortiOS defaults |
| Custom language files | Cosmetic |
| Internet service definitions | FortiGuard-managed |
| VPN certificates and SSH keys (factory defaults) | Factory-embedded — replaced at bootstrap by custom certs (see §1a) |
| GUI dashboard widgets | Cosmetic, per-admin |
| Switch-controller / wireless-controller | No physical switches/APs in lab |
| Traffic shapers (`high-priority`, `medium-priority`, `low-priority`) | Defined but unused in any policy |
| Firewall schedules (only `always` is used — built-in) | Built-in |
| DLP profiles/data-types/dictionaries | Defined but not applied to any policy |
| VoIP profiles | Defined but not applied to any policy |
| Admin users (`admin`, `datalake`) | Sensitive — managed via bootstrap/out-of-band |
| FortiAnalyzer serial number | Runtime value — device auth is out-of-band |
| DHCP server (FortiLink) | FortiSwitch management — no switches in lab |
| Wildcard FQDN objects | Large set of defaults — not referenced by any policy |
| Email filter / virtual-patch / CASB profiles | Defined but not applied to any policy |

---

## Terraform Implementation Plan

### Provider Configuration

```hcl
# In versions.tf — add to existing required_providers block
fortios = {
  source  = "fortinetdev/fortios"
  version = "~> 1.22"
}
```

```hcl
# Provider block
provider "fortios" {
  hostname = local.fortigate_api_host
  token    = var.fortigate_api_token
  insecure = false  # valid Let's Encrypt wildcard cert injected at bootstrap
}
```

### New Variables (add to `variables.tf`)

| Variable | Type | Sensitive | Default | Description |
|----------|------|-----------|---------|-------------|
| `student_number` | number | no | — | Student identifier (1–999); drives DNS names |
| `fortigate_api_token` | string | yes | — | REST API token for `fortios` provider |
| `ipsec_psk` | string | yes | — | Pre-shared key for IPsec VPN phase1 |
| `vpnuser1_password` | string | yes | — | Password for local user `vpnuser1` |
| `guest_password` | string | yes | — | Password for local user `guest` |
| `aws_access_key` | string | yes | — | AWS Access Key ID for Route 53 DNS management |
| `aws_secret_key` | string | yes | — | AWS Secret Access Key for Route 53 DNS management |

> No new variables for FortiAnalyzer IP or serial. The FAZ IP is already
> available as `var.fortianalyzer_ip`. The FAZ serial is not configured
> from the FortiGate side via Terraform.

### New File Structure

```
xperts_threat_hunting/
├── certs/                               # NEW: SSL certificate files (git-ignored)
│   ├── fullchain.pem                    #   Server cert + intermediate (from dl.sxroomec.net/)
│   ├── privkey.pem                      #   Private key (from dl.sxroomec.net/)
│   └── chain.pem                        #   Let's Encrypt intermediate CA (from dl.sxroomec.net/)
├── cloud-init/
│   └── fortigate.tpl                    # UPDATE: add cert + CA + admin-server-cert blocks
├── versions.tf                          # UPDATE: add fortios + aws providers
├── variables.tf                         # UPDATE: add 7 new variables
├── locals_fortigate.tf                  # NEW: FortiGate config values as locals
├── resource_fortigate_system.tf         # NEW: global, dns, password-policy, accprofile
├── resource_fortigate_interface.tf      # NEW: port1, port2 config
├── resource_fortigate_router.tf         # NEW: static routes
├── resource_fortigate_address.tf        # NEW: address objects + address groups
├── resource_fortigate_service.tf        # NEW: service groups
├── resource_fortigate_user.tf           # NEW: local users + user groups
├── resource_fortigate_vpn.tf            # NEW: IPsec phase1 + phase2
├── resource_fortigate_security.tf       # NEW: IPS sensor, app-ctrl, webfilter profiles
├── resource_fortigate_policy.tf         # NEW: firewall policies, VIP, local-in policy
├── resource_fortigate_log.tf            # NEW: FortiAnalyzer logging config
├── resource_dns.tf                     # NEW: Route 53 A records for FortiGate and FortiAnalyzer
├── (all existing .tf files unchanged)
```

### Resource Dependency Chain

```
Layer 0 — Bootstrap (cloud-init, before Terraform fortios provider):
  SSL certificates (fullchain local cert, LetsEncrypt_CA remote CA)
  admin-server-cert "fullchain" binding

Layer 0.5 — Depends on Azure public IPs:
  Route 53 A records (dl-fg-<n>.dl.sxroomec.net, dl-faz-<n>.dl.sxroomec.net)

Layer 1 — No dependencies:
  system global (admin-server-cert already set at bootstrap), dns, password-policy, accprofile

Layer 2 — Depends on Layer 1:
  interfaces (port1, port2)

Layer 3 — Depends on Layer 2:
  static routes

Layer 4 — Depends on Layer 2:
  firewall address objects (some have associated-interface)

Layer 5 — Depends on Layer 4:
  firewall address groups

Layer 6 — No FortiGate dependencies (built-in services):
  firewall service groups

Layer 7 — No dependencies:
  local users (guest, vpnuser1)

Layer 8 — Depends on Layer 7:
  user groups (Guest-group, RA_IPSEC_USERS)

Layer 9 — Depends on Layer 2, Layer 8:
  IPsec VPN phase1 (needs port1 interface, RA_IPSEC_USERS group)

Layer 10 — Depends on Layer 9:
  IPsec VPN phase2

Layer 11 — No dependencies:
  security profiles (ips_monitor, monitor_all, Monitor_Everything, monitor-all)

Layer 12 — Depends on Layer 4:
  firewall VIP (WATCHTOWER_DNAT)

Layer 13 — Depends on Layers 2, 4, 5, 6, 9, 11, 12:
  firewall policies (all 5 policies)

Layer 14 — Depends on Layer 13:
  local-in policy

Layer 15 — No FortiGate object dependencies:
  FortiAnalyzer log settings (uses var.fortianalyzer_ip)
```

### Key Design Decisions

1. **Two-phase deployment.** The `fortios` provider requires API connectivity
   to the FortiGate. Run `terraform apply` for Azure infrastructure first,
   then supply the FortiGate API token for the second apply.
   Alternatively, use `depends_on` with the FortiGate VM resource and accept
   that the first apply handles only Azure resources. The SSL certificate is
   injected at bootstrap (cloud-init), so the admin GUI serves a valid
   Let's Encrypt cert from first boot — enabling `insecure = false` on the
   `fortios` provider.

2. **Locals-driven pattern.** Follow the existing project convention:
   define all FortiGate configuration values in `locals_fortigate.tf` as
   structured maps, then iterate with `for_each` in resource files.

3. **Sensitive values.** PSK, user passwords, and API token are supplied via
   variables (never hardcoded). Use a git-ignored `terraform.tfvars` or
   `TF_VAR_` environment variables.

4. **Built-in profiles referenced by name.** Policies reference `default` AV
   profile, `deep-inspection` SSL profile, `default` DNS filter profile, and
   `default` app-ctrl list. These exist on every FortiGate out of the box —
   use direct string references, not Terraform resources.

5. **Custom profiles managed.** `ips_monitor`, `monitor_all`,
   `Monitor_Everything`, and `monitor-all` are custom profiles that must be
   created before the policies that reference them.

6. **IPsec tunnel interface name.** The config uses `"phase1"` (with embedded
   quotes in the FortiOS config). In Terraform, this is the tunnel interface
   name created by the `fortios_vpnipsec_phase1interface` resource and
   referenced by firewall policies as the source/destination interface.

7. **FortiAnalyzer logging.** The `fortios_log_fortianalyzer_setting`
   resource configures the FortiGate to send logs. It uses
   `var.fortianalyzer_ip` (already defined). The FAZ serial is omitted —
   device authorization happens on the FAZ side after registration.

8. **SD-WAN health checks.** Included for completeness. These are monitoring
   probes only (no SD-WAN steering rules). Can be deferred to a later phase
   without functional impact on the lab.

9. **SSL certificate at bootstrap.** The Let's Encrypt wildcard certificate
   (`*.dl.sxroomec.net`) is injected via cloud-init rather than managed by the
   `fortios` provider. This is required because the `fortios` provider needs
   a valid TLS connection (`insecure = false`) to the FortiGate API, creating
   a chicken-and-egg problem if the cert were managed by the provider itself.
   The `certs/` directory is git-ignored; files must be placed there before
   `terraform apply`. Certificate renewal (every 90 days) requires updating
   the files in `certs/` and redeploying or running a fresh `terraform apply`
   to regenerate the cloud-init with the new PEM content.

10. **Automated DNS via Route 53.** The `aws` provider creates A records in the
    `dl.sxroomec.net` hosted zone for both FortiGate (`dl-fg-<n>.dl.sxroomec.net`)
    and FortiAnalyzer (`dl-faz-<n>.dl.sxroomec.net`) using the Azure public IPs
    allocated at deploy time. The `fortigate_api_hostname` variable is replaced by
    a computed local (`local.fortigate_api_host`), eliminating manual DNS configuration.
    The `student_number` variable drives unique per-student FQDNs.

---

## Validation Criteria

| Test | Expected Result |
|------|----------------|
| `terraform plan` | All FortiGate resources shown as "to be created" |
| `terraform apply` | Completes without errors |
| Admin GUI TLS certificate | `https://dl-fg-<student-number>.dl.sxroomec.net:10443` serves the Let's Encrypt wildcard cert (no browser warning) |
| `get vpn certificate local` (CLI) | Shows `fullchain` entry with correct cert |
| `get vpn certificate ca` (CLI) | Shows `LetsEncrypt_CA` entry |
| `get system global \| grep admin-server-cert` | Returns `fullchain` |
| `fortios` provider connectivity | Connects with `insecure = false` — no TLS errors |
| FortiGate running config | Matches spec (verify via CLI: `show full-configuration`) |
| Internet from Watchtower | Policy 1 permits, traffic logged with UTM inspection |
| SSH to Watchtower via :622 | Policy 2 + VIP DNAT translates port1:622 → 192.168.27.37:22 |
| IPsec VPN with vpnuser1 | Phase1/Phase2 negotiate, mode-cfg assigns 10.10.100.x IP |
| VPN → LAN access | Policy 3 permits VPN pool → LAN subnet |
| VPN → Internet (full tunnel) | Policy 5 permits with UTM + NAT |
| FortiAnalyzer logs | FortiGate registers and sends logs in realtime |
| Local-in policy | Inbound from Tor/malicious IPs blocked before reaching any policy |
| `terraform plan` (re-run) | No changes detected (idempotent) |
