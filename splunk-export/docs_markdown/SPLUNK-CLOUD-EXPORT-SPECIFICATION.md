# DynaBridge Splunk Cloud Export Script - Technical Specification

## Version 4.0.1 | REST API-Only Data Collection for Splunk Cloud

**Last Updated**: January 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Cloud README](README-SPLUNK-CLOUD.md) | [Export Schema](EXPORT-SCHEMA.md)

---

## Executive Summary

This specification defines the complete requirements for a **Splunk Cloud-specific** data collection script that operates **100% via REST API** without any file system access.

### Key Differences from Enterprise Script

| Aspect | Enterprise Script | Cloud Script |
|--------|------------------|--------------|
| **Where it runs** | ON the Splunk server | ANYWHERE with network access |
| **Access method** | SSH + File system + REST | **REST API ONLY** |
| **Authentication** | Local Splunk creds | Cloud credentials or API tokens |
| **SPLUNK_HOME access** | Yes | No |
| **File-based configs** | Yes (props.conf, etc.) | No - must use REST endpoints |
| **Output format** | Same `.tar.gz` structure | Same `.tar.gz` structure |

---

## What's New in v4.0.1

### Container Compatibility Improvements
- **Container-friendly progress display**: Progress bars now use newlines at 5% intervals instead of carriage returns, ensuring clean output in kubectl exec, Docker exec, and other containerized environments
- **Improved output formatting**: Progress updates print cleanly without overlapping lines in non-TTY environments

---

## What's New in v4.0.0

### Enterprise Resilience Features (MAJOR UPDATE)
The Cloud script now has **full feature parity** with the Enterprise script for large-scale environments:

- **Paginated API calls**: `api_call_paginated()` with configurable `BATCH_SIZE` (default: 100)
- **Extended timeouts**: `API_TIMEOUT=120s`, `MAX_TOTAL_TIME=14400s` (4 hours)
- **Checkpoint/resume**: Automatic detection and resume of incomplete exports
- **Export timing statistics**: Detailed API call tracking and duration reporting
- **Zero-configuration reliability**: Defaults tuned for 4000+ dashboards, 10K+ alerts

### Enterprise-Ready Defaults

| Setting | Default | Purpose |
|---------|---------|---------|
| `BATCH_SIZE` | 100 | Items per API request |
| `RATE_LIMIT_DELAY` | 0.1s | Between requests (100ms) |
| `API_TIMEOUT` | 120s | Per-request timeout |
| `MAX_TOTAL_TIME` | 14400s | 4 hours max runtime |
| `MAX_RETRIES` | 3 | Retry with exponential backoff |
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume |

### Previous Features (from v3.6.0)
- **Python-based JSON processing**: All JSON parsing uses Python 3
- **Container compatibility**: Multiple hostname fallbacks for Docker/Kubernetes
- **Aligned rate limiting**: Consistent with Enterprise script

---

## Table of Contents

