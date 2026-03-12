# DMA Splunk Cloud Export — Beta Script

## Version 4.5.6

### What's New in Beta

The beta script includes several features not yet in the stable release:

- **`--remask` flag** — Re-anonymize an existing unmasked archive without reconnecting to Splunk
- **`--test-access` mode** — Pre-flight API access verification (9 checks, read-only, no export)
- **`--skip-internal` flag** — Skip `_internal` index queries when restricted in Splunk Cloud
- **`--analytics-period` flag** — Override the analytics time window (default: `7d`)
- **`--scoped` flag** — Scope all collections to selected apps only
- **Masking integrity checks** — Disk space verification, file count validation before/after copy and anonymization
- **Analytics overhaul** — Fixed broken `search_type=dashboard` queries, async search dispatch, global aggregate queries
- **RBAC enhancements** — New LDAP/SAML collection endpoints, fixed SAML error handling
- **Password auth improvements** — URL-encoded credentials, session key diagnostics, Splunk Cloud cluster guidance

---

## Quick Start

```bash
# Token auth (recommended)
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --token YOUR_TOKEN --all-apps

# With RBAC and usage analytics
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --token YOUR_TOKEN --all-apps --rbac --usage

# Test access first (no data exported)
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token YOUR_TOKEN --rbac --usage

# Username/password auth
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --user admin --password 'P@ssw0rd' --all-apps

# Re-anonymize an existing unmasked archive (no Splunk connection needed)
./dma-splunk-cloud-export_beta.sh --remask /path/to/dma_cloud_export_original.tar.gz
```

---

## All CLI Flags

| Flag | Argument | Description |
|------|----------|-------------|
| `--stack` | `URL` | Splunk Cloud stack URL (e.g., `acme.splunkcloud.com`) |
| `--token` | `TOKEN` | API token for authentication (recommended) |
| `--user` | `USER` | Username for password-based authentication |
| `--password` | `PASS` | Password for password-based authentication |
| `--all-apps` | | Export all applications |
| `--apps` | `LIST` | Comma-separated list of specific apps to export |
| `--output` | `DIR` | Output directory for the export archive |
| `--usage` | | Collect usage analytics (OFF by default — requires `_audit`/`_internal` access) |
| `--no-usage` | | Explicitly disable usage analytics (legacy, usage is off by default) |
| `--rbac` | | Collect RBAC/users data (OFF by default — global user/role data) |
| `--no-rbac` | | Explicitly disable RBAC collection (legacy, RBAC is off by default) |
| `--analytics-period` | `WINDOW` | Analytics time window (default: `7d`, e.g., `30d`, `90d`) |
| `--skip-internal` | | Skip queries requiring `_internal` index (use when restricted in Splunk Cloud) |
| `--scoped` | | Scope all collections to selected apps only (auto-enabled with `--apps`) |
| `--proxy` | `URL` | Route all connections through a proxy server (e.g., `http://proxy:8080`) |
| `--resume-collect` | `FILE` | Resume a previous interrupted export from a `.tar.gz` archive |
| `--test-access` | | Pre-flight API access verification — runs 9 read-only checks, no data exported |
| `--remask` | `FILE` | Re-anonymize an existing unmasked `.tar.gz` archive (no Splunk connection needed) |
| `-d`, `--debug` | | Enable verbose debug logging (writes to `export_debug.log`) |
| `--help` | | Show usage information |

---

## `--test-access` Mode

Pre-flight verification that tests API access for every data collection category **without exporting any data**. Use this before a full export to confirm the service account has all required permissions.

### Usage

```bash
# Test core access only
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token YOUR_TOKEN

# Test core + RBAC + usage analytics access
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token YOUR_TOKEN --rbac --usage

# Test with _internal skipped (Splunk Cloud restricted)
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token YOUR_TOKEN --rbac --usage --skip-internal

# Test against specific apps
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token YOUR_TOKEN --apps myapp1,myapp2 --rbac --usage
```

### The 9 Access Checks

