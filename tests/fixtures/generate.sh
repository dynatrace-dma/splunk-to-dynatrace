#!/usr/bin/env bash
# Synthetic fixture generator for Splunk Cloud /servicesNS/-/-/saved/searches
# REST responses. Produces deterministic JSON matching the real REST envelope
# shape so the replay harness can feed it to both old and new collect_alerts.
#
# Each generated entry has ~50 keys in `content`, mirroring the real-world
# content envelope observed in customer extracts (HCA Healthcare etc.):
# - 5 alert/search "kinds" cycled deterministically (plain, scheduled,
#   email-alert, webhook+slack-alert, custom-condition-alert)
# - display.visualizations.* keys (converter must preserve all content keys)
# - durable.*, dispatch.*, schedule_*, request.* keys for realism
# - One regression-bait entry with custom third-party action.* keys
#
# Usage:
#   generate.sh <num_apps> <entries_per_app> <output_file>

set -euo pipefail

NUM_APPS=${1:?"missing num_apps"}
ENTRIES_PER_APP=${2:?"missing entries_per_app"}
OUTPUT=${3:?"missing output file"}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# Realistic base content keys observed across HCA, Dell, Emirates, Costco
# successful extracts. Every entry gets these — the converter has no field
# allowlist (archiveParser.convertParsedJsonToConf), so all of these flow
# through to the parsed conf and downstream.
BASE_CONTENT='{
  "search": "PLACEHOLDER",
  "description": "PLACEHOLDER",
  "disabled": "0",
  "is_visible": "1",
  "request.ui_dispatch_app": "search",
  "request.ui_dispatch_view": "search",
  "qualifiedSearch": "PLACEHOLDER",
  "schedule_priority": "default",
  "schedule_window": "0",
  "schedule_as": "auto",
  "run_n_times": "0",
  "run_on_startup": "0",
  "max_concurrent": "1",
  "realtime_schedule": "1",
  "restart_on_searchpeer_add": "1",
  "skip_scheduled_realtime_idxc": "0",
  "precalculate_required_fields_for_alerts": "auto",
  "vsid": "PLACEHOLDER",
  "workload_pool": "",
  "embed.enabled": "0",
  "displayview": "",
  "next_scheduled_time": "",
  "durable.track_time_type": "_time",
  "durable.max_backfill_intervals": "0",
  "durable.lag_time": "0",
  "durable.backfill_type": "auto",
  "display.general.type": "statistics",
  "display.visualizations.type": "table",
  "display.visualizations.trellis.enabled": "0",
  "display.visualizations.trellis.scales.shared": "1",
  "display.visualizations.trellis.size": "medium",
  "display.visualizations.trellis.splitBy": "_aggregation",
  "display.visualizations.singlevalueHeight": "200",
  "display.visualizations.singlevalue.useThousandSeparators": "1",
  "display.visualizations.singlevalue.useColors": "0",
  "display.visualizations.singlevalue.unit": "",
  "display.visualizations.singlevalue.unitPosition": "after",
  "display.visualizations.singlevalue.underLabel": "",
  "display.visualizations.singlevalue.trendInterval": "auto",
  "display.visualizations.singlevalue.trendDisplayMode": "absolute",
  "display.visualizations.singlevalue.trendColorInterpretation": "standard"
}'

