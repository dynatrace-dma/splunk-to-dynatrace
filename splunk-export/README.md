# DMA Splunk Export Scripts

**Versions**: Enterprise (`dma-splunk-export.sh`) **4.6.5** · Cloud Bash (`dma-splunk-cloud-export.sh`) **4.6.6** · Cloud PowerShell (`dma-splunk-cloud-export.ps1`) **4.6.6**
**Last Updated**: May 2026

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Overview

These scripts extract configuration, dashboards, alerts, and usage analytics from Splunk environments to produce the export archive that powers the **Dynatrace Migration Assistant (DMA)**. The archive feeds into the **DMA Curator Server** for migration planning, reporting, and Splunk-to-Dynatrace conversion workflows.

There are **three scripts**. All produce the same archive format — the DMA Server does not care which script created the export.

| Script | Target Environment | Platform | Notes |
|--------|-------------------|----------|-------|
| `dma-splunk-cloud-export.sh` | Splunk Cloud | Bash (Linux/macOS/WSL) | Primary Cloud script. REST API only. |
| `dma-splunk-cloud-export.ps1` | Splunk Cloud | PowerShell 5.1+ (Windows) | Full parity with the Bash Cloud script. Zero external dependencies. |
| `dma-splunk-export.sh` | Splunk Enterprise (on-prem) | Bash (Linux) | Runs directly on the Search Head. Reads configs from filesystem + REST API. |

The two Cloud scripts (Bash and PowerShell) are functionally identical — they collect the same data, produce the same archive, and accept the same flags (with minor naming conventions for PowerShell). Choose whichever matches the machine you are running from. The Enterprise script collects the same data but reads configuration files directly from the Splunk filesystem, which is why it must run on the Search Head itself.

---

## Splunk Cloud — Start Here

The Cloud scripts are the most commonly used and the most sensitive to permissions. **Insufficient permissions are the #1 cause of failed or incomplete exports.** This section covers exactly what you need before running either Cloud script.

### CRITICAL: Required Permissions for Splunk Cloud

> **Before you do anything else**, confirm the user or token you plan to use has the correct role and capabilities. Running the export with insufficient permissions will not produce errors on every call — instead, many API responses will silently return empty results, and the export will appear to complete normally but will be missing critical data.

**Recommended approach**: Create a user with the **`sc_admin`** role, then generate an API token for that user under **Settings > Tokens > New Token**.

If `sc_admin` is not available, the user's role **must** include all of the following capabilities:

| Capability | Why It Is Required |
|------------|-------------------|
| `admin_all_objects` | Read dashboards, saved searches, and alerts across **all** apps. Without this, the export only sees assets owned by the user — most dashboards will be missing. |
| `list_settings` | Read server configuration and system settings. |
| `rest_properties_get` | Execute REST API calls for configs, knowledge objects, and metadata. |
| `search` | Run SPL search jobs (required for usage analytics against `_audit` and `_internal`). |
| `list_users` | Enumerate users and roles (required when using `--rbac`). |
| `list_indexes` | Read index metadata, retention policies, and sourcetype lists. |

**For usage analytics** (`--usage` flag), the user also needs **search-time access** to these internal indexes:

| Index | What It Provides | Without It |
|-------|-----------------|------------|
| `_audit` | Dashboard view counts, user activity, search patterns | No usage data — the Explorer's Dashboards, Alerts, and Indexes tabs will show zero usage |
| `_internal` | Alert firing stats, ingestion volume per index | No alert execution data, no volume estimates for Grail planning |

> **`_audit` and `_internal` access is commonly restricted in Splunk Cloud.** This is the single most frequent reason exports appear "empty" in the DMA Explorer. If your Splunk Cloud admin cannot grant access to these indexes, use `--skip-internal` to collect what you can, but understand that usage-based prioritization data will be missing.

### CRITICAL: Always Run `--test-access` First

**Do not run a full export until you have confirmed permissions with `--test-access`.** This pre-flight check tests 9 API categories and reports exactly what will and will not work — without writing any export data.

```bash
# Bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --usage --rbac \
  --test-access
```

