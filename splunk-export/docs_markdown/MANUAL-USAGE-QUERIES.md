# Manual Usage Analytics Queries

**Version**: 4.6.0
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

### Symptoms of This Problem

| Symptom | Expected | Possible Cause |
|---------|----------|----------------|
| Dashboard views count is very low | Thousands of views across all dashboards | **Enterprise**: Only seeing 1 SHC member's local `_audit`. **Cloud**: Token lacks `index_audit` capability |
| User activity count is very low | Hundreds of active users | Same as above |
| Index volume returns 0 results | Every index with volume data | **Enterprise**: License master not forwarding `_internal`. **Cloud**: `_internal` not accessible to tenant users |
| Alert firing stats are low or zero | Thousands of scheduled search runs | **Enterprise**: `_internal` scheduler logs not reachable. **Cloud**: Same `_internal` restriction |

---

## Splunk Cloud

### Why Analytics May Be Incomplete

Splunk Cloud environments are fully managed by Splunk. Unlike Enterprise, you cannot SSH into the infrastructure, modify `outputs.conf`, or access the Monitoring Console. Common issues:

1. **`_audit` access is restricted.** In some Splunk Cloud stacks (particularly Victoria Experience), tenant users may have limited or no access to `_audit`. The `sc_admin` role has access by default, but custom roles or tokens may not.

2. **`_internal` is inaccessible.** Splunk Cloud does not expose `_internal` to tenants in most configurations. This means `license_usage.log` (Query 4) and `sourcetype=scheduler` (Query 5) may return 0 results regardless of permissions.

3. **Token capabilities.** The export script authenticates via Bearer or Splunk token. If the token's role doesn't include `index_audit` capability (for `_audit`) or `index_internal` (for `_internal`), those queries silently return empty results.

### How to Run Queries on Splunk Cloud

**Option A — Splunk Web (Recommended)**

1. Log into your Splunk Cloud stack's web interface as `sc_admin` or a user with the `admin` role
2. Navigate to **Search & Reporting**
3. Run each query from the [Manual Query Set](#manual-query-set) below
4. Export results as **JSON** (Export > JSON > Results)
5. Inject into the export archive (see [Placing Files in the Export](#placing-files-in-the-export))

**Option B — Via the Export Script with Correct Token**

Ensure your API token has these capabilities:
- `search` — run searches
- `admin_all_objects` — see all apps and knowledge objects
- `list_settings` — access system configuration
- `index_audit` — search `_audit` index
- `index_internal` — search `_internal` index (if available on your stack)

Re-run the export with `--test-access` first to verify:
```bash
./dma-splunk-cloud-export.sh --stack <your-stack>.splunkcloud.com --token "YOUR_TOKEN" --test-access
```

### Cloud-Specific Notes for Each Query

- **Queries 1-3** (`_audit`): These work on Splunk Cloud if the user/token has `index_audit` capability. Use `sc_admin` role for best results.
- **Query 4** (`_internal` license_usage.log): **Often unavailable on Splunk Cloud.** Use the REST API alternative below instead:
  ```spl
  | rest /services/data/indexes
  | search title!=_* disabled=0 totalEventCount>0
  | table title, currentDBSizeMB, totalEventCount
  | eval total_gb=round(currentDBSizeMB/1024, 2)
  | sort -total_gb
  | rename title as index_name
  ```
  This provides current index sizes (not historical ingestion rates) but is sufficient for migration planning.
- **Query 5** (`_internal` scheduler): **Often unavailable on Splunk Cloud.** Use this REST alternative:
  ```spl
  | rest /servicesNS/-/-/saved/searches
  | search is_scheduled=1 OR alert.track=1
  | table title, eai:acl.app, cron_schedule, alert.severity, alert.track, disabled, next_scheduled_time, dispatch.earliest_time, dispatch.latest_time
  | rename eai:acl.app as app, title as savedsearch_name
  ```
  This gives you the alert/saved search inventory (what exists and its schedule) but not firing history (how often it ran and whether it succeeded).
- **Query 6** (daily event counts): Same as Query 4 — `_internal` may be unavailable. Skip this on Cloud if Query 4 isn't accessible.

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

**Requires**: `_audit` access
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

**Requires**: `_audit` access
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

**Requires**: `_internal` access (often unavailable on Splunk Cloud — see alternative below)
**Save as**: `index_volume_summary.json`

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
**Save as**: `alert_firing_global.json`

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
**Save as**: `index_event_counts_daily.json` (optional)

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

## Placing Files in the Export

After exporting each query's results as JSON from Splunk, inject them into the DMA export archive.

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
EXPORT_DIR=$(ls -d dma_export_* | head -1)
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
