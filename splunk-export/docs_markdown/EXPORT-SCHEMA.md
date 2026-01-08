# DynaBridge Splunk Export Schema v3.4

## Purpose

This document defines the **guaranteed output schema** for all DynaBridge Splunk exports. Regardless of Splunk environment size, version, or deployment type, exports MUST conform to this schema so DynaBridge can reliably parse them.

---

## Archive Structure

Every export produces a `.tar.gz` archive with this **exact** structure:

```
dynabridge_export_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
│
├── manifest.json                    # REQUIRED - Export metadata
├── _anonymization_report.json       # OPTIONAL - Only present if anonymization enabled
├── dynasplunk-env-summary.md        # REQUIRED - Human-readable summary
├── export.log                       # REQUIRED - Export process log
│
├── _systeminfo/                     # REQUIRED - System information
│   ├── environment.json             # REQUIRED - Standardized env info
│   ├── splunk.version               # OPTIONAL - Raw Splunk version file
│   ├── server_info.json             # OPTIONAL - REST API server info
│   ├── installed_apps.json          # OPTIONAL - All installed apps
│   ├── search_peers.json            # OPTIONAL - Distributed search peers
│   └── license_info.json            # OPTIONAL - License information
│
├── _rbac/                           # OPTIONAL - User/role data
│   ├── users.json                   # User list
│   ├── roles.json                   # Role definitions
│   ├── authentication.conf          # Auth config (passwords redacted)
│   └── authorize.conf               # Authorization config
│
├── _indexes/                        # OPTIONAL - Index information
│   ├── indexes.conf                 # Index definitions
│   ├── indexes_detailed.json        # REST API index details
│   └── data_inputs.json             # Data input configurations
│
├── _usage_analytics/                # OPTIONAL - Usage data
│   ├── recent_searches.json         # Search job history
│   ├── saved_searches_all.json      # All saved searches
│   ├── kvstore_stats.json           # KV Store statistics
│   └── server_status.json           # Server status
│
├── _system/                         # OPTIONAL - System-level configs
│   └── local/
│       ├── inputs.conf
│       ├── outputs.conf
│       └── server.conf
│
├── _audit_sample/                   # OPTIONAL - Audit log sample
│   └── audit_sample.log
│
├── dashboard_studio/                # OPTIONAL - Dashboard Studio exports
│   ├── dashboards_list.json         # List of all dashboards
│   └── <dashboard_name>.json        # Individual dashboard definitions
│
└── <app_name>/                      # One directory per exported app
    ├── default/
    │   ├── props.conf
    │   ├── transforms.conf
    │   ├── eventtypes.conf
    │   ├── tags.conf
    │   ├── indexes.conf
    │   ├── macros.conf
    │   ├── savedsearches.conf
    │   ├── inputs.conf
    │   ├── outputs.conf
    │   ├── collections.conf
    │   ├── fields.conf
    │   ├── workflow_actions.conf
    │   ├── commands.conf
    │   └── data/
    │       └── ui/
    │           └── views/
    │               └── *.xml        # Classic dashboards
    ├── local/
    │   └── (same structure as default/)
    └── lookups/                     # OPTIONAL
        └── *.csv
```

---

## File Source Categories

Understanding the origin of each file helps distinguish between **raw Splunk data** and **DynaBridge-generated migration intelligence**.

### Category 1: Script-Generated Analytics (DynaBridge Migration Intelligence)

These files are **created by the export script** by running SPL queries against Splunk's internal indexes (`_audit`, `_internal`). They provide migration-specific insights that don't exist natively in Splunk.

