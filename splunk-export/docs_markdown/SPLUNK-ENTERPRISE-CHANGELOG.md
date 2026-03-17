# DMA Splunk Enterprise Export — Changelog

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
