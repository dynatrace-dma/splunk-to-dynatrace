#!/usr/bin/env bats
# Smoke test for the test infrastructure itself.
# Verifies bats can run, helpers.bash sources cleanly, and the production
# scripts can be loaded as libraries without side effects.

load helpers

@test "bats is operational" {
  [ -n "$BATS_TEST_FILENAME" ]
}

@test "cloud-bash script sources without running main" {
  load_cloud_bash
  # If `main "$@"` ran on source, the script would have tried to do real work
  # and likely failed. Our stub returns 0; reaching this line means it worked.
  [ "$(type -t collect_alerts)" = "function" ]
  [ "$(type -t api_call)" = "function" ]
}

@test "cloud-bash exposes SCRIPT_VERSION" {
  load_cloud_bash
  [ -n "$SCRIPT_VERSION" ]
  [ "$SCRIPT_VERSION" = "4.6.6" ]
}

@test "enterprise script sources without running main" {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    skip "enterprise script requires bash 4+ (uses 'declare -A'); current shell is ${BASH_VERSION}. Install via 'brew install bash' to run this test on macOS."
  fi
  load_enterprise
  [ "$(type -t collect_app_configs)" = "function" ]
}

@test "fixture_path resolves under tests/fixtures/" {
  result=$(fixture_path "saved_searches_small.json")
  [[ "$result" == */tests/fixtures/saved_searches_small.json ]]
}
