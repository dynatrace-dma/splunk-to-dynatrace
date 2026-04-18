# Interactive Mode Walkthrough

**Applies to**: All DMA Export Scripts v4.6.2

This document shows exactly what you will see when running each script in interactive mode. When all required parameters are provided on the command line, the scripts run in **non-interactive mode** and skip all prompts.

**Scripts covered:**

| Script | Platform | Use Case |
|--------|----------|----------|
| `dma-splunk-cloud-export.sh` | Bash (macOS/Linux) | Splunk Cloud |
| `dma-splunk-export.sh` | Bash (Linux) | Splunk Enterprise (on-prem) |
| `dma-splunk-cloud-export.ps1` | PowerShell (Windows) | Splunk Cloud |

---

## Switching Between Interactive and Non-Interactive Mode

Interactive mode is the default when you run any script without providing the minimum required parameters. To skip all prompts, supply the required flags on the command line.

### Non-Interactive Examples

**Cloud Bash** -- provide `--stack` and either `--token` or `-u`/`-p`:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "eyJraWQ..." \
  --usage --rbac \
  --analytics-period 30d
```

**Enterprise Bash** -- provide `--token` or `-u`/`-p` (SPLUNK_HOME is auto-detected):

```bash
./dma-splunk-export.sh \
  --token "eyJraWQ..." \
  --usage --rbac \
  --analytics-period 30d
```

**PowerShell** -- provide `-Stack` and either `-Token` or `-User`/`-Password`:

```powershell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token "eyJraWQ..." `
  -Usage -Rbac `
  -AnalyticsPeriod 30d
```

If you provide only partial parameters (e.g., `-Stack` without authentication), the script prints a warning and falls back to interactive mode:

```
WARNING: -Stack provided but no authentication
  For non-interactive mode, also provide:
    -Token YOUR_TOKEN
    OR -User USER -Password PASS

  Falling back to interactive mode...
```

---

## Splunk Cloud (Bash)

Script: `dma-splunk-cloud-export.sh`

### Step 1: Banner and Welcome

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║  DYNABRIDGE                                                                ║
║                                                                            ║
║                   SPLUNK CLOUD EXPORT SCRIPT                               ║
║                                                                            ║
║          Complete REST API-Based Data Collection for Migration              ║
║                        Version 4.6.2                                       ║
║                                                                            ║
║   Developed for Dynatrace One by Enterprise Solutions & Architecture       ║
║                  An ACE Services Division of Dynatrace                     ║
║                                                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

  WHAT THIS SCRIPT DOES

  This script collects data from your Splunk Cloud environment using
  the REST API to prepare for migration to Dynatrace Gen3 Grail.

  IMPORTANT: THIS IS FOR SPLUNK CLOUD ONLY

  If you have Splunk Enterprise (on-premises), please use:
    ./dma-splunk-export.sh

Do you want to continue? (Y/n):
```

**Action**: Press `Y` or Enter to continue.

### Step 2: Pre-Flight Checklist

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     PRE-FLIGHT CHECKLIST                                   ║
║         Please confirm you have the following before continuing            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  SPLUNK CLOUD ACCESS:                                                      ║
║    [ ]  Splunk Cloud stack URL (e.g., your-company.splunkcloud.com)        ║
║    [ ]  Splunk username with admin privileges                              ║
║    [ ]  Splunk password OR API token (sc_admin role recommended)           ║
║                                                                            ║
║  REQUIRED CAPABILITIES (for Usage Analytics):                              ║
║    [ ]  search capability                                                  ║
║    [ ]  list_settings capability                                           ║
║                                                                            ║
║  DATA PRIVACY & SECURITY:                                                  ║
║                                                                            ║
║  We do NOT collect or export:                                              ║
║    x  User passwords or password hashes                                    ║
║    x  API tokens or session keys                                           ║
║    x  Private keys or certificates                                         ║
║    x  Your actual log data (only metadata/structure)                       ║
║                                                                            ║
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

  WHY WE NEED THIS:
  We need to connect to your Splunk Cloud instance via REST API.
  This is the only way to access Splunk Cloud data - there is
  no file system or SSH access to Splunk Cloud infrastructure.

  Your Splunk Cloud stack URL looks like:
    https://your-company.splunkcloud.com

  Enter your Splunk Cloud stack URL: acme-corp.splunkcloud.com

