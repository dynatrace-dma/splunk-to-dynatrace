# Script-Generated Analytics Reference

## DynaBridge Splunk Export - Complete Analytics File Reference

**Applies To**: Splunk Enterprise & Splunk Cloud Export Scripts
**Version**: 4.0.1 (Enterprise) / 4.0.1 (Cloud)
**Last Updated**: January 2026

---

## Executive Summary

The DynaBridge Splunk Export Scripts generate **migration intelligence files** by running SPL queries against Splunk's internal indexes (`_audit`, `_internal`). These files provide insights that **do not exist natively in Splunk** and are specifically designed to support data-driven migration decisions.

### Key Value Proposition

| What Splunk Provides | What DynaBridge Generates |
|---------------------|---------------------------|
| Raw configurations | **Migration prioritization scores** |
| Dashboard definitions | **Dashboard usage analytics** (who views what, how often) |
| Alert configurations | **Alert effectiveness metrics** (which fire, which don't) |
| User accounts | **User activity intelligence** (who's active, who's not) |
| Index definitions | **Volume trends and capacity planning data** |

---

## Enterprise vs. Cloud: Key Differences

Both the **Enterprise** and **Cloud** export scripts generate the **same ~47 analytics files**. However, there are important differences in how data is collected and potential limitations:

### Comparison Matrix

| Aspect | Enterprise Script | Cloud Script |
|--------|------------------|--------------|
| **Script File** | `dynabridge-splunk-export.sh` | `dynabridge-splunk-cloud-export.sh` |
| **Access Method** | File system + REST API | REST API only |
| **Run Location** | On the Splunk server | Any machine with network access |
| **Authentication** | Username/password | API Token (recommended) or username/password |
| **`_audit` Index Access** | Full access | May be restricted (Classic Experience) |
| **`_internal` Index Access** | Full access | May be restricted |
| **File System Exports** | Yes (`.conf` files, XML dashboards) | No (REST API only) |
| **Expected Success Rate** | ~95-100% of analytics files | ~70-90% (varies by Cloud tier/config) |

### Cloud-Specific Limitations

Splunk Cloud environments may have restricted access to internal indexes. The following analytics categories are most likely to be affected:

| Category | Risk Level | Reason |
|----------|------------|--------|
| **Dashboard View Analytics** | 🟡 Medium | Requires `_audit` index access |
| **User Activity Analytics** | 🟡 Medium | Requires `_audit` index access |
| **Alert Execution Analytics** | 🟡 Medium | Requires `_internal` scheduler logs |
| **Search Pattern Analytics** | 🟡 Medium | Requires `_audit` index access |
| **Volume & Capacity Analytics** | 🟠 High | Requires `_internal` license_usage.log |
| **Ingestion Infrastructure** | 🟠 High | Requires `_internal` metrics.log |
| **Ownership Mapping** | 🟢 Low | Uses REST API (`| rest` command) |
| **Scheduler & Performance** | 🟡 Medium | Requires `_internal` index access |

### Cloud Workarounds

If analytics files fail in Splunk Cloud:

1. **Check Permissions**: Ensure your user/token has `admin_all_objects` and `search` capabilities
2. **Classic vs. Victoria**: Victoria Experience may have different restrictions than Classic
3. **Support Ticket**: Some organizations can request enhanced access to internal indexes
4. **Manual Export**: For critical analytics, run the SPL query manually in Splunk Web and export results

### File Status Indicators

When parsing export archives, DynaBridge handles missing analytics gracefully:

```json
{
  "analytics_status": {
    "dashboard_views_top100.json": "success",
    "daily_volume_by_index.json": "failed_access_denied",
    "users_most_active.json": "success"
  }
}
```

---

## File Categories Overview

| Category | Files | Primary Use Case | Enterprise | Cloud |
|----------|-------|------------------|------------|-------|
| [Dashboard Analytics](#1-dashboard-analytics) | 4 | Identify high-value dashboards to migrate | ✅ Full | 🟡 Partial |
| [User Activity Analytics](#2-user-activity-analytics) | 4 | Identify stakeholders and inactive users | ✅ Full | 🟡 Partial |
| [Alert Analytics](#3-alert-analytics) | 6 | Find critical alerts vs. elimination candidates | ✅ Full | 🟡 Partial |
| [Search Pattern Analytics](#4-search-pattern-analytics) | 4 | Understand query patterns for DQL conversion | ✅ Full | 🟡 Partial |
| [Data Source Analytics](#5-data-source-analytics) | 4 | Map data sources for ingestion planning | ✅ Full | 🟡 Partial |
| [Volume & Capacity Analytics](#6-volume--capacity-analytics) | 8 | Plan Dynatrace Grail bucket sizing | ✅ Full | 🟠 Limited |
| [Ingestion Infrastructure](#7-ingestion-infrastructure-analytics) | 9 | Understand data collection methods for OneAgent planning | ✅ Full | 🟠 Limited |
| [Ownership Mapping](#8-ownership-mapping-analytics) | 3 | Enable user-centric migration | ✅ Full | ✅ Full |
| [Scheduler & Performance](#9-scheduler--performance-analytics) | 4 | Plan Dynatrace workflow capacity | ✅ Full | 🟡 Partial |
| [Manifest & Environment](#10-manifest--environment) | 2 | Export metadata and environment detection | ✅ Full | ✅ Full |

**Total: ~47 Script-Generated Files**

### Availability Legend

| Icon | Meaning | Description |
|------|---------|-------------|
| ✅ Full | Available | All files in this category are expected to succeed |
| 🟡 Partial | Likely Available | Most files succeed; some may fail depending on Cloud configuration |
| 🟠 Limited | May Fail | Files require `_internal` index access which is often restricted in Cloud |

---

## 1. Dashboard Analytics

### 1.1 `dashboard_views_top100.json`

**Location**: `_usage_analytics/dashboard_views_top100.json`

**Cloud Availability**: 🟡 Requires `_audit` index access - may fail in restricted Cloud environments

**SPL Query Source**:
```spl
index=_audit action=search info=granted search_type=dashboard
| stats count as view_count, dc(user) as unique_users, latest(_time) as last_viewed
  by app, dashboard
| sort - view_count
| head 100
```

**Description**:
Lists the top 100 most-viewed dashboards in the Splunk environment over the analysis period (default 30 days). Includes view count, unique viewer count, and last access timestamp.

**Sample Output**:
```json
{
  "results": [
    {
      "app": "security_app",
      "dashboard": "security_overview",
      "view_count": 2345,
      "unique_users": 45,
      "last_viewed": "2025-12-03T14:30:00Z"
    }
  ]
}
```

**DynaBridge Migration Purpose**:
- **Prioritization**: Dashboards with high view counts should be migrated first
- **Stakeholder Identification**: Unique user count helps identify which teams depend on each dashboard
- **Validation**: After migration, compare Dynatrace dashboard usage to baseline Splunk usage

---

### 1.2 `dashboard_views_trend.json`

**Location**: `_usage_analytics/dashboard_views_trend.json`

**Cloud Availability**: 🟡 Requires `_audit` index access - may fail in restricted Cloud environments

**SPL Query Source**:
```spl
index=_audit action=search info=granted search_type=dashboard
| timechart span=1d count as views by dashboard limit=20
```

**Description**:
Daily view trends for the top 20 dashboards over the analysis period. Shows usage patterns over time.

**DynaBridge Migration Purpose**:
- **Trend Analysis**: Identify dashboards with growing vs. declining usage
- **Timing**: Schedule migration of high-trend dashboards during low-usage periods
- **Seasonality**: Detect dashboards with periodic usage (month-end reports, etc.)

---

### 1.3 `dashboards_never_viewed.json`

**Location**: `_usage_analytics/dashboards_never_viewed.json`

**Cloud Availability**: 🟡 Requires `_audit` index access - may fail in restricted Cloud environments

**SPL Query Source**:
```spl
index=_audit action=search info=granted search_type=dashboard
| stats count by dashboard
| append [| rest /servicesNS/-/-/data/ui/views | table title | rename title as dashboard | eval count=0]
| stats sum(count) as total_views by dashboard
| where total_views=0
```

**Description**:
Lists all dashboards that have **zero views** during the analysis period. These are candidates for elimination rather than migration.

**Sample Output**:
```json
{
  "results": [
    {"dashboard": "old_test_dashboard"},
    {"dashboard": "legacy_report_v1"},
    {"dashboard": "unused_prototype"}
  ]
}
```

**DynaBridge Migration Purpose**:
- **Cost Reduction**: Avoid migrating unused dashboards (saves conversion effort)
- **Cleanup Opportunity**: Present to stakeholders as archive/delete candidates
- **Migration Scope**: Reduce project scope by excluding dead weight

---

### 1.4 `dashboard_ownership.json`

**Location**: `_usage_analytics/dashboard_ownership.json`

**Cloud Availability**: ✅ Uses REST API - works in both Enterprise and Cloud

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/data/ui/views
| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing
| rename title as dashboard, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing
```

**Description**:
Complete mapping of every dashboard to its owner, app, and sharing level.

**Sample Output**:
```json
{
  "results": [
    {
      "dashboard": "security_overview",
      "app": "security_app",
      "owner": "jsmith",
      "sharing": "app"
    }
  ]
}
```

**DynaBridge Migration Purpose**:
- **User-Centric Migration**: Show users only their own dashboards during migration
- **Responsibility Assignment**: Know who to contact for dashboard requirements
- **Access Control**: Map Splunk sharing to Dynatrace document permissions

---

## 2. User Activity Analytics

### 2.1 `users_most_active.json`

**Location**: `_usage_analytics/users_most_active.json`

**Cloud Availability**: 🟡 Requires `_audit` index access - may fail in restricted Cloud environments

**SPL Query Source**:
```spl
index=_audit action=search info=granted
| stats count as search_count, dc(search) as unique_searches, latest(_time) as last_active
  by user
| sort - search_count
| head 50
```

**Description**:
Top 50 most active users ranked by search count. Shows total searches, variety of searches, and last activity time.

**DynaBridge Migration Purpose**:
- **Stakeholder Engagement**: Identify power users who should be consulted during migration
- **Training Priority**: Focus training on most active users first
- **UAT Planning**: Select active users for User Acceptance Testing

---

### 2.2 `users_inactive.json`

**Location**: `_usage_analytics/users_inactive.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted
| stats latest(_time) as last_active by user
| where last_active < relative_time(now(), "-30d")
| table user, last_active
```

**Description**:
Users with no search activity in the last 30 days.

**DynaBridge Migration Purpose**:
- **Scope Reduction**: Don't migrate personal content for inactive users
- **License Planning**: Identify users who may not need Dynatrace access
- **Cleanup**: Identify potential orphaned content

---

### 2.3 `daily_active_users.json`

**Location**: `_usage_analytics/daily_active_users.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted
| timechart span=1d dc(user) as active_users
```

**Description**:
Daily count of unique active users over the analysis period.

**DynaBridge Migration Purpose**:
- **Adoption Baseline**: Establish pre-migration user engagement metrics
- **Post-Migration Comparison**: Validate Dynatrace adoption matches Splunk usage
- **Capacity Planning**: Understand concurrent user patterns

---

### 2.4 `activity_by_role.json`

**Location**: `_usage_analytics/activity_by_role.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted
| stats count as searches, dc(user) as users by roles
| sort - searches
```

**Description**:
Search activity broken down by Splunk role.

**DynaBridge Migration Purpose**:
- **Role-Based Migration**: Prioritize migration for high-activity roles
- **Permission Mapping**: Map Splunk roles to Dynatrace IAM groups
- **Training Planning**: Customize training by role

---

## 3. Alert Analytics

### 3.1 `alerts_most_fired.json`

**Location**: `_usage_analytics/alerts_most_fired.json`

**Cloud Availability**: 🟡 Requires `_internal` index access - may fail in restricted Cloud environments

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler status=success savedsearch_name=*
| stats count as fire_count, avg(run_time) as avg_runtime, latest(_time) as last_fired
  by savedsearch_name, app
| where fire_count > 0
| sort - fire_count
| head 100
```

**Description**:
Top 100 most frequently executed alerts with execution count, average runtime, and last execution time.

**Sample Output**:
```json
{
  "results": [
    {
      "savedsearch_name": "Security - Failed Logins",
      "app": "security_app",
      "fire_count": 2880,
      "avg_runtime": 12.5,
      "last_fired": "2025-12-03T14:00:00Z"
    }
  ]
}
```

**DynaBridge Migration Purpose**:
- **Critical Alert Identification**: High-fire alerts are operationally critical
- **Performance Planning**: Runtime data helps plan Dynatrace workflow execution
- **Conversion Priority**: Migrate frequently-firing alerts first

---

### 3.2 `alerts_with_actions.json`

**Location**: `_usage_analytics/alerts_with_actions.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler status=success alert_actions!=""
| stats count as action_count, values(alert_actions) as actions
  by savedsearch_name
| sort - action_count
| head 50
```

**Description**:
Alerts that have triggered actions (email, webhook, PagerDuty, etc.) ranked by action count.

**DynaBridge Migration Purpose**:
- **Action Mapping**: Identify Splunk alert actions to map to Dynatrace workflows
- **Integration Discovery**: Discover integrations (PagerDuty, Slack, etc.) to configure in Dynatrace
- **Criticality Assessment**: Alerts with actions are typically more critical

---

### 3.3 `alerts_failed.json`

**Location**: `_usage_analytics/alerts_failed.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler (status=failed OR status=skipped)
| stats count as failure_count, latest(status) as last_status, latest(reason) as last_reason
  by savedsearch_name
| sort - failure_count
| head 50
```

**Description**:
Alerts with execution failures or skips, including failure reasons.

**DynaBridge Migration Purpose**:
- **Fix Before Migrate**: Address broken alerts before converting to Dynatrace
- **Elimination Candidates**: Persistently failing alerts may be candidates for removal
- **Root Cause Analysis**: Understand why alerts fail to prevent issues in Dynatrace

---

### 3.4 `alerts_never_fired.json`

**Location**: `_usage_analytics/alerts_never_fired.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler
| stats count by savedsearch_name
| append [| rest /servicesNS/-/-/saved/searches search="alert.track=1" | table title | rename title as savedsearch_name | eval count=0]
| stats sum(count) as total_fires by savedsearch_name
| where total_fires=0
```

**Description**:
Alerts that exist but have never executed during the analysis period.

**DynaBridge Migration Purpose**:
- **Elimination Candidates**: Why migrate alerts that never fire?
- **Review Triggers**: May indicate misconfigured schedules or conditions
- **Scope Reduction**: Reduce migration effort by excluding unused alerts

---

### 3.5 `alert_firing_trend.json`

**Location**: `_usage_analytics/alert_firing_trend.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler status=success
| timechart span=1d count as alert_fires by savedsearch_name limit=20
```

**Description**:
Daily firing trends for the top 20 alerts over the analysis period.

**DynaBridge Migration Purpose**:
- **Trend Analysis**: Identify alerts with increasing/decreasing activity
- **Anomaly Detection**: Spot unusual firing patterns before migration
- **Baseline Establishment**: Compare post-migration alert behavior

---

### 3.6 `alert_ownership.json`

**Location**: `_usage_analytics/alert_ownership.json`

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/saved/searches
| table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, is_scheduled, alert.track
| rename title as alert_name, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing
```

**Description**:
Complete mapping of every saved search/alert to its owner, app, and scheduling status.

**DynaBridge Migration Purpose**:
- **Ownership Tracking**: Know who to contact for alert requirements
- **User-Centric Migration**: Show users their own alerts during conversion
- **Responsibility Assignment**: Assign migration tasks by owner

---

## 4. Search Pattern Analytics

### 4.1 `search_commands_popular.json`

**Location**: `_usage_analytics/search_commands_popular.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted search=*
| rex field=search "^\s*\|?\s*(?<first_command>\w+)"
| stats count by first_command
| sort - count
| head 30
```

**Description**:
Most frequently used SPL commands across all searches.

**Sample Output**:
```json
{
  "results": [
    {"first_command": "search", "count": 45678},
    {"first_command": "stats", "count": 23456},
    {"first_command": "timechart", "count": 12345}
  ]
}
```

**DynaBridge Migration Purpose**:
- **DQL Mapping Priority**: Focus SPL→DQL conversion on most-used commands
- **Training Focus**: Train users on DQL equivalents of their most-used SPL
- **Conversion Complexity**: Identify commands that may require custom solutions

---

### 4.2 `search_by_type.json`

**Location**: `_usage_analytics/search_by_type.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted
| stats count by search_type
| sort - count
```

**Description**:
Search activity broken down by type (ad-hoc, scheduled, dashboard, etc.).

**DynaBridge Migration Purpose**:
- **Usage Pattern Understanding**: Know the mix of interactive vs. scheduled queries
- **Workflow Planning**: High scheduled search count = more Dynatrace workflows needed
- **User Behavior**: Understand how users interact with data

---

### 4.3 `searches_slow.json`

**Location**: `_usage_analytics/searches_slow.json`

**SPL Query Source**:
```spl
index=_audit action=search info=completed
| where total_run_time > 60
| stats count as slow_runs, avg(total_run_time) as avg_time, max(total_run_time) as max_time
  by search_id, user
| sort - avg_time
| head 50
```

**Description**:
Searches with runtime greater than 60 seconds, ranked by average runtime.

**DynaBridge Migration Purpose**:
- **Performance Optimization**: Identify queries that need optimization before/during migration
- **DQL Optimization**: Flag queries that may need different approaches in DQL
- **Capacity Planning**: Long-running queries impact Dynatrace query unit consumption

---

### 4.4 `indexes_searched.json`

**Location**: `_usage_analytics/indexes_searched.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted search=*
| rex field=search "index=(?<searched_index>\w+)"
| stats count by searched_index
| sort - count
| head 20
```

**Description**:
Most frequently searched indexes extracted from query patterns.

**DynaBridge Migration Purpose**:
- **Data Ingestion Priority**: Ensure frequently searched indexes are available in Grail
- **Query Conversion**: Know which indexes to map to Grail buckets in DQL
- **Scope Definition**: Focus data migration on actually-used indexes

---

## 5. Data Source Analytics

### 5.1 `sourcetypes_searched.json`

**Location**: `_usage_analytics/sourcetypes_searched.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted search=*
| rex field=search "sourcetype=(?<searched_sourcetype>[\w:_-]+)"
| stats count as search_count, dc(user) as users by searched_sourcetype
| sort - search_count
| head 50
```

**Description**:
Most frequently searched sourcetypes extracted from query patterns.

**DynaBridge Migration Purpose**:
- **OpenPipeline Priority**: Create OpenPipeline processors for most-searched sourcetypes
- **Field Extraction Planning**: Focus DPL field extraction on high-value sourcetypes
- **Data Mapping**: Map Splunk sourcetypes to Dynatrace log attributes

---

### 5.2 `indexes_queried.json`

**Location**: `_usage_analytics/indexes_queried.json`

**SPL Query Source**:
```spl
index=_audit action=search info=granted search=*
| rex field=search "index=(?<queried_index>[\w_-]+)"
| stats count as query_count, dc(user) as users by queried_index
| sort - query_count
```

**Description**:
All indexes that appear in search queries, ranked by query frequency.

**DynaBridge Migration Purpose**:
- **Active Index Identification**: Distinguish actively-queried indexes from dormant ones
- **Bucket Mapping**: Map queried indexes to Dynatrace Grail buckets
- **Ingestion Planning**: Prioritize data ingestion for actively-queried indexes

---

### 5.3 `index_sizes.json`

**Location**: `_usage_analytics/index_sizes.json`

**SPL Query Source**:
```spl
| dbinspect index=*
| stats sum(sizeOnDiskMB) as size_mb, sum(eventCount) as events by index
| sort - size_mb
```

**Description**:
Storage size and event count for each index.

**DynaBridge Migration Purpose**:
- **Grail Capacity Planning**: Size Dynatrace buckets based on Splunk index sizes
- **Cost Estimation**: Estimate Dynatrace storage costs based on volume
- **Retention Planning**: Compare Splunk retention to Grail retention requirements

---

### 5.4 `saved_searches_all.json`

**Location**: `_usage_analytics/saved_searches_all.json`

**REST API Source**: `GET /services/saved/searches`

**Description**:
Complete metadata for all saved searches from Splunk REST API.

**DynaBridge Migration Purpose**:
- **Comprehensive Inventory**: Full saved search catalog for migration planning
- **Query Extraction**: Extract SPL queries for conversion to DQL
- **Schedule Analysis**: Understand scheduling patterns for Dynatrace workflow setup

---

## 6. Volume & Capacity Analytics

### 6.1 `daily_volume_by_index.json`

**Location**: `_usage_analytics/daily_volume_by_index.json`

**Cloud Availability**: 🟠 Requires `_internal` license_usage.log - often restricted in Cloud environments

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| timechart span=1d sum(b) as bytes by idx
| eval gb=round(bytes/1024/1024/1024,2)
| fields _time, idx, gb
```

**Description**:
Daily ingestion volume (GB) per index over the last 30 days.

**DynaBridge Migration Purpose**:
- **Grail Bucket Sizing**: Size each bucket based on actual daily volume
- **Trend Analysis**: Identify growing indexes that need capacity headroom
- **Cost Projection**: Project Dynatrace ingestion costs by index

---

### 6.2 `daily_volume_by_sourcetype.json`

**Location**: `_usage_analytics/daily_volume_by_sourcetype.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| timechart span=1d sum(b) as bytes by st
| eval gb=round(bytes/1024/1024/1024,2)
| fields _time, st, gb
```

**Description**:
Daily ingestion volume (GB) per sourcetype over the last 30 days.

**DynaBridge Migration Purpose**:
- **OpenPipeline Sizing**: Size processing capacity by sourcetype volume
- **Log Source Mapping**: Map Splunk sourcetypes to Dynatrace log sources
- **Optimization Targets**: Identify high-volume sourcetypes for compression/filtering

---

### 6.3 `daily_volume_summary.json`

**Location**: `_usage_analytics/daily_volume_summary.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| timechart span=1d sum(b) as bytes
| eval gb=round(bytes/1024/1024/1024,2)
| stats avg(gb) as avg_daily_gb, max(gb) as peak_daily_gb, sum(gb) as total_30d_gb
```

**Description**:
Summary statistics: average daily volume, peak daily volume, and 30-day total.

**Sample Output**:
```json
{
  "results": [
    {
      "avg_daily_gb": 125.5,
      "peak_daily_gb": 189.2,
      "total_30d_gb": 3765.0
    }
  ]
}
```

**DynaBridge Migration Purpose**:
- **License Planning**: Estimate Dynatrace DPS/DDU requirements
- **Peak Capacity**: Plan for peak ingestion days
- **Budget Estimation**: Project monthly/annual Dynatrace costs

---

### 6.4 `daily_events_by_index.json`

**Location**: `_usage_analytics/daily_events_by_index.json`

**SPL Query Source**:
```spl
index=_internal source=*metrics.log group=per_index_thruput earliest=-30d@d
| timechart span=1d sum(ev) as events by series
| rename series as index
```

**Description**:
Daily event count per index over the last 30 days.

**DynaBridge Migration Purpose**:
- **Event Rate Planning**: Understand events per second (EPS) by index
- **Query Performance**: High event counts may impact DQL query performance
- **Sampling Strategy**: Identify indexes that may benefit from sampling

---

### 6.5 `hourly_volume_pattern.json`

**Location**: `_usage_analytics/hourly_volume_pattern.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-7d
| eval hour=strftime(_time, "%H")
| stats sum(b) as bytes by hour
| eval gb=round(bytes/1024/1024/1024,2)
| sort hour
```

**Description**:
Hourly ingestion pattern showing which hours have highest volume.

**DynaBridge Migration Purpose**:
- **Peak Hour Identification**: Know when peak ingestion occurs
- **Maintenance Windows**: Schedule migrations during low-volume hours
- **Burst Capacity**: Plan Dynatrace capacity for peak hours

---

### 6.6 `top_indexes_by_volume.json`

**Location**: `_usage_analytics/top_indexes_by_volume.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| stats sum(b) as total_bytes by idx
| eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2)
| sort - daily_avg_gb
| head 20
```

**Description**:
Top 20 indexes ranked by daily average volume.

**DynaBridge Migration Purpose**:
- **80/20 Analysis**: Typically 20% of indexes contain 80% of volume
- **Migration Priority**: Focus on high-volume indexes for biggest impact
- **Cost Optimization**: Identify indexes for potential filtering/sampling

---

### 6.7 `top_sourcetypes_by_volume.json`

**Location**: `_usage_analytics/top_sourcetypes_by_volume.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| stats sum(b) as total_bytes by st
| eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2)
| sort - daily_avg_gb
| head 20
```

**Description**:
Top 20 sourcetypes ranked by daily average volume.

**DynaBridge Migration Purpose**:
- **OpenPipeline Priority**: Build processors for highest-volume sourcetypes first
- **Parsing Optimization**: Focus parsing effort on high-volume data
- **Field Extraction ROI**: Extract fields from sourcetypes with most data

---

### 6.8 `top_hosts_by_volume.json`

**Location**: `_usage_analytics/top_hosts_by_volume.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d@d
| stats sum(b) as total_bytes by h
| eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2)
| sort - daily_avg_gb
| head 50
```

**Description**:
Top 50 hosts ranked by daily average volume sent.

**DynaBridge Migration Purpose**:
- **OneAgent Deployment**: Prioritize OneAgent installation on high-volume hosts
- **Infrastructure Mapping**: Map Splunk forwarder hosts to Dynatrace monitored hosts
- **Troubleshooting**: Identify chatty hosts that may need log filtering

---

## 7. Ingestion Infrastructure Analytics

### 7.1 `by_connection_type.json`

**Location**: `_usage_analytics/ingestion_infrastructure/by_connection_type.json`

**Cloud Availability**: 🟠 Requires `_internal` metrics.log - often restricted in Cloud environments

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d
| stats dc(sourceHost) as unique_hosts, sum(kb) as total_kb by connectionType
| eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)
```

**Description**:
Data ingestion broken down by connection type (cooked from UF, raw from HF, etc.).

**DynaBridge Migration Purpose**:
- **Forwarder Inventory**: Understand ratio of Universal vs. Heavy Forwarders
- **OneAgent Planning**: Plan log ingestion method based on forwarder architecture
- **Migration Strategy**: Determine if logs can route directly to Dynatrace

---

### 7.2 `by_input_method.json`

**Location**: `_usage_analytics/ingestion_infrastructure/by_input_method.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d
| rex field=series "^(?<input_type>[^:]+):"
| stats sum(kb) as total_kb, dc(series) as unique_sources by input_type
| eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)
| sort - total_kb
```

**Description**:
Data ingestion broken down by input method (splunktcp, http, monitor, udp, tcp, etc.).

**DynaBridge Migration Purpose**:
- **Input Mapping**: Map Splunk inputs to Dynatrace ingestion methods
- **HEC Migration**: Identify HEC usage for migration to Dynatrace Log Ingest API
- **Syslog Planning**: Plan Dynatrace ActiveGate syslog receivers

---

### 7.3 `hec_usage.json`

**Location**: `_usage_analytics/ingestion_infrastructure/hec_usage.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput series=http:* earliest=-7d
| stats sum(kb) as total_kb, dc(series) as token_count
| eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)
```

**Description**:
HTTP Event Collector (HEC) usage statistics including volume and token count.

**DynaBridge Migration Purpose**:
- **API Migration**: Size Dynatrace Log Ingest API capacity
- **Token Mapping**: Plan API token migration from Splunk HEC to Dynatrace
- **Application Integration**: Identify applications sending data via HEC

---

### 7.4 `forwarding_hosts.json`

**Location**: `_usage_analytics/ingestion_infrastructure/forwarding_hosts.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d
| stats sum(kb) as total_kb, latest(_time) as last_seen, values(connectionType) as connection_types
  by sourceHost
| eval total_gb=round(total_kb/1024/1024,2)
| sort - total_kb
| head 500
```

**Description**:
Inventory of up to 500 forwarding hosts with volume, last activity, and connection type.

**DynaBridge Migration Purpose**:
- **OneAgent Deployment List**: Direct list of hosts needing OneAgent installation
- **Forwarder Migration**: Plan OneAgent Splunk Forwarder extension deployment
- **Infrastructure Mapping**: Map Splunk forwarder topology to Dynatrace hosts

---

### 7.5 `by_sourcetype_category.json`

**Location**: `_usage_analytics/ingestion_infrastructure/by_sourcetype_category.json`

**SPL Query Source**:
```spl
index=_internal source=*license_usage.log type=Usage earliest=-30d
| stats sum(b) as bytes, dc(h) as unique_hosts by st
| eval daily_avg_gb=round((bytes/30)/1024/1024/1024,2)
| eval category=case(
    match(st,"^otel|^otlp|opentelemetry"),"opentelemetry",
    match(st,"^aws:|^azure:|^gcp:|^cloud"),"cloud",
    match(st,"^WinEventLog|^windows|^wmi"),"windows",
    match(st,"^linux|^syslog|^nix"),"linux_unix",
    match(st,"^cisco:|^pan:|^juniper:|^fortinet:|^f5:|^checkpoint"),"network_security",
    match(st,"^access_combined|^nginx|^apache|^iis"),"web",
    match(st,"^docker|^kube|^container"),"containers",
    1=1,"other"
  )
| stats sum(daily_avg_gb) as daily_avg_gb, sum(unique_hosts) as unique_hosts, values(st) as sourcetypes
  by category
| sort - daily_avg_gb
```

**Description**:
Sourcetypes grouped into logical categories (OpenTelemetry, cloud, Windows, Linux, network/security, web, containers, other).

**DynaBridge Migration Purpose**:
- **Migration Strategy**: Different categories may have different migration paths
- **OpenTelemetry Detection**: Identify if OTel data is already in Splunk
- **Dynatrace Entity Mapping**: Map log categories to Dynatrace entity types

---

### 7.6 `data_inputs_by_app.json`

**Location**: `_usage_analytics/ingestion_infrastructure/data_inputs_by_app.json`

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/data/inputs/all
| stats count by eai:acl.app, disabled
| eval status=if(disabled="0","enabled","disabled")
| stats count by eai:acl.app, status
```

**Description**:
Data input definitions grouped by app with enabled/disabled status.

**DynaBridge Migration Purpose**:
- **Input Inventory**: Complete catalog of data inputs per app
- **Active vs. Disabled**: Focus on enabled inputs only
- **App Dependencies**: Understand which apps have data input dependencies

---

### 7.7 `syslog_inputs.json`

**Location**: `_usage_analytics/ingestion_infrastructure/syslog_inputs.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d
| search series=udp:* OR series=tcp:*
| stats sum(kb) as total_kb by series
| eval total_gb=round(total_kb/1024/1024,2)
| sort - total_kb
```

**Description**:
Syslog input volume breakdown by UDP and TCP listeners.

**DynaBridge Migration Purpose**:
- **Syslog Migration**: Plan Dynatrace ActiveGate syslog receiver configuration
- **Port Mapping**: Identify ports used for syslog collection
- **Volume Planning**: Size syslog ingestion capacity in Dynatrace

---

### 7.8 `scripted_inputs.json`

**Location**: `_usage_analytics/ingestion_infrastructure/scripted_inputs.json`

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/data/inputs/script
| stats count by eai:acl.app, disabled, interval
| eval status=if(disabled="0","enabled","disabled")
```

**Description**:
Inventory of scripted inputs with app, status, and execution interval.

**DynaBridge Migration Purpose**:
- **Custom Integration Mapping**: Scripted inputs often represent custom integrations
- **Extension Planning**: May need Dynatrace extensions to replace scripted inputs
- **OneAgent Extension**: Some scripts may be replaceable by OneAgent capabilities

---

### 7.9 `summary.json` (Ingestion)

**Location**: `_usage_analytics/ingestion_infrastructure/summary.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d
| stats dc(sourceHost) as total_forwarding_hosts, sum(kb) as total_kb
| eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)
```

**Description**:
High-level summary of forwarding infrastructure: total hosts, total volume, daily average.

**DynaBridge Migration Purpose**:
- **Migration Scope**: Quick view of infrastructure size
- **OneAgent Deployment Scale**: Number of hosts requiring agent installation
- **Capacity Planning**: Total daily ingestion volume for Dynatrace sizing

---

## 8. Ownership Mapping Analytics

### 8.1 `dashboard_ownership.json`

*See [Section 1.4](#14-dashboard_ownershipjson) above*

---

### 8.2 `alert_ownership.json`

*See [Section 3.6](#36-alert_ownershipjson) above*

---

### 8.3 `ownership_summary.json`

**Location**: `_usage_analytics/ownership_summary.json`

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/data/ui/views
| stats count as dashboards by eai:acl.owner
| rename eai:acl.owner as owner
| append [| rest /servicesNS/-/-/saved/searches | stats count as alerts by eai:acl.owner | rename eai:acl.owner as owner]
| stats sum(dashboards) as dashboards, sum(alerts) as alerts by owner
| sort - dashboards
```

**Description**:
Summary of dashboard and alert ownership by user.

**Sample Output**:
```json
{
  "results": [
    {"owner": "jsmith", "dashboards": 45, "alerts": 23},
    {"owner": "security_team", "dashboards": 32, "alerts": 67},
    {"owner": "admin", "dashboards": 28, "alerts": 45}
  ]
}
```

**DynaBridge Migration Purpose**:
- **Workload Distribution**: Identify owners with most content to migrate
- **Task Assignment**: Assign migration tasks based on ownership
- **Stakeholder Identification**: Large owners are key stakeholders

---

## 9. Scheduler & Performance Analytics

### 9.1 `scheduler_load.json`

**Location**: `_usage_analytics/scheduler_load.json`

**SPL Query Source**:
```spl
index=_internal sourcetype=scheduler
| timechart span=1h count as scheduled_searches, avg(run_time) as avg_runtime
```

**Description**:
Hourly scheduler activity showing search count and average runtime.

**DynaBridge Migration Purpose**:
- **Workflow Capacity**: Plan Dynatrace workflow execution capacity
- **Peak Hours**: Identify scheduler load patterns for workflow scheduling
- **Performance Baseline**: Establish pre-migration scheduler performance

---

### 9.2 `saved_searches_by_owner.json`

**Location**: `_usage_analytics/saved_searches_by_owner.json`

**SPL Query Source**:
```spl
| rest /servicesNS/-/-/saved/searches
| stats count by eai:acl.owner
| sort - count
| head 30
```

**Description**:
Top 30 saved search owners ranked by search count.

**DynaBridge Migration Purpose**:
- **Owner Identification**: Know who owns the most scheduled content
- **Migration Assignment**: Distribute conversion work by ownership
- **Stakeholder Priority**: High-count owners are key stakeholders

---

### 9.3 `recent_searches.json`

**Location**: `_usage_analytics/recent_searches.json`

**REST API Source**: `GET /services/search/jobs?count=1000`

**Description**:
Last 1000 search jobs with full metadata from Splunk REST API.

**DynaBridge Migration Purpose**:
- **Search Pattern Analysis**: Understand recent query patterns
- **Performance Metrics**: Runtime and result count for recent searches
- **User Behavior**: Who's running what queries

---

### 9.4 `kvstore_stats.json`

**Location**: `_usage_analytics/kvstore_stats.json`

**REST API Source**: `GET /services/server/introspection/kvstore`

**Description**:
KV Store statistics and health metrics.

**DynaBridge Migration Purpose**:
- **KV Store Migration**: Identify KV Store collections for potential migration
- **Data Dependencies**: Dashboard Studio uses KV Store - understand dependencies
- **Capacity Planning**: KV Store size impacts Dashboard Studio migration

---

## 10. Manifest & Environment

### 10.1 `manifest.json`

**Location**: Root of export (`manifest.json`)

**Generated By**: Export script aggregation logic

**Description**:
Master manifest containing all export metadata, statistics, and migration intelligence summaries.

**Key Contents**:
- Schema version and tool version
- Source environment details (hostname, Splunk version, architecture)
- Collection options used
- Statistics (apps, dashboards, alerts, users, indexes)
- Usage intelligence summary (top dashboards, top alerts, elimination candidates)
- Volume summaries
- Checksums

**DynaBridge Migration Purpose**:
- **Programmatic Parsing**: DynaBridge parser reads manifest first
- **Migration Planning**: High-level statistics for project scoping
- **Validation**: Checksums ensure export integrity

---

### 10.2 `environment.json`

**Location**: `_systeminfo/environment.json`

**Generated By**: Script environment detection logic

**Description**:
Detected environment profile including hostname, platform, Splunk version, and deployment architecture.

**Sample Output**:
```json
{
  "hostname": "splunk-sh01",
  "fqdn": "splunk-sh01.company.com",
  "platform": "Linux",
  "platform_version": "5.4.0-150-generic",
  "architecture": "x86_64",
  "splunk_home": "/opt/splunk",
  "splunk_flavor": "enterprise",
  "splunk_role": "search_head",
  "splunk_architecture": "distributed",
  "splunk_version": "9.1.3",
  "export_timestamp": "2025-12-03T14:25:30Z",
  "export_version": "4.0.0"
}
```

**DynaBridge Migration Purpose**:
- **Environment Identification**: Distinguish exports from different environments
- **Architecture Understanding**: Distributed vs. standalone impacts migration approach
- **Version Compatibility**: Ensure SPL/DQL conversion considers Splunk version

---

## Quick Reference: Files by Migration Use Case

### Use Case 1: Dashboard Migration Prioritization

| File | Use |
|------|-----|
| `dashboard_views_top100.json` | Which dashboards to migrate first |
| `dashboards_never_viewed.json` | Which dashboards to skip |
| `dashboard_ownership.json` | Who to contact for each dashboard |

### Use Case 2: Alert Migration Prioritization

| File | Use |
|------|-----|
| `alerts_most_fired.json` | Which alerts to migrate first |
| `alerts_with_actions.json` | Which alerts have integrations to map |
| `alerts_never_fired.json` | Which alerts to skip |
| `alerts_failed.json` | Which alerts to fix or eliminate |
| `alert_ownership.json` | Who to contact for each alert |

### Use Case 3: Data Ingestion Planning

| File | Use |
|------|-----|
| `daily_volume_summary.json` | Total ingestion volume for licensing |
| `top_indexes_by_volume.json` | Which indexes to prioritize |
| `top_sourcetypes_by_volume.json` | Which sourcetypes need OpenPipeline |
| `forwarding_hosts.json` | Hosts needing OneAgent deployment |
| `by_connection_type.json` | Forwarder type distribution |

### Use Case 4: Capacity Planning

| File | Use |
|------|-----|
| `daily_volume_summary.json` | Average and peak daily GB |
| `hourly_volume_pattern.json` | Peak hour identification |
| `index_sizes.json` | Total storage requirements |
| `scheduler_load.json` | Workflow execution capacity |

### Use Case 5: Stakeholder Identification

| File | Use |
|------|-----|
| `users_most_active.json` | Power users to engage |
| `users_inactive.json` | Users to deprioritize |
| `ownership_summary.json` | Content owners by volume |

### Use Case 6: Cleanup Before Migration

| File | Use |
|------|-----|
| `dashboards_never_viewed.json` | Dashboards to archive/delete |
| `alerts_never_fired.json` | Alerts to review/delete |
| `alerts_failed.json` | Broken alerts to fix/delete |
| `users_inactive.json` | Personal content to skip |

---

## Appendix A: Complete Cloud Availability Reference

This table provides Cloud availability status for **all 47 script-generated analytics files**.

### Dashboard Analytics (4 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `dashboard_views_top100.json` | `index=_audit` | 🟡 May fail |
| `dashboard_views_trend.json` | `index=_audit` | 🟡 May fail |
| `dashboards_never_viewed.json` | `index=_audit` + REST | 🟡 May fail |
| `dashboard_ownership.json` | REST API | ✅ Works |

### User Activity Analytics (4 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `users_most_active.json` | `index=_audit` | 🟡 May fail |
| `users_inactive.json` | `index=_audit` + REST | 🟡 May fail |
| `daily_active_users.json` | `index=_audit` | 🟡 May fail |
| `activity_by_role.json` | `index=_audit` + REST | 🟡 May fail |

### Alert Analytics (6 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `alerts_most_fired.json` | `index=_internal` | 🟡 May fail |
| `alerts_with_actions.json` | `index=_internal` | 🟡 May fail |
| `alerts_failed.json` | `index=_internal` | 🟡 May fail |
| `alerts_never_fired.json` | `index=_internal` + REST | 🟡 May fail |
| `alert_firing_trend.json` | `index=_internal` | 🟡 May fail |
| `alert_ownership.json` | REST API | ✅ Works |

### Search Pattern Analytics (4 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `search_commands_popular.json` | `index=_audit` | 🟡 May fail |
| `search_by_type.json` | `index=_audit` | 🟡 May fail |
| `searches_slow.json` | `index=_audit` | 🟡 May fail |
| `indexes_searched.json` | `index=_audit` | 🟡 May fail |

### Data Source Analytics (4 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `sourcetypes_searched.json` | `index=_audit` | 🟡 May fail |
| `indexes_queried.json` | `index=_internal` | 🟠 Often fails |
| `index_sizes.json` | REST API | ✅ Works |
| `saved_searches_all.json` | REST API | ✅ Works |

### Volume & Capacity Analytics (8 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `daily_volume_by_index.json` | `index=_internal` license_usage | 🟠 Often fails |
| `daily_volume_by_sourcetype.json` | `index=_internal` license_usage | 🟠 Often fails |
| `daily_volume_summary.json` | `index=_internal` license_usage | 🟠 Often fails |
| `daily_events_by_index.json` | `index=_internal` metrics | 🟠 Often fails |
| `hourly_volume_pattern.json` | `index=_internal` license_usage | 🟠 Often fails |
| `top_indexes_by_volume.json` | `index=_internal` license_usage | 🟠 Often fails |
| `top_sourcetypes_by_volume.json` | `index=_internal` license_usage | 🟠 Often fails |
| `top_hosts_by_volume.json` | `index=_internal` license_usage | 🟠 Often fails |

### Ingestion Infrastructure Analytics (9 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `by_connection_type.json` | `index=_internal` metrics | 🟠 Often fails |
| `by_input_method.json` | `index=_internal` metrics | 🟠 Often fails |
| `hec_usage.json` | `index=_internal` metrics | 🟠 Often fails |
| `forwarding_hosts.json` | `index=_internal` metrics | 🟠 Often fails |
| `by_sourcetype_category.json` | `index=_internal` license_usage | 🟠 Often fails |
| `data_inputs_by_app.json` | REST API | ✅ Works |
| `syslog_inputs.json` | `index=_internal` metrics | 🟠 Often fails |
| `scripted_inputs.json` | REST API | ✅ Works |
| `summary.json` | `index=_internal` metrics | 🟠 Often fails |

### Ownership Mapping Analytics (3 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `dashboard_ownership.json` | REST API | ✅ Works |
| `alert_ownership.json` | REST API | ✅ Works |
| `ownership_summary.json` | REST API | ✅ Works |

### Scheduler & Performance Analytics (4 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `scheduler_load.json` | `index=_internal` | 🟡 May fail |
| `saved_searches_by_owner.json` | REST API | ✅ Works |
| `recent_searches.json` | REST API | ✅ Works |
| `kvstore_stats.json` | REST API | ✅ Works |

### Manifest & Environment (2 files)

| File | Data Source | Cloud Status |
|------|-------------|--------------|
| `manifest.json` | Script-generated | ✅ Works |
| `environment.json` | Script-generated | ✅ Works |

### Summary by Cloud Status

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ Works (REST API / Script-generated) | 16 | 34% |
| 🟡 May fail (`_audit` dependent) | 14 | 30% |
| 🟠 Often fails (`_internal` dependent) | 17 | 36% |

### Cloud Migration Recommendations

1. **Start with guaranteed files**: Focus on REST API-based files first (ownership, saved searches, index sizes)
2. **Test internal access**: Run a test query against `_audit` and `_internal` to determine your Cloud tier's access level
3. **Request access**: If volume/ingestion analytics are critical, file a support ticket to request `_internal` access
4. **Alternative volume data**: Use Splunk Cloud's License Usage Report dashboard as an alternative to volume analytics
5. **Document gaps**: If analytics fail, document this for manual migration planning

---

## Appendix B: SPL to DQL Considerations

When converting queries that reference these analytics, remember:

| Splunk Concept | Dynatrace Equivalent |
|----------------|---------------------|
| `index=_audit` | No direct equivalent - use Dynatrace audit logs |
| `index=_internal` | No direct equivalent - use Dynatrace platform metrics |
| `| stats` | `| summarize` in DQL |
| `| timechart` | `| makeTimeseries` in DQL |
| `| rex` | `| parse` with DPL in DQL |
| `sourcetype` | Log attribute or `log.source` |
| `index` | Grail bucket or `dt.system.bucket` |

---

*Document Version: 4.0.0*
*Applies To: DynaBridge Splunk Enterprise & Cloud Export Scripts*
*Last Updated: January 2026*
