# DMA Splunk Enterprise Export — Changelog

## v4.6.6 (May 2026) — large-environment hardening

Closes a structural failure mode where Splunk Cloud environments with
many apps could exceed the 12-hour runtime cap and silently produce
"complete-looking" archives that contained zero alerts.

### Cloud scripts (`dma-splunk-cloud-export.sh` 4.6.3 → 4.6.6, `dma-splunk-cloud-export.ps1` 4.6.3 → 4.6.6)

- **Single-call `collect_alerts`** — replaces the per-app `/saved/searches`
  REST loop with one stack-wide call partitioned by `acl.app` locally.
  Per-app savedsearches.json file shape is unchanged. Eliminates the
  redundant per-app transfer that caused the original timeout cascade.
- **OS-level timeout backstop now fail-fast** — script exits at startup
  with install instructions if neither `timeout` (Linux) nor `gtimeout`
  (macOS via `brew install coreutils`) is on PATH. Previously this was
  a silent fallback that disabled the curl hung-request kill-switch.
- **Runtime cap is now fatal** — `exit 124` with resume instructions
  instead of `return 1`. Prevents the "looks complete but isn't" archive
  outcome.
- **Resume validation (R1, R2)**:
  - R1 (`is_valid_app_savedsearches`): rejects per-app `savedsearches.json`
    that's corrupt JSON, missing `.entry`, or has foreign `acl.app` entries.
    Drops the resume sentinel and re-fetches.
  - R2 (`validate_alerts_inventory_outputs`): rejects `alerts_inventory`
    checkpoint when its sentinel files are runtime-exceeded error shells.
    `drop_analytics_checkpoint` invalidates the stale key, Q6 re-runs.
- **New flag `--validate-archive FILE`** — pre-flight integrity check.
  Extracts read-only, runs R1/R2, prints verdict, exits. No Splunk connection.
- **New flag `--clean-resume PHASES`** — explicit phase invalidation
  on resume. Comma-separated. Phases: `alerts`, `alerts_inventory`,
  `analytics`. Escape hatch when R1/R2 auto-detection isn't enough.
- **Banner now logs script version + auth + apps + resume mode** — makes
  post-mortem investigation possible from `_export.log` alone.
- Removed accidental duplicate `SCRIPT_VERSION` declaration in cloud-bash.

### Test infrastructure

- New `tests/` tree with bats-core 1.10.0 vendored, fixture generator,
  Splunk API mock library, baseline snapshots, and 27 unit tests.
- BASH_SOURCE guard on both `*.sh` scripts so they can be sourced as
  libraries by the test harness without invoking `main`.

### Enterprise (`dma-splunk-export.sh` 4.6.4 → 4.6.5)

- BASH_SOURCE guard added (test infrastructure prerequisite). No behavioral
  change when executed normally. Failure-mode hardening (timeout + cap) is
  scheduled for v4.6.6 in the next release cycle.

## v4.6.0 (April 2026)

### Usage Analytics Overhaul — Global Aggregates Replace Detailed Queries

The `collect_usage_analytics` function has been fundamentally restructured. Previously it ran ~40 individual SPL search jobs (users_most_active, activity_by_role, users_inactive, daily_active_users, sourcetypes_searched, indexes_queried, index_sizes, daily_volume_by_index, daily_volume_by_sourcetype, daily_volume_summary, daily_events_by_index, hourly_volume_pattern, top_indexes_by_volume, top_sourcetypes_by_volume, top_hosts_by_volume, ingestion_infrastructure/\*, alert_migration/\*, rbac/\*, saved_searches_by_owner, scheduler_load). All of those individual jobs have been removed.

**What `collect_usage_analytics` does now:**
- Ownership mapping: 3 `| rest` queries (dashboard, saved search, alert ownership)
- REST metadata: 3 curl calls for supplemental metadata
- Generates `USAGE_INTELLIGENCE_SUMMARY.md`

**What produces the Explorer data:**
- 6 global aggregate queries in `collect_app_analytics` now produce all data that the DMA Explorer consumes. These queries run per-app and write to `dma_analytics/usage_analytics/`.

