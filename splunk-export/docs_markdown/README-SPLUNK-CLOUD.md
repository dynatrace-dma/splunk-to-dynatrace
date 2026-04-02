# DMA Splunk Cloud Export Script
## Prerequisites Guide for Splunk Cloud (Classic & Victoria Experience)

**Version**: 4.5.8
**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Cloud Export Specification](SPLUNK-CLOUD-EXPORT-SPECIFICATION.md)

### What's New in v4.5.8

#### Token Authentication Fixes
- **Auto-detect token prefix** (Bearer vs Splunk) via probe loop — tokens created via Splunk's Settings > Tokens require the `Splunk` prefix, not `Bearer`
- `Invoke-SplunkApi` / `api_call` now uses the discovered auth header instead of hardcoding Bearer
- Clear error messages when the token lacks permissions for `server_info` or app listing (previously showed cryptic "No applications found")

#### Async Search Dispatch (replaces blocking mode)
- `exec_mode=normal` returns the SID immediately; the script polls `dispatchState` with adaptive intervals (5s, increasing to 30s cap)
- Maximum wait per query: 1 hour (up from 300s hard timeout in blocking mode)
- Auto-cancels timed-out jobs to free Splunk search quota
- `Invoke-AnalyticsSearchBlocking` preserved for fast `| rest` queries

#### Global Aggregate Analytics (replaces per-app loops)
- 6 global queries replace N x 7 per-app queries (for 90 apps: 630 jobs reduced to 6)
- Dashboard views use `provenance` field — `search_type=dashboard` was NOT a native `_audit` field and produced unreliable results
- View session de-duplication counts page loads (30s window per user), not individual panel searches
- Search type breakdown derived from `provenance`/`search_id` via `eval case()`

#### New CLI Flags
| Flag (Bash / PowerShell) | Description |
|--------------------------|-------------|
| `--test-access` / `-TestAccess` | Pre-flight check: test API access across 9 categories, then exit (no export) |
| `--remask FILE` / `-Remask FILE` | Re-anonymize an existing archive without connecting to Splunk |
| `--analytics-period N` / `-AnalyticsPeriod N` | Analytics time window (default: 7d; also: 30d, 90d) |
| `--skip-internal` / `-SkipInternal` | Skip `_audit`/`_internal` index searches for restricted accounts |

#### Expanded RBAC Collection
Now collects capabilities, SAML config, SAML groups, LDAP groups, LDAP config. All new endpoints handle 404 gracefully with placeholder JSON when SAML/LDAP is not configured.

#### Progressive Analytics Checkpointing
Each of the 6 global analytics queries saves a checkpoint on completion. If an export is interrupted and resumed, only incomplete queries are re-run.

#### Default Changes
- `USAGE_PERIOD` changed from 30d to **7d** (4x less `_audit` data to scan)

### Previous v4.3.0 Changes

- **Resume Collection** (`--resume-collect`): Resume interrupted exports from `.tar.gz` archive
- **12-Hour Max Runtime**: `MAX_TOTAL_TIME=43200` (up from 4 hours)
- **PowerShell Edition**: `dma-splunk-cloud-export.ps1` with zero external dependencies
- **Proxy Support** (`--proxy` / `-Proxy`): Route all connections through corporate proxy

### Previous v4.2.4 Changes

- **Two-Archive Anonymization**: Original + `_masked` copy for safe sharing
- **RBAC/Usage OFF by default**: Use `--rbac` / `--usage` to enable
- **Faster defaults**: Batch size 250, API delay 50ms

### Previous v4.2.0 Changes

- **App-Centric Dashboard Structure (v2)**: `{AppName}/dashboards/classic/` and `{AppName}/dashboards/studio/`
- **Manifest Schema v4.0**: `archive_structure_version: "v2"`

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Quick Start

```bash
# This script runs from YOUR machine (not on Splunk Cloud)
# You need network access to your Splunk Cloud instance

./dma-splunk-cloud-export.sh
```

### Quick Start (PowerShell - Windows)

```powershell
# This script runs from YOUR Windows machine (not on Splunk Cloud)
.\dma-splunk-cloud-export.ps1

# Non-interactive with token
.\dma-splunk-cloud-export.ps1 -Stack "acme-corp.splunkcloud.com" -Token "your-token"
```

---

## How This Differs from Enterprise Export

| Aspect | Enterprise Script | Cloud Script (Bash) | Cloud Script (PowerShell) |
|--------|------------------|-------------------------|---------------------------|
| **Where you run it** | ON the Splunk server | ANYWHERE (your laptop, jump host) | ANYWHERE (Windows machine) |
| **Access method** | SSH + File system | REST API only | REST API only |
| **What you need** | SSH access + splunk user | Network access + API credentials | Network access + API credentials |
| **File reading** | Reads props.conf, etc. | Reconstructs from REST API | Reconstructs from REST API |
| **Dependencies** | bash, tar | bash, curl, Python 3 | PowerShell 5.1+ only (zero external deps) |

---

## Prerequisites Checklist

### 1. Network Access

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         NETWORK REQUIREMENTS                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Your machine must be able to reach:                                     │
│                                                                          │
│    https://<your-stack>.splunkcloud.com:8089                            │
│                                                                          │
│  This is the Splunk Cloud REST API management port.                     │
│                                                                          │
│  TEST IT:                                                                │
│  $ curl -I https://acme-corp.splunkcloud.com:8089/services/server/info  │
│                                                                          │
│  If this fails, check:                                                   │
│  • Corporate firewall rules                                              │
│  • VPN requirements                                                      │
│  • Splunk Cloud IP allowlist settings                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2. Splunk Cloud Credentials

You need ONE of the following:

#### Option A: API Token (Recommended)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CREATING AN API TOKEN                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Log into Splunk Cloud web UI                                        │
│     https://your-stack.splunkcloud.com                                  │
│                                                                          │
│  2. Click Settings (gear icon) → Tokens                                 │
│                                                                          │
│  3. Click "New Token"                                                   │
│                                                                          │
│  4. Configure the token:                                                │
│     • Name: DMA Export Token                                            │
│     • Expiration: Set appropriate (e.g., 7 days)                        │
│     • Audience: Search (if asked)                                       │
│                                                                          │
│  5. Copy the token value (shown only once!)                             │
│                                                                          │
│  6. Store it securely - you'll need it for the export script            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Option B: Username/Password