+ Stack URL configured: https://acme-corp.splunkcloud.com:8089
```

**Action**: Enter your stack URL (with or without `https://` prefix). The script strips the protocol and port automatically.

> **Proxy prompt**: If you are behind a corporate proxy, the script asks before the connectivity test:
> ```
>   Does your environment require a proxy server to connect to Splunk Cloud? (y/N): y
>   Enter proxy URL (e.g., http://proxy.company.com:8080): http://proxy.internal:3128
> + Proxy configured: http://proxy.internal:3128
> ```
> Skip this by passing `--proxy http://proxy.internal:3128` on the command line.

### Step 4: Connectivity Test

```
-> Testing connection to https://acme-corp.splunkcloud.com:8089...
+ Connection successful
```

**If connectivity fails**, you will see a troubleshooting box:

```
  CONNECTION TROUBLESHOOTING

  Cannot reach your Splunk Cloud instance. Please check:

    1. Is the URL correct? acme-corp.splunkcloud.com
    2. Are you on VPN (if required by your company)?
    3. Is your IP address allowlisted in Splunk Cloud?
    4. Can you reach it in a browser?

  To check your public IP: curl ifconfig.me
```

The script exits on connection failure. Fix the issue and re-run.

### Step 5: Authentication

```
+---------------------------------------------------------------------------+
| STEP 2: AUTHENTICATION                                                    |
+---------------------------------------------------------------------------+

  REST API access requires authentication. You can use:

    Option 1: API Token (Recommended)
      - More secure - limited scope, can be revoked
      - Works with MFA-enabled accounts
      - Create in Splunk Cloud: Settings -> Tokens

    Option 2: Username/Password
      - Your regular Splunk Cloud login
      - May not work if MFA is enforced

  Required Permissions:
    - admin_all_objects - Access all knowledge objects
    - list_users, list_roles - Access RBAC data
    - search - Run analytics queries

  Choose authentication method:

    1) API Token (recommended)
    2) Username/Password

  Select option [1]: 1

  Enter API token: ********************************

  Testing authentication...
+ Token authentication successful (prefix: Bearer, user: admin)

  Checking user capabilities...
+ All required capabilities present
```

**Action**: Choose your auth method and enter credentials. The script automatically detects whether your token requires the `Bearer` or `Splunk` prefix.

**If authentication fails:**

```
  AUTHENTICATION FAILED

  Could not authenticate to Splunk Cloud. Please check:

    - Credentials are correct
    - API token has not expired
    - Account is not locked
    - User has required capabilities

  To create an API token:
    1. Log into Splunk Cloud web UI
    2. Click Settings (gear) -> Tokens
    3. Create new token with required permissions
```

The script exits on auth failure. Fix credentials and re-run.

### Step 6: Environment Detection

```
+---------------------------------------------------------------------------+
| STEP 3: ENVIRONMENT DETECTION                                             |
+---------------------------------------------------------------------------+

-> Detecting Splunk Cloud environment...

  +--------------------------------------------------------------------+
  | Detected Environment:                                              |
  +--------------------------------------------------------------------+
  |   Stack:      acme-corp.splunkcloud.com                            |
  |   Type:       Splunk Cloud (victoria)                              |
  |   Version:    9.2.2403.107                                         |
  |   GUID:       A1B2C3D4-E5F6-7890...                               |
  |   Apps:       24 installed                                         |
  |   Users:      15                                                   |
  +--------------------------------------------------------------------+

  Is this the correct environment? (Y/n): Y
```

**Action**: Confirm the detected environment.

### Step 7: Application Selection

```
+---------------------------------------------------------------------------+
| STEP 4: APPLICATION SELECTION                                             |
+---------------------------------------------------------------------------+

-> Retrieving app list...

  Found 24 apps. Choose export scope:

    1) Export ALL applications (recommended for complete analysis)
    2) Enter specific app names (comma-separated)
    3) Select from numbered list
    4) System apps only (minimal export)

  Select option [1]: 1

+ Will export ALL 24 applications
```

**Action**: Press `1` or Enter to export all apps. Other options:

- **Option 2**: Enter app names: `security_app, ops_monitoring, compliance`
- **Option 3**: Select by number with ranges: `1,3,5-8`
- **Option 4**: Minimal export with system apps only

### Step 8: Data Category Toggle Menu

