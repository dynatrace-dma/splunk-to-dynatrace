# Interactive Mode Walkthrough

**Applies to**: All DMA Export Scripts (v4.5.8 Cloud / v4.4.0 Enterprise)

This document shows exactly what you will see when running each script in interactive mode. Non-interactive mode (when all required parameters are provided on the command line) skips all prompts and proceeds automatically.

---

## Splunk Cloud (Bash)

Script: `dma-splunk-cloud-export_beta.sh`

### Step 1: Launch and Welcome Screen

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
║                   SPLUNK CLOUD EXPORT SCRIPT                                   ║
║                                                                                ║
║          Complete REST API-Based Data Collection for Migration                  ║
║                        Version 4.5.8                                           ║
║                                                                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

Do you want to continue? (Y/n):
```

**Action**: Press `Y` or Enter to continue.

### Step 2: Pre-Flight Checklist

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     PRE-FLIGHT CHECKLIST                                    ║
║         Please confirm you have the following before continuing            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  SPLUNK CLOUD ACCESS:                                                      ║
║    [ ]  Splunk Cloud stack URL (e.g., your-company.splunkcloud.com)        ║
║    [ ]  Splunk username with admin privileges                              ║
║    [ ]  Splunk password OR API token (sc_admin role recommended)           ║
║                                                                              ║
║  DATA PRIVACY & SECURITY:                                                  ║
║                                                                              ║
║  We do NOT collect or export:                                              ║
║    x  User passwords or password hashes                                    ║
║    x  API tokens or session keys                                           ║
║    x  Private keys or certificates                                         ║
║    x  Your actual log data (only metadata/structure)                       ║
║                                                                              ║
║  We automatically REDACT:                                                  ║
║    +  password = [REDACTED] in all .conf files                             ║
║    +  secret = [REDACTED] in outputs.conf                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Quick System Check:
    + bash: 5.2.15(1)-release
    + curl: 8.1.2
    + Python: Python 3.11.4
    + tar: available

Ready to proceed? (Y/n):
```

**Action**: Press `Y` if all checks pass.

### Step 3: Splunk Cloud Stack URL

```
+---------------------------------------------------------------------------+
| STEP 1: SPLUNK CLOUD CONNECTION                                           |
+---------------------------------------------------------------------------+

  Your Splunk Cloud stack URL looks like:
    https://your-company.splunkcloud.com

  Enter your Splunk Cloud stack URL: acme-corp.splunkcloud.com

  Testing connection to https://acme-corp.splunkcloud.com:8089...
+ Connection successful
```

**Action**: Enter your stack URL (without `https://` prefix). The script tests TCP connectivity and TLS handshake to port 8089.

> If you need a proxy, the script will ask before this step:
> `Do you need to use a proxy server? (y/N): `

### Step 4: Authentication

```
+---------------------------------------------------------------------------+
| STEP 2: AUTHENTICATION                                                    |
+---------------------------------------------------------------------------+

  Choose authentication method:

    1) API Token (recommended)
    2) Username/Password

  Select option [1]: 1

  Enter API token: ********************************

  Testing authentication...
+ Token authentication successful (prefix: Bearer, user: admin)
```

**Action**: Choose your auth method and enter credentials. The script automatically detects whether your token requires the `Bearer` or `Splunk` prefix (v4.5.8).

> **Capability check**: After authentication, the script verifies your permissions:
> ```
>   Checking capabilities...
> + All required capabilities present
> ```
> If capabilities are missing, you'll see a warning but the export continues (some data may be incomplete).

### Step 5: Application Selection

```
+---------------------------------------------------------------------------+
| STEP 3: APPLICATION SELECTION                                             |
+---------------------------------------------------------------------------+

  Found 24 applications.

  Export options:
    1) All applications (recommended for full migration analysis)
    2) Select specific applications
    3) Top apps by dashboard count

  Select option [1]: 1

-> Will export 24 app(s)
```

**Action**: Press `1` or Enter to export all apps. Option 2 lets you enter a comma-separated list.

### Step 6: Data Categories

```
+---------------------------------------------------------------------------+
| STEP 5: DATA CATEGORIES                                                   |
+---------------------------------------------------------------------------+

  Select data categories to collect:

    [+] 1. Configurations (via REST - reconstructed from API)
    [+] 2. Dashboards (Classic + Dashboard Studio)
    [+] 3. Alerts & Saved Searches
    [ ] 4. Users & RBAC (use --rbac to enable)
    [ ] 5. Usage Analytics (use --usage to enable; requires _audit access)
    [+] 6. Index Statistics
    [ ] 7. Lookup Contents (may be large)
    [+] 8. Anonymize Data (emails->fake, hosts->fake, IPs->redacted)

  Privacy: User data includes names/roles only. Passwords are NEVER collected.
  Tip: Enable option 8 when sharing export with third parties.

  Accept defaults? (Y/n): Y
```