- Your Splunk Cloud admin username and password
- If MFA is required, you may need to create an API token instead

### 3. Required Permissions (CRITICAL - READ THIS CAREFULLY)

> **WARNING**: Insufficient permissions are the #1 cause of export failures. Follow this section exactly to avoid partial exports and repeated runs.

The export script needs access to REST API endpoints across ALL apps in your Splunk Cloud environment. This requires a user or token with **elevated privileges** — a standard user account will NOT work.

---

#### Complete Capabilities Reference

| Capability | Required For | What Fails Without It |
|------------|--------------|----------------------|
| `admin_all_objects` | **CRITICAL** | Cannot list apps, dashboards, saved searches in other apps |
| `list_settings` | Core export | Cannot read server settings, configurations |
| `rest_properties_get` | REST API access | API calls return 403 Forbidden |
| `search` | Usage analytics | All `--usage` SPL queries fail |
| `list_users` | RBAC collection | `--rbac` flag returns empty user list |
| `list_roles` | RBAC collection | `--rbac` flag returns empty role list |
| `list_indexes` | Index metadata | Cannot collect index information |
| `schedule_search` | Usage analytics | Some scheduled search queries fail |
| `list_inputs` | Data inputs | Cannot collect input configurations |
| `list_forwarders` | Ingestion data | Cannot collect forwarder information |
| `indexes_edit` | Index details | Cannot read index properties (some environments) |
| `read_internal_indexes` | Usage analytics | Cannot query `_internal`, `_audit` indexes |

---

#### Option 1: Use the `sc_admin` Role (Recommended for Splunk Cloud)

Splunk Cloud provides a built-in role called `sc_admin` that has all the capabilities needed for a complete export. This is the **easiest and most reliable** approach.

**Step-by-step Setup:**

1. **Log into Splunk Cloud** as an admin user
   ```
   https://your-stack.splunkcloud.com
   ```

2. **Go to Settings → Access Controls → Users**

3. **Create a new user** (or modify an existing one):
   - Click "New User" or select an existing user
   - Username: `dma_export_user` (or any name)
   - Set a strong password
   - **Assign Roles**: Select `sc_admin`
   - Click "Save"