| Directory | File | Purpose | SPL Query Source |
|-----------|------|---------|------------------|
| `_usage_analytics/` | `dashboard_views_top100.json` | Prioritize high-value dashboards | `index=_audit action=search search_type=dashboard` |
| `_usage_analytics/` | `dashboards_never_viewed.json` | Identify elimination candidates | `index=_audit` + REST comparison |
| `_usage_analytics/` | `users_most_active.json` | Identify stakeholders | `index=_audit action=search` |
| `_usage_analytics/` | `users_inactive.json` | Skip inactive user content | `index=_audit` with time filter |
| `_usage_analytics/` | `alerts_most_fired.json` | Critical alerts to migrate | `index=_internal sourcetype=scheduler` |
| `_usage_analytics/` | `alerts_never_fired.json` | Elimination candidates | `index=_internal` + REST comparison |
| `_usage_analytics/` | `alerts_failed.json` | Broken alerts to fix/skip | `index=_internal status=failed` |
| `_usage_analytics/` | `alerts_with_actions.json` | Alerts with triggered actions | `index=_internal alert_actions!=''` |
| `_usage_analytics/` | `alert_firing_trend.json` | Alert activity trends | `index=_internal sourcetype=scheduler` |
| `_usage_analytics/` | `sourcetypes_searched.json` | Data sources actually used | `index=_audit` with rex extraction |
| `_usage_analytics/` | `indexes_queried.json` | Which indexes matter | `index=_audit` with rex extraction |
| `_usage_analytics/` | `indexes_searched.json` | Most searched indexes | `index=_audit action=search` |
| `_usage_analytics/` | `index_sizes.json` | Capacity planning | `| dbinspect` or REST |
| `_usage_analytics/` | `daily_volume_by_index.json` | Daily ingestion by index | `index=_internal` metrics |
| `_usage_analytics/` | `daily_volume_by_sourcetype.json` | Daily ingestion by sourcetype | `index=_internal` metrics |
| `_usage_analytics/` | `daily_volume_summary.json` | Overall volume metrics | `index=_internal` aggregation |
| `_usage_analytics/` | `daily_events_by_index.json` | Event counts by index | `index=_internal` metrics |
| `_usage_analytics/` | `hourly_volume_pattern.json` | Peak hour identification | `index=_internal` timechart |
| `_usage_analytics/` | `top_indexes_by_volume.json` | High-volume index focus | `index=_internal` stats |
| `_usage_analytics/` | `top_sourcetypes_by_volume.json` | High-volume sourcetype focus | `index=_internal` stats |
| `_usage_analytics/` | `top_hosts_by_volume.json` | Host-level volume analysis | `index=_internal` stats |
| `_usage_analytics/` | `search_commands_popular.json` | Popular SPL commands | `index=_audit` with rex extraction |
| `_usage_analytics/` | `search_by_type.json` | Searches by type | `index=_audit` stats |
| `_usage_analytics/` | `searches_slow.json` | Performance concerns | `index=_audit` with runtime filter |
| `_usage_analytics/` | `daily_active_users.json` | User engagement trends | `index=_audit` timechart |
| `_usage_analytics/` | `activity_by_role.json` | Activity by role | `index=_audit` by roles |
| `_usage_analytics/` | `dashboard_ownership.json` | Dashboard → owner mapping | REST `/servicesNS/-/-/data/ui/views` |
| `_usage_analytics/` | `alert_ownership.json` | Alert → owner mapping | REST `/servicesNS/-/-/saved/searches` |
| `_usage_analytics/` | `ownership_summary.json` | Ownership by user | Aggregation of ownership data |
| `_usage_analytics/` | `saved_searches_all.json` | All saved searches metadata | REST `/servicesNS/-/-/saved/searches` |
| `_usage_analytics/` | `recent_searches.json` | Recent search jobs | REST `/services/search/jobs` |
| `_usage_analytics/` | `kvstore_stats.json` | KV Store statistics | REST `/services/kvstore/status` |
| `_usage_analytics/` | `scheduler_load.json` | Alert/report load | `index=_internal sourcetype=scheduler` |
| `_usage_analytics/ingestion_infrastructure/` | `by_connection_type.json` | Ingestion by connection | `index=_internal` metrics |
| `_usage_analytics/ingestion_infrastructure/` | `by_input_method.json` | Ingestion by input type | `index=_internal` metrics |
| `_usage_analytics/ingestion_infrastructure/` | `hec_usage.json` | HEC usage metrics | `index=_internal` HEC stats |
| `_usage_analytics/ingestion_infrastructure/` | `forwarding_hosts.json` | Forwarder host list | `index=_internal` host stats |
| `_usage_analytics/ingestion_infrastructure/` | `by_sourcetype_category.json` | Sourcetype categories | `index=_internal` stats |
| `_usage_analytics/ingestion_infrastructure/` | `data_inputs_by_app.json` | Inputs by app | `index=_internal` stats |
| `_usage_analytics/ingestion_infrastructure/` | `syslog_inputs.json` | Syslog input metrics | `index=_internal` syslog stats |
| `_usage_analytics/ingestion_infrastructure/` | `scripted_inputs.json` | Scripted input metrics | `index=_internal` script stats |
| `_usage_analytics/ingestion_infrastructure/` | `summary.json` | Ingestion summary | Aggregation |
| Root | `manifest.json` | Master manifest with stats | Script-generated metadata |
| `_systeminfo/` | `environment.json` | Script-detected environment | Script environment detection |

