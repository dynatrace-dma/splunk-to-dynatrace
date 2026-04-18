# Manual Usage Analytics Queries

**Version**: 4.6.2
**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise Export README](README-SPLUNK-ENTERPRISE.md) | [Cloud Export README](README-SPLUNK-CLOUD.md) | [Export Schema](EXPORT-SCHEMA.md)

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## When to Use This Guide

The DMA export scripts run 6 global analytics queries against `index=_audit` and `index=_internal` to collect dashboard usage, user activity, search patterns, index volumes, and alert firing statistics. These queries work correctly in most environments.

**However, there are common scenarios in both Splunk Cloud and Splunk Enterprise where the script returns incomplete or empty analytics results.** This document provides the standalone SPL queries that can be run manually in Splunk Search and injected into the DMA export archive.

### Applies To

| Platform | Script(s) | Common Reasons for Incomplete Results |
|----------|-----------|--------------------------------------|
| **Splunk Cloud** | `dma-splunk-cloud-export.sh`, `dma-splunk-cloud-export.ps1` | Token missing `index_audit` or `index_internal` capabilities; restricted `_audit` access in Victoria Experience stacks; Cloud-managed infrastructure hides `_internal` from tenants |
| **Splunk Enterprise** | `dma-splunk-export.sh` | SHC members not forwarding `_audit` to indexers; license master not forwarding `_internal`; service account lacking `admin_all_objects` capability |

### CRITICAL: File Naming Requirements

> **The DMA Server will NOT recognize your files if they are named incorrectly.**
>
> When you export query results from Splunk, Splunk names the file something like `search_results_1713456789.json` or `export.json`. **IMPORTANT PLEASE rename each file to the exact filename listed below BEFORE sending to your Dynatrace associate or injecting into the archive.**
>
> | Query | Required Filename (exact, case-sensitive) |
> |-------|------------------------------------------|
> | Query 1 — Dashboard Views | **`dashboard_views_global.json`** |
> | Query 2 — User Activity | **`user_activity_global.json`** |
> | Query 3 — Search Patterns | **`search_patterns_global.json`** |
> | Query 4 — Index Volume | **`index_volume_summary.json`** |
> | Query 5 — Alert Firing | **`alert_firing_global.json`** |
> | Query 6 — Daily Event Counts | **`index_event_counts_daily.json`** |
>
> **Wrong**: `export.json`, `search_results.json`, `Query1.json`, `dashboard_views.json`, `Dashboard_Views_Global.json`
>
> **Right**: `dashboard_views_global.json` (lowercase, exact match, no spaces)
>
> If any file is named incorrectly, the DMA Server will silently ignore it and the corresponding usage data will not appear in the Explorer.

---

### Symptoms of This Problem

| Symptom | Expected | Possible Cause |
|---------|----------|----------------|
| Dashboard views count is very low | Thousands of views across all dashboards | **Enterprise**: Only seeing 1 SHC member's local `_audit`. **Cloud**: Token lacks `index_audit` capability |
| User activity count is very low | Hundreds of active users | Same as above |
| Index volume returns 0 results | Every index with volume data | **Enterprise**: License master not forwarding `_internal`. **Cloud**: `_internal` not accessible to tenant users |
| Alert firing stats are low or zero | Thousands of scheduled search runs | **Enterprise**: `_internal` scheduler logs not reachable. **Cloud**: Same `_internal` restriction |

---

## Splunk Cloud

### What You Need: `_audit` Access

On Splunk Cloud, **dashboard views and alert firing history require `_audit` index access**. There is no reliable alternative — the REST API endpoints do not provide historical usage data, and other internal indexes (`_internal`, `_telemetry`, `_introspection`) are either restricted or do not contain the data needed.

**Before running any queries, confirm your user/token has `_audit` access:**

```spl
index=_audit earliest=-1h | stats count
```

If this returns 0, you need to either:
- Log in as `sc_admin` (which has `_audit` access by default)
- Ask your Splunk Cloud administrator to grant the `index_audit` capability to your role/token
- File a support case with Splunk to enable `_audit` access for your admin role