```powershell
# PowerShell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Usage -Rbac `
  -TestAccess
```

Example output:

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                    ACCESS TEST RESULTS                          │
  ├──────────────────────────────────┬────────┬────────────────────┤
  │ Category                         │ Status │ Detail             │
  ├──────────────────────────────────┼────────┼────────────────────┤
  │ System Info                      │  PASS  │ Splunk v9.3.2411   │
  │ Configurations (indexes)         │  PASS  │ 12 entries         │
  │ Dashboards (myapp)               │  PASS  │ 47 found           │
  │ Saved Searches / Alerts (myapp)  │  PASS  │ 83 found           │
  │ RBAC (users/roles)               │  PASS  │ 24 users, 8 roles  │
  │ Knowledge Objects (myapp)        │  PASS  │ macros, props, ... │
  │ App Analytics (_audit)           │  PASS  │ 3 result(s)        │
  │ Usage Analytics (_internal)      │  FAIL  │ _internal denied   │
  │ Indexes                          │  PASS  │ 12 found           │
  └──────────────────────────────────┴────────┴────────────────────┘
```

**How to read the results:**
- **PASS** — This category will collect data normally.
- **FAIL** on `_audit` or `_internal` — Usage analytics will be incomplete. Ask your Splunk admin to grant search access to these indexes, or accept the gap.
- **FAIL** on `Dashboards` or `Saved Searches` — The user likely lacks `admin_all_objects`. This is a **critical** problem — the export will be mostly empty.
- **SKIP** — The category was not requested (e.g., RBAC shows SKIP if you did not pass `--rbac`).

> **If `--test-access` shows FAIL on Dashboards, Saved Searches, or System Info, stop and fix permissions before proceeding.** Running a full export with these failures will produce an archive the DMA Server cannot use.

### Splunk Cloud: Token Authentication

Both Cloud scripts auto-detect the correct token prefix. Splunk Cloud uses two different authorization header formats depending on how the token was created:

| Token Type | Header Format | How to Tell |
|-----------|---------------|-------------|
| Tokens from **Settings > Tokens** (UI) | `Authorization: Splunk <token>` | Most common in Splunk Cloud |
| JWT / OAuth2 tokens | `Authorization: Bearer <token>` | Less common |

You do **not** need to know which format to use — the script probes `/services/authentication/current-context` with both prefixes and uses whichever succeeds. If neither works, authentication has failed (wrong token, expired, or revoked).

### Splunk Cloud: Running the Export

**Interactive mode** (prompts for everything):
```bash
./dma-splunk-cloud-export.sh
```

**Non-interactive mode** (all parameters on command line):
```bash
./dma-splunk-cloud-export.sh \
  --stack acme-corp.splunkcloud.com \
  --token "$TOKEN" \
  --usage --rbac --yes
```

```powershell
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $TOKEN `
  -Usage -Rbac -NonInteractive