**Total: ~45 script-generated files** providing migration intelligence

### Category 2: Raw Splunk API Exports (Direct Splunk Data)

These files are **direct dumps from Splunk REST APIs** - essentially reformatted native Splunk data structures with minimal transformation.

| Directory | File | Splunk REST API Source | Purpose |
|-----------|------|------------------------|---------|
| `_systeminfo/` | `server_info.json` | `GET /services/server/info` | Splunk version, platform |
| `_systeminfo/` | `installed_apps.json` | `GET /services/apps/local` | App inventory |
| `_systeminfo/` | `search_peers.json` | `GET /services/search/distributed/peers` | Distributed search topology |
| `_systeminfo/` | `license_info.json` | `GET /services/licenser/licenses` | License details |
| `_rbac/` | `users.json` | `GET /services/authentication/users` | User accounts |
| `_rbac/` | `roles.json` | `GET /services/authorization/roles` | Role definitions |
| `_indexes/` | `indexes_detailed.json` | `GET /services/data/indexes` | Index configurations |
| `_indexes/` | `data_inputs.json` | `GET /services/data/inputs/all` | Data input definitions |
| `dashboard_studio/` | `dashboards_list.json` | `GET /servicesNS/-/-/data/ui/views` | Dashboard Studio list |
| `dashboard_studio/` | `{dashboard_name}.json` | `GET /servicesNS/{owner}/{app}/data/ui/views/{name}` | Individual dashboards |

**Total: ~10 base files + N dashboard files** (direct Splunk exports)

### Category 3: Raw File System Exports (Splunk Configuration Files)

These are **direct copies** of Splunk configuration files from the file system (`$SPLUNK_HOME/etc/`).

| Directory | Files | Source Location |
|-----------|-------|-----------------|
| `<app_name>/default/` | `*.conf` files | `$SPLUNK_HOME/etc/apps/<app>/default/` |
| `<app_name>/local/` | `*.conf` files | `$SPLUNK_HOME/etc/apps/<app>/local/` |
| `<app_name>/default/data/ui/views/` | `*.xml` dashboards | Classic SimpleXML dashboards |
| `<app_name>/lookups/` | `*.csv` files | Lookup table data |
| `_system/local/` | `inputs.conf`, `outputs.conf`, etc. | `$SPLUNK_HOME/etc/system/local/` |
| `_rbac/` | `authentication.conf`, `authorize.conf` | System auth configs |
| `_indexes/` | `indexes.conf` | Index definitions |

### Summary: File Source Distribution

| Category | Files | Purpose |
|----------|-------|---------|
| **Script-Generated Analytics** | ~45 | Migration intelligence (prioritization, elimination candidates, usage patterns) |
| **Raw API Exports** | ~10 + dashboards | Direct Splunk data structures |
| **Raw File Exports** | Variable (per app) | Configuration files copied from disk |

### Why This Matters

1. **Script-Generated Analytics** = **Unique DynaBridge Value**
   - These don't exist in Splunk natively
   - Enable data-driven migration prioritization
   - Identify what to migrate vs. eliminate

2. **Raw Exports** = **Source of Truth**
   - Exact representation of Splunk configurations
   - Required for accurate conversion to Dynatrace
   - No transformation applied

