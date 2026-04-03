# Manual Usage Analytics Queries for Distributed Splunk Environments

**Version**: 4.6.0
**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise Export README](README-SPLUNK-ENTERPRISE.md) | [Export Schema](EXPORT-SCHEMA.md)

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## When to Use This Guide

The DMA export script runs 6 global analytics queries against `index=_audit` and `index=_internal` to collect dashboard usage, user activity, search patterns, index volumes, and alert firing statistics. These queries work correctly in most environments.

**However, in large distributed Splunk deployments — particularly Search Head Clusters (SHCs) — the script may return incomplete results because:**

- **`_audit` is a local index.** Each Splunk component (search head, indexer) maintains its own `_audit`. By default, search heads do NOT forward their `_audit` data to the indexer tier. When the export script runs on one SHC member, it only sees that member's local search audit data — not the other 25 members' activity.

- **`license_usage.log` only exists on the license master.** If the license master doesn't forward its `_internal` data to the indexer tier, searching from any other node returns zero results for index volume data.

### Symptoms of This Problem

| Symptom | Expected | Indicates |
|---------|----------|-----------|
| Dashboard views count is very low | Thousands of views across all dashboards | Only seeing 1 SH member's local `_audit` |
| User activity count is very low | Hundreds of active users | Same — only one member's activity |
| Index volume returns 0 results | Every index with volume data | License master not forwarding `_internal` |
| Alert firing stats are low or zero | Thousands of scheduled search runs | `_internal` scheduler logs not reachable |

### Quick Diagnostic

Run this query first from the node where you plan to execute the export script:

```spl
index=_audit sourcetype=audittrail earliest=-1d
| stats count by splunk_server
| sort -count
```

**If results only show 1-3 servers** instead of all SHC members + indexers, you are affected by this issue. Every SHC member and indexer should appear in the results if you have full visibility.

---

## Root Cause: `_audit` Forwarding in Distributed Splunk

In a distributed Splunk deployment with a Search Head Cluster:

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

**The search audit trail (`action=search info=granted`) is generated on the search head that dispatched the search**, not on the indexers. So if SHC members don't forward `_audit` to the indexer tier, searching from any single member only captures ~1/N of the total search activity (where N = number of SHC members).

---

## Solution Options

### Option A: Run Queries from the Monitoring Console (Recommended)

If your environment has a Splunk Monitoring Console (MC) deployed, it already has all instances (SHC members, indexers, license master) as distributed search peers. Running the queries from the MC provides complete visibility.

