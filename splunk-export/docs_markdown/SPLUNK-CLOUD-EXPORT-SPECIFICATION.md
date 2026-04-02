# DMA Splunk Cloud Export -- Technical Specification

## Version 4.6.0 | REST API-Only Data Collection for Splunk Cloud

**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Cloud README](README-SPLUNK-CLOUD.md) | [Export Schema](EXPORT-SCHEMA.md)

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Table of Contents

1. [Overview](#1-overview)
2. [Scripts and Platforms](#2-scripts-and-platforms)
3. [Configuration Defaults](#3-configuration-defaults)
4. [Authentication](#4-authentication)
5. [API Communication Layer](#5-api-communication-layer)
6. [Connectivity and Pre-flight Checks](#6-connectivity-and-pre-flight-checks)
7. [Collection Phases](#7-collection-phases)
8. [Async Search Dispatch](#8-async-search-dispatch)
9. [Global Analytics Queries](#9-global-analytics-queries)
10. [Usage Analytics (Supplementary)](#10-usage-analytics-supplementary)
11. [REST API Endpoints Reference](#11-rest-api-endpoints-reference)
12. [Output Structure and Archive Format](#12-output-structure-and-archive-format)
13. [Manifest Schema](#13-manifest-schema)
14. [Anonymization Algorithm](#14-anonymization-algorithm)
15. [Rate Limiting Strategy](#15-rate-limiting-strategy)
16. [Error Handling](#16-error-handling)
17. [Resume and Checkpoint System](#17-resume-and-checkpoint-system)
18. [Remask Mode](#18-remask-mode)
19. [Test-Access Mode](#19-test-access-mode)
20. [CLI Reference](#20-cli-reference)
21. [Security Considerations](#21-security-considerations)

---

## 1. Overview

This specification defines the complete technical behavior of the DMA Splunk Cloud Export script, version 4.6.0. The script collects Splunk Cloud configuration, knowledge objects, dashboards, alerts, RBAC data, index metadata, and usage analytics entirely via the Splunk REST API (port 8089). No file system access, SSH, or agent installation is required.

### Key Characteristics

| Aspect | Detail |
|--------|--------|
| **Access method** | REST API only (HTTPS to port 8089) |
| **Runs from** | Any machine with network access to the Splunk Cloud stack |
| **Authentication** | Token (Bearer or Splunk prefix, auto-detected) or username/password |
| **Dependencies (Bash)** | `curl`, Python 3 (required); `jq` (optional, improves filtering) |
| **Dependencies (PowerShell)** | None (uses built-in `Invoke-WebRequest`) |
| **Output** | `.tar.gz` archive with JSON files, optionally anonymized |
| **Max runtime** | 12 hours (configurable via `MAX_TOTAL_TIME`) |

### What Changed in v4.6.0

| Change | Detail |
|--------|--------|
| **`collect_usage_analytics` stripped** | No longer runs SPL queries. Now collects only REST-based ownership metadata, saved search metadata, and a summary document. |
| **Global analytics queries** | 6 queries in `collect_app_analytics` with `by app` grouping replace the previous per-app loop (N apps x 7 queries). |
| **Async search dispatch** | All analytics SPL queries use `exec_mode=normal`, poll `dispatchState`, 1-hour max timeout, auto-cancel on timeout. |
| **Blocking search preserved** | Only for fast `| rest` and `| tstats` queries that complete in seconds (alerts inventory, event counts). |

---

## 2. Scripts and Platforms

There are exactly **two** Cloud export scripts in v4.6.0:

| Script | Platform | Dependencies |
|--------|----------|--------------|
| `dma-splunk-cloud-export.sh` | Bash (macOS, Linux) | `curl`, Python 3, optional `jq` |
| `dma-splunk-cloud-export.ps1` | PowerShell 5.1+ / 7+ (Windows, cross-platform) | None |

The beta file has been deleted. Both scripts implement identical collection logic and produce archives with the same structure.

---

## 3. Configuration Defaults

All defaults can be overridden via environment variables (Bash) or parameters (PowerShell).

### Pagination and Batching

| Setting | Default | Description |
|---------|---------|-------------|
| `BATCH_SIZE` | 250 | Items per paginated API request |
| `RATE_LIMIT_DELAY` | 0.05 (50ms) | Delay between paginated batch requests |

### Timeouts

| Setting | Default | Description |
|---------|---------|-------------|
| `CONNECT_TIMEOUT` | 30s | TCP connection timeout |
| `API_TIMEOUT` | 120s | Per-request maximum time |
| `MAX_TOTAL_TIME` | 43200s (12h) | Script-wide runtime limit |
| `ANALYTICS_BUDGET` | 21600s (6h) | Dedicated analytics time budget |

### Retry and Backoff

| Setting | Default | Description |
|---------|---------|-------------|
| `MAX_RETRIES` | 3 | Retry attempts per failed request |
| `BACKOFF_MULTIPLIER` | 2 | Exponential backoff multiplier |

### Search Dispatch

| Setting | Default | Description |
|---------|---------|-------------|
| `API_DELAY_SECONDS` | 0.05 (50ms) | Delay between API calls |
| `MAX_CONCURRENT_SEARCHES` | 1 | No parallel search jobs |
| `SEARCH_POLL_INTERVAL` | 1s | Base poll frequency for job status |

### Checkpoint

| Setting | Default | Description |
|---------|---------|-------------|
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume capability |
| `CHECKPOINT_INTERVAL` | 50 | Save checkpoint every N items |

### Collection Flags (Defaults)

| Flag | Default | Description |
|------|---------|-------------|
| `COLLECT_CONFIGS` | true | Collect global configurations |
| `COLLECT_DASHBOARDS` | true | Collect dashboards per app |
| `COLLECT_ALERTS` | true | Collect saved searches and alerts per app |
| `COLLECT_RBAC` | **false** | Global user/role data (use `--rbac` to enable) |
| `COLLECT_USAGE` | **true** | Usage analytics collection |
| `COLLECT_INDEXES` | true | Index metadata |
| `COLLECT_LOOKUPS` | false | Download lookup table file contents |
| `COLLECT_AUDIT` | false | Audit log collection |
| `ANONYMIZE_DATA` | true | Run anonymization pass on export |
| `USAGE_PERIOD` | 30d | Time window for analytics queries |
| `SKIP_INTERNAL` | false | Skip `_internal` index searches |

### Blocked Endpoints

The following endpoints are known to be blocked or restricted in Splunk Cloud and are automatically skipped. When a request matches a blocked endpoint, the script returns an empty `{"entry": [], "skipped": true}` response without making a network call:

```
/services/licenser/licenses
/services/licenser/pools
/services/deployment/server/clients
/services/cluster/master/info
/services/cluster/master/peers
/services/shcluster/captain/info
/services/shcluster/captain/members
/services/data/inputs/monitor
/services/data/inputs/tcp/raw
/services/data/inputs/tcp/cooked
/services/data/inputs/udp
```

---

## 4. Authentication

### 4.1 Token Authentication (Recommended)

The script probes token validity by calling `/services/authentication/current-context?output_mode=json` with two prefixes in sequence:

1. **Bearer prefix**: `Authorization: Bearer <token>`
2. **Splunk prefix**: `Authorization: Splunk <token>`

The probe checks whether the response body contains the string `"username"`. The first prefix that succeeds is stored in `AUTH_HEADER` and used for all subsequent API calls.

```
POST https://<stack>:8089/services/authentication/current-context?output_mode=json
Header: Authorization: Bearer <token>

If response contains "username" -> success, use Bearer prefix
If not -> retry with "Splunk" prefix
If neither works -> error: "Token authentication failed (tried Bearer and Splunk prefixes)"
```

Tokens created via Splunk Settings > Tokens require the `Splunk` prefix. OAuth2/JWT tokens use `Bearer`.

### 4.2 Username/Password Authentication

Sends a POST to `/services/auth/login?output_mode=json` with URL-encoded credentials:

```
POST https://<stack>:8089/services/auth/login?output_mode=json
Body: username=<url_encoded_user>&password=<url_encoded_pass>

Success response: {"sessionKey": "<session_key>"}
```

The session key is stored and used as `Authorization: Splunk <session_key>` for all subsequent calls. Password special characters (`$`, backtick, `"`, `\`) are handled via Python `urllib.parse.quote` piped through stdin to avoid shell interpretation.

### 4.3 Required Capabilities

| Capability | Purpose |
|------------|---------|
| `admin_all_objects` | Access all knowledge objects across apps |
| `list_all_users` | Read user list |
| `search` | Dispatch analytics search jobs |

The script checks capabilities via `/services/authentication/current-context` after authentication and warns if any are missing.

---

## 5. API Communication Layer

### 5.1 `api_call` Function

Every REST API interaction goes through a single `api_call` function with this signature:

```
api_call(endpoint, method, data)
```

**Request construction:**

- GET requests: Query parameters appended to URL (`${url}?${data}`)
- POST requests: Data sent as `-d` body with `Content-Type: application/x-www-form-urlencoded`
- TLS verification disabled (`-k` flag) for self-signed certs
- Proxy support via `$CURL_PROXY_ARGS` when `--proxy` is set

**Pre-request checks:**

1. Blocked endpoint list check -- returns empty result immediately if matched
2. Total runtime limit check -- returns error if `MAX_TOTAL_TIME` exceeded
3. Rate limit delay (`RATE_LIMIT_DELAY` sleep before each call)

**Response handling by HTTP status code:**

| Code | Behavior |
|------|----------|
| 200, 201 | Success -- return response body |
| 000 | Timeout/connection error -- retry with linear backoff (`retries * 2` seconds) |
| 429 | Rate limited -- retry with exponential backoff (`retries * BACKOFF_MULTIPLIER * 2`, max 60s) |
| 401 | Auth failed -- return error immediately (special message for session key rejection on SHC) |
| 403 | Forbidden -- return error immediately |
| 404 | Not found -- if app-scoped resource endpoint, return empty `{"entry": []}` silently; otherwise return error |
| 500, 502, 503 | Server error -- retry with linear backoff (`retries * 2` seconds) |
| Other | Return error immediately |

After `MAX_RETRIES` exhausted, the call returns error.

### 5.2 `api_call_paginated` Function

For endpoints that may return large result sets:

```
api_call_paginated(endpoint, output_dir, category)
```

**Flow:**

1. Initial count request: `GET {endpoint}?output_mode=json&count=1` -- extracts `paging.total` from response
2. If total is 0, return immediately
3. Loop: `GET {endpoint}?output_mode=json&count={BATCH_SIZE}&offset={offset}`
4. Each batch saved as `batch_N.json` in `output_dir`
5. Sleep `RATE_LIMIT_DELAY` between batches
6. Save checkpoint every `CHECKPOINT_INTERVAL` batches
7. Progress displayed as percentage

---

## 6. Connectivity and Pre-flight Checks

### 6.1 Connectivity Test

Three-step diagnostic when connecting to a Splunk Cloud stack:

**Step 1: DNS Resolution** (skipped when proxy configured)
- Uses `nslookup`, `host`, or `dig +short` to resolve the hostname
- Extracts first IPv4 address from output

**Step 2: TCP Port Test** (skipped when proxy configured)
- Uses `nc -zv -w 10 <hostname> 8089`
- Reports whether port 8089 is open or blocked

**Step 3: HTTPS Connection**
- `curl -v -k --connect-timeout 15 --max-time 60 <url>/services/server/info`
- Reports HTTP status code, DNS lookup time, TCP connect time, TLS handshake time, total time
- Interprets curl exit codes: 6 (DNS), 7 (connection refused), 28 (timeout), 35 (TLS), 52 (empty response), 56 (network data failure)

### 6.2 Test-Access Mode (`--test-access`)

Pre-flight check that tests API access across 9 categories without exporting any data. Each test makes a minimal API call (`count=1` or short time range) and records PASS/FAIL/WARN/SKIP with a severity level (CRITICAL, REQUIRED, OPTIONAL).

**9 test categories in order:**

| # | Category | Endpoint Tested | Level |
|---|----------|-----------------|-------|
| 1 | System Info | `/services/server/info` | CRITICAL |
| 2 | Configurations | `/servicesNS/-/-/configs/conf-indexes` | REQUIRED |
| 3 | Dashboards | `/servicesNS/-/{app}/data/ui/views` | REQUIRED |
| 4 | Saved Searches / Alerts | `/servicesNS/-/{app}/saved/searches` | REQUIRED |
| 5 | RBAC | `/services/authentication/users` + `/services/authorization/roles` | OPTIONAL |
| 6 | Knowledge Objects | `/servicesNS/-/{app}/admin/macros` + `conf-props` + `lookup-table-files` | REQUIRED |
| 7 | App Analytics | `search index=_audit action=search ... earliest=-1h \| head 1` | OPTIONAL |
| 8 | Usage Analytics | `search index=_internal sourcetype=scheduler earliest=-1h \| head 1` | OPTIONAL |
| 9 | Indexes | `/services/data/indexes` | REQUIRED |

**Exit codes:** 0 = all pass, 1 = critical failure, 2 = some failures.

If test #1 (System Info) fails, all remaining tests are skipped and the script exits immediately.

---

## 7. Collection Phases

The export runs the following phases in strict order. Each phase is gated by its corresponding collection flag.

### Phase 1: Export Directory Setup

Creates the directory tree:

```
dma_cloud_export_<stack>_<YYYYMMDD_HHMMSS>/
  _export.log
  dma_analytics/
    system_info/
    rbac/
    usage_analytics/
      ingestion_infrastructure/
    indexes/
  _configs/
```

### Phase 2: System Information Collection

| Endpoint | Output File | Notes |
|----------|-------------|-------|
| `/services/server/info` | `dma_analytics/system_info/server_info.json` | Version, OS, GUID |
| `/services/apps/local?count=0` | `dma_analytics/system_info/installed_apps.json` | All apps |
| `/services/licenser/licenses` | `dma_analytics/system_info/license_info.json` | May be blocked |
| `/services/server/settings` | `dma_analytics/system_info/server_settings.json` | Server config |

### Phase 3: Configuration Collection

Only truly global configurations are collected here (per-app configs are in Phase 6):

| Config | Endpoint | Output |
|--------|----------|--------|
| indexes | `/servicesNS/-/-/configs/conf-indexes?output_mode=json&count=0` | `_configs/indexes.json` |
| inputs | `/servicesNS/-/-/configs/conf-inputs?output_mode=json&count=0` | `_configs/inputs.json` |
| outputs | `/servicesNS/-/-/configs/conf-outputs?output_mode=json&count=0` | `_configs/outputs.json` |

Props, transforms, and savedsearches are NOT collected globally. They are collected per-app in Phase 6 to avoid dumping data from all 400+ apps.

### Phase 4: Dashboard Collection

For each selected app:

1. Create directory structure: `{app}/dashboards/classic/` and `{app}/dashboards/studio/`
2. Fetch app dashboards: `GET /servicesNS/-/{app}/data/ui/views?output_mode=json&count=0&search=eai:acl.app={app}`
3. Save master list to `{app}/dashboards/dashboard_list.json`
4. For each dashboard name, fetch full detail: `GET /servicesNS/-/{app}/data/ui/views/{name}?output_mode=json`

**Dashboard type detection:**

- **Dashboard Studio v2**: Contains `version="2"` in XML, or `splunk-dashboard-studio` reference, or `eai:data` starts with `{`
- **Classic**: `<dashboard>` or `<form>` without `version="2"`

Studio dashboards saved to `{app}/dashboards/studio/{name}.json`. If the dashboard has a `<definition>` CDATA block containing JSON, the JSON is extracted via Python and saved as `{name}_definition.json`.

Classic dashboards saved to `{app}/dashboards/classic/{name}.json`.

Also saves a global master list: `dma_analytics/system_info/all_dashboards.json` from `GET /servicesNS/-/-/data/ui/views?output_mode=json&count=0`.

### Phase 5: Alert and Saved Search Collection

For each selected app:

1. Fetch: `GET /servicesNS/-/{app}/saved/searches?output_mode=json&count=0`
2. Filter by `acl.app == {app}` (via `jq` if available) to exclude globally-shared searches
3. Save to `{app}/savedsearches.json`

**Alert detection logic** (matches TypeScript parser -- single source of truth):

A saved search is classified as an alert if ANY of these are true:
- `alert.track` is `1` or `true`
- `alert_type` is `always`, `custom`, or starts with `number of`
- `alert_condition` is non-empty
- `alert_comparator` is non-empty
- `alert_threshold` is non-empty
- `counttype` contains `number of`
- `actions` has any non-empty value
- Any `action.*` key (`action.email`, `action.webhook`, `action.script`, `action.slack`, `action.pagerduty`, `action.summary_index`, `action.populate_lookup`) is `1` or `true`

### Phase 6: Knowledge Object Collection

For each selected app, the following endpoints are called. All responses are filtered by `acl.app == {app}` to include only objects owned by the app:

| Object Type | Endpoint | Output |
|-------------|----------|--------|
| Macros | `/servicesNS/-/{app}/admin/macros?output_mode=json&count=0` | `{app}/macros.json` |
| Eventtypes | `/servicesNS/-/{app}/saved/eventtypes?output_mode=json&count=0` | `{app}/eventtypes.json` |
| Tags | `/servicesNS/-/{app}/configs/conf-tags?output_mode=json&count=0` | `{app}/tags.json` |
| Field Extractions | `/servicesNS/-/{app}/data/transforms/extractions?output_mode=json&count=0` | `{app}/field_extractions.json` |
| Data Inputs | `/servicesNS/-/{app}/data/inputs/all?output_mode=json&count=0` | `{app}/inputs.json` |
| Props | `/servicesNS/-/{app}/configs/conf-props?output_mode=json&count=0` | `{app}/props.json` |
| Transforms | `/servicesNS/-/{app}/configs/conf-transforms?output_mode=json&count=0` | `{app}/transforms.json` |
| Lookups | `/servicesNS/-/{app}/data/lookup-table-files?output_mode=json&count=0` | `{app}/lookups.json` |

### Phase 7: RBAC Collection (optional, `--rbac`)

**Users:**
- In scoped mode: SPL search `index=_audit sourcetype=audittrail action=search info=granted` filtered to selected apps, excluding system users. Output: `dma_analytics/rbac/users_active_in_apps.json`
- In full mode: `GET /services/authentication/users?output_mode=json&count=0`. Output: `dma_analytics/rbac/users.json`

**Roles:**
- `GET /services/authorization/roles?output_mode=json&count=0` -> `dma_analytics/rbac/roles.json`

**Capabilities:**
- `GET /services/authorization/capabilities?output_mode=json` -> `dma_analytics/rbac/capabilities.json`

**SAML (graceful 404 handling):**
- `GET /services/admin/SAML-groups?output_mode=json` -> `dma_analytics/rbac/saml_groups.json`
- `GET /services/authentication/providers/SAML?output_mode=json` -> `dma_analytics/rbac/saml_config.json`
- If not configured, writes `{"configured": false, "note": "..."}`

**LDAP (graceful 404 handling):**
- `GET /services/admin/LDAP-groups?output_mode=json` -> `dma_analytics/rbac/ldap_groups.json`
- `GET /services/authentication/providers/LDAP?output_mode=json` -> `dma_analytics/rbac/ldap_config.json`
- If not configured, writes `{"configured": false, "note": "..."}`

**Current Context:**
- `GET /services/authentication/current-context?output_mode=json` -> `dma_analytics/rbac/current_context.json`

### Phase 8: Index Collection

- Full mode: `GET /services/data/indexes?output_mode=json&count=0` -> `dma_analytics/indexes/indexes.json`
- Extended stats: `GET /services/data/indexes-extended?output_mode=json&count=0` -> `dma_analytics/indexes/indexes_extended.json`
- Scoped mode: collects index references from per-app data instead of global list

### Phase 9: App Analytics (Global SPL Queries)

See [Section 9: Global Analytics Queries](#9-global-analytics-queries).

### Phase 10: Usage Analytics (Supplementary REST Data)

See [Section 10: Usage Analytics (Supplementary)](#10-usage-analytics-supplementary).

### Phase 11: Manifest Generation

See [Section 13: Manifest Schema](#13-manifest-schema).

### Phase 12: Anonymization

See [Section 14: Anonymization Algorithm](#14-anonymization-algorithm).

### Phase 13: Archive Creation

Two archives when anonymization is enabled:
1. `dma_cloud_export_<stack>_<timestamp>.tar.gz` -- original data
2. `dma_cloud_export_<stack>_<timestamp>_masked.tar.gz` -- anonymized copy

---

## 8. Async Search Dispatch

### 8.1 `run_analytics_search` (Async)

Used for all SPL queries that may take significant time (analytics queries against `_audit`, `_internal`).

**Dispatch flow:**

```
Step 1: Dispatch
  POST /services/search/jobs
  Body: search=<url_encoded_spl>&output_mode=json&exec_mode=normal&max_time=0
  Response: {"sid": "<search_id>"}

Step 2: Poll dispatchState
  GET /services/search/jobs/<sid>?output_mode=json
  Read: response.entry[0].content.dispatchState

  States: QUEUED -> PARSING -> RUNNING -> FINALIZING -> DONE
          (or FAILED at any point)

  Poll interval: starts at 5s, increases by 5s per iteration, caps at 30s
  Progress log: every ~60s

Step 3: Timeout handling
  Default max_wait: 3600s (1 hour)
  On timeout:
    POST /services/search/jobs/<sid>/control
    Body: action=cancel
  Writes error JSON to output file

Step 4: Fetch results (on DONE)
  GET /services/search/jobs/<sid>/results?output_mode=json&count=0
  Save complete results to output file

Step 5: Failure handling (on FAILED)
  Extract error message from response.entry[0].content.messages[0].text
  Write error JSON to output file
```

**Error JSON format:**

```json
{
  "error": "<error_type>",
  "label": "<query_description>",
  "elapsed_seconds": 42,
  "message": "<detailed_error_message>"
}
```

Error types: `search_dispatch_failed`, `no_sid_returned`, `search_timeout`, `search_failed`, `results_fetch_failed`

### 8.2 `run_analytics_search_blocking` (Legacy)

Retained only for fast queries that complete in seconds:
- `| rest` queries (alerts inventory)
- `| tstats` queries (event counts)

Uses `exec_mode=blocking` with a short timeout. Falls back to empty result on failure.

---

## 9. Global Analytics Queries

The `collect_app_analytics` function runs 6 global aggregate queries. Each query groups results `by app`, and the DMA Curator Server splits them into per-app files after import. This replaced the previous approach of N x 7 per-app queries.

All queries use `earliest=-{USAGE_PERIOD}` (default 30d). Each query checks for a checkpoint before running and saves one on success.

### Query 1: Dashboard Views (CRITICAL)

```
search index=_audit sourcetype=audittrail action=search info=granted
  {app_filter}
  (provenance="UI:Dashboard:*" OR provenance="UI:dashboard:*")
  user!="splunk-system-user"
  earliest=-{USAGE_PERIOD}
| rex field=provenance "UI:[Dd]ashboard:(?<dashboard_name>[\w\-\.]+)"
| where isnotnull(dashboard_name)
| eval view_session=user."_".floor(_time/30)
| stats dc(view_session) as view_count, dc(user) as unique_users,
        values(user) as viewers, latest(_time) as last_viewed
        by app, dashboard_name
| sort -view_count
```

- **Timeout**: 3600s (1 hour)
- **Output**: `dma_analytics/usage_analytics/dashboard_views_global.json`
- **Key detail**: Uses `provenance` field (not `search_type=dashboard`, which is not a native `_audit` field). View session de-duplication uses a 30-second window per user to count page loads rather than individual panel searches.

### Query 2: User Activity

```
search index=_audit sourcetype=audittrail action=search info=granted
  {app_filter}
  user!="splunk-system-user" user!="nobody"
  earliest=-{USAGE_PERIOD}
| stats count as searches, dc(search_id) as unique_searches,
        latest(_time) as last_active
        by app, user
| sort -searches
```

- **Timeout**: 3600s
- **Output**: `dma_analytics/usage_analytics/user_activity_global.json`

### Query 3: Search Type Breakdown

```
search index=_audit sourcetype=audittrail action=search info=granted
  {app_filter}
  user!="splunk-system-user"
  earliest=-{USAGE_PERIOD}
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

- **Timeout**: 1800s (30 minutes)
- **Output**: `dma_analytics/usage_analytics/search_patterns_global.json`
- **Key detail**: `search_type` is computed from `provenance` and `search_id` fields. Monitoring Console computes this with eval case(), but the raw `_audit` index does not have a `search_type` field.

### Query 4: Daily Ingestion Volume

```
search index=_internal source=*license_usage.log type=Usage
  earliest=-{USAGE_PERIOD}
| eval index_name=idx
| stats sum(b) as total_bytes, dc(st) as sourcetype_count,
        dc(h) as host_count, min(_time) as earliest_event,
        max(_time) as latest_event
        by index_name
| eval total_gb=round(total_bytes/1024/1024/1024, 2),
       daily_avg_gb=round(total_gb/{usage_days}, 2)
| sort -total_gb
| fields index_name, total_bytes, total_gb, daily_avg_gb,
         sourcetype_count, host_count, earliest_event, latest_event
```

- **Timeout**: 600s (10 minutes)
- **Output**: `dma_analytics/usage_analytics/index_volume_summary.json`
- **Skipped when**: `--skip-internal` is set (writes skip reason JSON)
- **Fallback (4b)**: `| tstats count where index=* by index, _time span=1d` -> `index_event_counts_daily.json` (blocking, 60s timeout)

### Query 5: Alert Firing Stats

```
search index=_internal sourcetype=scheduler
  {app_filter}
  earliest=-{USAGE_PERIOD}
| fields _time, app, savedsearch_name, status
| stats count as total_runs,
        sum(eval(if(status="success",1,0))) as successful,
        sum(eval(if(status="skipped",1,0))) as skipped,
        sum(eval(if(status!="success" AND status!="skipped",1,0))) as failed,
        latest(_time) as last_run
        by app, savedsearch_name
| sort -total_runs
```

- **Timeout**: 3600s
- **Output**: `dma_analytics/usage_analytics/alert_firing_global.json`
- **Skipped when**: `--skip-internal` is set

### Query 6: Alerts Inventory (per-app, blocking)

For each selected app:

```
| rest /servicesNS/-/{app}/saved/searches
| search (is_scheduled=1 OR alert.track=1)
| table title, cron_schedule, alert.severity, alert.track, actions, disabled
| rename title as alert_name
```

- **Timeout**: 120s per app (blocking)
- **Output**: `{app}/splunk-analysis/alerts_inventory.json`

---

## 10. Usage Analytics (Supplementary)

The `collect_usage_analytics` function in v4.6.0 collects **only REST-based supplementary data**. All SPL analytics queries have moved to `collect_app_analytics` (Phase 9).

### REST-Based Metadata

| Data | Endpoint | Params | Output |
|------|----------|--------|--------|
| Saved search metadata | `/servicesNS/-/-/saved/searches` | `output_mode=json&count=0&f=title&f=eai:acl&f=is_scheduled&f=disabled&f=cron_schedule&f=alert.track&f=alert.severity&f=actions&f=next_scheduled_time&f=dispatch.earliest_time&f=dispatch.latest_time` | `saved_searches_all.json` |
| Recent search jobs | `/services/search/jobs` | `output_mode=json&count=100` | `recent_searches.json` |
| KVStore status | `/services/kvstore/status` | `output_mode=json` | `kvstore_stats.json` |

The `f=` parameter on saved searches requests only metadata fields, preventing the full SPL text from being returned (which can exceed 256MB on large environments).

In scoped mode, `saved_searches_all.json` is post-filtered with `jq` to include only entries where `acl.app` matches a selected app.

### Ownership Mapping

Collected via direct REST API calls (not SPL `| rest`):

**Dashboard ownership:**
- `GET /servicesNS/-/-/data/ui/views?output_mode=json&count=0&f=title&f=eai:acl`
- Transformed to: `{results: [{dashboard, app, owner, sharing}, ...]}`
- Output: `dashboard_ownership.json`

**Alert ownership:**
- `GET /servicesNS/-/-/saved/searches?output_mode=json&count=0&f=title&f=eai:acl&f=is_scheduled&f=alert.track`
- Transformed to: `{results: [{alert_name, app, owner, sharing, is_scheduled, alert_track}, ...]}`
- Output: `alert_ownership.json`

**Ownership summary:**
- Computed from the dashboard and alert ownership files
- Groups by owner, counts dashboards and alerts per owner
- Output: `ownership_summary.json`

### Usage Intelligence Summary

A Markdown file (`USAGE_INTELLIGENCE_SUMMARY.md`) is generated with a migration prioritization framework, describing what data was collected and how to interpret it.

---

## 11. REST API Endpoints Reference

### System Information

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/server/info` | GET | Server version, OS, GUID |
| `/services/server/settings` | GET | Server configuration |
| `/services/apps/local` | GET | Installed apps list |
| `/services/licenser/licenses` | GET | License information (often blocked) |

### Knowledge Objects (per-app)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/servicesNS/-/{app}/data/ui/views` | GET | Dashboards for app |
| `/servicesNS/-/{app}/data/ui/views/{name}` | GET | Single dashboard detail |
| `/servicesNS/-/{app}/saved/searches` | GET | Saved searches and alerts |
| `/servicesNS/-/{app}/admin/macros` | GET | Search macros |
| `/servicesNS/-/{app}/saved/eventtypes` | GET | Event types |
| `/servicesNS/-/{app}/configs/conf-tags` | GET | Tags |
| `/servicesNS/-/{app}/data/lookup-table-files` | GET | Lookup definitions |
| `/servicesNS/-/{app}/data/transforms/extractions` | GET | Field extractions |
| `/servicesNS/-/{app}/data/inputs/all` | GET | Data inputs |
| `/servicesNS/-/{app}/configs/conf-props` | GET | Props configuration |
| `/servicesNS/-/{app}/configs/conf-transforms` | GET | Transforms configuration |

### Global Knowledge Objects

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/servicesNS/-/-/data/ui/views` | GET | All dashboards (master list + ownership) |
| `/servicesNS/-/-/saved/searches` | GET | All saved searches (metadata + ownership) |

### Configurations (global)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/servicesNS/-/-/configs/conf-indexes` | GET | Index configuration |
| `/servicesNS/-/-/configs/conf-inputs` | GET | Input configuration |
| `/servicesNS/-/-/configs/conf-outputs` | GET | Output configuration |

### RBAC

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/authentication/users` | GET | All users |
| `/services/authorization/roles` | GET | All roles |
| `/services/authentication/current-context` | GET | Current user capabilities |
| `/services/authorization/capabilities` | GET | System capabilities list |
| `/services/admin/SAML-groups` | GET | SAML group-to-role mappings |
| `/services/authentication/providers/SAML` | GET | SAML provider configuration |
| `/services/admin/LDAP-groups` | GET | LDAP group-to-role mappings |
| `/services/authentication/providers/LDAP` | GET | LDAP provider configuration |

### Indexes

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/data/indexes` | GET | Index list and settings |
| `/services/data/indexes-extended` | GET | Extended index statistics |

### Search Jobs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/search/jobs` | POST | Create/dispatch search job |
| `/services/search/jobs` | GET | List recent jobs |
| `/services/search/jobs/{sid}` | GET | Check job status (dispatchState) |
| `/services/search/jobs/{sid}/results` | GET | Fetch search results |
| `/services/search/jobs/{sid}/control` | POST | Control job (cancel, pause, etc.) |

### Other

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/kvstore/status` | GET | KVStore status |
| `/services/auth/login` | POST | Username/password authentication |
| `/services/authentication/current-context` | GET | Token validation probe |

---

## 12. Output Structure and Archive Format

### Archive Naming

```
dma_cloud_export_<stack_clean>_<YYYYMMDD_HHMMSS>.tar.gz        (original)
dma_cloud_export_<stack_clean>_<YYYYMMDD_HHMMSS>_masked.tar.gz  (anonymized)
```

`<stack_clean>` is the stack hostname with `.splunkcloud.com` stripped and non-alphanumeric characters replaced with `_`.

### Directory Structure

```
dma_cloud_export_<stack>_<timestamp>/
|
|-- _export.log                              # Export session log
|-- _anonymization_report.json               # Anonymization statistics (if enabled)
|-- _configs/
|   |-- indexes.json                         # Global indexes config
|   |-- inputs.json                          # Global inputs config
|   |-- outputs.json                         # Global outputs config
|
|-- dma_analytics/
|   |-- manifest.json                        # Manifest (schema v4.0)
|   |-- system_info/
|   |   |-- server_info.json
|   |   |-- installed_apps.json
|   |   |-- license_info.json
|   |   |-- server_settings.json
|   |   |-- all_dashboards.json              # Master dashboard list
|   |
|   |-- rbac/                                # Only when --rbac enabled
|   |   |-- users.json
|   |   |-- roles.json
|   |   |-- capabilities.json
|   |   |-- current_context.json
|   |   |-- saml_groups.json
|   |   |-- saml_config.json
|   |   |-- ldap_groups.json
|   |   |-- ldap_config.json
|   |   |-- users_active_in_apps.json        # Scoped mode only
|   |
|   |-- usage_analytics/
|   |   |-- dashboard_views_global.json      # Query 1
|   |   |-- user_activity_global.json        # Query 2
|   |   |-- search_patterns_global.json      # Query 3
|   |   |-- index_volume_summary.json        # Query 4
|   |   |-- index_event_counts_daily.json    # Query 4b (tstats)
|   |   |-- alert_firing_global.json         # Query 5
|   |   |-- saved_searches_all.json          # REST metadata
|   |   |-- recent_searches.json             # REST jobs
|   |   |-- kvstore_stats.json               # REST KVStore
|   |   |-- dashboard_ownership.json         # REST ownership
|   |   |-- alert_ownership.json             # REST ownership
|   |   |-- ownership_summary.json           # Computed
|   |   |-- USAGE_INTELLIGENCE_SUMMARY.md    # Migration guide
|   |
|   |-- indexes/
|       |-- indexes.json
|       |-- indexes_extended.json
|
|-- {AppName}/                               # One per selected app
|   |-- dashboards/
|   |   |-- dashboard_list.json
|   |   |-- classic/
|   |   |   |-- {dashboard_name}.json
|   |   |-- studio/
|   |       |-- {dashboard_name}.json
|   |       |-- {dashboard_name}_definition.json  # Extracted JSON
|   |
|   |-- savedsearches.json
|   |-- macros.json
|   |-- eventtypes.json
|   |-- tags.json
|   |-- field_extractions.json
|   |-- inputs.json
|   |-- props.json
|   |-- transforms.json
|   |-- lookups.json
|   |
|   |-- splunk-analysis/
|       |-- alerts_inventory.json            # Query 6
```

---

## 13. Manifest Schema

The manifest (`dma_analytics/manifest.json`) uses schema version 4.0 with archive structure version v2.

```json
{
  "schema_version": "4.0",
  "archive_structure_version": "v2",
  "export_tool": "dma-splunk-cloud-export",
  "export_tool_version": "4.6.0",
  "export_timestamp": "2026-04-02T12:00:00Z",
  "export_duration_seconds": 1234,

  "archive_structure": {
    "version": "v2",
    "description": "App-centric dashboard organization prevents name collisions",
    "dashboard_location": "{AppName}/dashboards/classic/ and {AppName}/dashboards/studio/"
  },

  "source": {
    "hostname": "acme-corp.splunkcloud.com",
    "fqdn": "acme-corp.splunkcloud.com",
    "platform": "Splunk Cloud",
    "platform_version": "classic|victoria"
  },

  "splunk": {
    "home": "cloud",
    "version": "9.x.x",
    "build": "cloud",
    "flavor": "cloud",
    "role": "search_head",
    "architecture": "cloud",
    "is_cloud": true,
    "cloud_type": "classic|victoria",
    "server_guid": "<guid>"
  },

  "collection": {
    "configs": true,
    "dashboards": true,
    "alerts": true,
    "rbac": false,
    "usage_analytics": true,
    "usage_period": "30d",
    "indexes": true,
    "lookups": false,
    "data_anonymized": true
  },

  "statistics": {
    "apps_exported": 5,
    "dashboards_classic": 120,
    "dashboards_studio": 30,
    "dashboards_total": 150,
    "alerts": 45,
    "saved_searches": 200,
    "users": 0,
    "roles": 0,
    "indexes": 25,
    "api_calls_made": 1500,
    "rate_limit_hits": 0,
    "errors": 2,
    "warnings": 5,
    "total_files": 350,
    "total_size_bytes": 52428800
  },

  "apps": [
    {
      "name": "myapp",
      "dashboards": 25,
      "dashboards_classic": 20,
      "dashboards_studio": 5,
      "alerts": 10,
      "saved_searches": 40
    }
  ],

  "usage_intelligence": {
    "prioritization": {
      "top_dashboards": [],
      "top_alerts": [],
      "top_users": []
    },
    "volume": {
      "index_volume": [],
      "index_events": [],
      "note": "See index_volume_summary.json for per-index daily ingestion"
    },
    "search_patterns": []
  }
}
```

The `usage_intelligence` section references top-10 slices from the global analytics query results.

---

## 14. Anonymization Algorithm

### Two-Archive Workflow

When `ANONYMIZE_DATA=true` (default):

1. Complete data collection to `EXPORT_DIR`
2. Create archive #1: `{name}.tar.gz` (original, untouched data)
3. Run anonymization on `EXPORT_DIR` in-place
4. Create archive #2: `{name}_masked.tar.gz` (anonymized copy)
5. Delete `EXPORT_DIR`

### Python-Based Anonymizer

A Python script is generated inline at runtime (`$EXPORT_DIR/.anonymizer.py`) and processes all `.json`, `.conf`, `.xml`, `.csv`, `.txt`, and `.meta` files. Binary files are skipped.

**Transformations applied per line:**

1. **Email addresses**: Regex `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}` replaced with `anon<md5_hash_8chars>@anon.dma.local`. Already-anonymized emails (`@anon.dma.local`, `@example.com`, `@localhost`) are skipped.

2. **Private IP addresses (RFC 1918 only)**:
   - `10.x.x.x` -> `[IP-REDACTED]`
   - `172.16-31.x.x` -> `[IP-REDACTED]`
   - `192.168.x.x` -> `[IP-REDACTED]`
   - Public IPs are NOT redacted (prevents breaking version numbers and other dot-separated values)

3. **Hostnames in JSON**: Keys `host`, `hostname`, `splunk_server`, `server`, `serverName` have their string values replaced with `host-<md5_hash_8chars>.anon.local`. Reserved values (`localhost`, `127.0.0.1`, `null`, `none`, `*`, empty) are preserved.

4. **Hostnames in conf format**: `key=hostname` and `key = hostname` patterns for the same key set.

### Consistency

All anonymization uses MD5 hashing (`hashlib.md5(value.encode()).hexdigest()[:8]`) to ensure the same input always produces the same output across all files in the export. This preserves referential integrity (the same user appears as the same anonymized user everywhere).

### JSON Safety

After processing, the anonymizer:
1. Fixes invalid JSON escape sequences created during replacement (e.g., `\u` followed by non-hex, `\a`, `\h`)
2. Validates JSON parsability before saving
3. If anonymization would corrupt valid JSON, the file is left unmodified

### Fallback

If Python is not available, a sed-based fallback handles only IP address redaction (no email or hostname anonymization).

### Report

After anonymization, `_anonymization_report.json` is written:

```json
{
  "anonymization_applied": true,
  "timestamp": "2026-04-02T12:00:00Z",
  "statistics": {
    "files_processed": 350,
    "unique_emails_anonymized": 42,
    "unique_hosts_anonymized": 15,
    "ip_addresses": "all_redacted"
  },
  "transformations": {
    "emails": "original@domain.com -> anon######@anon.dma.local",
    "hostnames": "server.example.com -> host-########.anon.local",
    "ipv4": "x.x.x.x -> [IP-REDACTED]"
  }
}
```

---

## 15. Rate Limiting Strategy

### Between API Calls

Every `api_call` invocation sleeps `RATE_LIMIT_DELAY` (default 50ms) before making the request. This applies to all calls including retries.

### Between Paginated Batches

After each batch in `api_call_paginated`, sleep `RATE_LIMIT_DELAY` (50ms).

### On 429 (Rate Limited)

Exponential backoff: `wait_time = retries * BACKOFF_MULTIPLIER * 2`, capped at 60 seconds. Retry counter increments. After `MAX_RETRIES` exhausted, the call fails.

### On 500/502/503 (Server Error)

Linear backoff: `wait_time = retries * 2` seconds. Same retry limit.

### On 000 (Timeout/Connection Error)

Linear backoff: `wait_time = retries * 2` seconds.

### Search Job Polling

Adaptive interval for `dispatchState` polling:
- Start at 5 seconds
- Increase by 5 seconds each iteration
- Cap at 30 seconds
- Prevents excessive API load during long-running searches

---

## 16. Error Handling

### Error Classification

| Error Type | Behavior | Retry |
|------------|----------|-------|
| Network timeout (000) | Retry with backoff | Yes |
| Rate limit (429) | Retry with exponential backoff | Yes |
| Auth failure (401) | Fail immediately | No |
| Forbidden (403) | Fail immediately | No |
| Not found (404) on app resource | Return empty result | No |
| Not found (404) on other | Warn and continue | No |
| Server error (5xx) | Retry with backoff | Yes |
| Max runtime exceeded | Graceful shutdown | No |
| Search dispatch failed | Write error JSON, continue | No |
| Search timeout | Cancel job, write error JSON, continue | No |

### Graceful Degradation

The script never aborts on a single collection failure. If dashboards fail, alerts still proceed. If analytics searches fail, REST metadata still proceeds. Each phase records its errors and continues.

### Error and Warning Tracking

Global counters track `STATS_ERRORS`, `STATS_WARNINGS`, `STATS_API_CALLS`, `STATS_API_RETRIES`, `STATS_API_FAILURES`, `STATS_RATE_LIMITS`. These appear in the manifest and final summary.

### Search Error JSON

When a search job fails or times out, the output file receives a structured error instead of being left empty:

```json
{
  "error": "search_timeout",
  "label": "Dashboard views (global, provenance-based)",
  "elapsed_seconds": 3601,
  "message": "Exceeded max wait of 3600s. The _audit index may be very large."
}
```

---

## 17. Resume and Checkpoint System

### Checkpoint Files

During collection, checkpoints are saved to `$EXPORT_DIR/.export_checkpoint` at regular intervals (`CHECKPOINT_INTERVAL=50` batches for paginated calls).

For analytics queries, each completed query saves a checkpoint to `$EXPORT_DIR/.analytics_checkpoint`. On resume, only incomplete queries are re-run.

### Resume Mode (`--resume-collect`)

```bash
./dma-splunk-cloud-export.sh --resume-collect previous_export.tar.gz
```

1. Extracts previous `.tar.gz` to a working directory
2. Detects already-collected data (dashboards, alerts, configs, etc.)
3. Reconnects to Splunk Cloud and fills gaps
4. Creates versioned output with `-v1`, `-v2` suffixes to preserve prior exports
5. Per-app skip logic: skips dashboards, alerts, and knowledge objects for already-collected apps
6. Global skip logic: skips configs, RBAC, usage analytics, and indexes if already present

---

## 18. Remask Mode

```bash
./dma-splunk-cloud-export.sh --remask /path/to/original_export.tar.gz
```

Re-anonymizes an existing archive without connecting to Splunk:

1. Extract archive to temp directory
2. Check disk space (needs ~2x extracted size)
3. Run full anonymization pass on extracted files
4. Create new `_masked.tar.gz` archive
5. Clean up temp directory
6. Original archive is NOT modified

---

## 19. Test-Access Mode

See [Section 6.2](#62-test-access-mode---test-access) for the full 9-category test specification.

### Usage

```bash
# Bash
./dma-splunk-cloud-export.sh --stack acme.splunkcloud.com --token XXX --test-access

# PowerShell
.\dma-splunk-cloud-export.ps1 -Stack acme.splunkcloud.com -Token XXX -TestAccess
```

### Output Format

Each test prints a status line:

```
  [OK  ]  System Info                          Splunk v9.2.0
  [OK  ]  Configurations (indexes)             1 entries
  [FAIL]  RBAC (users/roles)                   Both denied
  [SKIP]  Usage Analytics (_internal)          Skipped (--skip-internal)
```

Summary table printed at the end with PASS/FAIL/WARN/SKIP counts and a verdict.

---

## 20. CLI Reference

### Bash (`dma-splunk-cloud-export.sh`)

| Flag | Argument | Description |
|------|----------|-------------|
| `--stack` | URL | Splunk Cloud stack (e.g., `acme.splunkcloud.com`) |
| `--token` | TOKEN | API token for authentication |
| `--user` | USER | Username (alternative to token) |
| `--password` | PASS | Password (alternative to token) |
| `--all-apps` | -- | Export all applications |
| `--apps` | LIST | Comma-separated app names |
| `--output` | DIR | Output directory |
| `--rbac` | -- | Enable RBAC/users collection (OFF by default) |
| `--usage` | -- | Enable usage analytics collection (ON by default) |
| `--no-usage` | -- | Disable usage analytics |
| `--no-rbac` | -- | Disable RBAC collection (legacy, already off) |
| `--analytics-period` | N | Analytics time window (e.g., `7d`, `30d`, `90d`) |
| `--skip-internal` | -- | Skip `_internal` index searches |
| `--scoped` | -- | Scope collections to selected apps only |
| `--proxy` | URL | Route all connections through proxy |
| `--resume-collect` | FILE | Resume from previous `.tar.gz` archive |
| `--test-access` | -- | Pre-flight access check (no export) |
| `--remask` | FILE | Re-anonymize existing archive offline |
| `-d`, `--debug` | -- | Enable verbose debug logging |
| `--help` | -- | Show help text |

### PowerShell (`dma-splunk-cloud-export.ps1`)

| Parameter | Argument | Bash Equivalent |
|-----------|----------|-----------------|
| `-Stack` | URL | `--stack` |
| `-Token` | TOKEN | `--token` |
| `-User` | USER | `--user` |
| `-Password` | PASS | `--password` |
| `-AllApps` | -- | `--all-apps` |
| `-Apps` | LIST | `--apps` |
| `-Output` | DIR | `--output` |
| `-Rbac` | -- | `--rbac` |
| `-Usage` | -- | `--usage` |
| `-NoUsage` | -- | `--no-usage` |
| `-AnalyticsPeriod` | N | `--analytics-period` |
| `-SkipInternal` | -- | `--skip-internal` |
| `-Scoped` | -- | `--scoped` |
| `-Proxy` | URL | `--proxy` |
| `-ResumeCollect` | FILE | `--resume-collect` |
| `-TestAccess` | -- | `--test-access` |
| `-Remask` | FILE | `--remask` |
| `-Debug` | -- | `--debug` |

### Non-Interactive Mode

Automatically enabled when `--stack` and `--token` (or `--user`/`--password`) are provided on the command line. Skips all interactive prompts. When `--apps` is specified, `SCOPE_TO_APPS` is automatically set to true.

### Environment Variable Overrides (Bash)

```bash
BATCH_SIZE=50 RATE_LIMIT_DELAY=0.5 API_TIMEOUT=300 ./dma-splunk-cloud-export.sh ...
```

---

## 21. Security Considerations

### Credentials

- Tokens and passwords are never written to log files
- Debug mode redacts sensitive values in output
- Session keys from username/password auth are held in memory only
- Password encoding uses Python `urllib.parse.quote` via stdin to prevent shell expansion

### TLS

- TLS verification is disabled (`curl -k`) to support Splunk Cloud instances with self-signed or custom CA certificates
- TLS version is determined by curl defaults (typically TLS 1.2+)

### Data Protection

- Anonymization enabled by default produces two archives: original (for internal use) and masked (safe to share)
- Anonymization mapping is one-way (hash-based) and cannot be reversed from the export data alone
- Mapping files (`/tmp/dma_email_map_$$`, `/tmp/dma_host_map_$$`) are deleted after processing
- The generated Python anonymizer script (`.anonymizer.py`) is included in the export directory and archived

### Network

- All communication is HTTPS on port 8089
- Proxy support available for environments behind corporate firewalls
- When proxy is configured, direct DNS and TCP tests are skipped (proxy handles routing)
- The script never initiates outbound connections to any host other than the specified Splunk Cloud stack (and optionally the configured proxy)

---

*Generated for DMA Splunk Cloud Export v4.6.0*
