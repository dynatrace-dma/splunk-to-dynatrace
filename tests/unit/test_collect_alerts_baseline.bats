#!/usr/bin/env bats
# Baseline behavior tests for the CURRENT (v4.6.3) collect_alerts function.
# These lock in expected behavior so we can verify v4.6.6's refactor preserves
# the contract (per-app file shape, alert counts, acl.app-filtered entries).

load helpers

setup() {
  load_cloud_bash
  source "$REPO_ROOT/tests/replay/mocks.sh"
  mock_reset

  EXPORT_DIR=$(mktemp -d -t collect-alerts-test-XXXXXX)
  export EXPORT_DIR

  # Generate a fresh small fixture for this test run.
  FIXTURE="$REPO_ROOT/tests/fixtures/saved_searches_small.json"
  if [ ! -s "$FIXTURE" ]; then
    "$REPO_ROOT/tests/fixtures/generate.sh" 5 10 "$FIXTURE" >/dev/null
  fi
  mock_set_fixture "$FIXTURE"

  # The function expects SELECTED_APPS, COLLECT_ALERTS, HAS_JQ to be set.
  SELECTED_APPS=(app_1 app_2 app_3 app_4 app_5)
  COLLECT_ALERTS=true
  HAS_JQ=true

  # Make per-app dirs so the function can write into them.
  for app in "${SELECTED_APPS[@]}"; do
    mkdir -p "$EXPORT_DIR/$app"
  done
}

teardown() {
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
  mock_reset
}

@test "v4.6.3 baseline: collect_alerts writes one savedsearches.json per app" {
  collect_alerts

  for app in "${SELECTED_APPS[@]}"; do
    [ -s "$EXPORT_DIR/$app/savedsearches.json" ] || {
      echo "Missing or empty: $EXPORT_DIR/$app/savedsearches.json"
      return 1
    }
  done
}

@test "v4.6.3 baseline: each app's savedsearches.json contains only entries with matching acl.app" {
  collect_alerts

  for app in "${SELECTED_APPS[@]}"; do
    local foreign
    foreign=$(jq --arg app "$app" '[.entry[] | select(.acl.app != $app)] | length' \
      "$EXPORT_DIR/$app/savedsearches.json")
    [ "$foreign" = "0" ] || {
      echo "App $app has $foreign foreign entries (acl.app != $app)"
      return 1
    }
  done
}

@test "v4.6.3 baseline: total entry count across per-app files equals fixture entry count" {
  collect_alerts

  local total=0
  for app in "${SELECTED_APPS[@]}"; do
    local n
    n=$(jq '.entry | length' "$EXPORT_DIR/$app/savedsearches.json")
    total=$((total + n))
  done

  local fixture_total
  fixture_total=$(jq '.entry | length' "$FIXTURE")
  [ "$total" = "$fixture_total" ]
}

@test "v4.6.6: makes exactly 1 api_call to /servicesNS/-/-/saved/searches (was N per-app in v4.6.3)" {
  collect_alerts

  local global_calls per_app_calls
  global_calls=$(mock_calls_to '/servicesNS/-/-/saved/searches')
  # Per-app calls have an app name (not "-") in the second segment.
  per_app_calls=$(mock_calls_to 'GET\|/servicesNS/-/[^-][^/]*/saved/searches')

  [ "$global_calls" = "1" ] || {
    echo "Expected 1 global call to /servicesNS/-/-/saved/searches, got $global_calls"
    cat "$MOCK_CALL_LOG"
    return 1
  }
  [ "$per_app_calls" = "0" ] || {
    echo "Expected 0 per-app /saved/searches calls, got $per_app_calls (the v4.6.3 bug)"
    cat "$MOCK_CALL_LOG"
    return 1
  }
}

@test "v4.6.6: writes resume sentinel dma_analytics/.savedsearches_collected" {
  collect_alerts
  [ -f "$EXPORT_DIR/dma_analytics/.savedsearches_collected" ]
}

@test "v4.6.6: resume mode short-circuits on existing sentinel" {
  # First run: populate sentinel + per-app files.
  collect_alerts
  [ -f "$EXPORT_DIR/dma_analytics/.savedsearches_collected" ]
  initial_calls=$(mock_call_count)

  # Reset mock log; second run with RESUME_MODE=true should NOT call api_call again.
  mock_reset
  RESUME_MODE=true
  collect_alerts
  later_calls=$(mock_calls_to '/servicesNS/.*/saved/searches')
  [ "$later_calls" = "0" ] || {
    echo "Resume short-circuit failed: still made $later_calls api_call(s) to /saved/searches"
    cat "$MOCK_CALL_LOG"
    return 1
  }

  # Stats should match the first run (recomputed from cached files).
  [ "$STATS_SAVED_SEARCHES" -gt 0 ]
}

@test "v4.6.3 baseline: STATS_ALERTS reflects detected alerts (alert.track=1, etc.)" {
  collect_alerts

  # Cross-check by counting alert-marked entries in the fixture directly.
  local fixture_alerts
  fixture_alerts=$(jq '[.entry[] | select(
    ((.content["alert.track"] // "") | tostring | . == "1" or . == "true") or
    ((.content["alert_type"] // "") | ascii_downcase | . == "always" or . == "custom" or test("^number of")) or
    ((.content["alert_condition"] // "") | length > 0) or
    ((.content["alert_comparator"] // "") | length > 0) or
    ((.content["alert_threshold"] // "") | length > 0) or
    ((.content["counttype"] // "") | test("number of"; "i")) or
    ((.content["actions"] // "") | split(",") | map(select(length > 0)) | length > 0) or
    ((.content["action.email"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.webhook"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.script"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.slack"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.pagerduty"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.summary_index"] // "") | tostring | . == "1" or . == "true") or
    ((.content["action.populate_lookup"] // "") | tostring | . == "1" or . == "true")
  )] | length' "$FIXTURE")

  [ "$STATS_ALERTS" = "$fixture_alerts" ] || {
    echo "STATS_ALERTS=$STATS_ALERTS, expected $fixture_alerts (per fixture content)"
    return 1
  }
}
