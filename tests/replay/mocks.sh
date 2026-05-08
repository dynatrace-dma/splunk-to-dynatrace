# tests/replay/mocks.sh — Splunk API mock library
#
# Provides drop-in replacements for the production script's network-touching
# functions, so tests can run collect_alerts / authenticate_splunk / etc.
# without a real Splunk Cloud token. Mocks are dispatched by endpoint pattern.
#
# Usage:
#   source helpers.bash
#   load_cloud_bash                          # production functions defined
#   source "$REPO_ROOT/tests/replay/mocks.sh"  # OVERRIDE production functions
#   mock_set_fixture "$REPO_ROOT/tests/fixtures/saved_searches_small.json"
#   collect_alerts                           # uses mocked api_call
#
# All API calls are appended to MOCK_CALL_LOG ($1=method, $2=endpoint, $3=data).
# Tests can grep this log to assert call patterns (e.g. "single call to /saved/searches").

# Where the mock pulls /saved/searches responses from. Set via mock_set_fixture.
MOCK_FIXTURE_SAVED_SEARCHES=""

# All mocked api_call invocations append a line to this file.
MOCK_CALL_LOG="${MOCK_CALL_LOG:-$(mktemp -t mock-calls-XXXXXX.log)}"
export MOCK_CALL_LOG

# Reset call log + fixture state. Call from teardown.
mock_reset() {
  : > "$MOCK_CALL_LOG"
  MOCK_FIXTURE_SAVED_SEARCHES=""
}

mock_set_fixture() {
  MOCK_FIXTURE_SAVED_SEARCHES="$1"
  if [ ! -s "$MOCK_FIXTURE_SAVED_SEARCHES" ]; then
    echo "ERROR: mock_set_fixture: fixture not found or empty: $MOCK_FIXTURE_SAVED_SEARCHES" >&2
    return 1
  fi
}

# Inspect call log conveniently in tests.
mock_call_count() {
  wc -l < "$MOCK_CALL_LOG" | awk '{print $1}'
}

mock_calls_to() {
  # Usage: mock_calls_to /servicesNS/-/-/saved/searches
  # Returns the count on stdout. grep -c emits "0" + exit 1 on no-match;
  # capturing in a variable absorbs the non-zero exit so `set -e` (bats
  # strict mode) doesn't trip the assignment.
  local pattern="$1" count=0
  if [ -s "$MOCK_CALL_LOG" ]; then
    count=$(grep -cE "$pattern" "$MOCK_CALL_LOG" 2>/dev/null || true)
  fi
  echo "${count:-0}"
}

# =============================================================================
# api_call mock — drop-in replacement for the production api_call.
# Production signature (cloud-bash line ~1124):
#   api_call <endpoint> <method> [data]
# Returns response on stdout, exit 0 on success, exit 1 on error.
# =============================================================================
api_call() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="${3:-}"

  echo "${method}|${endpoint}|${data}" >> "$MOCK_CALL_LOG"

  case "$endpoint" in
    /servicesNS/-/-/saved/searches)
      # The new v4.6.6 single-call path. Return the fixture verbatim.
      if [ -n "$MOCK_FIXTURE_SAVED_SEARCHES" ] && [ -s "$MOCK_FIXTURE_SAVED_SEARCHES" ]; then
        cat "$MOCK_FIXTURE_SAVED_SEARCHES"
        return 0
      fi
      echo '{"entry":[],"messages":[]}'
      return 0
      ;;
    /servicesNS/-/*/saved/searches)
      # The OLD per-app path. Return fixture entries filtered to this app.
      # This lets the replay harness exercise the OLD code path against the
      # same fixture data, for old-vs-new diff comparison.
      local app
      app=$(echo "$endpoint" | sed -E 's|/servicesNS/-/([^/]+)/saved/searches.*|\1|')
      if [ -n "$MOCK_FIXTURE_SAVED_SEARCHES" ] && command -v jq >/dev/null 2>&1; then
        jq --arg app "$app" '{
          links: .links, origin: .origin, updated: .updated, generator: .generator,
          entry: [.entry[] | select(.acl.app == $app)],
          paging: .paging, messages: []
        }' "$MOCK_FIXTURE_SAVED_SEARCHES"
        return 0
      fi
      echo '{"entry":[],"messages":[]}'
      return 0
      ;;
    /services/server/info)
      echo '{"entry":[{"name":"server-info","content":{"version":"10.2.2510.13","serverName":"mock-splunk","build":"mock"}}]}'
      return 0
      ;;
    /services/authentication/current-context)
      echo '{"entry":[{"name":"context","content":{"username":"mock_user","roles":["sc_admin"]}}]}'
      return 0
      ;;
    /services/apps/local)
      # Return a synthesized app list matching whatever apps are in the fixture.
      if [ -n "$MOCK_FIXTURE_SAVED_SEARCHES" ] && command -v jq >/dev/null 2>&1; then
        jq '{entry: ([.entry[].acl.app] | unique | map({name: ., content: {disabled: "0", visible: "1", label: .}}))}' \
          "$MOCK_FIXTURE_SAVED_SEARCHES"
        return 0
      fi
      echo '{"entry":[]}'
      return 0
      ;;
    *)
      # Unknown endpoint — return empty success. Tests that need a specific
      # response shape for some other endpoint can extend this case statement.
      echo '{"entry":[],"messages":[]}'
      return 0
      ;;
  esac
}

# =============================================================================
# authenticate_splunk mock — bypass the real Splunk login round-trip.
# =============================================================================
authenticate_splunk() {
  echo "${FUNCNAME[0]}||" >> "$MOCK_CALL_LOG"
  AUTH_HEADER="Authorization: Splunk mock-session-key"
  SESSION_KEY="mock-session-key"
  AUTH_TOKEN="mock-token"
  return 0
}

# Some script paths probe whether Bearer or Splunk prefix works for the token.
# Skip the probe entirely.
probe_token_prefix() {
  echo "${FUNCNAME[0]}||" >> "$MOCK_CALL_LOG"
  AUTH_HEADER="Authorization: Splunk mock-session-key"
  return 0
}

# =============================================================================
# run_analytics_search / run_analytics_search_blocking mocks — used by
# collect_app_analytics for global queries (Q1-Q6). For test purposes we
# synthesize empty result files so checkpoints save normally.
# =============================================================================
run_analytics_search() {
  local query="$1"
  local output_file="$2"
  local label="$3"
  echo "run_analytics_search|${label}|${output_file}" >> "$MOCK_CALL_LOG"
  echo '{"results":[],"_mock":true}' > "$output_file"
  return 0
}

run_analytics_search_blocking() {
  local query="$1"
  local output_file="$2"
  local label="$3"
  echo "run_analytics_search_blocking|${label}|${output_file}" >> "$MOCK_CALL_LOG"
  echo '{"results":[],"_mock":true}' > "$output_file"
  return 0
}
