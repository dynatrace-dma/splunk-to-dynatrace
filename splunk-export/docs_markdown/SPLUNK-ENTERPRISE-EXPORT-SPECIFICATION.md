# DMA Splunk Enterprise Export Script - Comprehensive Specification

## Version 4.4.0 | Complete Data Collection Framework

**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise README](README-SPLUNK-ENTERPRISE.md) | [Export Schema](EXPORT-SCHEMA.md)

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Executive Summary

This specification defines the complete requirements for a Splunk data collection script that supports **all Splunk deployment types** and collects **comprehensive migration intelligence** including:

- **All Splunk Flavors**: Enterprise (standalone, distributed), Cloud, Universal Forwarder, Heavy Forwarder, Search Head Cluster, Indexer Cluster, Deployment Server
- **Ownership & RBAC**: Users, groups, roles, capabilities, object ownership
- **Usage Analytics**: Query frequency, dashboard views, alert triggers, index volume trends
- **Migration Prioritization**: Scoring of high-value assets worth migrating

> **Note**: For Splunk Cloud environments, dedicated Cloud export scripts are available: `dma-splunk-cloud-export.sh` (Bash) and `dma-splunk-cloud-export.ps1` (PowerShell). See [README-SPLUNK-CLOUD.md](README-SPLUNK-CLOUD.md) for details.

---

## What's New in v4.4.0

### New CLI Flags

| Flag | Description |
|------|-------------|
| `--proxy URL` | Route all curl calls through an HTTP proxy |
| `--skip-internal` | Skip `_audit`/`_internal` index searches for restricted accounts |
| `--test-access` | Pre-flight API access check across all categories (no export written) |
| `--remask FILE` | Re-anonymize an existing archive without connecting to Splunk |
| `--resume-collect FILE` | Resume an interrupted export from a `.tar.gz` archive |

### Expanded RBAC Collection
Now collects 5 additional endpoints (all with graceful 404 handling):
- `/services/authorization/capabilities` → `capabilities.json`
- `/services/admin/SAML-groups` → `saml_groups.json`
- `/services/authentication/providers/SAML` → `saml_config.json`
- `/services/admin/LDAP-groups` → `ldap_groups.json`
- `/services/authentication/providers/LDAP` → `ldap_config.json`

When SAML or LDAP is not configured, the script writes `{"configured": false, "note": "..."}` instead of failing.

### Progressive Checkpointing
Each collection phase saves a checkpoint on completion. Usage analytics checkpoints are per-query, so interrupted analytics resume mid-way without re-running completed queries. Checkpoint file: `$EXPORT_DIR/.analytics_checkpoint`.

### Resume Support
`--resume-collect FILE` extracts a previous partial archive, detects which phases completed via checkpoint files, and continues from the first incomplete phase. Collection phases guarded with `has_collected_data()` checks for: system_info, rbac, usage_analytics, indexes.

---

## What's New in v4.3.0

