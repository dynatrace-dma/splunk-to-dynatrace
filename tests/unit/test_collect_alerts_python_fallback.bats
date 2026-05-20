#!/usr/bin/env bats
# v4.6.7: Python fallback for collect_alerts. Locks in behavior of the
# no-jq partition path so we don't regress the fix for the Fifth Third /
# Encova class of broken-archive incidents.
#
# Key invariant: with HAS_JQ=false, collect_alerts must produce the SAME
# per-app savedsearches.json files (envelope shape + entry filtering by
# acl.app) and the SAME STATS_SAVED_SEARCHES / STATS_ALERTS totals as the
# jq path.

load helpers

setup() {
  load_cloud_bash
  source "$REPO_ROOT/tests/replay/mocks.sh"
  mock_reset

  EXPORT_DIR=$(mktemp -d -t collect-alerts-py-test-XXXXXX)
  export EXPORT_DIR

  FIXTURE="$REPO_ROOT/tests/fixtures/saved_searches_small.json"
  [ -s "$FIXTURE" ] || skip "missing fixture $FIXTURE (run tests/fixtures/generate.sh)"
  mock_set_fixture "$FIXTURE"

  SELECTED_APPS=(app_1 app_2 app_3 app_4 app_5)
  COLLECT_ALERTS=true
  HAS_JQ=false     # <-- force Python fallback

  # PYTHON_CMD is normally set during init_environment; tests bypass that.
  if command -v python3 &>/dev/null; then
    PYTHON_CMD=python3
  elif command -v python &>/dev/null; then
    PYTHON_CMD=python
  else
    skip "python3/python not available — Python fallback cannot be tested"
  fi

  for app in "${SELECTED_APPS[@]}"; do
    mkdir -p "$EXPORT_DIR/$app"
  done
}

teardown() {
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
  mock_reset
}

@test "v4.6.7 fallback: collect_alerts writes one savedsearches.json per app (no jq)" {
  collect_alerts

  for app in "${SELECTED_APPS[@]}"; do
    [ -s "$EXPORT_DIR/$app/savedsearches.json" ] || {
      echo "Missing or empty: $EXPORT_DIR/$app/savedsearches.json"
      return 1
    }
  done
}

@test "v4.6.7 fallback: each app's entry[] contains only matching acl.app (no jq)" {
  collect_alerts

  for app in "${SELECTED_APPS[@]}"; do
    local foreign
    foreign=$("$PYTHON_CMD" - "$EXPORT_DIR/$app/savedsearches.json" "$app" <<'PY'
import json, sys
with open(sys.argv[1]) as fh: d = json.load(fh)
app = sys.argv[2]
print(sum(1 for e in d.get("entry", []) if (e.get("acl") or {}).get("app") != app))
PY
)
    [ "$foreign" = "0" ] || {
      echo "App $app has $foreign foreign entries (acl.app != $app)"
      return 1
    }
  done
}

@test "v4.6.7 fallback: STATS_SAVED_SEARCHES + STATS_ALERTS populated (no jq)" {
  collect_alerts

  [ "$STATS_SAVED_SEARCHES" -gt 0 ] || {
    echo "STATS_SAVED_SEARCHES=$STATS_SAVED_SEARCHES (expected > 0)"
    return 1
  }
  # Alert count must be >= 0 and <= total (sanity).
  [ "$STATS_ALERTS" -ge 0 ] || return 1
  [ "$STATS_ALERTS" -le "$STATS_SAVED_SEARCHES" ] || {
    echo "STATS_ALERTS ($STATS_ALERTS) > STATS_SAVED_SEARCHES ($STATS_SAVED_SEARCHES)"
    return 1
  }
}

@test "v4.6.7 fallback: writes resume sentinel even on no-jq path" {
  collect_alerts
  [ -f "$EXPORT_DIR/dma_analytics/.savedsearches_collected" ]
}

@test "v4.6.7 fallback: makes exactly 1 api_call to /servicesNS/-/-/saved/searches" {
  collect_alerts

  local stack_calls
  stack_calls=$(mock_calls_to '^GET\|/servicesNS/-/-/saved/searches')
  [ "$stack_calls" = "1" ] || {
    echo "Expected 1 stack-wide /saved/searches call, got $stack_calls"
    cat "$MOCK_CALL_LOG"
    return 1
  }

  local per_app_calls
  per_app_calls=$(mock_calls_to '^GET\|/servicesNS/-/[^-][^/]*/saved/searches')
  [ "$per_app_calls" = "0" ] || {
    echo "Expected 0 per-app /saved/searches calls, got $per_app_calls"
    cat "$MOCK_CALL_LOG"
    return 1
  }
}