```
+---------------------------------------------------------------------------+
| STEP 5: DATA CATEGORIES                                                   |
+---------------------------------------------------------------------------+

  Select data categories to collect:

    [+] 1. Configurations      (via REST - reconstructed from API)
    [+] 2. Dashboards          (Classic + Dashboard Studio)
    [+] 3. Alerts & Saved Searches
    [ ] 4. Users & RBAC        (global user/role data - use --rbac to enable)
    [ ] 5. Usage Analytics     (requires _audit - often blocked in Cloud)
    [+] 6. Index Statistics
    [ ] 7. Lookup Contents     (may be large)
    [+] 8. Anonymize Data      (emails->fake, hosts->fake, IPs->redacted)

  Privacy: User data includes names/roles only. Passwords are NEVER collected.
  Tips:
     - Options 4 (RBAC) and 5 (Usage) are OFF by default for faster exports
     - Option 5 requires _audit/_internal access (often blocked in Cloud)
     - Enable option 8 when sharing export with third parties

  Accept defaults? (Y/n): n

  Enter numbers to toggle (e.g., 5,7 to disable Usage and Lookups):
  Toggle: 4,5
```

**Action**: Press `Y` to accept defaults, or `n` to toggle individual categories.

**Default state**: 1 (Configs), 2 (Dashboards), 3 (Alerts), 6 (Indexes), and 8 (Anonymize) are ON. Items 4 (RBAC), 5 (Usage), and 7 (Lookups) are OFF.

You can also enable these from the command line without entering the toggle menu:
- `--rbac` enables RBAC collection
- `--usage` enables Usage Analytics
- `--lookups` enables Lookup collection

### Step 9: Analytics Period (if Usage Enabled)

This step only appears if you toggled Usage Analytics (option 5) ON.

```
  Usage Analytics Period:

    1) Last 7 days
    2) Last 30 days (recommended -- comprehensive migration planning)
    3) Last 90 days
    4) Last 365 days

  Select period [2]: 2

i Usage analytics will cover the last 30d
```

**Action**: Choose a time window. Default is 30 days. Skip this prompt by passing `--analytics-period 30d` on the command line.

> **v4.6.0 note**: Usage analytics now runs only 6 global aggregate queries plus an ownership REST call, replacing the previous per-app query loop. For 24 apps, this means 6 queries instead of 168. Typical completion time is under 2 minutes.

### Step 10: Data Collection Progress

```
+---------------------------------------------------------------------------+
| COLLECTING DATA                                                           |
+---------------------------------------------------------------------------+

  [1/8] Collecting system information...
+ Server info collected
+ Installed apps collected

  [2/8] Collecting configurations via REST API...
+ Props configuration collected
+ Transforms configuration collected
+ Indexes configuration collected

  [3/8] Collecting dashboards...
  [========================================] 100% security_app/security_overview
+ Collected 47 Classic dashboards
+ Collected 12 Dashboard Studio dashboards

  [4/8] Collecting alerts and saved searches...
+ Collected 89 saved searches (34 alerts)

  [5/8] Collecting users and roles...
+ 15 users collected (passwords NOT collected)
+ 8 roles collected with capabilities

  [6/8] Running global aggregate analytics...

    Analytics period: 30d | Dispatch: async (max 1h per query)
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

-> Running: Index volume trends (global)
+ Completed search: Index volume trends (9s)

-> Running: Alert firing history (global)
+ Completed search: Alert firing history (7s)

-> Running: Alerts inventory (global)
+ Completed search: Alerts inventory (5s)

+ Global analytics completed in 64s (6 queries total)

-> Collecting search ownership via REST...
+ Ownership data collected for 89 saved searches

  [7/8] Collecting index statistics...
+ Index stats collected for 15 indexes

  [8/8] Creating archive...
+ Original archive: dma_cloud_export_acme-corp_20260402_143052.tar.gz
+ Masked archive:   dma_cloud_export_acme-corp_20260402_143052_masked.tar.gz
```

**What's happening**: Analytics searches use async dispatch -- each query is dispatched immediately and polled with adaptive intervals (5s to 30s). In v4.6.0, the script runs 6 global aggregate queries instead of per-app queries, dramatically reducing collection time.

### Step 11: Export Complete

