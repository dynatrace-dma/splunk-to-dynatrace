# Parity Work: dma-splunk-export.sh → v4.4.0

## Context

`dma-splunk-export.sh` (Splunk Enterprise) had fallen significantly behind
`dma-splunk-cloud-export_beta.sh` (Splunk Cloud, v4.5.6). The two scripts serve
different deployment targets but should be functionally equivalent where the
underlying Splunk platform allows. This plan tracked all gaps identified and the
changes made to close them.

**All 11 items are now complete. Script is at v4.4.0.**

---

## File Modified

[splunk-export/dma-splunk-export.sh](splunk-export/dma-splunk-export.sh)

---

## Completed Changes

### 1. Async Search Dispatch ✅
**Why:** All analytics searches were blocking (`exec_mode=blocking`), causing timeouts
on large environments with no way to resume mid-search.

**What was done:**
- Replaced synchronous `run_usage_search()` with async dispatch: `exec_mode=normal`
  returns a SID immediately; script polls `/services/search/jobs/{sid}` on `dispatchState`
- Adaptive poll interval: starts at 5s, increases by 5s up to a 30s cap
- Job cancelled via `action=cancel` POST on timeout to free search quota

---

### 2. Token Authentication + Safe Password Encoding ✅
**Why:** Only username/password via curl basic auth (`-u user:pass`) was supported.
No token support, and basic auth is unsafe for passwords containing `$`, backticks, `"`, `\`.

**What was done:**
- Added `--token TOKEN` flag; sets `AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"`
- Password path now POSTs to `/services/auth/login`, extracts `sessionKey`, sets
  `AUTH_HEADER="Authorization: Splunk $SESSION_KEY"`
- Password URL-encoded via Python stdin (never passed on command line)
- All ~20+ curl calls migrated from `-u user:pass` to `-H "$AUTH_HEADER"`
- Token-only invocation auto-enables `NON_INTERACTIVE` mode

**Auth header formats confirmed correct** against official Splunk REST API docs and
Python SDK: `Splunk` prefix for session keys (all versions), `Bearer` prefix for
JWT tokens (requires Enterprise 7.3+). The two prefixes are NOT interchangeable.

---

### 3. `--analytics-period` Flag ✅
**Why:** Analytics window was set via an interactive prompt only; non-interactive
runs couldn't override the default without manual input.

**What was done:**
- Added `--analytics-period N` CLI flag (e.g., `7d`, `30d`, `90d`)
- Default changed from `30d` to `7d` (matches Cloud default)
- `select_usage_period()` is skipped when flag is provided (`ANALYTICS_PERIOD_SET=true`)

---

### 4. RBAC and Usage Default to OFF ✅
**Why:** RBAC and usage collection were ON by default; v4.2.4 started the flip but
never completed it. Cloud has them OFF by default because they're slow and rarely
needed for basic migration scoping.

**What was done:**
- `COLLECT_RBAC=false`, `COLLECT_USAGE=false` as defaults (lines 193–194)
- `--rbac` and `--usage` flags enable them explicitly (opt-in, not opt-out)
- `--no-rbac` / `--no-usage` kept as no-ops for backwards compatibility

---

### 5. `--test-access` Pre-flight Mode ✅
**Why:** No way to verify API connectivity and permissions without attempting a full
export. Auth or permission issues only surfaced after minutes of work.

**What was done:**
- Added `--test-access` flag; sets `TEST_ACCESS_MODE=true`
- `run_test_access()` function checks every REST endpoint category (server info,
  dashboards, alerts, RBAC, analytics, indexes, knowledge objects) and prints
  PASS/FAIL/WARN/SKIP per category with an overall verdict
- Called in `main()` after `authenticate_splunk()`; exits immediately after — no data written

---

### 6. `--remask` Re-anonymization ✅
**Why:** If anonymization failed or needed updating, users had to re-run the full
export from scratch just to get a correctly masked archive.

**What was done:**
- Added `--remask FILE` flag; sets `REMASK_MODE=true`
- `remask_archive()` function extracts archive to temp dir, re-runs `anonymize_export`,
  repacks to `${original_name}_masked.tar.gz`
- Called early in `main()` before any Splunk connection; exits after completion

---

### 7. `--resume-collect` ✅
**Why:** Interrupted exports had no formal resume path; users had to restart from scratch
or manually edit checkpoint files.