### Token Authentication (`--token`)
- API token authentication via `--token TOKEN` flag (recommended for automation)
- Session key auth replaces curl basic auth (`-u user:pass`) throughout all API calls
- Password URL-encoding via Python stdin (safe for `$`, backticks, `"`, `\`)
- Token-only invocation auto-enables non-interactive mode

### Async Search Dispatch
Analytics searches now use `exec_mode=normal` (non-blocking) with `dispatchState` polling:
- Adaptive poll interval: 5s, increasing by 5s per iteration, caps at 30s
- Job cancellation on timeout to free search quota
- Replaces fixed 1s polling with blocking mode

### Analytics Period Flag
- `--analytics-period N` (e.g., `7d`, `30d`, `90d`) — skips interactive period prompt
- Default changed from `30d` to `7d` (matches Cloud script default)

### Enable Flags
- `--rbac` enables RBAC/user collection (off by default since v4.2.4)
- `--usage` enables usage analytics collection (off by default since v4.2.4)

---

## What's New in v4.2.4

### Two-Archive Anonymization (Preserves Original Data)
When anonymization is enabled, the script creates **TWO separate archives**:
- `{export_name}.tar.gz` - **Original, untouched data** (keep for your records)
- `{export_name}_masked.tar.gz` - **Anonymized copy** (safe to share with third parties)

### Performance Optimizations
- **RBAC/Users collection OFF by default** - Use `--rbac` flag to enable
- **Usage analytics OFF by default** - Use `--usage` flag to enable
- **Faster defaults**: Batch size 250 (was 100), API delay 50ms (was 250ms)
- **Savedsearches ACL fix**: Correctly filters searches by app ownership

---

## What's New in v4.2.0

### App-Centric Dashboard Structure (v2)
- **No more flat folders**: Dashboards are now saved to `{AppName}/dashboards/classic/` and `{AppName}/dashboards/studio/` instead of root-level `dashboards_classic/` and `dashboards_studio/`
- **Prevents name collisions**: Multiple apps can now have dashboards with the same name without data loss
- **Manifest Schema v4.0**: Added `archive_structure_version: "v2"` for DMA to detect and process the new structure

---

## What Was New in v4.1.0

### App-Scoped Export Mode
- **`--apps` flag**: Export specific apps only (e.g., `--apps "search,myapp,security"`)
- **`--quick` mode**: Skip global analytics for fastest possible export (**TESTING ONLY**)
- **`--scoped` mode**: Scope RBAC/usage collection to selected apps only
- **Auto-scoped**: When `--apps` is specified, collections automatically scope to those apps

> **⚠️ WARNING**: `--quick` is for **testing/validation only**. It eliminates usage analytics, user data, and RBAC information critical for migration analysis. Always use full or `--scoped` export for actual migration planning.

### Debug Mode
- **`--debug` flag**: Enable verbose logging for troubleshooting
- **Debug log file**: `export_debug.log` with detailed API/search lifecycle
- **Color-coded console output**: ERROR (red), WARN (yellow), API (cyan), SEARCH (magenta), TIMING (blue)
- **Sensitive data redaction**: Passwords and tokens automatically redacted in debug output

### Skip Collection Options
- **`--no-usage`**: Skip usage analytics collection
- **`--no-rbac`**: Skip RBAC/user collection

### Performance Improvements
- **App-filtered queries**: RBAC and usage searches now filter by selected apps
- **Reduced scope**: Quick mode can complete in minutes vs hours for large environments

---

## What's New in v4.0.1

### Container Compatibility Improvements
- **Container-friendly progress display**: Progress bars now use newlines at 5% intervals instead of carriage returns, ensuring clean output in kubectl exec, Docker exec, and other containerized environments
- **Improved output formatting**: Progress updates print cleanly without overlapping lines in non-TTY environments

---

## What's New in v4.0.0

### Enterprise-Ready Defaults
- **Zero-configuration reliability**: Defaults tuned for environments with 4000+ dashboards and 10K+ alerts
- **Extended timeouts**: `API_TIMEOUT=120s`, `MAX_TOTAL_TIME=43200s` (12 hours), search `max_wait=300s`
- **Optimized rate limiting**: `RATE_LIMIT_DELAY=0.1s` - fast but polite API calls

### Enterprise Resilience Features
- **Paginated API calls**: `splunk_api_call_paginated` with configurable `BATCH_SIZE` (default: 250)
- **Checkpoint/resume**: Automatic detection of incomplete exports with resume capability
- **SHC Captain detection**: Warning when running on Search Head Cluster Captain
- **Export timing statistics**: Detailed timing report at completion

### Enhanced Features (from v4.0.0)
- **Python-based JSON processing**: Uses Splunk's bundled Python or system Python for all JSON operations
- **Container compatibility**: Multiple hostname fallbacks for Docker/Kubernetes environments
- **Progress bars**: Visual feedback during long operations like dashboard exports
- **Scale warnings**: Alerts when exporting large environments (200+ dashboards, 500+ alerts, etc.)
- **Dashboard Studio JSON extraction**: Automatically extracts JSON definitions from CDATA blocks

### Bug Fixes
- Fixed progress bar showing >100% in Usage Intelligence section
- Improved error handling for REST API failures
- Better handling of special characters in dashboard names

---

## Table of Contents

1. [Splunk Deployment Types](#1-splunk-deployment-types)
2. [Detection & Environment Profiling](#2-detection--environment-profiling)
3. [Data Collection Categories](#3-data-collection-categories)
4. [Users, Groups & RBAC Collection](#4-users-groups--rbac-collection)
5. [Usage Analytics Collection](#5-usage-analytics-collection)
6. [Output Structure & Summary File](#6-output-structure--summary-file)
7. [Script Flow & Interactive Prompts](#7-script-flow--interactive-prompts)
8. [API Endpoints Reference](#8-api-endpoints-reference)
9. [Error Handling & Fallbacks](#9-error-handling--fallbacks)
10. [Security Considerations](#10-security-considerations)

---

## 1. Splunk Deployment Types

### 1.1 Splunk Flavors Matrix

| Flavor | Description | Has Local Data? | Has REST API? | Typical Role |
|--------|-------------|-----------------|---------------|--------------|
| **Enterprise Standalone** | Single-server deployment | Yes | Yes | Full stack |
| **Enterprise Search Head** | Search & UI tier | Limited | Yes | Search, dashboards |
| **Enterprise Indexer** | Data storage tier | Yes | Yes | Indexing, storage |
| **Search Head Cluster (SHC)** | Clustered search tier | Limited | Yes | HA search |
| **Indexer Cluster (IDX)** | Clustered indexer tier | Yes | Yes | HA storage |
| **Heavy Forwarder (HF)** | Parsing forwarder | Transit only | Yes | Data routing |
| **Universal Forwarder (UF)** | Lightweight forwarder | Transit only | Limited | Data collection |
| **Deployment Server (DS)** | Configuration manager | No | Yes | Config distribution |
| **License Master (LM)** | License management | No | Yes | Licensing |
| **Cluster Master/Manager** | Cluster coordination | No | Yes | Cluster management |
| **Splunk Cloud** | SaaS deployment | Yes (managed) | Yes | Full stack |
| **Splunk Cloud Gateway** | Hybrid connector | No | Yes | Cloud bridge |

### 1.2 Detection Signatures

```bash
# Detection logic for each flavor

# Universal Forwarder Detection
- Binary: splunkd (smaller footprint)
- Path: /opt/splunkforwarder
- No web UI (port 8000)
- File: $SPLUNK_HOME/etc/splunk-launch.conf contains SPLUNK_ROLE=universalforwarder

# Heavy Forwarder Detection
- Has parsing capability (props.conf processing)
- No local indexes (or minimal)
- File: outputs.conf routes all data externally
- Often has: TCP/UDP inputs defined

# Search Head Detection
- Has web UI (port 8000)
- distributed_search.conf with distsearch enabled
- search peers configured
- Limited or no local indexes

# Search Head Cluster Member Detection
- File: $SPLUNK_HOME/etc/system/local/server.conf contains [shclustering]
- shcluster_label defined
- Has captain/member role

# Indexer Detection
- Large local indexes (data/db directories)
- inputs.conf with TCP receiving (splunktcp://)
- File: indexes.conf with hot/warm/cold paths defined

# Indexer Cluster Peer Detection
- File: server.conf contains [clustering] with mode = slave
- master_uri configured
- replication_factor > 0

# Cluster Master/Manager Detection
- File: server.conf contains [clustering] with mode = master
- Manages multiple cluster peers

# Deployment Server Detection
- File: serverclass.conf exists
- deployment-apps/ directory with apps
- Manages forwarder configurations

# License Master Detection
- File: server.conf contains [license] section
- license_master_uri = self

# Splunk Cloud Detection
- Domain: *.splunkcloud.com
- Cloud-specific REST endpoints
- Managed infrastructure indicators
```

### 1.3 Flavor-Specific Collection Paths

| Flavor | Configuration | Dashboards | Alerts | Indexes | Usage Stats | Users/RBAC |
|--------|---------------|------------|--------|---------|-------------|------------|
| Standalone | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| Search Head | ✅ Full | ✅ Full | ✅ Full | ⚠️ Limited | ✅ Full | ✅ Full |
| SHC Member | ✅ Full | ✅ Full | ✅ Full | ⚠️ Limited | ✅ Full | ✅ Via Captain |
| Indexer | ✅ Limited | ❌ None | ❌ None | ✅ Full | ⚠️ Index only | ⚠️ Limited |
| IDX Cluster | ✅ Limited | ❌ None | ❌ None | ✅ Full | ⚠️ Index only | ⚠️ Limited |
| Heavy Forwarder | ✅ Routing | ❌ None | ❌ None | ❌ None | ⚠️ Throughput | ⚠️ Limited |
| Universal Forwarder | ✅ Inputs | ❌ None | ❌ None | ❌ None | ⚠️ Throughput | ❌ None |
| Deployment Server | ✅ Deployed | ❌ None | ❌ None | ❌ None | ❌ None | ⚠️ Limited |
| Cloud | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ✅ Full |

---

## 2. Detection & Environment Profiling

### 2.1 Environment Detection Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                     START DETECTION                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Locate SPLUNK_HOME                                  │
│   - Check $SPLUNK_HOME env variable                         │
│   - Check /opt/splunk, /opt/splunkforwarder                 │
│   - Check /Applications/Splunk (macOS)                      │
│   - Prompt user if not found                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 2: Determine Splunk Product Type                       │
│   - Check splunk-launch.conf for SPLUNK_ROLE                │
│   - Check binary size/footprint                             │
│   - Check for web.conf (UI capability)                      │
│   - Result: Enterprise, Universal Forwarder, Heavy Forwarder│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 3: Detect Deployment Architecture                      │
│   - Check server.conf [clustering] section                  │
│   - Check server.conf [shclustering] section                │
│   - Check distsearch.conf for search peers                  │
│   - Check for deployment-apps/ directory                    │
│   - Result: Standalone, Cluster, SHC, Deployment Server     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 4: Determine Node Role                                 │
│   - Search Head vs Indexer vs Forwarder                     │
│   - Master/Captain vs Member/Peer                           │
│   - License Master detection                                │
│   - Result: Specific role classification                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 5: Check Splunk Cloud Indicators                       │
│   - Check server.conf for cloud settings                    │
│   - Check for *.splunkcloud.com in configs                  │
│   - Check for cloud-specific apps                           │
│   - Result: On-prem vs Cloud vs Hybrid                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Step 6: Generate Environment Profile                        │
│   {                                                         │
│     "product": "enterprise|uf|hf",                          │
│     "architecture": "standalone|distributed|cloud",         │
│     "role": "search_head|indexer|forwarder|...",           │
│     "clustering": { "type": "none|shc|idx", ... },         │
│     "capabilities": ["search", "index", "forward", ...]    │
│   }                                                         │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Environment Profile Schema

```json
{
  "environmentProfile": {
    "detectionTimestamp": "2025-12-03T10:30:00Z",
    "hostname": "splunk-sh-01.company.com",
    "splunkHome": "/opt/splunk",

    "product": {
      "type": "enterprise",
      "version": "9.1.2",
      "build": "12345abc",
      "edition": "enterprise",
      "platform": "linux-x86_64"
    },

    "architecture": {
      "type": "distributed",
      "isCloud": false,
      "isHybrid": false
    },

    "role": {
      "primary": "search_head",
      "isClusterMember": true,
      "clusterType": "shc",
      "clusterRole": "member",
      "captainUri": "https://shc-captain:8089",
      "clusterLabel": "production_shc"
    },

    "capabilities": {
      "hasWebUI": true,
      "hasSearchCapability": true,
      "hasIndexCapability": false,
      "hasForwardingCapability": false,
      "hasDeploymentServer": false,
      "hasLicenseMaster": false
    },

    "connectedComponents": {
      "searchPeers": ["idx1:8089", "idx2:8089", "idx3:8089"],
      "deploymentServer": "ds.company.com:8089",
      "licenseMaster": "lm.company.com:8089",
      "clusterMaster": null
    },

    "recommendedCollectionPath": "search_head_full"
  }
}
```

---

## 3. Data Collection Categories

### 3.1 Configuration Files

#### Core Configuration Files (All Flavors)

| File | Purpose | Priority | Notes |
|------|---------|----------|-------|
| `server.conf` | Server identity, clustering | Critical | Reveals architecture |
| `inputs.conf` | Data inputs | Critical | All input definitions |
| `outputs.conf` | Data routing | Critical | Forwarding topology |
| `props.conf` | Field extraction, parsing | Critical | Data transformation |
| `transforms.conf` | Transformations, routing | Critical | Data processing |
| `indexes.conf` | Index definitions | Critical | Storage configuration |
| `authentication.conf` | Auth configuration | High | LDAP, SAML, etc. |
| `authorize.conf` | Role definitions | High | RBAC policies |

#### Search & UI Configuration (Search Heads Only)

| File | Purpose | Priority | Notes |
|------|---------|----------|-------|
| `savedsearches.conf` | Alerts, scheduled searches | Critical | Alert migration |
| `macros.conf` | Search macros | High | Query dependencies |
| `eventtypes.conf` | Event classification | Medium | Semantic layer |
| `tags.conf` | Tag assignments | Medium | Semantic layer |
| `workflow_actions.conf` | UI workflows | Low | UI customization |
| `commands.conf` | Custom commands | Medium | Custom SPL |
| `views.xml` | Dashboard definitions | Critical | Classic dashboards |
| `panels.xml` | Panel definitions | Medium | Reusable panels |
| `nav.xml` | Navigation menu | Low | UI customization |

#### Forwarder-Specific Configuration

| File | Purpose | Priority | Notes |
|------|---------|----------|-------|
| `deploymentclient.conf` | Deployment client config | High | DS relationship |
| `serverclass.conf` | Server classes (DS only) | High | App deployment |
| `limits.conf` | Resource limits | Medium | Performance tuning |

### 3.2 Collection Locations

```
$SPLUNK_HOME/
├── etc/
│   ├── system/
│   │   ├── default/    # Factory defaults (reference only)
│   │   └── local/      # System-level customizations ✅ COLLECT
│   │
│   ├── apps/
│   │   └── [app_name]/
│   │       ├── default/    # App defaults ✅ COLLECT
│   │       ├── local/      # App customizations ✅ COLLECT
│   │       ├── lookups/    # Lookup tables ✅ COLLECT
│   │       ├── bin/        # Custom scripts ⚠️ OPTIONAL
│   │       └── static/     # Static assets ⚠️ OPTIONAL
│   │
│   ├── users/
│   │   └── [username]/
│   │       └── [app]/
│   │           └── local/  # User-level objects ✅ COLLECT
│   │
│   ├── deployment-apps/    # (Deployment Server only)
│   │   └── [app_name]/     ✅ COLLECT
│   │
│   └── shcluster/          # (SHC members only)
│       └── apps/
│           └── [app_name]/ ✅ COLLECT
│
└── var/
    ├── lib/splunk/
    │   └── kvstore/        # KV Store data ⚠️ OPTIONAL
    │
    └── log/splunk/
        └── audit.log       # Audit trail ✅ COLLECT (usage stats)
```

---

## 4. Users, Groups & RBAC Collection

### 4.1 Authentication & Authorization Data

#### 4.1.1 User Collection

```bash
# REST API Endpoint
GET /services/authentication/users
GET /services/authentication/users/{username}

# Collect for each user:
{
  "username": "splunk_user",
  "realname": "Sample User",
  "email": "splunk_user@company.com",
  "roles": ["admin", "power_user"],
  "defaultApp": "search",
  "type": "Splunk",           # Splunk, LDAP, SAML, etc.
  "lastLoginTime": "2025-12-03T08:30:00Z",
  "createdAt": "2023-06-01T00:00:00Z",
  "capabilities": ["admin_all_objects", "edit_tcp", ...],
  "searchFilter": null
}
```

#### 4.1.2 Role Collection

```bash
# REST API Endpoint
GET /services/authorization/roles
GET /services/authorization/roles/{rolename}

# Collect for each role:
{
  "roleName": "power_user",
  "importedRoles": ["user"],
  "capabilities": [
    "accelerate_datamodel",
    "edit_modinput_*",
    "schedule_search",
    ...
  ],
  "srchIndexesAllowed": ["main", "security", "_*"],
  "srchIndexesDefault": ["main"],
  "srchFilter": null,
  "srchTimeWin": -1,
  "rtSrchJobsQuota": 6,
  "srchJobsQuota": 10,
  "srchDiskQuota": 100
}
```

#### 4.1.3 Capabilities Collection (v4.4.0)

```bash
# System capabilities inventory
GET /services/authorization/capabilities?output_mode=json
```

Lists all available Splunk capabilities. Used to verify the export user has required permissions and to document the full RBAC capability model for migration.

#### 4.1.4 Group Collection (LDAP/SAML)

All group/config endpoints handle 404 gracefully — when LDAP or SAML is not configured, the script writes `{"configured": false, "note": "..."}` instead of failing.

```bash
# LDAP groups and configuration (v4.4.0)
GET /services/admin/LDAP-groups?output_mode=json        → ldap_groups.json
GET /services/authentication/providers/LDAP?output_mode=json → ldap_config.json

# SAML groups and configuration (v4.4.0)
GET /services/admin/SAML-groups?output_mode=json         → saml_groups.json
GET /services/authentication/providers/SAML?output_mode=json → saml_config.json
```

Example LDAP group mapping:
```json
{
  "groupName": "splunk_admins",
  "mappedRoles": ["admin"],
  "memberCount": 5,
  "ldapBaseDN": "CN=splunk_admins,OU=Groups,DC=company,DC=com"
}
```

### 4.2 Object Ownership Mapping

#### 4.2.1 Dashboard Ownership

```bash
# REST API for each dashboard
GET /servicesNS/{owner}/{app}/data/ui/views/{dashboard_name}

# Extract ownership:
{
  "dashboardName": "security_overview",
  "app": "security_app",
  "owner": "splunk_user",
  "sharing": "app",              # user, app, global
  "permissions": {
    "read": ["*"],
    "write": ["admin", "power_user"]
  },
  "lastModifiedBy": "splunk_user",
  "lastModifiedTime": "2024-01-10T14:30:00Z"
}
```

#### 4.2.2 Alert Ownership

```bash
# REST API for saved searches
GET /servicesNS/{owner}/{app}/saved/searches/{search_name}

# Extract ownership:
{
  "alertName": "critical_security_alert",
  "app": "security_app",
  "owner": "security_team",
  "sharing": "app",
  "permissions": {
    "read": ["*"],
    "write": ["security_admins"]
  },
  "isScheduled": true,
  "actions": ["email", "webhook"],
  "lastRunTime": "2024-01-15T10:00:00Z",
  "lastModifiedBy": "mwilson",
  "lastModifiedTime": "2024-01-05T09:00:00Z"
}
```

#### 4.2.3 Saved Search Ownership

```bash
# Same as alerts - saved searches include:
# - Ad-hoc saved searches (isScheduled: false)
# - Reports (isScheduled: true, actions: [])
# - Alerts (isScheduled: true, actions: [...])
```

### 4.3 RBAC Summary Output

```json
{
  "rbacSummary": {
    "collectionTimestamp": "2025-12-03T10:30:00Z",

    "users": {
      "total": 150,
      "byType": {
        "Splunk": 25,
        "LDAP": 120,
        "SAML": 5
      },
      "activeInLast30Days": 87,
      "activeInLast90Days": 142
    },

    "roles": {
      "total": 15,
      "custom": 8,
      "builtin": 7,
      "list": ["admin", "power_user", "user", "security_analyst", ...]
    },

    "groups": {
      "total": 12,
      "ldapGroups": 10,
      "samlGroups": 2,
      "mappings": [
        {"group": "splunk_admins", "roles": ["admin"]},
        {"group": "security_team", "roles": ["security_analyst", "power_user"]}
      ]
    },

    "ownership": {
      "dashboards": {
        "total": 245,
        "byOwner": [
          {"owner": "splunk_user", "count": 45},
          {"owner": "security_team", "count": 32},
          ...
        ],
        "byApp": [
          {"app": "search", "count": 89},
          {"app": "security_app", "count": 56},
          ...
        ]
      },
      "alerts": {
        "total": 187,
        "byOwner": [...],
        "byApp": [...]
      },
      "savedSearches": {
        "total": 523,
        "byOwner": [...],
        "byApp": [...]
      }
    }
  }
}
```

---

## 5. Usage Analytics Collection

### 5.1 Search & Query Analytics

#### 5.1.1 Audit Log Analysis

```bash
# Primary source: $SPLUNK_HOME/var/log/splunk/audit.log
# Contains: All search activity, user logins, configuration changes

# Parse audit.log for search activity:
# - action=search
# - action=savedsearch_dispatch
# - action=alert_fired

# Extract metrics:
{
  "searchActivity": {
    "period": "last_30_days",
    "totalSearches": 45678,
    "uniqueUsers": 87,
    "searchesByType": {
      "adhoc": 32456,
      "scheduled": 12000,
      "alertTriggered": 1222
    }
  }
}
```

#### 5.1.2 Search Frequency Analysis

```bash
# REST API for scheduled search history
GET /services/search/jobs

# Internal index query (requires search capability)
index=_audit action=search
| stats count by user, savedsearch_name, search
| sort -count

# Output:
{
  "topSearches": [
    {
      "searchName": "Security - Failed Logins",
      "type": "scheduled",
      "executionCount30Days": 2880,
      "avgRuntimeSeconds": 12.5,
      "owner": "security_team",
      "app": "security_app"
    },
    ...
  ],
  "topAdhocSearchPatterns": [
    {
      "pattern": "index=main sourcetype=access_*",
      "count": 1234,
      "uniqueUsers": 15
    },
    ...
  ]
}
```

### 5.2 Dashboard Usage Analytics

#### 5.2.1 Dashboard View Metrics

```bash
# Internal index query
index=_internal sourcetype=splunk_web_access uri="*/app/*/[dashboard]*"
| stats count as views, dc(user) as unique_users by uri
| sort -views

# REST API approach (if internal indexes not accessible)
GET /services/search/jobs
# Run: | rest /servicesNS/-/-/data/ui/views | stats count by title

# Output:
{
  "dashboardUsage": {
    "period": "last_30_days",
    "totalViews": 12345,
    "uniqueViewers": 78,
    "dashboards": [
      {
        "name": "security_overview",
        "app": "security_app",
        "views": 2345,
        "uniqueViewers": 45,
        "avgSessionDuration": 180,
        "owner": "splunk_user",
        "lastViewed": "2024-01-15T09:30:00Z"
      },
      ...
    ]
  }
}
```

#### 5.2.2 Dashboard Interactivity

```bash
# Track dashboard drilldowns, filter changes
index=_internal sourcetype=splunk_web_access uri="*/app/*" method=POST
| stats count by uri_path

# Output:
{
  "dashboardInteractions": {
    "drilldowns": 5678,
    "filterChanges": 8901,
    "timeRangeChanges": 2345,
    "panelRefreshes": 12345
  }
}
```

### 5.3 Alert Usage Analytics

#### 5.3.1 Alert Trigger Metrics

```bash
# From audit.log or _audit index
index=_audit action=alert_fired
| stats count as triggers,
        values(severity) as severities,
        avg(result_count) as avg_results
  by savedsearch_name, app

# Output:
{
  "alertMetrics": {
    "period": "last_30_days",
    "totalTriggers": 4567,
    "uniqueAlerts": 87,
    "alerts": [
      {
        "name": "Critical - System Down",
        "app": "infrastructure",
        "triggers": 234,
        "suppressedCount": 45,
        "avgResultCount": 3.2,
        "severity": 5,
        "actions": ["email", "pagerduty"],
        "owner": "ops_team"
      },
      ...
    ]
  }
}
```

#### 5.3.2 Alert Action Analytics

```bash
# Track which alert actions are used
index=_internal sourcetype=scheduler action=*
| stats count by alert_actions

# Output:
{
  "alertActions": {
    "email": 12345,
    "webhook": 5678,
    "slack": 2345,
    "pagerduty": 1234,
    "script": 567,
    "summary_index": 8901
  }
}
```

### 5.4 Index Usage Analytics

#### 5.4.1 Index Volume Metrics

```bash
# REST API for index statistics
GET /services/data/indexes-extended

# Or via search
| dbinspect index=*
| stats sum(sizeOnDiskMB) as size_mb, sum(eventCount) as events by index

# Output:
{
  "indexMetrics": {
    "collectionTimestamp": "2025-12-03T10:30:00Z",
    "indexes": [
      {
        "name": "main",
        "sizeOnDiskGB": 1234.5,
        "totalEventCount": 12345678901,
        "earliestEvent": "2023-01-01T00:00:00Z",
        "latestEvent": "2024-01-15T10:30:00Z",
        "retentionDays": 365,
        "replicationFactor": 3,
        "searchFactor": 2,
        "buckets": {
          "hot": 5,
          "warm": 120,
          "cold": 890
        },
        "ingestionRate": {
          "last24h_GB": 45.6,
          "last7d_avgDaily_GB": 42.3,
          "last30d_avgDaily_GB": 40.1
        }
      },
      ...
    ],
    "totals": {
      "totalIndexes": 45,
      "totalSizeGB": 12345.6,
      "totalEvents": 987654321012,
      "dailyIngestionGB": 456.7
    }
  }
}
```

#### 5.4.2 Index Access Patterns

```bash
# From audit log - which indexes are searched most
index=_audit action=search
| rex field=search "index=(?<searched_index>\w+)"
| stats count by searched_index
| sort -count

# Output:
{
  "indexAccessPatterns": {
    "period": "last_30_days",
    "bySearchCount": [
      {"index": "main", "searchCount": 45678},
      {"index": "security", "searchCount": 34567},
      {"index": "_internal", "searchCount": 12345},
      ...
    ]
  }
}
```

### 5.5 Sourcetype Analytics

```bash
# Sourcetype volume and usage
| tstats count where index=* by index, sourcetype
| stats sum(count) as events by sourcetype

# Output:
{
  "sourcetypeMetrics": {
    "sourcetypes": [
      {
        "name": "access_combined",
        "eventCount": 12345678,
        "indexes": ["main", "web"],
        "searchFrequency": 1234,
        "usedInDashboards": 12,
        "usedInAlerts": 5
      },
      ...
    ]
  }
}
```

### 5.6 User Activity Analytics

```bash
# User login and activity patterns
index=_audit action=login OR action=search
| stats count as actions,
        min(_time) as first_activity,
        max(_time) as last_activity,
        dc(action) as action_types
  by user
| sort -actions

# Output:
{
  "userActivity": {
    "period": "last_30_days",
    "users": [
      {
        "username": "splunk_user",
        "totalActions": 12345,
        "searchCount": 5678,
        "loginCount": 45,
        "lastActivity": "2024-01-15T10:25:00Z",
        "primaryApp": "security_app",
        "roles": ["admin", "power_user"]
      },
      ...
    ],
    "summary": {
      "totalLogins": 4567,
      "uniqueActiveUsers": 87,
      "avgSearchesPerUser": 156,
      "peakHour": 14
    }
  }
}
```

---

## 6. Output Structure & Summary File

### 6.1 Export Directory Structure

```
splunk_export_[env_name]_[timestamp]/
│
├── manifest.json                       # 📋 STANDARDIZED METADATA (v3.5.0)
├── dma-env-summary.md           # 📊 MASTER SUMMARY FILE
├── _metadata.json                      # Export metadata
├── _environment_profile.json           # Detected environment profile
│
├── _systeminfo/                        # System infrastructure
│   ├── server_info.json
│   ├── installed_apps.json
│   ├── search_peers.json
│   ├── license_info.json
│   ├── cluster_info.json
│   └── deployment_info.json
│
├── _rbac/                              # Users, Groups, Roles
│   ├── users.json                      # All users
│   ├── roles.json                      # All roles with capabilities
│   ├── capabilities.json               # System capabilities inventory (v4.4.0)
│   ├── saml_groups.json                # SAML group mappings (v4.4.0)
│   ├── saml_config.json                # SAML configuration (v4.4.0)
│   ├── ldap_groups.json                # LDAP group mappings (v4.4.0)
│   ├── ldap_config.json                # LDAP configuration (v4.4.0)
│   ├── current_context.json            # Current user context
│   ├── authentication.conf             # Auth configuration
│   ├── authorize.conf                  # Authorization config
│   └── ownership_map.json              # Object → Owner mapping
│
├── _usage_analytics/                   # Usage statistics
│   ├── search_activity.json            # Search frequency, patterns
│   ├── dashboard_usage.json            # Dashboard views, interactions
│   ├── alert_metrics.json              # Alert triggers, actions
│   ├── index_usage.json                # Index access patterns
│   ├── sourcetype_usage.json           # Sourcetype popularity
│   ├── user_activity.json              # User engagement
│   ├── dashboard_ownership.json        # Dashboard → owner mapping (v3.5.0)
│   ├── alert_ownership.json            # Alert → owner mapping (v3.5.0)
│   ├── ownership_summary.json          # Ownership by user (v3.5.0)
│   ├── top_indexes_by_volume.json      # Volume analysis (v3.5.0)
│   ├── top_sourcetypes_by_volume.json  # Sourcetype volume (v3.5.0)
│   ├── top_hosts_by_volume.json        # Host volume data (v3.5.0)
│   ├── zero_view_dashboards.json       # Elimination candidates (v3.5.0)
│   ├── never_fired_alerts.json         # Elimination candidates (v3.5.0)
│   └── migration_priority_scores.json  # Computed priority rankings
│
├── _indexes/                           # Index configurations
│   ├── indexes.conf                    # Index definitions
│   ├── indexes_detailed.json           # Full index metadata
│   └── index_volumes.json              # Size and volume data
│
├── _system/                            # System-level configs
│   └── local/
│       ├── inputs.conf
│       ├── outputs.conf
│       ├── server.conf
│       └── web.conf
│
├── [app_name]/                         # Per-app exports (v2 app-centric structure)
│   ├── dashboards/                     # v2: App-scoped dashboards (v4.2.0+)
│   │   ├── classic/                    # Classic XML dashboards for this app
│   │   │   └── *.xml
│   │   └── studio/                     # Dashboard Studio JSON for this app
│   │       └── *.json
│   ├── default/
│   │   ├── props.conf
│   │   ├── transforms.conf
│   │   ├── savedsearches.conf
│   │   ├── macros.conf
│   │   ├── eventtypes.conf
│   │   ├── tags.conf
│   │   └── data/
│   │       └── ui/
│   │           ├── views/              # Legacy location (v1 archives only)
│   │           ├── panels/             # Prebuilt panels
│   │           └── nav/                # Navigation
│   ├── local/
│   │   └── [same structure as default]
│   └── lookups/
│       └── *.csv
│
└── _audit_sample/                      # Sample audit data (optional)
    └── audit_sample.log                # Last 10000 audit entries
```

### 6.2 manifest.json Schema (v4.2.0)

The script generates a standardized `manifest.json` with guaranteed schema for DMA:

```json
{
  "schemaVersion": "4.0",
  "exportType": "splunk_enterprise",
  "exportTimestamp": "2025-12-03T10:30:00Z",
  "scriptVersion": "4.4.0",
  "archive_structure": {
    "version": "v2",
    "dashboard_organization": "app_scoped"
  },

  "environment": {
    "hostname": "splunk-sh-01.company.com",
    "splunkHome": "/opt/splunk",
    "splunkVersion": "9.1.2",
    "splunkFlavor": "enterprise",
    "architecture": "distributed",
    "role": "search_head"
  },

  "collection": {
    "apps": 45,
    "dashboards": 245,
    "alerts": 187,
    "users": 150,
    "indexes": 32,
    "errors": 0,
    "warnings": 5
  },

  "usageIntelligence": {
    "analysisPeriod": "7d",
    "totalSearches": 45678,
    "totalDashboardViews": 12345,
    "totalAlertTriggers": 4567,
    "topIndexesByVolume": [...],
    "topSourcetypesByVolume": [...],
    "topHostsByVolume": [...],
    "elimination_candidates": {
      "zeroDashboards": 12,
      "neverFiredAlerts": 23
    }
  },

  "exportDuration": {
    "startTime": "2025-12-03T10:25:00Z",
    "endTime": "2025-12-03T10:32:45Z",
    "durationSeconds": 465
  }
}
```

### 6.3 Master Summary File: dma-env-summary.md

```markdown
# DynaSplunk Environment Summary

**Export Date**: 2025-12-03T10:30:00Z
**Splunk Version**: 9.1.2
**Environment ID**: PROD-SH-CLUSTER-01
**Export Tool Version**: 4.1.0

---

## 🏗️ Environment Overview

### Deployment Architecture

| Attribute | Value |
|-----------|-------|
| **Deployment Type** | Distributed (Search Head Cluster + Indexer Cluster) |
| **Product Edition** | Splunk Enterprise |
| **Role** | Search Head (SHC Member) |
| **Cluster Label** | production_shc |
| **Search Peers** | 6 indexers |
| **Total Indexed Data** | 45.6 TB |
| **Daily Ingestion Rate** | 456 GB/day |
| **License Type** | Enterprise Term License |
| **License Daily Quota** | 500 GB |

### Connected Components

| Component | Endpoint | Status |
|-----------|----------|--------|
| SHC Captain | shc-captain.company.com:8089 | Active |
| Indexer Cluster Master | cm.company.com:8089 | Active |
| License Master | lm.company.com:8089 | Active |
| Deployment Server | ds.company.com:8089 | Active |

---

## 👥 Users & Access Summary

### User Statistics

| Metric | Value |
|--------|-------|
| **Total Users** | 150 |
| **Active (30 days)** | 87 (58%) |
| **Active (90 days)** | 142 (95%) |
| **LDAP Users** | 120 (80%) |
| **Local Users** | 25 (17%) |
| **SAML Users** | 5 (3%) |

### Role Distribution

| Role | Users | Capabilities |
|------|-------|--------------|
| admin | 5 | Full admin access |
| power_user | 23 | Schedule searches, create alerts |
| security_analyst | 15 | Security app access |
| user | 107 | Basic search access |

### Top Asset Owners

| Owner | Dashboards | Alerts | Saved Searches |
|-------|------------|--------|----------------|
| security_team | 32 | 45 | 89 |
| splunk_user | 28 | 12 | 34 |
| ops_team | 24 | 38 | 67 |
| network_admin | 18 | 22 | 45 |
| mwilson | 15 | 8 | 23 |

---

## 📊 Usage Analytics (Last 30 Days)

### Search Activity

| Metric | Value |
|--------|-------|
| **Total Searches** | 45,678 |
| **Unique Users** | 87 |
| **Scheduled Searches** | 12,000 (26%) |
| **Ad-hoc Searches** | 32,456 (71%) |
| **Alert-Triggered** | 1,222 (3%) |
| **Avg Search Runtime** | 8.5 seconds |
| **Peak Hour** | 2:00 PM (14:00) |

### Top 10 Most Executed Searches

| Rank | Search Name | Type | Executions | Avg Runtime | Owner |
|------|-------------|------|------------|-------------|-------|
| 1 | Security - Failed Logins | Scheduled | 2,880 | 12.5s | security_team |
| 2 | Infrastructure Health Check | Scheduled | 2,880 | 8.2s | ops_team |
| 3 | Application Error Monitor | Scheduled | 2,016 | 15.3s | dev_team |
| 4 | Network Traffic Analysis | Scheduled | 1,440 | 45.2s | network_admin |
| 5 | User Activity Report | Scheduled | 720 | 23.1s | compliance |
| ... | ... | ... | ... | ... | ... |

### Dashboard Usage

| Metric | Value |
|--------|-------|
| **Total Dashboard Views** | 12,345 |
| **Unique Viewers** | 78 |
| **Avg Session Duration** | 3.5 minutes |
| **Most Popular Hour** | 10:00 AM |

### Top 10 Most Viewed Dashboards

| Rank | Dashboard | App | Views | Unique Users | Owner |
|------|-----------|-----|-------|--------------|-------|
| 1 | Security Overview | security_app | 2,345 | 45 | security_team |
| 2 | Infrastructure Status | ops_app | 1,890 | 38 | ops_team |
| 3 | Application Performance | apm_app | 1,567 | 32 | dev_team |
| 4 | Network Dashboard | network_app | 1,234 | 28 | network_admin |
| 5 | Compliance Report | compliance | 987 | 15 | compliance |
| ... | ... | ... | ... | ... | ... |

### Alert Statistics

| Metric | Value |
|--------|-------|
| **Total Alert Triggers** | 4,567 |
| **Unique Alerts Fired** | 87 |
| **Suppressed Alerts** | 1,234 |
| **Avg Results per Trigger** | 3.2 |

### Top 10 Most Triggered Alerts

| Rank | Alert Name | Triggers | Severity | Actions | Owner |
|------|------------|----------|----------|---------|-------|
| 1 | Failed Login Threshold | 456 | High | email, pagerduty | security_team |
| 2 | Disk Space Warning | 345 | Medium | email | ops_team |
| 3 | Application Error Spike | 234 | High | slack, pagerduty | dev_team |
| 4 | Network Latency Alert | 189 | Medium | email | network_admin |
| 5 | Unauthorized Access | 156 | Critical | email, pagerduty, script | security_team |
| ... | ... | ... | ... | ... | ... |

---

## 💾 Index Statistics

### Index Summary

| Metric | Value |
|--------|-------|
| **Total Indexes** | 45 |
| **Total Size** | 45.6 TB |
| **Total Events** | 987.6 billion |
| **Daily Ingestion** | 456 GB |

### Top 10 Indexes by Size

| Rank | Index | Size (TB) | Events | Retention | Search Freq |
|------|-------|-----------|--------|-----------|-------------|
| 1 | main | 12.3 | 234.5B | 365 days | 45,678 |
| 2 | security | 8.9 | 178.2B | 365 days | 34,567 |
| 3 | network | 7.2 | 145.8B | 180 days | 23,456 |
| 4 | application | 5.6 | 112.3B | 90 days | 12,345 |
| 5 | infrastructure | 4.3 | 89.4B | 90 days | 8,901 |
| ... | ... | ... | ... | ... | ... |

### Top 10 Sourcetypes by Volume

| Rank | Sourcetype | Events | Indexes | Search Freq | Dashboards | Alerts |
|------|------------|--------|---------|-------------|------------|--------|
| 1 | access_combined | 89.5B | main, web | 12,345 | 23 | 12 |
| 2 | syslog | 78.3B | main, security | 23,456 | 18 | 8 |
| 3 | WinEventLog:Security | 56.7B | security | 34,567 | 32 | 24 |
| 4 | cisco:asa | 45.6B | network | 8,901 | 15 | 6 |
| 5 | linux_secure | 34.5B | security | 5,678 | 8 | 4 |
| ... | ... | ... | ... | ... | ... | ... |

---

## 🎯 Migration Priority Scoring

### Priority Calculation Methodology

Assets are scored on a scale of 0-100 based on:
- **Usage Frequency** (40%): How often the asset is used
- **User Reach** (25%): How many users interact with it
- **Business Criticality** (20%): Severity, ownership, app context
- **Data Volume** (15%): Size and ingestion rate

### High Priority Assets (Score > 75)

#### Dashboards to Migrate First

| Priority | Dashboard | Score | Views/30d | Users | Owner | Notes |
|----------|-----------|-------|-----------|-------|-------|-------|
| 1 | Security Overview | 95 | 2,345 | 45 | security_team | Critical security visibility |
| 2 | Infrastructure Status | 92 | 1,890 | 38 | ops_team | Operations essential |
| 3 | Compliance Report | 88 | 987 | 15 | compliance | Regulatory requirement |
| 4 | Application Performance | 85 | 1,567 | 32 | dev_team | High user engagement |
| 5 | Executive Summary | 82 | 567 | 12 | leadership | C-level visibility |

#### Alerts to Migrate First

| Priority | Alert | Score | Triggers/30d | Severity | Owner | Notes |
|----------|-------|-------|--------------|----------|-------|-------|
| 1 | Unauthorized Access | 98 | 156 | Critical | security_team | Security-critical |
| 2 | System Down | 96 | 34 | Critical | ops_team | Availability |
| 3 | Failed Login Threshold | 94 | 456 | High | security_team | Security |
| 4 | Data Exfiltration | 92 | 23 | Critical | security_team | DLP |
| 5 | Application Error Spike | 88 | 234 | High | dev_team | App health |

#### Indexes to Migrate First

| Priority | Index | Score | Size | Search Freq | Sourcetypes | Notes |
|----------|-------|-------|------|-------------|-------------|-------|
| 1 | security | 97 | 8.9 TB | 34,567 | 15 | Security operations |
| 2 | main | 95 | 12.3 TB | 45,678 | 45 | Primary data store |
| 3 | infrastructure | 89 | 4.3 TB | 8,901 | 12 | Ops monitoring |
| 4 | application | 85 | 5.6 TB | 12,345 | 23 | App logs |
| 5 | compliance | 82 | 2.1 TB | 3,456 | 8 | Audit requirements |

### Medium Priority Assets (Score 50-75)

| Asset Type | Count | Top Examples |
|------------|-------|--------------|
| Dashboards | 45 | Network Overview, DB Performance, API Metrics |
| Alerts | 32 | Warning thresholds, capacity alerts |
| Saved Searches | 89 | Reporting queries, analysis searches |
| Indexes | 12 | Development, testing, archive |

### Low Priority Assets (Score < 50)

| Asset Type | Count | Recommendation |
|------------|-------|----------------|
| Dashboards | 78 | Review for archival |
| Alerts | 45 | Consolidate or retire |
| Saved Searches | 234 | Evaluate necessity |
| Indexes | 18 | Consider retention policy |

---

## 📦 App Inventory

### Installed Apps Summary

| App | Version | Dashboards | Alerts | Owner | Migration Priority |
|-----|---------|------------|--------|-------|-------------------|
| security_app | 4.2.1 | 32 | 45 | security_team | High |
| ops_app | 2.1.0 | 24 | 38 | ops_team | High |
| network_app | 3.0.2 | 15 | 22 | network_admin | Medium |
| compliance | 1.5.0 | 8 | 12 | compliance | High |
| dev_tools | 2.0.0 | 12 | 8 | dev_team | Medium |
| ... | ... | ... | ... | ... | ... |

---

## 🔄 Data Flow Summary

### Input Types

| Input Type | Count | Volume/Day |
|------------|-------|------------|
| File monitoring | 234 | 45 GB |
| TCP/UDP receivers | 56 | 123 GB |
| HTTP Event Collector | 89 | 78 GB |
| Scripted inputs | 34 | 12 GB |
| Modular inputs | 45 | 89 GB |
| Database inputs | 12 | 34 GB |
| Cloud inputs | 23 | 56 GB |

### Output Destinations

| Destination | Type | Volume/Day |
|-------------|------|------------|
| Local indexers | Indexer cluster | 456 GB |
| AWS S3 (archive) | Smartstore | 234 GB |
| Summary index | Internal | 12 GB |

---

## ⚠️ Migration Considerations

### Potential Challenges

1. **Custom Commands**: 12 custom SPL commands detected - require manual conversion
2. **Lookup Tables**: 45 CSV lookups (234 MB total) - need data migration strategy
3. **Complex Alerts**: 23 alerts with multi-step actions - review automation needs
4. **Heavy Macros**: 15 macros with nested dependencies - test thoroughly
5. **Custom Visualizations**: 8 custom viz used in dashboards - need alternatives

### Data Gaps

| Category | Issue | Impact | Recommendation |
|----------|-------|--------|----------------|
| Orphaned Dashboards | 12 dashboards with no owner | Medium | Assign ownership |
| Unused Alerts | 23 alerts never triggered | Low | Consider removal |
| Empty Indexes | 5 indexes with no data | Low | Remove or repurpose |
| Duplicate Searches | 34 similar saved searches | Medium | Consolidate |

### Recommended Migration Order

1. **Phase 1 (Critical)**: Security dashboards, critical alerts, main indexes
2. **Phase 2 (High)**: Operations dashboards, infrastructure monitoring
3. **Phase 3 (Medium)**: Application monitoring, development tools
4. **Phase 4 (Low)**: Archive data, deprecated assets

---

## 📋 Export Manifest

### Files Included

| Category | Count | Size |
|----------|-------|------|
| Configuration files | 234 | 12 MB |
| Dashboard definitions | 245 | 45 MB |
| Alert configurations | 187 | 8 MB |
| Lookup tables | 45 | 234 MB |
| Audit samples | 1 | 50 MB |
| System info | 12 | 5 MB |
| RBAC data | 6 | 2 MB |
| Usage analytics | 8 | 15 MB |

**Total Export Size**: 371 MB

---

*Generated by DMA Splunk Export Tool v4.0.0*
```

---

## 7. Script Flow & Interactive Prompts

### 7.0 Verbosity & User Guidance Philosophy

**CRITICAL REQUIREMENT**: Every prompt in this script MUST include:

1. **Context Explanation**: Why we're asking this question
2. **Impact Statement**: What happens with each choice
3. **Recommendation**: What we suggest for most users
4. **Data Justification**: What data will be collected and why it matters for migration

The script should feel like a guided conversation with an expert, not a terse command-line interrogation.

### 7.1 Complete Script Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SCRIPT START                                 │
│                                                                      │
│  Display banner and version information                              │
│  Check prerequisites (bash version, curl, permissions)               │
│  Display pre-flight checklist and requirements                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: ENVIRONMENT DETECTION                                       │
│                                                                      │
│ 1.1 Detect SPLUNK_HOME                                              │
│     - Auto-detect: /opt/splunk, /opt/splunkforwarder, etc.          │
│     - Prompt if not found                                           │
│                                                                      │
│ 1.2 Detect Splunk Flavor                                            │
│     → Universal Forwarder detected! Limited export available.       │
│     → Enterprise detected! Full export available.                   │
│                                                                      │
│ 1.3 Detect Architecture (standalone/distributed/cloud)              │
│                                                                      │
│ 1.4 Display Environment Profile                                     │
│     ┌────────────────────────────────────────────────────┐          │
│     │ Detected Environment:                               │          │
│     │   Product: Splunk Enterprise 9.1.2                 │          │
│     │   Role: Search Head (SHC Member)                   │          │
│     │   Architecture: Distributed                         │          │
│     │   Cluster: production_shc                          │          │
│     │   Search Peers: 6 indexers                         │          │
│     └────────────────────────────────────────────────────┘          │
│                                                                      │
│ [PROMPT] Is this correct? (Y/n)                                     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 2: APPLICATION SELECTION                                       │
│                                                                      │
│ ╔════════════════════════════════════════════════════════════════╗  │
│ ║  APPLICATION SELECTION                                          ║  │
│ ╠════════════════════════════════════════════════════════════════╣  │
│ ║                                                                 ║  │
│ ║  WHY WE ASK:                                                    ║  │
│ ║  Splunk organizes content into "Apps" - containers that hold    ║  │
│ ║  dashboards, alerts, saved searches, and configurations.        ║  │
│ ║  We need to know which apps contain the content you want to     ║  │
│ ║  migrate to Dynatrace.                                          ║  │
│ ║                                                                 ║  │
│ ║  WHAT WE COLLECT FROM EACH APP:                                 ║  │
│ ║  • Dashboards (Classic XML and Dashboard Studio JSON)           ║  │
│ ║  • Alerts and Scheduled Searches (savedsearches.conf)           ║  │
│ ║  • Field Extractions (props.conf, transforms.conf)              ║  │
│ ║  • Lookup Tables (.csv files)                                   ║  │
│ ║  • Search Macros (macros.conf)                                  ║  │
│ ║  • Event Classifications (eventtypes.conf, tags.conf)           ║  │
│ ║                                                                 ║  │
│ ║  RECOMMENDATION:                                                ║  │
│ ║  For a complete migration assessment, we recommend exporting    ║  │
│ ║  ALL apps. This gives DMA the full picture of your              ║  │
│ ║  Splunk environment and enables accurate migration planning.    ║  │
│ ║                                                                 ║  │
│ ╚════════════════════════════════════════════════════════════════╝  │
│                                                                      │
│ Discovered Applications (45 total):                                  │
│ ┌────────────────────────────────────────────────────────────────┐  │
│ │  #  │ App Name          │ Dashboards │ Alerts │ Size    │      │  │
│ │ ────┼───────────────────┼────────────┼────────┼─────────┤      │  │
│ │  1  │ search            │ 12         │ 0      │ 2.3 MB  │      │  │
│ │  2  │ security_app      │ 32         │ 45     │ 15.6 MB │      │  │
│ │  3  │ ops_monitoring    │ 24         │ 38     │ 8.9 MB  │      │  │
│ │  4  │ network_app       │ 15         │ 22     │ 5.2 MB  │      │  │
│ │  5  │ compliance        │ 8          │ 12     │ 3.1 MB  │      │  │
│ │ ... │ (40 more apps)    │            │        │         │      │  │
│ └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│ [PROMPT] How would you like to select applications?                  │
│                                                                      │
│   1. Export ALL applications (Recommended for full migration)        │
│      → Includes all 45 apps with their complete configurations       │
│      → Best for comprehensive migration assessment                   │
│      → Estimated export size: ~150 MB                                │
│                                                                      │
│   2. Enter specific app names (comma-separated)                      │
│      → Example: security_app, ops_monitoring, compliance             │
│      → Use this if you know exactly which apps to migrate            │
│      → Faster export, smaller file size                              │
│                                                                      │
│   3. Select from numbered list                                       │
│      → Enter numbers like: 1,2,5,7-10                                │
│      → Interactive selection for browsing apps                       │
│                                                                      │
│   4. Export system configurations only (no apps)                     │
│      → Only collects indexes, inputs, system-level configs           │
│      → Use for infrastructure-only assessment                        │
│                                                                      │
│ Enter choice [1]:                                                    │
│                                                                      │
│ ── If option 2 selected ──────────────────────────────────────────  │
│                                                                      │
│ Enter app names (comma-separated):                                   │
│ > security_app, ops_monitoring, compliance                           │
│                                                                      │
│ Validating app names...                                              │
│ ✓ security_app - Found (32 dashboards, 45 alerts)                   │
│ ✓ ops_monitoring - Found (24 dashboards, 38 alerts)                 │
│ ✓ compliance - Found (8 dashboards, 12 alerts)                      │
│                                                                      │
│ Total: 3 apps selected (64 dashboards, 95 alerts)                   │
│                                                                      │
│ [PROMPT] Proceed with these 3 apps? (Y/n)                           │
│                                                                      │
│ ── If option 3 selected ──────────────────────────────────────────  │
│                                                                      │
│ Enter app numbers (e.g., 1,2,5 or 1-5,8,10):                        │
│ > 2,3,5                                                              │
│                                                                      │
│ Selected apps:                                                       │
│ ✓ security_app (32 dashboards, 45 alerts)                           │
│ ✓ ops_monitoring (24 dashboards, 38 alerts)                         │
│ ✓ compliance (8 dashboards, 12 alerts)                              │
│                                                                      │
│ [PROMPT] Proceed with these 3 apps? (Y/n)                           │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: DATA CATEGORY SELECTION                                     │
│                                                                      │
│ ╔════════════════════════════════════════════════════════════════╗  │
│ ║  DATA CATEGORIES TO COLLECT                                     ║  │
│ ╠════════════════════════════════════════════════════════════════╣  │
│ ║                                                                 ║  │
│ ║  WHY WE ASK:                                                    ║  │
│ ║  Different migration scenarios require different data. For     ║  │
│ ║  example, if you only want to migrate dashboards, you might    ║  │
│ ║  skip collecting user activity data. However, for a complete   ║  │
│ ║  migration assessment, we recommend collecting everything.     ║  │
│ ║                                                                 ║  │
│ ╚════════════════════════════════════════════════════════════════╝  │
│                                                                      │
│ Select data categories to collect:                                   │
│                                                                      │
│ [✓] 1. Configuration Files (props, transforms, indexes, inputs)     │
│        → Required for understanding data pipeline                    │
│        → Maps how Splunk processes and stores data                   │
│                                                                      │
│ [✓] 2. Dashboards (Classic XML + Dashboard Studio JSON)             │
│        → Visual content for conversion to Dynatrace apps            │
│        → Includes all panels, queries, and layouts                   │
│                                                                      │
│ [✓] 3. Alerts & Saved Searches (savedsearches.conf)                 │
│        → Critical for operational continuity                         │
│        → Includes schedules, triggers, and actions                   │
│                                                                      │
│ [✓] 4. Users, Roles & Groups (RBAC data)                            │
│        → Essential for ownership mapping                             │
│        → Identifies who owns which dashboards/alerts                 │
│        → Helps prioritize migration by team                          │
│                                                                      │
│ [✓] 5. Usage Analytics (search frequency, dashboard views)          │
│        → Identifies high-value assets worth migrating                │
│        → Shows which content is actively used                        │
│        → Enables data-driven migration prioritization                │
│                                                                      │
│ [✓] 6. Index & Data Statistics                                       │
│        → Volume metrics for capacity planning                        │
│        → Retention settings for Dynatrace bucket config              │
│        → Sourcetype mapping for OpenPipeline                         │
│                                                                      │
│ [ ] 7. Lookup Tables (.csv files)                                    │
│        → Reference data used in searches                             │
│        → May contain sensitive data - review before including        │
│                                                                      │
│ [ ] 8. Audit Log Sample (last 10,000 entries)                        │
│        → Detailed search patterns for analysis                       │
│        → May contain sensitive query content                         │
│                                                                      │
│ Enter categories to toggle (e.g., 7,8 to add) or press Enter:       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: AUTHENTICATION                                              │
│                                                                      │
│ [PROMPT] Enter Splunk admin credentials for REST API access:        │
│   Username [admin]:                                                  │
│   Password: ********                                                 │
│                                                                      │
│ Testing authentication...                                            │
│ ✓ Authentication successful                                         │
│                                                                      │
│ Checking capabilities...                                             │
│ ✓ admin_all_objects: YES                                            │
│ ✓ list_users: YES                                                   │
│ ✓ list_roles: YES                                                   │
│ ⚠ audit_read: NO (usage analytics will be limited)                  │
│                                                                      │
│ [PROMPT] Continue with limited capabilities? (Y/n)                  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 4: USAGE ANALYTICS OPTIONS                                     │
│                                                                      │
│ [PROMPT] Usage analytics collection period:                         │
│   1. Last 7 days                                                    │
│   2. Last 30 days (Recommended)                                     │
│   3. Last 90 days                                                   │
│   4. Last 365 days                                                  │
│   5. Skip usage analytics                                           │
│                                                                      │
│ [PROMPT] Collect audit log sample? (y/N)                            │
│   This helps identify search patterns but may contain sensitive data│
│   Max sample size: 10,000 entries                                   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 5: DATA COLLECTION                                             │
│                                                                      │
│ Progress display with stages:                                        │
│                                                                      │
│ [1/10] Collecting system information...                    ✓        │
│ [2/10] Collecting installed apps...                        ✓        │
│ [3/10] Collecting configuration files...                   ⏳ 45%   │
│        └─ security_app/default/props.conf                           │
│        └─ security_app/local/savedsearches.conf                     │
│ [4/10] Collecting dashboards (Classic XML)...              ○        │
│ [5/10] Collecting dashboards (Dashboard Studio)...         ○        │
│ [6/10] Collecting users and roles...                       ○        │
│ [7/10] Collecting LDAP/SAML groups...                      ○        │
│ [8/10] Collecting usage analytics...                       ○        │
│ [9/10] Collecting index statistics...                      ○        │
│ [10/10] Generating summary report...                        ○        │
│                                                                      │
│ Current: props.conf (45 stanzas)                                    │
│ Elapsed: 00:02:34 | Estimated remaining: 00:05:12                   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 6: SUMMARY GENERATION                                          │
│                                                                      │
│ Calculating migration priority scores...                             │
│ Generating dma-env-summary.md...                             │
│                                                                      │
│ Summary Preview:                                                     │
│ ┌────────────────────────────────────────────────────────┐          │
│ │ Environment: PROD-SH-CLUSTER-01                        │          │
│ │ Total Dashboards: 245 (High priority: 23)              │          │
│ │ Total Alerts: 187 (High priority: 15)                  │          │
│ │ Total Users: 150 (Active: 87)                          │          │
│ │ Total Data: 45.6 TB across 45 indexes                  │          │
│ │                                                        │          │
│ │ Migration Complexity Score: 72/100 (Medium-High)       │          │
│ └────────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 7: ARCHIVE CREATION                                            │
│                                                                      │
│ Creating compressed archive...                                       │
│ ✓ Archive created: /tmp/splunk_export_PROD_20240115_103000.tar.gz  │
│ ✓ Size: 371 MB                                                      │
│ ✓ Files: 567                                                        │
│                                                                      │
│ SHA256: a1b2c3d4e5f6...                                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 8: COMPLETION                                                   │
│                                                                      │
│ ╔════════════════════════════════════════════════════════════════╗  │
│ ║                    EXPORT COMPLETE!                             ║  │
│ ╚════════════════════════════════════════════════════════════════╝  │
│                                                                      │
│ Export file: /tmp/splunk_export_PROD_20240115_103000.tar.gz         │
│ Size: 371 MB                                                        │
│ Duration: 00:07:45                                                  │
│                                                                      │
│ NEXT STEPS:                                                         │
│ 1. Download the export file                                         │
│ 2. Open DMA in Dynatrace                                            │
│ 3. Upload the .tar.gz file                                          │
│                                                                      │
│ The dma-env-summary.md file contains:                        │
│ • Environment overview                                              │
│ • User and access summary                                           │
│ • Usage analytics for last 30 days                                  │
│ • Migration priority rankings                                       │
│ • Recommended migration phases                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 Flavor-Specific Prompts

#### Universal Forwarder Detected

```
┌─────────────────────────────────────────────────────────────────────┐
│ ⚠️  UNIVERSAL FORWARDER DETECTED                                    │
│                                                                      │
│ This is a Universal Forwarder installation.                          │
│ Universal Forwarders have limited data available for export:        │
│                                                                      │
│ Available:                                                           │
│   ✓ inputs.conf (data sources)                                      │
│   ✓ outputs.conf (forwarding config)                                │
│   ✓ props.conf (if any local parsing)                               │
│   ✓ deploymentclient.conf (if managed by DS)                        │
│                                                                      │
│ NOT Available:                                                       │
│   ✗ Dashboards (no search capability)                               │
│   ✗ Alerts (no search capability)                                   │
│   ✗ Users/RBAC (minimal)                                            │
│   ✗ Usage analytics (no searches)                                   │
│                                                                      │
│ For full export, run this script on:                                │
│   • Search Head                                                     │
│   • Deployment Server (for deployed configs)                        │
│                                                                      │
│ [PROMPT] Continue with forwarder export? (Y/n)                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Search Head Cluster Detected

```
┌─────────────────────────────────────────────────────────────────────┐
│ 🔷 SEARCH HEAD CLUSTER MEMBER DETECTED                              │
│                                                                      │
│ This node is part of a Search Head Cluster.                         │
│                                                                      │
│ Cluster Details:                                                    │
│   Cluster Label: production_shc                                     │
│   This Node: shc-member-02.company.com                              │
│   Captain: shc-captain.company.com                                  │
│   Members: 3                                                        │
│                                                                      │
│ For SHC environments, we recommend:                                  │
│   • Run export from the CAPTAIN for most complete data              │
│   • Use REST API (not file-based) for shared knowledge objects     │
│                                                                      │
│ [PROMPT] Collection options:                                        │
│   1. Export from this member (may have incomplete shared objects)   │
│   2. Connect to Captain and export from there (Recommended)         │
│   3. Exit and run script on Captain node                            │
│                                                                      │
│ Select option [2]:                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

#### Splunk Cloud Detected

```
┌─────────────────────────────────────────────────────────────────────┐
│ ☁️  SPLUNK CLOUD ENVIRONMENT DETECTED                               │
│                                                                      │
│ This appears to be a Splunk Cloud deployment.                       │
│                                                                      │
│ Cloud Stack: production.splunkcloud.com                             │
│ Region: us-west-2                                                   │
│                                                                      │
│ For Splunk Cloud exports:                                           │
│   • File system access is limited                                   │
│   • All collection will use REST API                                │
│   • Some internal indexes may not be accessible                     │
│                                                                      │
│ Required: Splunk Cloud admin credentials                            │
│                                                                      │
│ [PROMPT] Enter Splunk Cloud admin username:                         │
│ [PROMPT] Enter Splunk Cloud admin password:                         │
│                                                                      │
│ Testing connection to production.splunkcloud.com:8089...            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 8. API Endpoints Reference

### 8.1 Core REST API Endpoints

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| **Server Info** | `/services/server/info` | GET | Version, OS, platform |
| **Server Settings** | `/services/server/settings` | GET | Server configuration |
| **Apps** | `/services/apps/local` | GET | Installed apps list |
| **Indexes** | `/services/data/indexes` | GET | Index list and metadata |
| **Indexes Extended** | `/services/data/indexes-extended` | GET | Detailed index stats |
| **Inputs** | `/services/data/inputs/all` | GET | All data inputs |

### 8.2 User & RBAC Endpoints

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| **Users** | `/services/authentication/users` | GET | All users |
| **Roles** | `/services/authorization/roles` | GET | All roles |
| **Capabilities** | `/services/authorization/capabilities` | GET | All capabilities |
| **Current User** | `/services/authentication/current-context` | GET | Current auth context |
| **LDAP** | `/services/authentication/providers/LDAP` | GET | LDAP config |
| **SAML** | `/services/authentication/providers/SAML` | GET | SAML config |

### 8.3 Knowledge Objects Endpoints

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| **Saved Searches** | `/servicesNS/-/-/saved/searches` | GET | All saved searches/alerts |
| **Dashboards** | `/servicesNS/-/-/data/ui/views` | GET | All dashboards |
| **Panels** | `/servicesNS/-/-/data/ui/panels` | GET | All panels |
| **Macros** | `/servicesNS/-/-/admin/macros` | GET | All macros |
| **Eventtypes** | `/servicesNS/-/-/saved/eventtypes` | GET | All eventtypes |
| **Tags** | `/servicesNS/-/-/configs/conf-tags` | GET | All tags |
| **Lookups** | `/servicesNS/-/-/data/lookup-table-files` | GET | All lookup files |
| **Transforms** | `/servicesNS/-/-/data/transforms/extractions` | GET | Field extractions |

### 8.4 Cluster & Distributed Endpoints

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| **Search Peers** | `/services/search/distributed/peers` | GET | Indexer peers |
| **Cluster Master** | `/services/cluster/master/info` | GET | CM info |
| **Cluster Peers** | `/services/cluster/master/peers` | GET | Cluster peer list |
| **SHC Captain** | `/services/shcluster/captain/info` | GET | SHC captain info |
| **SHC Members** | `/services/shcluster/captain/members` | GET | SHC member list |

### 8.5 Usage Analytics Endpoints

| Category | Endpoint | Method | Purpose |
|----------|----------|--------|---------|
| **Search Jobs** | `/services/search/jobs` | GET | Recent search jobs |
| **Introspection** | `/services/server/introspection` | GET | Internal metrics |
| **Deployment Clients** | `/services/deployment/server/clients` | GET | Forwarder list |
| **License Usage** | `/services/licenser/usage` | GET | License consumption |

### 8.6 Search-Based Analytics (Internal Indexes)

```bash
# These require search capability and access to internal indexes
# Default period: 7d (configurable via --analytics-period)
# v4.3.0+: uses exec_mode=normal (async dispatch) with adaptive polling

# Search activity from audit index
index=_audit sourcetype=audittrail action=search info=granted earliest=-7d
| stats count by user, savedsearch_name, app

# Dashboard views (v4.5.0+ uses provenance field in Cloud scripts)
index=_audit sourcetype=audittrail action=search info=granted earliest=-7d
| stats count by user, app

# Alert triggers
index=_internal sourcetype=scheduler status=* earliest=-7d
| stats count as total_runs by app, savedsearch_name

# Index usage patterns
index=_audit sourcetype=audittrail action=search earliest=-7d
| rex field=search "index=(?<searched_index>\w+)"
| stats count by searched_index
```

---

## 9. Error Handling & Fallbacks

### 9.1 Error Categories and Responses

| Error Type | Detection | Fallback Strategy |
|------------|-----------|-------------------|
| **No REST API access** | HTTP 401/403 | File-based collection only |
| **Limited capabilities** | Missing capabilities | Collect what's accessible, note gaps |
| **File permission denied** | EACCES errors | Skip file, continue, report |
| **Network timeout** | Connection timeout | Retry 3x, then skip |
| **Large file** | File > 100MB | Sample or truncate |
| **Missing directory** | ENOENT | Skip, continue |
| **Corrupted config** | Parse error | Include raw, flag for review |

### 9.2 Fallback Collection Matrix

| Primary Method | Fallback 1 | Fallback 2 | Last Resort |
|----------------|------------|------------|-------------|
| REST API + Files | REST API only | Files only | Abort with partial |
| Internal index search | Audit log parse | Skip analytics | Note in summary |
| SHC Captain query | Local member data | REST API | Note limitations |
| Cluster-wide stats | Local node only | Skip | Note limitations |

### 9.3 Error Reporting Format

```json
{
  "errors": [
    {
      "timestamp": "2024-01-15T10:32:15Z",
      "stage": "collect_users",
      "severity": "warning",
      "message": "Unable to access LDAP configuration",
      "endpoint": "/services/authentication/providers/LDAP",
      "httpStatus": 403,
      "fallback": "LDAP group mappings will not be included",
      "impactedData": ["groups.json", "rbacSummary.ldapGroups"]
    }
  ],
  "warnings": [...],
  "skipped": [...]
}
```

---

## 10. Security Considerations

### 10.1 Sensitive Data Handling

| Data Type | Sensitivity | Handling |
|-----------|-------------|----------|
| **User passwords** | Critical | NEVER collect |
| **API tokens** | Critical | NEVER collect |
| **LDAP bind passwords** | Critical | NEVER collect |
| **Session tokens** | High | NEVER collect |
| **User emails** | Medium | Collect, mark PII |
| **Real names** | Medium | Collect, mark PII |
| **IP addresses** | Low | Collect |
| **Hostnames** | Low | Collect |

### 10.2 Configuration Sanitization

```bash
# Before including config files, sanitize:

# Remove passwords
sed -i 's/password\s*=\s*.*/password = [REDACTED]/g' file.conf

# Remove tokens
sed -i 's/token\s*=\s*.*/token = [REDACTED]/g' file.conf

# Remove private keys
sed -i 's/privateKey\s*=\s*.*/privateKey = [REDACTED]/g' file.conf

# Remove connection strings with credentials
sed -i 's/\(connection.*:\/\/[^:]*:\)[^@]*@/\1[REDACTED]@/g' file.conf
```

### 10.3 Audit Log Sampling

```bash
# When collecting audit samples:

# 1. Limit sample size (max 10,000 entries)
tail -10000 audit.log > audit_sample.log

# 2. Anonymize if requested
# Replace usernames with hashes
# Replace IPs with anonymized versions
# Remove search query content (may contain sensitive data)
```

### 10.4 Export File Protection

```bash
# 1. Set restrictive permissions on export file
chmod 600 export.tar.gz

# 2. Generate checksum for integrity
sha256sum export.tar.gz > export.tar.gz.sha256

# 3. Recommend secure transfer
echo "Transfer this file using SCP, SFTP, or other encrypted method"
echo "Delete the export file after upload to DMA"
```

---

## Appendix A: Complete Script Pseudocode

```bash
#!/bin/bash
# DMA Splunk Export Script v3.0.0

# =============================================================================
# INITIALIZATION
# =============================================================================

display_banner()
check_prerequisites()  # bash version, curl, permissions
initialize_logging()

# =============================================================================
# STEP 1: ENVIRONMENT DETECTION
# =============================================================================

detect_splunk_home() {
  # Check env var, common paths, prompt if needed
}

detect_splunk_flavor() {
  # Returns: enterprise|uf|hf
  check_splunk_launch_conf()
  check_binary_footprint()
  check_web_capability()
}

detect_architecture() {
  # Returns: standalone|distributed|cloud
  check_server_conf_clustering()
  check_server_conf_shclustering()
  check_distsearch_conf()
  check_cloud_indicators()
}

detect_node_role() {
  # Returns: search_head|indexer|forwarder|captain|master|...
  analyze_configuration_files()
  analyze_running_services()
}

build_environment_profile() {
  # Combine all detection results into JSON profile
}

display_environment_profile()
prompt_confirmation()

# =============================================================================
# STEP 2: SCOPE SELECTION
# =============================================================================

prompt_export_scope() {
  # 1. Full export
  # 2. Specific apps
  # 3. Specific categories
  # 4. Minimal (configs only)
}

if [ "$scope" == "specific_apps" ]; then
  display_app_selector()
  prompt_app_selection()
fi

if [ "$scope" == "specific_categories" ]; then
  display_category_selector()
  prompt_category_selection()
fi

# =============================================================================
# STEP 3: AUTHENTICATION
# =============================================================================

prompt_credentials()
test_authentication()
check_capabilities()

if [ "$missing_capabilities" ]; then
  display_capability_warnings()
  prompt_continue_with_limitations()
fi

# =============================================================================
# STEP 4: USAGE ANALYTICS OPTIONS
# =============================================================================

prompt_analytics_period()  # 7d, 30d, 90d, 365d, skip
prompt_audit_log_sample()  # y/n

# =============================================================================
# STEP 5: DATA COLLECTION
# =============================================================================

create_export_directory()

# Stage 1: System Information
collect_server_info()
collect_installed_apps()
collect_cluster_info()

# Stage 2: Configuration Files
for app in $apps; do
  collect_app_configs "$app"
done
collect_system_configs()

# Stage 3: Dashboards
collect_classic_dashboards()      # XML files
collect_dashboard_studio()        # REST API JSON

# Stage 4: Alerts & Saved Searches
collect_saved_searches()

# Stage 5: Users & RBAC
collect_users()
collect_roles()
collect_groups()
build_ownership_map()

# Stage 6: Usage Analytics
collect_search_activity()
collect_dashboard_usage()
collect_alert_metrics()
collect_index_usage()
collect_user_activity()

# Stage 7: Index Statistics
collect_index_details()
collect_sourcetype_stats()

# =============================================================================
# STEP 6: SUMMARY GENERATION
# =============================================================================

calculate_priority_scores()
generate_summary_markdown()

# =============================================================================
# STEP 7: ARCHIVE CREATION
# =============================================================================

create_tarball()
calculate_checksum()
cleanup_temp_files()

# =============================================================================
# STEP 8: COMPLETION
# =============================================================================

display_summary()
display_next_steps()
```

---

## Appendix B: Migration Priority Scoring Algorithm

```python
def calculate_priority_score(asset):
    """
    Calculate migration priority score (0-100) for an asset.

    Weights:
    - Usage Frequency: 40%
    - User Reach: 25%
    - Business Criticality: 20%
    - Data Volume: 15%
    """

    # Usage Frequency (0-40 points)
    if asset.type == "dashboard":
        usage_score = min(40, (asset.views_30d / 100) * 40)
    elif asset.type == "alert":
        usage_score = min(40, (asset.triggers_30d / 50) * 40)
    elif asset.type == "saved_search":
        usage_score = min(40, (asset.executions_30d / 500) * 40)
    elif asset.type == "index":
        usage_score = min(40, (asset.search_count_30d / 1000) * 40)

    # User Reach (0-25 points)
    reach_score = min(25, (asset.unique_users / 20) * 25)

    # Business Criticality (0-20 points)
    criticality_score = 0
    if asset.severity == "critical":
        criticality_score += 10
    elif asset.severity == "high":
        criticality_score += 7
    elif asset.severity == "medium":
        criticality_score += 4

    if asset.owner in HIGH_VALUE_OWNERS:  # security, compliance, ops
        criticality_score += 5

    if asset.app in CRITICAL_APPS:
        criticality_score += 5

    criticality_score = min(20, criticality_score)

    # Data Volume (0-15 points) - only for indexes
    if asset.type == "index":
        volume_score = min(15, (asset.size_gb / 1000) * 15)
    else:
        volume_score = 0

    # Total Score
    total = usage_score + reach_score + criticality_score + volume_score

    return round(total, 1)
```

---

## Appendix C: Flavor-Specific Collection Matrices

### Universal Forwarder Collection

| Category | Collected | Method | Notes |
|----------|-----------|--------|-------|
| inputs.conf | ✅ | File | All monitored files/directories |
| outputs.conf | ✅ | File | Forwarding destinations |
| props.conf | ✅ | File | Local parsing rules (if any) |
| transforms.conf | ✅ | File | Local transforms (if any) |
| deploymentclient.conf | ✅ | File | DS relationship |
| server.conf | ✅ | File | Basic server config |
| Server info | ⚠️ | REST | Limited (if REST available) |
| Dashboards | ❌ | N/A | Not applicable |
| Alerts | ❌ | N/A | Not applicable |
| Users/RBAC | ❌ | N/A | Not applicable |
| Usage stats | ❌ | N/A | Not applicable |

### Heavy Forwarder Collection

| Category | Collected | Method | Notes |
|----------|-----------|--------|-------|
| All UF items | ✅ | File | Same as UF |
| props.conf | ✅ | File | Full parsing rules |
| transforms.conf | ✅ | File | Full transforms |
| routing rules | ✅ | File | Data routing configuration |
| Server info | ✅ | REST | Full server info |
| Throughput stats | ⚠️ | REST | If metrics available |
| Users/RBAC | ⚠️ | REST | Limited local users |

### Search Head / SHC Collection

| Category | Collected | Method | Notes |
|----------|-----------|--------|-------|
| All configs | ✅ | File + REST | Full collection |
| Dashboards | ✅ | REST | Classic + Studio |
| Alerts | ✅ | REST | All saved searches |
| Users/RBAC | ✅ | REST | Full RBAC |
| Usage stats | ✅ | REST + Search | Full analytics |
| Index details | ⚠️ | REST | From search peers |

### Indexer / IDX Cluster Collection

| Category | Collected | Method | Notes |
|----------|-----------|--------|-------|
| indexes.conf | ✅ | File | Full index config |
| props.conf | ✅ | File | Index-time parsing |
| transforms.conf | ✅ | File | Index-time transforms |
| Index stats | ✅ | REST | Full volume data |
| Bucket info | ✅ | REST | Storage details |
| Dashboards | ❌ | N/A | Run on SH |
| Alerts | ❌ | N/A | Run on SH |
| Users/RBAC | ⚠️ | REST | Limited |

---

*End of Specification Document*
*Version 4.4.0 | DMA Splunk Export Framework*