```
+============================================================================+
|                         EXPORT COMPLETE!                                   |
+============================================================================+
|                                                                            |
|  Export Archives:                                                          |
|    dma_cloud_export_acme-corp_20260402_143052.tar.gz          (original)   |
|    dma_cloud_export_acme-corp_20260402_143052_masked.tar.gz   (anonymized) |
|                                                                            |
|  Summary:                                                                  |
|    Dashboards:        59 (47 Classic + 12 Studio)                          |
|    Alerts:            34                                                   |
|    Saved Searches:    89                                                   |
|    Users:             15                                                   |
|    Apps:              24                                                   |
|    Indexes:           15                                                   |
|                                                                            |
|  Duration: 2 minutes 47 seconds                                            |
|  Archive Size: 2.3 MB                                                      |
|                                                                            |
|  NEXT STEPS:                                                               |
|                                                                            |
|  1. Upload the _masked archive to DMA Curator Server                       |
|  2. Review dma-env-summary.md for a human-readable overview                |
|                                                                            |
+============================================================================+
```

**Two archives are created** when anonymization is enabled:
- **Original** (`*.tar.gz`) -- untouched data, keep for your records
- **Masked** (`*_masked.tar.gz`) -- anonymized, safe to share and upload to DMA

---

## Splunk Enterprise (Bash)

Script: `dma-splunk-export.sh`

The Enterprise script follows a similar flow but includes additional steps for detecting the local Splunk installation and filesystem-based configuration collection.

### Step 1: Banner and Welcome

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║  DYNABRIDGE                                                                ║
║                                                                            ║
║                SPLUNK ENTERPRISE EXPORT SCRIPT                             ║
║                                                                            ║
║          Complete Data Collection for Migration to Dynatrace Gen3          ║
║                        Version 4.6.2                                       ║
║                                                                            ║
║   Developed for Dynatrace One by Enterprise Solutions & Architecture       ║
║                  An ACE Services Division of Dynatrace                     ║
║                                                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

  WHAT THIS SCRIPT DOES

  This script collects data from your Splunk Enterprise environment
  to prepare for migration to Dynatrace Gen3 Grail.

  IMPORTANT: THIS IS FOR SPLUNK ENTERPRISE ONLY

  If you have Splunk Cloud (Classic or Victoria Experience), please use:
    ./dma-splunk-cloud-export.sh

  This script reads configuration files directly from $SPLUNK_HOME

  Documentation: See README-SPLUNK-ENTERPRISE.md for prerequisites

Ready to begin? (Y/n):
```

**Action**: Press `Y` or Enter to continue.

### Step 2: Pre-Flight Checklist

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     PRE-FLIGHT CHECKLIST                                   ║
║         Please confirm you have the following before continuing            ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                            ║
║  SHELL ACCESS:                                                             ║
║    [ ]  SSH access to Splunk server (or running locally on Splunk server)  ║
║    [ ]  User with read access to $SPLUNK_HOME directory                    ║
║    [ ]  Root/sudo access (may be needed for some configs)                  ║
║                                                                            ║
║  SPLUNK REST API ACCESS (Optional - for Usage Analytics):                  ║
║    [ ]  Splunk username with admin privileges                              ║
║    [ ]  Splunk password (for REST API searches)                            ║
║    [ ]  Access to _audit and _internal indexes                             ║
║                                                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Quick System Check:
    + bash: 4.4.20(1)-release (4.0+ required)
    + curl: 7.88.1
    + Python: Python 3.9.16 (Splunk bundled)
    + tar: available
    + gzip: available
    + SPLUNK_HOME: /opt/splunk

Ready to proceed? (Y/n):
```

### Step 3: SPLUNK_HOME Detection

```
  STEP 1: LOCATE SPLUNK INSTALLATION

  WHY WE NEED THIS:
  We need to know where Splunk is installed to read configuration
  files and access the Splunk CLI tools.

-> Searching for Splunk installation...
+ Found Splunk installation: /opt/splunk
```

**Action**: If the script finds Splunk, it reports the path automatically. If not, you are prompted:

```
! Could not automatically detect Splunk installation

  Please enter the path to your Splunk installation.
  This is typically /opt/splunk or /opt/splunkforwarder

  Enter SPLUNK_HOME path [/opt/splunk]: /opt/splunk

+ Valid Splunk installation found: /opt/splunk
```

The script searches common paths: `/opt/splunk`, `/opt/splunkforwarder`, `/usr/local/splunk`, `$HOME/splunk`, and the `$SPLUNK_HOME` environment variable.

