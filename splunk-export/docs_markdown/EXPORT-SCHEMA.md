# DMA Splunk Export Schema v4.0

## Purpose

This document defines the **guaranteed output schema** for all DMA Splunk exports. Regardless of Splunk environment size, version, or deployment type, exports MUST conform to this schema so DMA can reliably parse them.

> **Applies to all export scripts (v4.6.0):**
> - `dma-splunk-export.sh` (Enterprise, Bash)
> - `dma-splunk-cloud-export.sh` (Cloud, Bash)
> - `dma-splunk-cloud-export.ps1` (Cloud, PowerShell)

---

## Archive Structure

Every export produces a `.tar.gz` archive with this **exact** structure. When anonymization is enabled, a second `_masked.tar.gz` archive is also created.

### Enterprise Export

```
dma_export_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
|
+-- manifest.json                          # REQUIRED - Export metadata & statistics
+-- _anonymization_report.json             # OPTIONAL - Only in _masked archive
+-- dma-env-summary.md                     # REQUIRED - Human-readable summary
+-- export.log                             # REQUIRED - Export process log
|
+-- dma_analytics/                         # REQUIRED - All DMA-generated analytics
|   +-- system_info/                       # REQUIRED - System information
|   |   +-- environment.json               # REQUIRED - Standardized env info
|   |   +-- splunk.version                 # OPTIONAL - Raw Splunk version file
|   |   +-- server_info.json               # OPTIONAL - REST /services/server/info
|   |   +-- installed_apps.json            # OPTIONAL - REST /services/apps/local
|   |   +-- search_peers.json              # OPTIONAL - REST distributed search peers
|   |   +-- license_info.json              # OPTIONAL - REST licenser/licenses
|   |
|   +-- rbac/                              # OPTIONAL - User/role data
|   |   +-- users.json                     # REST /services/authentication/users
|   |   +-- users_active_in_apps.json      # OPTIONAL - Scoped mode: users with activity
|   |   +-- roles.json                     # REST /services/authorization/roles
|   |
|   +-- indexes/                           # OPTIONAL - Index information
|   |   +-- indexes.conf                   # System indexes.conf from filesystem
|   |   +-- indexes_detailed.json          # REST /services/data/indexes
|   |   +-- data_inputs.json               # REST /services/data/inputs/all
|   |
|   +-- usage_analytics/                   # OPTIONAL - Usage analytics data
|   |   +-- dashboard_views_global.json    # Dashboard views by app (provenance-based)
|   |   +-- user_activity_global.json      # User activity per app
|   |   +-- search_patterns_global.json    # Search type breakdown per app
|   |   +-- index_volume_summary.json      # Per-index daily ingestion (GB)
|   |   +-- index_event_counts_daily.json  # Event counts per index per day (tstats)
|   |   +-- alert_firing_global.json       # Alert execution stats per app
|   |   +-- dashboard_ownership.json       # Dashboard -> owner mapping (REST)
|   |   +-- alert_ownership.json           # Alert -> owner mapping (REST)
|   |   +-- ownership_summary.json         # Ownership counts by user
|   |   +-- saved_searches_all.json        # All saved searches metadata (REST)
|   |   +-- recent_searches.json           # Recent search jobs (REST)
|   |   +-- kvstore_stats.json             # KV Store statistics (REST)
|   |   +-- USAGE_INTELLIGENCE_SUMMARY.md  # Human-readable migration guide
|   |
|   +-- index_stats.json                   # OPTIONAL - Legacy index stats
|
+-- _system/                               # OPTIONAL - System-level configs
|   +-- local/
|       +-- inputs.conf
|       +-- outputs.conf
|       +-- server.conf
|       +-- macros.conf                    # System-level macros
|
+-- <app_name>/                            # One directory per exported app
    +-- dashboards/                        # v2 app-centric structure (v4.2.0+)
    |   +-- classic/                       # Classic XML dashboards for this app
    |   |   +-- *.xml
    |   +-- studio/                        # Dashboard Studio JSON for this app
    |       +-- *.json
    +-- default/                           # Filesystem configs from $SPLUNK_HOME/etc/apps/<app>/default/
    |   +-- props.conf
    |   +-- transforms.conf
    |   +-- eventtypes.conf
    |   +-- tags.conf
    |   +-- indexes.conf
    |   +-- macros.conf
    |   +-- savedsearches.conf
    |   +-- inputs.conf
    |   +-- outputs.conf
    |   +-- collections.conf
    |   +-- fields.conf
    |   +-- workflow_actions.conf
    |   +-- commands.conf
    |   +-- data/
    |       +-- ui/
    |           +-- views/                 # Legacy dashboard location (filesystem)
    |               +-- *.xml
    +-- local/                             # Filesystem configs from $SPLUNK_HOME/etc/apps/<app>/local/
    |   +-- (same structure as default/)
    +-- metadata/                          # OPTIONAL - App metadata
    |   +-- default.meta
    |   +-- local.meta
    +-- lookups/                           # OPTIONAL - Lookup table files
        +-- *.csv
```