# Build entry array as a stream of JSON objects, then wrap.
{
  for ((a=1; a<=NUM_APPS; a++)); do
    APP="app_${a}"
    OWNER="user_$((a % 7 + 1))"

    for ((e=1; e<=ENTRIES_PER_APP; e++)); do
      NAME="saved_search_${a}_${e}"
      KIND=$(( (a * e) % 5 ))

      jq -nc \
        --arg app "$APP" \
        --arg owner "$OWNER" \
        --arg name "$NAME" \
        --argjson kind "$KIND" \
        --argjson base "$BASE_CONTENT" '
        {
          name: $name,
          id: "https://splunk.example.com/servicesNS/\($owner)/\($app)/saved/searches/\($name)",
          updated: "2026-05-01T00:00:00+00:00",
          links: {
            alternate: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)",
            list: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)",
            "_reload": "/servicesNS/\($owner)/\($app)/saved/searches/\($name)/_reload",
            edit: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)",
            remove: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)",
            disable: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)/disable",
            move: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)/move",
            dispatch: "/servicesNS/\($owner)/\($app)/saved/searches/\($name)/dispatch"
          },
          author: $owner,
          acl: {
            app: $app,
            owner: $owner,
            sharing: "app",
            modifiable: true,
            removable: true,
            can_share_app: true,
            can_share_global: false,
            can_share_user: false,
            can_write: true,
            can_change_perms: true,
            ttl: "10",
            perms: {read: ["*"], write: [$owner]}
          },
          content: (
            ($base
              | .search                = "index=app_\($app) | stats count by host"
              | .description           = "Synthetic saved search \($name)"
              | .qualifiedSearch       = "search index=app_\($app) | stats count by host"
              | .vsid                  = "scheduler_\($owner)_\($app)__RMD"
              | ."request.ui_dispatch_app"  = $app)
            +
            (if $kind == 0 then
              # Plain saved search (no schedule, no alert)
              {is_scheduled: "0", "alert.track": "0", cron_schedule: "", actions: ""}
            elif $kind == 1 then
              # Scheduled (no alert action)
              {is_scheduled: "1", cron_schedule: "*/15 * * * *", "alert.track": "0", actions: ""}
            elif $kind == 2 then
              # Email alert
              {
                is_scheduled: "1",
                cron_schedule: "0 * * * *",
                "alert.track": "1",
                "alert.severity": "3",
                "alert.suppress": "0",
                "alert.suppress.period": "5m",
                "alert.digest_mode": "1",
                actions: "email",
                "action.email": "1",
                "action.email.to": "\($owner)@example.com",
                "action.email.subject": "Alert: \($name)",
                "action.email.subject.alert": "Alert: \($name)",
                "action.email.content_type": "html",
                "action.email.sendresults": "1",
                "action.email.include.search": "1",
                "action.email.include.trigger": "1",
                "action.email.include.trigger_time": "1",
                "action.email.include.results_link": "1",
                "action.email.priority": "3",
                counttype: "number of events",
                quantity: "0",
                relation: "greater than",
                "dispatch.earliest_time": "-1h",
                "dispatch.latest_time": "now"
              }
            elif $kind == 3 then
              # Webhook + Slack alert
              {
                is_scheduled: "1",
                cron_schedule: "*/5 * * * *",
                "alert.track": "1",
                "alert.severity": "5",
                actions: "webhook,slack",
                "action.webhook": "1",
                "action.webhook.param.url": "https://webhook.example.com/notify",
                "action.slack": "1",
                "action.slack.param.channel": "#alerts-\($app)",
                alert_type: "always",
                "dispatch.earliest_time": "-15m",
                "dispatch.latest_time": "now"
              }
            elif $kind == 4 then
              # Custom condition + summary index (regression-bait: alert.track=0
              # but is still an alert via alert_condition / counttype)
              {
                is_scheduled: "1",
                cron_schedule: "0 9 * * *",
                "alert.track": "0",
                alert_condition: "search count > 100",
                alert_comparator: "greater than",
                alert_threshold: "100",
                alert_type: "custom",
                counttype: "number of events",
                actions: "summary_index",
                "action.summary_index": "1",
                "action.summary_index._name": "summary_\($app)",
                "dispatch.earliest_time": "-24h",
                "dispatch.latest_time": "now"
              }
            else {} end)
            +
            # Regression-bait: third-party custom action that must round-trip
            # through the converter unchanged. Inject for every Nth entry.
            (if (($kind == 2) and (($app | length) > 0)) then
              {
                "action.servicenow_incident": "1",
                "action.servicenow_incident.param.assignment_group": "ops_\($app)",
                "action.servicenow_incident.param.urgency": "2",
                "action.itsi_submit_event": "0",
                "action.hca_webhook.param.webhook_url": "https://internal-bridge.example.com/\($app)"
              }
            else {} end)
          )
        }
      '
    done
  done
} | jq -s '
  {
    links: {
      create: "/services/saved/searches/_new",
      _reload: "/services/saved/searches/_reload"
    },
    origin: "https://splunk.example.com/services/saved/searches",
    updated: "2026-05-01T00:00:00+00:00",
    generator: {build: "synthetic", version: "fixture-generate-2.0"},
    entry: .,
    paging: {total: length, perPage: length, offset: 0},
    messages: []
  }
' > "$OUTPUT"

ENTRIES=$(jq '.entry | length' "$OUTPUT")
APPS=$(jq -r '[.entry[].acl.app] | unique | length' "$OUTPUT")
SIZE=$(wc -c < "$OUTPUT" | awk '{print $1}')
KEY_COUNTS=$(jq -r '[.entry[] | (.content | keys | length)] | min, max, (add/length)' "$OUTPUT" | tr '\n' ' ')
ALERT_COUNT=$(jq '[.entry[] | select((.content["alert.track"] // "0") == "1")] | length' "$OUTPUT")
echo "Generated: $OUTPUT"
echo "  Entries: $ENTRIES across $APPS apps  (${SIZE} bytes)"
echo "  Content keys per entry: min/max/avg = ${KEY_COUNTS}"
echo "  Alerts (alert.track=1): $ALERT_COUNT"