```

### Splunk Cloud: Prerequisites

| Requirement | Bash | PowerShell |
|-------------|------|------------|
| **Platform** | Linux, macOS, or WSL | Windows 10 1803+ |
| **Shell** | bash 3.2+ | PowerShell 5.1+ or 7+ |
| **External dependencies** | curl, Python 3, tar | **None** (zero — no Python, curl, or jq) |
| **Disk space** | 500 MB+ free | 500 MB+ free |
| **Network** | HTTPS to `your-stack.splunkcloud.com:8089` | HTTPS to `your-stack.splunkcloud.com:8089` |
| **Credentials** | API token (recommended) or username/password | API token (recommended) or username/password |

### Splunk Cloud: Where to Run

The Cloud scripts run **anywhere** with network access to the Splunk Cloud management port (8089). They do not need to be on the Splunk infrastructure:

- Your laptop
- A jump host or bastion
- A CI/CD runner
- Any machine that can reach `your-stack.splunkcloud.com:8089` over HTTPS

---

## Splunk Enterprise (On-Premises)

The Enterprise script (`dma-splunk-export.sh`) collects the same data as the Cloud scripts but operates differently: it reads configuration files directly from the Splunk filesystem (`$SPLUNK_HOME/etc/apps/`) in addition to making REST API calls. This means it **must run on the Splunk server itself**.

### Where to Run the Enterprise Script

The Enterprise script must run on a machine that has:
1. **Filesystem access** to `$SPLUNK_HOME/etc/apps/` (for reading `props.conf`, `transforms.conf`, `indexes.conf`, dashboards XML, lookup CSVs, etc.)
2. **REST API access** to `localhost:8089` (for saved searches, alerts, usage analytics, index metadata)

This typically means running it **on the Search Head**.

#### Search Head Cluster (SHC) Considerations

If your environment uses a Search Head Cluster, where you run the script matters:

| Server | What You Get | Recommended? |
|--------|-------------|--------------|
| **SHC Member** | Full data — configs, dashboards, alerts, and REST API analytics | **Yes** — best choice |
| **SHC Captain** | Works, but the script will show a warning. The Captain handles cluster coordination and running a heavy export adds load. | Avoid if possible |
| **Deployment Server** | Has the app configurations pushed to it, but does **not** have REST API search capabilities or `_audit`/`_internal` data. Configs will be complete but usage analytics will fail. | Only use if Search Heads are inaccessible |
| **Indexers** | Missing search-time knowledge objects and dashboard definitions. | **No** |

> The script auto-detects SHC membership and will warn you if it detects you are on the Captain node, recommending you run from a member instead.

#### Running the Enterprise Script

```bash
# Copy the script to the Search Head, then:
sudo -u splunk bash /tmp/dma-splunk-export.sh

# Or non-interactive:
sudo -u splunk bash /tmp/dma-splunk-export.sh \
  --token "$TOKEN" \
  --usage --rbac --yes
```

The script will auto-detect `$SPLUNK_HOME` by checking common paths (`/opt/splunk`, `/opt/splunkforwarder`, etc.) or using the `$SPLUNK_HOME` environment variable if set.

### Enterprise: Prerequisites

| Requirement | Detail |
|-------------|--------|
| **Where to run** | On the Splunk Search Head (SSH required) |
| **Run as** | The `splunk` user (e.g., `sudo -u splunk bash dma-splunk-export.sh`) |
| **Shell** | bash 4.0+ |
| **Utilities** | curl, Python 3 (Splunk bundles Python), tar |
| **Disk space** | 500 MB+ free in `/tmp` or working directory |
| **Network** | localhost access to port 8089 |

### Enterprise: Permissions

The same capabilities listed in the Cloud section apply. For Enterprise, the user also needs filesystem read access to `$SPLUNK_HOME/etc/apps/` — running as the `splunk` user handles this automatically.

`--test-access` works on Enterprise too and should be run first.

---

## What Is Collected

All scripts collect the same categories of data. The archive format is identical regardless of which script produces it.

### Always Collected (defaults ON)

| Category | Description | Migration Use |
|----------|-------------|---------------|
| **Dashboards** | Classic XML + Dashboard Studio v2 JSON, per app | Visual conversion to Dynatrace dashboards/notebooks |
| **Alerts & Saved Searches** | All definitions with SPL queries and schedules | SPL-to-DQL conversion, alert migration |
| **Configurations** | props.conf, transforms.conf, indexes.conf, inputs.conf | OpenPipeline generation, field extractions |
| **Index Statistics** | Index metadata, sizes, retention policies, sourcetypes | Dynatrace Grail bucket planning, capacity estimation |
| **Knowledge Objects** | Macros, eventtypes, tags, lookups, field extractions | Completeness check for SPL conversion |

### Opt-In (defaults OFF)

| Category | Flag | Description |
|----------|------|-------------|
| **Users & RBAC** | `--rbac` / `-Rbac` | Users, roles, capabilities, LDAP/SAML config. No passwords collected. |
| **Usage Analytics** | `--usage` / `-Usage` | Dashboard views, alert executions, user activity, ingestion volume. Requires `_audit` and `_internal` index access. |

### What Usage Analytics Produces (v4.6.0)

When `--usage` is enabled, 6 global aggregate queries run against `_audit` and `_internal`:

| File | Index | Explorer Tab |
|------|-------|-------------|
| `dashboard_views_global.json` | `_audit` | Dashboards — view counts per dashboard |
| `user_activity_global.json` | `_audit` | (supplementary) — searches per user per app |
| `search_patterns_global.json` | `_audit` | (supplementary) — search type breakdown |
| `index_volume_summary.json` | `_internal` | Indexes — daily ingestion GB per index |
| `index_event_counts_daily.json` | `_internal` | Indexes — event counts per index per day |
| `alert_firing_global.json` | `_internal` | Alerts — execution stats per alert |

Additionally, **ownership data** is collected via REST API (no search jobs required):

| File | Method | Explorer Tab |
|------|--------|-------------|
| `dashboard_ownership.json` | REST API | Dashboards — owner column |
| `alert_ownership.json` | REST API | Alerts — owner column |
| `ownership_summary.json` | REST API | (supplementary) |

### What Is NOT Collected

- User passwords or password hashes
- API tokens or session keys
- Actual log/event data (only metadata and structure)
- SSL certificates or private keys

---

## Command-Line Reference

Arguments are the same across all scripts, with minor naming differences for PowerShell.

### Connection & Authentication

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--stack URL` | `-Stack URL` | Splunk Cloud stack URL (Cloud only) |
| `--token TOKEN` | `-Token TOKEN` | API token (recommended) |
| `-u USER` / `--user USER` | `-User USER` | Username (alternative to token) |
| `-p PASS` / `--password PASS` | `-Password PASS` | Password (with username) |
| `-h HOST` / `--host HOST` | N/A | Splunk host (Enterprise only, default: localhost) |
| `-P PORT` / `--port PORT` | N/A | Splunk port (Enterprise only, default: 8089) |
| `--proxy URL` | `-Proxy URL` | HTTP proxy for all connections |