4. **Create an API Token** for this user:
   - Log in as the `dma_export_user`
   - Go to Settings → Tokens
   - Click "New Token"
   - Name: `DMA Export Token`
   - Expiration: 7 days (or as needed)
   - Click "Create"
   - **COPY THE TOKEN NOW** (it's only shown once)

5. **Run the export** with this token:
   ```bash
   ./dma-splunk-cloud-export.sh --stack your-stack.splunkcloud.com --token "YOUR_TOKEN"
   ```

---

#### Option 2: Create a Custom Role with Minimum Required Capabilities

If you cannot use `sc_admin` (e.g., due to security policies), create a custom role with exactly the capabilities needed.

**Step-by-step Setup:**

1. **Go to Settings → Access Controls → Roles**

2. **Click "New Role"**

3. **Configure the role:**
   - Name: `dma_export_role`
   - Default app: `search`

4. **Under "Capabilities", enable ALL of the following:**

   **Core Capabilities (REQUIRED):**
   ```
   admin_all_objects
   list_settings
   rest_properties_get
   rest_properties_set
   ```

   **Search Capabilities (REQUIRED for --usage):**
   ```
   search
   schedule_search
   rtsearch
   ```

   **RBAC Capabilities (REQUIRED for --rbac):**
   ```
   list_users
   edit_user
   list_roles
   ```

   **Index Capabilities (REQUIRED for index collection):**
   ```
   list_indexes
   indexes_edit
   ```

   **Internal Index Access (REQUIRED for usage analytics):**
   ```
   list_introspection
   ```

5. **Under "Indexes searched by default", add:**
   ```
   _internal
   _audit
   _introspection
   ```

6. **Under "Indexes", set:**
   - "Indexes searched by default": Select all indexes OR `*`
   - "Indexes": Select all indexes OR `*`

7. **Inherit from**: Select `user` as the base role

8. **Click "Save"**

9. **Assign this role to your export user** (Settings → Users → select user → add `dma_export_role`)

---

#### Option 3: Using an Existing Admin User

If your organization has an existing admin user with appropriate access, you can use those credentials directly. However, verify the user has all required capabilities first.

---

#### Verifying Your Permissions BEFORE Running the Export

Run these searches in Splunk Cloud to verify your token/user has the correct access:

**1. Check your capabilities:**
```spl
| rest /services/authentication/current-context
| table username, roles
| append [| rest /services/authentication/current-context
| mvexpand capabilities
| stats values(capabilities) as capabilities]
```

**2. Verify you can list all apps:**
```spl
| rest /services/apps/local
| stats count
```
Expected: Returns a count > 0 (should show all apps you have access to)

**3. Verify you can access saved searches across apps:**
```spl
| rest /servicesNS/-/-/saved/searches
| stats count by eai:acl.app
```
Expected: Returns saved searches from multiple apps

**4. Verify you can query internal indexes (needed for --usage):**
```spl
index=_internal sourcetype=splunkd | head 1
```
Expected: Returns at least 1 result (not "no results found")

**5. Verify you can query audit index (needed for --usage):**
```spl
index=_audit action=search | head 1
```
Expected: Returns at least 1 result

---

#### Common Permission Errors and Solutions

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `No applications found! Cannot proceed` | User lacks `admin_all_objects` or `list_settings` | Assign `sc_admin` role or add missing capabilities |
| `Access forbidden (403)` | User lacks `rest_properties_get` | Add capability to role |
| `Failed to retrieve user capabilities` | Token expired or invalid | Generate a new token |
| `0 users collected` with `--rbac` | User lacks `list_users` capability | Add `list_users` to role |
| `0 results` from usage queries | User lacks access to `_internal`/`_audit` indexes | Add indexes to role's searchable indexes |
| `403 on /services/authentication/users` | User cannot list other users | Add `list_users` and `edit_user` capabilities |
| `Skipping endpoint (blocked in Cloud)` | Normal - some endpoints don't exist in Cloud | Not an error, script handles this automatically |

---

#### Minimum Permissions Summary Table

| Collection Type | Flag | Required Capabilities | Required Index Access |
|----------------|------|----------------------|----------------------|
| **Basic Export** (apps, dashboards, alerts) | (default) | `admin_all_objects`, `list_settings`, `rest_properties_get` | None |
| **RBAC/Users** | `--rbac` | Above + `list_users`, `list_roles`, `edit_user` | None |
| **Usage Analytics** | `--usage` | Above + `search`, `schedule_search` | `_internal`, `_audit` |
| **Index Metadata** | (default) | Above + `list_indexes` | None |
| **Full Export** | `--rbac --usage` | All of the above | `_internal`, `_audit` |

---

#### Why Can't I Just Use My Regular User Account?

Regular Splunk users typically:
- Can only see their own apps and objects (not `admin_all_objects`)
- Cannot list other users (`list_users` not granted)
- Cannot query `_internal` or `_audit` indexes
- Cannot access REST endpoints for system configuration

The export script needs to see **everything** in your Splunk environment to provide a complete migration assessment. This requires admin-level access.

---

#### Checking Your Permissions (Quick Test)

Before running the full export, test your credentials:

```bash
# Test if you can reach the API and list apps
curl -s -k -H "Authorization: Bearer YOUR_TOKEN" \
  "https://your-stack.splunkcloud.com:8089/services/apps/local?output_mode=json&count=0" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Apps found: {len(d.get(\"entry\",[]))}')"
```

Expected output: `Apps found: 42` (some number > 0)

If you see `Apps found: 0` or an error, your token lacks the required permissions.

### 4. Local Machine Requirements

| Requirement | Purpose | Check Command |
|-------------|---------|---------------|
| `bash` 4.0+ | Script execution | `bash --version` |
| `curl` | REST API calls | `curl --version` |
| `Python 3` | JSON parsing | `python3 --version` |
| Disk space | Store export | 500MB+ free |

#### PowerShell Edition Requirements

| Requirement | Purpose | Check Command |
|-------------|---------|---------------|
| PowerShell 5.1+ or 7+ | Script execution | `$PSVersionTable.PSVersion` |
| Windows 10 1803+ | Built-in tar.exe | `tar --version` |
| Network access | REST API calls | Port 8089 to Splunk Cloud |
| No external dependencies | Pure PowerShell | No Python, curl, or jq needed |

---

## Splunk Cloud Stack URL

### Finding Your Stack URL

Your Splunk Cloud stack URL is the address you use to access Splunk Cloud:

```
https://<stack-name>.splunkcloud.com
```

**Examples**:
- `https://acme-corp.splunkcloud.com`
- `https://mycompany-prod.splunkcloud.com`
- `https://enterprise1.splunkcloud.com`

### Testing Connectivity

```bash
# Test if you can reach the REST API
curl -I "https://your-stack.splunkcloud.com:8089/services/server/info"

# Expected: HTTP/2 401 (Unauthorized - but reachable)
# If you get connection refused or timeout, check network/firewall
```

---

## Supported Splunk Cloud Types

| Cloud Type | Supported | Notes |
|------------|-----------|-------|
| Splunk Cloud Classic | ✅ Yes | Legacy multi-tenant |
| Splunk Cloud Victoria Experience | ✅ Yes | Current default |
| Splunk Cloud on AWS | ✅ Yes | Single-tenant |
| Splunk Cloud on GCP | ✅ Yes | Single-tenant |
| Splunk Cloud on Azure | ✅ Yes | Single-tenant |

---

## What Data Can Be Collected

### ✅ Fully Available via REST API

| Data Type | REST Endpoint | Notes |
|-----------|---------------|-------|
| Dashboards | `/data/ui/views` | Classic + Dashboard Studio |
| Saved Searches | `/saved/searches` | Includes alerts, reports |
| Users | `/authentication/users` | Full user list |
| Roles | `/authorization/roles` | With capabilities |
| Macros | `/admin/macros` | All search macros |
| Eventtypes | `/saved/eventtypes` | Event classifications |
| Tags | `/configs/conf-tags` | Tag assignments |
| Lookup Definitions | `/data/lookup-table-files` | File metadata |
| Lookup Contents | Download via REST | CSV data |
| Field Extractions | `/data/transforms/extractions` | Regex extractions |
| Apps List | `/apps/local` | Installed apps |
| Index Settings | `/data/indexes` | Index configuration |

### ⚠️ Partially Available

| Data Type | Limitation | Workaround |
|-----------|------------|------------|
| Props.conf | No file access | Reconstructed from `/configs/conf-props` |
| Transforms.conf | No file access | Reconstructed from `/configs/conf-transforms` |
| Usage Analytics | Requires search | Run searches on `_audit` index |
| Index Sizes | Limited stats | Best-effort from API |

### ❌ Not Available

| Data Type | Why | Impact |
|-----------|-----|--------|
| Raw config files | No file system | Use REST reconstruction |
| $SPLUNK_HOME access | Cloud infrastructure | N/A |
| Audit.log file | No file system | Use `_audit` index search |
| License file | Cloud-managed | N/A |
| Deployment apps | Cloud-managed | N/A |

---

## IP Allowlisting (If Required)

Some Splunk Cloud instances require IP allowlisting for API access:

### Check If Required

Contact your Splunk Cloud admin or check:
- Splunk Cloud Admin Config (if you have access)
- Cloud Stack settings

### Adding Your IP

1. Log into Splunk Cloud Admin Config
2. Go to IP Allowlist settings
3. Add your machine's public IP:
   ```bash
   # Find your public IP
   curl ifconfig.me
   ```
4. Allow port 8089 (REST API)

---

## Running the Script

### Basic Usage

```bash
# Make executable
chmod +x dma-splunk-cloud-export.sh

# Run interactively
./dma-splunk-cloud-export.sh
```

### With Pre-set Values

```bash
# Set stack URL via environment
export SPLUNK_CLOUD_STACK="acme-corp.splunkcloud.com"

# Set token via environment (more secure than command line)
export SPLUNK_CLOUD_TOKEN="your-api-token"

./dma-splunk-cloud-export.sh
```

### Non-Interactive Mode (for automation)

```bash
./dma-splunk-cloud-export.sh \
  --stack "acme-corp.splunkcloud.com" \
  --token "$SPLUNK_CLOUD_TOKEN" \
  --all-apps \
  --output /path/to/output
```

---

## Command-Line Arguments (Updated in v4.5.8)

| Argument (Bash) | PowerShell | Description |
|------------------|------------|-------------|
| `--stack URL` | `-Stack URL` | Splunk Cloud stack URL |
| `--token TOKEN` | `-Token TOKEN` | API token (recommended) |
| `--user USER` | `-User USER` | Username (alternative to token) |
| `--password PASS` | `-Password PASS` | Password (used with `--user`) |
| `--apps "a,b"` | `-Apps "a,b"` | Comma-separated list of apps |
| `--all-apps` | `-AllApps` | Export all applications (default) |
| `--scoped` | N/A | Scope collections to selected apps only |
| `--rbac` | `-Rbac` | Enable RBAC/user collection (OFF by default) |
| `--usage` | `-Usage` | Enable usage analytics (OFF by default) |
| `--analytics-period N` | `-AnalyticsPeriod N` | Analytics time window (default: 7d; e.g. 30d, 90d) |
| `--skip-internal` | `-SkipInternal` | Skip `_audit`/`_internal` index searches |
| `--test-access` | `-TestAccess` | Pre-flight API access check (no export) |
| `--remask FILE` | `-Remask FILE` | Re-anonymize existing archive (no Splunk needed) |
| `--resume-collect FILE` | `-ResumeCollect FILE` | Resume from previous .tar.gz archive |
| `--proxy URL` | `-Proxy URL` | Route all connections through proxy |
| `--output DIR` | `-Output DIR` | Output directory |
| `-d, --debug` | `-Debug_Mode` | Enable verbose debug logging |
| `--skip-anonymize` | `-SkipAnonymization` | Skip data anonymization |
| `--help` | `-ShowHelp` | Show help message |

### App-Scoped Export Mode

For large Splunk Cloud environments, dramatically reduce export time by targeting specific apps:

```bash
# Scoped mode - exports app configs + only users/searches related to those apps
./dma-splunk-cloud-export.sh \
  --stack acme.splunkcloud.com \
  --token "$TOKEN" \
  --apps "myapp,otherapp" \
  --scoped
```

| Mode | What It Does | Use When |
|------|-------------|----------|
| `--scoped` | App configs + app-filtered users/usage | You want usage data but only for selected apps |
| (default) | Full export of all apps + global analytics | **Recommended** - Full migration analysis |

### Resume Collection Mode (NEW in v4.3.0)

If a previous export was interrupted, timed out, or was run without certain flags (like `--rbac` or `--usage`), you can resume and complete the export without starting over.

The script extracts the previous archive, inspects what was already collected, skips those data types, and collects only the missing pieces. The output is a new versioned archive (e.g., `-v1`, `-v2`).

#### Bash Examples

```bash
# Resume a previous incomplete export
./dma-splunk-cloud-export.sh \
  --stack acme.splunkcloud.com \
  --token "$TOKEN" \
  --resume-collect ./dma_cloud_export_acme-corp_20260115_093000.tar.gz

# Resume AND add RBAC + usage data that were skipped originally
./dma-splunk-cloud-export.sh \
  --stack acme.splunkcloud.com \
  --token "$TOKEN" \
  --resume-collect ./dma_cloud_export_acme-corp_20260115_093000.tar.gz \
  --rbac --usage
```

#### PowerShell Examples

```powershell
# Resume a previous incomplete export
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme.splunkcloud.com" `
  -Token $TOKEN `
  -ResumeCollect ".\dma_cloud_export_acme-corp_20260115_093000.tar.gz"

# Resume AND add RBAC + usage data
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme.splunkcloud.com" `
  -Token $TOKEN `
  -ResumeCollect ".\dma_cloud_export_acme-corp_20260115_093000.tar.gz" `
  -Rbac -Usage
```

#### Versioned Output

When resuming, the script creates a versioned archive to avoid overwriting the original:

- Original: `dma_cloud_export_acme-corp_20260115_093000.tar.gz`
- First resume: `dma_cloud_export_acme-corp_20260115_093000-v1.tar.gz`
- Second resume: `dma_cloud_export_acme-corp_20260115_093000-v2.tar.gz`

#### What Gets Skipped vs Collected

| Data Type | Skip If... |
|-----------|------------|
| Dashboards | App already has dashboard files |
| Saved Searches | App already has `savedsearches.json` |
| Knowledge Objects | App has `macros.json` + `props.json` + `transforms.json` |
| Configs | `_configs/` directory exists |
| RBAC | `users.json` + `roles.json` exist |
| Usage Analytics | `usage_analytics/` has 2+ files |
| Indexes | `indexes.json` exists |

### Debug Mode (NEW in v4.1.0)

When troubleshooting issues, enable debug mode to capture detailed logs:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme.splunkcloud.com \
  --token "$TOKEN" \
  --apps myapp \
  --debug
```

Debug mode provides:
- **Console output**: Color-coded messages by category (API, SEARCH, TIMING, ERROR, WARN)
- **Debug log file**: `export_debug.log` inside the export directory (included in the .tar.gz)
- **API call tracking**: Every REST API call with HTTP status and response size
- **Detailed timing**: Duration of each API call and search operation

---

## Enterprise Resilience Features

**NEW in v4.0.0**: The Cloud script now includes the same enterprise-scale features as the Enterprise script for environments with 4000+ dashboards and 10K+ alerts.

### Default Settings (Enterprise-Ready)

| Setting | Default | Description |
|---------|---------|-------------|
| `BATCH_SIZE` | 100 | Items per API request |
| `API_TIMEOUT` | 120s | Per-request timeout (2 min) |
| `MAX_TOTAL_TIME` | 43200s | Max runtime (12 hours) |
| `MAX_RETRIES` | 3 | Retry attempts with exponential backoff |
| `RATE_LIMIT_DELAY` | 0.1s | Delay between API calls (100ms) |
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume capability |
| `RESUME_COLLECT` | (none) | Path to previous .tar.gz for resume collection **(NEW v4.3.0)** |

### Checkpoint/Resume Capability

If the export is interrupted (timeout, network error, Ctrl+C), you can resume:

```bash
# Script detects previous incomplete export
./dma-splunk-cloud-export.sh

# Output:
# Found checkpoint from 2025-01-06 14:30:00
# Would you like to resume? (Y/n): Y
# Resuming from: Dashboards (offset 500)...
```

### Export Timing Statistics

At completion, the script shows detailed timing:

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    EXPORT TIMING STATISTICS                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Total Duration:        5 minutes 4 seconds                              ║
║  API Calls:             347                                              ║
║  API Retries:           2                                                ║
║  API Failures:          0                                                ║
║  Rate Limit Hits:       0                                                ║
║  Batches Completed:     52                                               ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Environment Variable Overrides

For very large Splunk Cloud environments, tune via environment variables:

```bash
# Large environment (5000+ dashboards)
export BATCH_SIZE=50
export API_TIMEOUT=180
./dma-splunk-cloud-export.sh

# Or inline
BATCH_SIZE=50 API_TIMEOUT=180 ./dma-splunk-cloud-export.sh
```

---

## PowerShell Edition

The `dma-splunk-cloud-export.ps1` script provides the same functionality as the Bash script for Windows environments. It is written in pure PowerShell with zero external dependencies -- no Python, curl, jq, or any other tools are required.

### Supported PowerShell Versions

| Version | Platform | Notes |
|---------|----------|-------|
| PowerShell 5.1 | Windows PowerShell (built into Windows 10/11) | Most common |
| PowerShell 7+ | Cross-platform (Windows, macOS, Linux) | Recommended for non-Windows |

### Parameter Equivalence (Bash to PowerShell)

| Bash Flag | PowerShell Parameter | Example |
|-----------|---------------------|---------|
| `--stack` | `-Stack` | `-Stack "acme.splunkcloud.com"` |
| `--token` | `-Token` | `-Token "xxxxx"` |
| `--user` | `-User` | `-User "admin"` |
| `--password` | `-Password` | `-Password "xxx"` |
| `--apps` | `-Apps` | `-Apps "search,myapp"` |
| `--all-apps` | `-AllApps` | `-AllApps` |
| `--quick` | `-Quick` | `-Quick` |
| `--scoped` | `-Scoped` | `-Scoped` |
| `--rbac` | `-Rbac` | `-Rbac` |
| `--usage` | `-Usage` | `-Usage` |
| `--no-usage` | `-NoUsage` | `-NoUsage` |
| `--resume-collect` | `-ResumeCollect` | `-ResumeCollect ".\previous.tar.gz"` |
| `--proxy` | `-Proxy` | `-Proxy "http://proxy:8080"` |
| `--output` | `-Output` | `-Output "C:\exports"` |
| `--debug` | `-Debug` | `-Debug` |
| `--help` | `-Help` or `Get-Help` | `Get-Help .\dma-splunk-cloud-export.ps1` |

### Example Commands

```powershell
# Interactive mode (prompts for all inputs)
.\dma-splunk-cloud-export.ps1

# Non-interactive full export
.\dma-splunk-cloud-export.ps1 -Stack "acme.splunkcloud.com" -Token $env:SPLUNK_TOKEN -AllApps

# Export specific apps with RBAC and usage
.\dma-splunk-cloud-export.ps1 -Stack "acme.splunkcloud.com" -Token $env:SPLUNK_TOKEN -Apps "search,security_app" -Rbac -Usage

# Resume a previous incomplete export
.\dma-splunk-cloud-export.ps1 -Stack "acme.splunkcloud.com" -Token $env:SPLUNK_TOKEN -ResumeCollect ".\previous_export.tar.gz"
```

### Key Differences from Bash

- **Zero external dependencies**: Uses `Invoke-RestMethod` instead of curl, native JSON handling instead of Python/jq
- **Windows-native tar**: Uses `tar.exe` built into Windows 10 1803+ for archive creation
- **PowerShell parameter style**: Uses `-ParameterName` instead of `--flag-name`
- **Environment variables**: Use `$env:SPLUNK_CLOUD_TOKEN` instead of `$SPLUNK_CLOUD_TOKEN`

---

## Troubleshooting

### Connection Refused

```
Error: curl: (7) Failed to connect to acme-corp.splunkcloud.com port 8089
```

**Solutions**:
1. Check if you're on VPN (if required)
2. Verify the stack URL is correct
3. Check corporate firewall rules
4. Verify Splunk Cloud IP allowlist includes your IP

### Authentication Failed (401)

```
Error: HTTP 401 Unauthorized
```

**Solutions**:
1. Verify credentials are correct
2. Check if token has expired
3. Try creating a new token
4. Verify user account is active

### Forbidden (403)

```
Error: HTTP 403 Forbidden for /services/authentication/users
```

**Solutions**:
1. User/token lacks required capabilities
2. Add `admin_all_objects` capability
3. Check role assignments
4. Some Cloud stacks restrict certain APIs

### Rate Limited (429)

```
Error: HTTP 429 Too Many Requests
```

**Solutions**:
1. Script will automatically back off and retry
2. If persistent, wait 5 minutes and try again
3. Contact Splunk Cloud support for limit increases

### SSL Certificate Error

```
Error: SSL certificate problem: unable to get local issuer certificate
```

**Solutions**:
1. Update CA certificates: `update-ca-certificates`
2. Script uses `-k` flag as fallback (warns user)
3. Download Splunk Cloud CA cert and specify

---

## Security Best Practices

### Token Security

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TOKEN SECURITY CHECKLIST                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ✓ Use API tokens instead of passwords                                  │
│  ✓ Set appropriate token expiration (7-30 days)                         │
│  ✓ Don't share tokens in chat, email, or tickets                       │
│  ✓ Use environment variables, not command-line args                    │
│  ✓ Delete token after export is complete                               │
│  ✓ Don't commit tokens to version control                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Export File Security

```bash
# Export file contains sensitive metadata
# Handle with appropriate care

# Secure transfer
scp export.tar.gz user@secure-server:/path/

# Delete after upload to DMA
rm export.tar.gz
```

---

## What Gets Exported

The export creates a `.tar.gz` file compatible with DMA containing:

```
dma_cloud_export_[stack]_[timestamp]/
├── dma-env-summary.md      # Summary report
├── manifest.json                   # Export metadata (schema v4.0)
├── _systeminfo/                    # Server info
├── _rbac/                         # Users and roles
├── _configs/                      # Reconstructed configs
├── _usage_analytics/              # Usage data
└── [app_name]/                    # Per-app data (v2 app-centric structure)
    ├── dashboards/                 # v2: App-scoped dashboards (v4.2.0+)
    │   ├── classic/               # Classic XML dashboards for this app
    │   └── studio/                # Dashboard Studio JSON for this app
    ├── savedsearches.json
    └── macros.json
```

---

## Comparison with Enterprise Export

| Feature | Enterprise Export | Cloud Export |
|---------|------------------|--------------|
| Dashboards | ✅ Complete | ✅ Complete |
| Alerts | ✅ Complete | ✅ Complete |
| Users/RBAC | ✅ Complete | ✅ Complete |
| Props/Transforms | ✅ File-based | ⚠️ REST reconstruction |
| Usage Analytics | ✅ Audit log + search | ⚠️ Search only |
| Index Stats | ✅ Complete | ⚠️ Limited |
| Lookup Contents | ✅ Direct file | ✅ REST download |
| Custom Scripts | ✅ bin/ directory | ❌ Not accessible |
| Export Format | .tar.gz | .tar.gz (compatible) |

---

## Frequently Asked Questions

### Q: Can I run this on my laptop?

**A: Yes!** That's exactly where you should run it. You just need network access to your Splunk Cloud instance.

### Q: Do I need SSH access to anything?

**A: No.** This script is 100% REST API based. No SSH required.

### Q: Will this work with MFA enabled?

**A: Use an API token.** MFA typically doesn't apply to API token authentication.

### Q: How long does the export take?

**A: 5-30 minutes** depending on the size of your environment and network speed. Large environments with many dashboards may take longer.

### Q: Can I schedule this to run automatically?

**A: Yes.** Use the non-interactive mode with environment variables:
```bash
export SPLUNK_CLOUD_STACK="your-stack.splunkcloud.com"
export SPLUNK_CLOUD_TOKEN="your-token"
./dma-splunk-cloud-export.sh --all-apps --output /exports/
```

### Q: Can I run this on Windows?

**A: Yes!** Use `dma-splunk-cloud-export.ps1` which requires only PowerShell 5.1+ and has zero external dependencies. See the [PowerShell Edition](#powershell-edition) section for details.

### Q: My previous export timed out. Do I need to start over?

**A: No!** Use `--resume-collect` (Bash) or `-ResumeCollect` (PowerShell) to pass your previous `.tar.gz`. The script will detect what has already been collected and fill in the gaps, creating a new versioned archive (e.g., `-v1`).

```bash
# Bash
./dma-splunk-cloud-export.sh --stack acme.splunkcloud.com --token "$TOKEN" --resume-collect ./previous_export.tar.gz

# PowerShell
.\dma-splunk-cloud-export.ps1 -Stack "acme.splunkcloud.com" -Token $TOKEN -ResumeCollect ".\previous_export.tar.gz"
```

### Q: What if I have multiple Splunk Cloud stacks?

**A: Run the script once per stack.** Each export will be labeled with the stack name.

---

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the export log file generated during the run
3. Contact the DMA team with:
   - Error messages
   - Stack URL (without credentials)
   - Splunk Cloud type (Classic/Victoria)

---

## What to Expect: Step-by-Step Walkthrough

This section shows exactly what you'll see when running the script successfully.

### Step 1: Launch and Welcome Screen

When you run `./dma-splunk-cloud-export.sh`, you'll see:

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
║                   ☁️  SPLUNK CLOUD EXPORT SCRIPT  ☁️                         ║
║                                                                                ║
║          Complete REST API-Based Data Collection for Migration              ║
║                        Version 4.5.8                                    ║
║                                                                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

Do you want to continue? (Y/n):
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
║  SPLUNK CLOUD ACCESS:                                                      ║
║    □  Splunk Cloud stack URL (e.g., your-company.splunkcloud.com)          ║
║    □  Splunk username with admin privileges                                ║
║    □  Splunk password OR API token (sc_admin role recommended)             ║
║                                                                              ║
║  🔒 DATA PRIVACY & SECURITY:                                                ║
║                                                                              ║
║  We do NOT collect or export:                                              ║
║    ✗  User passwords or password hashes                                    ║
║    ✗  API tokens or session keys                                           ║
║    ✗  Private keys or certificates                                         ║
║    ✗  Your actual log data (only metadata/structure)                       ║
║                                                                              ║
║  We automatically REDACT:                                                  ║
║    ✓  password = [REDACTED] in all .conf files                             ║
║    ✓  secret = [REDACTED] in outputs.conf                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

  Quick System Check:
    ✓ bash: 5.2.15(1)-release
    ✓ curl: 8.1.2
    ✓ jq: jq-1.6
    ✓ tar: available

Ready to proceed? (Y/n):
```

**Action**: Press `Y` if all checks pass.

### Step 3: Enter Splunk Cloud Stack URL

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: SPLUNK CLOUD CONNECTION                                             │
└─────────────────────────────────────────────────────────────────────────────┘

  Your Splunk Cloud stack URL looks like:
    https://your-company.splunkcloud.com

  Enter your Splunk Cloud stack URL: acme-corp.splunkcloud.com

◐ Testing connection to https://acme-corp.splunkcloud.com:8089...
✓ Connection successful
```

**Action**: Enter your stack URL (without `https://` prefix).

### Step 4: Authentication

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: AUTHENTICATION                                                      │
└─────────────────────────────────────────────────────────────────────────────┘

  Required Permissions:
    • admin_all_objects - Access all knowledge objects
    • list_users, list_roles - Access RBAC data
    • search - Run analytics queries

  🔒 Security: Your credentials are used locally only and are NEVER stored,
     logged, or transmitted outside of this session. They are cleared on exit.

  Choose authentication method:

    1) API Token (recommended)
    2) Username/Password

  Select option [1]: 1

  Enter API token: ••••••••••••••••••••••••••••••••

