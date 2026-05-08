#!/usr/bin/env bats
# R1 (resume validation): is_valid_app_savedsearches must accept only the
# valid-and-correct-app shape, force re-fetch for everything else.
#
# These tests will FAIL until §3.1 lands the helper. They're TDD specs.

load helpers

setup() {
  load_cloud_bash
  source "$REPO_ROOT/tests/replay/mocks.sh"

  # Ensure all corruption variants exist.
  if [ ! -s "$REPO_ROOT/tests/fixtures/saved_searches_small.json" ]; then
    "$REPO_ROOT/tests/fixtures/generate.sh" 5 10 "$REPO_ROOT/tests/fixtures/saved_searches_small.json" >/dev/null
  fi
  if [ ! -s "$REPO_ROOT/tests/fixtures/corrupt_truncated.json" ]; then
    "$REPO_ROOT/tests/fixtures/generate_corruption_variants.sh" >/dev/null
  fi

  EXPORT_DIR=$(mktemp -d -t r1-test-XXXXXX)
  export EXPORT_DIR
  HAS_JQ=true
}

teardown() {
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
}

# Helper: place a fixture file at <EXPORT_DIR>/<app>/savedsearches.json,
# optionally rewriting acl.app to match the dir name.
place_app_savedsearches() {
  local app="$1" fixture="$2" rewrite_acl="${3:-true}"
  mkdir -p "$EXPORT_DIR/$app"
  if [ "$rewrite_acl" = "true" ] && command -v jq >/dev/null; then
    jq --arg app "$app" '.entry[]?.acl.app = $app' "$fixture" > "$EXPORT_DIR/$app/savedsearches.json"
  else
    cp "$fixture" "$EXPORT_DIR/$app/savedsearches.json"
  fi
}

@test "R1 [TDD]: is_valid_app_savedsearches function exists in v4.6.6" {
  [ "$(type -t is_valid_app_savedsearches)" = "function" ]
}

@test "R1: accepts a valid file with all entries' acl.app matching the dir name" {
  place_app_savedsearches "app_1" "$REPO_ROOT/tests/fixtures/saved_searches_small.json" true
  run is_valid_app_savedsearches "app_1"
  [ "$status" -eq 0 ]
}

@test "R1: rejects a missing file" {
  mkdir -p "$EXPORT_DIR/app_1"
  run is_valid_app_savedsearches "app_1"
  [ "$status" -ne 0 ]
}

@test "R1: rejects a zero-byte file" {
  mkdir -p "$EXPORT_DIR/app_1"
  : > "$EXPORT_DIR/app_1/savedsearches.json"
  run is_valid_app_savedsearches "app_1"
  [ "$status" -ne 0 ]
}

@test "R1: rejects a JSON-corrupt (truncated) file (production 000-self-service case)" {
  place_app_savedsearches "000-self-service" "$REPO_ROOT/tests/fixtures/corrupt_truncated.json" false
  run is_valid_app_savedsearches "000-self-service"
  [ "$status" -ne 0 ]
}

@test "R1: rejects a parseable file with foreign acl.app entries" {
  place_app_savedsearches "app_1" "$REPO_ROOT/tests/fixtures/foreign_acl.json" false
  run is_valid_app_savedsearches "app_1"
  [ "$status" -ne 0 ]
}

@test "R1: rejects a file missing the .entry key entirely" {
  place_app_savedsearches "app_1" "$REPO_ROOT/tests/fixtures/missing_entry.json" false
  run is_valid_app_savedsearches "app_1"
  [ "$status" -ne 0 ]
}

@test "R1: accepts a file with empty .entry array (valid app, just no searches)" {
  place_app_savedsearches "app_1" "$REPO_ROOT/tests/fixtures/empty_entry.json" false
  run is_valid_app_savedsearches "app_1"
  [ "$status" -eq 0 ]
}
