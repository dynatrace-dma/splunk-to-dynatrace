#!/usr/bin/env bash
# Generate corruption-variant fixtures used by R1/R2 unit tests.
# Inputs: a base valid fixture (saved_searches_small.json by default).
# Outputs:
#   - corrupt_truncated.json    — valid prefix, truncated mid-stream
#   - foreign_acl.json          — parseable, but entries belong to a different app
#   - empty_entry.json          — valid envelope, empty entry array
#   - missing_entry.json        — envelope without an entry key at all
#   - error_shell_alerts_inventory.json — 465-byte error-shell mimicking
#                                  the broken alerts_inventory.json files
#                                  observed in real-world production cases

set -e

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${FIXTURES_DIR}/saved_searches_small.json"

if [ ! -s "$BASE" ]; then
  echo "Base fixture not found: $BASE — run generate.sh first" >&2
  exit 1
fi

# 1. Truncated mid-stream — like a savedsearches.json that was cut off
#    while writing. Take the first 4KB of the valid fixture; jq parse will fail.
head -c 4096 "$BASE" > "$FIXTURES_DIR/corrupt_truncated.json"
echo "Generated corrupt_truncated.json ($(wc -c < $FIXTURES_DIR/corrupt_truncated.json) bytes)"

# 2. Foreign ACL — every entry's acl.app is "WRONG_APP" instead of matching
#    its directory name. R1 must reject this when used as <app>/savedsearches.json.
jq '.entry[].acl.app = "WRONG_APP" | .' "$BASE" > "$FIXTURES_DIR/foreign_acl.json"
echo "Generated foreign_acl.json ($(wc -c < $FIXTURES_DIR/foreign_acl.json) bytes)"

# 3. Empty entry array — valid JSON, no entries
jq '.entry = [] | .paging.total = 0' "$BASE" > "$FIXTURES_DIR/empty_entry.json"
echo "Generated empty_entry.json ($(wc -c < $FIXTURES_DIR/empty_entry.json) bytes)"

# 4. Missing entry key entirely — envelope without entry
jq 'del(.entry)' "$BASE" > "$FIXTURES_DIR/missing_entry.json"
echo "Generated missing_entry.json ($(wc -c < $FIXTURES_DIR/missing_entry.json) bytes)"

# 5. Error-shell alerts_inventory.json — exactly the 465-byte shape that
#    alerts_inventory.json files take when written by
#    run_analytics_search_blocking after the runtime cap was already exceeded.
cat > "$FIXTURES_DIR/error_shell_alerts_inventory.json" <<'EOF'
{
  "preview": false,
  "init_offset": 0,
  "messages": [
    {
      "type": "ERROR",
      "text": "Maximum runtime (43200 seconds) exceeded. Export incomplete."
    }
  ],
  "fields": [],
  "results": [],
  "highlighted": {},
  "_meta": {
    "_export_runtime_exceeded": true,
    "_query_attempted": "Alerts inventory",
    "_export_log_ref": "_export.log"
  }
}
EOF
echo "Generated error_shell_alerts_inventory.json ($(wc -c < $FIXTURES_DIR/error_shell_alerts_inventory.json) bytes)"

# 6. Valid alerts_inventory.json shape (the success case for R2's positive test).
cat > "$FIXTURES_DIR/valid_alerts_inventory.json" <<'EOF'
{
  "preview": false,
  "init_offset": 0,
  "messages": [],
  "fields": [
    {"name": "alert_name"},
    {"name": "cron_schedule"},
    {"name": "alert.severity"},
    {"name": "alert.track"},
    {"name": "actions"},
    {"name": "disabled"}
  ],
  "results": [
    {
      "alert_name": "High CPU alert",
      "cron_schedule": "*/5 * * * *",
      "alert.severity": "5",
      "alert.track": "1",
      "actions": "email,webhook",
      "disabled": "0"
    },
    {
      "alert_name": "Disk space alert",
      "cron_schedule": "0 * * * *",
      "alert.severity": "3",
      "alert.track": "1",
      "actions": "email",
      "disabled": "0"
    }
  ],
  "highlighted": {}
}
EOF
echo "Generated valid_alerts_inventory.json ($(wc -c < $FIXTURES_DIR/valid_alerts_inventory.json) bytes)"

echo ""
echo "All corruption variants generated under $FIXTURES_DIR/"