### Scope & Data Selection

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--all-apps` | `-AllApps` | Export all applications (default) |
| `--apps "a,b,c"` | `-Apps "a,b,c"` | Export only these apps |
| `--scoped` | N/A | Scope analytics to selected apps only |
| `--rbac` | `-Rbac` | Enable RBAC/users collection |
| `--usage` | `-Usage` | Enable usage analytics |
| `--analytics-period 7d` | `-AnalyticsPeriod 7d` | Analytics time window (default: 7d; also: 30d, 90d) |
| `--skip-internal` | `-SkipInternal` | Skip `_internal` index searches |
| `--no-anonymize` | `-SkipAnonymization` | Disable data anonymization |

### Special Modes

| Bash | PowerShell | Description |
|------|------------|-------------|
| `--test-access` | `-TestAccess` | Pre-flight permission check — test all API categories, then exit. **Always run this first.** |
| `--remask FILE` | `-Remask FILE` | Re-anonymize an existing archive. No Splunk connection needed. |
| `--resume-collect FILE` | `-ResumeCollect FILE` | Resume an interrupted export from a `.tar.gz` archive. |

### Operational

| Bash | PowerShell | Description |
|------|------------|-------------|
| `-y` / `--yes` | `-NonInteractive` | Auto-confirm all prompts |
| `-d` / `--debug` | `-Debug_Mode` | Verbose debug logging (writes `_export_debug.log`) |
| `--help` | `-ShowHelp` | Show help and exit |

---

## Data Anonymization

When anonymization is enabled (the default), the script creates **two archives**:

| Archive | Contents | Purpose |
|---------|----------|---------|
| `{name}.tar.gz` | Original, untouched data | Reference copy — keep internally |
| `{name}_masked.tar.gz` | Anonymized copy | Safe to share with Dynatrace or externally |

Anonymization applies deterministic masking:
- **Emails**: `user@corp.com` → `anon######@anon.dma.local`
- **Hostnames**: `splunk-idx01.corp.com` → `host-########.anon.local`
- **IPv4/IPv6**: Replaced with `[IP-REDACTED]` / `[IPv6-REDACTED]`

Upload the `_masked` archive when sharing externally. Use the original archive for internal analysis on the DMA Server.

---

## What to Expect

### Interactive Mode