1. [Splunk Cloud Overview](#1-splunk-cloud-overview)
2. [Authentication Methods](#2-authentication-methods)
3. [REST API Data Collection](#3-rest-api-data-collection)
4. [API Endpoints Reference](#4-api-endpoints-reference)
5. [Script Flow](#5-script-flow)
6. [Output Structure](#6-output-structure)
7. [Usage Intelligence](#7-usage-intelligence)
8. [Manifest Schema](#8-manifest-schema)
9. [Rate Limiting & Throttling](#9-rate-limiting--throttling)
10. [Error Handling](#10-error-handling)
11. [Security Considerations](#11-security-considerations)

---

## 1. Splunk Cloud Overview

### 1.1 Splunk Cloud Flavors

| Flavor | Description | API Access | Notes |
|--------|-------------|------------|-------|
| **Splunk Cloud Classic** | Original multi-tenant cloud | Full REST API | Legacy, being phased out |
| **Splunk Cloud Victoria** | Latest cloud architecture | Full REST API | Current default |
| **Splunk Cloud on AWS** | AWS-hosted single tenant | Full REST API | Enterprise features |
| **Splunk Cloud on GCP** | GCP-hosted single tenant | Full REST API | Enterprise features |

### 1.2 Cloud Stack URL Patterns

```
# Standard Splunk Cloud URL patterns
https://<stack-name>.splunkcloud.com           # Web UI
https://<stack-name>.splunkcloud.com:8089      # REST API (management port)

# Examples
https://acme-corp.splunkcloud.com
https://acme-corp.splunkcloud.com:8089/services/server/info

# Some stacks use different patterns
https://inputs.<stack-name>.splunkcloud.com    # HEC endpoint
https://api.<stack-name>.splunkcloud.com       # API endpoint (some configs)
```

### 1.3 What's Accessible via REST API

| Data Type | REST Endpoint | Available? |
|-----------|---------------|------------|
| Server Info | `/services/server/info` | ✅ Yes |
| Installed Apps | `/services/apps/local` | ✅ Yes |
| Dashboards | `/servicesNS/-/-/data/ui/views` | ✅ Yes |
| Saved Searches/Alerts | `/servicesNS/-/-/saved/searches` | ✅ Yes |
| Users | `/services/authentication/users` | ✅ Yes |
| Roles | `/services/authorization/roles` | ✅ Yes |
| Macros | `/servicesNS/-/-/admin/macros` | ✅ Yes |
| Eventtypes | `/servicesNS/-/-/saved/eventtypes` | ✅ Yes |
| Tags | `/servicesNS/-/-/configs/conf-tags` | ✅ Yes |
| Lookups (definitions) | `/servicesNS/-/-/data/lookup-table-files` | ✅ Yes |
| Lookup contents | `/servicesNS/-/-/data/lookup-table-files/{name}` | ✅ Yes |
| Field Extractions | `/servicesNS/-/-/data/transforms/extractions` | ✅ Yes |
| Props (via conf) | `/servicesNS/-/-/configs/conf-props` | ✅ Yes |
| Transforms (via conf) | `/servicesNS/-/-/configs/conf-transforms` | ✅ Yes |
| Indexes | `/services/data/indexes` | ✅ Yes |
| Index Stats | `/services/data/indexes-extended` | ⚠️ Limited |
| Search Jobs | `/services/search/jobs` | ✅ Yes |
| KV Store Collections | `/servicesNS/-/-/storage/collections/config` | ✅ Yes |
| Audit Logs | `index=_audit` via search | ⚠️ Requires search |

### 1.4 What's NOT Accessible

| Data Type | Why Not Available |
|-----------|------------------|
| Raw config files | No file system access |
| `$SPLUNK_HOME/etc/` | No file system access |
| Audit.log file | No file system access |
| Bucket metadata | No file system access |
| Internal indexes (some) | Cloud restrictions |
| License file | Cloud-managed |

---

## 2. Authentication Methods

### 2.1 Username/Password Authentication

```bash
# Basic authentication
curl -k -u "username:password" \
  "https://acme.splunkcloud.com:8089/services/server/info" \
  -d "output_mode=json"
```

**Requirements**:
- Splunk Cloud admin account
- Account must have required capabilities
- May require MFA bypass token for API access

### 2.2 Splunk Authentication Token

```bash
# Token-based authentication (recommended)
curl -k -H "Authorization: Bearer <token>" \
  "https://acme.splunkcloud.com:8089/services/server/info" \
  -d "output_mode=json"
```

**Creating an Auth Token**:
1. Log into Splunk Cloud web UI
2. Settings → Tokens
3. Create new token with required permissions
4. Set appropriate expiration

**Required Token Permissions**:
- `admin_all_objects`
- `list_users`
- `list_roles`
- `list_indexes`
- `search`
- `rest_access`

### 2.3 Session Token Authentication

```bash
# Step 1: Get session key
SESSION_KEY=$(curl -k -u "user:pass" \
  "https://acme.splunkcloud.com:8089/services/auth/login" \
  -d "username=user&password=pass" \
  | grep -oP '(?<=<sessionKey>)[^<]+')

# Step 2: Use session key
curl -k -H "Authorization: Splunk $SESSION_KEY" \
  "https://acme.splunkcloud.com:8089/services/server/info"
```

### 2.4 Authentication Decision Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   AUTHENTICATION FLOW                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Do you have an API Token?                                   │
│   └─ YES → Use token-based auth (most secure)               │
│   └─ NO  → Do you have username/password?                   │
│             └─ YES → Is MFA required?                       │
│                       └─ YES → Need MFA bypass or token    │
│                       └─ NO  → Use basic auth               │
│             └─ NO  → Cannot authenticate                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. REST API Data Collection

### 3.1 Collection Strategy

Since we cannot read files, all data must come from REST API endpoints. The strategy is:

1. **Server & Environment Info**: Direct REST calls
2. **Apps & Configurations**: Use `/configs/conf-{name}` endpoints
3. **Knowledge Objects**: Use `/servicesNS/-/-/` namespace
4. **Users & RBAC**: Use `/services/authentication/` and `/services/authorization/`
5. **Usage Analytics**: Run searches against `_audit` index
6. **Dashboards**: Combine views endpoint with KV Store for Dashboard Studio

### 3.2 Configuration Reconstruction

Since we can't read `props.conf` directly, we reconstruct it from REST:

```bash
# Get all props stanzas
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/servicesNS/-/-/configs/conf-props" \
  -d "output_mode=json" -d "count=0"

# Get all transforms stanzas
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/servicesNS/-/-/configs/conf-transforms" \
  -d "output_mode=json" -d "count=0"
```

### 3.3 Dashboard Collection

```bash
# Classic Dashboards (SimpleXML)
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/servicesNS/-/-/data/ui/views" \
  -d "output_mode=json" -d "count=0"

# For each dashboard, get the full definition
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/servicesNS/-/-/data/ui/views/{dashboard_name}" \
  -d "output_mode=json"

# Dashboard Studio (stored in KV Store)
# These are included in the views endpoint with isDashboardStudio=true
```

### 3.4 Saved Searches & Alerts

```bash
# Get all saved searches (includes alerts, reports, scheduled searches)
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/servicesNS/-/-/saved/searches" \
  -d "output_mode=json" -d "count=0"

# Each result includes:
# - Search query (SPL)
# - Schedule (cron_schedule)
# - Alert settings (alert.*, action.*)
# - Owner and permissions
```

### 3.5 Usage Analytics via Search

```bash
# Create a search job to get usage analytics
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/services/search/jobs" \
  -d "search=search index=_audit action=search earliest=-30d | stats count by user, savedsearch_name" \
  -d "output_mode=json"

# Poll for completion
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/services/search/jobs/{sid}"

# Get results
curl -k -u "$USER:$PASS" \
  "https://$STACK:8089/services/search/jobs/{sid}/results" \
  -d "output_mode=json" -d "count=0"
```

---

## 4. API Endpoints Reference

### 4.1 System Information

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/server/info` | GET | Server version, OS, GUID |
| `/services/server/settings` | GET | Server configuration |
| `/services/apps/local` | GET | Installed apps list |
| `/services/licenser/licenses` | GET | License information |

### 4.2 Knowledge Objects

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/servicesNS/-/-/data/ui/views` | GET | All dashboards |
| `/servicesNS/-/-/saved/searches` | GET | All saved searches/alerts |
| `/servicesNS/-/-/admin/macros` | GET | All search macros |
| `/servicesNS/-/-/saved/eventtypes` | GET | All eventtypes |
| `/servicesNS/-/-/configs/conf-tags` | GET | All tags |
| `/servicesNS/-/-/data/lookup-table-files` | GET | Lookup file definitions |
| `/servicesNS/-/-/data/transforms/extractions` | GET | Field extractions |

### 4.3 Configurations (Reconstructed)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/servicesNS/-/-/configs/conf-props` | GET | Props.conf equivalent |
| `/servicesNS/-/-/configs/conf-transforms` | GET | Transforms.conf equivalent |
| `/servicesNS/-/-/configs/conf-indexes` | GET | Indexes.conf equivalent |
| `/servicesNS/-/-/configs/conf-inputs` | GET | Inputs.conf equivalent |
| `/servicesNS/-/-/configs/conf-outputs` | GET | Outputs.conf equivalent |
| `/servicesNS/-/-/configs/conf-savedsearches` | GET | Savedsearches.conf equivalent |

### 4.4 Users & RBAC

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/authentication/users` | GET | All users |
| `/services/authorization/roles` | GET | All roles |
| `/services/authentication/current-context` | GET | Current user context |
| `/services/admin/SAML-groups` | GET | SAML group mappings |

### 4.5 Indexes & Data

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/data/indexes` | GET | Index list and settings |
| `/services/data/indexes-extended` | GET | Extended index stats |
| `/services/catalog/metricstore/dimensions` | GET | Metric dimensions |

### 4.6 Search for Analytics

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/services/search/jobs` | POST | Create search job |
| `/services/search/jobs/{sid}` | GET | Check job status |
| `/services/search/jobs/{sid}/results` | GET | Get search results |

---

## 5. Script Flow

### 5.1 Complete Script Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SCRIPT START                                 │
│                                                                      │
│  • Display banner                                                   │
│  • Check prerequisites (curl, jq recommended)                       │
│  • Explain this is for Splunk Cloud                                 │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: SPLUNK CLOUD CONNECTION                                     │
│                                                                      │
│ ╔════════════════════════════════════════════════════════════════╗  │
│ ║  WHY WE ASK:                                                    ║  │
│ ║  We need to connect to your Splunk Cloud instance via REST API. ║  │
│ ║  This is the only way to access Splunk Cloud data - there is    ║  │
│ ║  no file system or SSH access to Splunk Cloud infrastructure.   ║  │
│ ╚════════════════════════════════════════════════════════════════╝  │
│                                                                      │
│ [PROMPT] Enter your Splunk Cloud stack URL:                        │
│   Example: acme-corp.splunkcloud.com                                │
│   > _______________                                                  │
│                                                                      │
│ Testing connection to https://acme-corp.splunkcloud.com:8089...     │
│ ✓ Splunk Cloud instance reachable                                   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 2: AUTHENTICATION                                              │
│                                                                      │
│ ╔════════════════════════════════════════════════════════════════╗  │
│ ║  WHY WE ASK:                                                    ║  │
│ ║  REST API access requires authentication. You can use either:   ║  │
│ ║  • Username/Password (your Splunk Cloud login)                  ║  │
│ ║  • API Token (more secure, recommended)                         ║  │
│ ║                                                                 ║  │
│ ║  REQUIRED PERMISSIONS:                                          ║  │
│ ║  • admin_all_objects - Access all knowledge objects             ║  │
│ ║  • list_users, list_roles - Access RBAC data                    ║  │
│ ║  • search - Run analytics queries                               ║  │
│ ╚════════════════════════════════════════════════════════════════╝  │
│                                                                      │
│ [PROMPT] Authentication method:                                      │
│   1. Username/Password                                               │
│   2. API Token (recommended)                                         │
│                                                                      │
│ [If option 1]:                                                       │
│   Enter username: admin                                              │
│   Enter password: ********                                           │
│                                                                      │
│ [If option 2]:                                                       │
│   Enter API token: ********                                          │
│                                                                      │
│ Testing authentication...                                            │
│ ✓ Authentication successful                                         │
│ ✓ User: admin@acme-corp.com                                         │
│ ✓ Capabilities: admin_all_objects, list_users, search               │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: ENVIRONMENT DETECTION                                       │
│                                                                      │
│ Detecting Splunk Cloud environment...                                │
│                                                                      │
│ ┌────────────────────────────────────────────────────────────────┐  │
│ │ Detected Environment:                                          │  │
│ │   Stack: acme-corp.splunkcloud.com                             │  │
│ │   Type: Splunk Cloud Victoria Experience                       │  │
│ │   Version: 9.1.2312                                            │  │
│ │   GUID: ABC123-DEF456-...                                      │  │
│ │   Apps: 45 installed                                           │  │
│ │   Users: 150                                                   │  │
│ └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│ [PROMPT] Is this the correct environment? (Y/n)                     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 4: APPLICATION SELECTION                                       │
│                                                                      │
│ [Same as Enterprise script - list apps, allow selection]            │
│                                                                      │
│   1. Export ALL applications (Recommended)                          │
│   2. Enter specific app names (comma-separated)                     │
│   3. Select from numbered list                                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 5: DATA CATEGORIES                                             │
│                                                                      │
│ [Same categories as Enterprise, but note Cloud limitations]         │
│                                                                      │
│ [✓] 1. Configurations (via REST - reconstructed from API)          │
│ [✓] 2. Dashboards (Classic + Dashboard Studio)                      │
│ [✓] 3. Alerts & Saved Searches                                      │
│ [✓] 4. Users & RBAC                                                 │
│ [✓] 5. Usage Analytics (via search on _audit)                       │
│ [✓] 6. Index Statistics                                             │
│ [ ] 7. Lookup Table Contents (may be large)                         │
│                                                                      │
│ Note: Some data may be limited due to Cloud restrictions            │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 6: DATA COLLECTION                                             │
│                                                                      │
│ [1/10] Collecting server information...              ✓              │
│ [2/10] Collecting installed apps...                  ✓              │
│ [3/10] Collecting configurations via REST...         ⏳ 45%         │
│        └─ props.conf (via /configs/conf-props)                      │
│        └─ transforms.conf (via /configs/conf-transforms)            │
│ [4/10] Collecting dashboards...                      ○              │
│ [5/10] Collecting saved searches & alerts...         ○              │
│ [6/10] Collecting users and roles...                 ○              │
│ [7/10] Running usage analytics searches...           ○              │
│ [8/10] Collecting index statistics...                ○              │
│ [9/10] Collecting macros & eventtypes...             ○              │
│ [10/10] Generating summary report...                 ○              │
│                                                                      │
│ Note: Some API calls may be rate-limited. Please be patient.        │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 7: ARCHIVE CREATION & COMPLETION                               │
│                                                                      │
│ Creating compressed archive...                                       │
│ ✓ Archive created: ./dynabridge_cloud_export_acme_20240115.tar.gz  │
│ ✓ Size: 125 MB                                                      │
│                                                                      │
│ NEXT STEPS:                                                         │
│ 1. Upload this file to DynaBridge in Dynatrace                      │
│ 2. The export format is compatible with Enterprise exports          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. Output Structure

### 6.1 Directory Structure

The output structure matches the Enterprise export for DynaBridge compatibility:

```
dynabridge_cloud_export_[stack]_[timestamp]/
│
├── dynasplunk-env-summary.md          # Master summary
├── _metadata.json                      # Export metadata
├── _environment_profile.json           # Cloud environment details
│
├── _systeminfo/
│   ├── server_info.json               # From /services/server/info
│   ├── installed_apps.json            # From /services/apps/local
│   └── license_info.json              # From /services/licenser/licenses
│
├── _rbac/
│   ├── users.json                     # From /services/authentication/users
│   ├── roles.json                     # From /services/authorization/roles
│   └── saml_groups.json               # From /services/admin/SAML-groups
│
├── _usage_analytics/
│   ├── search_activity.json           # From search on _audit
│   ├── dashboard_usage.json           # From search on _internal
│   └── alert_metrics.json             # From search on _audit
│
├── _indexes/
│   └── indexes.json                   # From /services/data/indexes
│
├── _configs/                          # Reconstructed from REST
│   ├── props.json                     # From /configs/conf-props
│   ├── transforms.json                # From /configs/conf-transforms
│   ├── indexes.json                   # From /configs/conf-indexes
│   └── inputs.json                    # From /configs/conf-inputs
│
├── [app_name]/                        # Per-app data
│   ├── app_info.json                  # App metadata
│   ├── dashboards/                    # Dashboard definitions
│   │   ├── dashboard_list.json
│   │   └── [dashboard_name].json
│   ├── savedsearches.json             # Alerts and saved searches
│   ├── macros.json                    # Search macros
│   ├── eventtypes.json                # Event types
│   ├── tags.json                      # Tags
│   ├── lookups/                       # Lookup definitions
│   │   ├── lookup_files.json
│   │   └── [lookup_name].csv          # If content collection enabled
│   └── field_extractions.json         # Field extractions
│
└── dashboard_studio/                  # Dashboard Studio dashboards
    ├── dashboards_list.json
    └── [dashboard_name].json
```

### 6.2 Updated Output Structure (v4.0.0)

The v4.0.0 output includes additional usage intelligence files:

```
dynabridge_cloud_export_[stack]_[timestamp]/
│
├── manifest.json                         # Standardized metadata schema
├── dynasplunk-env-summary.md             # Human-readable summary report
│
├── _usage_analytics/
│   ├── search_activity.json              # Search frequency data
│   ├── dashboard_usage.json              # Dashboard view metrics
│   ├── alert_metrics.json                # Alert trigger statistics
│   ├── dashboard_ownership.json          # Dashboard → owner mapping
│   ├── alert_ownership.json              # Alert → owner mapping
│   ├── ownership_summary.json            # Ownership by user summary
│   ├── top_indexes_by_volume.json        # Volume analysis
│   ├── top_sourcetypes_by_volume.json    # Sourcetype volume data
│   ├── top_hosts_by_volume.json          # Host volume data
│   ├── zero_view_dashboards.json         # Elimination candidates
│   └── never_fired_alerts.json           # Elimination candidates
│
└── [other directories as before]
```

---

## 7. Usage Intelligence

### 7.1 Ownership Mapping

The script collects ownership information for user-centric migration planning:

```json
// dashboard_ownership.json
{
  "results": [
    {
      "dashboard": "security_overview",
      "app": "security_app",
      "owner": "security_team",
      "sharing": "app"
    }
  ]
}

// alert_ownership.json
{
  "results": [
    {
      "alert": "critical_security_alert",
      "app": "security_app",
      "owner": "security_team",
      "is_scheduled": true
    }
  ]
}

// ownership_summary.json
{
  "results": [
    {
      "owner": "security_team",
      "dashboard_count": 32,
      "alert_count": 45
    }
  ]
}
```

### 7.2 Volume Analysis

Daily ingestion volume analysis for capacity planning:

```json
// top_indexes_by_volume.json
{
  "results": [
    {
      "index": "main",
      "total_gb": 12.34,
      "event_count": 123456789
    }
  ]
}

// top_sourcetypes_by_volume.json
{
  "results": [
    {
      "sourcetype": "access_combined",
      "total_gb": 5.67,
      "event_count": 45678901
    }
  ]
}
```

### 7.3 Elimination Candidates

Identifies unused assets that may be candidates for retirement:

**Dashboards with Zero Views:**
```json
// zero_view_dashboards.json
{
  "results": [
    {
      "dashboard": "old_unused_dashboard",
      "app": "legacy_app",
      "owner": "departed_user",
      "views_30d": 0
    }
  ]
}
```

**Alerts That Never Fired:**
```json
// never_fired_alerts.json
{
  "results": [
    {
      "alert": "never_triggered_alert",
      "app": "test_app",
      "owner": "test_user",
      "triggers_30d": 0
    }
  ]
}
```

---

## 8. Manifest Schema

### 8.1 Guaranteed manifest.json Schema

The script generates a standardized `manifest.json` file with a guaranteed schema for DynaBridge consumption:

```json
{
  "schemaVersion": "4.0.0",
  "exportType": "splunk_cloud",
  "exportTimestamp": "2025-12-03T10:30:00Z",
  "scriptVersion": "4.0.0",

  "cloudEnvironment": {
    "stackUrl": "acme-corp.splunkcloud.com",
    "stackType": "victoria",
    "splunkVersion": "9.1.2312",
    "serverGuid": "ABC123-DEF456-...",
    "cloudRegion": "aws-us-west-2"
  },

  "authentication": {
    "method": "api_token",
    "username": "admin@acme-corp.com",
    "capabilities": ["admin_all_objects", "list_users", "search"]
  },

  "collection": {
    "apps": 45,
    "dashboards": 245,
    "alerts": 187,
    "users": 150,
    "indexes": 32,
    "apiCallsMade": 523,
    "rateLimitHits": 3,
    "errors": 0,
    "warnings": 5
  },

  "usageIntelligence": {
    "analysisPeriod": "30d",
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

### 8.2 Schema Versioning

| Schema Version | Script Version | Key Changes |
|----------------|----------------|-------------|
| 1.0.0 | 1.0.0 | Initial schema |
| 3.0.0 | 3.0.0 | Added usage analytics |
| 3.5.0 | 3.5.0 | Added ownership mapping, elimination candidates, volume analysis |
| 4.0.0 | 4.0.0 | Enterprise resilience: paginated APIs, checkpoints, extended timeouts, timing stats |

---

## 9. Rate Limiting & Throttling

### 9.1 Splunk Cloud API Limits

Splunk Cloud may enforce rate limits on REST API calls:

| Limit Type | Typical Value | Handling Strategy |
|------------|---------------|-------------------|
| Requests per minute | 100-500 | Exponential backoff |
| Concurrent connections | 10-50 | Sequential processing |
| Response size | 50MB | Pagination |
| Search concurrency | 5-10 | Queue searches |

### 9.2 Rate Limit Detection

```bash
# HTTP 429 indicates rate limiting
if [ "$http_code" = "429" ]; then
  retry_after=$(echo "$headers" | grep -i "Retry-After" | cut -d: -f2)
  sleep $retry_after
  # Retry request
fi
```

### 9.3 Throttling Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    THROTTLING STRATEGY                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Start with normal request rate                          │
│                                                              │
│  2. On 429 response:                                        │
│     • Check Retry-After header                              │
│     • Wait specified time (or default 60s)                  │
│     • Reduce request rate by 50%                            │
│     • Retry request                                         │
│                                                              │
│  3. Implement exponential backoff:                          │
│     • 1st retry: wait 1 second                              │
│     • 2nd retry: wait 2 seconds                             │
│     • 3rd retry: wait 4 seconds                             │
│     • Max: wait 60 seconds                                  │
│                                                              │
│  4. For large collections (>1000 items):                    │
│     • Use pagination (count=100, offset=N)                  │
│     • Add 100ms delay between pages                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 10. Error Handling

### 10.1 Common Errors

| HTTP Code | Meaning | Handling |
|-----------|---------|----------|
| 401 | Unauthorized | Check credentials, re-authenticate |
| 403 | Forbidden | Check capabilities/permissions |
| 404 | Not Found | Skip resource, log warning |
| 429 | Rate Limited | Apply backoff, retry |
| 500 | Server Error | Retry with backoff |
| 503 | Service Unavailable | Wait, retry |

### 10.2 Error Response Format

```json
{
  "errors": [
    {
      "timestamp": "2025-12-03T10:32:15Z",
      "endpoint": "/servicesNS/-/-/data/ui/views",
      "httpStatus": 403,
      "message": "Capability 'admin_all_objects' required",
      "severity": "error",
      "impact": "Dashboards will not be collected",
      "resolution": "Grant 'admin_all_objects' to the user/token"
    }
  ],
  "warnings": [...],
  "skipped": [...]
}
```

### 10.3 Graceful Degradation

```
┌─────────────────────────────────────────────────────────────┐
│                   GRACEFUL DEGRADATION                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  If endpoint fails:                                         │
│  1. Log the error with details                              │
│  2. Continue with other endpoints                           │
│  3. Mark that data category as incomplete                   │
│  4. Include error in summary report                         │
│  5. Suggest resolution in final output                      │
│                                                              │
│  Never fail the entire export for a single endpoint error   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. Security Considerations

### 11.1 Credential Handling

```
┌─────────────────────────────────────────────────────────────┐
│                   CREDENTIAL SECURITY                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  DO:                                                        │
│  ✓ Use API tokens instead of passwords when possible        │
│  ✓ Clear credentials from memory after use                  │
│  ✓ Use HTTPS for all API calls                             │
│  ✓ Validate SSL certificates (warn if skipping)            │
│                                                              │
│  DO NOT:                                                    │
│  ✗ Store credentials in the export file                    │
│  ✗ Log credentials in any output                           │
│  ✗ Pass credentials as command-line arguments               │
│  ✗ Store credentials in environment variables permanently   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.2 Data Sensitivity

| Data Type | Sensitivity | Handling |
|-----------|-------------|----------|
| API Token | Critical | Never stored, cleared after use |
| Password | Critical | Never stored, cleared after use |
| User emails | Medium | Collected, marked as PII |
| User names | Medium | Collected, marked as PII |
| Search queries | Medium | May contain sensitive terms |
| Dashboard names | Low | Collected |
| Index names | Low | Collected |

### 11.3 Network Security

```bash
# Always use HTTPS
URL="https://${STACK}.splunkcloud.com:8089"

# Verify SSL certificate (default)
curl "$URL/services/server/info"

# If custom CA or self-signed (warn user)
curl -k "$URL/services/server/info"  # Not recommended
```

---

## Appendix A: Full API Collection Script Outline

```bash
#!/bin/bash
# dynabridge-splunk-cloud-export.sh

# 1. Parse arguments and show banner
# 2. Get stack URL from user
# 3. Test connectivity
# 4. Get authentication (token or user/pass)
# 5. Test authentication and check capabilities
# 6. Detect environment (version, type)
# 7. List apps and let user select
# 8. Select data categories
# 9. Create output directory
# 10. Collect data via REST API:
#     - Server info
#     - Apps
#     - Configs (props, transforms, etc.)
#     - Dashboards
#     - Saved searches
#     - Users and roles
#     - Macros, eventtypes, tags
#     - Index info
#     - Usage analytics (via search)
# 11. Generate summary
# 12. Create archive
# 13. Cleanup and display next steps
```

---

## Appendix B: jq Dependency Note

**NOTE**: `jq` is **recommended** (not required) for manifest.json generation in v4.0.0. The script will check for jq and display a warning if not installed, but will continue with fallback methods.

```bash
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "jq is not installed - REQUIRED for manifest.json generation"
    echo "Install with: apt-get install jq / yum install jq / brew install jq"
    exit 1
fi
```

The script uses jq extensively for:
- Parsing REST API responses
- Extracting usage intelligence data
- Generating and validating manifest.json
- Building the ownership mapping files

**Installation**:
- Ubuntu/Debian: `apt-get install jq`
- RHEL/CentOS: `yum install jq`
- macOS: `brew install jq`

---

*End of Splunk Cloud Export Script Technical Specification*
*Version 4.0.0*