◐ Testing authentication...
✓ Token authentication successful (user: admin)
```

**Action**: Choose auth method and enter credentials.

### Step 5: Select Data Categories

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: DATA CATEGORIES                                                     │
└─────────────────────────────────────────────────────────────────────────────┘

  Select data categories to collect:

    [✓] 1. Configurations (via REST - reconstructed from API)
    [✓] 2. Dashboards (Classic + Dashboard Studio)
    [✓] 3. Alerts & Saved Searches
    [✓] 4. Users & RBAC (usernames & roles only - NO passwords)
    [✓] 5. Usage Analytics (via search on _audit)
    [✓] 6. Index Statistics
    [✓] 7. Lookup Contents (may be large)
    [ ] 8. Anonymize Data (emails→fake, hosts→fake, IPs→redacted)

  🔒 Privacy: User data includes names/roles only. Passwords are NEVER collected.
  💡 Tip: Enable option 8 when sharing export with third parties.

  Accept defaults? (Y/n): Y
```

**Action**: Press `Y` to accept defaults or `n` to customize.

### Step 6: Data Collection Progress

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ COLLECTING DATA                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

  [1/7] Collecting system information...
✓ Server info collected
✓ Installed apps collected

  [2/7] Collecting configurations via REST API...
✓ Props configuration collected
✓ Transforms configuration collected
✓ Indexes configuration collected

  [3/7] Collecting dashboards...