### Cloud Export

Cloud exports use REST API JSON responses instead of filesystem `.conf` files. Knowledge objects are stored as JSON at the app root level rather than in `default/` and `local/` subdirectories.

```
dma_cloud_export_<stack>_<YYYYMMDD_HHMMSS>.tar.gz
|
+-- manifest.json                          # REQUIRED - Export metadata & statistics
+-- _anonymization_report.json             # OPTIONAL - Only in _masked archive
+-- dma-env-summary.md                     # REQUIRED - Human-readable summary
+-- _export.log                            # REQUIRED - Export process log
|
+-- dma_analytics/                         # REQUIRED - All DMA-generated analytics
|   +-- system_info/                       # REQUIRED - System information
|   |   +-- environment.json               # REQUIRED - Standardized env info
|   |   +-- server_info.json               # OPTIONAL - REST /services/server/info
|   |   +-- installed_apps.json            # OPTIONAL - REST /services/apps/local
|   |   +-- license_info.json              # OPTIONAL - REST licenser/licenses
|   |   +-- server_settings.json           # OPTIONAL - REST /services/server/settings
|   |   +-- all_dashboards.json            # OPTIONAL - Master dashboard list from REST
|   |
|   +-- rbac/                              # OPTIONAL - User/role data
|   |   +-- users.json                     # REST /services/authentication/users
|   |   +-- users_active_in_apps.json      # OPTIONAL - Scoped mode: users with activity
|   |   +-- roles.json                     # REST /services/authorization/roles
|   |
|   +-- indexes/                           # OPTIONAL - Index information
|   |   +-- indexes.json                   # REST /services/data/indexes
|   |   +-- indexes_extended.json          # OPTIONAL - REST /services/data/indexes-extended
|   |   +-- indexes_used_by_apps.json      # OPTIONAL - Scoped mode: indexes per app
|   |
|   +-- usage_analytics/                   # OPTIONAL - Usage analytics data
|       +-- dashboard_views_global.json    # Dashboard views by app (provenance-based)
|       +-- user_activity_global.json      # User activity per app
|       +-- search_patterns_global.json    # Search type breakdown per app
|       +-- index_volume_summary.json      # Per-index daily ingestion (GB)
|       +-- index_event_counts_daily.json  # Event counts per index per day (tstats)
|       +-- alert_firing_global.json       # Alert execution stats per app
|       +-- dashboard_ownership.json       # Dashboard -> owner mapping (REST)
|       +-- alert_ownership.json           # Alert -> owner mapping (REST)
|       +-- ownership_summary.json         # Ownership counts by user
|       +-- saved_searches_all.json        # All saved searches metadata (REST)
|       +-- recent_searches.json           # Recent search jobs (REST)
|       +-- kvstore_stats.json             # KV Store statistics (REST)
|       +-- USAGE_INTELLIGENCE_SUMMARY.md  # Human-readable migration guide
|
+-- _configs/                              # OPTIONAL - Global system configs (REST JSON)
|   +-- indexes.json                       # Global indexes config
|   +-- inputs.json                        # Global inputs config
|   +-- outputs.json                       # Global outputs config
|
+-- <app_name>/                            # One directory per exported app
    +-- dashboards/                        # v2 app-centric structure (v4.2.0+)
    |   +-- classic/                       # Classic XML dashboards (saved as JSON from REST)
    |   |   +-- *.json
    |   +-- studio/                        # Dashboard Studio JSON for this app
    |       +-- *.json
    +-- savedsearches.json                 # Saved searches for this app (REST, filtered by acl.app)
    +-- props.json                         # Props config for this app (REST)
    +-- transforms.json                    # Transforms config for this app (REST)
    +-- macros.json                        # Macros for this app (REST)
    +-- eventtypes.json                    # Event types for this app (REST)
    +-- tags.json                          # Tags for this app (REST)
    +-- field_extractions.json             # Field extractions for this app (REST)
    +-- inputs.json                        # Data inputs for this app (REST)
    +-- lookups.json                       # Lookup table metadata (REST)
    +-- splunk-analysis/                   # OPTIONAL - Per-app analytics
        +-- alerts_inventory.json          # Alerts inventory for this app (REST)
```

