# DMA Splunk Cloud Export - Beta

**Version**: 4.4.0 (Beta)
**Script**: `dma-splunk-cloud-export_beta.sh`
**Last Updated**: February 2026

> **BETA NOTICE**: This is a beta release for real-world testing. It introduces new features and fixes that are not yet in the stable `dma-splunk-cloud-export.sh` script. Use this script when you need the latest capabilities or have been directed here by the DMA team. Report issues to the DMA team with your export log.

---

## What's New in Beta v4.4.0

### Pre-Flight Access Verification (`--test-access`)

A brand-new mode that verifies your API token has the correct permissions **before** running a full export. It runs 9 read-only checks against every data collection category and produces a pass/fail report with actionable resolution steps for any failures.

This eliminates the #1 support issue: running a multi-hour export only to discover halfway through that your token lacks the required permissions.

```bash
# Quick access check (required categories only)
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token "$TOKEN"

# Full access check including RBAC and usage analytics
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token "$TOKEN" --rbac --usage

# Full check but skip _internal index (common restriction in Splunk Cloud)
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token "$TOKEN" --usage --skip-internal
```

**No data is exported.** This is a read-only check that makes minimal API calls (count=1 on each endpoint) and exits with a summary report.

### Usage Collection Fixes

- Improved handling when `_internal` or `_audit` indexes are restricted (common in Splunk Cloud)
- New `--skip-internal` flag to bypass `_internal` index queries entirely
- Better error messages when usage analytics searches fail due to permission restrictions

---

## Quick Start

```bash
# Run from YOUR machine (not on Splunk Cloud)
# You need network access to your Splunk Cloud instance on port 8089

# Step 1: Verify access first (recommended)
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token "$TOKEN" --rbac --usage

# Step 2: If all checks pass, run the full export
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --token "$TOKEN" --rbac --usage
```

---

## `--test-access` Mode

### How It Works

When you pass `--test-access`, the script:

1. Connects to your Splunk Cloud instance
2. Determines a test app (uses `--apps` if provided, otherwise picks the first user app)
3. Runs 9 access checks against the REST API endpoints used during export
4. Prints a real-time status line for each check (PASS/FAIL/WARN/SKIP)
5. Prints a summary table with a final verdict
6. Exits with a status code (no export is performed)

### The 9 Access Checks

| # | Check | Level | What It Tests | Endpoint |
|---|-------|-------|---------------|----------|
| 1 | **System Info** | CRITICAL | Can reach Splunk REST API and authenticate | `/services/server/info` |
| 2 | **Configurations** | REQUIRED | Can read Splunk configuration objects | `/servicesNS/-/-/configs/conf-indexes` |
| 3 | **Dashboards** | REQUIRED | Can read dashboard definitions per app | `/servicesNS/-/{app}/data/ui/views` |
| 4 | **Saved Searches / Alerts** | REQUIRED | Can read saved searches and alert definitions | `/servicesNS/-/{app}/saved/searches` |
| 5 | **RBAC (users/roles)** | OPTIONAL | Can read users and roles (requires `--rbac`) | `/services/authentication/users`, `/services/authorization/roles` |
| 6 | **Knowledge Objects** | REQUIRED | Can read macros, props.conf, and lookups | `/servicesNS/-/{app}/admin/macros`, `conf-props`, `lookup-table-files` |
| 7 | **App Analytics (_audit)** | OPTIONAL | Can search `_audit` index (requires `--usage`) | `search index=_audit action=search` |
| 8 | **Usage Analytics (_internal)** | OPTIONAL | Can search `_internal` index (requires `--usage`) | `search index=_internal sourcetype=scheduler` |
| 9 | **Indexes** | REQUIRED | Can read index definitions and metadata | `/services/data/indexes` |

### Check Levels

| Level | Meaning |
|-------|---------|
| **CRITICAL** | Export cannot run at all if this fails (connectivity / auth) |
| **REQUIRED** | Core data collection will be missing if this fails |
| **OPTIONAL** | Can be skipped with flags (`--no-rbac`, `--no-usage`, `--skip-internal`) |

### Status Values

| Status | Meaning |
|--------|---------|
| **PASS** | Endpoint accessible, data returned |
| **FAIL** | Endpoint denied or returned an error — includes cause and resolution |
| **WARN** | Partial access (e.g., users OK but roles denied) |
| **SKIP** | Check not applicable (e.g., RBAC skipped because `--rbac` not passed) |

### Verdict Logic

The summary report ends with one of four verdicts:

| Verdict | Condition |
|---------|-----------|
| **All access checks passed. You are ready to run a full export.** | 0 failures, 0 warnings |
| **All required checks passed (some warnings).** | 0 failures, 1+ warnings |
| **Some checks failed. Export will run but some data will be missing.** | 1+ non-critical failures |
| **Critical failures detected. Cannot run export until resolved.** | System Info (check #1) failed |

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All checks passed (or only warnings) |
| `1` | Critical failure — cannot run export |
| `2` | Non-critical failures — export will run with missing data |

### Example Output

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ACCESS VERIFICATION TEST                                                │
│                                                                          │
│  Testing API access for each data collection category.                   │
│  This verifies your permissions before running a full export.            │
│                                                                          │
│  No data will be exported. This is a read-only check.                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

  Running 9 access checks...

  [OK  ]  System Info                       Splunk v9.1.2312.200
  [OK  ]  Configurations (indexes)          1 entries
  [OK  ]  Dashboards (myapp)                1 found
  [OK  ]  Saved Searches / Alerts (myapp)   1 found
  [SKIP]  RBAC (users/roles)                Not requested (add --rbac)
  [OK  ]  Knowledge Objects (myapp)         macros, props, lookups
  [SKIP]  App Analytics (_audit)            Not requested (add --usage)
  [SKIP]  Usage Analytics (_internal)       Not requested (add --usage)
  [OK  ]  Indexes                           1 found

  Passed: 6  Failed: 0  Warnings: 0  Skipped: 3  Total: 9

  VERDICT: All access checks passed. You are ready to run a full export.
```

### Failure Example

When a check fails, the script prints diagnostic details inline:

```
  [FAIL]  Configurations (indexes)          Access denied
         Endpoint:   /servicesNS/-/-/configs/conf-indexes
         Cause:      Cannot read Splunk configuration objects
         Resolution: User needs list_settings or admin_all_objects capability
```

---

## `--skip-internal` Flag

Many Splunk Cloud environments restrict access to the `_internal` index. When this is the case, usage analytics searches that query `_internal` will fail.

Use `--skip-internal` to skip all searches that require the `_internal` index:

```bash
# Export with usage analytics but skip _internal searches
./dma-splunk-cloud-export_beta.sh --stack acme.splunkcloud.com --token "$TOKEN" --usage --skip-internal

# Test access with the same configuration
./dma-splunk-cloud-export_beta.sh --test-access --stack acme.splunkcloud.com --token "$TOKEN" --usage --skip-internal
```

The script will still collect usage data from `_audit` (dashboard views, search activity). Only the scheduler-based analytics from `_internal` are skipped.

---

## Required Permissions

> **Insufficient permissions are the #1 cause of export failures.** Run `--test-access` first to verify.

### Option 1: Use the `sc_admin` Role (Recommended)

1. Create a user with the `sc_admin` role in Splunk Cloud
2. Create an API token for that user (Settings > Tokens)
3. Use that token with the export script

### Option 2: Minimum Required Capabilities

If you cannot use `sc_admin`, your user/token needs these capabilities:

| Capability | What It Enables |
|------------|-----------------|
| `admin_all_objects` | Access dashboards/alerts in ALL apps |
| `list_settings` | Read server configuration |
| `rest_properties_get` | Make REST API calls |
| `search` | Run usage analytics queries |
| `list_users` | Collect user data (for `--rbac`) |
| `list_roles` | Collect role data (for `--rbac`) |
| `list_indexes` | Collect index metadata |

**Plus, for `--usage` analytics**, the user needs access to search these indexes:
- `_internal` (or use `--skip-internal` to bypass)
- `_audit`

### Verify Before Running

Use `--test-access` to verify all permissions in one step:

```bash
./dma-splunk-cloud-export_beta.sh --test-access \
  --stack acme.splunkcloud.com \
  --token "$TOKEN" \
  --rbac --usage
```

Or manually test your token can list apps:

```bash
curl -s -k -H "Authorization: Bearer YOUR_TOKEN" \
  "https://your-stack.splunkcloud.com:8089/services/apps/local?output_mode=json&count=0" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Apps found: {len(d.get(\"entry\",[]))}')"
```

If this returns `Apps found: 0`, your token lacks `admin_all_objects`.

**Full permissions documentation**: See [README-SPLUNK-CLOUD.md](docs_markdown/README-SPLUNK-CLOUD.md#3-required-permissions-critical---read-this-carefully)

---

## All CLI Flags

| Flag | Description |
|------|-------------|
| `--stack URL` | Splunk Cloud stack URL (e.g., `acme.splunkcloud.com`) |
| `--token TOKEN` | API token for authentication |
| `--user USER` | Username (if not using token) |
| `--password PASS` | Password (if not using token) |
| `--all-apps` | Export all applications |
| `--apps LIST` | Comma-separated list of apps to export |
| `--output DIR` | Output directory |
| `--rbac` | Collect RBAC/users data (OFF by default) |
| `--usage` | Collect usage analytics (OFF by default) |
| `--skip-internal` | Skip searches requiring `_internal` index |
| `--scoped` | Scope all collections to selected apps only |
| `--proxy URL` | Route all connections through a proxy server |
| `--resume-collect FILE` | Resume a previous interrupted export from a `.tar.gz` archive |
| `--test-access` | **NEW** - Pre-flight access verification (no export) |
| `-d`, `--debug` | Enable verbose debug logging |
| `--anonymize` | Enable data anonymization (two-archive output) |
| `-y` | Auto-confirm all prompts (non-interactive mode) |
| `--help` | Show help text |

---

## Differences from Stable Script

| Aspect | Stable (`dma-splunk-cloud-export.sh`) | Beta (`dma-splunk-cloud-export_beta.sh`) |
|--------|---------------------------------------|------------------------------------------|
| **Version** | 4.3.0 | 4.4.0 |
| **`--test-access`** | Not available | 9-check pre-flight verification |
| **`--skip-internal`** | Not available | Skip `_internal` index queries |
| **Usage collection** | May fail silently on restricted indexes | Improved error handling and diagnostics |
| **Stability** | Production-tested | Beta — for real-world validation |

---

## Recommended Workflow

```
1. RUN --test-access          Verify permissions (30 seconds)
   ↓
2. FIX any failures           Follow resolution steps in the report
   ↓
3. RE-RUN --test-access       Confirm all checks pass
   ↓
4. RUN full export            Confident that permissions are correct
```

```bash
# Step 1: Verify
./dma-splunk-cloud-export_beta.sh --test-access \
  --stack acme.splunkcloud.com --token "$TOKEN" --rbac --usage

# Step 2-3: Fix and re-verify (repeat until all pass)

# Step 4: Export
./dma-splunk-cloud-export_beta.sh \
  --stack acme.splunkcloud.com --token "$TOKEN" --rbac --usage
```

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*