---

## manifest.json (REQUIRED)

Every export MUST include a `manifest.json` at the root with this exact schema:

```json
{
  "schema_version": "4.0",
  "export_tool": "dynabridge-splunk-export",
  "export_tool_version": "4.0.0",
  "export_timestamp": "2025-12-03T14:25:30Z",
  "export_duration_seconds": 847,

  "source": {
    "hostname": "splunk-sh01.example.com",
    "fqdn": "splunk-sh01.example.com",
    "ip_addresses": ["10.0.1.50", "192.168.1.50"],
    "platform": "Linux",
    "platform_version": "5.4.0-150-generic",
    "architecture": "x86_64"
  },

  "splunk": {
    "home": "/opt/splunk",
    "version": "9.1.3",
    "build": "d95b3299fa65",
    "flavor": "enterprise",
    "role": "search_head",
    "architecture": "distributed",
    "is_shc_member": true,
    "is_shc_captain": false,
    "is_idx_cluster": true,
    "is_cloud": false,
    "license_type": "enterprise",
    "license_quota_gb": 500
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
    "audit_sample": false,
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
    "roles": 23,
    "indexes": 45,
    "data_inputs": 234,
    "lookups": 0,
    "macros": 178,
    "eventtypes": 45,
    "props_stanzas": 892,
    "transforms_stanzas": 234,
    "errors": 3,
    "warnings": 12
  },

  "apps": [
    {
      "name": "security_app",
      "label": "Security Operations",
      "version": "2.3.1",
      "dashboards": 87,
      "alerts": 45,
      "saved_searches": 123,
      "has_props": true,
      "has_transforms": true,
      "has_lookups": false
    },
    {
      "name": "ops_monitoring",
      "label": "Operations Monitoring",
      "version": "1.5.0",
      "dashboards": 45,
      "alerts": 23,
      "saved_searches": 67,
      "has_props": true,
      "has_transforms": false,
      "has_lookups": true
    }
  ],

  "indexes_summary": [
    {
      "name": "main",
      "size_mb": 125000,
      "event_count": 45000000,
      "earliest_time": "2024-01-01T00:00:00Z",
      "latest_time": "2025-12-03T14:00:00Z"
    },
    {
      "name": "security",
      "size_mb": 89000,
      "event_count": 23000000,
      "earliest_time": "2024-06-01T00:00:00Z",
      "latest_time": "2025-12-03T14:00:00Z"
    }
  ],

  "data_sources_summary": [
    {
      "sourcetype": "access_combined",
      "index": "web",
      "estimated_eps": 5000,
      "sample_count": 1000000
    },
    {
      "sourcetype": "syslog",
      "index": "main",
      "estimated_eps": 12000,
      "sample_count": 5000000
    }
  ],

  "checksums": {
    "algorithm": "sha256",
    "manifest": "a1b2c3d4...",
    "total_files": 1247,
    "total_size_bytes": 48923847
  },

  "usage_intelligence": {
    "summary": {
      "dashboards_never_viewed": 45,
      "alerts_never_fired": 23,
      "users_inactive_30d": 12,
      "alerts_with_failures": 8
    },
    "prioritization": {
      "top_dashboards": [
        {"dashboard": "security_overview", "app": "security_app", "views": 15234},
        {"dashboard": "ops_dashboard", "app": "ops_monitoring", "views": 8901}
      ],
      "top_users": [
        {"user": "admin", "searches": 45123, "last_active": "2025-12-03"},
        {"user": "analyst1", "searches": 23456, "last_active": "2025-12-02"}
      ],
      "top_alerts": [
        {"alert": "critical_error_alert", "app": "security_app", "executions": 8923},
        {"alert": "disk_space_warning", "app": "ops_monitoring", "executions": 5634}
      ],
      "top_sourcetypes": [
        {"sourcetype": "access_combined", "searches": 12345},
        {"sourcetype": "syslog", "searches": 9876}
      ],
      "top_indexes": [
        {"index": "main", "searches": 34567},
        {"index": "security", "searches": 23456}
      ]
    },
    "volume": {
      "avg_daily_gb": 125.5,
      "peak_daily_gb": 189.2,
      "total_30d_gb": 3765.0,
      "top_indexes_by_volume": [
        {"idx": "main", "daily_avg_gb": 45.2},
        {"idx": "security", "daily_avg_gb": 32.1}
      ],
      "top_sourcetypes_by_volume": [
        {"st": "access_combined", "daily_avg_gb": 28.5},
        {"st": "syslog", "daily_avg_gb": 22.3}
      ],
      "top_hosts_by_volume": [
        {"h": "webserver01", "daily_avg_gb": 5.2},
        {"h": "appserver01", "daily_avg_gb": 4.8}
      ],
      "note": "See _usage_analytics/daily_volume_*.json for full daily breakdown"
    },
    "elimination_candidates": {
      "dashboards_never_viewed_count": 45,
      "alerts_never_fired_count": 23,
      "note": "See _usage_analytics/ for full lists of candidates"
    },
    "ownership": {
      "dashboard_owners": 45,
      "alert_owners": 32,
      "top_owners": [
        {"owner": "admin", "dashboards": 87, "alerts": 45},
        {"owner": "analyst1", "dashboards": 34, "alerts": 23},
        {"owner": "security_team", "dashboards": 28, "alerts": 18}
      ],
      "note": "See _usage_analytics/dashboard_ownership.json and alert_ownership.json for complete mappings"
    }
  }
}
```

