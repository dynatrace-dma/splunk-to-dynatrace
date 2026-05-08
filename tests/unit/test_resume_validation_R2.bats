#!/usr/bin/env bats
# R2 (resume validation): validate_alerts_inventory_outputs must invalidate
# the alerts_inventory checkpoint when its sentinel files are 465-byte error
# shells (real production case), and accept it when they contain real results.
#
# These tests will FAIL until §3.2 lands the helper. They're TDD specs.

load helpers

setup() {
  load_cloud_bash
  source "$REPO_ROOT/tests/replay/mocks.sh"

  if [ ! -s "$REPO_ROOT/tests/fixtures/error_shell_alerts_inventory.json" ]; then
    "$REPO_ROOT/tests/fixtures/generate_corruption_variants.sh" >/dev/null
  fi

  EXPORT_DIR=$(mktemp -d -t r2-test-XXXXXX)
  export EXPORT_DIR
  HAS_JQ=true

  SELECTED_APPS=(app_1 app_2 app_3)
  for app in "${SELECTED_APPS[@]}"; do
    mkdir -p "$EXPORT_DIR/$app/splunk-analysis"
  done
}

teardown() {
  [ -n "${EXPORT_DIR:-}" ] && rm -rf "$EXPORT_DIR"
}

place_alerts_inventory() {
  local app="$1" fixture="$2"
  mkdir -p "$EXPORT_DIR/$app/splunk-analysis"
  cp "$fixture" "$EXPORT_DIR/$app/splunk-analysis/alerts_inventory.json"
}

@test "R2 [TDD]: validate_alerts_inventory_outputs function exists in v4.6.6" {
  [ "$(type -t validate_alerts_inventory_outputs)" = "function" ]
}

@test "R2: rejects when ALL files are error-shell JSON (production case)" {
  for app in "${SELECTED_APPS[@]}"; do
    place_alerts_inventory "$app" "$REPO_ROOT/tests/fixtures/error_shell_alerts_inventory.json"
  done
  run validate_alerts_inventory_outputs
  [ "$status" -ne 0 ]
}

@test "R2: accepts when files contain valid results" {
  for app in "${SELECTED_APPS[@]}"; do
    place_alerts_inventory "$app" "$REPO_ROOT/tests/fixtures/valid_alerts_inventory.json"
  done
  run validate_alerts_inventory_outputs
  [ "$status" -eq 0 ]
}

@test "R2: accepts mixed (some apps have results, some legitimately empty)" {
  place_alerts_inventory "app_1" "$REPO_ROOT/tests/fixtures/valid_alerts_inventory.json"
  # app_2 and app_3 have no file — that's a legitimate "no alerts in this app" case
  run validate_alerts_inventory_outputs
  [ "$status" -eq 0 ]
}

@test "R2: rejects when ALL files are missing entirely" {
  # No files placed.
  run validate_alerts_inventory_outputs
  [ "$status" -ne 0 ]
}

@test "R2 [TDD]: drop_analytics_checkpoint helper exists in v4.6.6" {
  [ "$(type -t drop_analytics_checkpoint)" = "function" ]
}

@test "R2: drop_analytics_checkpoint removes a key from .analytics_checkpoint" {
  printf "alerts_inventory\nusage_user_activity\n" > "$EXPORT_DIR/.analytics_checkpoint"
  run drop_analytics_checkpoint "alerts_inventory"
  [ "$status" -eq 0 ]
  remaining=$(cat "$EXPORT_DIR/.analytics_checkpoint")
  [ "$remaining" = "usage_user_activity" ]
}