1. Log into the Monitoring Console's Splunk Web
2. Open **Search & Reporting**
3. Run each query from the [Manual Query Set](#manual-query-set) below
4. Export results as JSON
5. Place files in the export archive (see [Placing Files in the Export](#placing-files-in-the-export))

### Option B: Configure SHC Forwarding (Long-Term Fix)

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

### Option C: Run Queries Manually and Inject Results (Immediate)

If you cannot configure forwarding and don't have an MC, run the queries manually from a node with access to all data, then inject the JSON results into the DMA export archive.

This is the approach documented in detail below.

---

## Manual Query Set

Run each query below in Splunk Search & Reporting. Set the time picker to **All Time** (the `earliest=` constraint is embedded in each query). Adjust `earliest=-90d` to match your desired analytics period (default is 90 days; use `-30d` for 30 days, `-365d` for one year).

### Prerequisites

Verify your search node has visibility across the deployment:

```spl
| rest /services/search/distributed/peers
| table title, status, server_roles
| sort title
```

You should see all SHC members, indexers, and the license master listed with `status=Up`. If any are missing, the queries below will be incomplete.

---

### Query 1: Dashboard Views

**Purpose**: Identifies which dashboards are actively used, by how many users, and how often. This is the most critical query for migration prioritization — it determines which dashboards to migrate first.

**Save as**: `dashboard_views_global.json`

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

**Save as**: `user_activity_global.json`

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

**Save as**: `search_patterns_global.json`

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

**Save as**: `index_volume_summary.json`

**Important**: This query requires access to the **license master's** `_internal` index. If it returns 0 results, the license master is not forwarding data to the indexer tier. In that case, run this query directly on the license master.

```spl
index=_internal source=*license_usage.log type=Usage earliest=-90d
| eval index_name=idx
| stats sum(b) as total_bytes, dc(st) as sourcetype_count, dc(h) as host_count, min(_time) as earliest_event, max(_time) as latest_event by index_name
| eval total_gb=round(total_bytes/1024/1024/1024, 2), daily_avg_gb=round(total_gb/90, 2)
| sort -total_gb
| fields index_name, total_bytes, total_gb, daily_avg_gb, sourcetype_count, host_count, earliest_event, latest_event
```

**Expected results**: One row per index. `total_gb` should match your license usage dashboard. If results are empty, you need to run this query from the license master directly.

**Alternative — run on license master**:
```spl
| rest splunk_server=<license_master_hostname> /services/data/indexes
| table title, currentDBSizeMB, totalEventCount, maxTotalDataSizeMB
| eval total_gb=round(currentDBSizeMB/1024, 2)
| sort -total_gb
```

---

### Query 5: Alert Firing Stats

**Purpose**: Shows which saved searches and alerts are actively firing, how often, and their success/failure rates. Essential for understanding which alerts to prioritize in migration.

**Save as**: `alert_firing_global.json`

**Important**: This query searches `index=_internal sourcetype=scheduler`, which lives on the search heads. Same `_audit`-like visibility issue applies — scheduler logs are local to each SH.

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

**Expected results**: One row per saved search per app. Active environments with many scheduled searches should show thousands of rows.

---

### Query 6: Index Event Counts (Daily)

**Purpose**: Provides daily event count trends per index for capacity planning. This is a supplementary query not in the core 6 but valuable for the DMA Explorer.

**Save as**: `index_event_counts_daily.json` (optional)

```spl
index=_internal source=*license_usage.log type=Usage earliest=-90d
| eval index_name=idx
| bin _time span=1d
| stats sum(b) as daily_bytes by index_name, _time
| eval daily_gb=round(daily_bytes/1024/1024/1024, 2)
| sort index_name, _time
```

---

## Placing Files in the Export

After exporting each query's results as JSON from Splunk:

### Step 1: Extract the existing export archive

```bash
# Create working directory
mkdir -p /tmp/dma_manual_inject
cd /tmp/dma_manual_inject

# Extract the existing export archive
tar xzf /path/to/dma_export_<hostname>_<timestamp>.tar.gz
```

### Step 2: Copy JSON files into the analytics directory

```bash
# Navigate to the usage analytics directory
EXPORT_DIR=$(ls -d dma_export_*)
mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics"

# Copy your exported JSON files
cp dashboard_views_global.json   "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp user_activity_global.json     "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp search_patterns_global.json   "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp index_volume_summary.json     "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp alert_firing_global.json      "$EXPORT_DIR/dma_analytics/usage_analytics/"
cp index_event_counts_daily.json "$EXPORT_DIR/dma_analytics/usage_analytics/"
```

### Step 3: Re-create the archive

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

## Splunk REST API Alternatives

If running SPL queries is not feasible, some data can be gathered via REST API calls. These don't require `_audit` or `_internal` access but provide less detail:

### Index sizes (no license_usage.log needed)

```spl
| rest /services/data/indexes splunk_server=*
| search title!=_*
| stats sum(currentDBSizeMB) as total_mb, sum(totalEventCount) as total_events by title
| eval total_gb=round(total_mb/1024, 2)
| sort -total_gb
```

### All saved searches with schedule info

```spl
| rest /servicesNS/-/-/saved/searches splunk_server=local
| search is_scheduled=1 OR alert.track=1
| table title, eai:acl.app, cron_schedule, alert.severity, alert.track, disabled, next_scheduled_time
| rename eai:acl.app as app, title as savedsearch_name
```

### All dashboards with metadata

```spl
| rest /servicesNS/-/-/data/ui/views splunk_server=local
| search isDashboard=1
| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, updated
| rename eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing
```

These REST-based queries don't provide **usage** data (who viewed what, how often) but they do provide complete **inventory** data (what exists) which is still valuable for migration planning.

---

## Troubleshooting

### "0 results" on all _audit queries

**Cause**: The search node has no distributed search peers, or peers are down.

**Check**:
```spl
| rest /services/search/distributed/peers
| table title, status, server_roles
```

If empty or all status=Down, the node cannot reach any other Splunk instances.

### Results only from 1-2 servers

**Cause**: SHC members not forwarding `_audit` to indexers. You're only seeing the local SH's data.

**Check**:
```spl
index=_audit sourcetype=audittrail earliest=-1d
| stats count by splunk_server
| sort -count
```

If only 1-2 `splunk_server` values appear, run the queries from the Monitoring Console instead.

### Dashboard views count seems too low

**Cause**: Several possible reasons beyond forwarding:
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

### license_usage.log returns 0 from SHC but works from license master

**Cause**: License master is not forwarding `_internal` to the indexer tier.

**Workaround**: SSH to the license master and run Query 4 directly, or use:
```spl
| rest splunk_server=<license_master_hostname> /services/licenser/usage/license_usage
| table title, quota, slaves_usage_bytes
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 2026 | Initial document — manual query alternative for distributed SHC environments |
