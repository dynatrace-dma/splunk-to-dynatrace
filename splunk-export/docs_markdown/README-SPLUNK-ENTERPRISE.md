# DynaBridge Splunk Enterprise Export Script
## READ THIS FIRST - Complete Prerequisites Guide

**Version**: 4.0.1
**Last Updated**: January 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise Export Specification](SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | [Export Improvement Analysis](EXPORT-IMPROVEMENT-ANALYSIS.md)

---

## CRITICAL: Where to Run This Script

### TL;DR - Run It ONCE on the Search Head

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    WHERE TO RUN THE EXPORT SCRIPT                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✅ RUN HERE (Primary - Required):                                       │
│     • Search Head (standalone)                                           │
│     • SHC Captain (in Search Head Cluster)                              │
│                                                                          │
│  ⚠️  OPTIONAL (Secondary - Only if needed):                              │
│     • Deployment Server (for forwarder deployment configs)              │
│                                                                          │
│  ❌ DO NOT RUN ON:                                                       │
│     • Indexers / Indexer Cluster peers (SH queries them via REST)       │
│     • Universal Forwarders (configs come from Deployment Server)        │
│     • Heavy Forwarders (unless standalone, not managed by DS)           │
│     • Cluster Manager (SH can get cluster info via REST)                │
│     • License Master (SH can get license info via REST)                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Only the Search Head?

The Search Head is the **authoritative source** for migration-relevant data:

| Data Type | Lives On | How SH Gets It |
|-----------|----------|----------------|
| Dashboards | Search Head | Local files + KV Store |
| Alerts & Saved Searches | Search Head | Local files |
| Users & Roles | Search Head | Local + REST API |
| Search Macros | Search Head | Local files |
| Index Statistics | Indexers | **REST API from SH** |
| Cluster Topology | Cluster Manager | **REST API from SH** |
| License Info | License Master | **REST API from SH** |

**The Search Head can collect everything via its REST API connections to other components.**

### When to Run on Deployment Server (Optional)

Only run on the Deployment Server if you need:
- The **source-of-truth** for forwarder configurations (`deployment-apps/`)
- Server class definitions (`serverclass.conf`)
- Which forwarders receive which app configurations

This is **supplementary** to the main SH export, not a replacement.

---

## Supported Platforms

### ✅ SUPPORTED: Splunk Enterprise (On-Premises)

This script is designed for **Splunk Enterprise** deployments where you have:
- SSH/shell access to the Splunk servers
- File system access to `$SPLUNK_HOME/etc/`
- REST API access (ports 8089 or custom)

Supported architectures:
- Standalone (single server)
- Distributed (Search Heads + Indexers)
- Search Head Cluster (SHC)
- Indexer Cluster
- With or without Deployment Server

### ❌ NOT SUPPORTED: Splunk Cloud (Classic or Victoria Experience)

**Splunk Cloud does NOT allow SSH access** to the underlying infrastructure.

For Splunk Cloud migrations, you need:
1. **REST API-only export** (different script - contact DynaBridge team)
2. **Splunk Cloud admin credentials** with appropriate permissions
3. **Network access** to `https://your-stack.splunkcloud.com:8089`

If you're migrating from Splunk Cloud, please contact the DynaBridge team for:
- Splunk Cloud-specific export script
- Guidance on Cloud-to-Dynatrace migration patterns

---

## What This Document Covers

This document explains **everything you need to know** before running the DynaBridge Splunk Export Script, including:

1. [What This Script Does](#1-what-this-script-does)
2. [Server Access Requirements](#2-server-access-requirements)
3. [Splunk User Permissions](#3-splunk-user-permissions)
4. [Permissions by Splunk Deployment Type](#4-permissions-by-splunk-deployment-type)
5. [Pre-Flight Checklist](#5-pre-flight-checklist)
6. [What Data Gets Collected](#6-what-data-gets-collected)
7. [Security & Privacy Considerations](#7-security--privacy-considerations)
8. [Command-Line Arguments & Automation](#8-command-line-arguments--automation) **(NEW in v4.0)**
9. [Troubleshooting Access Issues](#9-troubleshooting-access-issues)

---

## 1. What This Script Does

The DynaBridge Export Script collects configuration data, dashboards, alerts, and usage analytics from your Splunk environment to enable migration to Dynatrace.

### The Script Collects:

| Category | What's Collected | Why It's Needed |
|----------|-----------------|-----------------|
| **Configurations** | props.conf, transforms.conf, indexes.conf, inputs.conf | Understanding data pipeline for OpenPipeline conversion |
| **Dashboards** | Classic XML dashboards + Dashboard Studio JSON | Visual conversion to Dynatrace apps |
| **Alerts** | savedsearches.conf with all alert definitions | Migration of monitoring and alerting |
| **Users & RBAC** | Users, roles, groups, object ownership | Mapping who owns what for migration prioritization |
| **Usage Analytics** | Search frequency, dashboard views, alert triggers | Identifying high-value assets worth migrating |
| **Index Statistics** | Sizes, retention, sourcetypes, volume metrics | Capacity planning for Dynatrace buckets |

### The Script Does NOT:

- ❌ Collect passwords, API tokens, or secrets
- ❌ Access actual log data or search results
- ❌ Modify any Splunk configurations
- ❌ Send data anywhere (all data stays local)
- ❌ Require network access (runs entirely on the Splunk server)

---

## 2. Server Access Requirements

### 2.1 How to Access the Server

You need **shell access** (SSH or console) to the Splunk server. The script must run directly on the machine where Splunk is installed.

```bash
# Example: SSH to your Splunk server
ssh your_username@splunk-server.company.com

# Or if using a jump host
ssh -J jumphost your_username@splunk-server.company.com
```

### 2.2 Operating System User Requirements

| Requirement | Details |
|-------------|---------|
| **Recommended User** | `splunk` (the user running Splunk) |
| **Alternative** | `root` or any user with read access to `$SPLUNK_HOME/etc/` |
| **Required Permissions** | Read access to Splunk configuration directories |

#### Why Run as the `splunk` User?

The `splunk` user (or whatever user runs your Splunk installation) has guaranteed read access to all configuration files. This is the safest and most reliable option.

```bash
# Switch to splunk user
sudo su - splunk

# Or run script as splunk user
sudo -u splunk bash dynabridge-splunk-export.sh
```

### 2.3 File System Access Required

The script needs to READ (not write) from these directories:

```
$SPLUNK_HOME/
├── etc/
│   ├── system/local/          # System-level configurations
│   ├── apps/*/                # All app configurations
│   ├── users/*/               # User-level objects (optional)
│   └── deployment-apps/       # (Deployment Server only)
└── var/
    └── log/splunk/audit.log   # (Optional) For usage analytics
```

### 2.4 Checking Your Access

Run these commands to verify you have the required access:

```bash
# Check if you can read Splunk configs
ls -la $SPLUNK_HOME/etc/apps/

# Check if you can read a config file
cat $SPLUNK_HOME/etc/system/local/server.conf

# Check if audit.log is readable (optional, for usage analytics)
head -5 $SPLUNK_HOME/var/log/splunk/audit.log
```

If any of these fail with "Permission denied", you need to either:
1. Switch to the `splunk` user
2. Run as root
3. Ask your administrator to add read permissions

---

## 3. Splunk User Permissions

### 3.1 Why Splunk Credentials Are Needed

In addition to OS-level access, the script uses **Splunk's REST API** to collect:
- Dashboard Studio dashboards (stored in KV Store, not files)
- User and role information
- Usage analytics from internal indexes
- Cluster and distributed environment information

### 3.2 Required Splunk Capabilities

The Splunk user account used for the export needs these capabilities:

| Capability | Required? | What It's Used For |
|------------|-----------|-------------------|
| `admin_all_objects` | **Required** | Access all apps and objects |
| `list_users` | **Required** | Collect user information |
| `list_roles` | **Required** | Collect role definitions |
| `rest_access` | **Required** | Make REST API calls |
| `search` | Recommended | Run analytics searches |
| `list_indexes` | Recommended | Get index metadata |
| `list_inputs` | Recommended | Get data input details |
| `list_settings` | Recommended | Get system settings |

### 3.3 Checking Your Splunk Permissions

Run this search in Splunk to see your capabilities:

```spl
| rest /services/authentication/current-context
| table username, roles, capabilities
```

Or use the CLI:

```bash
$SPLUNK_HOME/bin/splunk show user-info
```

### 3.4 Creating a Dedicated Export User (Recommended)

For security best practices, create a dedicated user for the export:

```bash
# Create a new role with required capabilities
$SPLUNK_HOME/bin/splunk add role dynabridge_export \
  -capability admin_all_objects \
  -capability list_users \
  -capability list_roles \
  -capability list_indexes \
  -capability list_inputs \
  -capability list_settings \
  -capability rest_access \
  -capability search \
  -auth admin:your_password

# Create the export user with this role
$SPLUNK_HOME/bin/splunk add user dynabridge_user \
  -password 'SecurePassword123!' \
  -role dynabridge_export \
  -auth admin:your_password
```

### 3.5 Using the Admin Account

If creating a dedicated user isn't possible, you can use any existing admin account. The script will prompt for credentials:

```
Enter Splunk admin username [admin]:
Enter Splunk admin password: ********
```

---

## 4. Permissions by Splunk Deployment Type

Different Splunk deployment types require different access levels. Identify your environment type and follow the specific requirements below.

### IMPORTANT: You Only Need to Run on ONE Server

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DISTRIBUTED ENVIRONMENT?                          │
│                                                                          │
│  Q: Do I need to run on SHC, IDXC, DS, each UF, each HWF?               │
│                                                                          │
│  A: NO! Run ONCE on the Search Head (or SHC Captain).                   │
│                                                                          │
│     The Search Head can collect data from all other components via      │
│     REST API. You do NOT need to run on:                                │
│       • Indexers (SH queries them)                                      │
│       • Universal Forwarders (configs come from DS)                     │
│       • Heavy Forwarders (configs come from DS)                         │
│       • Cluster Manager (SH queries it)                                 │
│       • License Master (SH queries it)                                  │
│                                                                          │
│     The ONLY exception: Optionally run on Deployment Server if you      │
│     need forwarder deployment configs (deployment-apps/).               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Standalone Splunk Enterprise

**Description**: Single server running all Splunk components

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the single Splunk server |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Any admin account |
| **Special Considerations** | None - full access from one server |

```
┌─────────────────────────────────────┐
│         STANDALONE SERVER           │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  ✅ Run script HERE         │   │
│  │  • Full file system access  │   │
│  │  • Full REST API access     │   │
│  │  • All data available       │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

### 4.2 Distributed Environment (Search Head + Indexers)

**Description**: Separate search heads and indexer tiers

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the **Search Head** (NOT indexers) |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Admin account with distributed search access |
| **Special Considerations** | Index stats come from search peers via REST |

```
┌─────────────────────────────────────────────────────────────┐
│                 DISTRIBUTED ENVIRONMENT                      │
│                                                              │
│  ┌──────────────────┐       ┌─────────────────────────────┐ │
│  │  SEARCH HEAD     │       │  INDEXER CLUSTER            │ │
│  │                  │ REST  │                              │ │
│  │  ✅ Run HERE     ├──────►│  ❌ DO NOT run here         │ │
│  │  • Dashboards    │       │  (SH queries via REST)      │ │
│  │  • Alerts        │       │                              │ │
│  │  • Users/RBAC    │       └─────────────────────────────┘ │
│  │  • Usage stats   │                                       │
│  │  • Index stats   │ ◄── Collected via REST from indexers │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 Search Head Cluster (SHC)

**Description**: Multiple search heads in a cluster for high availability

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the **SHC Captain** (preferred) or any member |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Admin account |
| **Special Considerations** | Captain has authoritative view of all shared objects |

```
┌─────────────────────────────────────────────────────────────┐
│               SEARCH HEAD CLUSTER                            │
│                                                              │
│  ┌──────────────────┐                                       │
│  │  SHC CAPTAIN     │ ◄── Run script HERE (preferred)       │
│  │  • Authoritative  │                                       │
│  │  • All shared KOs │                                       │
│  └────────┬─────────┘                                       │
│           │                                                  │
│  ┌────────┼────────┐                                        │
│  │        │        │                                         │
│  ▼        ▼        ▼                                         │
│ ┌───┐   ┌───┐   ┌───┐                                       │
│ │SH1│   │SH2│   │SH3│  ◄── Or run on any member             │
│ └───┘   └───┘   └───┘      (may miss some shared objects)   │
└─────────────────────────────────────────────────────────────┘
```

**Finding the SHC Captain**:
```bash
$SPLUNK_HOME/bin/splunk show shcluster-status -auth admin:password
```

### 4.4 Indexer Cluster

**Description**: Clustered indexers with a Cluster Manager

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the **Search Head** (NOT Cluster Manager or indexers) |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Admin account |
| **Special Considerations** | Run on SH; CM only for cluster configs if needed |

```
┌─────────────────────────────────────────────────────────────┐
│                INDEXER CLUSTER                               │
│                                                              │
│  ┌──────────────────┐                                       │
│  │  SEARCH HEAD     │ ◄── Run script HERE                   │
│  │  • Dashboards    │                                        │
│  │  • Alerts        │                                        │
│  │  • Full export   │                                        │
│  └────────┬─────────┘                                       │
│           │ REST                                             │
│  ┌────────┴────────────────────────────────────────┐        │
│  │           INDEXER CLUSTER                         │        │
│  │  ┌────────────┐                                  │        │
│  │  │ Cluster    │ ◄── Only for cluster topology    │        │
│  │  │ Manager    │     (optional, script handles)   │        │
│  │  └─────┬──────┘                                  │        │
│  │        │                                          │        │
│  │  ┌─────┼─────┬─────┐                             │        │
│  │  ▼     ▼     ▼     ▼                              │        │
│  │ IDX1  IDX2  IDX3  IDX4                           │        │
│  └──────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 4.5 Universal Forwarder

**Description**: Lightweight agent that only forwards data

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the forwarder host |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Not needed (no REST API on UF) |
| **Special Considerations** | **LIMITED EXPORT** - No dashboards, alerts, or users |

```
┌─────────────────────────────────────────────────────────────┐
│            UNIVERSAL FORWARDER                               │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  WHAT CAN BE COLLECTED:                               │   │
│  │  ✓ inputs.conf (what logs are being monitored)        │   │
│  │  ✓ outputs.conf (where logs are forwarded to)         │   │
│  │  ✓ props.conf (any local parsing rules)               │   │
│  │  ✓ deploymentclient.conf (deployment server config)   │   │
│  │                                                       │   │
│  │  WHAT CANNOT BE COLLECTED:                            │   │
│  │  ✗ Dashboards (UF has no search capability)           │   │
│  │  ✗ Alerts (UF cannot run searches)                    │   │
│  │  ✗ Users/RBAC (minimal authentication)                │   │
│  │  ✗ Usage analytics (no search history)                │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  RECOMMENDATION: Run full export on Search Head instead     │
└─────────────────────────────────────────────────────────────┘
```

### 4.6 Heavy Forwarder

**Description**: Full Splunk instance configured for forwarding with parsing

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the Heavy Forwarder |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Admin account (REST API available) |
| **Special Considerations** | Focus on data routing configs; no dashboards |

### 4.7 Deployment Server

**Description**: Central configuration management for forwarders

| Requirement | Details |
|-------------|---------|
| **Server Access** | SSH to the Deployment Server |
| **OS User** | `splunk` or `root` |
| **Splunk User** | Admin account |
| **Special Considerations** | Collects deployed app configurations |

```
┌─────────────────────────────────────────────────────────────┐
│              DEPLOYMENT SERVER                               │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  WHAT CAN BE COLLECTED:                               │   │
│  │  ✓ deployment-apps/* (all apps deployed to forwarders)│   │
│  │  ✓ serverclass.conf (which forwarders get which apps) │   │
│  │  ✓ Server configurations                              │   │
│  │                                                       │   │
│  │  WHAT CANNOT BE COLLECTED:                            │   │
│  │  ✗ Dashboards (typically not on DS)                   │   │
│  │  ✗ Alerts (typically not on DS)                       │   │
│  │  ✗ Usage analytics (no searches run here)             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  NOTE: DS export is useful for understanding forwarder      │
│        configurations and data collection landscape         │
└─────────────────────────────────────────────────────────────┘
```

### 4.8 Splunk Cloud (Classic & Victoria Experience)

**⚠️ NOT CURRENTLY SUPPORTED BY THIS SCRIPT**

**Description**: Splunk-managed SaaS deployment

```
┌─────────────────────────────────────────────────────────────┐
│                  SPLUNK CLOUD                                │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                                                       │   │
│  │  ❌ THIS SCRIPT DOES NOT SUPPORT SPLUNK CLOUD         │   │
│  │                                                       │   │
│  │  Splunk Cloud (both Classic and Victoria Experience)  │   │
│  │  does NOT allow SSH access to the infrastructure.     │   │
│  │                                                       │   │
│  │  This script requires file system access to:          │   │
│  │    • $SPLUNK_HOME/etc/apps/                          │   │
│  │    • $SPLUNK_HOME/etc/system/local/                  │   │
│  │    • $SPLUNK_HOME/var/log/splunk/                    │   │
│  │                                                       │   │
│  │  Which is not possible in Splunk Cloud.               │   │
│  │                                                       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  FOR SPLUNK CLOUD MIGRATIONS:                               │
│                                                              │
│  Contact the DynaBridge team for:                           │
│  • Splunk Cloud REST API-only export script                 │
│  • Cloud-specific migration guidance                        │
│  • Hybrid (Cloud + On-prem) migration patterns              │
│                                                              │
│  A future version may include --cloud mode for REST-only    │
│  collection from Splunk Cloud environments.                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

| Requirement | Details |
|-------------|---------|
| **Server Access** | ❌ Not possible - No SSH to Splunk Cloud |
| **This Script** | ❌ Not supported |
| **Alternative** | Contact DynaBridge team for Cloud export tool |

---

## 5. Pre-Flight Checklist

Before running the export script, verify each item:

### Server & OS Access

- [ ] I have SSH or console access to the appropriate Splunk server
- [ ] I can switch to the `splunk` user OR I have root access
- [ ] I can read files in `$SPLUNK_HOME/etc/`

### Splunk Credentials

- [ ] I have a Splunk admin username and password
- [ ] The account has `admin_all_objects` capability
- [ ] The account has `list_users` and `list_roles` capabilities

### Network & Firewall

- [ ] The Splunk REST API port (default 8089) is accessible locally
- [ ] For Splunk Cloud: I can reach the cloud URL from my machine

### Disk Space

- [ ] I have at least 500 MB free in `/tmp` for the export archive
- [ ] (Optional) I have space to store the archive before download

### Time & Scheduling

- [ ] I'm running this during a low-activity period (recommended)
- [ ] I have approximately 15-30 minutes for the export to complete
- [ ] I've notified relevant teams about the export activity

---

## 6. What Data Gets Collected

### 6.1 Data Collection Summary

| Data Type | File/Location | Sensitivity | Redacted? |
|-----------|---------------|-------------|-----------|
| Server info | _systeminfo/server_info.json | Low | No |
| App list | _systeminfo/installed_apps.json | Low | No |
| props.conf | [app]/default/props.conf | Low | No |
| transforms.conf | [app]/default/transforms.conf | Low | No |
| indexes.conf | _system/local/indexes.conf | Low | No |
| inputs.conf | [app]/local/inputs.conf | Medium | Paths only |
| savedsearches.conf | [app]/local/savedsearches.conf | Medium | No |
| Dashboards XML | [app]/data/ui/views/*.xml | Low | No |
| Dashboard Studio | dashboard_studio/*.json | Low | No |
| Users list | _rbac/users.json | Medium | Emails included |
| Roles list | _rbac/roles.json | Low | No |
| LDAP/SAML config | _rbac/authentication.conf | Medium | Passwords redacted |
| Usage analytics | _usage_analytics/*.json | Low | Anonymizable |
| Audit sample | _audit_sample/audit_sample.log | Medium | Optional |

### 6.2 Sensitive Data Handling

The script automatically redacts or excludes:

```
ALWAYS REDACTED:
• Passwords (password = [REDACTED])
• API tokens (token = [REDACTED])
• Private keys (privateKey = [REDACTED])
• Session tokens
• LDAP bind credentials

NEVER COLLECTED:
• Actual log data
• Search results
• KV Store data (except dashboard definitions)
• Encrypted credential storage
```

### 6.3 Optional/Sensitive Collections

These require explicit opt-in:

| Collection | Risk Level | Contains |
|------------|------------|----------|
| **Lookup Tables** | Medium | May contain reference data with PII |
| **Audit Log Sample** | Medium | May contain search queries with sensitive terms |
| **User Email Addresses** | Low | PII but useful for ownership mapping |

---

## 7. Security & Privacy Considerations

### 7.1 Data Stays Local

The export script:
- Creates a `.tar.gz` file on the local filesystem
- Does NOT transmit data to any external service
- Does NOT require internet access (except for Splunk Cloud)
- Does NOT modify any Splunk configurations

### 7.2 Secure the Export File

After the export completes:

```bash
# The export file is created with restrictive permissions
ls -la /tmp/splunk_export_*.tar.gz
# -rw------- 1 splunk splunk 150M Jan 15 10:30 splunk_export_...

# Transfer securely (examples)
scp /tmp/splunk_export_*.tar.gz user@secure-host:/path/
rsync -avz --progress /tmp/splunk_export_*.tar.gz user@host:/path/

# Delete after transfer
rm /tmp/splunk_export_*.tar.gz
```

### 7.3 Audit Trail

The script logs its activities:

```bash
# View what the script did
cat /tmp/splunk_export_*/export.log

# The audit log shows:
# - What was collected
# - What was skipped
# - Any errors encountered
# - Duration of each step
```

### 7.4 Approval Workflow

For regulated environments, consider:

1. **Pre-Approval**: Get written approval before running the export
2. **Witness**: Have a security team member observe the export
3. **Review**: Examine the export contents before sharing
4. **Document**: Log the export as a data handling event

### 7.5 Data Anonymization (Option 9)

When sharing exports with third parties (e.g., migration consultants, Dynatrace Professional Services), enable **Option 9: Anonymize Sensitive Data** to protect privacy while preserving data relationships.

**What Gets Anonymized:**

| Data Type | Original | Anonymized |
|-----------|----------|------------|
| **Email Addresses** | `john.doe@acme-corp.com` | `user3f8a2c@anon.dynabridge.local` |
| **Hostnames** | `splunk-idx01.acme.internal` | `host-7b4c9e12.anon.local` |
| **IP Addresses** | `192.168.1.100` | `[IP-REDACTED]` |
| **IPv6 Addresses** | `2001:db8::1` | `[IPv6-REDACTED]` |

**Key Features:**

- **Consistent Mapping**: The same original value always produces the same anonymized value, preserving relationships (e.g., all logs from `server-01` still appear together)
- **Hash-Based**: Uses SHA-256 hashing, so anonymized values cannot be reversed to reveal originals
- **Selective**: `localhost` and `127.0.0.1` are preserved
- **Report**: Creates `_anonymization_report.json` documenting what was anonymized

**When to Use:**

```
✅ Use Anonymization When:
  • Sharing export with external consultants
  • Sending to vendor for analysis
  • Including in support tickets
  • Uploading to shared/cloud environments

❌ Skip Anonymization When:
  • Internal use only
  • Migration team needs real hostnames for planning
  • Troubleshooting requires actual IP addresses
```

**To Enable:**

During Step 4 (Data Categories), enter `9` to toggle anonymization ON:

```
Enter numbers to toggle (e.g., 7,8,9 to add lookups, audit, and anonymization)
Toggle: 9
✓ Data Anonymization: ON - Emails, hostnames, and IPs will be anonymized
```

---

## 8. Command-Line Arguments & Automation

**NEW in v4.0**: The script now supports command-line arguments for automation and CI/CD pipelines.

### 8.1 Available Command-Line Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `-u, --username` | Splunk admin username | `-u admin` |
| `-p, --password` | Splunk admin password | `-p MyPassword123` |
| `-h, --host` | Splunk host (default: localhost) | `-h splunk-server.local` |
| `-P, --port` | Splunk REST API port (default: 8089) | `-P 8089` |
| `--splunk-home` | Splunk installation path | `--splunk-home /opt/splunk` |
| `--anonymize` | Enable data anonymization (default) | `--anonymize` |
| `--no-anonymize` | Disable data anonymization | `--no-anonymize` |
| `-y, --yes` | Auto-confirm all prompts (non-interactive) | `-y` |
| `--help` | Show help message | `--help` |

### 8.2 Non-Interactive Mode (Automation)

Use `-y` or `--yes` to run the script without any prompts:

```bash
# Fully automated export
./dynabridge-splunk-export.sh \
  -u admin \
  -p 'YourPassword' \
  --splunk-home /opt/splunk \
  --anonymize \
  -y
```

### 8.3 Environment Variables

The script also supports environment variables (useful for container deployments):

| Variable | Description |
|----------|-------------|
| `SPLUNK_USER` or `SPLUNK_ADMIN_USER` | Splunk username |
| `SPLUNK_PASSWORD` or `SPLUNK_ADMIN_PASSWORD` | Splunk password |

Example:
```bash
export SPLUNK_ADMIN_USER="admin"
export SPLUNK_ADMIN_PASSWORD="MySecurePassword"
./dynabridge-splunk-export.sh -y --splunk-home /opt/splunk
```

### 8.4 CI/CD Pipeline Integration

Example for Jenkins/GitLab CI:

```yaml
# GitLab CI example
splunk_export:
  stage: export
  script:
    - chmod +x dynabridge-splunk-export.sh
    - ./dynabridge-splunk-export.sh \
        -u $SPLUNK_USER \
        -p $SPLUNK_PASSWORD \
        --splunk-home /opt/splunk \
        --anonymize \
        -y
  artifacts:
    paths:
      - dynabridge-export-*.tar.gz
```

### 8.5 Enhanced Anonymization (v4.0)

The v4.0 script now anonymizes additional sensitive data types:

| Data Type | Anonymization Pattern |
|-----------|----------------------|
| Email addresses | `user######@anon.dynabridge.local` |
| Hostnames | `host-########.anon.local` |
| IP addresses | `[IP-REDACTED]` |
| **Webhook URLs** | `https://webhook.anon.dynabridge.local/hook-###` |
| **API keys/tokens** | `[API-KEY-########]` |
| **PagerDuty keys** | `[PAGERDUTY-KEY-########]` |
| **Slack channels** | `#anon-channel-######` |
| **Usernames** | `anon-user-######` |

This ensures your export can be safely shared with consultants or support teams.

### 8.6 Enterprise Resilience Features (v4.0.0)

**NEW in v4.0.0**: The script now includes comprehensive enterprise-scale features for environments with 4000+ dashboards and 10K+ alerts.

#### Default Settings (Enterprise-Ready)

| Setting | Default | Description |
|---------|---------|-------------|
| `BATCH_SIZE` | 100 | Items per API request |
| `API_TIMEOUT` | 120s | Per-request timeout (2 min) |
| `MAX_TOTAL_TIME` | 14400s | Max runtime (4 hours) |
| `MAX_RETRIES` | 3 | Retry attempts with exponential backoff |
| `RATE_LIMIT_DELAY` | 0.1s | Delay between API calls (100ms) |
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume capability |

#### Search Head Cluster (SHC) Detection

The script automatically detects if running on an SHC Captain and displays a warning:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  ⚠️  SEARCH HEAD CLUSTER CAPTAIN DETECTED                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  You are running this script on the SHC Captain.                        │
│                                                                          │
│  The Captain has additional cluster coordination duties. Running        │
│  intensive operations may temporarily impact cluster performance.       │
│                                                                          │
│  RECOMMENDATIONS:                                                        │
│    • Run during off-peak hours                                          │
│    • Consider running on an SHC Member instead                          │
│    • Monitor cluster health during export                               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Checkpoint/Resume Capability

If the export is interrupted (timeout, network error, Ctrl+C), you can resume:

```bash
# Script detects previous incomplete export
./dynabridge-splunk-export.sh

# Output:
# Found incomplete export from 2025-01-06 14:30:00
# Would you like to resume? (Y/n): Y
# Resuming from: Usage Analytics (step 5 of 8)...
```

#### Export Timing Statistics

At completion, the script shows detailed timing:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      EXPORT TIMING STATISTICS                            │
├─────────────────────────────────────────────────────────────────────────┤
│  Total Duration:        5 minutes 4 seconds                              │
│  API Calls:             347                                              │
│  API Retries:           2                                                │
│  API Failures:          0                                                │
│  Batches Completed:     52                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Environment Variable Overrides

For very large environments, tune via environment variables:

```bash
# Large environment (5000+ dashboards)
export BATCH_SIZE=50
export API_TIMEOUT=180
./dynabridge-splunk-export.sh

# Or inline
BATCH_SIZE=50 API_TIMEOUT=180 ./dynabridge-splunk-export.sh
```

---

## 9. Troubleshooting Access Issues

### 9.1 "Permission Denied" Reading Files

**Symptom**: Script fails with permission errors

**Solution**:
```bash
# Check current user
whoami

# Switch to splunk user
sudo su - splunk

# Or run as root
sudo bash dynabridge-splunk-export.sh
```

### 9.2 "Connection Refused" on REST API

**Symptom**: REST API calls fail

**Check**:
```bash
# Is Splunk running?
$SPLUNK_HOME/bin/splunk status

# Is the management port listening?
netstat -tlnp | grep 8089
ss -tlnp | grep 8089

# Can you connect locally?
curl -k https://localhost:8089/services/server/info -u admin:password
```

### 9.3 "Unauthorized" on REST API

**Symptom**: Authentication fails

**Check**:
```bash
# Test credentials manually
$SPLUNK_HOME/bin/splunk login -auth admin:password

# Check user capabilities
$SPLUNK_HOME/bin/splunk show user-info -auth admin:password
```

### 9.4 "Capability Not Granted"

**Symptom**: REST calls return 403 for certain endpoints

**Solution**: Add required capabilities to the user's role:
```bash
$SPLUNK_HOME/bin/splunk edit role your_role \
  -capability list_users \
  -capability list_roles \
  -capability admin_all_objects \
  -auth admin:password
```

### 9.5 Splunk Cloud Access Issues

**Symptom**: Cannot reach Splunk Cloud

**Check**:
```bash
# Test network connectivity
curl -I https://your-stack.splunkcloud.com

# Check if port is blocked
telnet your-stack.splunkcloud.com 8089

# Verify credentials
curl -k https://your-stack.splunkcloud.com:8089/services/server/info \
  -u your_username:your_password
```

### 9.6 Search Head Cluster Issues

**Symptom**: Missing dashboards or knowledge objects

**Solution**: Run the script on the SHC Captain:
```bash
# Find the captain
$SPLUNK_HOME/bin/splunk show shcluster-status -auth admin:password | grep -i captain

# SSH to captain and run script there
ssh splunk@shc-captain.company.com
bash dynabridge-splunk-export.sh
```

---

## Quick Reference Card

### Where to Run - Decision Tree

```
Is it Splunk Cloud?
  └─ YES → ❌ This script not supported. Contact DynaBridge team.
  └─ NO  → Is it a distributed environment?
             └─ YES → Run on Search Head (or SHC Captain)
             └─ NO  → Run on the standalone Splunk server
```

### Minimum Requirements Summary

| Environment | Where to Run | OS User | Splunk User | Notes |
|-------------|--------------|---------|-------------|-------|
| Standalone | The server | `splunk` | Admin | Full export |
| Distributed | **Search Head only** | `splunk` | Admin | Queries indexers via REST |
| SHC | **SHC Captain only** | `splunk` | Admin | Has all shared objects |
| Indexer Cluster | **Search Head only** | `splunk` | Admin | SH queries cluster via REST |
| With Deployment Server | SH + optionally DS | `splunk` | Admin | DS for forwarder configs |
| Universal Forwarder | ❌ Don't run here | - | - | Use Deployment Server instead |
| Heavy Forwarder | ❌ Don't run here | - | - | Use Deployment Server instead |
| Splunk Cloud | ❌ Not supported | - | - | Different script needed |

### One-Liner Access Test

```bash
# Test everything at once
sudo -u splunk $SPLUNK_HOME/bin/splunk search "| rest /services/authentication/current-context | table username, roles" -auth admin:password
```

If this returns your username and roles, you're ready to run the export script!

---

## Next Steps

Once you've verified all requirements:

1. **Download the script**: `dynabridge-splunk-export.sh`
2. **Copy to Splunk server**: `scp dynabridge-splunk-export.sh splunk-server:/tmp/`
3. **Run the script**: `sudo -u splunk bash /tmp/dynabridge-splunk-export.sh`
4. **Follow the prompts**: The script will guide you through each step
5. **Download the export**: Copy the `.tar.gz` file to your workstation
6. **Upload to DynaBridge**: Open DynaBridge in Dynatrace and upload

---

## What to Expect: Step-by-Step Walkthrough

This section shows exactly what you'll see when running the script successfully.

### Step 1: Launch and Welcome Screen

When you run `./dynabridge-splunk-export.sh`, you'll see:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║  ██████╗ ██╗   ██╗███╗   ██╗ █████╗ ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗ ║
║  ██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝ ║
║  ██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗   ║
║  ██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝   ║
║  ██████╔╝   ██║   ██║ ╚████║██║  ██║██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗ ║
║  ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝ ║
║                                                                                ║
║                 🏢  SPLUNK ENTERPRISE EXPORT SCRIPT  🏢                       ║
║                                                                                ║
║          Complete Data Collection for Migration to Dynatrace Gen3            ║
║                        Version 4.0.0                                    ║
║                                                                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Documentation: See README-SPLUNK-ENTERPRISE.md for prerequisites

Ready to begin? (Y/n):
```

**Action**: Press `Y` or Enter to continue.

### Step 2: Pre-Flight Checklist

After confirming, you'll see a checklist and system verification:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     PRE-FLIGHT CHECKLIST                                    ║
║         Please confirm you have the following before continuing            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  SHELL ACCESS:                                                              ║
║    □  SSH access to Splunk server (or running locally on Splunk server)    ║
║    □  User with read access to $SPLUNK_HOME directory                      ║
║    □  Root/sudo access (may be needed for some configs)                    ║
║                                                                              ║
║  🔒 DATA PRIVACY & SECURITY:                                                ║
║                                                                              ║
║  We do NOT collect or export:                                              ║
║    ✗  User passwords or password hashes                                    ║
║    ✗  API tokens or session keys                                           ║
║    ✗  Private keys or certificates                                         ║
║    ✗  Your actual log data (only metadata/structure)                       ║
║    ✗  SSL certificates or .pem files                                       ║
║                                                                              ║
║  We automatically REDACT:                                                  ║
║    ✓  password = [REDACTED] in all .conf files                             ║
║    ✓  secret = [REDACTED] in outputs.conf                                  ║
║    ✓  pass4SymmKey = [REDACTED] in server.conf                             ║
║    ✓  sslPassword = [REDACTED] in inputs.conf                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Quick System Check:
    ✓ bash: 4.4.20(1)-release (4.0+ required)
    ✓ curl: 7.88.1
    ✓ Python: Python 3.9.16 (Splunk bundled)
    ✓ tar: available
    ✓ SPLUNK_HOME: /opt/splunk

Ready to proceed? (Y/n):
```

**Action**: Press `Y` if all checks pass.

### Step 3: SPLUNK_HOME Detection

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: DETECTING SPLUNK INSTALLATION                                       │
└─────────────────────────────────────────────────────────────────────────────┘

◐ Searching for Splunk installation...
✓ Found SPLUNK_HOME: /opt/splunk

  Splunk Version: 9.1.2
  Splunk Build:   abc123def
  Server Name:    splunk-sh01
  Server Role:    search_head

  Is this the correct Splunk installation? (Y/n): Y
```

**Action**: Confirm the detected Splunk installation.

### Step 4: Environment Detection

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: DETECTING ENVIRONMENT                                               │
└─────────────────────────────────────────────────────────────────────────────┘

◐ Analyzing Splunk environment...

  Detected Configuration:
  ┌────────────────────────────────────────────────────────────────────────┐
  │  Deployment Type:     Distributed (Search Head)                        │
  │  Search Head Cluster: Yes (Captain)                                    │
  │  Indexer Cluster:     Yes (connected)                                  │
  │  Deployment Server:   No                                               │
  │  License Master:      Connected                                        │
  └────────────────────────────────────────────────────────────────────────┘

  Apps Found: 24 apps in $SPLUNK_HOME/etc/apps/
  Users:      15 users configured

  Is the detected environment correct? (Y/n): Y
```

**Action**: Confirm the environment detection is accurate.

### Step 5: Select Data Categories

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: DATA CATEGORIES                                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Select data categories to collect:

  [✓] 1. Configuration Files (props, transforms, indexes, inputs)
      → Required for understanding data pipeline

  [✓] 2. Dashboards (Classic XML + Dashboard Studio JSON)
      → Visual content for conversion to Dynatrace apps

  [✓] 3. Alerts & Saved Searches (savedsearches.conf)
      → Critical for operational continuity

  [✓] 4. Users, Roles & Groups (RBAC data - NO passwords)
      → Usernames and roles only - passwords are NEVER collected

  [✓] 5. Usage Analytics (search frequency, dashboard views)
      → Identifies high-value assets worth migrating

  [✓] 6. Index & Data Statistics
      → Volume metrics for capacity planning

  [ ] 7. Lookup Tables (.csv files)
      → May contain sensitive data - review before including

  [ ] 8. Audit Log Sample (last 10,000 entries)
      → May contain sensitive query content

  [ ] 9. Anonymize Sensitive Data (emails, hostnames, IPs)
      → Replaces real data with consistent fake values
      → RECOMMENDED when sharing export with third parties

  🔒 Privacy: Passwords are NEVER collected. Secrets in .conf files are auto-redacted.

Enter numbers to toggle (e.g., 7,8,9 to add lookups, audit, and anonymization)
Or press Enter to accept defaults [1-6]:
```

**Action**: Press Enter to accept defaults, or enter numbers to toggle options.

### Step 6: Splunk Authentication (for Usage Analytics)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: SPLUNK AUTHENTICATION                                               │
└─────────────────────────────────────────────────────────────────────────────┘

  WHY WE NEED THIS:
  Some data requires accessing Splunk's REST API, including:
    • Dashboard Studio dashboards (stored in KV Store)
    • User and role information
    • Usage analytics from internal indexes
    • Distributed environment topology

  REQUIRED PERMISSIONS:
  The account needs: admin_all_objects, list_users, list_roles

  SECURITY NOTE:
  Credentials are only used locally and are never stored or transmitted.

Splunk admin username [admin]: admin
Splunk admin password: ••••••••••••

◐ Testing authentication...
✓ Authentication successful

◐ Checking account capabilities...
✓ admin_all_objects: granted
✓ list_users: granted
✓ list_roles: granted
✓ search: granted
```

**Action**: Enter Splunk admin credentials.

### Step 7: Data Collection Progress

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ COLLECTING DATA                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

  [1/8] Collecting system information...
✓ Server info collected
✓ License info collected
✓ Installed apps list collected

  [2/8] Collecting configuration files...
✓ apps/search/local/props.conf
✓ apps/search/local/transforms.conf
✓ apps/security_essentials/local/savedsearches.conf
[████████████████████████████████████████] 100% (127 files)

  [3/8] Collecting dashboards...
✓ apps/search/default/data/ui/views/ (12 dashboards)
✓ apps/security_essentials/default/data/ui/views/ (28 dashboards)
✓ Dashboard Studio: 15 dashboards from KV Store

  [4/8] Collecting alerts and saved searches...
✓ Collected 156 saved searches
✓ Identified 47 alerts (alert.track = 1)

  [5/8] Collecting users and roles...
✓ 15 users collected (passwords NOT collected)
✓ 8 roles collected with capabilities

  [6/8] Collecting usage analytics...
◐ Running: Dashboard views (last 30 days)...
✓ Dashboard usage collected
◐ Running: Most active users...
✓ User activity collected
◐ Running: Alert execution history...
✓ Alert statistics collected

  [7/8] Collecting index statistics...
✓ 23 indexes analyzed
✓ Volume metrics collected

  [8/8] Generating manifest and summary...
✓ manifest.json created
✓ dynasplunk-env-summary.md created
```

### Step 8: Export Complete

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         EXPORT COMPLETE!                                     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Export Archive:                                                             ║
║    📦 dynabridge_export_splunk-sh01_20241203_152347.tar.gz                   ║
║                                                                              ║
║  Summary:                                                                    ║
║  ┌──────────────────────────────────────────────────────────────────────┐   ║
║  │  Dashboards:        55 (40 Classic + 15 Studio)                      │   ║
║  │  Alerts:            47                                               │   ║
║  │  Saved Searches:    156                                              │   ║
║  │  Users:             15                                               │   ║
║  │  Roles:             8                                                │   ║
║  │  Apps:              24                                               │   ║
║  │  Indexes:           23                                               │   ║
║  │  Config Files:      127                                              │   ║
║  └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
║  Duration: 7 minutes 12 seconds                                              ║
║  Archive Size: 8.7 MB                                                        ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  NEXT STEPS:                                                                 ║
║                                                                              ║
║  1. Copy the export to your workstation:                                     ║
║     scp splunk-sh01:/tmp/dynabridge_export_*.tar.gz ./                       ║
║                                                                              ║
║  2. Upload to DynaBridge:                                                    ║
║     Open DynaBridge for Splunk app → Data Sources → Upload Export            ║
║                                                                              ║
║  3. Review the summary report:                                               ║
║     cat dynabridge_export_splunk-sh01_20241203_152347/                       ║
║         dynasplunk-env-summary.md                                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### What Success Looks Like

After a successful export, you'll have a `.tar.gz` file. Extract it to see:

```bash
$ tar -tzf dynabridge_export_splunk-sh01_20241203_152347.tar.gz | head -25

dynabridge_export_splunk-sh01_20241203_152347/
dynabridge_export_splunk-sh01_20241203_152347/manifest.json
dynabridge_export_splunk-sh01_20241203_152347/dynasplunk-env-summary.md
dynabridge_export_splunk-sh01_20241203_152347/_export.log
dynabridge_export_splunk-sh01_20241203_152347/_systeminfo/
dynabridge_export_splunk-sh01_20241203_152347/_systeminfo/environment.json
dynabridge_export_splunk-sh01_20241203_152347/_systeminfo/server_info.json
dynabridge_export_splunk-sh01_20241203_152347/_systeminfo/license_info.json
dynabridge_export_splunk-sh01_20241203_152347/_rbac/
dynabridge_export_splunk-sh01_20241203_152347/_rbac/users.json
dynabridge_export_splunk-sh01_20241203_152347/_rbac/roles.json
dynabridge_export_splunk-sh01_20241203_152347/_usage_analytics/
dynabridge_export_splunk-sh01_20241203_152347/_usage_analytics/dashboard_views.json
dynabridge_export_splunk-sh01_20241203_152347/_usage_analytics/users_most_active.json
dynabridge_export_splunk-sh01_20241203_152347/_usage_analytics/alert_execution_history.json
dynabridge_export_splunk-sh01_20241203_152347/_indexes/
dynabridge_export_splunk-sh01_20241203_152347/_indexes/index_stats.json
dynabridge_export_splunk-sh01_20241203_152347/search/
dynabridge_export_splunk-sh01_20241203_152347/search/local/props.conf
dynabridge_export_splunk-sh01_20241203_152347/search/local/transforms.conf
dynabridge_export_splunk-sh01_20241203_152347/search/local/savedsearches.conf
dynabridge_export_splunk-sh01_20241203_152347/search/default/data/ui/views/
dynabridge_export_splunk-sh01_20241203_152347/security_essentials/
dynabridge_export_splunk-sh01_20241203_152347/dashboard_studio/
```

### If Something Goes Wrong

If errors occur, you'll see a warning box:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  ⚠️  EXPORT COMPLETED WITH 2 ERRORS                                          ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Some data could not be collected. See details below:                        ║
║                                                                              ║
║  Errors:                                                                     ║
║    • Permission denied reading /opt/splunk/etc/apps/custom_app/local/        ║
║    • REST API timeout querying indexer cluster status                        ║
║                                                                              ║
║  A troubleshooting report has been generated:                                ║
║    📄 TROUBLESHOOTING.md                                                      ║
║                                                                              ║
║  The export is still usable - only the failed items are missing.             ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

Review `TROUBLESHOOTING.md` in the export directory for specific remediation steps.

### Verifying the Export

After the export completes, verify it's valid:

```bash
# Check the manifest
$ cat dynabridge_export_*/manifest.json | jq '.statistics'
{
  "apps": 24,
  "dashboards": 55,
  "alerts": 47,
  "saved_searches": 156,
  "users": 15,
  "roles": 8,
  "indexes": 23
}

# Check for errors in the log
$ grep -i error dynabridge_export_*/_export.log
(no output = no errors)

# Verify archive integrity
$ tar -tzf dynabridge_export_*.tar.gz > /dev/null && echo "Archive OK"
Archive OK
```

---

## Sample Output Files

### Example: dynasplunk-env-summary.md

This human-readable summary report is generated in the export directory:

```markdown
# DynaSplunk Environment Summary

**Export Date**: 2025-12-03T20:23:47Z
**Hostname**: splunk-sh01.acme-corp.com
**Export Tool Version**: 4.0.0

---

## Environment Overview

| Attribute | Value |
|-----------|-------|
| **Product** | Splunk Enterprise |
| **Role** | Search Head |
| **Architecture** | Distributed |
| **SPLUNK_HOME** | /opt/splunk |

---

## Export Statistics

| Category | Count |
|----------|-------|
| **Applications Exported** | 24 |
| **Dashboards** | 156 |
| **Alerts** | 47 |
| **Users** | 15 |
| **Indexes** | 23 |
| **Errors** | 0 |

---

## Applications Included

- search
- security_essentials
- enterprise_security
- itsi
- splunk_app_for_aws
- splunk_app_for_infrastructure
- Splunk_TA_windows
- Splunk_TA_nix
- phantom
- dashboard_studio
- alert_manager
- monitoring_console
- user-prefs
- learned
- introspection_generator_addon
- custom_security_app
- compliance_reporting
- soc_dashboards
- executive_reports
- it_ops_analytics
- network_monitor
- cloud_security
- devsecops
- ml_toolkit

---

## Data Categories Collected

| Category | Collected |
|----------|-----------|
| Configuration Files | Yes |
| Dashboards | Yes |
| Alerts & Saved Searches | Yes |
| Users & RBAC | Yes |
| Usage Analytics | Yes (30d) |
| Index Statistics | Yes |
| Lookup Tables | Yes |
| Audit Log Sample | Yes |
| Data Anonymization | Yes (emails, hosts, IPs) |

---

## Next Steps

1. Download the export file from this server
2. Open DynaBridge for Splunk in Dynatrace
3. Navigate to: Migration Workspace → Project Initialization
4. Upload the .tar.gz file
5. DynaBridge will analyze your environment and show:
   - Migration readiness assessment
   - Dashboard conversion preview
   - Alert conversion checklist
   - Data pipeline requirements

---

*Generated by DynaBridge Splunk Export Tool v4.0.0*
```

### Example: manifest.json (Schema)

This machine-readable manifest is used by DynaBridge to process your export:

```json
{
  "schema_version": "3.3",
  "export_tool": "dynabridge-splunk-export",
  "export_tool_version": "4.0.0",
  "export_timestamp": "2025-12-03T20:23:47Z",
  "export_duration_seconds": 187,

  "source": {
    "hostname": "splunk-sh01",
    "fqdn": "splunk-sh01.acme-corp.com",
    "platform": "Linux",
    "platform_version": "Red Hat Enterprise Linux 8.7",
    "ip_addresses": ["10.0.1.50", "192.168.100.50"]
  },

  "splunk": {
    "home": "/opt/splunk",
    "version": "9.1.3",
    "build": "d95b3299fa65",
    "flavor": "enterprise",
    "role": "search_head",
    "architecture": "distributed",
    "license_type": "enterprise",
    "cluster_label": "acme-production",
    "is_cloud": false
  },

  "collection": {
    "configs": true,
    "dashboards": true,
    "alerts": true,
    "rbac": true,
    "usage_analytics": true,
    "usage_period": "30d",
    "indexes": true,
    "lookups": true,
    "audit_sample": true
  },

  "statistics": {
    "apps_exported": 24,
    "dashboards_classic": 128,
    "dashboards_studio": 28,
    "dashboards_total": 156,
    "alerts": 47,
    "saved_searches": 234,
    "users": 15,
    "roles": 8,
    "indexes": 23,
    "lookups": 34,
    "config_files": 156,
    "errors": 0,
    "warnings": 2,
    "total_files": 512,
    "total_size_bytes": 8847234
  },

  "apps": [
    {
      "name": "security_essentials",
      "dashboards": 32,
      "alerts": 18,
      "saved_searches": 45,
      "lookups": 8
    },
    {
      "name": "enterprise_security",
      "dashboards": 24,
      "alerts": 12,
      "saved_searches": 67,
      "lookups": 12
    },
    {
      "name": "itsi",
      "dashboards": 18,
      "alerts": 8,
      "saved_searches": 34,
      "lookups": 4
    }
  ],

  "usage_intelligence": {
    "summary": {
      "dashboards_never_viewed": 23,
      "alerts_never_fired": 11,
      "users_inactive_30d": 3,
      "alerts_with_failures": 4
    },
    "volume": {
      "avg_daily_gb": 127.4,
      "peak_daily_gb": 245.8,
      "total_30d_gb": 3822.5,
      "top_indexes_by_volume": [
        {"index": "main", "total_gb": 1245.6},
        {"index": "security", "total_gb": 876.3},
        {"index": "windows", "total_gb": 543.2},
        {"index": "linux", "total_gb": 412.8},
        {"index": "network", "total_gb": 298.4}
      ],
      "top_sourcetypes_by_volume": [
        {"sourcetype": "WinEventLog:Security", "total_gb": 567.3},
        {"sourcetype": "syslog", "total_gb": 423.8},
        {"sourcetype": "access_combined", "total_gb": 312.4},
        {"sourcetype": "aws:cloudtrail", "total_gb": 245.6}
      ],
      "top_hosts_by_volume": [
        {"host": "dc01.acme-corp.com", "total_gb": 234.5},
        {"host": "web-prod-01", "total_gb": 187.3},
        {"host": "app-server-cluster", "total_gb": 156.8}
      ]
    },
    "prioritization": {
      "top_dashboards": [
        {"dashboard": "security_overview", "app": "security_essentials", "views": 3847},
        {"dashboard": "executive_summary", "app": "executive_reports", "views": 2156},
        {"dashboard": "soc_main", "app": "soc_dashboards", "views": 1923},
        {"dashboard": "incident_tracker", "app": "enterprise_security", "views": 1654}
      ],
      "top_users": [
        {"user": "admin", "searches": 8934},
        {"user": "soc_analyst1", "searches": 5621},
        {"user": "security_lead", "searches": 4532},
        {"user": "it_ops", "searches": 3245}
      ],
      "top_alerts": [
        {"alert": "Failed Authentication", "app": "security_essentials", "fires": 1234},
        {"alert": "High CPU Usage", "app": "itsi", "fires": 567},
        {"alert": "Suspicious Network Activity", "app": "enterprise_security", "fires": 345}
      ],
      "top_sourcetypes": [
        {"sourcetype": "WinEventLog:Security", "searches": 12453},
        {"sourcetype": "syslog", "searches": 8976},
        {"sourcetype": "access_combined", "searches": 5643}
      ],
      "top_indexes": [
        {"index": "main", "searches": 15678},
        {"index": "security", "searches": 12345},
        {"index": "_audit", "searches": 4532}
      ]
    },
    "elimination_candidates": {
      "dashboards_never_viewed_count": 23,
      "alerts_never_fired_count": 11,
      "users_inactive_count": 3,
      "note": "See _usage_analytics/ for full lists of candidates"
    },
    "ownership_mapping": {
      "apps_by_owner": [
        {"owner": "security_team", "apps": ["security_essentials", "enterprise_security"]},
        {"owner": "it_ops", "apps": ["itsi", "splunk_app_for_infrastructure"]},
        {"owner": "admin", "apps": ["search", "monitoring_console"]}
      ],
      "dashboards_by_owner": [
        {"owner": "soc_analyst1", "count": 12},
        {"owner": "security_lead", "count": 8},
        {"owner": "admin", "count": 45}
      ]
    }
  },

  "cluster": {
    "is_clustered": true,
    "cluster_mode": "search_head_cluster",
    "cluster_label": "acme-production",
    "captain": "splunk-sh01.acme-corp.com",
    "members": [
      "splunk-sh01.acme-corp.com",
      "splunk-sh02.acme-corp.com",
      "splunk-sh03.acme-corp.com"
    ]
  }
}
```

This manifest enables DynaBridge to:
- **Prioritize migration** based on actual usage data (most-viewed dashboards first)
- **Identify elimination candidates** (unused dashboards/alerts - don't migrate waste)
- **Estimate data volume** for Dynatrace ingestion planning and licensing
- **Map ownership** to coordinate with stakeholders
- **Understand cluster topology** for multi-node environments

---

*For support, contact your DynaBridge administrator or visit the documentation portal.*