**What was done:**
- Added `--resume-collect FILE` flag; sets `RESUME_MODE=true`
- `resume_from_archive()` extracts archive to `/tmp`, sets `EXPORT_DIR`, `LOG_FILE`,
  `CHECKPOINT_FILE`, etc. to point at extracted directory
- `create_export_directory` is skipped in resume mode
- Collection phases guarded via `has_collected_data()` (checks for sentinel files):
  `system_info`, `rbac`, `usage_analytics`, `indexes`
- App-level phases guarded via `.analytics_checkpoint` file (see item 11):
  `system_macros`, `app_configs:<appname>`, `dashboard_studio`, `app_analytics:<appname>`

---

### 8. `--proxy` Support ✅
**Why:** Environments behind a corporate proxy couldn't reach the Splunk REST API.

**What was done:**
- Added `--proxy URL` flag; sets `PROXY_URL` and `CURL_PROXY_ARGS="-x $PROXY_URL"`
- `$CURL_PROXY_ARGS` is unquoted in all curl calls so it expands to nothing when empty
- Injected into `splunk_api_call()`, `authenticate_splunk()`, and all inline curl calls

---

### 9. Expanded RBAC Endpoints (LDAP, SAML, Capabilities) ✅
**Why:** Enterprise environments commonly use LDAP and SAML; only users and roles
were collected previously, missing critical auth infrastructure context.

**What was done:**
- `collect_rbac()` now also collects:
  - `/services/authorization/capabilities` → `capabilities.json`
  - `/services/admin/LDAP-groups` → `ldap_groups.json`
  - `/services/authentication/providers/LDAP` → `ldap_config.json`
  - `/services/admin/SAML-groups` → `saml_groups.json`
  - `/services/authentication/providers/SAML` → `saml_config.json`
- All new endpoints handle 404 gracefully (writes placeholder JSON; not all instances
  have LDAP/SAML configured)

---

### 10. `--skip-internal` Flag ✅
**Why:** Non-admin accounts or hardened Enterprise instances may not have access to
`index=_audit` and `index=_internal`. Without a skip flag, those searches would
silently fail or error.

**What was done:**
- Added `--skip-internal` flag; sets `SKIP_INTERNAL=true`
- Guards added to `collect_usage_analytics()` and `collect_app_analytics()`: both
  return early with a warning when flag is set
- Displayed in the non-interactive mode banner

---

### 11. Progressive Checkpointing ✅
**Why:** Checkpointing existed only at coarse phase boundaries. An interrupted run
during the 30+ minute usage analytics or a 200-app config collection would lose all
progress within that phase.

**What was done:**

**`collect_usage_analytics()` — 9 task groups, each checkpointed:**
`usage_user_activity`, `usage_data_source`, `usage_daily_volume`,
`usage_ingestion_infra`, `usage_ownership`, `usage_alert_migration`,
`usage_user_role_mapping`, `usage_saved_search_metadata`, `usage_scheduler_stats`

**`collect_app_analytics()` — per-app checkpoint:**
- Guard at top: `has_analytics_checkpoint "app_analytics:$app"` → early return if done
- Save at bottom: `save_analytics_checkpoint "app_analytics:$app"` after all 8 searches

**`main()` — additional phase guards:**
- `collect_system_macros` → `has_analytics_checkpoint "system_macros"`
- `collect_app_configs "$app"` loop → `has_analytics_checkpoint "app_configs:$app"` per app
  (histogram counting still runs unconditionally so the dashboard histogram is accurate on resume)
- `collect_dashboard_studio` → `has_analytics_checkpoint "dashboard_studio"`

**Checkpoint infrastructure** (`$EXPORT_DIR/.analytics_checkpoint`):
- `save_analytics_checkpoint "key"` appends key to file
- `has_analytics_checkpoint "key"` greps for exact line match
- Returns non-zero (no skip) if file doesn't exist — correct for fresh runs
- In resume mode, `resume_from_archive()` points `EXPORT_DIR` at the extracted archive,
  which contains the existing checkpoint file — all prior keys are automatically recognized
- Per-app keys use `:` namespace (`app_configs:myapp`, `app_analytics:myapp`) to avoid
  colliding with global analytics keys (`usage_user_activity`, etc.)

---

## Version History

| Version | Changes |
|---|---|
| 4.2.4 | Baseline (two-archive anonymization, RBAC/usage flip started but incomplete) |
| 4.3.0 | Items 1–3: async search, token auth, `--analytics-period` |
| 4.4.0 | Items 4–11: proxy, skip-internal, test-access, remask, resume-collect, expanded RBAC, progressive checkpointing |