### Step 4: Environment Detection

```
+---------------------------------------------------------------------------+
| STEP 2: DETECTING ENVIRONMENT                                             |
+---------------------------------------------------------------------------+

-> Analyzing Splunk environment...

  +----------------------------------------------------------------------+
  | Detected Configuration:                                              |
  +----------------------------------------------------------------------+
  |  Splunk Version:    9.1.2                                            |
  |  Server Name:       splunk-sh01                                      |
  |  Server Role:       search_head                                      |
  |  Deployment Type:   Distributed (Search Head)                        |
  |  Search Head Cluster: Yes (Captain)                                  |
  |  Indexer Cluster:   Yes (connected)                                  |
  +----------------------------------------------------------------------+

  Apps Found: 24 apps in $SPLUNK_HOME/etc/apps/
  Users:      15 users configured

  Is the detected environment correct? (Y/n): Y
```

**Action**: Confirm the environment detection. If you are on an SHC member (not the captain), the script warns and recommends running on the captain instead.

**Universal Forwarder warning**: If SPLUNK_HOME points to a Universal Forwarder, you will see:

```
  LIMITED EXPORT AVAILABLE

  This is a Universal Forwarder installation.

  Universal Forwarders have limited data available:
    + inputs.conf (data sources being collected)
    + outputs.conf (forwarding destinations)
    + props.conf (local parsing rules, if any)

    x Dashboards (UF has no search capability)
    x Alerts (UF cannot run searches)
    x Users/RBAC (minimal authentication)
    x Usage analytics (no search history)

  RECOMMENDATION: For full export, run this script on your
  Search Head instead.

Continue with limited forwarder export? (Y/n):
```

### Step 5: Application Selection

```
  STEP 3: SELECT APPLICATIONS TO EXPORT

-> Discovering installed applications...
+ Found 24 applications

  Discovered Applications:
  ------------------------------------------------------------------------
  #    App Name                       Dashboards       Alerts
  ------------------------------------------------------------------------
  1    search                                 3            2
  2    security_essentials                   28           15
  3    ops_monitoring                        12            8
  4    compliance_app                         7            5
  ...
  ------------------------------------------------------------------------

  How would you like to select applications?

    1. Export ALL applications (Recommended for full migration)
       -> Includes all 24 apps with their complete configurations
       -> Best for comprehensive migration assessment

    2. Enter specific app names (comma-separated)
       -> Example: security_app, ops_monitoring, compliance

    3. Select from numbered list
       -> Enter numbers like: 1,2,5,7-10

    4. Export system configurations only (no apps)
       -> Only collects indexes, inputs, system-level configs

  Enter your choice [1]: 1

+ Will export ALL 24 applications
```

**Action**: Press Enter or `1` to export all. The Enterprise script shows a table of discovered apps with dashboard and alert counts.

### Step 6: Data Categories

```
  STEP 4: SELECT DATA CATEGORIES TO COLLECT

  Select data categories to collect:

    [+] 1. Configuration Files (props, transforms, indexes, inputs)
          -> Required for understanding data pipeline

    [+] 2. Dashboards (Classic XML + Dashboard Studio JSON)
          -> Visual content for conversion to Dynatrace apps

    [+] 3. Alerts & Saved Searches (savedsearches.conf)
          -> Critical for operational continuity

    [ ] 4. Users, Roles & Groups (RBAC data - NO passwords)
          -> OFF by default - enable with toggle or --rbac flag

    [ ] 5. Usage Analytics (search frequency, dashboard views)
          -> OFF by default - enable with toggle or --usage flag

    [+] 6. Index & Data Statistics
          -> Volume metrics for capacity planning

    [ ] 7. Lookup Tables (.csv files)
          -> May contain sensitive data - review before including

    [ ] 8. Audit Log Sample (last 10,000 entries)
          -> May contain sensitive query content

    [+] 9. Anonymize Sensitive Data (emails, hostnames, IPs)
          -> ON by default - recommended for security

  Privacy: Passwords are NEVER collected. Secrets in .conf files are auto-redacted.

  Enter numbers to toggle (e.g., 7,8 to add lookups and audit)
  Or press Enter to accept defaults [1-3,6,9] (RBAC/Usage OFF):

  Toggle categories: 4,5
i Users/RBAC: ON
i Usage Analytics: ON
```