**Action**: Press `Y` to accept, or `n` to toggle individual categories by number. Note that RBAC (4) and Usage Analytics (5) are **OFF by default** since v4.2.4 — enable them with `--rbac` and `--usage` if needed.

### Step 7: Analytics Period (if Usage enabled)

If you enabled Usage Analytics (option 5), you'll be prompted:

```
  Select analytics time window:

    1) Last 7 days (recommended, fast)
    2) Last 30 days
    3) Last 90 days
    4) Last 365 days

  Select option [1]: 1

-> Analytics period: 7d
```

**Action**: Choose a time window. Shorter periods are faster. Default is 7 days (v4.5.8).

> Skip this prompt entirely by passing `--analytics-period 7d` on the command line.

### Step 8: Data Collection Progress

```
+---------------------------------------------------------------------------+
| COLLECTING DATA                                                           |
+---------------------------------------------------------------------------+

  [1/7] Collecting system information...
+ Server info collected
+ Installed apps collected

  [2/7] Collecting configurations via REST API...
+ Props configuration collected
+ Transforms configuration collected
+ Indexes configuration collected

  [3/7] Collecting dashboards...
  [========================================] 100% security_app/security_overview
+ Collected 47 Classic dashboards
+ Collected 12 Dashboard Studio dashboards

  [4/7] Collecting alerts and saved searches...
+ Collected 89 saved searches (34 alerts)

  [5/7] Running global aggregate analytics...

    Analytics period: 7d | Dispatch: async (max 1h per query)
    Queries use verified field names: provenance, sourcetype=audittrail

-> Running: Dashboard views (global, provenance-based)
  [DISPATCH] sid=1711929583.12345
  [RUNNING] 15s elapsed, poll interval 10s
  [DONE] 23s total
+ Completed search: Dashboard views (23s)

-> Running: User activity (global)
+ Completed search: User activity (8s)

-> Running: Search type breakdown (global)
+ Completed search: Search type breakdown (12s)

  ... (6 queries total)

+ Global analytics completed in 67s (6 queries vs 168 in previous versions)

  [6/7] Collecting index statistics...
+ Index stats collected for 15 indexes

  [7/7] Creating archive...
+ Original archive: dma_cloud_export_acme-corp_20260402_143052.tar.gz
+ Masked archive:   dma_cloud_export_acme-corp_20260402_143052_masked.tar.gz
```

**What's happening**: Analytics searches use async dispatch (v4.5.0+) — each query is dispatched immediately and polled with adaptive intervals (5s to 30s). This replaces the old blocking mode that had a hard 300-second timeout. For 24 apps, v4.5.8 runs 6 global queries instead of 168 per-app queries.

### Step 9: Export Complete

```
+============================================================================+
|                         EXPORT COMPLETE!                                    |
+=============================================================================
|                                                                             |
|  Export Archives:                                                           |
|    dma_cloud_export_acme-corp_20260402_143052.tar.gz          (original)    |
|    dma_cloud_export_acme-corp_20260402_143052_masked.tar.gz   (anonymized)  |
|                                                                             |
|  Summary:                                                                   |
|    Dashboards:        59 (47 Classic + 12 Studio)                           |
|    Alerts:            34                                                    |
|    Saved Searches:    89                                                    |
|    Apps:              24                                                    |
|    Indexes:           15                                                    |
|                                                                             |
|  Duration: 2 minutes 47 seconds                                             |
|  Archive Size: 2.3 MB                                                       |
|                                                                             |
|  NEXT STEPS:                                                                |
|                                                                             |
|  1. Upload the _masked archive to DMA Curator Server                        |
|  2. Review dma-env-summary.md for a human-readable overview                 |
|                                                                             |
+============================================================================+
```

**Two archives are created** when anonymization is enabled:
- **Original** (`*.tar.gz`) — untouched data, keep for your records
- **Masked** (`*_masked.tar.gz`) — anonymized, safe to share and upload

---

## Splunk Enterprise (Bash)

Script: `dma-splunk-export.sh`

The Enterprise script follows a similar flow but includes additional steps for detecting the local Splunk installation.

