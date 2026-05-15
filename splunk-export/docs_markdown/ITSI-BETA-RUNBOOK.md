# DMA Splunk Export — ITSI Beta Runbook

**Script:** `dma-splunk-export-beta.sh` (v4.7.0-beta.2 or later)
**Audience:** Splunk admins running the export against ITSI-enabled Splunk Enterprise clusters
**Date:** 2026-05-15

## What this beta does

The beta script is functionally identical to the stable `dma-splunk-export.sh` with one additive layer: **automatic ITSI Comprehensive Cataloging**. When an ITSI app is detected on the Splunk instance, the script also collects the workspace-wide ITSI KV-store data — Glass Tables, Deep Dives, Services (including embedded KPIs), Entities, NEAPs, correlation-search metadata, KPI base searches, service templates, threshold templates, maintenance calendars, and Glass Table image assets — and writes them under a new `itsi_assets/` top-level directory in the archive.

Non-ITSI clusters see zero behavior change from stable.

## Prerequisites

For ITSI KV-store collection to succeed, three conditions must be met on the Splunk server you're exporting from:

| Requirement | Why | Verify with |
|---|---|---|
| The Splunk instance has SA-ITOA installed (canonical signal: `SA-ITOA` app present and enabled) | All ITSI REST endpoints live under the `SA-ITOA` namespace | `ls $SPLUNK_HOME/etc/apps/SA-ITOA/` |
| The Splunk REST API on port 8089 is reachable from wherever the script runs | KV-store has no filesystem-direct extraction path; **REST is the only supported way** to read ITSI's KV-store data on Splunk Enterprise. All Splunk-provided tools (`kvstore_to_json.py`, Backup/Restore UI) also use REST internally. | `curl -k https://<your-splunk-sh>:8089/services/server/info` |
| The auth user/token has `read_itsi_*` capability | Required to access `/servicesNS/nobody/SA-ITOA/itoa_interface/*` endpoints | Any `itoa_*` role, OR `sc_admin`/`admin` with `read_itsi_*` granted directly |

## The recommended way to run it

**Run the script directly on the Splunk search head.** This is the single most reliable setup for ITSI extraction on Enterprise:

```bash
# 1. Copy the beta script to the search head
scp dma-splunk-export-beta.sh <splunk-admin>@<splunk-sh>:/tmp/

# 2. ssh in and run it there
ssh <splunk-admin>@<splunk-sh>
cd /tmp
chmod +x dma-splunk-export-beta.sh

# 3. Run with --all-apps (or the explicit ITSI ecosystem app list — see below)
DMA_DEPLOYMENT_TARGET=prod ./dma-splunk-export-beta.sh \
    --host https://localhost:8089 \
    --token <a-token-with-read_itsi_*-capability> \
    --all-apps
```

### Why "on the SH" matters

The script's ITSI detection makes an HTTP call to the SH's management port (typically 8089). When run anywhere else, you need network connectivity AND firewall access to that port. Running on the SH means `localhost:8089` is always reachable from inside the SH — zero network or firewall complications.

**This does NOT mean "expose 8089 to the internet."** It just means the script needs to make local HTTP calls to the SH's mgmt endpoint. If your network team objects to opening 8089 externally, this on-SH approach completely sidesteps that conversation.

### Required `--apps` for full ITSI ecosystem coverage

The ITSI ecosystem includes more than just the `itsi` app. The complete recommended `--apps` set:

```
--apps itsi,SA-ITOA,SA-IndexCreation,SA-UserAccess,\
       SA-ITSI-ATAD,SA-ITSI-AlertCorrelation,SA-ITSI-CustomModuleViz,\
       SA-ITSI-DriftDetection,SA-ITSI-Licensechecker,SA-ITSI-MetricAD,\
       DA-ITSI-APPSERVER,DA-ITSI-ContentLibrary,DA-ITSI-DATABASE,\
       DA-ITSI-EUEM,DA-ITSI-LB,DA-ITSI-OS,DA-ITSI-STORAGE,\
       DA-ITSI-VIRTUALIZATION,DA-ITSI-WEBSERVER
```