| # | Check | Level | What It Tests |
|---|-------|-------|---------------|
| 1 | System Info | **CRITICAL** | Basic connectivity and Splunk version (`/services/server/info`) |
| 2 | Configurations | REQUIRED | Index configuration access (`/servicesNS/-/-/configs/conf-indexes`) |
| 3 | Dashboards | REQUIRED | Dashboard definitions for a test app (`/servicesNS/-/{APP}/data/ui/views`) |
| 4 | Saved Searches / Alerts | REQUIRED | Saved search/alert access for a test app (`/servicesNS/-/{APP}/saved/searches`) |
| 5 | RBAC (users/roles) | OPTIONAL | User list + role definitions — only tested if `--rbac` is passed |
| 6 | Knowledge Objects | REQUIRED | Macros, props.conf, lookups for a test app |
| 7 | App Analytics (`_audit`) | OPTIONAL | Search access to `_audit` index — only tested if `--usage` is passed |
| 8 | Usage Analytics (`_internal`) | OPTIONAL | Search access to `_internal` index — only tested if `--usage` is passed, skipped if `--skip-internal` |
| 9 | Indexes | REQUIRED | Index list and metadata (`/services/data/indexes`) |

### Result Statuses

| Status | Meaning |
|--------|---------|
| **PASS** | Access verified — endpoint returned data |
| **FAIL** | Access denied — endpoint returned 401/403 or search was rejected |
| **WARN** | Partial access — some sub-checks passed, others failed |
| **SKIP** | Not tested — feature not requested (e.g., RBAC without `--rbac` flag) |

### Verdict Logic

- **All pass** → "You are ready to run a full export"
- **Critical failure** (System Info fails) → "Cannot run export until resolved" (exit code 1)
- **Non-critical failures** → "Export will run but some data will be missing" (exit code 2)
- **Warnings only** → "All required checks passed (some warnings)" (exit code 0)

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed (or warnings only) |
| `1` | Critical failure — cannot reach Splunk API |
| `2` | Non-critical failures — export will be incomplete |

---

## Required Permissions

### Core Capabilities (must have all)

| Capability | Required For |
|---|---|
| `search` | Execute all SPL queries |
| `admin_all_objects` | Access configs, dashboards, saved searches across all apps |
| `list_settings` | Read server settings and index configurations |
| `rest_properties_get` | Read all REST API endpoints |
| `list_indexes` | List index definitions and metadata |

### Additional for RBAC (`--rbac`)

| Capability | Required For |
|---|---|
| `list_users` | Export user list |
| `list_users_roles` | Export role definitions and mappings |

### Index Access for Usage Analytics (`--usage`)

| Index | Required For | Can Skip? |
|---|---|---|
| `_audit` | Dashboard views, user activity, search patterns | Use `--no-usage` |
| `_internal` | Daily ingestion volume, alert firing stats | Use `--skip-internal` |

The recommended Splunk Cloud role is **`sc_admin`**, which includes all required capabilities. Use `--test-access` to verify before running a full export.

---

## Breaking Changes (v4.5.0)

| Change | Before (v4.4.0) | After (v4.5.0) |
|--------|-----------------|-----------------|
| Default analytics period | 30 days | **7 days** (use `--analytics-period 30d` for old behavior) |
| Analytics output location | Per-app `splunk-analysis/` folders | Global `dma_analytics/usage_analytics/` folder |
| Search dispatch mode | `exec_mode=blocking` (300s limit) | `exec_mode=normal` + async polling (1 hour default) |
| Dashboard view queries | `search_type=dashboard` (BROKEN) | `provenance` field (CORRECT) |
| Resume with `--usage` | Skips if old data exists | **Always re-collects** analytics |

---

## Root Cause: Why Analytics Were Broken

### The `search_type=dashboard` Bug

All dashboard view queries in v4.4.0 and earlier used this pattern:

```spl
index=_audit action=search search_type=dashboard ...
```

**Problem**: `search_type` is **NOT a native `_audit` field**. It's a derived field created by Splunk's Monitoring Console via `eval case(...)`. When you search `_audit` directly, `search_type` doesn't exist — every query matches zero events and returns empty results.

### The Fix: `provenance` Field

Dashboard views in `_audit` are identified by the `provenance` field:

```
provenance="UI:Dashboard:my_dashboard"    (Classic XML dashboards)
provenance="UI:dashboard:my_dashboard"    (Dashboard Studio)
```

The `provenance` field only exists in `info=granted` events. All v4.5.0 queries use:

```spl
index=_audit sourcetype=audittrail info=granted
  (provenance="UI:Dashboard:*" OR provenance="UI:dashboard:*")
```