[████████████████████████████████████████] 100% security_app/security_overview
✓ Collected 47 Classic dashboards
✓ Collected 12 Dashboard Studio dashboards

  [4/7] Collecting alerts and saved searches...
✓ Collected 89 saved searches (34 alerts)

  [5/7] Collecting users and roles...
✓ Collected 23 users
✓ Collected 8 roles

  [6/7] Collecting usage analytics...
◐ Running search: Dashboard views (last 7 days)...
✓ Dashboard usage collected
◐ Running search: User activity...
✓ User activity collected

  [7/7] Collecting index statistics...
✓ Index stats collected for 15 indexes
```

### Step 7: Export Complete

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         EXPORT COMPLETE!                                     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Export Archive:                                                             ║
║    📦 dma_cloud_export_acme-corp_20241203_143052.tar.gz               ║
║                                                                              ║
║  Summary:                                                                    ║
║    • Dashboards:        59 (47 Classic + 12 Studio)                          ║
║    • Alerts:            34                                                   ║
║    • Saved Searches:    89                                                   ║
║    • Users:             23                                                   ║
║    • Roles:             8                                                    ║
║    • Apps:              12                                                   ║
║    • Indexes:           15                                                   ║
║                                                                              ║
║  Duration: 4 minutes 23 seconds                                              ║
║  Archive Size: 2.3 MB                                                        ║
║                                                                              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  NEXT STEPS:                                                                 ║
║                                                                              ║
║  1. Upload to DMA:                                                           ║
║     Open Dynatrace Migration Assistant app → Data Sources → Upload Export    ║
║                                                                              ║
║  2. Review the summary report:                                               ║
║     cat dma_cloud_export_acme-corp_20241203_143052/                   ║
║         dma-env-summary.md                                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### What Success Looks Like

After a successful export, you'll have a `.tar.gz` file. Extract it to see:

```bash
$ tar -tzf dma_cloud_export_acme-corp_20241203_143052.tar.gz | head -20