### Step 1: Launch and Welcome Screen

```
+============================================================================+
|                                                                             |
|  DYNATRACE MIGRATION ASSISTANT                                              |
|                                                                             |
|  SPLUNK ENTERPRISE EXPORT SCRIPT                                            |
|                                                                             |
|  Complete Data Collection for Migration to Dynatrace Gen3                   |
|  Version 4.4.0                                                              |
|                                                                             |
+============================================================================+

  Documentation: See README-SPLUNK-ENTERPRISE.md for prerequisites

Ready to begin? (Y/n):
```

### Step 2: Pre-Flight Checklist

Similar to Cloud, but checks for local Splunk access:

```
  SHELL ACCESS:
    [ ]  SSH access to Splunk server (or running locally)
    [ ]  User with read access to $SPLUNK_HOME directory
    [ ]  Root/sudo access (may be needed for some configs)

  Quick System Check:
    + bash: 4.4.20(1)-release (4.0+ required)
    + curl: 7.88.1
    + Python: Python 3.9.16 (Splunk bundled)
    + tar: available
    + SPLUNK_HOME: /opt/splunk
```

### Step 3: SPLUNK_HOME Detection

```
+---------------------------------------------------------------------------+
| STEP 1: DETECTING SPLUNK INSTALLATION                                     |
+---------------------------------------------------------------------------+

  Searching for Splunk installation...
+ Found SPLUNK_HOME: /opt/splunk

  Splunk Version: 9.1.2
  Splunk Build:   abc123def
  Server Name:    splunk-sh01
  Server Role:    search_head

  Is this the correct Splunk installation? (Y/n): Y
```

**Action**: Confirm the detected installation. The script searches common paths (`/opt/splunk`, `/opt/splunkforwarder`, etc.).

### Step 4: Environment Detection

```
+---------------------------------------------------------------------------+
| STEP 2: DETECTING ENVIRONMENT                                             |
+---------------------------------------------------------------------------+

  Analyzing Splunk environment...

  Detected Configuration:
  +----------------------------------------------------------------------+
  |  Deployment Type:     Distributed (Search Head)                       |
  |  Search Head Cluster: Yes (Captain)                                   |
  |  Indexer Cluster:     Yes (connected)                                 |
  |  Deployment Server:   No                                              |
  |  License Master:      Connected                                       |
  +----------------------------------------------------------------------+

  Apps Found: 24 apps in $SPLUNK_HOME/etc/apps/
  Users:      15 users configured

  Is the detected environment correct? (Y/n): Y
```

**Action**: Confirm the environment detection.

### Step 5: Data Categories

```
+---------------------------------------------------------------------------+
| STEP 4: DATA CATEGORIES                                                   |
+---------------------------------------------------------------------------+

Select data categories to collect:

  [+] 1. Configuration Files (props, transforms, indexes, inputs)
  [+] 2. Dashboards (Classic XML + Dashboard Studio JSON)
  [+] 3. Alerts & Saved Searches (savedsearches.conf)
  [ ] 4. Users, Roles & Groups (RBAC data - NO passwords)
  [ ] 5. Usage Analytics (search frequency, dashboard views)
  [+] 6. Index & Data Statistics
  [ ] 7. Lookup Tables (.csv files)
  [ ] 8. Audit Log Sample (last 10,000 entries)
  [ ] 9. Anonymize Sensitive Data (emails, hostnames, IPs)

  Privacy: Passwords are NEVER collected. Secrets in .conf files are auto-redacted.

Enter numbers to toggle (e.g., 4,5,9 to add RBAC, usage, and anonymization)
Or press Enter to accept defaults [1-3,6]:
```

**Action**: Press Enter to accept defaults, or enter numbers to toggle. RBAC (4) and Usage (5) are off by default.

### Step 6: Authentication

```
+---------------------------------------------------------------------------+
| STEP 5: SPLUNK AUTHENTICATION                                             |
+---------------------------------------------------------------------------+

  WHY WE NEED THIS:
  Some data requires accessing Splunk's REST API, including:
    - Dashboard Studio dashboards (stored in KV Store)
    - User and role information
    - Usage analytics from internal indexes

  Choose authentication method:
    1) API Token (recommended for automation)
    2) Username/Password

  Select option [2]: 2

Splunk admin username [admin]: admin
Splunk admin password: ************

  Testing authentication...
+ Authentication successful

  Checking account capabilities...
+ admin_all_objects: granted
+ search: granted
```