**Action**: Press Enter to accept defaults, or enter numbers to toggle. Note that the Enterprise script has 9 categories (the Cloud scripts have 8, with no separate Audit Log option).

### Step 7: Authentication

```
  STEP 5: SPLUNK AUTHENTICATION

  WHY WE NEED THIS:
  Some data requires accessing Splunk's REST API, including:
    - Dashboard Studio dashboards (stored in KV Store)
    - User and role information
    - Usage analytics from internal indexes
    - Distributed environment topology

  Splunk admin username [admin]: admin
  Splunk admin password: ************

-> Testing authentication...
+ Authentication successful

-> Checking account capabilities...
+ Capability: admin_all_objects
+ Capability: list_users
+ Capability: list_roles
```

**Action**: Enter Splunk admin credentials. For automation, pass `--token TOKEN` on the command line to skip this prompt entirely.

**If authentication fails:**

```
x Authentication failed (invalid credentials)

  Would you like to try again? (Y/n): Y
```

Or if the REST API is unreachable:

```
x Could not connect to Splunk REST API (connection refused or timeout)

  This could mean:
    - Splunk is not running
    - Management port is different from 8089
    - Firewall blocking connections

  Continue without REST API access? (y/N): y
! Some data will not be collected (Dashboard Studio, users, usage analytics)
```

### Step 8: Analytics Period (if Usage Enabled)

```
  STEP 6: USAGE ANALYTICS TIME PERIOD

  WHY WE ASK:
  Usage analytics help identify which dashboards, alerts, and
  searches are actively used. A longer period gives more accurate
  data but takes longer to collect.

  RECOMMENDATION:
  30 days provides a good balance of accuracy and speed.

  Select usage analytics collection period:

    1. Last 7 days   (fastest, limited data)
    2. Last 30 days  (recommended)
    3. Last 90 days  (more comprehensive)
    4. Last 365 days (full year, slowest)
    5. Skip usage analytics

  Enter choice [2]: 2

i Will collect 30 days of usage data
```

**Action**: Choose a time window. Default is 30 days. Skip this prompt with `--analytics-period 30d`.

> **v4.6.0 note**: Usage analytics now uses 6 global aggregate queries plus ownership REST calls, the same optimization as the Cloud script.

### Step 9: Data Collection Progress

```
+---------------------------------------------------------------------------+
| COLLECTING DATA                                                           |
+---------------------------------------------------------------------------+

  [1/9] Collecting system information...
+ Server info collected
+ License info collected
+ Installed apps list collected

  [2/9] Collecting configuration files...
+ apps/search/local/props.conf
+ apps/security_essentials/local/savedsearches.conf
  [========================================] 100% (127 files)

  [3/9] Collecting dashboards...
+ apps/search/default/data/ui/views/ (12 dashboards)
+ apps/security_essentials/default/data/ui/views/ (28 dashboards)
+ Dashboard Studio: 15 dashboards from KV Store

  [4/9] Collecting alerts and saved searches...
+ Collected 156 saved searches
+ Identified 47 alerts (alert.track = 1)

  [5/9] Collecting users and roles...
+ 15 users collected (passwords NOT collected)
+ 8 roles collected with capabilities

  [6/9] Running global aggregate analytics...

    Analytics period: 30d | Dispatch: async (max 1h per query)

-> Running: Dashboard views (global, provenance-based)
+ Completed search: Dashboard views (23s)

-> Running: User activity (global)
+ Completed search: User activity (8s)

-> Running: Search type breakdown (global)
+ Completed search: Search type breakdown (12s)

  ... (6 queries total)

+ Global analytics completed in 67s (6 queries total)

  [7/9] Collecting index statistics...
+ 23 indexes analyzed

  [8/9] Collecting lookup tables...
+ 12 lookup CSV files collected (1.2 MB)

  [9/9] Generating manifest and summary...
+ manifest.json created
+ dma-env-summary.md created
```

### Step 10: Export Complete