### Key Differences: Enterprise vs Cloud

| Aspect | Enterprise | Cloud |
|--------|-----------|-------|
| Config format | `.conf` files (INI) from filesystem | `.json` files from REST API |
| Config location | `<app>/default/` and `<app>/local/` | `<app>/` (flat, single JSON per type) |
| Dashboard format | Classic: `.xml`, Studio: `.json` | Both stored as `.json` from REST |
| System configs | `_system/local/*.conf` from filesystem | `_configs/*.json` from REST |
| Log file name | `export.log` | `_export.log` |
| Search peers | Collected (distributed search) | Not applicable (cloud) |
| Filesystem access | Direct file copy | REST API only |

---

## File Source Categories

Understanding the origin of each file helps distinguish between **raw Splunk data** and **DMA-generated migration intelligence**.

### Category 1: Global Analytics (SPL Search Queries)

These files are generated by running SPL queries against Splunk's internal indexes (`_audit`, `_internal`). In v4.6.0, these are **6 global aggregate queries** with `by app` grouping, replacing the previous per-app query model.

| File | SPL Source | Purpose |
|------|-----------|---------|
| `dashboard_views_global.json` | `index=_audit provenance="UI:Dashboard:*"` with view_session de-duplication | Dashboard usage ranked by views per app |
| `user_activity_global.json` | `index=_audit action=search` stats by app, user | User search activity per app |
| `search_patterns_global.json` | `index=_audit action=search` with provenance-based type classification | Search type breakdown (dashboard/scheduled/ad-hoc/other) |
| `index_volume_summary.json` | `index=_internal source=*license_usage.log type=Usage` | Per-index daily ingestion volume in GB |
| `index_event_counts_daily.json` | `\| tstats count where index=* by index, _time span=1d` | Daily event counts per index (tstats fallback) |
| `alert_firing_global.json` | `index=_internal sourcetype=scheduler` stats by app, savedsearch_name | Alert execution counts and success/failure rates |

### Category 2: REST API Metadata

These files are collected directly from Splunk REST APIs. They provide metadata used for ownership mapping, search inventories, and supplementary intelligence.

| File | REST API Source | Purpose |
|------|----------------|---------|
| `dashboard_ownership.json` | `GET /servicesNS/-/-/data/ui/views` | Dashboard-to-owner mapping |
| `alert_ownership.json` | `GET /servicesNS/-/-/saved/searches` | Alert-to-owner mapping |
| `ownership_summary.json` | Computed from ownership data | Owner counts for dashboards and alerts |
| `saved_searches_all.json` | `GET /servicesNS/-/-/saved/searches` (metadata fields only) | All saved search metadata |
| `recent_searches.json` | `GET /services/search/jobs` | Recent search job list |
| `kvstore_stats.json` | `GET /services/kvstore/status` | KV Store status |

### Category 3: System Information (REST API)

| File | REST API Source | Purpose |
|------|----------------|---------|
| `environment.json` | Script-detected | Hostname, platform, Splunk version |
| `server_info.json` | `GET /services/server/info` | Splunk server details |
| `installed_apps.json` | `GET /services/apps/local` | App inventory |
| `search_peers.json` | `GET /services/search/distributed/peers` | Distributed search topology (Enterprise only) |
| `license_info.json` | `GET /services/licenser/licenses` | License details |
| `server_settings.json` | `GET /services/server/settings` | Server settings (Cloud only) |

