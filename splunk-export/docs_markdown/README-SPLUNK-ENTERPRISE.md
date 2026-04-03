# DMA Splunk Enterprise Export Script

**Version**: 4.6.0
**Last Updated**: April 2026
**Related Documents**: [Script-Generated Analytics Reference](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | [Enterprise Export Specification](SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | [Manual Usage Queries (SHC/Distributed)](MANUAL-USAGE-QUERIES.md) | For Splunk Cloud exports, see [Cloud Export README](README-SPLUNK-CLOUD.md)

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Overview

The Enterprise script (`dma-splunk-export.sh`) collects configuration, dashboards, alerts, and usage analytics from Splunk Enterprise (on-premises) deployments. It reads configuration files directly from the Splunk filesystem (`$SPLUNK_HOME/etc/apps/`) and makes REST API calls to `localhost:8089`. The resulting archive feeds into the **DMA Curator Server** for migration planning and Splunk-to-Dynatrace conversion.

This script is for **Splunk Enterprise only**. For Splunk Cloud, use `dma-splunk-cloud-export.sh` (Bash) or `dma-splunk-cloud-export.ps1` (PowerShell). See [README-SPLUNK-CLOUD.md](README-SPLUNK-CLOUD.md).

---

## Where to Run

The Enterprise script **must run on the Splunk Search Head** because it needs both filesystem access to `$SPLUNK_HOME/etc/apps/` and REST API access to `localhost:8089`.

### Search Head Cluster (SHC)

If your environment uses a Search Head Cluster, where you run the script matters:

| Server | What You Get | Recommended? |
|--------|-------------|--------------|
| **SHC Member** | Full data -- configs, dashboards, alerts, REST API analytics. Replicated knowledge objects are available on every member. | **Yes -- best choice** |
| **SHC Captain** | Works, but the script warns you. The Captain handles cluster coordination and running a heavy export adds load. | Avoid if possible |
| **Deployment Server** | Has app configurations pushed to it, but lacks REST API search capabilities or `_audit`/`_internal` data. Configs complete, usage analytics will fail. | Only if Search Heads are inaccessible |
| **Indexers** | Missing search-time knowledge objects and dashboard definitions. | **No** |

The script auto-detects SHC membership via the `/services/shcluster/member/info` REST endpoint. If it detects you are on the Captain node, it displays a warning recommending you run from a member instead.

### Where NOT to Run

- **Indexers / Indexer Cluster peers** -- the Search Head queries these via REST
- **Universal Forwarders** -- no search capability, no dashboards, no alerts
- **Heavy Forwarders** -- unless standalone and not managed by a Deployment Server
- **Cluster Manager / License Master** -- the Search Head queries these via REST

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| **Where to run** | On the Splunk Search Head (SSH required) |
| **Run as** | The `splunk` user (e.g., `sudo -u splunk bash dma-splunk-export.sh`) |
| **Shell** | bash 4.0+ |
| **Utilities** | curl, Python 3 (Splunk bundles Python at `$SPLUNK_HOME/bin/python3`), tar, gzip |
| **Disk space** | 500 MB+ free in `/tmp` or the working directory |
| **Network** | localhost access to port 8089 (Splunk management port) |

### Filesystem Permissions

The script reads (never writes to) these directories:

```
$SPLUNK_HOME/
  etc/
    apps/*/default/     # App default configurations
    apps/*/local/       # App local configurations
    apps/*/metadata/    # default.meta, local.meta
    apps/*/default/data/ui/views/   # Classic XML dashboards
    apps/*/local/data/ui/views/     # Classic XML dashboards
    apps/*/lookups/     # Lookup CSV files (if --lookups enabled)
    system/local/       # System-level configurations
```

Running as the `splunk` user (the user that owns the Splunk installation) guarantees read access to all of these paths:

```bash
# Switch to splunk user
sudo su - splunk

# Or run the script as the splunk user directly
sudo -u splunk bash /tmp/dma-splunk-export.sh
```

### SPLUNK_HOME Detection

The script auto-detects `$SPLUNK_HOME` using the following order:

1. **Environment variable** -- if `$SPLUNK_HOME` is set and the directory exists, uses it directly
2. **Common paths** -- scans `/opt/splunk`, `/opt/splunkforwarder`, `/Applications/Splunk`, `/Applications/SplunkForwarder`, `$HOME/splunk`, `$HOME/splunkforwarder`, `/usr/local/splunk`
3. **Interactive prompt** -- if none of the above are found, asks you to enter the path manually

You can also set it explicitly with the `--splunk-home` flag.

### Splunk User Permissions (REST API)

In addition to filesystem access, the script uses the Splunk REST API. The Splunk user account needs these capabilities:

| Capability | Required? | What It Is Used For |
|------------|-----------|---------------------|
| `admin_all_objects` | **Required** | Access dashboards, saved searches, and alerts across all apps |
| `list_users` | **Required** | Enumerate users and roles (for RBAC collection) |
| `list_roles` | **Required** | Collect role definitions |
| `rest_access` | **Required** | Make REST API calls |
| `search` | Recommended | Run SPL search jobs (ownership queries, usage analytics) |
| `list_indexes` | Recommended | Get index metadata and retention policies |
| `list_inputs` | Recommended | Get data input details |
| `list_settings` | Recommended | Get system settings |

For usage analytics (`--usage` or the default), the user also needs search-time access to `_audit` and `_internal` indexes.

---

## Always Run --test-access First

Before running a full export, confirm permissions with `--test-access`. This pre-flight check tests API categories and reports what will and will not work -- without writing any export data.

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --test-access
```

If `--test-access` shows FAIL on Dashboards, Saved Searches, or System Info, stop and fix permissions before proceeding. Running a full export with these failures will produce an incomplete archive.

---

## Running the Export

### Interactive Mode

When run without CLI arguments, the script walks you through each step:

1. **Pre-flight checklist** -- verifies bash, curl, Python 3, tar, gzip, disk space
2. **SPLUNK_HOME detection** -- auto-detects or prompts for the Splunk installation path
3. **Authentication** -- choose token or username/password; credentials are verified against the REST API
4. **SHC detection** -- warns if running on the Captain, shows member count
5. **Application selection** -- export all apps or pick specific ones
6. **Data category selection** -- toggle configs, dashboards, alerts, RBAC, usage, indexes, lookups, anonymization
7. **Analytics period** (if usage enabled) -- 7d, 30d, 90d, or 365d
8. **Collection** -- progress displayed per category
9. **Anonymization** -- creates the `_masked` archive (unless disabled)
10. **Summary** -- statistics table with counts, timing, and any errors

```bash
# Interactive -- prompts for everything
sudo -u splunk bash /tmp/dma-splunk-export.sh
```

### Non-Interactive Mode

Supply all required parameters on the command line with `-y` / `--yes` to skip prompts:

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --splunk-home /opt/splunk \
  --yes
```

Token-only invocation (`--token` without username/password) auto-enables non-interactive mode.

### Authentication Options

| Method | Flags | Notes |
|--------|-------|-------|
| **API token** (recommended) | `--token TOKEN` | Sets `Authorization: Splunk $TOKEN` header for all API calls |
| **Username + password** | `-u USER -p PASS` | POSTs to `/services/auth/login` to obtain a session key |
| **Environment variables** | `SPLUNK_USER` + `SPLUNK_PASSWORD` | Alternative to CLI flags; useful for container deployments |

---

## What Is Collected

### Default Behavior (v4.6.0)

The Enterprise script defaults differ from the Cloud scripts:

| Setting | Enterprise Default | Cloud Default |
|---------|-------------------|---------------|
| **RBAC** | **ON** (`--no-rbac` to disable) | OFF (`--rbac` to enable) |
| **Usage Analytics** | **ON** (`--no-usage` to disable) | OFF (`--usage` to enable) |
| **Analytics Period** | **30d** | 7d |
| **Max Runtime** | **4 hours** (14400s) | 4 hours |

### Always Collected (defaults ON)

| Category | Source | Description |
|----------|--------|-------------|
| **Configuration files** | Filesystem | `props.conf`, `transforms.conf`, `eventtypes.conf`, `tags.conf`, `indexes.conf`, `macros.conf`, `savedsearches.conf`, `inputs.conf`, `outputs.conf`, `collections.conf`, `fields.conf`, `workflow_actions.conf`, `commands.conf` -- from both `default/` and `local/` directories of each app |
| **Dashboards** | Filesystem + REST | Classic XML from `data/ui/views/*.xml`; Dashboard Studio JSON via REST API (KV Store) |
| **Alerts & Saved Searches** | Filesystem + REST | All definitions with SPL queries and schedules |
| **Index Statistics** | REST API | Index metadata, sizes, retention policies, sourcetypes |
| **Knowledge Objects** | Filesystem | Macros, eventtypes, tags, lookups, field extractions |
| **Metadata** | Filesystem | `default.meta` and `local.meta` per app (for macro export scope) |

### On by Default in Enterprise (use --no-rbac / --no-usage to disable)

| Category | Flag to Disable | Description |
|----------|----------------|-------------|
| **Users & RBAC** | `--no-rbac` | Users, roles, capabilities, SAML groups, SAML config, LDAP groups, LDAP config. No passwords collected. 404s handled gracefully with placeholder JSON when not configured. |
| **Usage Analytics** | `--no-usage` | Ownership mapping, REST metadata, and (if `_audit`/`_internal` accessible) the 6 global aggregate queries that power the DMA Explorer. |

### What Usage Analytics Produces (v4.6.0)

In v4.6.0, `collect_usage_analytics` has been streamlined. It now collects:

**Ownership data** (via `| rest` SPL queries -- no `_audit`/`_internal` access required):

| File | Method | Explorer Tab |
|------|--------|-------------|
| `dashboard_ownership.json` | `\| rest /servicesNS/-/-/data/ui/views` | Dashboards -- owner column |
| `alert_ownership.json` | `\| rest /servicesNS/-/-/saved/searches` | Alerts -- owner column |
| `ownership_summary.json` | `\| rest` (aggregate) | Supplementary -- assets per owner |

**REST supplementary metadata** (direct REST calls, no search jobs):

| File | Endpoint | Purpose |
|------|----------|---------|
| `saved_searches_all.json` | `/servicesNS/-/-/saved/searches` (metadata fields only via `f=` params) | Schedule, severity, actions for all saved searches |
| `recent_searches.json` | `/services/search/jobs` (last 1000) | Recent search job activity |
| `kvstore_stats.json` | `/services/server/introspection/kvstore` | KV Store usage statistics |

**USAGE_INTELLIGENCE_SUMMARY.md** -- a markdown summary document describing the collected data and providing a migration prioritization framework.

The 6 global aggregate queries that produce Explorer data are in `collect_app_analytics` (not `collect_usage_analytics`). These run against `_audit` and `_internal`:

| File | Index | Explorer Tab |
|------|-------|-------------|
| `dashboard_views_global.json` | `_audit` | Dashboards -- view counts per dashboard |
| `user_activity_global.json` | `_audit` | Supplementary -- searches per user per app |
| `search_patterns_global.json` | `_audit` | Supplementary -- search type breakdown |
| `index_volume_summary.json` | `_internal` | Indexes -- daily ingestion GB per index |
| `index_event_counts_daily.json` | `_internal` | Indexes -- event counts per index per day |
| `alert_firing_global.json` | `_internal` | Alerts -- execution stats per alert |

### What Is NOT Collected

- User passwords or password hashes
- API tokens or session keys (passwords in `.conf` files are auto-redacted)
- Actual log/event data (only metadata and structure)
- SSL certificates or private keys
- KV Store data (except Dashboard Studio definitions)

---

## Data Anonymization

When anonymization is enabled (the default), the script creates **two archives**:

| Archive | Contents | Purpose |
|---------|----------|---------|
| `dma_export_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz` | Original, untouched data | Reference copy -- keep internally |
| `dma_export_<hostname>_<YYYYMMDD_HHMMSS>_masked.tar.gz` | Anonymized copy | Safe to share with Dynatrace or externally |

Anonymization applies deterministic (hash-based) masking:

| Data Type | Example Original | Example Anonymized |
|-----------|-----------------|-------------------|
| **Email addresses** | `user@corp.com` | `anon######@anon.dma.local` |
| **Hostnames** | `splunk-idx01.corp.com` | `host-########.anon.local` |
| **IPv4 addresses** | `192.168.1.100` | `[IP-REDACTED]` |
| **IPv6 addresses** | `2001:db8::1` | `[IPv6-REDACTED]` |
| **Webhook URLs** | `https://hooks.slack.com/...` | `https://webhook.anon.dma.local/hook-###` |
| **API keys/tokens** | (various) | `[API-KEY-########]` |

`localhost` and `127.0.0.1` are preserved. The same original value always produces the same anonymized value, so relationships are maintained across the archive. An `_anonymization_report.json` documents what was anonymized.

Upload the `_masked` archive when sharing externally. Use the original archive for internal analysis on the DMA Server.

---

## Command-Line Reference

### Connection & Authentication

| Flag | Description | Default |
|------|-------------|---------|
| `--token TOKEN` | API token authentication (recommended for automation) | -- |
| `-u`, `--username USER` | Splunk admin username | -- |
| `-p`, `--password PASS` | Splunk admin password | -- |
| `-h`, `--host HOST` | Splunk host | `localhost` |
| `-P`, `--port PORT` | Splunk REST API port | `8089` |
| `--splunk-home PATH` | Splunk installation path (overrides auto-detection) | auto-detect |
| `--proxy URL` | Route all connections through an HTTP proxy | -- |

### Scope & Data Selection

| Flag | Description | Default |
|------|-------------|---------|
| `--all-apps` | Export all applications | ON (default) |
| `--apps "a,b,c"` | Export only these apps (comma-separated) | all apps |
| `--scoped` | Scope all collections to selected apps only | OFF |
| `--rbac` | Enable RBAC/users collection | **ON** (Enterprise default) |
| `--no-rbac` | Disable RBAC/users collection | -- |
| `--usage` | Enable usage analytics | **ON** (Enterprise default) |
| `--no-usage` | Disable usage analytics | -- |
| `--analytics-period N` | Analytics time window (e.g., `7d`, `30d`, `90d`, `365d`) | `30d` |
| `--skip-internal` | Skip `_audit`/`_internal` index searches | OFF |
| `--anonymize` | Enable data anonymization | ON (default) |
| `--no-anonymize` | Disable data anonymization | -- |

### Special Modes

| Flag | Description |
|------|-------------|
| `--test-access` | Pre-flight permission check -- test all API categories, then exit. No export written. **Always run this first.** |
| `--remask FILE` | Re-anonymize an existing unmasked archive. No Splunk connection needed. |
| `--resume-collect FILE` | Resume an interrupted export from a `.tar.gz` archive. Detects completed phases via checkpoint files and continues from where it stopped. Per-query checkpointing means individual analytics searches resume mid-way. |
| `--quick` | Quick mode -- skips global analytics entirely. **TESTING ONLY, not for migration analysis.** |

### Operational

| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Auto-confirm all prompts (non-interactive mode) |
| `-d`, `--debug` | Verbose debug logging (writes `_export_debug.log` inside the archive) |
| `--help` | Show help and exit |

---

## Examples

### Recommended: Full Export with Token

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --splunk-home /opt/splunk \
  --yes
```

RBAC and usage are on by default in Enterprise, so this collects everything.

### Minimal Export (No RBAC, No Usage)

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --no-rbac --no-usage \
  --yes
```

### Scoped to Specific Apps

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --apps "search,myapp,security_essentials" \
  --scoped --yes
```

### Pre-Flight Access Check

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --test-access
```

### Resume an Interrupted Export

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --resume-collect dma_export_splunk-sh01_20260401_143022.tar.gz
```

### Re-Anonymize an Existing Archive

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --remask dma_export_splunk-sh01_20260401_143022.tar.gz
```

No Splunk connection needed -- extracts, anonymizes, and repacks locally.

### With Username/Password and Environment Variables

```bash
export SPLUNK_USER="admin"
export SPLUNK_PASSWORD="MySecurePassword"
sudo -u splunk -E bash /tmp/dma-splunk-export.sh \
  --splunk-home /opt/splunk --yes
```

---

## Enterprise Resilience Settings

The script includes enterprise-scale defaults for environments with 4000+ dashboards and 10K+ alerts. All are overridable via environment variables:

| Setting | Default | Description |
|---------|---------|-------------|
| `BATCH_SIZE` | 250 | Items per API request |
| `RATE_LIMIT_DELAY` | 0.05s | Delay between paginated requests (50ms) |
| `API_TIMEOUT` | 120s | Per-request timeout (2 minutes) |
| `CONNECT_TIMEOUT` | 10s | TCP connection timeout |
| `MAX_TOTAL_TIME` | 14400s (4 hours) | Maximum total script runtime |
| `MAX_RETRIES` | 3 | Retry attempts with exponential backoff |
| `RETRY_DELAY` | 2s | Initial retry delay (doubles on each retry) |
| `CHECKPOINT_ENABLED` | true | Enable checkpoint/resume capability |

Override for very large environments:

```bash
BATCH_SIZE=50 API_TIMEOUT=180 sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" --yes
```

---

## Typical Runtimes

| Environment | Without Usage Analytics | With Usage Analytics |
|-------------|------------------------|---------------------|
| Small (10 apps, 200 dashboards) | 2-5 minutes | 5-15 minutes |
| Medium (50 apps, 1000 dashboards) | 10-20 minutes | 20-45 minutes |
| Large (200+ apps, 5000+ dashboards) | 30-60 minutes | 1-3 hours |

Analytics searches use async dispatch with up to 1 hour per query, so large `_audit` indexes no longer cause timeouts.

---

## Debug Mode

Add `--debug` (or `-d`) for detailed diagnostics:

- **Console**: Color-coded messages by category (ERROR, WARN, API, SEARCH, TIMING, AUTH, CONFIG, ENV)
- **Log file**: `_export_debug.log` inside the archive
- **API calls**: Logs every request with endpoint, HTTP status, response size, and duration
- **Auth**: Logs token probe responses and final header format
- **Search jobs**: Logs SID dispatch, poll states, completion time

```bash
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" --debug --yes
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SPLUNK_HOME not found` | Not running on the Search Head, or non-standard install path | Set `$SPLUNK_HOME` environment variable, use `--splunk-home`, or run as the `splunk` user |
| `Permission denied` reading config files | Not running as the `splunk` user | Run with `sudo -u splunk bash dma-splunk-export.sh` |
| `Connection refused` on REST API | Splunk not running or management port not 8089 | Check `$SPLUNK_HOME/bin/splunk status`; verify port with `ss -tlnp \| grep 8089` |
| `Unauthorized` on REST API | Wrong credentials or insufficient capabilities | Test with `--test-access`; verify the account has `admin_all_objects` |
| SHC Captain warning | Running on the cluster captain | Switch to an SHC member node |
| Export completes but Explorer shows no usage data | `_audit`/`_internal` access denied | Run `--test-access` to confirm; use `--skip-internal` to collect what you can |
| Analytics searches timeout | Very large `_audit` index | Reduce `--analytics-period 7d`; or use `--apps "app1,app2" --scoped` |
| Export takes hours | Large environment with usage analytics | Scope to key apps: `--apps "app1,app2" --scoped` |

---

## Where to Upload the Archive

After the export completes, upload the `.tar.gz` archive:

- **DMA Curator Server** -- migration planning, reporting, and team collaboration (recommended for all exports)
- **DMA Splunk App** -- ad-hoc migration analysis (suitable for smaller archives)

Use the `_masked` variant when sharing outside your organization.

---

## Additional Documentation

| Document | Description |
|----------|-------------|
| [README-SPLUNK-CLOUD.md](README-SPLUNK-CLOUD.md) | Cloud prerequisites, token creation, and network requirements |
| [EXPORT-SCHEMA.md](EXPORT-SCHEMA.md) | Complete archive file structure and field definitions |
| [SCRIPT-GENERATED-ANALYTICS-REFERENCE.md](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | Reference of all SPL queries used for analytics collection |
| [SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md](SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | Technical specification for Enterprise export internals |
| [INTERACTIVE-WALKTHROUGH.md](INTERACTIVE-WALKTHROUGH.md) | Step-by-step visual guide to the interactive prompts |