Plus any environment-specific `DA-ITSI-CP-*` content packs the customer has installed.

**Easier alternative: just use `--all-apps`.** The KV-store layer is workspace-wide and won't be affected; `--all-apps` ensures you capture every companion app's classic surface (savedsearches.conf, props.conf, transforms.conf, internal dashboards).

If you DO pass a narrow `--apps` that excludes SA-ITOA + companions, the beta will print a **clear WARNING** at detection time naming exactly which companion apps you're missing. The export still proceeds, but you'll know the gap.

## Multi-cluster ITSI deployments

If the customer runs ITSI on **multiple search head clusters** (common for separating operational domains — e.g., "general ITSI" and "connectivity ITSI"):

1. **Run the script on each ITSI search head separately.** Each cluster has its own KV store.
2. **Send us each archive separately.** The DMA Server imports them as separate project tabs but can correlate cross-cluster signals.
3. **The script will correctly skip ITSI on non-ITSI clusters** (e.g., your general SIEM SH). It auto-detects via app presence.

For Dell-shaped deployments with 4 clusters where 2 have ITSI: you'll end up with 4 archives — 2 with `itsi_assets/` populated (the ITSI clusters), 2 with `_itsi_inventory.json` marked `collected: false` reason `itsi_not_installed` (the non-ITSI clusters). That's correct.

## How to verify ITSI collection succeeded

After the export completes, check `itsi_assets/_itsi_inventory.json` in the archive:

```json
{
  "collected": true,
  "reason": null,
  "itsi_version": "4.21.2",
  "counts": {
    "glass_tables": 12,
    "deep_dives": 8,
    "services": 41,
    "kpis": 247,
    "entities": 1832,
    ...
  },
  "errors": []
}
```

`collected: true` means the KV-store fetch succeeded. Non-zero counts confirm what was retrieved. An empty `errors[]` array confirms no per-endpoint partial failures.

Also check `itsi_assets/_collection_trace.log` for the per-HTTP-call trace if anything looks off:

```
2026-05-15T14:22:01Z GET /servicesNS/nobody/SA-ITOA/itoa_interface/glass_table?limit=1 200 4823 145
2026-05-15T14:22:02Z GET /servicesNS/nobody/SA-ITOA/itoa_interface/glass_table?limit=500&offset=0 200 1234567 892
```

## Common failure modes

### Failure: `_itsi_inventory.json` shows `collected: false` reason `rest_unreachable`

Means the script couldn't reach `<splunk-host>:8089`. Most common causes on Enterprise:

1. **Script run from a host that can't reach the SH's port 8089.**
   FIX: run the script on the SH itself (recommended above). Localhost:8089 is always reachable.

2. **Firewall between the export host and SH blocks port 8089.**
   FIX: Open 8089 between the two boxes (talk to your network team), or use option 1.

3. **Wrong `--host` value** (pointing to web UI port 8000 instead of mgmt port 8089).
   FIX: `--host=https://<splunk-sh>:8089` (NOT `:8000`).

4. **SH's splunkd has 8089 bound to localhost only.**
   FIX: SHC captains usually serve 8089 cluster-wide; if locked down by config, either reconfigure or use option 1.

### Failure: `_itsi_inventory.json` shows `collected: false` reason `missing_capability`

The auth user lacks `read_itsi_*` capabilities. Splunk admin needs to either:

- **(a)** Assign an `itoa_*` role to the user (e.g., `itoa_admin`, `itoa_team_admin`)
- **(b)** Grant `read_itsi_*` capabilities directly to the user's existing role (`sc_admin`, `admin`, or custom)

Either path is fine — the script detects whichever you choose via the endpoint probe response.

### Failure: `_itsi_inventory.json` shows `collected: false` reason `itsi_not_installed`