dma_cloud_export_acme-corp_20241203_143052/
dma_cloud_export_acme-corp_20241203_143052/manifest.json
dma_cloud_export_acme-corp_20241203_143052/dma-env-summary.md
dma_cloud_export_acme-corp_20241203_143052/_export.log
dma_cloud_export_acme-corp_20241203_143052/_systeminfo/
dma_cloud_export_acme-corp_20241203_143052/_systeminfo/server_info.json
dma_cloud_export_acme-corp_20241203_143052/_systeminfo/installed_apps.json
dma_cloud_export_acme-corp_20241203_143052/_rbac/
dma_cloud_export_acme-corp_20241203_143052/_rbac/users.json
dma_cloud_export_acme-corp_20241203_143052/_rbac/roles.json
dma_cloud_export_acme-corp_20241203_143052/_usage_analytics/
dma_cloud_export_acme-corp_20241203_143052/_usage_analytics/dashboard_views.json
dma_cloud_export_acme-corp_20241203_143052/_usage_analytics/users_most_active.json
dma_cloud_export_acme-corp_20241203_143052/security_app/
dma_cloud_export_acme-corp_20241203_143052/security_app/dashboards/
dma_cloud_export_acme-corp_20241203_143052/security_app/savedsearches.json
```

### If Something Goes Wrong

If errors occur, you'll see a warning box:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  ⚠️  EXPORT COMPLETED WITH 3 ERRORS                                          ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Some data could not be collected. See details below:                        ║
║                                                                              ║
║  Errors:                                                                     ║
║    • HTTP 403: Access denied to /services/data/lookup-table-files           ║
║    • Search timeout: Usage analytics query exceeded 5 minutes               ║
║    • HTTP 429: Rate limited - some data may be incomplete                   ║
║                                                                              ║
║  A troubleshooting report has been generated:                                ║
║    📄 TROUBLESHOOTING.md                                                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

Review `TROUBLESHOOTING.md` in the export directory for specific remediation steps.

---

## Sample Output Files

### Example: dma-env-summary.md

This human-readable summary report is generated in the export directory:

```markdown
# DMA Splunk Cloud Environment Summary