### Search Query Improvements

- Dashboard views now use the `provenance` field (search_type=dashboard was unreliable)
- All `_audit` queries optimized: `sourcetype=audittrail` + `info=granted` (tsidx-level filtering)
- Search type breakdown derived from `provenance`/`search_id` (matches Cloud script logic)
- Alert firing queries: added `| fields` before `| stats` (reduces indexer memory on large environments)
- Removed ALL `| head N` limits from usage queries (was silently dropping data on large environments)

### Data Collection Changes

- Default `USAGE_PERIOD` changed to `30d` (was `7d`) for comprehensive migration planning
- `saved_searches_all.json`: uses `f=` field selection (was 256MB+ raw REST dump on large environments)
- `alert_ownership.json`: uses `f=` field selection (was duplicate 256MB+ REST dump)
- Usage collection ON by default (now explicit)

### Manifest and Checkpoint Updates

- Updated manifest builder (`usage_intelligence` section) to reference global aggregate files
- Updated `has_collected_data` check to use `dashboard_ownership.json` instead of `users_most_active.json`
- Updated checkpoint clearing to remove old detailed checkpoint names
- `--resume-collect` with usage active now clears usage checkpoints to force re-collection

### Other

- `USAGE_INTELLIGENCE_SUMMARY.md` content updated to reference v4.6.0 global files
- Dynamic `daily_avg_gb` calculation uses actual `USAGE_PERIOD` days (was hardcoded `/7`)
- Dramatically reduced failure risk by minimizing the total number of search jobs dispatched

## v4.4.0

- Added `--proxy URL` flag: routes all curl calls through an HTTP proxy
- Added `--skip-internal` flag: skips `index=_audit`/`_internal` searches (for restricted accounts)
- Added `--test-access` flag: pre-flight API check across all categories (no export written)
- Added `--remask FILE` flag: re-anonymizes an existing archive without connecting to Splunk
- Added `--resume-collect FILE` flag: resumes a previously interrupted export from archive
- Expanded RBAC: now collects capabilities, LDAP groups/config, SAML groups/config
- Progressive analytics checkpointing: each task group saves a checkpoint on success; resume skips already-completed groups automatically
- `collect_system_macros`, `collect_app_configs` (per-app), `collect_dashboard_studio`, `collect_app_analytics` (per-app) all wrapped with checkpoint guards for resume support
- `RBAC`, `usage_analytics`, `system_info`, `index_stats` phases wrapped with `has_collected_data` guards for resume support

## v4.3.0

- Added `--token TOKEN` flag for API token authentication (recommended for automation)
- Password authentication now uses Python URL-encoding via stdin (safe for special characters: `$`, backtick, `"`, `\`)
- Session key auth replaces curl basic auth (`-u user:pass`) throughout all API calls
- Added `--analytics-period N` flag (e.g. `7d`, `30d`, `90d`); skips interactive period prompt when provided
- Added `--usage` and `--rbac` enable flags to match Cloud script interface
- Changed `USAGE_PERIOD` default from `30d` to `7d` (matches Cloud default)
- Async search dispatch: analytics searches now use `exec_mode=normal` + `dispatchState` polling
- Adaptive poll interval (5s→30s) and job cancellation on timeout replace fixed 1s polling
- Token-only invocation auto-enables `NON_INTERACTIVE` mode
- All API guards updated to check `AUTH_HEADER` (works for both token and session key auth)

## v4.2.4

- Anonymization now creates two archives: original (untouched) + `_masked` (anonymized)
- Preserves original data in case anonymization corrupts files
- RBAC/Users collection now OFF by default (use `--rbac` to enable)
- Usage analytics collection now OFF by default (use `--usage` to enable)
- Faster performance defaults: batch size 250 (was 100), API delay 50ms (was 250ms)
- Optimized usage analytics queries with sampling for expensive regex extractions
- Changed `latest()` to `max()` for faster time aggregations
- Moved filters to search-time for better performance