### Category 4: RBAC Data (REST API)

| File | REST API Source | Purpose |
|------|----------------|---------|
| `users.json` | `GET /services/authentication/users` | User accounts |
| `users_active_in_apps.json` | SPL query on `_audit` (scoped mode only) | Users with activity in selected apps |
| `roles.json` | `GET /services/authorization/roles` | Role definitions |

### Category 5: Index Data

| File | Source | Purpose |
|------|--------|---------|
| `indexes.conf` | Filesystem (Enterprise) | Index definitions from config |
| `indexes.json` | REST `/services/data/indexes` (Cloud) | Index configurations |
| `indexes_detailed.json` | REST `/services/data/indexes` (Enterprise) | Detailed index info |
| `indexes_extended.json` | REST `/services/data/indexes-extended` (Cloud) | Extended index stats |
| `data_inputs.json` | REST `/services/data/inputs/all` (Enterprise) | Data input configurations |

### Category 6: App Knowledge Objects

**Enterprise** (filesystem `.conf` files):

| Directory | Files | Source |
|-----------|-------|--------|
| `<app>/default/` | `props.conf`, `transforms.conf`, `eventtypes.conf`, `tags.conf`, `macros.conf`, `savedsearches.conf`, `inputs.conf`, `outputs.conf`, `collections.conf`, `fields.conf`, `workflow_actions.conf`, `commands.conf`, `indexes.conf` | `$SPLUNK_HOME/etc/apps/<app>/default/` |
| `<app>/local/` | Same as default/ | `$SPLUNK_HOME/etc/apps/<app>/local/` |
| `<app>/lookups/` | `*.csv` | Lookup table data files |
| `<app>/metadata/` | `default.meta`, `local.meta` | App metadata (export scope) |

**Cloud** (REST API JSON, filtered by `acl.app`):

| File | REST API Source |
|------|----------------|
| `<app>/savedsearches.json` | `GET /servicesNS/-/<app>/saved/searches` |
| `<app>/props.json` | `GET /servicesNS/-/<app>/configs/conf-props` |
| `<app>/transforms.json` | `GET /servicesNS/-/<app>/configs/conf-transforms` |
| `<app>/macros.json` | `GET /servicesNS/-/<app>/admin/macros` |
| `<app>/eventtypes.json` | `GET /servicesNS/-/<app>/saved/eventtypes` |
| `<app>/tags.json` | `GET /servicesNS/-/<app>/configs/conf-tags` |
| `<app>/field_extractions.json` | `GET /servicesNS/-/<app>/data/transforms/extractions` |
| `<app>/inputs.json` | `GET /servicesNS/-/<app>/data/inputs/all` |
| `<app>/lookups.json` | `GET /servicesNS/-/<app>/data/lookup-table-files` |

---

## manifest.json (REQUIRED)

Every export MUST include a `manifest.json` at the root. The schema is the same for both Enterprise and Cloud exports.

