# DMA Splunk Enterprise Export Script -- Technical Specification

## Version 4.6.5

**Last Updated**: May 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise README](README-SPLUNK-ENTERPRISE.md) | [Export Schema](EXPORT-SCHEMA.md)

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Executive Summary

`dma-splunk-export.sh` is an Enterprise-specific Bash script that collects migration intelligence from on-premises Splunk deployments. It combines **filesystem reads** of `$SPLUNK_HOME/etc/apps/` configuration files with **REST API calls** and **SPL search jobs** to produce a self-contained `.tar.gz` archive for import into the DMA Server.

Key characteristics of the Enterprise script (vs. the Cloud script):

- Reads configuration files directly from `$SPLUNK_HOME/etc/apps/<app>/default/` and `local/` on the filesystem
- Detects `SPLUNK_HOME` automatically from environment variables and common installation paths
- Detects Search Head Cluster membership via REST API + filesystem checks for `[shclustering]` in `server.conf`
- RBAC collection (`COLLECT_RBAC`) and usage analytics (`COLLECT_USAGE`) are **ON by default**
- Produces two archives when anonymization is enabled: original + `_masked`

> **Note**: For Splunk Cloud environments, use the dedicated Cloud export scripts: `dma-splunk-cloud-export.sh` (Bash) and `dma-splunk-cloud-export.ps1` (PowerShell). See [README-SPLUNK-CLOUD.md](README-SPLUNK-CLOUD.md).

---

## Table of Contents