**Action**: Enter Splunk admin credentials. Token auth (`--token`) is recommended for non-interactive/automated runs.

### Step 7: Data Collection Progress

```
+---------------------------------------------------------------------------+
| COLLECTING DATA                                                           |
+---------------------------------------------------------------------------+

  [1/8] Collecting system information...
+ Server info collected
+ License info collected
+ Installed apps list collected

  [2/8] Collecting configuration files...
+ apps/search/local/props.conf
+ apps/security_essentials/local/savedsearches.conf
  [========================================] 100% (127 files)

  [3/8] Collecting dashboards...
+ apps/search/default/data/ui/views/ (12 dashboards)
+ apps/security_essentials/default/data/ui/views/ (28 dashboards)
+ Dashboard Studio: 15 dashboards from KV Store

  [4/8] Collecting alerts and saved searches...
+ Collected 156 saved searches
+ Identified 47 alerts (alert.track = 1)

  [5/8] Collecting users and roles...
+ 15 users collected (passwords NOT collected)
+ 8 roles collected with capabilities

  [6/8] Collecting usage analytics...
-> Running: Dashboard views (last 7 days)...
+ Dashboard usage collected
-> Running: Most active users...
+ User activity collected

  [7/8] Collecting index statistics...
+ 23 indexes analyzed

  [8/8] Generating manifest and summary...
+ manifest.json created
+ dma-env-summary.md created
```

### Step 8: Export Complete

```
+============================================================================+
|                         EXPORT COMPLETE!                                    |
+============================================================================+
|                                                                             |
|  Export Archive:                                                            |
|    dma_export_splunk-sh01_20260402_152347.tar.gz                            |
|                                                                             |
|  Summary:                                                                   |
|    Dashboards:        55 (40 Classic + 15 Studio)                           |
|    Alerts:            47                                                    |
|    Saved Searches:    156                                                   |
|    Users:             15                                                    |
|    Apps:              24                                                    |
|    Indexes:           23                                                    |
|    Config Files:      127                                                   |
|                                                                             |
|  Duration: 7 minutes 12 seconds                                             |
|  Archive Size: 8.7 MB                                                       |
|                                                                             |
|  NEXT STEPS:                                                                |
|                                                                             |
|  1. Copy the export to your workstation:                                    |
|     scp splunk-sh01:/tmp/dma_export_*.tar.gz ./                             |
|                                                                             |
|  2. Upload to DMA Curator Server for migration planning                     |
|                                                                             |
+============================================================================+
```

---

## PowerShell Cloud Script

The PowerShell script (`dma-splunk-cloud-export.ps1`) follows the same interactive flow as the Bash Cloud script. The prompts and console output are visually identical. The only differences are:

- **Parameter syntax**: `-Stack` instead of `--stack`, `-Token` instead of `--token`, etc.
- **Execution**: `.\dma-splunk-cloud-export.ps1` instead of `./dma-splunk-cloud-export_beta.sh`
- **Secure input**: Password entry uses `Read-Host -AsSecureString` (Windows native secure prompt)
- **No external dependencies**: Does not require Python, curl, or jq

To skip all prompts, provide parameters on the command line:

```powershell
.\dma-splunk-cloud-export.ps1 -Stack "acme-corp.splunkcloud.com" -Token $TOKEN -Usage -Rbac
```

---

## If Something Goes Wrong

If errors occur during collection, you'll see a warning at the end:

```
+============================================================================+
|  EXPORT COMPLETED WITH 3 ERRORS                                            |
+============================================================================+
|                                                                             |
|  Some data could not be collected. See details below:                       |
|                                                                             |
|  Errors:                                                                    |
|    - HTTP 403: Access denied to /services/data/lookup-table-files           |
|    - Search timeout: Usage analytics query exceeded timeout                 |
|    - HTTP 429: Rate limited - some data may be incomplete                   |
|                                                                             |
|  A troubleshooting report has been generated:                               |
|    TROUBLESHOOTING.md                                                       |
|                                                                             |
+============================================================================+
```

The export archive is still created with whatever data was collected. Review `TROUBLESHOOTING.md` inside the archive for specific remediation steps. Common fixes:

- **403 errors**: User lacks required capabilities (see [README.md](../README.md#3-prerequisites-permissions-connectivity))
- **Search timeouts**: Use `--analytics-period 7d` to reduce the time window, or `--skip-internal` if `_internal` is restricted
- **429 rate limits**: The script auto-retries with exponential backoff; usually no action needed