```json
{
  "schema_version": "4.0",
  "archive_structure_version": "v2",
  "export_tool": "dma-splunk-cloud-export",
  "export_tool_version": "4.6.0",
  "export_timestamp": "2026-03-15T14:25:30Z",
  "export_duration_seconds": 847,

  "archive_structure": {
    "version": "v2",
    "description": "App-centric dashboard organization prevents name collisions",
    "dashboard_location": "{AppName}/dashboards/classic/ and {AppName}/dashboards/studio/"
  },

  "source": {
    "hostname": "mystack.splunkcloud.com",
    "fqdn": "mystack.splunkcloud.com",
    "platform": "Splunk Cloud",
    "platform_version": "victoria"
  },

  "splunk": {
    "home": "cloud",
    "version": "9.2.2403.100",
    "build": "cloud",
    "flavor": "cloud",
    "role": "search_head",
    "architecture": "cloud",
    "is_cloud": true,
    "cloud_type": "victoria",
    "server_guid": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
  },

  "collection": {
    "configs": true,
    "dashboards": true,
    "alerts": true,
    "rbac": true,
    "usage_analytics": true,
    "usage_period": "30d",
    "indexes": true,
    "lookups": false,
    "data_anonymized": false
  },

  "statistics": {
    "apps_exported": 47,
    "dashboards_classic": 312,
    "dashboards_studio": 89,
    "dashboards_total": 401,
    "alerts": 156,
    "saved_searches": 523,
    "users": 87,
    "roles": 0,
    "indexes": 45,
    "api_calls_made": 1247,
    "rate_limit_hits": 3,
    "errors": 2,
    "warnings": 8,
    "total_files": 1247,
    "total_size_bytes": 48923847
  },

  "apps": [
    {
      "name": "security_app",
      "dashboards": 87,
      "dashboards_classic": 45,
      "dashboards_studio": 42,
      "alerts": 45,
      "saved_searches": 123
    },
    {
      "name": "ops_monitoring",
      "dashboards": 45,
      "dashboards_classic": 30,
      "dashboards_studio": 15,
      "alerts": 23,
      "saved_searches": 67
    }
  ],

  "usage_intelligence": {
    "prioritization": {
      "top_dashboards": [
        {"app": "security_app", "dashboard_name": "security_overview", "view_count": "15234", "unique_users": "45"}
      ],
      "top_alerts": [
        {"app": "security_app", "savedsearch_name": "critical_error_alert", "total_runs": "8923", "successful": "8900"}
      ],
      "top_users": [
        {"app": "security_app", "user": "analyst1", "searches": "23456", "last_active": "1711929600"}
      ]
    },
    "volume": {
      "index_volume": [
        {"index_name": "main", "total_gb": "125.50", "daily_avg_gb": "4.18", "sourcetype_count": "23"}
      ],
      "index_events": [
        {"index_name": "main", "count": "45000000", "_time": "2026-03-15T00:00:00.000+00:00"}
      ],
      "note": "See index_volume_summary.json for per-index daily ingestion"
    },
    "search_patterns": [
      {"app": "security_app", "search_type": "dashboard", "total_searches": "45000", "unique_users": "32"}
    ]
  }
}
```

### Manifest Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"4.0"` |
| `archive_structure_version` | string | Always `"v2"` (app-centric dashboards) |
| `export_tool` | string | `"dma-splunk-export"` or `"dma-splunk-cloud-export"` |
| `export_tool_version` | string | Script version (e.g., `"4.6.0"`) |
| `export_timestamp` | ISO 8601 | When export was created |
| `export_duration_seconds` | number | Total export time |
| `archive_structure.version` | string | Dashboard organization version |
| `archive_structure.dashboard_location` | string | Where dashboards live |
| `source.hostname` | string | Machine hostname or cloud stack name |
| `splunk.version` | string | Splunk version |
| `splunk.flavor` | string | `"enterprise"`, `"cloud"`, or `"uf"` |
| `splunk.is_cloud` | boolean | Whether this is Splunk Cloud |
| `collection.*` | boolean | Which data categories were collected |
| `collection.usage_period` | string | Analytics time range (e.g., `"30d"`) |
| `statistics.*` | number | Counts of collected objects |
| `apps` | array | Per-app breakdown of dashboards, alerts, saved searches |
| `usage_intelligence` | object | Programmatic access to analytics for migration prioritization |

---

## environment.json (REQUIRED)

Located at `dma_analytics/system_info/environment.json`:

```json
{
  "hostname": "splunk-sh01",
  "platform": "Linux",
  "platformVersion": "5.4.0-150-generic",
  "architecture": "x86_64",
  "splunkHome": "/opt/splunk",
  "splunkFlavor": "enterprise",
  "splunkRole": "search_head",
  "splunkArchitecture": "distributed",
  "exportTimestamp": "2026-03-15T14:25:30Z",
  "exportVersion": "4.6.0"
}
```

---

## _anonymization_report.json (OPTIONAL)

This file is **only present when data anonymization is enabled**. It documents the anonymization process and serves as a receipt confirming the export has been sanitized.

### Two-Archive Approach (v4.2.4+)

