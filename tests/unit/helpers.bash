# tests/unit/helpers.bash — sourced by every bats test under unit/
#
# Lets a test source the production script as a library: all functions are
# available, but the script's `main "$@"` invocation at the bottom is a no-op.
#
# Usage in a bats file:
#
#   load helpers
#   load_cloud_bash       # or load_enterprise
#
#   @test "my_test" {
#     # call any function from the script directly:
#     run my_function arg1 arg2
#     [ "$status" -eq 0 ]
#   }
#
# This avoids editing the production scripts. We rely on the fact that bash
# resolves `main "$@"` at the bottom against whatever `main` is defined when
# the script is sourced — defining a stub before `source` makes it a no-op.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPORT_DIR_ROOT="$REPO_ROOT/splunk-export"

# Stub `main` so the bottom-of-file `main "$@"` does nothing.
# Tests that need to invoke `main` should override this AFTER sourcing.
main() { return 0; }

# Stub a couple of logging helpers so sourcing doesn't try to write to a
# log file that doesn't exist yet. Tests that care about log output can
# override these per-test.
log()      { :; }
warning()  { :; }
error()    { :; }
debug_log(){ :; }
progress() { :; }
success()  { :; }

load_cloud_bash() {
  # shellcheck disable=SC1090
  source "$EXPORT_DIR_ROOT/dma-splunk-cloud-export.sh"
}

load_enterprise() {
  # shellcheck disable=SC1090
  source "$EXPORT_DIR_ROOT/dma-splunk-export.sh"
}

# Make a clean ephemeral EXPORT_DIR for tests that exercise file-writing helpers.
# Caller is responsible for cleanup via teardown.
make_test_export_dir() {
  EXPORT_DIR=$(mktemp -d -t dma-test-XXXXXX)
  export EXPORT_DIR
  echo "$EXPORT_DIR"
}

# Read a fixture file by name (relative to tests/fixtures/).
fixture_path() {
  echo "$REPO_ROOT/tests/fixtures/$1"
}