**Export Date**: 2025-12-03 14:30:52 EST
**Export Script Version**: 4.5.8
**Export Type**: Splunk Cloud (REST API)

---

## Environment Overview

| Property | Value |
|----------|-------|
| **Stack URL** | acme-corp.splunkcloud.com |
| **Cloud Type** | Victoria Experience |
| **Splunk Version** | 9.1.3 |
| **Server GUID** | 8F4A2B1C-3D5E-6F7A-8B9C-0D1E2F3A4B5C |

---

## Collection Summary

| Category | Count | Status |
|----------|-------|--------|
| **Applications** | 12 | ✅ Collected |
| **Dashboards** | 59 | ✅ Collected |
| **Alerts** | 34 | ✅ Collected |
| **Users** | 23 | ✅ Collected |
| **Indexes** | 15 | ✅ Collected |

---

## Collection Statistics

| Metric | Value |
|--------|-------|
| **API Calls Made** | 347 |
| **Rate Limit Hits** | 2 |
| **Errors** | 0 |
| **Warnings** | 1 |

---

## Data Categories Collected

- ✅ Configurations (via REST API reconstruction)
- ✅ Dashboards (Classic and Dashboard Studio)
- ✅ Alerts and Saved Searches
- ✅ Users, Roles, and RBAC
- ✅ Usage Analytics (last 7d)
- ✅ Index Statistics
- ⏭️ Lookup Contents (skipped)
- ⏭️ Data Anonymization (available - enable with option 8)

