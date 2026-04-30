# DMA Splunk Cloud Export — Detailed Guide

**Version**: 4.6.2
**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Cloud Export Specification](SPLUNK-CLOUD-EXPORT-SPECIFICATION.md) | [Manual Usage Queries](MANUAL-USAGE-QUERIES.md) | [Export Schema](EXPORT-SCHEMA.md)

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Table of Contents

- [What's New in v4.6.0](#whats-new-in-v460)
- [Previous Version Changes](#previous-version-changes)
- [Scripts Overview](#scripts-overview)
- [Prerequisites](#prerequisites)
- [Required Permissions (CRITICAL)](#required-permissions-critical)
- [Token Creation Walkthrough](#token-creation-walkthrough)
- [Connectivity Verification](#connectivity-verification)
- [Test Access (Pre-Flight Check)](#test-access-pre-flight-check)
- [Running the Export](#running-the-export)
- [Command-Line Reference](#command-line-reference)
- [Interactive vs Non-Interactive Mode](#interactive-vs-non-interactive-mode)
- [What Is Collected](#what-is-collected)
- [Data Anonymization and Archives](#data-anonymization-and-archives)
- [Resume Collection](#resume-collection)
- [Re-Anonymize an Existing Archive](#re-anonymize-an-existing-archive)
- [Proxy Support](#proxy-support)
- [Debug Mode](#debug-mode)
- [Enterprise Resilience Configuration](#enterprise-resilience-configuration)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)
- [FAQ](#faq)
- [Where to Upload the Archive](#where-to-upload-the-archive)

---

## What's New

> **Note on version history.** The Cloud scripts (`dma-splunk-cloud-export.sh` and `dma-splunk-cloud-export.ps1`) and the Enterprise script (`dma-splunk-export.sh`) are versioned independently. Cloud is currently at **v4.6.2** (last bump: `search`-app inclusion). Enterprise is at **v4.6.4** with its own Enterprise-specific fixes — see [README-SPLUNK-ENTERPRISE.md](README-SPLUNK-ENTERPRISE.md). Customers running the Cloud scripts can ignore Enterprise changelog references to v4.6.3 (user-namespace dashboard de-dup — Cloud's REST collection doesn't have that failure mode) and v4.6.4 (`eai:acl.*` `where`-clause quoting — Cloud's current call sites use plain `app` field names so they don't trip the parser, though the helper has been hardened defensively).

### v4.6.2 (April 2026)

- **`search` app is now exported.** Previously excluded as a "system app," but customers frequently create dashboards and saved searches in it. One customer had 674 dashboards (30% of total) silently dropped because the `search` app was in the skip list.

### v4.6.1 (April 2026)

- **Per-app and per-dashboard resume for `--resume-collect`.** Previously, if the script was interrupted mid-phase, resume would skip the entire phase if even one app had data. Now each app and dashboard is checked individually — only truly incomplete items are re-collected.
- **Per-app resume for alerts and knowledge objects.** Apps with cached `savedsearches.json` or `macros.json` are skipped individually on resume rather than re-querying everything.
- **OS-level timeout backstop for API calls.** Some Splunk Cloud Victoria stacks with TLS 1.3+SNI don't honor curl's `--max-time`. The script now wraps curl with `timeout`/`gtimeout` as a hard kill at `API_TIMEOUT + 30s`.
- **`--resume-collect` with `--usage` now forces analytics re-collection.** Clears usage checkpoints to prevent stale data from a prior interrupted run.

### v4.6.0

### Stripped Usage Queries — Global Aggregates Only

The `collect_usage_analytics` phase has been completely reworked. Detailed per-user, per-dashboard, and per-app usage queries have been **removed**. The script now collects only:

- **Ownership data** via REST API (no search jobs) — `dashboard_ownership.json`, `alert_ownership.json`, `ownership_summary.json`
- **REST metadata** — `saved_searches_all.json`, `recent_searches.json`, `kvstore_stats.json`
- **Summary data** — `index_volume_summary.json`, `index_event_counts_daily.json`

All Explorer-facing usage data comes from the **6 global aggregate queries** in `collect_app_analytics`. These queries run once (not per-app) and produce all the usage data the DMA Explorer needs:

| File | Index | Explorer Tab |
|------|-------|-------------|
| `dashboard_views_global.json` | `_audit` | Dashboards — view counts per dashboard |
| `user_activity_global.json` | `_audit` | (supplementary) — searches per user per app |
| `search_patterns_global.json` | `_audit` | (supplementary) — search type breakdown |
| `index_volume_summary.json` | `_internal` | Indexes — daily ingestion GB per index |
| `index_event_counts_daily.json` | `_internal` | Indexes — event counts per index per day |
| `alert_firing_global.json` | `_internal` | Alerts — execution stats per alert |

### Default Changes in v4.6.0

| Setting | Previous (v4.5.8) | New (v4.6.0) |
|---------|-------------------|-------------|
| `COLLECT_USAGE` | `false` (opt-in) | `true` (on by default) |
| `USAGE_PERIOD` | `7d` | `30d` |

Usage analytics is now collected by default. Use `--no-usage` to disable.

---

## Previous Version Changes

### v4.5.8

- **Auto-detect token prefix** (Bearer vs Splunk) via probe loop against `/services/authentication/current-context`
- **Async search dispatch** (`exec_mode=normal`) replaces blocking mode — max 1 hour per query with adaptive polling (5s, increasing to 30s cap)
- **6 global aggregate analytics** replace per-app query loops (for 90 apps: 630 jobs reduced to 6)
- **`--test-access`** pre-flight check — tests 9 API categories, then exits without exporting
- **`--remask FILE`** re-anonymize an existing archive without connecting to Splunk
- **`--analytics-period N`** configurable analytics time window (7d, 30d, 90d)
- **`--skip-internal`** skip `_audit`/`_internal` index searches for restricted accounts
- **Expanded RBAC** — capabilities, SAML config, SAML groups, LDAP groups, LDAP config
- **Progressive analytics checkpointing** — each of the 6 global queries saves a checkpoint on completion; interrupted exports resume mid-way

### v4.3.0

- **Resume Collection** (`--resume-collect`): Resume interrupted exports from `.tar.gz` archive
- **12-Hour Max Runtime**: `MAX_TOTAL_TIME=43200` (up from 4 hours)
- **PowerShell Edition**: `dma-splunk-cloud-export.ps1` with zero external dependencies
- **Proxy Support** (`--proxy` / `-Proxy`): Route all connections through corporate proxy

### v4.2.4

- **Two-Archive Anonymization**: Original + `_masked` copy for safe sharing
- **RBAC/Usage OFF by default**: Use `--rbac` / `--usage` to enable
- **Faster defaults**: Batch size 250, API delay 50ms

### v4.2.0

- **App-Centric Dashboard Structure (v2)**: `{AppName}/dashboards/classic/` and `{AppName}/dashboards/studio/`
- **Manifest Schema v4.0**: `archive_structure_version: "v2"`

---

## Scripts Overview

There are **two** Cloud export scripts. Both produce the same archive format and accept the same flags (with naming conventions adjusted for PowerShell).

| Script | Platform | Notes |
|--------|----------|-------|
| `dma-splunk-cloud-export.sh` | Bash (Linux / macOS / WSL) | Primary Cloud script. Requires curl and Python 3. |
| `dma-splunk-cloud-export.ps1` | PowerShell 5.1+ (Windows) | Full parity with the Bash script. Zero external dependencies. |

Choose whichever matches the machine you are running from. Both scripts are REST API only and can be run from any machine with network access to the Splunk Cloud management port.

---

## Prerequisites

### Platform Requirements

| Requirement | Bash Script | PowerShell Script |
|-------------|-------------|-------------------|
| **Platform** | Linux, macOS, or WSL | Windows 10 1803+ |
| **Shell** | bash 3.2+ | PowerShell 5.1+ or 7+ |
| **External dependencies** | curl, Python 3, tar | **None** (zero external deps) |
| **Disk space** | 500 MB+ free | 500 MB+ free |
| **Network** | HTTPS to `your-stack.splunkcloud.com:8089` | HTTPS to `your-stack.splunkcloud.com:8089` |
| **Credentials** | API token (recommended) or username/password | API token (recommended) or username/password |

### Where to Run

The Cloud scripts run **anywhere** with network access to the Splunk Cloud management port (8089). They do not need to be on the Splunk infrastructure:

- Your laptop
- A jump host or bastion
- A CI/CD runner
- Any machine that can reach `your-stack.splunkcloud.com:8089` over HTTPS

### Supported Splunk Cloud Types

| Cloud Type | Supported |
|------------|-----------|
| Splunk Cloud Classic | Yes |
| Splunk Cloud Victoria Experience | Yes |
| Splunk Cloud on AWS | Yes |
| Splunk Cloud on GCP | Yes |
| Splunk Cloud on Azure | Yes |

---

## Required Permissions (CRITICAL)

> **Insufficient permissions are the #1 cause of failed or incomplete exports.** Many API responses silently return empty results when permissions are missing — the export will appear to complete normally but will be missing critical data. Read this section carefully before running anything.

### Recommended: Use the `sc_admin` Role

Splunk Cloud provides a built-in role called `sc_admin` that has all the capabilities needed for a complete export. This is the **easiest and most reliable** approach.

Create a user with `sc_admin`, generate an API token for that user, and use that token for the export.

### Minimum Required Capabilities

If `sc_admin` is not available, the user's role **must** include all of the following:

| Capability | Why It Is Required | What Fails Without It |
|------------|-------------------|----------------------|
| `admin_all_objects` | Read dashboards, saved searches, and alerts across **all** apps | Cannot list apps, dashboards, saved searches in other apps — export sees only assets owned by the user |
| `list_settings` | Read server configuration and system settings | Cannot read server settings or configurations |
| `rest_properties_get` | Execute REST API calls for configs, knowledge objects, and metadata | API calls return 403 Forbidden |
| `search` | Run SPL search jobs (required for usage analytics against `_audit` and `_internal`) | All usage analytics queries fail |
| `list_users` | Enumerate users and roles (required with `--rbac`) | `--rbac` returns empty user list |
| `list_roles` | List roles and capabilities (required with `--rbac`) | `--rbac` returns empty role list |
| `list_indexes` | Read index metadata, retention policies, and sourcetype lists | Cannot collect index information |
| `schedule_search` | Dispatch async search jobs for analytics | Some analytics queries fail |

### Internal Index Access (for Usage Analytics)

When usage analytics is enabled (the default in v4.6.0), the user also needs **search-time access** to these internal indexes:

| Index | What It Provides | Without It |
|-------|-----------------|------------|
| `_audit` | Dashboard view counts, user activity, search patterns | No usage data — the Explorer's Dashboards, Alerts, and Indexes tabs will show zero usage |
| `_internal` | Alert firing stats, ingestion volume per index | No alert execution data, no volume estimates for Grail planning |

> **`_audit` and `_internal` access is commonly restricted in Splunk Cloud.** This is the single most frequent reason exports appear "empty" in the DMA Explorer. If your Splunk Cloud admin cannot grant access to these indexes, use `--skip-internal` to collect what you can, but understand that usage-based prioritization data will be missing.

### Custom Role Setup (If Not Using sc_admin)

1. Go to **Settings > Access Controls > Roles**
2. Click **New Role**
3. Name: `dma_export_role`, Default app: `search`
4. Under **Capabilities**, enable:

   **Core (REQUIRED):**
   ```
   admin_all_objects
   list_settings
   rest_properties_get
   ```

   **Search (REQUIRED for usage analytics):**
   ```
   search
   schedule_search
   ```

   **RBAC (REQUIRED for --rbac):**
   ```
   list_users
   list_roles
   ```

   **Indexes (REQUIRED for index collection):**
   ```
   list_indexes
   ```

5. Under **Indexes searched by default**, add: `_internal`, `_audit`
6. Under **Indexes**, set: Select all indexes or `*`
7. **Inherit from**: Select `user` as the base role
8. Click **Save**
9. Assign this role to your export user

### Minimum Permissions Summary

| Collection Type | Flag | Required Capabilities | Required Index Access |
|----------------|------|----------------------|----------------------|
| **Basic Export** (apps, dashboards, alerts, configs) | (default) | `admin_all_objects`, `list_settings`, `rest_properties_get` | None |
| **Usage Analytics** | `--usage` (default ON) | Above + `search`, `schedule_search` | `_internal`, `_audit` |
| **RBAC/Users** | `--rbac` | Above + `list_users`, `list_roles` | None |
| **Index Metadata** | (default ON) | Above + `list_indexes` | None |
| **Full Export** | `--rbac` | All of the above | `_internal`, `_audit` |

### Why a Regular User Account Will Not Work

Regular Splunk users typically:
- Can only see their own apps and objects (not `admin_all_objects`)
- Cannot list other users (`list_users` not granted)
- Cannot query `_internal` or `_audit` indexes
- Cannot access REST endpoints for system configuration

The export script needs to see **everything** in your Splunk environment to provide a complete migration assessment.

---

## Token Creation Walkthrough

### Option A: API Token (Recommended)

1. **Log into Splunk Cloud** as an admin user:
   ```
   https://your-stack.splunkcloud.com
   ```

2. **Create a dedicated export user** (or use an existing admin):
   - Go to **Settings > Access Controls > Users**
   - Click **New User**
   - Username: `dma_export_user` (or any name)
   - Set a strong password
   - **Assign Roles**: Select `sc_admin` (or your custom `dma_export_role`)
   - Click **Save**

3. **Log in as the export user**, then go to **Settings > Tokens**

4. Click **New Token**:
   - Name: `DMA Export Token`
   - Expiration: 7 days (or as appropriate)
   - Click **Create**
   - **COPY THE TOKEN IMMEDIATELY** — it is only shown once

5. **Store the token securely** — you will pass it to the export script via `--token` or an environment variable

### Option B: Username/Password

If token creation is not available, you can authenticate with username and password directly. However:
- If MFA is enabled, you may need to use a token instead
- Tokens are preferred because they can be scoped and expired independently

### Token Authentication: Bearer vs Splunk Prefix

Splunk Cloud uses two different authorization header formats depending on how the token was created:

| Token Type | Header Format |
|-----------|---------------|
| Tokens from **Settings > Tokens** (UI) | `Authorization: Splunk <token>` |
| JWT / OAuth2 tokens | `Authorization: Bearer <token>` |

You do **not** need to know which format your token uses. The script probes `/services/authentication/current-context` with both `Bearer` and `Splunk` prefixes and automatically uses whichever succeeds. If neither works, authentication has failed (wrong token, expired, or revoked).

---

## Connectivity Verification

Before running the export, verify you can reach the Splunk Cloud REST API management port.

### Finding Your Stack URL

Your Splunk Cloud stack URL is the address you use to access the Splunk Cloud web UI:

```
https://<stack-name>.splunkcloud.com
```

Examples: `acme-corp.splunkcloud.com`, `mycompany-prod.splunkcloud.com`

### Testing Connectivity

```bash
# Test if you can reach the REST API
curl -I "https://your-stack.splunkcloud.com:8089/services/server/info"

# Expected: HTTP/2 401 (Unauthorized but reachable)
# If you get connection refused or timeout, check network/firewall
```

```powershell
# PowerShell equivalent
try {
    Invoke-WebRequest -Uri "https://your-stack.splunkcloud.com:8089/services/server/info" -Method Head
} catch {
    $_.Exception.Response.StatusCode  # Should be 401 (Unauthorized)
}
```

### If Connectivity Fails

- **Corporate firewall**: Confirm outbound HTTPS to port 8089 is allowed
- **VPN**: Some organizations require VPN for Splunk Cloud API access
- **IP allowlist**: Some Splunk Cloud instances require your source IP to be allowlisted — check with your Splunk Cloud admin
- **Proxy**: If you need a proxy, use `--proxy` (see [Proxy Support](#proxy-support))

### Adding Your IP to the Allowlist (If Required)

1. Find your public IP: `curl ifconfig.me`
2. Ask your Splunk Cloud admin to add it to the IP allowlist for port 8089

---

## Test Access (Pre-Flight Check)

**Always run `--test-access` before a full export.** This pre-flight check tests 9 API categories and reports exactly what will and will not work — without writing any export data or creating search jobs.

### Running the Test

```bash
# Bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --test-access
```

```powershell
# PowerShell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -TestAccess
```

To also test usage analytics and RBAC access, add those flags:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --usage --rbac \
  --test-access
```

### Example Output

```
  +----------------------------------+--------+--------------------+
  |            ACCESS TEST RESULTS                                 |
  +----------------------------------+--------+--------------------+
  | Category                         | Status | Detail             |
  +----------------------------------+--------+--------------------+
  | System Info                      |  PASS  | Splunk v9.3.2411   |
  | Configurations (indexes)         |  PASS  | 12 entries         |
  | Dashboards (myapp)               |  PASS  | 47 found           |
  | Saved Searches / Alerts (myapp)  |  PASS  | 83 found           |
  | RBAC (users/roles)               |  PASS  | 24 users, 8 roles  |
  | Knowledge Objects (myapp)        |  PASS  | macros, props, ... |
  | App Analytics (_audit)           |  PASS  | 3 result(s)        |
  | Usage Analytics (_internal)      |  FAIL  | _internal denied   |
  | Indexes                          |  PASS  | 12 found           |
  +----------------------------------+--------+--------------------+
```

### How to Read the Results

- **PASS** — This category will collect data normally.
- **FAIL** on `_audit` or `_internal` — Usage analytics will be incomplete. Ask your Splunk admin to grant search access to these indexes, or accept the gap.
- **FAIL** on `Dashboards` or `Saved Searches` — The user likely lacks `admin_all_objects`. This is a **critical** problem — the export will be mostly empty.
- **SKIP** — The category was not requested (e.g., RBAC shows SKIP if you did not pass `--rbac`).

> **If `--test-access` shows FAIL on Dashboards, Saved Searches, or System Info, stop and fix permissions before proceeding.** Running a full export with these failures will produce an archive the DMA Server cannot use.

### Verifying Permissions via SPL (Alternative)

You can also verify permissions directly in the Splunk Cloud search bar:

```spl
| rest /services/authentication/current-context
| table username, roles
```

```spl
| rest /services/apps/local | stats count
```

```spl
| rest /servicesNS/-/-/saved/searches | stats count by eai:acl.app
```

```spl
index=_audit action=search | head 1
```

```spl
index=_internal sourcetype=splunkd | head 1
```

---

## Running the Export

### Quick Start (Bash)

```bash
# Make executable (first time only)
chmod +x dma-splunk-cloud-export.sh

# Interactive mode — prompts for everything
./dma-splunk-cloud-export.sh

# Non-interactive mode — all parameters on command line
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN"
```

### Quick Start (PowerShell)

```powershell
# Interactive mode
.\dma-splunk-cloud-export.ps1

# Non-interactive mode
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN
```

### Full Export with All Options

```bash
# Bash — full export with RBAC, usage analytics, 30-day window
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --rbac \
  --analytics-period 30d
```

```powershell
# PowerShell equivalent
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Rbac `
  -AnalyticsPeriod "30d"
```

### Scoped Export (Specific Apps Only)

For large environments, reduce export time by targeting specific apps:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --apps "myapp,otherapp" \
  --scoped
```

When `--apps` is used without `--all-apps`, the `--scoped` flag limits all collections (including analytics) to the selected apps only.

---

## Command-Line Reference

### Connection and Authentication

| Bash | PowerShell | Description | Default |
|------|------------|-------------|---------|
| `--stack URL` | `-Stack URL` | Splunk Cloud stack URL (e.g., `acme-corp.splunkcloud.com`) | (prompted) |
| `--token TOKEN` | `-Token TOKEN` | API token for authentication (recommended) | (prompted) |
| `--user USER` | `-User USER` | Username (alternative to token) | (prompted) |
| `--password PASS` | `-Password PASS` | Password (used with `--user`) | (prompted) |
| `--proxy URL` | `-Proxy URL` | Route all connections through HTTP proxy | (none) |

### Scope and Data Selection

| Bash | PowerShell | Description | Default |
|------|------------|-------------|---------|
| `--all-apps` | `-AllApps` | Export all applications | `true` |
| `--apps "a,b,c"` | `-Apps "a,b,c"` | Export only these apps (comma-separated) | (all) |
| `--scoped` | `-Scoped` | Scope analytics to selected apps only | `false` |
| `--rbac` | `-Rbac` | Enable RBAC/users collection | `false` |
| `--no-rbac` | `-NoRbac` | Disable RBAC collection (legacy flag) | (already off) |
| `--usage` | `-Usage` | Enable usage analytics | `true` |
| `--no-usage` | `-NoUsage` | Disable usage analytics | (already on) |
| `--analytics-period N` | `-AnalyticsPeriod N` | Analytics time window (e.g., `7d`, `30d`, `90d`) | `30d` |
| `--skip-internal` | `-SkipInternal` | Skip `_audit`/`_internal` index searches | `false` |
| `--output DIR` | `-Output DIR` | Output directory for the export | `.` (current dir) |

### Special Modes

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--test-access` | `-TestAccess` | Pre-flight permission check — test 9 API categories, then exit. **Always run this first.** |
| `--remask FILE` | `-Remask FILE` | Re-anonymize an existing archive. No Splunk connection needed. |
| `--resume-collect FILE` | `-ResumeCollect FILE` | Resume an interrupted export from a `.tar.gz` archive. |

### Operational

| Bash | PowerShell | Description |
|------|------------|-------------|
| `-d` / `--debug` | `-Debug_Mode` | Verbose debug logging (writes `_export_debug.log`) |
| N/A | `-SkipAnonymization` | Disable data anonymization (Bash controls this interactively) |
| N/A | `-NonInteractive` | Explicitly force non-interactive mode (Bash auto-detects when stack + auth are provided) |
| `--help` | `-ShowHelp` | Show help and exit |
| N/A | `-Version` | Display version and exit |

### Note on Non-Interactive Detection

The Bash script does not have an explicit `--yes` flag. It automatically enters non-interactive mode when both `--stack` and authentication (`--token` or `--user`/`--password`) are provided on the command line. The PowerShell script has an explicit `-NonInteractive` switch for the same purpose.

---

## Interactive vs Non-Interactive Mode

### Interactive Mode

When run without CLI arguments (or without both `--stack` and `--token`), the script walks you through:

1. **Welcome screen** — version display and continue prompt
2. **Pre-flight checklist** — system dependency verification (bash, curl, Python)
3. **Stack URL** — enter your Splunk Cloud address; script tests DNS, TCP 8089, and TLS
4. **Authentication** — choose token or username/password; credentials are verified against the API
5. **Capability check** — warns if recommended permissions are missing
6. **Application selection** — export all apps or pick specific ones
7. **Data category toggles** — enable/disable configs, dashboards, alerts, RBAC, usage, indexes, anonymization
8. **Analytics period** (if usage enabled) — choose 7d, 30d, 90d, or 365d
9. **Collection** — progress displayed per category with progress bars
10. **Anonymization** — creates the `_masked` archive (unless disabled)
11. **Summary** — statistics table with counts, timing, and any errors

### Non-Interactive Mode

When all required parameters are on the command line (Bash: `--stack` + `--token`; PowerShell: `-Stack` + `-Token` + `-NonInteractive`), the script runs without any prompts. All defaults apply unless overridden by flags.

```bash
# Bash — automatically non-interactive
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --rbac
```

```powershell
# PowerShell — explicit non-interactive
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Rbac -NonInteractive
```

### Typical Runtimes

| Environment | Without `--usage` | With `--usage` (default) |
|-------------|-------------------|--------------------------|
| Small (10 apps, 200 dashboards) | 2-5 minutes | 5-15 minutes |
| Medium (50 apps, 1000 dashboards) | 10-20 minutes | 20-45 minutes |
| Large (200+ apps, 5000+ dashboards) | 30-60 minutes | 1-3 hours |

Analytics searches use async dispatch with up to 1 hour per query, so large `_audit` indexes no longer cause timeouts.

---

## What Is Collected

### Always Collected (defaults ON)

| Category | Description | Migration Use |
|----------|-------------|---------------|
| **Dashboards** | Classic XML + Dashboard Studio v2 JSON, per app | Visual conversion to Dynatrace dashboards/notebooks |
| **Alerts and Saved Searches** | All definitions with SPL queries and schedules | SPL-to-DQL conversion, alert migration |
| **Configurations** | props.conf, transforms.conf, indexes.conf, inputs.conf (reconstructed from REST) | OpenPipeline generation, field extractions |
| **Index Statistics** | Index metadata, sizes, retention policies, sourcetypes | Dynatrace Grail bucket planning, capacity estimation |
| **Knowledge Objects** | Macros, eventtypes, tags, lookups, field extractions | Completeness check for SPL conversion |

### Usage Analytics (default ON in v4.6.0)

When `--usage` is enabled (the default), 6 global aggregate queries run against `_audit` and `_internal`:

| File | Index | Explorer Tab |
|------|-------|-------------|
| `dashboard_views_global.json` | `_audit` | Dashboards — view counts per dashboard |
| `user_activity_global.json` | `_audit` | (supplementary) — searches per user per app |
| `search_patterns_global.json` | `_audit` | (supplementary) — search type breakdown |
| `index_volume_summary.json` | `_internal` | Indexes — daily ingestion GB per index |
| `index_event_counts_daily.json` | `_internal` | Indexes — event counts per index per day |
| `alert_firing_global.json` | `_internal` | Alerts — execution stats per alert |

Additionally, **ownership data** is collected via REST API (no search jobs required):

| File | Method | Explorer Tab |
|------|--------|-------------|
| `dashboard_ownership.json` | REST API | Dashboards — owner column |
| `alert_ownership.json` | REST API | Alerts — owner column |
| `ownership_summary.json` | REST API | (supplementary) |

REST metadata files also collected: `saved_searches_all.json`, `recent_searches.json`, `kvstore_stats.json`.

### Opt-In (defaults OFF)

| Category | Flag | Description |
|----------|------|-------------|
| **Users and RBAC** | `--rbac` / `-Rbac` | Users, roles, capabilities, LDAP/SAML config. No passwords collected. |

### What Is NOT Collected

- User passwords or password hashes
- API tokens or session keys
- Actual log/event data (only metadata and structure)
- SSL certificates or private keys
- Raw config files (REST reconstruction is used instead)
- `$SPLUNK_HOME` filesystem (Cloud has no filesystem access)

---

## Data Anonymization and Archives

When anonymization is enabled (the default), the script creates **two archives**:

| Archive | Contents | Purpose |
|---------|----------|---------|
| `dma_cloud_export_<stack>_<YYYYMMDD_HHMMSS>.tar.gz` | Original, untouched data | Reference copy — keep internally |
| `dma_cloud_export_<stack>_<YYYYMMDD_HHMMSS>_masked.tar.gz` | Anonymized copy | Safe to share with Dynatrace or externally |

### What Gets Anonymized

Anonymization applies deterministic masking:

- **Emails**: `user@corp.com` becomes `anon######@anon.dma.local`
- **Hostnames**: `splunk-idx01.corp.com` becomes `host-########.anon.local`
- **IPv4 addresses**: Replaced with `[IP-REDACTED]`
- **IPv6 addresses**: Replaced with `[IPv6-REDACTED]`

Deterministic means the same input always produces the same output — relationships between objects are preserved in the masked copy.

### Which Archive to Use

- **Upload the `_masked` archive** when sharing externally (with Dynatrace, consultants, etc.)
- **Upload the original archive** for internal analysis on your own DMA Server — you get real names, emails, and hostnames in the Explorer

---

## Resume Collection

If an export is interrupted (network drop, Ctrl+C, timeout), you can resume it without starting over.

### How It Works

The script extracts the partial archive, detects which phases completed via checkpoint files, and continues from where it stopped. Per-query checkpointing means even individual analytics searches resume mid-way.

### Resume Examples

```bash
# Bash — resume a previous incomplete export
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --resume-collect ./dma_cloud_export_acme-corp_20260401_143022.tar.gz

# Resume AND add RBAC that was not collected originally
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --resume-collect ./dma_cloud_export_acme-corp_20260401_143022.tar.gz \
  --rbac
```

```powershell
# PowerShell — resume
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -ResumeCollect ".\dma_cloud_export_acme-corp_20260401_143022.tar.gz"

# Resume AND add RBAC
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -ResumeCollect ".\dma_cloud_export_acme-corp_20260401_143022.tar.gz" `
  -Rbac
```

### Versioned Output

When resuming, the script creates a versioned archive to avoid overwriting the original:

- Original: `dma_cloud_export_acme-corp_20260401_143022.tar.gz`
- First resume: `dma_cloud_export_acme-corp_20260401_143022-v1.tar.gz`
- Second resume: `dma_cloud_export_acme-corp_20260401_143022-v2.tar.gz`

### What Gets Skipped vs Re-Collected

| Data Type | Skipped When... |
|-----------|-----------------|
| Dashboards | App already has dashboard files |
| Saved Searches | App already has `savedsearches.json` |
| Knowledge Objects | App has `macros.json` + `props.json` + `transforms.json` |
| Configs | `_configs/` directory exists |
| RBAC | `users.json` + `roles.json` exist |
| Usage Analytics | `usage_analytics/` has 2+ files |
| Indexes | `indexes.json` exists |

---

## Re-Anonymize an Existing Archive

If you need to regenerate the masked copy (e.g., after sharing rules change), use `--remask`:

```bash
./dma-splunk-cloud-export.sh --remask dma_cloud_export_acme-corp_20260401_143022.tar.gz
```

```powershell
.\dma-splunk-cloud-export.ps1 -Remask ".\dma_cloud_export_acme-corp_20260401_143022.tar.gz"
```

No Splunk connection is needed — the script extracts, anonymizes, and repacks locally. A new `_masked.tar.gz` is created alongside the original.

---

## Proxy Support

If your network requires a proxy to reach the Splunk Cloud API, pass it with `--proxy`:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --proxy "http://proxy.corp.com:8080"
```

```powershell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Proxy "http://proxy.corp.com:8080"
```

The proxy is used for all HTTPS connections to the Splunk Cloud management API. The Bash script passes the proxy via `curl -x`; the PowerShell script uses `Invoke-RestMethod -Proxy`.

---

## Debug Mode

Add `--debug` (Bash) or `-Debug_Mode` (PowerShell) for detailed diagnostics:

```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --debug
```

Debug mode provides:

- **Console output**: Color-coded messages by category (API, SEARCH, TIMING, ERROR, WARN, AUTH)
- **Debug log file**: `_export_debug.log` inside the archive
- **API call tracking**: Every REST API call with endpoint, HTTP status, response size, and duration
- **Auth tracing**: Token probe responses and final header format
- **Search jobs**: SID dispatch, poll states, completion time

---

## Enterprise Resilience Configuration

The Cloud scripts include enterprise-scale features for environments with 4000+ dashboards and 10K+ alerts.

### Default Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `BATCH_SIZE` | 250 | Items per API request |
| `API_DELAY` | 50ms | Delay between API calls |
| `API_TIMEOUT` | 120s | Per-request timeout |
| `CONNECT_TIMEOUT` | 30s | Initial connection timeout |
| `MAX_TOTAL_TIME` | 43200s (12 hours) | Maximum total script runtime |
| `MAX_RETRIES` | 3 | Retry attempts with exponential backoff |
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume capability |

### Environment Variable Overrides

For very large environments, tune via environment variables:

```bash
# Large environment (5000+ dashboards) — smaller batches, longer timeout
BATCH_SIZE=50 API_TIMEOUT=180 ./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN"
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No applications found!` | Token lacks `admin_all_objects` | Use `sc_admin` role, or add capability to the user's role |
| `Token authentication failed` | Wrong token, expired, or revoked | Regenerate the token in Splunk Cloud under Settings > Tokens |
| Export completes but Explorer shows no usage data | `_audit` / `_internal` access denied | Run `--test-access` to confirm; request index access from Splunk admin |
| Analytics searches timeout | Very large `_audit` index | Reduce `--analytics-period 7d`; or use `--apps "app1,app2" --scoped` |
| `Rate limited (429)` | Too many API calls in sequence | Script auto-retries with exponential backoff — no action needed |
| `_audit` / `_internal` access denied | Splunk Cloud restricts these indexes by default | Use `--skip-internal` to collect what you can |
| Export takes hours | Large environment with `--usage` | Scope to key apps: `--apps "app1,app2" --scoped` |
| PowerShell: `Execution Policy` error | Script execution disabled | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |

### Connection Errors

| Error | Solutions |
|-------|----------|
| `curl: (7) Failed to connect ... port 8089` | Check VPN, verify stack URL, check firewall rules, verify Splunk Cloud IP allowlist |
| `HTTP 401 Unauthorized` | Verify credentials, check if token expired, create a new token |
| `HTTP 403 Forbidden` | User/token lacks required capabilities — add `admin_all_objects`, check role |
| `HTTP 429 Too Many Requests` | Script retries automatically; if persistent, wait 5 minutes |
| `SSL certificate problem` | Update CA certificates; script uses `-k` flag as fallback |

---

## Security Best Practices

### Token Security

- Use API tokens instead of passwords
- Set appropriate token expiration (7-30 days)
- Do not share tokens in chat, email, or tickets
- Use environment variables instead of command-line arguments when possible:
  ```bash
  export SPLUNK_TOKEN="your-token"
  ./dma-splunk-cloud-export.sh --stack acme.splunkcloud.com --token "$SPLUNK_TOKEN"
  ```
- Delete the token after the export is complete
- Do not commit tokens to version control

### Export File Security

- The export contains sensitive metadata (dashboard definitions, alert logic, user names)
- Transfer securely (SCP, SFTP, or encrypted channel)
- Use the `_masked` archive when sharing outside your organization
- Delete local copies after uploading to the DMA Server

---

## FAQ

**Q: Can I run this on my laptop?**
Yes. The Cloud scripts are designed to run from any machine with network access to your Splunk Cloud instance.

**Q: Do I need SSH access to anything?**
No. The Cloud scripts are 100% REST API based. No SSH required. (SSH is only needed for the Enterprise on-prem script.)

**Q: Will this work with MFA enabled?**
Use an API token. MFA typically does not apply to API token authentication.

**Q: How long does the export take?**
5-60 minutes depending on environment size and whether usage analytics is enabled. Very large environments with `--usage` may take 1-3 hours.

**Q: Can I schedule this to run automatically?**
Yes. Use non-interactive mode:
```bash
./dma-splunk-cloud-export.sh --stack acme.splunkcloud.com --token "$TOKEN" --output /exports/
```

**Q: My previous export timed out. Do I need to start over?**
No. Use `--resume-collect` to pass your previous `.tar.gz`. The script detects what was already collected and fills in the gaps.

**Q: What if I have multiple Splunk Cloud stacks?**
Run the script once per stack. Each export is labeled with the stack name.

**Q: Can I run this on Windows?**
Yes. Use `dma-splunk-cloud-export.ps1` which requires only PowerShell 5.1+ and has zero external dependencies.

---

## Where to Upload the Archive

After the export completes, upload the `.tar.gz` archive:

- **DMA Curator Server** — migration planning, reporting, and team collaboration (recommended for all exports)
- **DMA Splunk App** — ad-hoc migration analysis (suitable for smaller archives)

Use the `_masked` variant when sharing outside your organization.

---

*For Splunk Enterprise (on-premises), see [README-SPLUNK-ENTERPRISE.md](README-SPLUNK-ENTERPRISE.md) and use `dma-splunk-export.sh` instead.*