When anonymization is enabled, the export script creates **TWO separate archives**:

| Archive | Content | Purpose |
|---------|---------|---------|
| `{export_name}.tar.gz` | **Original, untouched data** | Keep for your records; re-run anonymization if needed |
| `{export_name}_masked.tar.gz` | **Anonymized copy** | Safe to share with consultants, support teams, external parties |

**Why Two Archives?**
- Preserves original data in case anonymization corrupts files
- Allows re-running anonymization without re-running the entire export
- Clear naming makes it obvious which file is safe to share

The `_anonymization_report.json` file is **only present in the `_masked` archive**.

### Schema

```json
{
  "anonymization_applied": true,
  "timestamp": "2026-03-15T15:30:45Z",
  "statistics": {
    "files_processed": 847,
    "unique_emails_anonymized": 156,
    "unique_hosts_anonymized": 89,
    "ip_addresses": "all_redacted"
  },
  "transformations": {
    "emails": "original@domain.com -> user######@anon.dma.local",
    "hostnames": "server.example.com -> host-########.anon.local",
    "ipv4": "x.x.x.x -> [IP-REDACTED]",
    "ipv6": "xxxx:xxxx:... -> [IPv6-REDACTED]"
  },
  "note": "This export has been anonymized. Original values cannot be recovered from this data."
}
```

### Key Properties

- **Consistent Mapping**: The same original email/hostname always produces the same anonymized value (SHA-256 hash-based)
- **Irreversible**: Hashing means originals cannot be recovered
- **Preserved Relationships**: Data relationships remain intact (all references to `server-01` become the same anonymized value)
- **Selective Preservation**: `localhost` and `127.0.0.1` are NOT anonymized

### When to Expect This File

- Present when user selects anonymization option
- Absent when anonymization is not selected
- Check `manifest.json` > `collection.data_anonymized` to programmatically detect

---

## Usage Analytics (v4.6.0)

### Architecture Change in v4.6.0

Previous versions ran **per-app analytics queries** (N apps x 7 queries = potentially thousands of search jobs). v4.6.0 replaces this with **6 global aggregate queries** that include `by app` grouping. The DMA Curator server splits results into per-app views after import.

### Global Analytics Files

All 6 files are located in `dma_analytics/usage_analytics/`:

| File | Query Type | Key Fields | Use For |
|------|-----------|------------|---------|
| `dashboard_views_global.json` | `_audit` with provenance | `app`, `dashboard_name`, `view_count`, `unique_users`, `viewers`, `last_viewed` | Migration prioritization by dashboard usage |
| `user_activity_global.json` | `_audit` action=search | `app`, `user`, `searches`, `unique_searches`, `last_active` | Stakeholder identification and training planning |
| `search_patterns_global.json` | `_audit` with type classification | `app`, `search_type`, `total_searches`, `unique_users`, `unique_searches` | Workload characterization (dashboard/scheduled/ad-hoc/other) |
| `index_volume_summary.json` | `_internal` license_usage.log | `index_name`, `total_bytes`, `total_gb`, `daily_avg_gb`, `sourcetype_count`, `host_count` | Dynatrace Grail storage planning and cost estimation |
| `index_event_counts_daily.json` | `\| tstats` (works without _internal) | `index_name`, `count`, `_time` | Volume trending and event rate estimation |
| `alert_firing_global.json` | `_internal` sourcetype=scheduler | `app`, `savedsearch_name`, `total_runs`, `successful`, `skipped`, `failed`, `last_run` | Critical alert identification and health assessment |

### Supplementary Metadata Files

Also in `dma_analytics/usage_analytics/`:

| File | Source | Use For |
|------|--------|---------|
| `dashboard_ownership.json` | REST API | Dashboard-to-owner mapping for user-centric migration |
| `alert_ownership.json` | REST API | Alert-to-owner mapping for user-centric migration |
| `ownership_summary.json` | Computed | Owner counts for dashboards and alerts |
| `saved_searches_all.json` | REST API (metadata fields only) | Saved search inventory without full SPL |
| `recent_searches.json` | REST API | Recent search job list |
| `kvstore_stats.json` | REST API | KV Store status and statistics |
| `USAGE_INTELLIGENCE_SUMMARY.md` | Generated | Human-readable migration guide |