---

## Applications Exported

- search
- security_app
- itsi
- splunk_app_for_aws
- enterprise_security
- phantom
- dashboard_studio
- user-prefs
- learned
- introspection_generator_addon
- alert_manager
- monitoring_console

---

## Cloud Export Notes

This export was collected via REST API from Splunk Cloud. Some differences from Enterprise exports:

1. **Configuration Files**: Reconstructed from REST API endpoints (not direct file access)
2. **Usage Analytics**: Collected via search queries on _audit and _internal indexes
3. **Index Statistics**: Limited to what's available via REST API
4. **No File System Access**: Cannot access raw bucket data, audit logs, etc.

---

## Errors and Warnings

### Errors (0)
No errors occurred.

### Warnings (1)
- Rate limit approached on dashboard collection; added 2s delay

---

## Next Steps

1. **Upload to DMA**: Upload the `.tar.gz` file to DMA in Dynatrace
2. **Review Dashboards**: Check the dashboard conversion preview
3. **Review Alerts**: Check alert conversion recommendations
4. **Plan Data Ingestion**: Use OpenPipeline templates for log ingestion

---

*Generated by DMA Splunk Cloud Export Script v4.0.0*
```

### Example: manifest.json (Schema)

This machine-readable manifest is used by DMA to process your export:

```json
{
  "schema_version": "3.3",
  "export_tool": "dma-splunk-cloud-export",
  "export_tool_version": "4.0.0",
  "export_timestamp": "2025-12-03T19:30:52Z",
  "export_duration_seconds": 263,

  "source": {
    "hostname": "acme-corp.splunkcloud.com",
    "fqdn": "acme-corp.splunkcloud.com",
    "platform": "Splunk Cloud",
    "platform_version": "Victoria Experience"
  },

  "splunk": {
    "home": "cloud",
    "version": "9.1.3",
    "build": "cloud",
    "flavor": "cloud",
    "role": "search_head",
    "architecture": "cloud",
    "is_cloud": true,
    "cloud_type": "Victoria Experience",
    "server_guid": "8F4A2B1C-3D5E-6F7A-8B9C-0D1E2F3A4B5C"
  },

  "collection": {
    "configs": true,
    "dashboards": true,
    "alerts": true,
    "rbac": true,
    "usage_analytics": true,
    "usage_period": "7d",
    "indexes": true,
    "lookups": false
  },

  "statistics": {
    "apps_exported": 12,
    "dashboards_classic": 47,
    "dashboards_studio": 12,
    "dashboards_total": 59,
    "alerts": 34,
    "saved_searches": 89,
    "users": 23,
    "roles": 8,
    "indexes": 15,
    "api_calls_made": 347,
    "rate_limit_hits": 2,
    "errors": 0,
    "warnings": 1,
    "total_files": 234,
    "total_size_bytes": 2411724
  },

  "apps": [
    {
      "name": "security_app",
      "dashboards": 15,
      "alerts": 12,
      "saved_searches": 28
    },
    {
      "name": "itsi",
      "dashboards": 8,
      "alerts": 6,
      "saved_searches": 14
    }
  ],

  "usage_intelligence": {
    "summary": {
      "dashboards_never_viewed": 12,
      "alerts_never_fired": 8,
      "users_inactive": 5,
      "alerts_with_failures": 2
    },
    "volume": {
      "avg_daily_gb": 45.7,
      "peak_daily_gb": 78.3,
      "total_period_gb": 1371.2,
      "top_indexes_by_volume": [
        {"index": "main", "total_gb": 456.2},
        {"index": "security", "total_gb": 312.8},
        {"index": "web_logs", "total_gb": 198.4}
      ],
      "top_sourcetypes_by_volume": [
        {"sourcetype": "access_combined", "total_gb": 234.5},
        {"sourcetype": "syslog", "total_gb": 187.3}
      ]
    },
    "prioritization": {
      "top_dashboards": [
        {"dashboard": "security_overview", "views": 1523},
        {"dashboard": "executive_summary", "views": 892}
      ],
      "top_users": [
        {"user": "admin", "searches": 4521},
        {"user": "analyst1", "searches": 2134}
      ],
      "top_alerts": [
        {"alert": "High CPU Alert", "fires": 234},
        {"alert": "Failed Login", "fires": 156}
      ]
    },
    "elimination_candidates": {
      "dashboards_never_viewed_count": 12,
      "alerts_never_fired_count": 8,
      "note": "See _usage_analytics/ for full lists of candidates"
    }
  }
}
```

This manifest enables DMA to:
- **Prioritize migration** based on actual usage data
- **Identify elimination candidates** (unused dashboards/alerts)
- **Estimate data volume** for Dynatrace ingestion planning
- **Map applications** to their respective assets

---

*For Splunk Enterprise (on-premises), use `dma-splunk-export.sh` instead.*