1. [What's New in v4.6.0](#1-whats-new-in-v460)
2. [Global Defaults and Tunables](#2-global-defaults-and-tunables)
3. [SPLUNK_HOME Detection](#3-splunk_home-detection)
4. [Environment Detection and SHC Awareness](#4-environment-detection-and-shc-awareness)
5. [Authentication](#5-authentication)
6. [Collection Phases](#6-collection-phases)
7. [Configuration File Collection (Filesystem)](#7-configuration-file-collection-filesystem)
8. [Dashboard Collection](#8-dashboard-collection)
9. [Alert and Saved Search Collection](#9-alert-and-saved-search-collection)
10. [RBAC Collection](#10-rbac-collection)
11. [App Analytics -- 6 Global Queries](#11-app-analytics----6-global-queries)
12. [Usage Analytics (Stripped in v4.6.0)](#12-usage-analytics-stripped-in-v460)
13. [Index and Data Statistics](#13-index-and-data-statistics)
14. [System Configuration Collection](#14-system-configuration-collection)
15. [Async Search Dispatch (run_usage_search)](#15-async-search-dispatch-run_usage_search)
16. [Checkpointing and Resume](#16-checkpointing-and-resume)
17. [Export Directory Structure](#17-export-directory-structure)
18. [Archive Creation and Anonymization](#18-archive-creation-and-anonymization)
19. [CLI Flags Reference](#19-cli-flags-reference)
20. [Test-Access Mode](#20-test-access-mode)
21. [Error Handling](#21-error-handling)
22. [API Endpoints Reference](#22-api-endpoints-reference)
23. [Security Considerations](#23-security-considerations)

---

## 1. What's New in v4.6.0

### Stripped Usage Analytics

The `collect_usage_analytics()` function has been reduced to:

- **3 search jobs** for ownership mapping (dashboard ownership, alert/saved-search ownership, ownership summary by user) -- all using `| rest` SPL queries
- **3 REST API calls** for supplementary metadata (saved searches metadata, recent search jobs, KV store stats)
- **1 summary markdown** file (`USAGE_INTELLIGENCE_SUMMARY.md`)

The ~40 detailed per-category SPL search jobs that previously ran in `collect_usage_analytics()` have been removed. All substantive usage data is now produced by the 6 global queries in `collect_app_analytics()`.

### Checkpoint Clearing

In resume mode (`--resume-collect`), only the `usage_ownership` checkpoint remains relevant. The old detailed per-query checkpoints (e.g., `usage_dashboard_views`, `usage_search_frequency`, etc.) no longer exist in the script.

### Default Changes

| Setting | v4.4.0 | v4.6.0 |
|---------|--------|--------|
| `MAX_TOTAL_TIME` | `43200` (12 hours) | `14400` (4 hours) |
| `COLLECT_RBAC` | ON by default | ON by default (unchanged) |
| `COLLECT_USAGE` | ON by default | ON by default (unchanged) |
| `USAGE_PERIOD` | `30d` | `30d` (unchanged) |
| Usage analytics jobs | ~40 SPL queries | 3 ownership `\| rest` queries + 3 curl calls |

---

## 2. Global Defaults and Tunables

All defaults are defined near the top of the script (lines ~155-259) and can be overridden via environment variables.

```
SPLUNK_HOST      = "localhost"
SPLUNK_PORT      = "8089"

BATCH_SIZE       = 250          # Items per paginated API request
RATE_LIMIT_DELAY = 0.05         # 50ms between API calls
API_DELAY_SECONDS= 0.05         # Alias used in collection loops

API_TIMEOUT      = 120          # Per-request curl timeout (seconds)
CONNECT_TIMEOUT  = 10           # curl --connect-timeout (seconds)
MAX_TOTAL_TIME   = 14400        # 4 hours maximum total runtime

MAX_RETRIES      = 3            # Retry attempts for failed API requests
RETRY_DELAY      = 2            # Initial retry delay (exponential backoff)

COLLECT_RBAC     = true         # ON by default (use --no-rbac to disable)
COLLECT_USAGE    = true         # ON by default (use --no-usage to disable)
COLLECT_DASHBOARDS = true
COLLECT_ALERTS   = true
COLLECT_INDEXES  = true
COLLECT_LOOKUPS  = false        # OFF by default (use --apps with lookups dir)
COLLECT_AUDIT    = false

ANONYMIZE_DATA   = true         # Two-archive anonymization (original + _masked)
USAGE_PERIOD     = "30d"        # Analytics time window (override: --analytics-period)
```

Override example:

```bash
BATCH_SIZE=50 MAX_TOTAL_TIME=7200 ./dma-splunk-export.sh -u admin -p pass
```

---

## 3. SPLUNK_HOME Detection

The `detect_splunk_home()` function (lines ~2461-2519) locates the Splunk installation directory. This is required because the Enterprise script reads configuration files directly from the filesystem.

### Detection Order

1. **`$SPLUNK_HOME` environment variable** -- if set and the directory exists, use it immediately
2. **Common installation paths** -- scanned in order:
   - `/opt/splunk`
   - `/opt/splunkforwarder`
   - `/Applications/Splunk`
   - `/Applications/SplunkForwarder`
   - `$HOME/splunk`
   - `$HOME/splunkforwarder`
   - `/usr/local/splunk`
3. **User prompt** -- if no path is found, the script prompts interactively (unless `--splunk-home` was provided via CLI)

Validation: the path must contain an `etc/` subdirectory (`[ -d "$SPLUNK_HOME/etc" ]`).

### Python Detection

After `SPLUNK_HOME` is located, the script searches for Python 3 in this order:

1. `$SPLUNK_HOME/bin/python3` (Splunk's bundled Python)
2. System `python3`
3. System `python` (only if version 3)

Python is required for all JSON processing throughout the script.

---

## 4. Environment Detection and SHC Awareness

### Filesystem-Based Detection (lines ~2560-2630)

After authentication, the script reads `$SPLUNK_HOME/etc/system/local/server.conf` to classify the deployment:

| Check | File/Section | Result |
|-------|-------------|--------|
| `[shclustering]` present | `server.conf` | `IS_SHC_MEMBER=true`, architecture=distributed |
| `mode=captain` under `[shclustering]` | `server.conf` | `IS_SHC_CAPTAIN=true`, role=`shc_captain` |
| `mode` not captain | `server.conf` | role=`shc_member` |
| `[clustering]` present | `server.conf` | `IS_IDX_CLUSTER=true`, architecture=distributed |
| `mode=master` under `[clustering]` | `server.conf` | role=`cluster_master` |
| `mode=slave` under `[clustering]` | `server.conf` | role=`indexer_peer` |
| `distsearch.conf` has `servers` | `distsearch.conf` | architecture=distributed, role=`search_head` |
| `outputs.conf` exists + few local indexes | filesystem | flavor=`hf`, role=`heavy_forwarder` |
| `deployment-apps/` has contents | filesystem | role=`deployment_server` |

### REST API SHC Detection (lines ~1770-1830)

The `detect_shc_role()` function makes REST calls when `AUTH_HEADER` is available:

```
GET /services/shcluster/member/info?output_mode=json
```

Checks `is_registered` in the response. If true, reads `status` to determine captain vs. member. Then:

```
GET /services/shcluster/member/members?output_mode=json
```

Retrieves the SHC member count. When running on the captain, the script warns the user and recommends running from a member instead (to avoid impacting the captain's workload).

### Detection Variables Set

```
SPLUNK_FLAVOR        = "enterprise" | "uf" | "hf"
SPLUNK_ARCHITECTURE  = "standalone" | "distributed"
SPLUNK_ROLE          = "search_head" | "shc_captain" | "shc_member" |
                       "cluster_master" | "indexer_peer" |
                       "heavy_forwarder" | "deployment_server"
IS_SHC_MEMBER        = true | false
IS_SHC_CAPTAIN       = true | false
IS_IDX_CLUSTER       = true | false
```

---

## 5. Authentication

### Methods

| Method | Flag | Mechanism |
|--------|------|-----------|
| **API Token** | `--token TOKEN` | Sets `AUTH_HEADER="Authorization: Bearer $TOKEN"` directly. Recommended for automation. Auto-enables non-interactive mode. |
| **Username/Password** | `-u USER -p PASS` | Calls `POST /services/auth/login` to obtain a session key; constructs `AUTH_HEADER="Authorization: Splunk $SESSION_KEY"`. |
| **Environment Variables** | `SPLUNK_USER`, `SPLUNK_PASSWORD` | Same as username/password but pre-set in environment (common in container deployments). |
| **Interactive** | (none) | Prompts for username and password if not provided. |

### Password Encoding

Passwords containing special characters (`$`, backticks, `"`, `\`) are URL-encoded via Python stdin to avoid shell escaping issues:

```bash
echo "$password" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))"
```

### Session Key Flow

1. POST to `/services/auth/login` with `username=` and `password=` (URL-encoded)
2. Extract `sessionKey` from JSON response
3. Construct `AUTH_HEADER="Authorization: Splunk $SESSION_KEY"`
4. All subsequent `curl` calls use `-H "$AUTH_HEADER"`

---

## 6. Collection Phases

The script executes collection in this order. Each phase is guarded by feature flags and resume-mode checks.

```
Phase 1: System Information        (collect_system_info)
Phase 2: System Macros             (collect_system_macros)
Phase 3: App Configuration Files   (collect_app_configs -- per app, filesystem reads)
Phase 4: Dashboards                (collect_dashboards -- REST API, app-scoped)
Phase 5: RBAC                      (collect_rbac -- REST API + filesystem)
Phase 6: App Analytics             (collect_app_analytics -- 6 global SPL queries)
Phase 7: Usage Analytics           (collect_usage_analytics -- 3 ownership queries + 3 REST calls)
Phase 8: Index Statistics           (collect_index_stats -- REST API + filesystem)
Phase 9: Manifest Generation       (generate_manifest)
Phase 10: Summary Generation       (generate_summary_markdown)
Phase 11: Archive Creation         (create_tarball + optional anonymization)
```

### Resume Guards

The `has_collected_data()` function (lines ~7280-7290) checks for sentinel files to skip already-completed phases:

| Category | Sentinel File |
|----------|--------------|
| `system_info` | `dma_analytics/system_info/server_info.json` |
| `rbac` | `dma_analytics/rbac/users.json` |
| `usage_analytics` | `dma_analytics/usage_analytics/dashboard_ownership.json` |
| `indexes` | `dma_analytics/index_stats.json` |

---

## 7. Configuration File Collection (Filesystem)

### collect_app_configs() (lines ~3573-3664)

For each selected app, the function reads from `$SPLUNK_HOME/etc/apps/<app>/`:

**Configuration files read from both `default/` and `local/`:**

| File | Purpose |
|------|---------|
| `props.conf` | Field extractions, line breaking, timestamp parsing |
| `transforms.conf` | Lookup definitions, field transforms, routing rules |
| `eventtypes.conf` | Event classification definitions |
| `tags.conf` | Tag assignments to event types and field values |
| `indexes.conf` | Index definitions (app-level) |
| `macros.conf` | Search macros |
| `savedsearches.conf` | Saved searches, reports, alerts |
| `inputs.conf` | Data input definitions |
| `outputs.conf` | Data routing configuration |
| `collections.conf` | KV Store collection definitions |
| `fields.conf` | Field definitions and extraction overrides |
| `workflow_actions.conf` | UI workflow action definitions |
| `commands.conf` | Custom search command registrations |

**Additional filesystem reads per app:**

| Path | Condition | Purpose |
|------|-----------|---------|
| `default/data/ui/views/*.xml` | `COLLECT_DASHBOARDS=true` | Classic XML dashboards |
| `local/data/ui/views/*.xml` | `COLLECT_DASHBOARDS=true` | Classic XML dashboards (local overrides) |
| `lookups/*.csv` | `COLLECT_LOOKUPS=true` | Lookup table CSV files |
| `metadata/default.meta` | Always | Macro export scope, sharing permissions |
| `metadata/local.meta` | Always | Macro export scope, sharing permissions |

### collect_system_macros() (lines ~3491-3571)

Collects macros from system-level directories:

| Source | Destination | Notes |
|--------|-------------|-------|
| `$SPLUNK_HOME/etc/system/local/macros.conf` | `_system/local/macros.conf` | Admin-created global macros |
| `$SPLUNK_HOME/etc/system/default/macros.conf` | `_system/default/macros.conf` | Splunk-provided reference macros |
| `$SPLUNK_HOME/etc/system/metadata/*.meta` | `_system/metadata/` | System-level metadata |
| `$SPLUNK_HOME/etc/users/*/*/local/macros.conf` | `_users/<user>/<app>/local/` | Only if `COLLECT_USER_MACROS=true` (off by default) |

---

## 8. Dashboard Collection

### Filesystem Copy (within collect_app_configs)

XML dashboards are copied directly from `$SPLUNK_HOME/etc/apps/<app>/default/data/ui/views/` and `local/data/ui/views/` using `cp *.xml` (glob, no `find` -- container compatible). These are tracked as `STATS_DASHBOARDS_XML` but NOT counted in the main `STATS_DASHBOARDS` counter (to avoid double-counting with REST).

### REST API Collection (collect_dashboards, lines ~3690-3988)

#### Pass 1: Discovery

For each selected app (or all apps if `EXPORT_ALL_APPS=true`):

```
GET /servicesNS/-/<app>/data/ui/views?output_mode=json&count=0
```

Extracts dashboard names from JSON response via grep.

#### Pass 2: Per-Dashboard Fetch

For each discovered dashboard:

```
GET /servicesNS/-/<app>/data/ui/views/<dashboard_name>?output_mode=json
```

The response is classified into Classic or Studio:

| Indicator | Classification |
|-----------|---------------|
| `version="2"` in `eai:data` | Dashboard Studio |
| `splunk-dashboard-studio` in response | Dashboard Studio (template reference) |
| `eai:data` starts with `{` | Dashboard Studio (direct JSON) |
| None of the above | Classic XML |

#### Output Paths (v2 App-Scoped Structure)

```
$EXPORT_DIR/<app>/dashboards/classic/<name>.json    # Classic dashboard REST response
$EXPORT_DIR/<app>/dashboards/studio/<name>.json     # Studio dashboard REST response
$EXPORT_DIR/<app>/dashboards/studio/<name>_definition.json  # Extracted Studio JSON definition
```

Studio dashboards with `<definition><![CDATA[{...}]]></definition>` blocks have their JSON extracted into a separate `_definition.json` file using Python.

#### Dashboard Studio Example JS Files

If `$SPLUNK_HOME/etc/apps/splunk-dashboard-studio/appserver/static/build/examples/` exists, all `.js` files are copied to `$EXPORT_DIR/dashboards_studio_examples/`.

---

## 9. Alert and Saved Search Collection

Alerts are collected in two ways:

1. **Filesystem** -- `savedsearches.conf` from each app's `default/` and `local/` directories (via `collect_app_configs`)
2. **REST API** -- The alerts inventory query (Query 6 in `collect_app_analytics`) uses:

```
| rest /servicesNS/-/<app>/saved/searches
| where is_scheduled=1
| table title, eai:acl.owner, ...
```

The saved searches REST metadata (with field filtering) is also collected in `collect_usage_analytics`:

```
GET /servicesNS/-/-/saved/searches?output_mode=json&count=0
    &f=title&f=eai:acl&f=is_scheduled&f=disabled&f=cron_schedule
    &f=alert.track&f=alert.severity&f=actions&f=next_scheduled_time
    &f=dispatch.earliest_time&f=dispatch.latest_time
```

This uses the `f=` parameter to request only metadata fields, NOT the full search SPL (a v4.6.0 fix to reduce response size).

---

## 10. RBAC Collection

Enabled by default (`COLLECT_RBAC=true`). Disable with `--no-rbac`.

### REST API Calls

| Endpoint | Output File | Notes |
|----------|-------------|-------|
| `GET /services/authentication/users?output_mode=json&count=0` | `dma_analytics/rbac/users.json` | All users with roles, type, default app |
| `GET /services/authorization/roles?output_mode=json&count=0` | `dma_analytics/rbac/roles.json` | All roles with capabilities, index access |
| `GET /services/authorization/capabilities?output_mode=json` | `dma_analytics/rbac/capabilities.json` | System capabilities inventory |
| `GET /services/admin/SAML-groups?output_mode=json` | `dma_analytics/rbac/saml_groups.json` | SAML group mappings |
| `GET /services/authentication/providers/SAML?output_mode=json` | `dma_analytics/rbac/saml_config.json` | SAML provider configuration |
| `GET /services/admin/LDAP-groups?output_mode=json` | `dma_analytics/rbac/ldap_groups.json` | LDAP group mappings |
| `GET /services/authentication/providers/LDAP?output_mode=json` | `dma_analytics/rbac/ldap_config.json` | LDAP provider configuration |

### Graceful 404 Handling

When SAML or LDAP is not configured, the endpoints return errors. The script writes a placeholder instead of failing:

```json
{"configured": false, "note": "SAML not configured or no group mappings defined"}
```

### Filesystem Copies

| Source | Destination | Notes |
|--------|-------------|-------|
| `$SPLUNK_HOME/etc/system/local/authentication.conf` | `dma_analytics/rbac/authentication.conf` | Password fields redacted via `sed` |
| `$SPLUNK_HOME/etc/system/local/authorize.conf` | `dma_analytics/rbac/authorize.conf` | Copied as-is |

### App-Scoped RBAC

When `--scoped` or `--apps` is active, an additional SPL search runs to find users who accessed the selected apps:

```
search index=_audit action=search info=granted (app="app1" OR app="app2") earliest=-30d
| stats dc(search_id) as searches, latest(_time) as last_active by user
```

Results go to `dma_analytics/rbac/users_active_in_apps.json`.

---

## 11. App Analytics -- 6 Global Queries

`collect_app_analytics()` (lines ~4469-4620) runs 6 global aggregate queries. These are the same queries used by the Cloud script. They are dispatched asynchronously via `run_usage_search()` with a 1-hour max wait per query.

Each query is guarded by a checkpoint. If the checkpoint exists (from a previous partial run), the query is skipped.

### Query 1: Dashboard Views

```
search index=_audit sourcetype=audittrail action=search info=granted
  (provenance="UI:Dashboard:*" OR provenance="UI:dashboard:*")
  user!="splunk-system-user" earliest=-<USAGE_PERIOD>
| rex field=provenance "UI:[Dd]ashboard:(?<dashboard_name>[\w\-\.]+)"
| where isnotnull(dashboard_name)
| eval view_session=user."_".floor(_time/30)
| stats dc(view_session) as view_count, dc(user) as unique_users,
        values(user) as viewers, latest(_time) as last_viewed
  by app, dashboard_name
| sort -view_count
```

**Output**: `dma_analytics/usage_analytics/dashboard_views_global.json`
**Checkpoint**: `dashboard_views`

Uses the `provenance` field (not `search_type=dashboard` which was broken). De-duplicates using 30-second view sessions per user.

### Query 2: User Activity

```
search index=_audit sourcetype=audittrail action=search info=granted
  user!="splunk-system-user" user!="nobody" earliest=-<USAGE_PERIOD>
| stats count as searches, dc(search_id) as unique_searches,
        latest(_time) as last_active
  by app, user
| sort -searches
```

**Output**: `dma_analytics/usage_analytics/user_activity_global.json`
**Checkpoint**: `user_activity`

### Query 3: Search Type Breakdown

```
search index=_audit sourcetype=audittrail action=search info=granted
  user!="splunk-system-user" earliest=-<USAGE_PERIOD>
| eval search_type=case(
    match(provenance, "^UI:[Dd]ashboard:"), "dashboard",
    match(search_id, "^(rt_)?scheduler__"), "scheduled",
    match(savedsearch_name, "^_ACCELERATE_"), "acceleration",
    match(search_id, "^SummaryDirector_"), "summarization",
    isnotnull(provenance) AND match(provenance, "^UI:"), "interactive",
    1=1, "other")
| stats count as total_searches, dc(user) as unique_users,
        dc(search_id) as unique_searches
  by app, search_type
| sort -total_searches
```

**Output**: `dma_analytics/usage_analytics/search_patterns_global.json`
**Checkpoint**: `search_patterns`

Derives `search_type` from `provenance`/`search_id` since `search_type` is NOT a native `_audit` field.

### Query 4: Daily Ingestion Volume

```
search index=_internal source=*license_usage.log type=Usage earliest=-<USAGE_PERIOD>
| eval index_name=idx
| stats sum(b) as total_bytes, dc(st) as sourcetype_count,
        dc(h) as host_count, min(_time) as earliest_event,
        max(_time) as latest_event
  by index_name
| eval total_gb=round(total_bytes/1024/1024/1024, 2),
       daily_avg_gb=round(total_gb/<days>, 2)
| sort -total_gb
```

**Output**: `dma_analytics/usage_analytics/index_volume_summary.json`
**Checkpoint**: `index_volume`
**Max wait**: 600 seconds
**Skipped when**: `--skip-internal` is set

### Query 5: Alert Firing Stats

```
search index=_internal sourcetype=scheduler earliest=-<USAGE_PERIOD>
| fields _time, app, savedsearch_name, status
| stats count as total_runs,
        sum(eval(if(status="success",1,0))) as successful,
        sum(eval(if(status="skipped",1,0))) as skipped,
        sum(eval(if(status!="success" AND status!="skipped",1,0))) as failed,
        latest(_time) as last_run
  by app, savedsearch_name
| sort -total_runs
```

**Output**: `dma_analytics/usage_analytics/alert_firing_global.json`
**Checkpoint**: `alert_firing`
**Skipped when**: `--skip-internal` is set

### Query 6: Alerts Inventory (per-app REST)

This is the only per-app query. For each selected app, it runs a blocking `| rest` search:

```
| rest /servicesNS/-/<app>/saved/searches
| where is_scheduled=1
| table title, eai:acl.owner, eai:acl.sharing, is_scheduled, disabled,
        cron_schedule, next_scheduled_time, alert.track, alert.severity,
        actions, dispatch.earliest_time, dispatch.latest_time
```

**Output**: `$EXPORT_DIR/<app>/splunk-analysis/alerts_inventory.json`
**Checkpoint**: `alerts_inventory`
**Dispatch mode**: Blocking (`exec_mode=blocking`)

---

## 12. Usage Analytics (Stripped in v4.6.0)

`collect_usage_analytics()` (lines ~4670-4807) has been stripped down from ~40 detailed SPL search jobs to a lightweight function that collects only ownership data and REST metadata.

### 3 Ownership Search Jobs (via run_usage_search)

| # | Query | Output File | Description |
|---|-------|-------------|-------------|
| 1 | `\| rest /servicesNS/-/-/data/ui/views \| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing` | `dashboard_ownership.json` | Maps each dashboard to its owner |
| 2 | `\| rest /servicesNS/-/-/saved/searches \| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, is_scheduled, alert.track` | `alert_ownership.json` | Maps each alert/saved search to its owner |
| 3 | Combined `\| rest` for views + saved searches, `\| stats sum(dashboards), sum(alerts) by owner` | `ownership_summary.json` | Ownership count summary by user |

**Checkpoint**: `usage_ownership` (single checkpoint for all 3)

When `--scoped` is active, `| rest` queries include an app filter clause via `eai:acl.app`.

### 3 REST API Calls (curl, no search jobs)

| # | Endpoint | Output File | Notes |
|---|----------|-------------|-------|
| 1 | `GET /servicesNS/-/-/saved/searches?count=0&f=title&f=eai:acl&f=is_scheduled&f=disabled&f=cron_schedule&f=alert.track&f=alert.severity&f=actions&f=next_scheduled_time&f=dispatch.earliest_time&f=dispatch.latest_time` | `saved_searches_all.json` | Metadata only (no search SPL) via `f=` field filtering |
| 2 | `GET /services/search/jobs?count=1000` | `recent_searches.json` | Recent search job metadata |
| 3 | `GET /services/server/introspection/kvstore` | `kvstore_stats.json` | KV Store health and stats |

### Summary Markdown

The function writes `USAGE_INTELLIGENCE_SUMMARY.md` to `dma_analytics/usage_analytics/` describing the collected data and providing a migration decision matrix.

---

## 13. Index and Data Statistics

`collect_index_stats()` (lines ~4809-4869) collects index configuration and metadata.

### Filesystem

| Source | Destination |
|--------|-------------|
| `$SPLUNK_HOME/etc/system/local/indexes.conf` | `dma_analytics/indexes/indexes.conf` |

### REST API

| Endpoint | Output File |
|----------|-------------|
| `GET /services/data/indexes?output_mode=json&count=0` | `dma_analytics/indexes/indexes_detailed.json` |
| `GET /services/data/inputs/all?output_mode=json&count=0` | `dma_analytics/indexes/data_inputs.json` |

### System-Level Configs (also copied in this phase)

The following files from `$SPLUNK_HOME/etc/system/local/` are copied to `$EXPORT_DIR/_system/local/`:

- `inputs.conf`
- `outputs.conf`
- `server.conf`

---

## 14. System Configuration Collection

System-level configurations are collected across multiple phases:

### In collect_index_stats (Phase 8)

| File | Destination |
|------|-------------|
| `$SPLUNK_HOME/etc/system/local/inputs.conf` | `_system/local/inputs.conf` |
| `$SPLUNK_HOME/etc/system/local/outputs.conf` | `_system/local/outputs.conf` |
| `$SPLUNK_HOME/etc/system/local/server.conf` | `_system/local/server.conf` |

### In collect_rbac (Phase 5)

| File | Destination | Notes |
|------|-------------|-------|
| `$SPLUNK_HOME/etc/system/local/authentication.conf` | `dma_analytics/rbac/authentication.conf` | Passwords redacted |
| `$SPLUNK_HOME/etc/system/local/authorize.conf` | `dma_analytics/rbac/authorize.conf` | Copied as-is |

### In collect_system_macros (Phase 2)

| File | Destination |
|------|-------------|
| `$SPLUNK_HOME/etc/system/local/macros.conf` | `_system/local/macros.conf` |
| `$SPLUNK_HOME/etc/system/default/macros.conf` | `_system/default/macros.conf` |
| `$SPLUNK_HOME/etc/system/metadata/*.meta` | `_system/metadata/` |

### In environment detection (not copied, only read)

These files are read during detection but not explicitly copied to the export:

- `$SPLUNK_HOME/etc/system/local/web.conf` -- read for `mgmtHostPort`
- `$SPLUNK_HOME/etc/system/local/distsearch.conf` -- read for distributed search detection

---

## 15. Async Search Dispatch (run_usage_search)

`run_usage_search()` (lines ~4261-4349) is the core function used by both `collect_app_analytics()` and `collect_usage_analytics()` to dispatch and poll Splunk searches.

### Dispatch

```bash
POST /services/search/jobs
  output_mode=json
  exec_mode=normal
  earliest_time=-<USAGE_PERIOD>
  latest_time=now
  search=<URL-encoded query>
```

### Polling

After extracting the SID from the dispatch response, the function polls:

```
GET /services/search/jobs/<sid>?output_mode=json
```

Checks `dispatchState` for completion. Polling uses an adaptive interval:

- Start: 5 seconds
- Increment: 5 seconds per iteration
- Cap: 30 seconds
- Maximum wait: configurable per query (default 3600 seconds / 1 hour)

### Job Cancellation on Timeout

If the search does not complete within `max_wait`, the job is cancelled:

```
POST /services/search/jobs/<sid>/control
  action=cancel
```

This frees the search quota on the Splunk server.

### Result Retrieval

```
GET /services/search/jobs/<sid>/results?output_mode=json&count=0
```

### Error Handling (HTTP Status)

| Code | Error Type | Written to Output |
|------|-----------|-------------------|
| `000` | Network error (no connection) | `{"error": "network_error", ...}` |
| `401` | Authentication failure | `{"error": "auth_error", ...}` |
| `403` | Permission denied | `{"error": "permission_error", ...}` |
| `404` | Endpoint not found | `{"error": "endpoint_not_found", ...}` |
| `500/502/503` | Server error | `{"error": "server_error", ...}` |

Each error increments `STATS_ERRORS` and writes a structured JSON error to the output file. The script continues with remaining queries.

---

## 16. Checkpointing and Resume

### Checkpoint File

Location: `$EXPORT_DIR/.analytics_checkpoint`

Each completed analytics query writes a line:

```
<checkpoint_name> <timestamp> <output_file>
```

### has_analytics_checkpoint

Before running a query, `has_analytics_checkpoint "<name>"` checks if the checkpoint file contains the named checkpoint. If yes, the query is skipped.

### Checkpoint Names (v4.6.0)

| Checkpoint | Phase | Query |
|------------|-------|-------|
| `dashboard_views` | App Analytics | Query 1 |
| `user_activity` | App Analytics | Query 2 |
| `search_patterns` | App Analytics | Query 3 |
| `index_volume` | App Analytics | Query 4 |
| `alert_firing` | App Analytics | Query 5 |
| `alerts_inventory` | App Analytics | Query 6 |
| `usage_ownership` | Usage Analytics | All 3 ownership queries |

### Resume Mode (--resume-collect FILE)

1. Extracts the specified `.tar.gz` archive to `/tmp/`
2. Detects which phases completed via `has_collected_data()` sentinel files
3. Continues from the first incomplete phase
4. Re-creates the final archive when complete

---

## 17. Export Directory Structure

```
dma_export_<hostname>_<timestamp>/
|
+-- manifest.json                                    # Schema v4.0 metadata
+-- dma-env-summary.md                               # Human-readable summary
+-- export.log                                       # Collection log
+-- .analytics_checkpoint                            # Checkpoint tracking
|
+-- dma_analytics/
|   +-- system_info/
|   |   +-- environment.json                         # OS, flavor, role, architecture
|   |   +-- server_info.json                         # GET /services/server/info
|   |   +-- installed_apps.json                      # GET /services/apps/local
|   |   +-- search_peers.json                        # GET /services/search/distributed/peers
|   |   +-- license_info.json                        # GET /services/licenser/licenses
|   |   +-- splunk.version                           # $SPLUNK_HOME/etc/splunk.version
|   |
|   +-- rbac/
|   |   +-- users.json                               # All users
|   |   +-- roles.json                               # All roles + capabilities
|   |   +-- capabilities.json                        # System capabilities inventory
|   |   +-- saml_groups.json                         # SAML group mappings (or placeholder)
|   |   +-- saml_config.json                         # SAML provider config (or placeholder)
|   |   +-- ldap_groups.json                         # LDAP group mappings (or placeholder)
|   |   +-- ldap_config.json                         # LDAP provider config (or placeholder)
|   |   +-- authentication.conf                      # Password-redacted copy
|   |   +-- authorize.conf                           # Authorization config
|   |   +-- users_active_in_apps.json                # (scoped mode only)
|   |
|   +-- usage_analytics/
|   |   +-- dashboard_views_global.json              # Query 1: Dashboard views
|   |   +-- user_activity_global.json                # Query 2: User activity
|   |   +-- search_patterns_global.json              # Query 3: Search type breakdown
|   |   +-- index_volume_summary.json                # Query 4: Ingestion volume
|   |   +-- alert_firing_global.json                 # Query 5: Alert firing stats
|   |   +-- dashboard_ownership.json                 # Ownership: dashboards
|   |   +-- alert_ownership.json                     # Ownership: alerts/searches
|   |   +-- ownership_summary.json                   # Ownership: by-user summary
|   |   +-- saved_searches_all.json                  # REST metadata (field-filtered)
|   |   +-- recent_searches.json                     # Recent search jobs
|   |   +-- kvstore_stats.json                       # KV Store introspection
|   |   +-- USAGE_INTELLIGENCE_SUMMARY.md            # Summary markdown
|   |   +-- ingestion_infrastructure/                # (reserved for future use)
|   |
|   +-- indexes/
|       +-- indexes.conf                             # System indexes.conf
|       +-- indexes_detailed.json                    # GET /services/data/indexes
|       +-- data_inputs.json                         # GET /services/data/inputs/all
|
+-- _system/
|   +-- local/
|   |   +-- inputs.conf
|   |   +-- outputs.conf
|   |   +-- server.conf
|   |   +-- macros.conf
|   +-- default/
|   |   +-- macros.conf
|   +-- metadata/
|       +-- default.meta
|       +-- local.meta
|
+-- <app_name>/                                      # One per collected app
|   +-- default/
|   |   +-- props.conf
|   |   +-- transforms.conf
|   |   +-- eventtypes.conf
|   |   +-- tags.conf
|   |   +-- indexes.conf
|   |   +-- macros.conf
|   |   +-- savedsearches.conf
|   |   +-- inputs.conf
|   |   +-- outputs.conf
|   |   +-- collections.conf
|   |   +-- fields.conf
|   |   +-- workflow_actions.conf
|   |   +-- commands.conf
|   |   +-- data/ui/views/*.xml                      # Classic dashboards (filesystem copy)
|   +-- local/
|   |   +-- (same structure as default)
|   +-- lookups/
|   |   +-- *.csv                                    # (when COLLECT_LOOKUPS=true)
|   +-- metadata/
|   |   +-- default.meta
|   |   +-- local.meta
|   +-- dashboards/
|   |   +-- classic/
|   |   |   +-- <name>.json                          # REST API response (Classic)
|   |   +-- studio/
|   |       +-- <name>.json                          # REST API response (Studio)
|   |       +-- <name>_definition.json               # Extracted JSON definition
|   +-- splunk-analysis/
|       +-- alerts_inventory.json                    # Query 6 per-app results
|
+-- dashboards_studio_examples/                      # (if Studio app installed)
|   +-- *.js                                         # Example JS definitions
|
+-- TROUBLESHOOTING.md                               # (generated if errors > 0)
```

### Archive Naming

```
dma_export_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz          # Original
dma_export_<hostname>_<YYYYMMDD_HHMMSS>_masked.tar.gz   # Anonymized copy
```

---

## 18. Archive Creation and Anonymization

### Two-Archive Model

When `ANONYMIZE_DATA=true` (the default), the script creates **two separate archives**:

1. **Original archive** (`dma_export_*.tar.gz`) -- untouched collected data
2. **Masked archive** (`dma_export_*_masked.tar.gz`) -- anonymized copy safe to share

### Anonymization Process

1. Copy the entire export directory to a temporary `_masked` directory
2. Run a Python-based anonymizer (`generate_python_anonymizer()`) over every `.json`, `.conf`, `.xml`, `.csv`, `.txt`, and `.meta` file
3. The anonymizer applies these transformations:
   - **Email addresses** -> `anon<hash>@anon.dma.local`
   - **RFC 1918 private IPs** (`10.x.x.x`, `172.16-31.x.x`, `192.168.x.x`) -> `[IP-REDACTED]`
   - **Hostnames** (in JSON `"host":` and conf `host =` patterns) -> `host-<hash>.anon.local`
   - **Webhook URLs** (Slack, PagerDuty, OpsGenie, Zapier) -> `https://webhook.anon.dma.local/hook-<hash>`
   - **API keys/tokens** (16+ char values in known JSON keys) -> `[API-KEY-<hash>]`
   - **Slack channels** -> `#anon-channel-<hash>`
   - **Usernames** (in JSON `"owner":`, `"user":`, etc.) -> `anon-user-<hash>`
4. JSON escape fixing: repairs invalid escape sequences created during anonymization
5. JSON validation: if the original file was valid JSON and the anonymized version is not, the original is kept
6. Tar the masked directory into the `_masked.tar.gz` archive
7. Clean up the temporary directory

### Preserved Values (Not Anonymized)

System users `nobody`, `admin`, `system`, `splunk-system-user`, `root` are never anonymized. IPs `localhost` and `127.0.0.1` are preserved. Already-anonymized values (detected by prefix patterns) are not double-anonymized.

### Remask Mode (--remask FILE)

Re-anonymizes an existing archive without connecting to Splunk:

1. Extract the archive
2. Run the anonymizer
3. Create a new `_masked.tar.gz`
4. Exit

---

## 19. CLI Flags Reference

| Flag | Arguments | Default | Description |
|------|-----------|---------|-------------|
| `--token` | `TOKEN` | -- | API token authentication (recommended for automation) |
| `-u`, `--username` | `USER` | -- | Splunk username |
| `-p`, `--password` | `PASS` | -- | Splunk password |
| `-h`, `--host` | `HOST` | `localhost` | Splunk host |
| `-P`, `--port` | `PORT` | `8089` | Splunk management port |
| `--splunk-home` | `PATH` | auto-detected | Splunk installation path |
| `--proxy` | `URL` | -- | HTTP proxy for all curl calls |
| `--apps` | `LIST` | all apps | Comma-separated app names to export |
| `--all-apps` | -- | `true` | Export all applications |
| `--scoped` | -- | `false` | Scope collections to selected apps only |
| `--quick` | -- | `false` | Skip global analytics (TESTING ONLY) |
| `--rbac` | -- | `true` | Collect RBAC/user data |
| `--no-rbac` | -- | -- | Disable RBAC collection |
| `--usage` | -- | `true` | Collect usage analytics |
| `--no-usage` | -- | -- | Disable usage analytics |
| `--analytics-period` | `N` | `30d` | Analytics time window (e.g., `7d`, `90d`, `365d`) |
| `--skip-internal` | -- | `false` | Skip `_audit`/`_internal` index searches |
| `--test-access` | -- | `false` | Pre-flight API access check (no export written) |
| `--remask` | `FILE` | -- | Re-anonymize an existing archive |
| `--resume-collect` | `FILE` | -- | Resume an interrupted export |
| `--anonymize` | -- | `true` | Enable two-archive anonymization |
| `--no-anonymize` | -- | -- | Disable anonymization |
| `-y`, `--yes` | -- | `false` | Auto-confirm all prompts |
| `-d`, `--debug` | -- | `false` | Enable verbose debug logging (`export_debug.log`) |
| `--help` | -- | -- | Show help and exit |

### Non-Interactive Mode

The script auto-enables non-interactive mode when:

- `--token` is provided (implies all credentials available)
- `-y` / `--yes` is used (auto-confirm)
- All required parameters are supplied via CLI flags

In non-interactive mode, all prompts use their default values.

---

## 20. Test-Access Mode

`--test-access` performs a pre-flight API access check across all collection categories without writing any export data.

### What It Tests

| Category | Endpoint Tested | What It Verifies |
|----------|----------------|------------------|
| Authentication | `POST /services/auth/login` | Credentials work |
| Server Info | `GET /services/server/info` | Basic API access |
| Apps | `GET /services/apps/local` | App listing permission |
| Dashboards | `GET /servicesNS/-/-/data/ui/views?count=1` | Dashboard read access |
| Saved Searches | `GET /servicesNS/-/-/saved/searches?count=1` | Alert/search read access |
| Users | `GET /services/authentication/users?count=1` | RBAC read access |
| Roles | `GET /services/authorization/roles?count=1` | Authorization read access |
| Indexes | `GET /services/data/indexes?count=1` | Index metadata access |
| Search | `POST /services/search/jobs` (simple test query) | Search dispatch permission |
| `_audit` | Search: `index=_audit \| head 1` | Internal index access |
| `_internal` | Search: `index=_internal \| head 1` | Internal index access |

Each test reports success/failure with HTTP status codes. The script exits after all tests complete -- no archive is produced.

---

## 21. Error Handling

### Error Categories

| Error Type | Detection | Script Behavior |
|-----------|-----------|-----------------|
| Network timeout | curl HTTP 000 | Log error, write error JSON, continue |
| Authentication failure | HTTP 401 | Log error, write error JSON, continue |
| Permission denied | HTTP 403 | Log error, write error JSON, continue |
| Endpoint not found | HTTP 404 | Write placeholder JSON, continue |
| Server error | HTTP 500/502/503 | Log error with response body, continue |
| File not found | `[ ! -f ... ]` | Skip file, log, continue |
| Directory not found | `[ ! -d ... ]` | Skip directory, log warning |
| Search job creation failure | No SID in response | Write error JSON, continue |
| Search timeout | Exceeds max_wait | Cancel job, write timeout error, continue |
| Python not found | No python3 available | Fatal -- exit with error |
| curl not installed | `command_exists` check | Fatal -- exit with error |

### Troubleshooting Report

If `STATS_ERRORS > 0` at the end of collection, the script generates `TROUBLESHOOTING.md` in the export directory containing:

- Environment information (version, host, flavor, role)
- Error summary and counts
- Phase 1 resilience statistics (API calls, retries, failures, batches)
- Detailed error analysis from failed search output files
- Common troubleshooting guides for network, auth, permission, timeout, and REST command issues

### Retry Logic

Failed API requests are retried up to `MAX_RETRIES` (default 3) times with exponential backoff starting at `RETRY_DELAY` (default 2 seconds).

---

## 22. API Endpoints Reference

### System Information

| Endpoint | Method | Output |
|----------|--------|--------|
| `/services/server/info` | GET | `dma_analytics/system_info/server_info.json` |
| `/services/apps/local` | GET | `dma_analytics/system_info/installed_apps.json` |
| `/services/search/distributed/peers` | GET | `dma_analytics/system_info/search_peers.json` |
| `/services/licenser/licenses` | GET | `dma_analytics/system_info/license_info.json` |

### Authentication and RBAC

| Endpoint | Method | Output |
|----------|--------|--------|
| `/services/auth/login` | POST | Session key (not saved to file) |
| `/services/authentication/users` | GET | `dma_analytics/rbac/users.json` |
| `/services/authorization/roles` | GET | `dma_analytics/rbac/roles.json` |
| `/services/authorization/capabilities` | GET | `dma_analytics/rbac/capabilities.json` |
| `/services/admin/SAML-groups` | GET | `dma_analytics/rbac/saml_groups.json` |
| `/services/authentication/providers/SAML` | GET | `dma_analytics/rbac/saml_config.json` |
| `/services/admin/LDAP-groups` | GET | `dma_analytics/rbac/ldap_groups.json` |
| `/services/authentication/providers/LDAP` | GET | `dma_analytics/rbac/ldap_config.json` |

### Knowledge Objects

| Endpoint | Method | Output |
|----------|--------|--------|
| `/servicesNS/-/<app>/data/ui/views` | GET | Dashboard listing (per-app) |
| `/servicesNS/-/<app>/data/ui/views/<name>` | GET | Individual dashboard content |
| `/servicesNS/-/-/saved/searches` | GET | `dma_analytics/usage_analytics/saved_searches_all.json` |

### Index and Data

| Endpoint | Method | Output |
|----------|--------|--------|
| `/services/data/indexes` | GET | `dma_analytics/indexes/indexes_detailed.json` |
| `/services/data/inputs/all` | GET | `dma_analytics/indexes/data_inputs.json` |

### Search Jobs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/search/jobs` | POST | Dispatch search (exec_mode=normal or blocking) |
| `/services/search/jobs/<sid>` | GET | Poll job status (dispatchState, isDone) |
| `/services/search/jobs/<sid>/results` | GET | Fetch results (count=0 for all) |
| `/services/search/jobs/<sid>/control` | POST | Cancel job (action=cancel) |
| `/services/search/jobs` | GET | `dma_analytics/usage_analytics/recent_searches.json` |

### SHC Detection

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/shcluster/member/info` | GET | Detect SHC membership, captain status |
| `/services/shcluster/member/members` | GET | SHC member count |

### Supplementary

| Endpoint | Method | Output |
|----------|--------|--------|
| `/services/server/introspection/kvstore` | GET | `dma_analytics/usage_analytics/kvstore_stats.json` |

---

## 23. Security Considerations

### Data Never Collected

| Data Type | Handling |
|-----------|----------|
| User passwords | Never collected. Redacted from `authentication.conf` via `sed`. |
| API tokens | Never saved to export files. Used only in memory for `AUTH_HEADER`. |
| LDAP bind passwords | Redacted from `authentication.conf`. |
| Session keys | Used transiently; not written to disk. |

### Password Redaction

When copying `authentication.conf` from filesystem:

```bash
sed 's/password\s*=.*/password = [REDACTED]/gi' "$SPLUNK_HOME/etc/system/local/authentication.conf"
```

### Debug Log Redaction

When `--debug` is enabled, the debug log file automatically redacts:

- Passwords in command-line arguments
- Token values in auth headers
- Session keys in API responses

### Export File Permissions

The archive is created with standard permissions. The script recommends:

- Transfer via SCP, SFTP, or other encrypted method
- Delete the export file after upload to DMA
- Use the `_masked` archive when sharing with third parties

### Sensitive Data in Anonymized Archives

The `_masked` archive anonymizes emails, hostnames, usernames, private IPs, webhook URLs, API keys, and Slack channels. Search SPL content and field values in dashboards/alerts are **not** fully anonymized -- they may contain business-specific terms, index names, and sourcetype names that reveal environment details.

---

*End of Specification*
*Version 4.6.0 | DMA Splunk Enterprise Export*