---

## environment.json (REQUIRED)

Located at `_systeminfo/environment.json`:

```json
{
  "hostname": "splunk-sh01",
  "fqdn": "splunk-sh01.example.com",
  "platform": "Linux",
  "platform_version": "5.4.0-150-generic",
  "architecture": "x86_64",
  "splunk_home": "/opt/splunk",
  "splunk_flavor": "enterprise",
  "splunk_role": "search_head",
  "splunk_architecture": "distributed",
  "splunk_version": "9.1.3",
  "export_timestamp": "2025-12-03T14:25:30Z",
  "export_version": "4.0.0",
  "timezone": "UTC",
  "locale": "en_US.UTF-8"
}
```

---

## _anonymization_report.json (OPTIONAL)

This file is **only present when data anonymization is enabled** (Option 9 in Enterprise, Option 8 in Cloud). It documents the anonymization process and serves as a receipt confirming the export has been sanitized.

### Schema

```json
{
  "anonymization_applied": true,
  "timestamp": "2025-12-10T15:30:45Z",
  "statistics": {
    "files_processed": 847,
    "unique_emails_anonymized": 156,
    "unique_hosts_anonymized": 89,
    "ip_addresses": "all_redacted"
  },
  "transformations": {
    "emails": "original@domain.com → user######@anon.dynabridge.local",
    "hostnames": "server.example.com → host-########.anon.local",
    "ipv4": "x.x.x.x → [IP-REDACTED]",
    "ipv6": "xxxx:xxxx:... → [IPv6-REDACTED]"
  },
  "note": "This export has been anonymized. Original values cannot be recovered from this data."
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `anonymization_applied` | boolean | Always `true` when this file exists |
| `timestamp` | ISO 8601 | When anonymization was performed |
| `statistics.files_processed` | number | Total text files scanned |
| `statistics.unique_emails_anonymized` | number | Unique email addresses replaced |
| `statistics.unique_hosts_anonymized` | number | Unique hostnames replaced |
| `statistics.ip_addresses` | string | Always "all_redacted" |
| `transformations` | object | Example mappings showing the pattern used |
| `note` | string | Warning about irreversibility |

### Key Properties

- **Consistent Mapping**: The same original email/hostname always produces the same anonymized value (hash-based)
- **Irreversible**: SHA-256 hashing means originals cannot be recovered
- **Preserved Relationships**: Data relationships remain intact (e.g., all references to `server-01` become the same anonymized value)
- **Selective Preservation**: `localhost` and `127.0.0.1` are NOT anonymized

### When to Expect This File

- ✅ Present when user selects anonymization option
- ❌ Absent when anonymization is not selected
- Check `manifest.json.collection.data_anonymized` to programmatically detect

---

## usage_intelligence (OPTIONAL)

The `usage_intelligence` section in `manifest.json` provides programmatic access to usage analytics for migration prioritization. This data is only available if usage collection was enabled during export.

### Purpose

This section helps answer critical migration questions:
- **What should we migrate first?** → `prioritization.top_*` arrays
- **What can we skip?** → `elimination_candidates.*` counts
- **Where are the active users?** → `prioritization.top_users`
- **Which data sources matter?** → `prioritization.top_sourcetypes/indexes`
- **How much data per day?** → `volume.avg_daily_gb`, `volume.peak_daily_gb`
- **What are the biggest data sources?** → `volume.top_*_by_volume` arrays
- **Who owns what?** → `ownership.*` for user-centric migration

### Schema

| Field | Type | Description |
|-------|------|-------------|
| `summary.dashboards_never_viewed` | number | Count of dashboards with zero views in 30d |
| `summary.alerts_never_fired` | number | Count of alerts that never executed in 30d |
| `summary.users_inactive_30d` | number | Count of users with no activity in 30d |
| `summary.alerts_with_failures` | number | Count of alerts with execution failures |
| `volume.avg_daily_gb` | number | Average daily ingestion volume in GB |
| `volume.peak_daily_gb` | number | Peak daily ingestion volume in GB |
| `volume.total_30d_gb` | number | Total ingestion volume over 30 days in GB |
| `volume.top_indexes_by_volume` | array | Top 10 indexes by daily average volume |
| `volume.top_sourcetypes_by_volume` | array | Top 10 sourcetypes by daily average volume |
| `volume.top_hosts_by_volume` | array | Top 10 hosts by daily average volume |
| `prioritization.top_dashboards` | array | Top 10 most viewed dashboards |
| `prioritization.top_users` | array | Top 10 most active users |
| `prioritization.top_alerts` | array | Top 10 most fired alerts |
| `prioritization.top_sourcetypes` | array | Top 10 most searched sourcetypes |
| `prioritization.top_indexes` | array | Top 10 most queried indexes |
| `elimination_candidates.note` | string | Reference to full data in `_usage_analytics/` |
| `ownership.dashboard_owners` | number | Count of unique dashboard owners |
| `ownership.alert_owners` | number | Count of unique alert owners |
| `ownership.top_owners` | array | Top owners with dashboard and alert counts |
| `ownership.note` | string | Reference to ownership files in `_usage_analytics/` |

### Volume Files Reference

| File | Content | Use For |
|------|---------|---------|
| `daily_volume_by_index.json` | Daily GB by index (30 days) | Capacity planning by index |
| `daily_volume_by_sourcetype.json` | Daily GB by sourcetype (30 days) | Capacity planning by data type |
| `daily_volume_summary.json` | Avg, peak, total volume | License planning |
| `daily_events_by_index.json` | Daily event counts by index | Event rate estimation |
| `hourly_volume_pattern.json` | Volume by hour (7 days) | Peak hour identification |
| `top_indexes_by_volume.json` | Top 20 indexes by daily avg | High-volume index focus |
| `top_sourcetypes_by_volume.json` | Top 20 sourcetypes by daily avg | High-volume sourcetype focus |
| `top_hosts_by_volume.json` | Top 50 hosts by daily avg | Host-level volume analysis |

### Ownership Files Reference

| File | Content | Use For |
|------|---------|---------|
| `dashboard_ownership.json` | All dashboards with owner, app, sharing | Show users their own dashboards |
| `alert_ownership.json` | All alerts with owner, app, sharing, schedule | Show users their own alerts |
| `ownership_summary.json` | Owners with dashboard and alert counts | Identify major content creators |

**Example dashboard_ownership.json:**
```json
{
  "results": [
    {"dashboard": "security_overview", "app": "security_app", "owner": "jsmith", "sharing": "app"},
    {"dashboard": "incident_tracker", "app": "security_app", "owner": "jsmith", "sharing": "global"},
    {"dashboard": "system_health", "app": "ops_monitoring", "owner": "admin", "sharing": "app"}
  ]
}
```

**Use Case - User-Centric Migration:**
When a user logs into Dynatrace, show them only their Splunk dashboards:
```typescript
// Filter dashboards for current user
const userDashboards = ownership.results.filter(d => d.owner === currentUser);
```

### Migration Decision Matrix

```
                    HIGH USAGE                    LOW USAGE
                ┌─────────────────────────┬─────────────────────────┐
   HIGH VALUE   │ ★ MIGRATE FIRST         │ Review with stakeholders│
                │ Top dashboards, alerts  │ May have seasonal use   │
                ├─────────────────────────┼─────────────────────────┤
   LOW VALUE    │ Consider migrating      │ ✗ ELIMINATE             │
                │ Users depend on these   │ Never viewed/fired      │
                └─────────────────────────┴─────────────────────────┘