When run without CLI arguments, the script walks you through:

1. **Connectivity check** — DNS resolution, TCP port 8089, TLS handshake
2. **Authentication** — choose token or username/password; credentials are verified
3. **Capability check** — warns if recommended permissions are missing
4. **Application selection** — export all apps or pick specific ones
5. **Data category selection** — toggle configs, dashboards, alerts, RBAC, usage, indexes
6. **Analytics period** (if `--usage` enabled) — 7d, 30d, 90d, or 365d
7. **Collection** — progress displayed per category; analytics use async search dispatch
8. **Anonymization** — creates the `_masked` archive (unless disabled)
9. **Summary** — statistics table with counts and any errors

### Non-Interactive Mode

When all required parameters are on the command line with `--yes` / `-NonInteractive`, the script runs without prompts.

### Typical Runtimes

| Environment | Without `--usage` | With `--usage` |
|-------------|-------------------|----------------|
| Small (10 apps, 200 dashboards) | 2-5 minutes | 5-15 minutes |
| Medium (50 apps, 1000 dashboards) | 10-20 minutes | 20-45 minutes |
| Large (200+ apps, 5000+ dashboards) | 30-60 minutes | 1-3 hours |

Analytics searches use async dispatch with up to 1 hour per query, so large `_audit` indexes no longer cause timeouts.

### Resume an Interrupted Export

If an export is interrupted (network drop, Ctrl+C, timeout), resume it:

```bash
./dma-splunk-cloud-export.sh \
  --resume-collect dma_cloud_export_acme_20260401_143022.tar.gz \
  --stack acme-corp.splunkcloud.com --token "$TOKEN"
```

The script extracts the partial archive, detects which phases completed via checkpoint files, and continues from where it stopped. Per-query checkpointing means even individual analytics searches resume mid-way.

### Re-Anonymize an Existing Archive

```bash
./dma-splunk-cloud-export.sh --remask dma_cloud_export_acme_20260401_143022.tar.gz
```