```
+============================================================================+
|                         EXPORT COMPLETE!                                   |
+============================================================================+
|                                                                            |
|  Export Archive:                                                           |
|    dma_export_splunk-sh01_20260402_152347.tar.gz                           |
|                                                                            |
|  Summary:                                                                  |
|    Dashboards:        55 (40 Classic + 15 Studio)                          |
|    Alerts:            47                                                   |
|    Saved Searches:    156                                                  |
|    Users:             15                                                   |
|    Apps:              24                                                   |
|    Indexes:           23                                                   |
|    Config Files:      127                                                  |
|                                                                            |
|  Duration: 5 minutes 12 seconds                                            |
|  Archive Size: 8.7 MB                                                      |
|                                                                            |
|  NEXT STEPS:                                                               |
|                                                                            |
|  1. Copy the export to your workstation:                                   |
|     scp splunk-sh01:/tmp/dma_export_*.tar.gz ./                            |
|                                                                            |
|  2. Upload to DMA Curator Server for migration planning                    |
|                                                                            |
+============================================================================+
```

---

## PowerShell Cloud Script

Script: `dma-splunk-cloud-export.ps1`

The PowerShell script follows the same interactive flow as the Bash Cloud script with identical steps:

1. **Banner** -- same ASCII art and version display (shows "Version 4.6.2 (PowerShell)")
2. **Pre-Flight Checklist** -- same checklist with system checks
3. **Stack URL** -- same prompt for Splunk Cloud URL
4. **Proxy** -- same optional proxy prompt
5. **Authentication** -- same token/userpass choice (password uses `Read-Host -AsSecureString`)
6. **Environment Detection** -- same environment confirmation
7. **Application Selection** -- same 4-option selection menu
8. **Data Categories** -- same 8-item toggle menu (Configs, Dashboards, Alerts, RBAC, Usage, Indexes, Lookups, Anonymize)
9. **Analytics Period** -- same 4-option period selector (if Usage enabled)
10. **Collection** -- same step-by-step progress with resume support

### Key Differences from the Bash Cloud Script

| Feature | Bash | PowerShell |
|---------|------|------------|
| Parameter prefix | `--stack`, `--token` | `-Stack`, `-Token` |
| Execution | `./dma-splunk-cloud-export.sh` | `.\dma-splunk-cloud-export.ps1` |
| Secure input | masked `read -s` | `Read-Host -AsSecureString` |
| External deps | Python 3, curl, jq (optional) | None (native .NET HTTP) |
| Resume support | `--resume-collect FILE` | `-ResumeCollect FILE` |
| Test mode | `--test-access` | `-TestAccess` |
| Re-mask mode | `--remask FILE` | `-Remask FILE` |

### Non-Interactive Example (PowerShell)

```powershell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token "eyJraWQ..." `
  -Usage -Rbac `
  -AnalyticsPeriod 30d `
  -Apps "security_app, ops_monitoring"
```

### Interactive Mode Flow (PowerShell)

The interactive steps are identical to Bash Cloud. Here is the category toggle menu as rendered by PowerShell:

```
+---------------------------------------------------------------------------+
| STEP 5: DATA CATEGORIES                                                   |
+---------------------------------------------------------------------------+

  Select data categories to collect:

    [+] 1. Configurations      (via REST - reconstructed from API)
    [+] 2. Dashboards          (Classic + Dashboard Studio)
    [+] 3. Alerts & Saved Searches
    [ ] 4. Users & RBAC        (global user/role data - use -Rbac to enable)
    [ ] 5. Usage Analytics     (requires _audit - often blocked in Cloud)
    [+] 6. Index Statistics
    [ ] 7. Lookup Contents     (may be large)
    [+] 8. Anonymize Data      (emails->fake, hosts->fake, IPs->redacted)

  Privacy: User data includes names/roles only. Passwords are NEVER collected.
  Tips:
     - Options 4 (RBAC) and 5 (Usage) are OFF by default for faster exports
     - Option 5 requires _audit/_internal access (often blocked in Cloud)
     - Enable option 8 when sharing export with third parties

  Accept defaults? (Y/n):
```

### Collection Progress with Resume (PowerShell)

If resuming a previously interrupted export with `-ResumeCollect`, already-collected phases are skipped:

```
+---------------------------------------------------------------------------+
| COLLECTING DATA                                                           |
+---------------------------------------------------------------------------+

  [1/9] System information... SKIP (already collected)
  [2/9] Configurations... SKIP (already collected)
  [3/9] Collecting dashboards...
+ Collected 47 Classic, 12 Studio dashboards
  [4/9] Collecting alerts and saved searches...
+ Collected 89 saved searches
  [5/9] Collecting users and roles...
+ 15 users collected
  [6/9] Collecting knowledge objects...