### Ownership Files

**dashboard_ownership.json example:**
```json
{
  "results": [
    {"dashboard": "security_overview", "app": "security_app", "owner": "splunk_user", "sharing": "app"},
    {"dashboard": "incident_tracker", "app": "security_app", "owner": "splunk_user", "sharing": "global"},
    {"dashboard": "system_health", "app": "ops_monitoring", "owner": "admin", "sharing": "app"}
  ]
}
```

**Use Case - User-Centric Migration:**
```typescript
// Filter dashboards for current user
const userDashboards = ownership.results.filter(d => d.owner === currentUser);
```

### Per-App Analytics (Cloud)

In Cloud exports, each app directory may contain a `splunk-analysis/` subdirectory with:

| File | Purpose |
|------|---------|
| `alerts_inventory.json` | Scheduled alerts and their configuration for this app (via `\| rest` command) |

### v4.6.0 Key Improvements

- **Dashboard views use the `provenance` field** (not `search_type=dashboard` which was unreliable)
- **View session de-duplication**: Counts page loads (30s window), not individual panel searches
- **Global aggregate queries**: 6 queries total instead of N x 7 per-app queries
- **Async search dispatch**: Searches can run up to 1 hour (was limited to 5 minutes with `exec_mode=blocking`)
- **Never-viewed dashboards**: Computed by the Curator from dashboard list + view data (no slow `| rest + | join`)

### Migration Decision Matrix

```
                    HIGH USAGE                    LOW USAGE
                +-------------------------+-------------------------+
   HIGH VALUE   | MIGRATE FIRST           | Review with stakeholders|
                | Top dashboards, alerts  | May have seasonal use   |
                +-------------------------+-------------------------+
   LOW VALUE    | Consider migrating      | ELIMINATE               |
                | Users depend on these   | Never viewed/fired      |
                +-------------------------+-------------------------+
```

---

## Guaranteed Fields by Category

### Apps (per app directory)

**Enterprise (.conf files):**

| File | Guaranteed Fields | Notes |
|------|-------------------|-------|
| `savedsearches.conf` | `[stanza_name]`, `search`, `cron_schedule`, `alert.*` | Alerts have `alert.track = 1` |
| `props.conf` | `[stanza_name]`, `TRANSFORMS-*`, `EXTRACT-*`, `REPORT-*` | Field extractions |
| `transforms.conf` | `[stanza_name]`, `REGEX`, `FORMAT`, `DEST_KEY` | Transform definitions |
| `macros.conf` | `[macro_name]`, `definition`, `args` | Search macros |
| `eventtypes.conf` | `[eventtype_name]`, `search` | Event classifications |
| `tags.conf` | `[source/sourcetype/eventtype]`, `tag=value` | Tags |

**Cloud (.json files):**

All REST API JSON responses follow Splunk's standard envelope format:
```json
{
  "entry": [
    {
      "name": "stanza_name",
      "acl": {"app": "app_name", "owner": "admin", "sharing": "app"},
      "content": { ... }
    }
  ]
}
```

### Dashboard XML (Classic - Enterprise)

All dashboard XML files must be valid Splunk SimpleXML:

```xml
<dashboard version="1.1">
  <label>Dashboard Title</label>
  <description>Description text</description>
  <row>
    <panel>
      <title>Panel Title</title>
      <chart>
        <search>
          <query>index=main | stats count by sourcetype</query>
          <earliest>-24h@h</earliest>
          <latest>now</latest>
        </search>
      </chart>
    </panel>
  </row>
</dashboard>
```

### Dashboard Studio JSON

```json
{
  "visualizations": {},
  "dataSources": {},
  "inputs": {},
  "layout": {},
  "title": "Dashboard Title",
  "description": "Description"
}
```

---

## Validation Rules

DMA validates exports against these rules:

### MUST Have (Export Fails Without These)
1. `manifest.json` exists and is valid JSON
2. `manifest.json` > `schema_version` is `"3.1"` or higher
3. `dma_analytics/system_info/environment.json` exists
4. At least one of: app directories OR `dma_analytics/` content