No Splunk connection needed — extracts, anonymizes, and repacks locally.

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No applications found!` | Token lacks `admin_all_objects` | Use `sc_admin` role, or add capability to the user's role |
| `Token authentication failed` | Wrong token, expired, or revoked | Regenerate the token in Splunk Cloud under Settings > Tokens |
| Export completes but Explorer shows no usage data | `_audit` / `_internal` access denied | Run `--test-access` to confirm; request index access from Splunk admin |
| Analytics searches timeout | Very large `_audit` index | Reduce `--analytics-period 7d`; or use `--apps "app1,app2" --scoped` |
| `Rate limited (429)` | Too many API calls in sequence | Script auto-retries with exponential backoff — no action needed |
| `_audit` / `_internal` access denied | Splunk Cloud restricts these indexes by default | Use `--skip-internal` to collect what you can |
| Export takes hours | Large environment with `--usage` | Scope to key apps: `--apps "app1,app2" --scoped` |
| PowerShell: `Execution Policy` error | Script execution disabled | Run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first |
| Enterprise: `SPLUNK_HOME not found` | Not running on the Search Head, or non-standard install path | Set `$SPLUNK_HOME` environment variable, or run as the `splunk` user |
| Enterprise: SHC Captain warning | Running on the cluster captain | Switch to an SHC member node |

### Debug Mode

Add `--debug` (Bash) or `-Debug_Mode` (PowerShell) for detailed diagnostics:

- **Console**: Color-coded messages (ERROR, WARN, API, SEARCH, TIMING, AUTH)
- **Log file**: `_export_debug.log` inside the archive
- **API calls**: Logs every request with endpoint, HTTP status, response size, and duration
- **Auth**: Logs token probe responses and final header format
- **Search jobs**: Logs SID dispatch, poll states, completion time

---

## Release Notes

> **Important:** the Enterprise script (`dma-splunk-export.sh`) and the Cloud scripts (`dma-splunk-cloud-export.sh` / `dma-splunk-cloud-export.ps1`) are versioned **independently**. Each release note below calls out which script(s) it applies to. Quick map:
>
> | Version | Enterprise (`dma-splunk-export.sh`) | Cloud Bash (`dma-splunk-cloud-export.sh`) | Cloud PowerShell (`dma-splunk-cloud-export.ps1`) |
> |---|:---:|:---:|:---:|
> | **v4.6.6** | — | ✅ (large-environment hardening + resume self-heal) | ✅ (parity with bash 4.6.6) |
> | **v4.6.5** | ✅ (`BASH_SOURCE` guard for test sourcing — no behavior change) | ✅ (intermediate — superseded by 4.6.6) | — |
> | **v4.6.4** | ✅ (eai:acl `where`-clause quoting) | — | — |
> | **v4.6.3** | ✅ (user-namespace dashboard de-dup) | — | — |
> | **v4.6.2** | — *(skipped — Enterprise jumped 4.6.0 → 4.6.3)* | ✅ (`search`-app inclusion) | ✅ (`search`-app + parity) |
> | **v4.6.1** | — *(skipped — same reason)* | ✅ (resume reliability) | ✅ (resume reliability) |
> | **v4.6.0** | ✅ | ✅ | ✅ |
>
> Customers running ONLY Enterprise can ignore the v4.6.1 + v4.6.2 + v4.6.6 entries (Cloud-only fixes; the Enterprise script always exported the `search` app and uses filesystem-based collection that doesn't have the per-app REST timeout-cascade failure mode v4.6.6 addresses). Customers running ONLY Cloud can ignore the v4.6.3 + v4.6.4 + v4.6.5 entries (Enterprise-only or no-op).

### v4.6.6 (Cloud only) — Large-environment hardening + resume self-heal

**Applies to:** `dma-splunk-cloud-export.sh` and `dma-splunk-cloud-export.ps1`. Enterprise unaffected — the Enterprise collection path doesn't have the per-app REST timeout-cascade failure mode v4.6.6 addresses.

Closes a structural failure mode where Splunk Cloud environments with many apps could exceed the 12-hour runtime cap and silently produce "complete-looking" archives that contained zero alerts. v4.6.6 closes the structural gap and adds resume validation that detects the failure mode automatically.

- **Single-call `collect_alerts`** — replaces the per-app `/saved/searches` REST loop with one stack-wide call partitioned by `acl.app` locally. Per-app `savedsearches.json` file shape is unchanged. Eliminates the redundant per-app transfer that caused the original timeout cascade.
- **OS-level timeout backstop is now fail-fast** — script exits at startup with install instructions if neither `timeout` (Linux) nor `gtimeout` (macOS via `brew install coreutils`) is on `PATH`. Previously this was a silent fallback that disabled the curl hung-request kill-switch. PowerShell's `Invoke-WebRequest` honors `-TimeoutSec` reliably, so this only applies to the Bash script.
- **Runtime cap is now fatal** — `exit 124` with resume instructions instead of `return 1`. Prevents the "looks complete but isn't" archive outcome.
- **Resume validation R1 (`is_valid_app_savedsearches`)** — on resume, rejects per-app `savedsearches.json` that is corrupt JSON, missing `.entry`, or contains foreign `acl.app` entries. Drops the resume sentinel and re-fetches.
- **Resume validation R2 (`validate_alerts_inventory_outputs` + `drop_analytics_checkpoint`)** — on resume, rejects the `alerts_inventory` checkpoint when its sentinel files are runtime-exceeded error shells. The stale checkpoint is invalidated and Q6 re-runs.
- **New flag `--validate-archive FILE`** — pre-flight integrity check. Extracts read-only, runs R1/R2, prints a verdict, exits. No Splunk connection required.
- **New flag `--clean-resume PHASES`** — explicit phase invalidation on resume. Comma-separated. Phases: `alerts`, `alerts_inventory`, `analytics`. Escape hatch when R1/R2 auto-detection isn't sufficient.
- **Banner now logs script version + auth + apps + resume mode** — makes post-mortem investigation possible from `_export.log` alone.
- Test infrastructure: `tests/` tree with bats-core 1.10.0 vendored, fixture generator, Splunk API mock library, baseline snapshots, and 27 unit tests. Both `*.sh` scripts now have a `BASH_SOURCE` guard so the harness can source them as libraries without invoking `main`.

### v4.6.5 (Enterprise only) — `BASH_SOURCE` guard for test sourcing

**Applies to:** `dma-splunk-export.sh`. No behavioral change when the script is run directly — the guard only affects what happens when the file is `source`d by the new test harness. Enterprise failure-mode hardening (timeout backstop + fatal runtime cap) is scheduled for a follow-up release.

### v4.6.4 (Enterprise only) — `eai:acl` field quoting in `where` clauses

**Applies to:** `dma-splunk-export.sh`. Cloud scripts unaffected (their helper has the same shape but isn't called with `eai:acl.*` field names today).

Customer hit three repeated `SEARCH FAILED` errors per pass when running with `--apps`:

```
SEARCH FAILED for 'Dashboard ownership mapping': "messages":[{"type":"FATAL",
  "text":"Error in 'where' command: The operator at ':acl.app IN (\"zy\") '
   is invalid."}...
SEARCH FAILED for 'Alert/saved search ownership mapping': ... ':acl.app IN (\"zy\") ...
SEARCH FAILED for 'Ownership summary by user':           ... ':acl.app IN (\"zy\") ...
```

Splunk's `where` parser rejects unquoted field names that contain `:`
or `.` (e.g. `eai:acl.app`) — the colon at position 3 is read as an
operator, then `.app` becomes a stray token, then `IN` makes no sense.
Splunk accepts the same field name when wrapped in single quotes:

```
| where 'eai:acl.app' IN ("zy")
```

The `get_app_in_clause` helper now wraps fields containing any
non-alphanumeric/underscore character in single quotes. Plain field
names (`app`, used in audit-log searches) stay unquoted so existing
behavior is unchanged. **Re-running the script after upgrading is
enough — no `--reset-collect` needed; the failed searches don't write
checkpoints, so resume picks up cleanly and the previously-failing
queries now succeed.**

### v4.6.3 (Enterprise only) — Dashboard de-dup across user namespaces (fixes 17h-ETA bug)

**Applies to:** `dma-splunk-export.sh`. Cloud scripts unaffected (Cloud's REST collection path doesn't have this failure mode).

Customer reported the Enterprise script's dashboard collection phase
showing a 17-hour ETA on an environment with hundreds of apps. Root
cause: the same dashboard ID appeared under multiple owner namespaces
(`servicesNS/<user>/<app>/...`) because Splunk exposes a separate
namespace per user who created or modified the dashboard. The collector
was fetching the same dashboard once per namespace, exploding both the
per-app dashboard count and the total ETA.

Fix: collection now de-duplicates by dashboard ID across the full
owner-namespace cross-product per app, restoring linear scaling. ETA
on the affected customer dropped from 17 hours to roughly 25 minutes.

This release also bundled three quality-of-life improvements:

- **`--resume-collect` archive-path validation** moved to argument-parse time so a typo or missing file fails immediately, not after authentication and app enumeration.
- **Live progress indicators** for REST counts and the global analytics queries — long phases now show a heartbeat instead of looking frozen.
- **SHC captain detection, saved-searches count, and toggle-display fixes** for SHC environments.

### v4.6.2 (Cloud only) — `search` app is now exported

**Applies to:** `dma-splunk-cloud-export.sh` and `dma-splunk-cloud-export.ps1`. Enterprise script always exported the `search` app — this fix brings the Cloud scripts back to parity.

Cloud's app-allowlist had `search` in the skip list as a "system app".
One customer had **674 dashboards (30% of total)** silently dropped
because users created their dashboards in the `search` app. The Cloud
scripts now include `search` by default.

### v4.6.1 (Cloud only) — Resume reliability for flaky search heads

**Applies to:** `dma-splunk-cloud-export.sh` and `dma-splunk-cloud-export.ps1`. Enterprise script unaffected — it reads configuration files directly from the Splunk filesystem and doesn't have the per-app REST hang failure mode that motivated these fixes.

A point release focused entirely on making `--resume-collect` actually
recover from partial dashboard / alert / knowledge-object collection
runs. No new features, no behavior changes when running fresh — only
fixes that matter when a previous export was interrupted or had per-app
REST timeouts against an overloaded Splunk Cloud search head.

**Bash (`dma-splunk-cloud-export.sh`) and PowerShell (`dma-splunk-cloud-export.ps1`):**

- **Per-app and per-dashboard resume in dashboard collection.** The
  collector now reuses cached `dashboard_list.json` files and skips
  individual dashboards already on disk. Previously, every resume run
  re-fetched everything in every app — including apps and dashboards
  that had already succeeded.
- **Per-app resume in alert / saved-search collection.** Apps whose
  `savedsearches.json` already exists are skipped on resume.
- **Per-app resume in knowledge-object collection.** Apps whose
  `macros.json` already exists are skipped entirely (the KO phase
  makes 8 REST calls per app — for an environment with 300 apps that
  is 2,400 REST calls saved on every resume).
- **Removed broken phase-level skip logic.** The previous "phase
  already complete" check returned true if even **one** app had data
  on disk, so apps that failed mid-phase were never re-tried by
  `--resume-collect`. The collectors above now handle skip decisions
  themselves at per-item granularity.

**Bash only:**

- **OS-level `timeout` backstop on every curl call.** We have observed
  individual REST calls hanging for 15-31 minutes against Splunk Cloud
  Victoria search heads despite curl's `--max-time 120` setting — some
  curl builds and TLS 1.3 + SNI network paths do not honour
  `--max-time` reliably. The script now wraps curl in `timeout` (or
  `gtimeout` on macOS) so the OS forcibly kills the request at
  `API_TIMEOUT + 30s`. The PowerShell script uses
  `Invoke-WebRequest -TimeoutSec`, which honours its timeout reliably,
  so no equivalent change was needed there.

**Recommended environment variables when running `--resume-collect` against a flaky search head:**

```bash
API_TIMEOUT=30 MAX_TOTAL_TIME=86400 ./dma-splunk-cloud-export.sh \
  --resume-collect <archive>.tar.gz \
  --stack <stack>.splunkcloud.com --token "$TOKEN"
```

`API_TIMEOUT=30` makes failed requests give up in 30s instead of 120s
(combined with the new OS backstop, this caps a failed retry triplet
at ~3 minutes instead of ~31 minutes). `MAX_TOTAL_TIME=86400` raises
the script's overall safety ceiling from 12 hours to 24 hours, giving
plenty of headroom for very large environments.

---

## Where to Upload the Archive

After the export completes, upload the `.tar.gz` archive:

- **DMA Curator Server** — migration planning, reporting, and team collaboration (recommended for all exports)
- **DMA Splunk App** — ad-hoc migration analysis (suitable for smaller archives)

Use the `_masked` variant when sharing outside your organization.

---

## Additional Documentation

These companion documents cover topics in greater depth:

| Document | Description |
|----------|-------------|
| [README-SPLUNK-CLOUD.md](docs_markdown/README-SPLUNK-CLOUD.md) | Detailed Cloud prerequisites, token creation walkthrough, and network requirements |
| [README-SPLUNK-ENTERPRISE.md](docs_markdown/README-SPLUNK-ENTERPRISE.md) | Detailed Enterprise prerequisites, SHC guidance, and filesystem requirements |
| [EXPORT-SCHEMA.md](docs_markdown/EXPORT-SCHEMA.md) | Complete archive file structure and field definitions |
| [SCRIPT-GENERATED-ANALYTICS-REFERENCE.md](docs_markdown/SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | Reference of all SPL queries used for analytics collection |
| [SPLUNK-CLOUD-EXPORT-SPECIFICATION.md](docs_markdown/SPLUNK-CLOUD-EXPORT-SPECIFICATION.md) | Technical specification for Cloud export internals |
| [SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md](docs_markdown/SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | Technical specification for Enterprise export internals |
| [INTERACTIVE-WALKTHROUGH.md](docs_markdown/INTERACTIVE-WALKTHROUGH.md) | Step-by-step visual guide to the interactive prompts |