+ Macros, eventtypes, tags collected
  [7/9] Running global aggregate analytics...
+ Global analytics completed in 58s (6 queries total)
  [8/9] Running global usage analytics...
+ Usage analytics completed
  [9/9] Collecting index information...
+ Index stats collected

i Resume summary: 7 collected, 2 skipped (already had data)
```

---

## Data Category Reference

All three scripts share the same core category set. The table below shows default states and how to enable/disable each from the command line.

| # | Category | Default | Cloud Bash Flag | Enterprise Bash Flag | PowerShell Flag |
|---|----------|---------|-----------------|---------------------|-----------------|
| 1 | Configurations | ON | (always on) | (always on) | (always on) |
| 2 | Dashboards | ON | (always on) | (always on) | (always on) |
| 3 | Alerts & Saved Searches | ON | (always on) | (always on) | (always on) |
| 4 | Users & RBAC | OFF | `--rbac` | `--rbac` | `-Rbac` |
| 5 | Usage Analytics | OFF | `--usage` | `--usage` | `-Usage` |
| 6 | Index Statistics | ON | (always on) | (always on) | (always on) |
| 7 | Lookup Contents | OFF | `--lookups` | `--lookups` | (toggle in menu) |
| 8 | Anonymize Data | ON | `--skip-anonymization` to disable | (toggle in menu) | `-SkipAnonymization` |
| -- | Audit Log Sample | OFF | N/A | (toggle in menu, category 8) | N/A |
| -- | Anonymize (Enterprise) | ON | N/A | (toggle in menu, category 9) | N/A |

> **Note**: The Enterprise script has 9 categories (adds Audit Log Sample as #8 and Anonymize as #9). The Cloud scripts have 8 categories with Anonymize as #8.

---

## If Something Goes Wrong

### Errors During Collection

If errors occur during collection, you will see a warning at the end:

```
+============================================================================+
|  EXPORT COMPLETED WITH 3 ERRORS                                           |
+============================================================================+
|                                                                            |
|  Some data could not be collected. See details below:                      |
|                                                                            |
|  Errors:                                                                   |
|    - HTTP 403: Access denied to /services/data/lookup-table-files          |
|    - Search timeout: Usage analytics query exceeded timeout                |
|    - HTTP 429: Rate limited - some data may be incomplete                  |
|                                                                            |
|  A troubleshooting report has been generated:                              |
|    TROUBLESHOOTING.md                                                      |
|                                                                            |
+============================================================================+
```

The export archive is still created with whatever data was collected. Review `TROUBLESHOOTING.md` inside the archive for specific remediation steps.

### Common Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| HTTP 403 | Missing capabilities | Grant `admin_all_objects`, `list_users`, `list_roles` to the user/token |
| Search timeout | Analytics query too broad | Use `--analytics-period 7d` to reduce the time window |
| HTTP 429 | API rate limiting | Script auto-retries with exponential backoff; usually no action needed |
| Connection refused | Splunk not running or wrong port | Verify Splunk is running and management port is 8089 |
| Token auth failed | Expired or invalid token | Create a new token in Splunk: Settings -> Tokens |
| `_audit` access denied | Cloud restriction | Usage analytics may not work in all Cloud environments; use `--skip-internal` |

### Resuming a Failed Export

If collection was interrupted (network drop, timeout, etc.), you can resume from where it stopped:

```bash
# Bash
./dma-splunk-cloud-export.sh --resume-collect dma_cloud_export_acme-corp_20260402_143052.tar.gz \
  --stack acme-corp.splunkcloud.com --token "$TOKEN"

# PowerShell
.\dma-splunk-cloud-export.ps1 -ResumeCollect dma_cloud_export_acme-corp_20260402_143052.tar.gz `
  -Stack acme-corp.splunkcloud.com -Token $TOKEN
```

The script extracts the previous archive, checks which phases completed, and re-runs only the missing ones.

### Pre-Flight Access Test

Before running a full export, you can verify API access with the test-access mode:

```bash
# Bash
./dma-splunk-cloud-export.sh --test-access --stack acme-corp.splunkcloud.com --token "$TOKEN"

# PowerShell
.\dma-splunk-cloud-export.ps1 -TestAccess -Stack acme-corp.splunkcloud.com -Token $TOKEN
```

This runs a quick PASS/FAIL/WARN check across all collection categories without exporting any data.