### SHOULD Have (Warnings If Missing)
1. Export log (`export.log` or `_export.log`) for troubleshooting
2. `dma-env-summary.md` for human review
3. `manifest.json` > `statistics` section populated
4. `manifest.json` > `usage_intelligence` section (for migration prioritization)

### Data Quality Checks
1. All `.conf` files are valid INI format
2. All `.json` files are valid JSON
3. All `.xml` dashboard files are valid XML
4. No binary files in unexpected locations
5. File paths don't contain `..` (path traversal)

---

## Handling Missing Data

When data is unavailable (no REST API access, permissions, etc.):

1. **Directory still created** but empty or with placeholder
2. **manifest.json** reflects actual collection status
3. **Warning logged** to export log

Example for missing RBAC:
```json
{
  "collection": {
    "rbac": false
  },
  "statistics": {
    "users": 0,
    "roles": 0
  }
}
```

Example for scoped mode placeholder:
```json
{
  "scoped": true,
  "reason": "App-scoped mode - only indexes used by selected apps collected",
  "apps": ["security_app", "ops_monitoring"]
}
```

---

## Versioning

| Schema Version | Export Tool Version | Changes |
|----------------|---------------------|---------|
| 4.0 | 4.6.0 | Global analytics (6 queries vs N x 7), provenance-based dashboard views, async search dispatch, view session de-duplication, simplified usage_analytics directory |
| 4.0 | 4.2.4 | Two-archive anonymization (original + _masked), RBAC/usage OFF by default, query optimizations |
| 4.0 | 4.2.0 | App-centric dashboard structure (v2): `{AppName}/dashboards/classic/` and `{AppName}/dashboards/studio/` |
| 4.0 | 4.1.0 | App-scoped export mode (`--apps`, `--scoped`, `--quick`), debug mode |
| 4.0 | 4.0.2 | Auto-fix for CRLF line endings (Windows download compatibility) |
| 4.0 | 4.0.1 | Container-friendly progress display (newlines at 5% intervals for kubectl/docker exec) |
| 4.0 | 4.0.0 | Enterprise resilience: paginated APIs, checkpoints, extended timeouts, timing stats |
| 3.4 | 3.4.0 | Added ownership mapping (dashboard_ownership.json, alert_ownership.json) |
| 3.3 | 3.3.0 | Added daily volume analysis and volume section to usage_intelligence |
| 3.2 | 3.2.0 | Added usage_intelligence to manifest.json |
| 3.1 | 3.1.0 | Added progress tracking, histograms, timing |
| 3.0 | 3.0.0 | Initial standardized schema |

---

## Example: Minimal Valid Export

The smallest valid export contains:

```
dma_export_splunk01_20260315_142530.tar.gz
+-- manifest.json
+-- dma_analytics/
    +-- system_info/
        +-- environment.json
```

With `manifest.json`:
```json
{
  "schema_version": "4.0",
  "archive_structure_version": "v2",
  "export_tool": "dma-splunk-export",
  "export_tool_version": "4.6.0",
  "export_timestamp": "2026-03-15T14:25:30Z",
  "source": {
    "hostname": "splunk01"
  },
  "splunk": {
    "flavor": "uf",
    "role": "universal_forwarder"
  },
  "statistics": {
    "apps_exported": 0,
    "dashboards_total": 0
  }
}
```

---

## DMA Parser Contract

DMA guarantees it can parse any export conforming to this schema:

```typescript
interface DMAExport {
  manifest: ExportManifest;           // Always present
  systemInfo: SystemInfo;             // Always present
  apps: Map<string, AppExport>;       // May be empty
  dashboardStudio: DashboardStudio[]; // May be empty
  rbac?: RBACExport;                  // Optional
  indexes?: IndexExport;              // Optional
  usageAnalytics?: UsageExport;       // Optional
}
```

The parser handles:
- Missing optional directories gracefully
- Partial data (some apps exported, others failed)
- Version differences (backward compatible)
- Encoding variations (UTF-8, UTF-16, etc.)
- Both Enterprise (`.conf`) and Cloud (`.json`) formats