> **If `_audit` access cannot be obtained**: Dashboard view counts and alert firing history will be unavailable. The remaining queries (search patterns, index volume) use REST endpoints that work without special permissions. See [Queries That Work Without `_audit`](#queries-that-work-without-_audit-cloud) below.

### How to Run

1. Log into your Splunk Cloud stack's web interface as `sc_admin` or a user with the `admin` role
2. Navigate to **Search & Reporting**
3. Run each Cloud query below
4. **Export results as JSON** (Export > JSON > Results)
5. **Rename each file to the exact filename shown** (see [File Naming Requirements](#critical-file-naming-requirements))
6. Send to your Dynatrace associate or inject into the archive (see [Delivering the Files](#delivering-the-files))

---

### Cloud Query 1: Dashboard Views (requires `_audit`)

This is the same query as the Enterprise version. It uses the `_audit` index with the `provenance` field to track dashboard-triggered searches. **There is no REST-based alternative that provides view counts.**

⚠️ **Save as (exact filename required)**: `dashboard_views_global.json`

```spl
index=_audit sourcetype=audittrail action=search info=granted
  (provenance="UI:Dashboard:*" OR provenance="UI:dashboard:*")
  user!="splunk-system-user" earliest=-90d
| rex field=provenance "UI:[Dd]ashboard:(?<dashboard_name>[\w\-\.]+)"
| where isnotnull(dashboard_name)
| eval view_session=user."_".floor(_time/30)
| stats dc(view_session) as view_count, dc(user) as unique_users, values(user) as viewers, latest(_time) as last_viewed by app, dashboard_name
| sort -view_count
```

**If `_audit` is unavailable**, this data cannot be collected. Use this REST fallback to at least capture dashboard inventory and ownership (no view counts):

```spl
| rest /servicesNS/-/-/data/ui/views
| search isDashboard=1 OR isDashboard=true
| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, updated
| rename eai:acl.app as app, title as dashboard_name, eai:acl.owner as owner, eai:acl.sharing as sharing
| eval view_count=0, unique_users=0, viewers=""
| sort app, dashboard_name
```

---

### Cloud Query 2: User Activity (requires `_audit`)

⚠️ **Save as (exact filename required)**: `user_activity_global.json`

```spl
index=_audit sourcetype=audittrail action=search info=granted
  user!="splunk-system-user" earliest=-90d
| stats count as search_count, dc(app) as app_count, values(app) as apps by user
| sort -search_count
```

**If `_audit` is unavailable**, this data cannot be collected. Skip this file.

---

### Queries That Work Without `_audit` (Cloud)

The following queries use REST endpoints and work on all Splunk Cloud stacks without special index permissions.

### Cloud Query 3: Search Patterns

⚠️ **Save as (exact filename required)**: `search_patterns_global.json`

```spl
| rest /servicesNS/-/-/saved/searches
| eval search_type=case(
    alert.track=="1" OR alert.track=="true" OR (isnotnull(actions) AND actions!="" AND alert.track!="0"), "alert",
    is_scheduled=="1" OR is_scheduled=="true", "report",
    1==1, "saved_search"
  )
| stats count by eai:acl.app, search_type
| rename eai:acl.app as app
| sort app, search_type
```

> **Note**: This query returns saved/scheduled searches only — true ad-hoc searches (run once from the search bar) are not captured by the REST endpoint.

---

### Cloud Query 4: Index Volume

⚠️ **Save as (exact filename required)**: `index_volume_summary.json`

```spl
| rest /services/data/indexes
| search NOT title=_* disabled=0 totalEventCount>0
| stats sum(currentDBSizeMB) as currentDBSizeMB, sum(totalEventCount) as totalEventCount, min(minTime) as minTime, max(maxTime) as maxTime, values(frozenTimePeriodInSecs) as frozenTimePeriodInSecs by title
| eval total_gb=round(currentDBSizeMB/1024, 2)
| sort -total_gb
| rename title as index_name
```

> **Note**: The `stats` aggregation is required because Splunk Cloud returns one row per index per indexer. Without it, index sizes appear duplicated.

---

### Cloud Query 5: Alert Firing Stats (requires `_audit`)

For actual alert firing history, `_audit` is required. The REST endpoint's `triggered_alert_count` field is **not reliable** — it only counts non-expired fired alert instances (default 24-hour TTL) and resets when alerts are modified or during SHC captain elections.

⚠️ **Save as (exact filename required)**: `alert_firing_global.json`

**With `_audit` access (recommended):**

```spl
index=_audit sourcetype=audittrail action=alert_fired earliest=-90d
| stats count as total_runs, latest(_time) as last_run by app, ss_name
| rename ss_name as savedsearch_name
| eval successful=total_runs, skipped=0, failed=0
| sort -total_runs
```

> **Note**: `_audit` records alert fires (condition met), not total scheduled runs. The `successful`/`skipped`/`failed` breakdown requires `_internal` (sourcetype=scheduler) which is unavailable on Cloud. The values above represent fires only.

**Without `_audit` access (limited fallback):**

```spl
| rest /servicesNS/-/-/saved/searches
| search is_scheduled=1 OR alert.track=1 OR alert.track=true OR alert.track=auto
| table eai:acl.app, title, triggered_alert_count, cron_schedule, disabled, alert.severity, alert.track, actions, next_scheduled_time, updated
| eval total_runs=triggered_alert_count
| eval successful=triggered_alert_count, skipped=0, failed=0
| eval last_run=updated
| rename eai:acl.app as app, title as savedsearch_name
| sort -total_runs
```

> **WARNING**: `triggered_alert_count` from REST is the count of **currently non-expired alert instances** (default 24-hour TTL), NOT total historical runs. An alert that has fired thousands of times may show single-digit counts. Treat these numbers as a **lower bound only**. The `skipped` and `failed` values are set to 0 because the REST endpoint does not provide this data — this does not mean no searches were skipped or failed.

---

### Cloud Query 6: Daily Event Counts (Optional)

⚠️ **Save as (exact filename required)**: `index_event_counts_daily.json`

```spl
| rest /services/data/indexes
| search NOT title=_* disabled=0 totalEventCount>0
| stats sum(currentDBSizeMB) as currentDBSizeMB, sum(totalEventCount) as totalEventCount, min(minTime) as minTime, max(maxTime) as maxTime by title
| eval days_span=round((now() - strptime(minTime, "%Y-%m-%dT%H:%M:%S%z")) / 86400, 0)
| eval events_per_day=if(days_span>0, round(totalEventCount/days_span, 0), totalEventCount)
| sort -totalEventCount
| rename title as index_name
```

> **Note**: The `events_per_day` calculation uses the actual time span of data in the index (from `minTime` to now), not an arbitrary divisor.

---

### Important: Inherent Splunk Cloud Usage Data Limitations

### Important: Inherent Splunk Cloud Usage Data Limitations

Even with correct permissions and full `_audit` access, usage analytics data on Splunk Cloud will be **inherently less complete** than on Splunk Enterprise. These are platform limitations, not configuration issues:

#### Dashboard View Counts

| Limitation | Impact | Explanation |
|-----------|--------|-------------|
| **Low view-count coverage** | Typically only 5-15% of dashboards show any view data | Most dashboards in large environments are created but rarely or never viewed. A Splunk Cloud environment with 2,000 dashboards may show only 100-300 with any view count. This is normal and expected. |
| **View tracking depends on `splunk_web_access`** | Views from API clients, embedded iframes, or Splunk Mobile are not counted | Only browser-based access through the Splunk Web UI generates view tracking events. Programmatic access to dashboard definitions via REST API does not register as a "view." |
| **SHC captain elections reset counters** | Short-lived view counts after cluster events | Splunk Cloud search head clusters periodically elect new captains. Some in-memory view counters reset during this process, resulting in artificially low counts. |

#### Alert and Scheduled Search Firing Stats

| Limitation | Impact | Explanation |
|-----------|--------|-------------|
| **Active alerts with zero run counts** | Alerts marked `is_scheduled=1` in the config may show no firing history | The `triggered_alert_count` counter on the `/services/saved/searches` REST endpoint resets when an alert is modified, when the search head restarts, or during SHC captain transfers. An alert that has been running for years may show 0 runs if it was recently edited. |
| **`_internal` scheduler logs unavailable** | No `sourcetype=scheduler` data for run success/failure/skip breakdown | Splunk Cloud does not expose `_internal` to tenant users. The scheduler action logs (`action_results`) that show whether each run succeeded, skipped, or failed are not queryable. The REST endpoint provides only `triggered_alert_count`, not the detailed breakdown. |
| **SHC member distribution** | Firing data may be partial | In a Splunk Cloud SHC, scheduled searches are distributed across multiple members. REST queries hit the captain, which aggregates counts, but transient member issues or recent rebalances can cause undercounting. |
| **Disabled-but-configured alerts** | Alerts show as "active" in config but never fire | An alert can have `disabled=0` in its config but be effectively disabled by Splunk Cloud administrators at the infrastructure level (e.g., suppressed by the monitoring console, skipped due to resource limits). The export captures the configuration state, not the runtime state. |

#### What This Means for Migration Planning

- **Dashboard view counts should be used as directional guidance, not absolute numbers.** A dashboard with 0 views may still be actively used via API, mobile, or embedded integrations.
- **Alert firing stats represent a lower bound.** An active alert with 0 recorded runs should not be assumed to be unused — the counter may have reset.
- **For critical migration decisions (keep vs. exclude), verify usage directly with the customer's Splunk administrators** rather than relying solely on the analytics data.
- **The LOE estimate is not affected by usage data.** Usage data informs prioritization (which dashboards to migrate first) but does not change the total estimated effort.

---

## Splunk Enterprise

### Why Analytics May Be Incomplete

In distributed Splunk Enterprise deployments — particularly those with Search Head Clusters (SHCs) — the script may return incomplete results due to how `_audit` and `_internal` indexes work.

#### `_audit` Is a Local Index

Each Splunk component (search head, indexer) maintains its own `_audit`. By default, search heads do NOT forward their `_audit` data to the indexer tier.

```
┌──────────────────────────────────────────────────┐
│              Search Head Cluster                  │
│                                                   │
│  SH-1 ──┐                                        │
│  SH-2 ──┤  Each SH has its OWN local _audit      │
│  SH-3 ──┤  containing only searches dispatched    │
│  ...   ──┤  from THAT specific search head.       │
│  SH-26 ─┘                                        │
│                                                   │
│  By default, SHs do NOT forward _audit            │
│  to the indexer tier.                             │
└──────────────────────────────────────────────────┘
            │
            │  Distributed search reaches indexers
            │  but NOT other SH members' local _audit
            ▼
┌──────────────────────────────────────────────────┐
│              Indexer Cluster                       │
│                                                   │
│  IDX-1 ──┐  Indexers have their own _audit        │
│  IDX-2 ──┤  (indexer-side events only, NOT        │
│  IDX-3 ──┘   search dispatch events)              │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│           License Master                          │
│                                                   │
│  license_usage.log lives HERE and only here.      │
│  If not forwarding to indexers, searching          │
│  from any other node returns 0 results.           │
└──────────────────────────────────────────────────┘
```

The search audit trail (`action=search info=granted`) is generated **on the search head that dispatched the search**, not on the indexers. So if SHC members don't forward `_audit` to the indexer tier, searching from any single member only captures ~1/N of the total search activity (where N = number of SHC members).

#### `license_usage.log` Only Exists on the License Master

If the license master doesn't forward its `_internal` data to the indexer tier, searching `index=_internal source=*license_usage.log` from any other node returns zero results.

### Quick Diagnostic (Enterprise Only)

Run this from the node where you plan to execute the export script:

```spl
index=_audit sourcetype=audittrail earliest=-1d
| stats count by splunk_server
| sort -count
```

**If results only show 1-3 servers** instead of all SHC members + indexers, you are affected by this issue. Every SHC member and indexer should appear in the results if you have full visibility.

### Enterprise Solution Options

#### Option A: Run Queries from the Monitoring Console (Recommended)

If your environment has a Splunk Monitoring Console (MC) deployed, it already has all instances (SHC members, indexers, license master) as distributed search peers. Running the queries from the MC provides complete visibility.

1. Log into the Monitoring Console's Splunk Web
2. Open **Search & Reporting**
3. Run each query from the [Manual Query Set](#manual-query-set) below
4. Export results as JSON
5. Place files in the export archive (see [Placing Files in the Export](#placing-files-in-the-export))

#### Option B: Configure SHC Forwarding (Long-Term Fix)

Deploy `outputs.conf` to all SHC members via the **SHC Deployer** and to the license master:

```ini
# $SPLUNK_HOME/etc/apps/dma_forwarding/local/outputs.conf
# Deploy via SHC deployer for search heads
# Deploy manually or via deployment server for license master

[tcpout]
defaultGroup = indexer_cluster
forwardedindex.filter.disable = true

[tcpout:indexer_cluster]
server = <indexer1>:9997, <indexer2>:9997, <indexer3>:9997
```

The critical setting is `forwardedindex.filter.disable = true` — by default, Splunk's forwarding **filters out internal indexes** (those starting with `_`). This setting includes `_audit` and `_internal` in forwarding.

After deploying, **wait 24-48 hours** for `_audit` data to accumulate on the indexer tier before re-running the export script. Historical local `_audit` data will NOT be retroactively forwarded — only new events going forward.

#### Option C: Run Queries Manually and Inject Results (Immediate)

If you cannot configure forwarding and don't have an MC, run the queries manually from a node with access to all data, then inject the JSON results into the DMA export archive. This is the approach documented in the [Manual Query Set](#manual-query-set) below.

---

## Manual Query Set

These queries work on **both Splunk Cloud and Splunk Enterprise**. The SPL syntax is identical — the only difference is where you run them and what data is accessible.

Run each query in Splunk Search & Reporting. Set the time picker to **All Time** (the `earliest=` constraint is embedded in each query). Adjust `earliest=-90d` to match your desired analytics period (default is 90 days; use `-30d` for 30 days, `-365d` for one year).

### Prerequisites

**Enterprise only** — verify your search node has visibility across the deployment:

```spl
| rest /services/search/distributed/peers
| table title, status, server_roles
| sort title
```

You should see all SHC members, indexers, and the license master listed with `status=Up`. If any are missing, the queries below will be incomplete.

**Cloud** — verify your user/token can access `_audit`:

```spl
index=_audit earliest=-1h | stats count
```

If this returns 0, your user/token does not have `_audit` access. Log in as `sc_admin` or contact your Splunk Cloud administrator.

---

### Query 1: Dashboard Views

**Purpose**: Identifies which dashboards are actively used, by how many users, and how often. This is the most critical query for migration prioritization — it determines which dashboards to migrate first.

**Requires**: `_audit` access
⚠️ **Save as (exact filename required)**: `dashboard_views_global.json`

```spl
index=_audit sourcetype=audittrail action=search info=granted
  (provenance="UI:Dashboard:*" OR provenance="UI:dashboard:*")
  user!="splunk-system-user" earliest=-90d
| rex field=provenance "UI:[Dd]ashboard:(?<dashboard_name>[\w\-\.]+)"
| where isnotnull(dashboard_name)
| eval view_session=user."_".floor(_time/30)
| stats dc(view_session) as view_count, dc(user) as unique_users, values(user) as viewers, latest(_time) as last_viewed by app, dashboard_name
| sort -view_count
```

**How it works**: Identifies dashboard-triggered searches via the `provenance` field, deduplicates page loads using a 30-second session window (multiple panels on one dashboard = one view), and aggregates by app and dashboard name.

**Expected results**: Hundreds to thousands of rows in an active environment. If you see fewer than 100 rows for an environment with 1000+ dashboards, you likely don't have full `_audit` visibility.

---

### Query 2: User Activity

**Purpose**: Shows which users are actively searching in each app. Used by the DMA Server to identify key stakeholders and high-activity users for each app being migrated.

**Requires**: `_audit` access
⚠️ **Save as (exact filename required)**: `user_activity_global.json`

```spl
index=_audit sourcetype=audittrail action=search info=granted
  user!="splunk-system-user" user!="nobody" earliest=-90d
| stats count as searches, dc(search_id) as unique_searches, latest(_time) as last_active by app, user
| sort -searches
```

**Expected results**: One row per user per app, with search counts. Total searches across all users should be in the thousands to hundreds of thousands for active environments.

---

### Query 3: Search Type Breakdown

**Purpose**: Categorizes all search activity by type (dashboard, scheduled, interactive, acceleration, summarization). Helps the migration team understand what kind of workload each app drives.

**Requires**: `_audit` access
⚠️ **Save as (exact filename required)**: `search_patterns_global.json`

```spl
index=_audit sourcetype=audittrail action=search info=granted
  user!="splunk-system-user" earliest=-90d
| eval search_type=case(
    match(provenance, "^UI:[Dd]ashboard:"), "dashboard",
    match(search_id, "^(rt_)?scheduler__"), "scheduled",
    match(savedsearch_name, "^_ACCELERATE_"), "acceleration",
    match(search_id, "^SummaryDirector_"), "summarization",
    isnotnull(provenance) AND match(provenance, "^UI:"), "interactive",
    1=1, "other")
| stats count as total_searches, dc(user) as unique_users, dc(search_id) as unique_searches by app, search_type
| sort -total_searches
```

**Expected results**: Multiple rows per app (one per search type). The `scheduled` and `dashboard` types should dominate in most production environments.

---

### Query 4: Index Volume (Ingestion)

**Purpose**: Shows daily ingestion volume per index from `license_usage.log`. Critical for Dynatrace Grail storage planning and cost estimation.

**Requires**: `_internal` access (often unavailable on Splunk Cloud — see alternative below)
⚠️ **Save as (exact filename required)**: `index_volume_summary.json`

```spl
index=_internal source=*license_usage.log type=Usage earliest=-90d
| eval index_name=idx
| stats sum(b) as total_bytes, dc(st) as sourcetype_count, dc(h) as host_count, min(_time) as earliest_event, max(_time) as latest_event by index_name
| eval total_gb=round(total_bytes/1024/1024/1024, 2), daily_avg_gb=round(total_gb/90, 2)
| sort -total_gb
| fields index_name, total_bytes, total_gb, daily_avg_gb, sourcetype_count, host_count, earliest_event, latest_event
```

**Expected results**: One row per index. `total_gb` should match your license usage dashboard.

**If this returns 0 results:**

- **Splunk Cloud**: `_internal` is typically not accessible to tenants. Use the REST alternative:
  ```spl
  | rest /services/data/indexes
  | search title!=_* disabled=0 totalEventCount>0
  | table title, currentDBSizeMB, totalEventCount
  | eval total_gb=round(currentDBSizeMB/1024, 2)
  | sort -total_gb
  | rename title as index_name
  ```

- **Splunk Enterprise**: The license master is not forwarding `_internal` to the indexer tier. Either run this query directly on the license master, or use:
  ```spl
  | rest splunk_server=<license_master_hostname> /services/data/indexes
  | table title, currentDBSizeMB, totalEventCount, maxTotalDataSizeMB
  | eval total_gb=round(currentDBSizeMB/1024, 2)
  | sort -total_gb
  | rename title as index_name
  ```

---

### Query 5: Alert Firing Stats

**Purpose**: Shows which saved searches and alerts are actively firing, how often, and their success/failure rates. Essential for understanding which alerts to prioritize in migration.

**Requires**: `_internal` access (often unavailable on Splunk Cloud — see alternative below)
⚠️ **Save as (exact filename required)**: `alert_firing_global.json`

```spl
index=_internal sourcetype=scheduler earliest=-90d
| fields _time, app, savedsearch_name, status
| stats count as total_runs,
    sum(eval(if(status="success",1,0))) as successful,
    sum(eval(if(status="skipped",1,0))) as skipped,
    sum(eval(if(status!="success" AND status!="skipped",1,0))) as failed,
    latest(_time) as last_run by app, savedsearch_name
| sort -total_runs
```

**Expected results**: One row per saved search per app.

**If this returns 0 results** (common on Splunk Cloud), use the REST alternative to get the alert/saved search inventory (without firing history):

```spl
| rest /servicesNS/-/-/saved/searches
| search is_scheduled=1 OR alert.track=1
| table title, eai:acl.app, cron_schedule, alert.severity, alert.track, disabled, next_scheduled_time
| rename eai:acl.app as app, title as savedsearch_name
```

**Enterprise note**: This query searches `index=_internal sourcetype=scheduler`, which has the same local-index visibility issue as `_audit`. On SHC environments, scheduler logs are local to each search head. Run from the Monitoring Console for complete results.

---

### Query 6: Index Event Counts (Daily)

**Purpose**: Provides daily event count trends per index for capacity planning. Supplementary to Query 4.

**Requires**: `_internal` access (same caveats as Query 4)
⚠️ **Save as (exact filename required)**: `index_event_counts_daily.json` (optional)

```spl
index=_internal source=*license_usage.log type=Usage earliest=-90d
| eval index_name=idx
| bin _time span=1d
| stats sum(b) as daily_bytes by index_name, _time
| eval daily_gb=round(daily_bytes/1024/1024/1024, 2)
| sort index_name, _time
```

If `_internal` is not accessible (Cloud), skip this query. The DMA Server can function without daily trend data.

---

## Delivering the Files

After exporting each query's results as JSON from Splunk, there are two ways to get these files into the DMA migration project.

> **REMINDER: Rename every file before sending.** Splunk exports files with generic names like `export.json`. Each file MUST be renamed to the exact canonical filename listed in the [File Naming Requirements](#critical-file-naming-requirements) table above. The DMA Server matches files by exact filename — incorrect names are silently ignored.

### Option 1: Send to Your Dynatrace Migration Associate (Recommended)

This is the simplest approach. Your Dynatrace associate managing the migration project can import the files directly through the DMA Server UI.

1. Export each query result as JSON (see [JSON Format Requirements](#json-format-requirements) below)
2. Place all the `.json` files into a single `.zip` archive
3. Send the `.zip` to your Dynatrace associate (via email, secure file share, or whatever channel you're using for the migration engagement)

Your Dynatrace associate will:
- Open the DMA Server **Import** dialog for your project
- Drag and drop the individual JSON files — the system automatically identifies each file type, maps it to the correct canonical filename, and places it in the appropriate location within the project
- Issue a **Full Rebuild** to incorporate the new data into the Project Indexes and Data Views

### Option 2: Inject into the Export Archive (Advanced)

If you prefer to handle it yourself, you can place the files directly into the export archive before uploading to the DMA Server.

**Step 1: Extract the existing export archive**

```bash
mkdir -p /tmp/dma_manual_inject
cd /tmp/dma_manual_inject
tar xzf /path/to/dma_export_<hostname>_<timestamp>.tar.gz
```

**Step 2: Copy JSON files into the analytics directory**

```bash
EXPORT_DIR=$(ls -d dma_export_* | head -1)
mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics"

cp dashboard_views_global.json   "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp user_activity_global.json     "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp search_patterns_global.json   "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp index_volume_summary.json     "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp alert_firing_global.json      "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp index_event_counts_daily.json "$EXPORT_DIR/dma_analytics/usage_analytics/"
```

**Step 3: Re-create the archive**

```bash
tar czf "${EXPORT_DIR}.tar.gz" "$EXPORT_DIR"
```

The resulting `.tar.gz` can be uploaded to the DMA Server as a normal export. The DMA Server's `stageUsageAnalytics()` picks up files from `dma_analytics/usage_analytics/` regardless of whether they were generated by the script or manually placed.

---

## JSON Format Requirements

When exporting from Splunk Search, use **Export > JSON > Results**. Splunk exports results in this format:

```json
{
  "preview": false,
  "init_offset": 0,
  "messages": [],
  "fields": [...],
  "results": [
    {
      "app": "search",
      "dashboard_name": "my_dashboard",
      "view_count": "142",
      "unique_users": "8",
      ...
    },
    ...
  ]
}
```

The DMA Server reads from the `results` array. The field names must match exactly what the SPL queries produce (they will if you copy-paste the queries above without modification).

**Important**: Do NOT use "Export > CSV" or "Export > XML" — the DMA Server expects JSON format.

---

## REST API Alternatives (No `_audit` / `_internal` Needed)

When `_audit` and `_internal` are completely inaccessible (common on Splunk Cloud), the following REST-based queries provide **inventory** data. These don't show usage history (who viewed what, how often) but do provide complete information about what exists in the environment.

### Index sizes

```spl
| rest /services/data/indexes
| search title!=_* disabled=0 totalEventCount>0
| stats sum(currentDBSizeMB) as total_mb, sum(totalEventCount) as total_events by title
| eval total_gb=round(total_mb/1024, 2)
| sort -total_gb
| rename title as index_name
```

### All saved searches with schedule info

```spl
| rest /servicesNS/-/-/saved/searches
| search is_scheduled=1 OR alert.track=1
| table title, eai:acl.app, cron_schedule, alert.severity, alert.track, disabled, next_scheduled_time
| rename eai:acl.app as app, title as savedsearch_name
```

### All dashboards with metadata

```spl
| rest /servicesNS/-/-/data/ui/views
| search isDashboard=1
| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, updated
| rename eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing
```

These REST-based queries don't provide **usage** data (who viewed what, how often) but they do provide complete **inventory** data (what exists) which is still valuable for migration planning.

---

## Troubleshooting

### "0 results" on all `_audit` queries

| Platform | Cause | Fix |
|----------|-------|-----|
| **Cloud** | Token/user lacks `index_audit` capability | Log in as `sc_admin` or create a token from a role with `index_audit` |
| **Enterprise** | No distributed search peers, or peers are down | Check: `\| rest /services/search/distributed/peers \| table title, status` |

### Results only from 1-2 servers (Enterprise)

**Cause**: SHC members not forwarding `_audit` to indexers. You're only seeing the local SH's data.

**Check**:
```spl
index=_audit sourcetype=audittrail earliest=-1d
| stats count by splunk_server
| sort -count
```

If only 1-2 `splunk_server` values appear, run the queries from the Monitoring Console instead.

### Dashboard views count seems too low

**Cause**: Several possible reasons beyond forwarding/permissions:
- `provenance` field may not be populated in older Splunk versions (pre-7.2)
- Dashboard Studio dashboards may log provenance differently than Classic XML
- Some dashboards may use `| inputlookup` or `| rest` instead of standard search commands, which don't generate `audittrail` events

**Check provenance coverage**:
```spl
index=_audit sourcetype=audittrail action=search info=granted earliest=-1d
| stats count by provenance
| sort -count
| head 20
```

### `license_usage.log` returns 0 results

| Platform | Cause | Fix |
|----------|-------|-----|
| **Cloud** | `_internal` not exposed to tenants | Use the REST alternative (`\| rest /services/data/indexes`) |
| **Enterprise** | License master not forwarding `_internal` to indexers | Run Query 4 directly on the license master, or configure `outputs.conf` on the LM |

### `sourcetype=scheduler` returns 0 results

| Platform | Cause | Fix |
|----------|-------|-----|
| **Cloud** | `_internal` not exposed to tenants | Use the REST alternative (`\| rest /servicesNS/-/-/saved/searches`) for inventory |
| **Enterprise** | Same SHC local-index issue as `_audit` | Run from Monitoring Console, or configure SH forwarding |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | April 2026 | Added Splunk Cloud section, REST alternatives, platform-specific guidance |
| 1.0 | April 2026 | Initial document — manual query alternative for distributed SHC environments |
