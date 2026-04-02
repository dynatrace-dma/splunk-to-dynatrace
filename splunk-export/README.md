# DMA Splunk Export Scripts

**Version**: 4.5.8 (Cloud) / 4.4.0 (Enterprise)
**Last Updated**: March 2026

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Table of Contents

- [1. Purpose](#1-purpose)
- [2. What Is Collected?](#2-what-is-collected)
- [3. Prerequisites, Permissions, Connectivity](#3-prerequisites-permissions-connectivity)
- [4. Running the Script](#4-running-the-script)
- [5. What to Expect](#5-what-to-expect)
- [6. Troubleshooting](#6-troubleshooting)
- [7. Version History](#7-version-history)

---

## 1. Purpose

These scripts extract configuration data, dashboards, alerts, and usage analytics from Splunk environments to enable migration planning with the **Dynatrace Migration Assistant (DMA)**.

The export archive they produce is the starting point for every Splunk-to-Dynatrace migration. It feeds into the **DMA Curator Server** for migration planning and reporting. For smaller exports, the archive can also be uploaded directly to the **Splunk App** for ad-hoc migration analysis.

### Available Scripts

| Script | Target | Platform | Version |
|--------|--------|----------|---------|
| `dma-splunk-cloud-export_beta.sh` | Splunk Cloud | Bash (Linux/macOS) | 4.5.8 |
| `dma-splunk-cloud-export.ps1` | Splunk Cloud | PowerShell (Windows) | 4.5.8 |
| `dma-splunk-export.sh` | Splunk Enterprise | Bash (Linux) | 4.4.0 |

### Cloud vs Enterprise: Key Differences

| | Enterprise | Cloud |
|--|-----------|-------|
| **Where to run** | ON the Splunk Search Head | ANYWHERE (your laptop, jump host, CI runner) |
| **Access method** | File system + REST API | REST API only |
| **What you need** | SSH access + `splunk` user | Network access to port 8089 + API token |
| **Config collection** | Direct file reads | Reconstructed from REST API |
| **PowerShell option** | No | Yes (full parity with Bash) |

---

## 2. What Is Collected?

All scripts collect the same categories of data. The archive format is identical regardless of which script produces it.

### Always Collected (defaults ON)

| Category | Description | Migration Use |
|----------|-------------|---------------|
| **Dashboards** | Classic XML + Dashboard Studio v2 JSON, per app | Visual conversion to Dynatrace dashboards/apps |
| **Alerts & Saved Searches** | All definitions with SPL queries and schedules | SPL-to-DQL conversion, alert migration |
| **Configurations** | props.conf, transforms.conf, indexes.conf, inputs.conf | OpenPipeline generation, field extractions |
| **Index Statistics** | Index metadata, sizes, retention policies, sourcetypes | Dynatrace Grail bucket planning, capacity estimation |
| **Knowledge Objects** | Macros, eventtypes, tags, lookups, field extractions | Completeness check for SPL conversion |

### Opt-In (defaults OFF)

| Category | Flag (Bash / PowerShell) | Description |
|----------|--------------------------|-------------|
| **Users & RBAC** | `--rbac` / `-Rbac` | Users, roles, capabilities, LDAP/SAML config. No passwords collected. Used for ownership mapping and stakeholder identification. |
| **Usage Analytics** | `--usage` / `-Usage` | Dashboard views, search frequency, alert executions, ingestion volume. Requires access to `_audit` and `_internal` indexes. Used for prioritization — identifies what is actively used vs abandoned. |

### What Is NOT Collected

- User passwords or password hashes
- API tokens or session keys
- Actual log/event data (only metadata and structure)
- SSL certificates or private keys

### Data Anonymization

When anonymization is enabled (the default), the script creates **two archives**:

| Archive | Contents | Purpose |
|---------|----------|---------|
| `{name}.tar.gz` | Original, untouched data | Reference copy (keep internally) |
| `{name}_masked.tar.gz` | Anonymized copy | Safe to share externally |

Anonymization applies deterministic masking:
- **Emails**: `user@corp.com` becomes `user######@anon.dma.local`
- **Hostnames**: `splunk-idx01.corp.com` becomes `host-########.anon.local`
- **IPv4/IPv6**: Replaced with `[IP-REDACTED]` / `[IPv6-REDACTED]`

---

## 3. Prerequisites, Permissions, Connectivity

### Splunk Cloud (Bash)

| Requirement | Detail |
|-------------|--------|
| **Platform** | Linux, macOS, or WSL |
| **Shell** | bash 3.2+ |
| **Utilities** | curl, Python 3, tar |
| **Disk space** | 500 MB+ free |
| **Network** | HTTPS access to `your-stack.splunkcloud.com:8089` |
| **Credentials** | API token (recommended) or username/password |

### Splunk Cloud (PowerShell)

| Requirement | Detail |
|-------------|--------|
| **Platform** | Windows 10 1803+ |
| **Shell** | PowerShell 5.1+ or PowerShell 7+ |
| **External dependencies** | None (zero — no Python, curl, or jq needed) |
| **Disk space** | 500 MB+ free |
| **Network** | HTTPS access to `your-stack.splunkcloud.com:8089` |
| **Credentials** | API token (recommended) or username/password |

### Splunk Enterprise (Bash)

| Requirement | Detail |
|-------------|--------|
| **Where to run** | On the Splunk Search Head (SSH required) |
| **Run as** | The `splunk` user (e.g. `sudo -u splunk bash dma-splunk-export.sh`) |
| **Shell** | bash 4.0+ (standard on Linux servers) |
| **Utilities** | curl, Python 3 (Splunk bundles Python), tar |
| **Disk space** | 500 MB+ free in `/tmp` |
| **Network** | localhost access to port 8089 |

### Required Permissions

> **Insufficient permissions are the #1 cause of export failures.** Verify access before running.

**Splunk Cloud — recommended approach:** Create a user with the `sc_admin` role, then create an API token for that user (Settings > Tokens).

**Minimum required capabilities** (Cloud and Enterprise):

| Capability | What It Enables |
|------------|-----------------|
| `admin_all_objects` | Access dashboards/alerts across all apps |
| `list_settings` | Read server configuration |
| `rest_properties_get` | Make REST API calls |
| `search` | Run usage analytics queries |
| `list_users` | Collect user data (needed for `--rbac`) |
| `list_indexes` | Collect index metadata |

For **`--usage` analytics**, the user also needs search access to:
- `index=_audit` (dashboard views, user activity, search patterns)
- `index=_internal` (alert firing stats, ingestion volume)

> Use `--skip-internal` if `_internal` is restricted. Use `--test-access` to verify permissions before running a full export.

### Verify Connectivity

**Splunk Cloud:**
```bash
curl -s -k -H "Authorization: Bearer YOUR_TOKEN" \
  "https://your-stack.splunkcloud.com:8089/services/apps/local?output_mode=json&count=1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'OK - {len(d.get(\"entry\",[]))} app(s)')"
```

**Splunk Enterprise:**
```bash
curl -s -k -u admin:password \
  "https://localhost:8089/services/apps/local?output_mode=json&count=1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'OK - {len(d.get(\"entry\",[]))} app(s)')"
```

If either returns `OK - 0 app(s)`, the user/token lacks `admin_all_objects`.

---

## 4. Running the Script

### Quick Start

**Splunk Cloud (Bash — interactive):**
```bash
./dma-splunk-cloud-export_beta.sh
# Follow the prompts for stack URL, credentials, and options
```

**Splunk Cloud (Bash — non-interactive):**
```bash
./dma-splunk-cloud-export_beta.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --usage --rbac
```

**Splunk Cloud (PowerShell — non-interactive):**
```powershell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Usage -Rbac
```

**Splunk Enterprise (Bash — interactive):**
```bash
# Copy to the Search Head, then:
sudo -u splunk bash /tmp/dma-splunk-export.sh
```

**Splunk Enterprise (Bash — non-interactive):**
```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --usage --rbac --yes
```

### Command-Line Arguments

Arguments are the same across all scripts, with minor naming differences for PowerShell.

#### Connection & Authentication

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--stack URL` | `-Stack URL` | Splunk Cloud stack URL (Cloud only) |
| `--token TOKEN` | `-Token TOKEN` | API token authentication (recommended) |
| `-u USER` / `--user USER` | `-User USER` | Username (alternative to token) |
| `-p PASS` / `--password PASS` | `-Password PASS` | Password (used with username) |
| `-h HOST` / `--host HOST` | N/A | Splunk host (Enterprise only, default: localhost) |
| `-P PORT` / `--port PORT` | N/A | Splunk port (Enterprise only, default: 8089) |
| `--proxy URL` | `-Proxy URL` | Route all connections through an HTTP proxy |

#### Scope & Data Selection

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--all-apps` | `-AllApps` | Export all applications (default) |
| `--apps "a,b,c"` | `-Apps "a,b,c"` | Export only these apps (comma-separated) |
| `--scoped` | N/A | Scope analytics to selected apps only |
| `--rbac` | `-Rbac` | Enable RBAC/users collection (off by default) |
| `--usage` | `-Usage` | Enable usage analytics (off by default) |
| `--analytics-period 7d` | `-AnalyticsPeriod 7d` | Analytics time window (default: 7d; also: 30d, 90d) |
| `--skip-internal` | `-SkipInternal` | Skip `_audit`/`_internal` index searches |
| `--no-anonymize` | `-SkipAnonymization` | Disable data anonymization |

#### Special Modes

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--test-access` | `-TestAccess` | Pre-flight check: test API access across 9 categories, then exit. No data exported. |
| `--remask FILE` | `-Remask FILE` | Re-anonymize an existing archive. No Splunk connection needed. |
| `--resume-collect FILE` | `-ResumeCollect FILE` | Resume an interrupted export from a `.tar.gz` archive. |

#### Operational

| Bash | PowerShell | Description |
|------|------------|-------------|
| `-y` / `--yes` | `-NonInteractive` | Auto-confirm all prompts |
| `-d` / `--debug` | `-Debug_Mode` | Verbose debug logging (writes `_export_debug.log`) |
| `--help` | `-ShowHelp` | Show help and exit |

### Where to Upload the Archive

After the export completes, upload the `.tar.gz` archive (use the `_masked` variant if you ran with anonymization):

- **DMA Curator Server** — for migration planning, reporting, and team collaboration (recommended for all exports)
- **Splunk App** — for ad-hoc migration analysis (suitable for smaller archives)

---

## 5. What to Expect

### Interactive Mode

When run without CLI arguments, the script walks you through these steps:

1. **Connectivity check** — DNS resolution, TCP port 8089, TLS handshake
2. **Authentication** — choose token or username/password; the script verifies credentials
3. **Capability check** — warns if recommended permissions are missing
4. **Application selection** — export all apps or pick specific ones
5. **Data category selection** — toggle configs, dashboards, alerts, RBAC, usage, indexes on/off
6. **Analytics period** (if `--usage` enabled) — 7 days, 30 days, 90 days, or 365 days
7. **Collection** — progress displayed per category; large analytics use async search dispatch with adaptive polling
8. **Anonymization** — creates the `_masked` archive (unless disabled)
9. **Summary** — statistics table with counts of dashboards, alerts, users, errors

### Non-Interactive Mode

When all required parameters are provided on the command line, the script runs without prompts. It logs the same steps to the console and to `_export.log` inside the archive.

### Typical Runtimes

| Environment | Without `--usage` | With `--usage` |
|-------------|-------------------|----------------|
| Small (10 apps, 200 dashboards) | 2-5 minutes | 5-15 minutes |
| Medium (50 apps, 1000 dashboards) | 10-20 minutes | 20-60 minutes |
| Large (200+ apps, 5000+ dashboards) | 30-60 minutes | 1-4 hours |

The maximum runtime is 12 hours. Analytics searches use async dispatch (v4.5.0+) with up to 1 hour per query, so large `_audit` indexes no longer cause timeouts.

### Pre-Flight Check (`--test-access`)

Run this first to verify permissions without exporting anything:

```bash
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --token "$TOKEN" --test-access
```

Output shows PASS/FAIL/WARN/SKIP for each category:

```
  [OK  ]  System Info                         Splunk v9.3.2411.128
  [OK  ]  Configurations (indexes)            1 entries
  [OK  ]  Dashboards (myapp)                  3 found
  [OK  ]  Saved Searches / Alerts (myapp)     5 found
  [SKIP]  RBAC (users/roles)                  Not requested (add --rbac)
  [OK  ]  Knowledge Objects (myapp)           macros, props, lookups
  [SKIP]  App Analytics (_audit)              Not requested (add --usage)
  [SKIP]  Usage Analytics (_internal)         Not requested (add --usage)
  [OK  ]  Indexes                             1 found
```

### Resume an Interrupted Export

If an export is interrupted (network drop, Ctrl+C, timeout), resume it:

```bash
./dma-splunk-cloud-export_beta.sh \
  --resume-collect dma_cloud_export_acme_20260331_143022.tar.gz \
  --stack acme.splunkcloud.com --token "$TOKEN"
```

The script extracts the partial archive, detects which phases completed (via checkpoint files), and continues from where it left off. Progressive per-query checkpointing means even analytics searches resume mid-way.

### Re-Anonymize an Existing Archive

If anonymization settings change or the first masking was skipped:

```bash
./dma-splunk-cloud-export_beta.sh --remask dma_cloud_export_acme_20260331_143022.tar.gz
```

This requires no Splunk connection — it extracts, anonymizes, and repacks the archive locally.

---

## 6. Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No applications found!` | Token lacks `admin_all_objects` or `list_apps` capability | Use `sc_admin` role, or add `admin_all_objects` to the user's role |
| `Token authentication failed` | Wrong token prefix (Bearer vs Splunk) | v4.5.8 auto-detects the prefix; if using an older script, upgrade |
| `Connected to Splunk Cloud v` (empty version) | `server_info` API call failed silently | Upgrade to v4.5.8 which shows the actual error; check `get_info` capability |
| `401 Unauthorized` on connectivity test | Endpoint requires auth (expected) | The 401 confirms network reachability; authentication happens in the next step |
| Analytics searches timeout | Blocking mode limit (pre-v4.5.0) or very large `_audit` | Upgrade to v4.5.8 (async dispatch, 1h timeout); try `--analytics-period 7d` |
| `Rate limited (429)` | Too many API calls | Script auto-retries with exponential backoff; no action needed |
| `_audit` / `_internal` access denied | Splunk Cloud restricts these indexes | Use `--skip-internal`; analytics that depend on these indexes will be skipped |
| Export takes hours | Large environment with `--usage` enabled | Use `--apps "app1,app2" --scoped` to limit scope; or reduce `--analytics-period` |
| PowerShell: `Execution Policy` error | Script execution disabled | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |

### Debug Mode

Add `--debug` (Bash) or `-Debug_Mode` (PowerShell) for detailed diagnostics:

- **Console**: Color-coded messages (ERROR, WARN, API, SEARCH, TIMING, AUTH)
- **Log file**: `_export_debug.log` inside the archive
- **API calls**: Logs every request with endpoint, HTTP status, response size, and duration
- **Auth**: Logs token length, masked value, and probe responses
- **Search jobs**: Logs SID dispatch, poll states, completion time

### Getting Help

- Run with `--help` / `-ShowHelp` for a quick reference of all flags
- See [docs_markdown/README-SPLUNK-CLOUD.md](docs_markdown/README-SPLUNK-CLOUD.md) for detailed Cloud prerequisites
- See [docs_markdown/README-SPLUNK-ENTERPRISE.md](docs_markdown/README-SPLUNK-ENTERPRISE.md) for Enterprise prerequisites
- See [docs_markdown/EXPORT-SCHEMA.md](docs_markdown/EXPORT-SCHEMA.md) for the full archive file structure

---

## 7. Version History

### v4.5.8 (March 2026) — Cloud scripts (Bash + PowerShell)

**Token authentication fixes:**
- Auto-detect token prefix (Bearer vs Splunk) via probe loop — tokens created via Splunk's Settings > Tokens require `Splunk` prefix
- `api_call` uses the discovered auth header instead of hardcoding Bearer
- Clear error messages when token lacks permissions for `server_info` or app listing

**Async search dispatch** (replaces blocking mode):
- `exec_mode=normal` returns SID immediately; script polls `dispatchState`
- Adaptive poll interval: 5s, increasing to 30s cap
- 1-hour max wait per query (up from 300s hard timeout)
- Auto-cancels timed-out jobs to free Splunk search quota

**Global aggregate analytics** (replaces per-app loops):
- 6 global queries replace N x 7 per-app queries (90 apps: 630 jobs reduced to 6)
- Dashboard views use `provenance` field (fixes broken `search_type=dashboard` pattern)
- View session de-duplication counts page loads, not individual panel searches
- Search type breakdown derived from `provenance`/`search_id` via `eval case()`

**New features:**
- `--test-access` / `-TestAccess`: pre-flight check across 9 API categories
- `--remask` / `-Remask`: re-anonymize an existing archive without Splunk connection
- `--analytics-period` / `-AnalyticsPeriod`: configurable analytics time window (default: 7d)
- Progressive per-query checkpointing for analytics (resume mid-way on interrupt)

**Expanded RBAC collection:**
- Added: capabilities, SAML config, SAML groups, LDAP groups, LDAP config
- Graceful 404 handling when SAML/LDAP not configured

**Default changes:**
- `USAGE_PERIOD` changed from 30d to 7d (4x less `_audit` data to scan)

### v4.4.0 (March 2026) — Enterprise script

- `--proxy URL`: routes all curl calls through an HTTP proxy
- `--skip-internal`: skips `_audit`/`_internal` searches for restricted accounts
- `--test-access`: pre-flight API access check (no export written)
- `--remask FILE`: re-anonymize existing archive without Splunk connection
- `--resume-collect FILE`: resume interrupted export from archive
- Expanded RBAC: capabilities, LDAP groups/config, SAML groups/config
- Progressive analytics checkpointing across all collection phases
- `has_collected_data` guards on all collection phases for resume support

### v4.3.0 (February 2026) — All scripts

- `--token`: API token authentication (recommended for automation)
- Password auth uses Python URL-encoding via stdin (safe for special characters)
- Session key auth replaces curl basic auth (`-u user:pass`) throughout
- `--analytics-period`: configurable analytics time window
- `--usage` / `--rbac` enable flags (both off by default)
- Async search dispatch with adaptive polling (Cloud)
- `--resume-collect`: resume interrupted exports from archive (Cloud)
- `--proxy`: HTTP proxy support (Cloud)
- PowerShell Cloud export script (`dma-splunk-cloud-export.ps1`) — zero external dependencies
- 12-hour maximum runtime (up from 4 hours)

### v4.2.4 (January 2026)

- Two-archive anonymization: original preserved, `_masked` copy for sharing
- RBAC/usage collection off by default (use `--rbac` / `--usage`)
- Batch size 250 (was 100), API delay 50ms (was 250ms)
- Saved searches ACL fix: correctly filters by app ownership

### v4.2.0 (December 2025)

- App-centric dashboard structure (v2): `{app}/dashboards/classic/` and `{app}/dashboards/studio/`
- Manifest schema v4.0 with `archive_structure_version: "v2"`

---

## Additional Documentation

| Document | Description |
|----------|-------------|
| [INTERACTIVE-WALKTHROUGH.md](docs_markdown/INTERACTIVE-WALKTHROUGH.md) | Step-by-step visual guide to the interactive prompts and console output |
| [README-SPLUNK-CLOUD.md](docs_markdown/README-SPLUNK-CLOUD.md) | Detailed Cloud prerequisites and setup |
| [README-SPLUNK-ENTERPRISE.md](docs_markdown/README-SPLUNK-ENTERPRISE.md) | Detailed Enterprise prerequisites and setup |
| [EXPORT-SCHEMA.md](docs_markdown/EXPORT-SCHEMA.md) | Complete archive file structure specification |
| [SPLUNK-CLOUD-EXPORT-SPECIFICATION.md](docs_markdown/SPLUNK-CLOUD-EXPORT-SPECIFICATION.md) | Technical specification for Cloud exports |
| [SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md](docs_markdown/SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | Technical specification for Enterprise exports |
| [SCRIPT-GENERATED-ANALYTICS-REFERENCE.md](docs_markdown/SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | Reference of all SPL queries used for analytics |