```

---

## Guaranteed Fields by Category

### Apps (per app directory)

| File | Guaranteed Fields | Notes |
|------|-------------------|-------|
| `savedsearches.conf` | `[stanza_name]`, `search`, `cron_schedule`, `alert.*` | Alerts have `alert.track = 1` |
| `props.conf` | `[stanza_name]`, `TRANSFORMS-*`, `EXTRACT-*`, `REPORT-*` | Field extractions |
| `transforms.conf` | `[stanza_name]`, `REGEX`, `FORMAT`, `DEST_KEY` | Transform definitions |
| `macros.conf` | `[macro_name]`, `definition`, `args` | Search macros |
| `eventtypes.conf` | `[eventtype_name]`, `search` | Event classifications |
| `tags.conf` | `[source/sourcetype/eventtype]`, `tag=value` | Tags |

### Dashboard XML (Classic)

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

DynaBridge validates exports against these rules:

### MUST Have (Export Fails Without These)
1. `manifest.json` exists and is valid JSON
2. `manifest.json.schema_version` is "3.1" or higher
3. `_systeminfo/environment.json` exists
4. At least one of: apps directory OR `_systeminfo/` content

### SHOULD Have (Warnings If Missing)
1. `export.log` for troubleshooting
2. `dynasplunk-env-summary.md` for human review
3. `manifest.json.statistics` section populated
4. `manifest.json.usage_intelligence` section (for migration prioritization)

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
3. **Warning logged** to `export.log`

Example for missing RBAC:
```json
{
  "collection": {
    "rbac": false,
    "rbac_skip_reason": "REST API authentication failed"
  },
  "statistics": {
    "users": 0,
    "roles": 0
  }
}
```

---

## Versioning

| Schema Version | Export Tool Version | Changes |
|----------------|---------------------|---------|
| 4.0 | 4.0.1 | Container-friendly progress display (newlines at 5% intervals for kubectl/docker exec) |
| 4.0 | 4.0.0 | Enterprise resilience: paginated APIs, checkpoints, extended timeouts, timing stats |
| 3.4 | 3.4.0 | Added ownership mapping for user-centric migration (dashboard_ownership.json, alert_ownership.json) |
| 3.3 | 3.3.0 | Added daily volume analysis and volume section to usage_intelligence |
| 3.2 | 3.2.0 | Added usage_intelligence to manifest.json for programmatic migration prioritization |
| 3.1 | 3.1.0 | Added progress tracking, histograms, timing |
| 3.0 | 3.0.0 | Initial standardized schema |

---

## Example: Minimal Valid Export

The smallest valid export contains:

```
dynabridge_export_splunk01_20251203_142530.tar.gz
├── manifest.json
├── _systeminfo/
│   └── environment.json
└── (empty or minimal app content)
```

With `manifest.json`:
```json
{
  "schema_version": "4.0",
  "export_tool": "dynabridge-splunk-export",
  "export_tool_version": "4.0.0",
  "export_timestamp": "2025-12-03T14:25:30Z",
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

## DynaBridge Parser Contract

DynaBridge guarantees it can parse any export conforming to this schema:

```typescript
interface DynaBridgeExport {
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