SA-ITOA isn't installed on this Splunk instance. This is the **correct** outcome for non-ITSI clusters. If this happens on a cluster you BELIEVE has ITSI, verify SA-ITOA is actually installed and enabled:

```bash
ls $SPLUNK_HOME/etc/apps/SA-ITOA/
$SPLUNK_HOME/bin/splunk display app SA-ITOA -auth <user>:<pass>
```

### WARNING during a successful run: "Your --apps selection EXCLUDES the SA-ITOA companion app set"

You ran with a narrow `--apps` that captures the `itsi` app but misses SA-ITOA's classic surface. The KV-store layer WAS collected (workspace-wide), but you'll be missing SA-ITOA's savedsearches.conf, internal dashboards, etc.

To fix: re-run with `--all-apps` OR with the expanded `--apps` list from above. You can also use `--resume-collect <archive.tar.gz>` to add the missing companion apps WITHOUT re-fetching everything else.

## What gets collected (and what doesn't)

| Data class | Source | Collected? |
|---|---|---|
| The `itsi` app's classic dashboards (XML), savedsearches.conf, props.conf, transforms.conf, lookups | Filesystem | ✓ (by standard collectors) |
| SA-ITOA + companion apps' classic surface (when `--apps` includes them or you use `--all-apps`) | Filesystem | ✓ (by standard collectors) |
| Glass Tables (KV store `itsi_pages` collection) | REST | ✓ (when REST works) |
| Deep Dives (KV store `itsi_pages` collection) | REST | ✓ (when REST works) |
| Services + embedded KPIs (KV store `itsi_services`) | REST | ✓ (when REST works) |
| KPI Base Searches (KV store `itsi_kpi_base_search`) | REST | ✓ (when REST works) |
| Service Templates (KV store `itsi_base_service_templates`) | REST | ✓ (when REST works) |
| Entities + Entity Types (KV store `itsi_entities`, `itsi_entity_types`) | REST | ✓ (when REST works) |
| NEAPs (KV store `itsi_notable_event_aggregation_policy`) | REST | ✓ (when REST works) |
| Correlation Searches metadata (KV store `itsi_correlation_searches`) | REST | ✓ (when REST works) |
| Maintenance Calendars (KV store `itsi_maintenance_calendars`) | REST | ✓ (when REST works) |
| Threshold Templates (KV store `itsi_kpi_threshold_templates`) | REST | ✓ (when REST works) |
| Glass Table image assets (KV store `SA-ITOA_files`) | REST | ✓ (when REST works) |

## Limitations and known constraints

- **REST is the only supported path** for ITSI KV-store extraction on Enterprise. There is no filesystem-direct alternative.
- **Splunk Cloud customers**: REST API access on port 8089 is gated by Splunk Support. If you don't already have it enabled, file a Support case before running this script.
- **The script gracefully skips** the KV-store layer on REST failure. The export completes regardless — only the `itsi_assets/` directory is affected. Classic surface (dashboards, savedsearches.conf, .conf files) is always collected via filesystem.
- **Cloud parity scripts** (`dma-splunk-cloud-export.sh`, `dma-splunk-cloud-export.ps1`) do NOT yet have the ITSI beta changes. Cloud customers should keep using the stable cloud-export scripts until Cloud parity ships in a later beta tag.

## After the export

Send the resulting `.tar.gz` archive(s) to the DMA team. We import them into the curator and run translation analysis. The `itsi_assets/` directory and the new dashboard subtypes (`<itsi>/dashboards/glasstable/`, `<itsi>/dashboards/deepdive/`) are visible to the DMA Server importer as soon as it's ready to consume them (Phase 1 importer work is separate from this collection step).

## Questions / issues

Anything unexpected? Send us:

1. The `.tar.gz` archive (or just `itsi_assets/_itsi_inventory.json` + `itsi_assets/_collection_trace.log` + the console log)
2. The exact CLI invocation you used (`--apps`, `--host`, etc.)
3. Whether you ran on the SH directly or from a separate host

That trio is enough to triage any ITSI-collection issue.