### View Session De-duplication

A single dashboard page load triggers multiple `_audit` events (one per panel search). To count actual *views* rather than panel executions:

```spl
eval view_session=user."_".floor(_time/30)
| stats dc(view_session) as views ...
```

This groups events within 30-second windows per user into a single "view session."

---

## Analytics Collection Overhaul

### Before: Per-App Loop (v4.4.0)

- Ran 7 search queries **per app** (N apps × 7 queries = 2,100+ jobs for 300 apps)
- All queries used broken `search_type=dashboard`
- `exec_mode=blocking` with 300-second hard limit
- Sequential execution — hours of wall time

### After: Global Aggregate Queries (v4.5.0)

- Runs **6 global queries total** regardless of app count
- All queries use verified field names (`provenance`, `sourcetype=audittrail`)
- `exec_mode=normal` with async polling (up to 1 hour per query)
- Progressive checkpointing — resume without re-running completed queries

### Global Queries

| # | Query | Description | Max Wait |
|---|-------|-------------|----------|
| 1 | Dashboard Views | Views by dashboard and app using `provenance` field | 1 hour |
| 2 | User Activity | Active users by app with search counts | 1 hour |
| 3 | Search Patterns | Search type breakdown (ad-hoc, scheduled, dashboard) | 30 min |
| 4 | Daily Ingestion | Volume per index from `license_usage.log` + `tstats` fallback | 10 min |
| 5 | Alert Firing | Alert execution stats from scheduler logs | 1 hour |
| 6 | Alerts Inventory | Per-app alert list via `| rest` (blocking, fast) | 5 min |

### Output Files

All analytics output goes to `dma_analytics/usage_analytics/`:

```
dma_analytics/
  usage_analytics/
    dashboard_views_global.json      # Dashboard view counts by app
    user_activity_global.json        # User activity by app
    search_patterns_global.json      # Search type breakdown
    index_volume_summary.json        # Daily ingestion volume
    index_event_counts_daily.json    # Event count fallback (tstats)
    alert_firing_global.json         # Alert firing statistics
    usage_intelligence.md            # Human-readable summary
    saved_searches_meta.json         # REST: saved search metadata
    kvstore_status.json              # REST: KV store status
    recent_jobs.json                 # REST: recent search jobs
```

---

## Async Search Dispatch

### Before: Blocking (v4.4.0)

```
exec_mode=blocking → 300s hard limit → search killed → empty results
```

### After: Async Polling (v4.5.0)

```
exec_mode=normal → SID returned immediately → poll every 5-30s → fetch results when DONE
```

Key improvements:
- **No 300s limit** — queries can run up to 1 hour (configurable per query)
- **Gradual backoff** — polling starts at 5s, increases by 5s up to 30s
- **Progress logging** — status updates every ~60 seconds
- **Graceful timeout** — cancels the search job on timeout to free quota
- **Standardized error JSON** — all failures write structured error files with troubleshooting info

---

## RBAC Collection Enhancements

### Fixed: App-Scoped User Search

**Before** (broken):
```spl
search index=_audit action=search ${app_filter} earliest=-${USAGE_PERIOD}
| stats count as activity, latest(_time) as last_active by user
| sort -activity
```

**After** (fixed):
```spl
search index=_audit sourcetype=audittrail action=search info=granted
  ${app_filter} user!="splunk-system-user" user!="nobody"
  earliest=-${USAGE_PERIOD}
| stats count as activity, dc(search_id) as unique_searches, max(_time) as last_active by user
| sort -activity
```

Changes:
- Added `sourcetype=audittrail` for performance
- Added `info=granted` (required for `action=search` events)
- Excluded system users (`splunk-system-user`, `nobody`)
- Added `dc(search_id) as unique_searches` for better activity metrics
- Changed `latest(_time)` to `max(_time)` (equivalent but more explicit)

### Fixed: SAML Groups Error Handling

SAML groups endpoint now handles errors gracefully instead of writing broken JSON:
- Checks entry count in response
- Writes meaningful note if SAML is not configured or endpoint returns 404
- No longer causes downstream parsing errors

### New RBAC Endpoints

Four new REST API calls collect additional identity and access data:

| Endpoint | Output File | Description |
|----------|-------------|-------------|
| `/services/authorization/capabilities` | `rbac/capabilities.json` | All system capabilities |
| `/services/authentication/providers/SAML` | `rbac/saml_config.json` | SAML provider configuration |
| `/services/admin/LDAP-groups` | `rbac/ldap_groups.json` | LDAP group mappings |
| `/services/authentication/providers/LDAP` | `rbac/ldap_config.json` | LDAP provider configuration |

Each endpoint has graceful error handling — if SAML/LDAP is not configured, a note is written instead of an error.

---

## New CLI Flags

### `--analytics-period <window>`

Override the analytics time window. Default is `7d`.

```bash
# Use 30-day window (old default)
./dma-splunk-cloud-export_beta.sh --usage --analytics-period 30d ...

# Use 90-day window for comprehensive analysis
./dma-splunk-cloud-export_beta.sh --usage --analytics-period 90d ...
```

Valid formats: `7d`, `30d`, `90d`, `365d` (any Splunk relative time specifier).

---

## Changed Defaults

### Analytics Period: 7 Days (was 30 Days)

The default analytics window changed from 30 days to 7 days. Rationale:

1. **4x less data to scan** — faster queries, lower resource impact
2. **Sufficient for migration planning** — 7 days captures active dashboards, users, and alerts
3. **Lower risk of search quota exhaustion** on production Splunk instances
4. **More reliable results** — shorter scans are less likely to timeout

Use `--analytics-period 30d` to restore the previous behavior, or select the period in the interactive menu.

### Interactive Menu Default

The interactive period selection menu now defaults to option 1 (7 days) instead of option 2 (30 days).

---

## Resume Behavior

### `--resume-collect --usage`

When `--usage` is explicitly passed with `--resume-collect`, the script **always re-collects analytics** even if prior analytics data exists. This is because:

1. Prior data may be from v4.4.0 or earlier with broken `search_type=dashboard` queries
2. All old analytics files contain zero results (the bug produced empty data)
3. Re-collection uses the new corrected queries with verified field names

Without `--usage`, the resume behavior is unchanged — existing analytics data is preserved.

### Progressive Checkpointing

Within `collect_app_analytics()`, each global query is checkpointed after completion. If the script is interrupted mid-collection, re-running with `--resume-collect --usage` will skip already-completed queries and continue from where it left off.

Checkpoint file: `$EXPORT_DIR/.analytics_checkpoint`

---

## Troubleshooting

### Empty Dashboard Views

If `dashboard_views_global.json` still shows zero results after upgrading:

1. **Check `_audit` access**: Run `index=_audit | head 10` in Splunk search. If no results, your role lacks `_audit` access.
2. **Check `provenance` field exists**: Run `index=_audit sourcetype=audittrail info=granted provenance="UI:*" | head 10`. If no results, dashboard views may not be logged (check `audit.conf`).
3. **Extend the period**: Try `--analytics-period 30d` — dashboards may not have been viewed in the last 7 days.

### Search Timeouts

If queries timeout (error JSON shows `"error": "search_timeout"`):

1. **Reduce the period**: Use `--analytics-period 7d` (default)
2. **Check search quota**: Splunk Cloud has concurrent search limits. Run during off-peak hours.
3. **Check `_audit` size**: Large `_audit` indexes (100GB+) slow all queries. The 7d default helps.

### SAML/LDAP "Not Configured" Notes

If `saml_config.json` or `ldap_config.json` contains a "not configured" note, this is expected — your Splunk instance doesn't use that authentication provider. The data is still collected for environments that do.

### `_internal` Skipped

If you see `--skip-internal` was used, daily volume and alert firing queries are skipped. These queries require `_internal` index access which is often restricted in Splunk Cloud. Index size data is still available from REST metadata.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.5.6 | 2026-03 | Fix masked archive dropping files: disk space check, file count validation, `--remask` flag |
| 4.5.5 | 2026-03 | Password auth: safer URL encoding, session key diagnostics, Splunk Cloud cluster 401 guidance |
| 4.5.0 | 2026-02 | Analytics overhaul: fix `search_type=dashboard` bug, global queries, async dispatch, RBAC enhancements |
| 4.4.0 | 2026-01 | Prior beta (per-app analytics, blocking dispatch, search_type=dashboard) |
