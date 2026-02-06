#!/bin/bash
# LINE ENDING FIX: Auto-detect and fix Windows CRLF line endings
# If you see "$'\r': command not found" errors, this block will auto-fix and re-run
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && grep -q $'\r' "$0" 2>/dev/null; then
    echo "Detected Windows line endings (CRLF). Converting to Unix (LF)..."
    sed -i.bak 's/\r$//' "$0" && rm -f "$0.bak"
    exec bash "$0" "$@"
fi

################################################################################
#
#  DMA Splunk Export Script v4.2.4
#
#  v4.2.4 Changes:
#    - Anonymization now creates TWO archives: original (untouched) + _masked (anonymized)
#    - Preserves original data in case anonymization corrupts files
#    - Users can re-run anonymization on original if needed without full re-export
#    - RBAC/Users collection now OFF by default (use --rbac to enable)
#    - Usage analytics collection now OFF by default (use --usage to enable)
#    - Faster performance defaults: batch size 250 (was 100), API delay 50ms (was 250ms)
#    - Optimized usage analytics queries with sampling for expensive regex extractions
#    - Changed latest() to max() for faster time aggregations
#    - Moved filters to search-time for better performance
#
#  Complete Splunk Environment Data Collection for Migration to Dynatrace
#
#  This script collects configurations, dashboards, alerts, users, and usage
#  analytics from your Splunk environment to enable migration planning and
#  execution using the Dynatrace Migration Assistant application.
#
################################################################################
#
#  ╔═══════════════════════════════════════════════════════════════════════════╗
#  ║                    PRE-FLIGHT CHECKLIST                                   ║
#  ╠═══════════════════════════════════════════════════════════════════════════╣
#  ║                                                                           ║
#  ║  BEFORE RUNNING THIS SCRIPT, VERIFY THE FOLLOWING:                        ║
#  ║                                                                           ║
#  ║  □ 1. SYSTEM REQUIREMENTS                                                 ║
#  ║     □ bash 4.0+ (REQUIRED) Run: bash --version                           ║
#  ║       └─ Most Linux servers have this. macOS default bash is too old.    ║
#  ║     □ curl installed   Run: curl --version                                ║
#  ║     □ Python 3 available (uses Splunk's bundled Python if available)      ║
#  ║       └─ Splunk includes Python - no separate install needed              ║
#  ║     □ tar installed    Run: tar --version                                 ║
#  ║     □ 500MB+ free      Run: df -h /tmp                                    ║
#  ║                                                                           ║
#  ║  □ 2. SPLUNK ACCESS                                                       ║
#  ║     □ Know SPLUNK_HOME path (e.g., /opt/splunk)                          ║
#  ║     □ Have admin username and password                                    ║
#  ║     □ User has these capabilities:                                        ║
#  ║       └─ search, admin_all_objects, list_settings, rest_properties_get    ║
#  ║       └─ schedule_search (for analytics searches)                         ║
#  ║                                                                           ║
#  ║  □ 3. NETWORK ACCESS                                                      ║
#  ║     □ Can reach Splunk REST API on port 8089                              ║
#  ║       Test: curl -k https://localhost:8089/services/server/info           ║
#  ║     □ No firewall blocking localhost:8089 or splunk-server:8089           ║
#  ║                                                                           ║
#  ║  □ 4. INTERNAL INDEXES (for usage analytics)                              ║
#  ║     □ User can search index=_audit                                        ║
#  ║     □ User can search index=_internal                                     ║
#  ║     □ These indexes have 30+ days retention (ideal)                       ║
#  ║       Test: | search index=_audit | head 1                                ║
#  ║                                                                           ║
#  ║  □ 5. INFORMATION TO GATHER BEFOREHAND                                    ║
#  ║     □ Splunk admin username: ___________________                          ║
#  ║     □ Splunk admin password: ___________________                          ║
#  ║     □ Splunk host (if not localhost): ___________________                 ║
#  ║     □ Splunk port (if not 8089): ___________________                      ║
#  ║     □ Apps to export (or "all"): ___________________                      ║
#  ║                                                                           ║
#  ╚═══════════════════════════════════════════════════════════════════════════╝
#
#  QUICK TEST: Verify API access before running full export:
#    curl -k -u admin:password https://localhost:8089/services/server/info
#
#  If the test fails, check:
#    1. Splunk is running: $SPLUNK_HOME/bin/splunk status
#    2. Port is correct: netstat -tlnp | grep 8089
#    3. Credentials work: Try logging into Splunk Web
#
################################################################################

set -o pipefail  # Fail on pipe errors
# Note: We don't use set -e because we want to handle errors gracefully

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

SCRIPT_VERSION="4.2.4"
SCRIPT_NAME="DMA Splunk Export"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# Box drawing characters
BOX_TL="╔"
BOX_TR="╗"
BOX_BL="╚"
BOX_BR="╝"
BOX_H="═"
BOX_V="║"
BOX_T="╠"
BOX_B="╣"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

SPLUNK_HOME=""
SPLUNK_USER="${SPLUNK_USER:-}"
# Preserve SPLUNK_PASSWORD from environment if set (common in container deployments)
SPLUNK_PASSWORD="${SPLUNK_PASSWORD:-}"
SPLUNK_HOST="localhost"
SPLUNK_PORT="8089"
EXPORT_DIR=""
EXPORT_NAME=""
TIMESTAMP=""
LOG_FILE=""

# Environment detection
SPLUNK_FLAVOR=""           # enterprise, uf, hf
SPLUNK_ARCHITECTURE=""     # standalone, distributed, cloud
SPLUNK_ROLE=""            # search_head, indexer, forwarder, etc.
IS_SHC_MEMBER=false
IS_SHC_CAPTAIN=false
IS_IDX_CLUSTER=false
IS_CLOUD=false

# Collection options
SELECTED_APPS=()
EXPORT_ALL_APPS=true
COLLECT_CONFIGS=true
COLLECT_DASHBOARDS=true
COLLECT_ALERTS=true
COLLECT_RBAC=false          # OFF by default - use --rbac to enable (slow, often not needed)
COLLECT_USAGE=false         # OFF by default - use --usage to enable (slow analytics queries)
COLLECT_INDEXES=true
COLLECT_LOOKUPS=false
COLLECT_AUDIT=false
ANONYMIZE_DATA=true
AUTO_CONFIRM=false
USAGE_PERIOD="30d"

# App-scoped collection mode - when true, limits all collections to selected apps only
# This dramatically reduces export time when only specific apps are selected
# Auto-enabled when --apps is used (unless --all-apps is also specified)
SCOPE_TO_APPS=false

# Quick mode - skips expensive global analytics entirely, just collects app configs
QUICK_MODE=false

# Non-interactive mode flag (set automatically when all params provided)
NON_INTERACTIVE=false

# Debug mode - enables verbose logging for troubleshooting
DEBUG_MODE=false
DEBUG_LOG_FILE=""

# Rate limiting (to avoid impacting Splunk performance)
API_DELAY_SECONDS=0.05     # Delay between API calls (seconds) - 50ms (was 250ms)
MAX_CONCURRENT_SEARCHES=1  # Don't run multiple searches in parallel
SEARCH_POLL_INTERVAL=1     # How often to check if search is done (seconds)

# =============================================================================
# PHASE 1: ENTERPRISE RESILIENCE CONFIGURATION
# =============================================================================
# These settings enable enterprise-scale exports (4000+ dashboards, 10K+ alerts)
# Override via environment variables: BATCH_SIZE=50 ./dma-splunk-export.sh

# Pagination settings
BATCH_SIZE=${BATCH_SIZE:-250}              # Items per API request (was 100, increased for speed)
RATE_LIMIT_DELAY=${RATE_LIMIT_DELAY:-0.05} # Delay between paginated requests (50ms - was 100ms)

# Timeout settings - GENEROUS defaults for enterprise environments
API_TIMEOUT=${API_TIMEOUT:-120}            # Per-request timeout (2 min - handles large result sets)
CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-10}     # Connection timeout in seconds
MAX_TOTAL_TIME=${MAX_TOTAL_TIME:-14400}    # Maximum total script runtime (4 hours for 5000+ assets)

# Retry settings
MAX_RETRIES=${MAX_RETRIES:-3}              # Number of retry attempts for failed requests
RETRY_DELAY=${RETRY_DELAY:-2}              # Initial retry delay in seconds (exponential backoff)

# Progress & Resume settings
CHECKPOINT_ENABLED=${CHECKPOINT_ENABLED:-true}   # Enable checkpoint/resume capability
PROGRESS_FILE=""                                  # Set at runtime: .export_progress
CHECKPOINT_FILE=""                                # Set at runtime: .export_checkpoint
ERROR_LOG_FILE=""                                 # Set at runtime: export_errors.log

# Statistics for resilience tracking
STATS_API_CALLS=0
STATS_API_RETRIES=0
STATS_API_FAILURES=0
STATS_BATCHES_COMPLETED=0

# Anonymization mappings (populated at runtime)
declare -A EMAIL_MAP
declare -A HOST_MAP
declare -A WEBHOOK_MAP
declare -A APIKEY_MAP
declare -A SLACK_CHANNEL_MAP
declare -A USERNAME_MAP
ANON_EMAIL_COUNTER=0
ANON_HOST_COUNTER=0
ANON_WEBHOOK_COUNTER=0
ANON_APIKEY_COUNTER=0
ANON_SLACK_COUNTER=0
ANON_USERNAME_COUNTER=0

# Statistics
STATS_APPS=0
STATS_DASHBOARDS=0
STATS_DASHBOARDS_XML=0  # Fallback count from XML files (used if REST API unavailable)
STATS_ALERTS=0
STATS_USERS=0
STATS_INDEXES=0
STATS_ERRORS=0

# Timing
EXPORT_START_TIME=0
EXPORT_END_TIME=0

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Print a horizontal line
print_line() {
  local char="${1:-─}"
  local width="${2:-72}"
  printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# =============================================================================
# DEBUG LOGGING FUNCTIONS
# =============================================================================

# Initialize debug log file
init_debug_log() {
  if [ "$DEBUG_MODE" = "true" ]; then
    DEBUG_LOG_FILE="${EXPORT_DIR:-/tmp}/export_debug.log"
    echo "===============================================================================" > "$DEBUG_LOG_FILE"
    echo "DMA Export Debug Log" >> "$DEBUG_LOG_FILE"
    echo "Started: $(date -Iseconds 2>/dev/null || date)" >> "$DEBUG_LOG_FILE"
    echo "Script Version: $SCRIPT_VERSION" >> "$DEBUG_LOG_FILE"
    echo "===============================================================================" >> "$DEBUG_LOG_FILE"
    echo "" >> "$DEBUG_LOG_FILE"

    # Log environment info
    debug_log "ENV" "Bash Version: ${BASH_VERSION:-unknown}"
    debug_log "ENV" "OS: $(uname -s 2>/dev/null || echo 'unknown') $(uname -r 2>/dev/null || echo '')"
    debug_log "ENV" "Hostname: $(get_hostname)"
    debug_log "ENV" "User: $(whoami 2>/dev/null || echo 'unknown')"
    debug_log "ENV" "PWD: $(pwd)"
    debug_log "ENV" "curl version: $(curl --version 2>/dev/null | head -1 || echo 'not found')"

    echo -e "${CYAN}[DEBUG] Debug logging enabled → $DEBUG_LOG_FILE${NC}"
  fi
}

# Log debug message (only when DEBUG_MODE is true)
# Usage: debug_log "CATEGORY" "message"
debug_log() {
  if [ "$DEBUG_MODE" != "true" ]; then
    return
  fi

  local category="${1:-INFO}"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

  # Write to debug log file
  if [ -n "$DEBUG_LOG_FILE" ] && [ -w "$(dirname "$DEBUG_LOG_FILE" 2>/dev/null || echo "/tmp")" ]; then
    echo "[$timestamp] [$category] $message" >> "$DEBUG_LOG_FILE"
  fi

  # Also show on console in debug mode (with color coding)
  case "$category" in
    ERROR)   echo -e "${RED}[DEBUG:$category] $message${NC}" ;;
    WARN)    echo -e "${YELLOW}[DEBUG:$category] $message${NC}" ;;
    API)     echo -e "${CYAN}[DEBUG:$category] $message${NC}" ;;
    SEARCH)  echo -e "${MAGENTA}[DEBUG:$category] $message${NC}" ;;
    TIMING)  echo -e "${BLUE}[DEBUG:$category] $message${NC}" ;;
    *)       echo -e "${GRAY}[DEBUG:$category] $message${NC}" ;;
  esac
}

# Log API call details (redacts sensitive info)
# Usage: debug_api_call "METHOD" "URL" "HTTP_CODE" "RESPONSE_SIZE" "DURATION_MS"
debug_api_call() {
  if [ "$DEBUG_MODE" != "true" ]; then
    return
  fi

  local method="$1"
  local url="$2"
  local http_code="$3"
  local response_size="${4:-unknown}"
  local duration_ms="${5:-unknown}"

  # Redact sensitive parts of URL
  local safe_url=$(echo "$url" | sed 's/password=[^&]*/password=REDACTED/g' | sed 's/token=[^&]*/token=REDACTED/g')

  debug_log "API" "$method $safe_url → HTTP $http_code (${response_size} bytes, ${duration_ms}ms)"
}

# Log search job lifecycle
# Usage: debug_search_job "ACTION" "SID" "DETAILS"
debug_search_job() {
  if [ "$DEBUG_MODE" != "true" ]; then
    return
  fi

  local action="$1"
  local sid="$2"
  local details="${3:-}"

  debug_log "SEARCH" "[$action] sid=$sid $details"
}

# Log timing for operations
# Usage: debug_timing "OPERATION" "DURATION_SECONDS"
debug_timing() {
  if [ "$DEBUG_MODE" != "true" ]; then
    return
  fi

  local operation="$1"
  local duration="$2"

  debug_log "TIMING" "$operation completed in ${duration}s"
}

# Log current configuration state
debug_config_state() {
  if [ "$DEBUG_MODE" != "true" ]; then
    return
  fi

  debug_log "CONFIG" "SPLUNK_HOST=$SPLUNK_HOST:$SPLUNK_PORT"
  debug_log "CONFIG" "SPLUNK_HOME=$SPLUNK_HOME"
  debug_log "CONFIG" "EXPORT_ALL_APPS=$EXPORT_ALL_APPS"
  debug_log "CONFIG" "SCOPE_TO_APPS=$SCOPE_TO_APPS"
  debug_log "CONFIG" "QUICK_MODE=$QUICK_MODE"
  debug_log "CONFIG" "COLLECT_RBAC=$COLLECT_RBAC"
  debug_log "CONFIG" "COLLECT_USAGE=$COLLECT_USAGE"
  debug_log "CONFIG" "COLLECT_INDEXES=$COLLECT_INDEXES"
  debug_log "CONFIG" "USAGE_PERIOD=$USAGE_PERIOD"
  debug_log "CONFIG" "SELECTED_APPS=(${SELECTED_APPS[*]})"
  debug_log "CONFIG" "BATCH_SIZE=$BATCH_SIZE"
  debug_log "CONFIG" "API_TIMEOUT=$API_TIMEOUT"
}

# Finalize debug log
finalize_debug_log() {
  if [ "$DEBUG_MODE" = "true" ] && [ -n "$DEBUG_LOG_FILE" ]; then
    echo "" >> "$DEBUG_LOG_FILE"
    echo "===============================================================================" >> "$DEBUG_LOG_FILE"
    echo "Export Completed: $(date -Iseconds 2>/dev/null || date)" >> "$DEBUG_LOG_FILE"
    echo "Total Errors: $STATS_ERRORS" >> "$DEBUG_LOG_FILE"
    echo "Total API Calls: $STATS_API_CALLS" >> "$DEBUG_LOG_FILE"
    echo "Total Retries: $STATS_API_RETRIES" >> "$DEBUG_LOG_FILE"
    echo "===============================================================================" >> "$DEBUG_LOG_FILE"

    echo -e "${GREEN}[DEBUG] Debug log saved to: $DEBUG_LOG_FILE${NC}"
  fi
}

# Get hostname with multiple fallbacks (for containers without hostname command)
get_hostname() {
  local mode="${1:-short}"  # short, full, or fqdn

  if [ "$mode" = "short" ] || [ "$mode" = "s" ]; then
    # Try multiple methods for short hostname
    hostname -s 2>/dev/null || \
    cat /etc/hostname 2>/dev/null | cut -d. -f1 || \
    echo "$HOSTNAME" | cut -d. -f1 || \
    cat /proc/sys/kernel/hostname 2>/dev/null | cut -d. -f1 || \
    echo "splunk"
  elif [ "$mode" = "fqdn" ] || [ "$mode" = "f" ]; then
    # Try multiple methods for FQDN
    hostname -f 2>/dev/null || \
    cat /etc/hostname 2>/dev/null || \
    echo "$HOSTNAME" || \
    cat /proc/sys/kernel/hostname 2>/dev/null || \
    echo "splunk.local"
  else
    # Default: try hostname command first, then fallbacks
    hostname 2>/dev/null || \
    cat /etc/hostname 2>/dev/null || \
    echo "$HOSTNAME" || \
    cat /proc/sys/kernel/hostname 2>/dev/null || \
    echo "splunk"
  fi
}

# =============================================================================
# PYTHON JSON HELPER FUNCTIONS (replaces jq dependency)
# =============================================================================
# These functions use Python (Splunk's bundled or system) for JSON processing
# to avoid requiring jq installation on customer servers.

# Global variable for Python command (set during prerequisites check)
PYTHON_CMD=""

# Get a value from a JSON file
# Usage: json_get "file.json" ".field.subfield" [default]
json_get() {
  local file="$1"
  local path="$2"
  local default="${3:-}"

  if [ ! -f "$file" ]; then
    echo "$default"
    return
  fi

  $PYTHON_CMD -c "
import json
import sys

try:
    with open('$file', 'r') as f:
        data = json.load(f)

    # Parse the path (e.g., '.results[0].field' or '.results[:10]')
    path = '''$path'''.strip()
    if path.startswith('.'):
        path = path[1:]

    result = data
    for part in path.replace('][', '.').replace('[', '.').replace(']', '').split('.'):
        if not part:
            continue
        if ':' in part:
            # Handle slicing like [:10]
            start, end = part.split(':')
            start = int(start) if start else None
            end = int(end) if end else None
            result = result[start:end]
        elif part.isdigit():
            result = result[int(part)]
        else:
            result = result.get(part, None) if isinstance(result, dict) else None
            if result is None:
                print('''$default''' or '[]' if '''$default''' == '' else '''$default''')
                sys.exit(0)

    if isinstance(result, (dict, list)):
        print(json.dumps(result))
    elif result is None:
        print('''$default''' if '''$default''' else 'null')
    else:
        print(result)
except Exception as e:
    print('''$default''' if '''$default''' else '[]')
" 2>/dev/null
}

# Get array length from JSON file
# Usage: json_length "file.json" ".results"
json_length() {
  local file="$1"
  local path="${2:-.}"

  if [ ! -f "$file" ]; then
    echo "0"
    return
  fi

  $PYTHON_CMD -c "
import json
try:
    with open('$file', 'r') as f:
        data = json.load(f)
    path = '''$path'''.strip()
    if path.startswith('.'):
        path = path[1:]
    result = data
    for part in path.split('.'):
        if part:
            result = result.get(part, []) if isinstance(result, dict) else []
    print(len(result) if isinstance(result, list) else 0)
except:
    print(0)
" 2>/dev/null
}

# Build a JSON object from arguments
# Usage: json_build key1 value1 key2 value2 ...
json_build() {
  $PYTHON_CMD -c "
import json
import sys

args = sys.argv[1:]
obj = {}
i = 0
while i < len(args) - 1:
    key = args[i]
    val = args[i + 1]
    # Try to parse as JSON first (for nested objects, arrays, numbers, bools)
    try:
        obj[key] = json.loads(val)
    except:
        obj[key] = val
    i += 2
print(json.dumps(obj))
" "$@" 2>/dev/null
}

# Append an object to a JSON array
# Usage: echo '[]' | json_array_append '{"name": "test"}'
json_array_append() {
  local new_item="$1"

  $PYTHON_CMD -c "
import json
import sys

try:
    arr = json.loads(sys.stdin.read())
    item = json.loads('''$new_item''')
    arr.append(item)
    print(json.dumps(arr))
except Exception as e:
    print('[]')
" 2>/dev/null
}

# Validate and pretty-print JSON file
# Usage: json_format "file.json"
json_format() {
  local file="$1"

  $PYTHON_CMD -c "
import json
try:
    with open('$file', 'r') as f:
        data = json.load(f)
    with open('$file', 'w') as f:
        json.dump(data, f, indent=2)
    print('valid')
except Exception as e:
    print('invalid: ' + str(e))
" 2>/dev/null
}

# Escape a string for JSON
# Usage: json_escape "string with \"quotes\""
json_escape() {
  local str="$1"
  $PYTHON_CMD -c "
import json
print(json.dumps('''$str'''))
" 2>/dev/null
}

# Build apps JSON array for manifest
# Usage: build_apps_json "app1" "app2" "app3"
build_apps_json() {
  local export_dir="$1"
  shift
  local apps=("$@")

  $PYTHON_CMD -c "
import json
import os
import re

export_dir = '''$export_dir'''
apps = '''${apps[*]}'''.split()

result = []
for app in apps:
    app_dashboards = 0
    app_alerts = 0
    app_saved = 0
    has_props = False
    has_transforms = False
    has_lookups = False

    # Count dashboards
    for dash_dir in ['default/data/ui/views', 'local/data/ui/views']:
        path = os.path.join(export_dir, app, dash_dir)
        if os.path.isdir(path):
            app_dashboards += len([f for f in os.listdir(path) if f.endswith('.xml')])

    # Count alerts and saved searches
    for conf_dir in ['default', 'local']:
        ss_path = os.path.join(export_dir, app, conf_dir, 'savedsearches.conf')
        if os.path.isfile(ss_path):
            with open(ss_path, 'r') as f:
                content = f.read()
                app_alerts += len(re.findall(r'alert\.track', content))
                app_saved += len(re.findall(r'^\[', content, re.MULTILINE))

        if os.path.isfile(os.path.join(export_dir, app, conf_dir, 'props.conf')):
            has_props = True
        if os.path.isfile(os.path.join(export_dir, app, conf_dir, 'transforms.conf')):
            has_transforms = True

    if os.path.isdir(os.path.join(export_dir, app, 'lookups')):
        has_lookups = True

    result.append({
        'name': app,
        'dashboards': app_dashboards,
        'alerts': app_alerts,
        'saved_searches': app_saved,
        'has_props': has_props,
        'has_transforms': has_transforms,
        'has_lookups': has_lookups
    })

print(json.dumps(result))
" 2>/dev/null || echo "[]"
}

# Build usage intelligence JSON for manifest
# Usage: build_usage_intel_json "$EXPORT_DIR"
build_usage_intel_json() {
  local export_dir="$1"

  $PYTHON_CMD -c "
import json
import os

export_dir = '''$export_dir'''
analytics_dir = os.path.join(export_dir, '_usage_analytics')

def safe_get(file_path, key_path, default):
    \"\"\"Safely get a value from a JSON file.\"\"\"
    try:
        if not os.path.isfile(file_path):
            return default
        with open(file_path, 'r') as f:
            data = json.load(f)
        result = data
        for key in key_path.split('.'):
            if key.startswith('[') and key.endswith(']'):
                idx = key[1:-1]
                if ':' in idx:
                    start, end = idx.split(':')
                    start = int(start) if start else None
                    end = int(end) if end else None
                    result = result[start:end]
                else:
                    result = result[int(idx)]
            else:
                result = result.get(key, default)
        return result
    except:
        return default

def safe_len(file_path, key='results'):
    \"\"\"Safely get length of results array.\"\"\"
    try:
        if not os.path.isfile(file_path):
            return 0
        with open(file_path, 'r') as f:
            data = json.load(f)
        return len(data.get(key, []))
    except:
        return 0

if not os.path.isdir(analytics_dir):
    print('{}')
else:
    result = {
        'summary': {
            'dashboards_never_viewed': safe_len(os.path.join(analytics_dir, 'dashboards_never_viewed.json')),
            'alerts_never_fired': safe_len(os.path.join(analytics_dir, 'alerts_never_fired.json')),
            'users_inactive_30d': safe_len(os.path.join(analytics_dir, 'users_inactive.json')),
            'alerts_with_failures': safe_len(os.path.join(analytics_dir, 'alerts_failed.json'))
        },
        'volume': {
            'avg_daily_gb': safe_get(os.path.join(analytics_dir, 'daily_volume_summary.json'), 'results.[0].avg_daily_gb', 0),
            'peak_daily_gb': safe_get(os.path.join(analytics_dir, 'daily_volume_summary.json'), 'results.[0].peak_daily_gb', 0),
            'total_30d_gb': safe_get(os.path.join(analytics_dir, 'daily_volume_summary.json'), 'results.[0].total_30d_gb', 0),
            'top_indexes_by_volume': safe_get(os.path.join(analytics_dir, 'top_indexes_by_volume.json'), 'results.[:10]', []),
            'top_sourcetypes_by_volume': safe_get(os.path.join(analytics_dir, 'top_sourcetypes_by_volume.json'), 'results.[:10]', []),
            'top_hosts_by_volume': safe_get(os.path.join(analytics_dir, 'top_hosts_by_volume.json'), 'results.[:10]', []),
            'note': 'See _usage_analytics/daily_volume_*.json for full daily breakdown'
        },
        'ingestion_infrastructure': {
            'summary': {
                'total_forwarding_hosts': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/summary.json'), 'results.[0].total_forwarding_hosts', 0),
                'daily_ingestion_gb': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/summary.json'), 'results.[0].daily_avg_gb', 0),
                'hec_enabled': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/hec_usage.json'), 'results.[0].token_count', 0) > 0,
                'hec_daily_gb': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/hec_usage.json'), 'results.[0].daily_avg_gb', 0)
            },
            'by_connection_type': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/by_connection_type.json'), 'results', []),
            'by_input_method': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/by_input_method.json'), 'results', []),
            'by_sourcetype_category': safe_get(os.path.join(analytics_dir, 'ingestion_infrastructure/by_sourcetype_category.json'), 'results', []),
            'note': 'See _usage_analytics/ingestion_infrastructure/ for detailed breakdown'
        },
        'prioritization': {
            'top_dashboards': safe_get(os.path.join(analytics_dir, 'dashboard_views_top100.json'), 'results.[:10]', []),
            'top_users': safe_get(os.path.join(analytics_dir, 'users_most_active.json'), 'results.[:10]', []),
            'top_alerts': safe_get(os.path.join(analytics_dir, 'alerts_most_fired.json'), 'results.[:10]', []),
            'top_sourcetypes': safe_get(os.path.join(analytics_dir, 'sourcetypes_searched.json'), 'results.[:10]', []),
            'top_indexes': safe_get(os.path.join(analytics_dir, 'indexes_searched.json'), 'results.[:10]', [])
        },
        'elimination_candidates': {
            'dashboards_never_viewed_count': safe_len(os.path.join(analytics_dir, 'dashboards_never_viewed.json')),
            'alerts_never_fired_count': safe_len(os.path.join(analytics_dir, 'alerts_never_fired.json')),
            'note': 'See _usage_analytics/ for full lists of candidates'
        }
    }
    print(json.dumps(result))
" 2>/dev/null || echo "{}"
}

# Get host IPs as JSON array (with fallbacks for containers)
# Usage: get_host_ips_json
get_host_ips_json() {
  $PYTHON_CMD -c "
import json
import subprocess
import socket

ips = []
try:
    # Method 1: hostname -I (Linux)
    result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
    if result.returncode == 0 and result.stdout.strip():
        ips = [ip.strip() for ip in result.stdout.split() if ip.strip()][:5]
except:
    pass

if not ips:
    try:
        # Method 2: ip addr (Linux containers)
        result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            import re
            ips = re.findall(r'inet (\d+\.\d+\.\d+\.\d+)', result.stdout)
            ips = [ip for ip in ips if ip != '127.0.0.1'][:5]
    except:
        pass

if not ips:
    try:
        # Method 3: Socket connection (works anywhere)
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ips = [s.getsockname()[0]]
        s.close()
    except:
        pass

print(json.dumps(ips if ips else []))
" 2>/dev/null || echo "[]"
}

# Iterate over JSON array entries and output each as a line
# Usage: json_iterate "file.json" ".entry"
json_iterate() {
  local file="$1"
  local path="${2:-.}"

  $PYTHON_CMD -c "
import json
try:
    with open('$file', 'r') as f:
        data = json.load(f)
    path = '''$path'''.strip()
    if path.startswith('.'):
        path = path[1:]
    result = data
    for part in path.split('.'):
        if part:
            result = result.get(part, []) if isinstance(result, dict) else []
    for item in result:
        print(json.dumps(item))
except:
    pass
" 2>/dev/null
}

# =============================================================================
# PROGRESS BAR AND HISTOGRAM FUNCTIONS (Scale-aware for 1000s of items)
# =============================================================================

# Global progress tracking
PROGRESS_START_TIME=0
PROGRESS_CURRENT=0
PROGRESS_TOTAL=0
PROGRESS_LABEL=""

# Spinner characters for visual feedback
SPINNER_CHARS=('/' '-' '\' '|')
SPINNER_INDEX=0

# Get next spinner character
get_spinner() {
  echo "${SPINNER_CHARS[$SPINNER_INDEX]}"
  SPINNER_INDEX=$(( (SPINNER_INDEX + 1) % 4 ))
}

# Initialize progress bar
# Usage: progress_init "Collecting dashboards" 1500
progress_init() {
  PROGRESS_LABEL="$1"
  PROGRESS_TOTAL="$2"
  PROGRESS_CURRENT=0
  PROGRESS_START_TIME=$(date +%s)

  # Show initial state
  echo -e "\n${CYAN}┌─────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│${NC} ${WHITE}${PROGRESS_LABEL}${NC}"
  echo -e "${CYAN}│${NC} ${GRAY}Total items: ${PROGRESS_TOTAL}${NC}"
  echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

# Update progress bar
# Usage: progress_update 50
# Note: Uses newlines at 5% intervals for container compatibility (kubectl exec)
PROGRESS_LAST_PERCENT=0
progress_update() {
  PROGRESS_CURRENT="$1"
  local percent=0
  local elapsed=$(( $(date +%s) - PROGRESS_START_TIME ))
  local rate=0
  local eta="calculating..."

  if [ "$PROGRESS_TOTAL" -gt 0 ]; then
    percent=$(( (PROGRESS_CURRENT * 100) / PROGRESS_TOTAL ))
  fi

  # Only print at 5% intervals to avoid flooding (container-friendly)
  local interval=5
  local rounded_percent=$(( (percent / interval) * interval ))
  if [ "$rounded_percent" -eq "$PROGRESS_LAST_PERCENT" ] && [ "$percent" -lt 100 ]; then
    return  # Skip - not at a new interval yet
  fi
  PROGRESS_LAST_PERCENT="$rounded_percent"

  # Calculate rate and ETA
  if [ "$elapsed" -gt 0 ] && [ "$PROGRESS_CURRENT" -gt 0 ]; then
    rate=$(( PROGRESS_CURRENT / elapsed ))
    if [ "$rate" -gt 0 ]; then
      local remaining=$(( PROGRESS_TOTAL - PROGRESS_CURRENT ))
      local eta_seconds=$(( remaining / rate ))
      if [ "$eta_seconds" -lt 60 ]; then
        eta="${eta_seconds}s"
      elif [ "$eta_seconds" -lt 3600 ]; then
        eta="$(( eta_seconds / 60 ))m $(( eta_seconds % 60 ))s"
      else
        eta="$(( eta_seconds / 3600 ))h $(( (eta_seconds % 3600) / 60 ))m"
      fi
    fi
  fi

  # Build progress bar (30 chars wide for cleaner output)
  local bar_width=30
  local filled=$(( (percent * bar_width) / 100 ))
  local empty=$(( bar_width - filled ))
  local bar=""

  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  # Print progress line with newline (container-friendly)
  echo -e "${CYAN}│${NC} ${GREEN}${bar}${NC} ${percent}% [${PROGRESS_CURRENT}/${PROGRESS_TOTAL}] ${GRAY}ETA: ${eta}${NC}"
}

# Mark individual task as complete (shows checkmark)
task_complete() {
  local task_name="${1:-Task}"
  echo -e "${GREEN}✓${NC} ${task_name} ${GRAY}done${NC}"
}

# =============================================================================
# ITEM-LEVEL PROGRESS WITH SPINNER (for showing progress within each item)
# =============================================================================

# Show item progress with spinner and per-item percentage
# Usage: item_progress_show "app: SplunkForwarder" 50 100 3 21
# Args: item_name, item_current, item_total, overall_current, overall_total
item_progress_show() {
  local item_name="$1"
  local item_current="${2:-0}"
  local item_total="${3:-100}"
  local overall_current="${4:-0}"
  local overall_total="${5:-1}"

  local spinner=$(get_spinner)
  local item_percent=0
  local overall_percent=0

  if [ "$item_total" -gt 0 ]; then
    item_percent=$(( (item_current * 100) / item_total ))
  fi

  if [ "$overall_total" -gt 0 ]; then
    overall_percent=$(( (overall_current * 100) / overall_total ))
  fi

  # Build item progress bar (30 chars wide)
  local bar_width=30
  local filled=$(( (item_percent * bar_width) / 100 ))
  local empty=$(( bar_width - filled ))
  local bar=""

  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  # Calculate ETA
  local elapsed=$(( $(date +%s) - PROGRESS_START_TIME ))
  local eta="calculating..."
  if [ "$elapsed" -gt 0 ] && [ "$overall_current" -gt 0 ]; then
    local rate=$(( overall_current * 1000 / elapsed ))  # items per 1000 seconds for precision
    if [ "$rate" -gt 0 ]; then
      local remaining=$(( overall_total - overall_current ))
      local eta_seconds=$(( remaining * 1000 / rate ))
      if [ "$eta_seconds" -lt 60 ]; then
        eta="${eta_seconds}s"
      elif [ "$eta_seconds" -lt 3600 ]; then
        eta="$(( eta_seconds / 60 ))m $(( eta_seconds % 60 ))s"
      else
        eta="$(( eta_seconds / 3600 ))h $(( (eta_seconds % 3600) / 60 ))m"
      fi
    fi
  fi

  # Print: spinner item_name | progress_bar | item% [overall/total] ETA
  printf "\r${YELLOW}%s${NC} %-30s ${CYAN}│${NC} ${GREEN}%s${NC} %3d%% ${GRAY}[%d/%d]${NC} ${GRAY}ETA: %s${NC}   " \
    "$spinner" "$item_name" "$bar" "$item_percent" "$overall_current" "$overall_total" "$eta"
}

# Show item completion at 100% with checkmark
# Usage: item_progress_complete "app: SplunkForwarder" 3 21
item_progress_complete() {
  local item_name="$1"
  local overall_current="${2:-0}"
  local overall_total="${3:-1}"

  local overall_percent=0
  if [ "$overall_total" -gt 0 ]; then
    overall_percent=$(( (overall_current * 100) / overall_total ))
  fi

  # Full progress bar for completed item
  local bar="██████████████████████████████"  # 30 filled chars

  printf "\r${GREEN}✓${NC} %-30s ${CYAN}│${NC} ${GREEN}%s${NC} 100%% ${GRAY}[%d/%d]${NC}                    \n" \
    "$item_name" "$bar" "$overall_current" "$overall_total"
}

# Simulate progress for an item with spinner animation
# Usage: simulate_item_progress "app: SplunkForwarder" 3 21 [delay_ms]
simulate_item_progress() {
  local item_name="$1"
  local overall_current="$2"
  local overall_total="$3"
  local delay="${4:-0.02}"  # Default 20ms between updates

  # Simulate progress from 0 to 100 in steps
  local steps=10
  for ((step=1; step<=steps; step++)); do
    local progress=$(( (step * 100) / steps ))
    item_progress_show "$item_name" "$progress" "100" "$overall_current" "$overall_total"
    sleep "$delay"
  done

  # Show completion
  item_progress_complete "$item_name" "$overall_current" "$overall_total"
}

# Complete progress bar
progress_complete() {
  local elapsed=$(( $(date +%s) - PROGRESS_START_TIME ))
  local rate=0

  if [ "$elapsed" -gt 0 ] && [ "$PROGRESS_CURRENT" -gt 0 ]; then
    rate=$(( PROGRESS_CURRENT / elapsed ))
  fi

  # Format elapsed time
  local elapsed_str=""
  if [ "$elapsed" -lt 60 ]; then
    elapsed_str="${elapsed}s"
  elif [ "$elapsed" -lt 3600 ]; then
    elapsed_str="$(( elapsed / 60 ))m $(( elapsed % 60 ))s"
  else
    elapsed_str="$(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m"
  fi

  printf "\r${CYAN}│${NC} ${GREEN}████████████████████████████████████████████████████${NC} 100%% [%d/%d]      \n" \
    "$PROGRESS_TOTAL" "$PROGRESS_TOTAL"
  echo -e "${CYAN}│${NC} ${GREEN}✓ Completed in ${elapsed_str}${NC} (${rate} items/sec)"
  echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${NC}"
}

# Show histogram of item distribution
# Usage: show_histogram "Apps by Dashboard Count" "app1:50" "app2:120" "app3:30" ...
show_histogram() {
  local title="$1"
  shift
  local items=("$@")
  local max_value=0
  local max_label_len=0

  # Find max value and label length
  for item in "${items[@]}"; do
    local label="${item%%:*}"
    local value="${item##*:}"
    if [ "$value" -gt "$max_value" ]; then
      max_value="$value"
    fi
    if [ "${#label}" -gt "$max_label_len" ]; then
      max_label_len="${#label}"
    fi
  done

  # Cap label length
  if [ "$max_label_len" -gt 25 ]; then
    max_label_len=25
  fi

  echo ""
  echo -e "${WHITE}$title${NC}"
  print_line "─" 70

  # Draw histogram bars
  local bar_max=40
  for item in "${items[@]}"; do
    local label="${item%%:*}"
    local value="${item##*:}"
    local bar_len=0

    if [ "$max_value" -gt 0 ]; then
      bar_len=$(( (value * bar_max) / max_value ))
    fi

    # Truncate label if needed
    if [ "${#label}" -gt "$max_label_len" ]; then
      label="${label:0:$((max_label_len-2))}.."
    fi

    # Build bar
    local bar=""
    for ((i=0; i<bar_len; i++)); do bar+="▓"; done

    # Color based on size
    local color="$GREEN"
    if [ "$value" -gt 100 ]; then color="$YELLOW"; fi
    if [ "$value" -gt 500 ]; then color="$RED"; fi

    printf "  %-${max_label_len}s │ ${color}%-${bar_max}s${NC} %5d\n" "$label" "$bar" "$value"
  done

  print_line "─" 70
}

# Show scale warning for large environments
show_scale_warning() {
  local item_type="$1"
  local count="$2"
  local threshold="$3"

  if [ "$count" -gt "$threshold" ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}⚠  LARGE ENVIRONMENT DETECTED${NC}                                       ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}  Found ${WHITE}${count} ${item_type}${NC} (threshold: ${threshold})                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  This export may take ${WHITE}15-60 minutes${NC} depending on:                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    • Network latency to Splunk REST API                               ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    • Disk I/O speed                                                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    • Number of dashboards with complex queries                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${CYAN}Progress bars will show estimated time remaining.${NC}                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi
}

# Print a box header
print_box_header() {
  local title="$1"
  local width=72
  local padding=$(( (width - ${#title} - 4) / 2 ))
  echo ""
  echo -e "${CYAN}${BOX_TL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_TR}${NC}"
  echo -e "${CYAN}${BOX_V}${NC}$(printf '%*s' $padding '')  ${BOLD}${WHITE}$title${NC}  $(printf '%*s' $((width - padding - ${#title} - 4)) '')${CYAN}${BOX_V}${NC}"
  echo -e "${CYAN}${BOX_T}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_B}${NC}"
}

# Print a box content line
print_box_line() {
  local content="$1"
  local width=72
  local stripped=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
  local padding=$((width - ${#stripped}))
  if [ $padding -lt 0 ]; then padding=0; fi
  echo -e "${CYAN}${BOX_V}${NC} $content$(printf '%*s' $padding '')${CYAN}${BOX_V}${NC}"
}

# Print a box footer
print_box_footer() {
  local width=72
  echo -e "${CYAN}${BOX_BL}$(printf '%*s' $width '' | tr ' ' "$BOX_H")${BOX_BR}${NC}"
}

# Print an info box with explanation
print_info_box() {
  local title="$1"
  shift
  print_box_header "$title"
  for line in "$@"; do
    print_box_line "$line"
  done
  print_box_footer
}

# Print success message
success() {
  echo -e "${GREEN}✓${NC} $1"
  log "SUCCESS: $1"
}

# Print error message
error() {
  echo -e "${RED}✗${NC} $1"
  log "ERROR: $1"
  ((STATS_ERRORS++))
}

# Print warning message
warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  log "WARNING: $1"
}

# Print info message
info() {
  echo -e "${CYAN}→${NC} $1"
  log "INFO: $1"
}

# Print progress
progress() {
  echo -e "${BLUE}◐${NC} $1"
  log "PROGRESS: $1"
}

# Logging function
log() {
  if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  fi
}

# Prompt for yes/no with default
prompt_yn() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer

  # If AUTO_CONFIRM or NON_INTERACTIVE is set, return based on default
  if [ "$AUTO_CONFIRM" = true ] || [ "$NON_INTERACTIVE" = "true" ]; then
    echo -e "${DIM}[AUTO] $prompt: ${default}${NC}"
    case "$default" in
      Y|y|yes) return 0 ;;
      *) return 1 ;;
    esac
  fi

  if [ "$default" = "Y" ]; then
    echo -ne "${YELLOW}$prompt (Y/n): ${NC}"
  else
    echo -ne "${YELLOW}$prompt (y/N): ${NC}"
  fi

  read -r answer
  answer=${answer:-$default}
  # Convert to lowercase (portable - works with bash 3.x on macOS)
  answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

  case "$answer" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Prompt for input with default
prompt_input() {
  local prompt="$1"
  local default="$2"
  local var_name="$3"
  local answer

  # Check if variable already has a value (from CLI or environment)
  local current_value
  eval "current_value=\$$var_name"

  # If AUTO_CONFIRM or NON_INTERACTIVE is set, use existing value or default without prompting
  if [ "$AUTO_CONFIRM" = true ] || [ "$NON_INTERACTIVE" = "true" ]; then
    if [ -n "$current_value" ]; then
      echo -e "${DIM}[AUTO] $prompt: ${current_value}${NC}"
      return
    fi
    echo -e "${DIM}[AUTO] $prompt: ${default}${NC}"
    eval "$var_name='$default'"
    return
  fi

  # If value already set, use it as the default
  if [ -n "$current_value" ]; then
    default="$current_value"
  fi

  if [ -n "$default" ]; then
    echo -ne "${YELLOW}$prompt [${default}]: ${NC}"
  else
    echo -ne "${YELLOW}$prompt: ${NC}"
  fi

  read -r answer
  answer=${answer:-$default}

  eval "$var_name='$answer'"
}

# Prompt for password (hidden)
prompt_password() {
  local prompt="$1"
  local var_name="$2"
  local answer

  # If AUTO_CONFIRM or NON_INTERACTIVE is set and password already provided via CLI, skip prompt
  if [ "$AUTO_CONFIRM" = true ] || [ "$NON_INTERACTIVE" = "true" ]; then
    local current_value
    eval "current_value=\$$var_name"
    if [ -n "$current_value" ]; then
      echo -e "${DIM}[AUTO] $prompt: ********${NC}"
      return
    fi
    # No password provided in non-interactive mode - this is an error
    echo -e "${RED}[ERROR] Password required but not provided in non-interactive mode${NC}"
    return 1
  fi

  echo -ne "${YELLOW}$prompt: ${NC}"
  read -rs answer
  echo ""

  eval "$var_name='$answer'"
}

# Check if command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# =============================================================================
# PHASE 1: ENTERPRISE RESILIENCE FUNCTIONS
# =============================================================================
# These functions provide retry logic, pagination, timeouts, and progress
# tracking for enterprise-scale exports (4000+ dashboards, 10K+ alerts)

# Initialize resilience tracking files
# Usage: init_resilience_tracking
init_resilience_tracking() {
  if [ -z "$EXPORT_DIR" ]; then
    return 1
  fi

  PROGRESS_FILE="$EXPORT_DIR/.export_progress"
  CHECKPOINT_FILE="$EXPORT_DIR/.export_checkpoint"
  ERROR_LOG_FILE="$EXPORT_DIR/export_errors.log"

  # Initialize progress file
  cat > "$PROGRESS_FILE" << EOF
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "server": "$SPLUNK_HOST",
  "status": "in_progress",
  "phase1_resilience": true,
  "config": {
    "batch_size": $BATCH_SIZE,
    "max_retries": $MAX_RETRIES,
    "api_timeout": $API_TIMEOUT
  },
  "dashboards": {"total": 0, "exported": 0, "failed": 0},
  "alerts": {"total": 0, "exported": 0, "failed": 0},
  "searches": {"total": 0, "exported": 0, "failed": 0}
}
EOF

  # Initialize error log
  echo "# DMA Export Error Log" > "$ERROR_LOG_FILE"
  echo "# Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$ERROR_LOG_FILE"
  echo "# Server: $SPLUNK_HOST" >> "$ERROR_LOG_FILE"
  echo "# ============================================" >> "$ERROR_LOG_FILE"

  log "Resilience tracking initialized"
}

# Update progress file
# Usage: update_progress "dashboards" "exported" 50
update_progress() {
  local category="$1"
  local field="$2"
  local value="$3"

  if [ -z "$PROGRESS_FILE" ] || [ ! -f "$PROGRESS_FILE" ]; then
    return
  fi

  $PYTHON_CMD -c "
import json
try:
    with open('$PROGRESS_FILE', 'r') as f:
        data = json.load(f)
    if '$category' in data:
        data['$category']['$field'] = $value
    data['last_updated'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    with open('$PROGRESS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    pass
" 2>/dev/null
}

# Log error to error log file
# Usage: log_error "dashboards" "my_dashboard" "Connection timeout after 60s"
log_error() {
  local category="$1"
  local item="$2"
  local error="$3"

  if [ -n "$ERROR_LOG_FILE" ] && [ -f "$ERROR_LOG_FILE" ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$category] $item: $error" >> "$ERROR_LOG_FILE"
  fi

  ((STATS_API_FAILURES++))
}

# Save checkpoint for resume capability
# Usage: save_checkpoint "dashboards" 500 "last_dashboard_name"
save_checkpoint() {
  local category="$1"
  local last_offset="$2"
  local last_item="$3"

  if [ "$CHECKPOINT_ENABLED" != "true" ] || [ -z "$CHECKPOINT_FILE" ]; then
    return
  fi

  cat > "$CHECKPOINT_FILE" << EOF
{
  "category": "$category",
  "last_offset": $last_offset,
  "last_item": "$last_item",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  log "Checkpoint saved: $category at offset $last_offset"
}

# Load checkpoint if exists
# Usage: if load_checkpoint; then RESUME_OFFSET=$LOADED_OFFSET; fi
# Sets: LOADED_CATEGORY, LOADED_OFFSET, LOADED_ITEM
load_checkpoint() {
  LOADED_CATEGORY=""
  LOADED_OFFSET=0
  LOADED_ITEM=""

  if [ "$CHECKPOINT_ENABLED" != "true" ] || [ -z "$CHECKPOINT_FILE" ] || [ ! -f "$CHECKPOINT_FILE" ]; then
    return 1
  fi

  LOADED_CATEGORY=$(json_get "$CHECKPOINT_FILE" ".category" "")
  LOADED_OFFSET=$(json_get "$CHECKPOINT_FILE" ".last_offset" "0")
  LOADED_ITEM=$(json_get "$CHECKPOINT_FILE" ".last_item" "")

  if [ -n "$LOADED_CATEGORY" ] && [ "$LOADED_OFFSET" -gt 0 ]; then
    return 0
  fi

  return 1
}

# Clear checkpoint after successful completion
# Usage: clear_checkpoint
clear_checkpoint() {
  if [ -n "$CHECKPOINT_FILE" ] && [ -f "$CHECKPOINT_FILE" ]; then
    rm -f "$CHECKPOINT_FILE"
    log "Checkpoint cleared"
  fi
}

# Splunk API call with retry logic and timeout
# Usage: splunk_api_call "endpoint" "output_file" [extra_curl_args...]
# Returns: 0 on success, 1 on failure
# Example: splunk_api_call "/servicesNS/-/-/data/ui/views" "$output_file" "-d count=100"
splunk_api_call() {
  local endpoint="$1"
  local output_file="$2"
  shift 2
  local extra_args=("$@")

  local url="https://${SPLUNK_HOST}:${SPLUNK_PORT}${endpoint}"
  local attempt=1
  local delay=$RETRY_DELAY
  local http_code=""
  local success=false
  local start_time=$(date +%s%3N 2>/dev/null || date +%s)

  ((STATS_API_CALLS++))
  debug_log "API" "→ GET $endpoint (attempt 1/$MAX_RETRIES)"

  while [ $attempt -le $MAX_RETRIES ]; do
    # Make the API call with timeout
    http_code=$(curl -k -s -w "%{http_code}" \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$API_TIMEOUT" \
      -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      -H "Accept: application/json" \
      -o "$output_file" \
      "${extra_args[@]}" \
      "$url" 2>/dev/null)

    local end_time=$(date +%s%3N 2>/dev/null || date +%s)
    local duration=$((end_time - start_time))
    local response_size=$(wc -c < "$output_file" 2>/dev/null || echo "0")
    debug_api_call "GET" "$endpoint" "$http_code" "$response_size" "$duration"

    case "$http_code" in
      200)
        success=true
        break
        ;;
      429)
        # Rate limited - exponential backoff
        debug_log "WARN" "Rate limited (429) on $endpoint. Backoff ${delay}s"
        log "Rate limited (429). Waiting ${delay}s before retry $attempt/$MAX_RETRIES"
        ((STATS_API_RETRIES++))
        sleep "$delay"
        delay=$((delay * 2))
        ;;
      500|502|503|504)
        # Server error - retry with backoff
        debug_log "WARN" "Server error ($http_code) on $endpoint. Retry in ${delay}s"
        log "Server error ($http_code). Retry $attempt/$MAX_RETRIES in ${delay}s"
        ((STATS_API_RETRIES++))
        sleep "$delay"
        delay=$((delay * 2))
        ;;
      401|403)
        # Auth error - don't retry
        debug_log "ERROR" "Auth failed ($http_code) on $endpoint"
        log_error "api" "$endpoint" "Authentication error ($http_code)"
        return 1
        ;;
      000)
        # Timeout or connection error
        debug_log "WARN" "Timeout/connection error on $endpoint. Retry in ${delay}s"
        log "Timeout/connection error. Retry $attempt/$MAX_RETRIES in ${delay}s"
        ((STATS_API_RETRIES++))
        sleep "$delay"
        delay=$((delay * 2))
        ;;
      *)
        # Other error
        log "Unexpected error ($http_code). Retry $attempt/$MAX_RETRIES"
        ((STATS_API_RETRIES++))
        sleep "$delay"
        delay=$((delay * 2))
        ;;
    esac

    ((attempt++))
  done

  if [ "$success" = true ]; then
    return 0
  else
    log_error "api" "$endpoint" "Failed after $MAX_RETRIES attempts (last code: $http_code)"
    return 1
  fi
}

# Get total count from Splunk API endpoint (for pagination)
# Usage: total=$(splunk_api_get_count "/servicesNS/-/-/data/ui/views")
splunk_api_get_count() {
  local endpoint="$1"
  local temp_file=$(mktemp)

  # Request with count=0 to get total without fetching all data
  if splunk_api_call "$endpoint" "$temp_file" "-G" "-d" "output_mode=json" "-d" "count=1"; then
    local total=$($PYTHON_CMD -c "
import json
try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    # Try paging.total first, then entry count
    total = data.get('paging', {}).get('total', 0)
    if total == 0:
        total = len(data.get('entry', []))
    print(total)
except:
    print(0)
" 2>/dev/null)
    rm -f "$temp_file"
    echo "$total"
  else
    rm -f "$temp_file"
    echo "0"
  fi
}

# Paginated API call - fetches all results in batches
# Usage: splunk_api_call_paginated "/servicesNS/-/-/data/ui/views" "$output_dir" "dashboards"
# Creates: $output_dir/dashboards_batch_0.json, dashboards_batch_100.json, etc.
# Returns: Total count fetched
splunk_api_call_paginated() {
  local endpoint="$1"
  local output_dir="$2"
  local prefix="$3"
  local start_offset="${4:-0}"

  local offset=$start_offset
  local total_fetched=0
  local batch_num=0
  local empty_batches=0
  local max_empty=3  # Stop after 3 consecutive empty batches

  # First, get total count for progress tracking
  local total_count=$(splunk_api_get_count "$endpoint")

  if [ "$total_count" -eq 0 ]; then
    log "No items found at $endpoint"
    echo "0"
    return
  fi

  log "Starting paginated export: $total_count items at $endpoint"

  # Show scale warning for very large exports
  if [ "$total_count" -gt 1000 ]; then
    show_scale_warning "${prefix}" "$total_count" 1000
  fi

  # Initialize progress
  progress_init "Exporting ${prefix} (paginated)" "$total_count"

  while [ $offset -lt $total_count ] && [ $empty_batches -lt $max_empty ]; do
    local batch_file="$output_dir/${prefix}_batch_${offset}.json"

    # Save checkpoint before each batch
    save_checkpoint "$prefix" "$offset" "batch_$batch_num"

    # Fetch batch with retry
    if splunk_api_call "$endpoint" "$batch_file" "-G" \
        "-d" "output_mode=json" \
        "-d" "count=$BATCH_SIZE" \
        "-d" "offset=$offset"; then

      # Verify we got results
      local batch_count=$($PYTHON_CMD -c "
import json
try:
    with open('$batch_file', 'r') as f:
        data = json.load(f)
    print(len(data.get('entry', [])))
except:
    print(0)
" 2>/dev/null)

      if [ "$batch_count" -eq 0 ]; then
        ((empty_batches++))
        log "Empty batch at offset $offset ($empty_batches consecutive)"
      else
        empty_batches=0
        total_fetched=$((total_fetched + batch_count))
        ((STATS_BATCHES_COMPLETED++))
      fi
    else
      log_error "$prefix" "batch_$offset" "Failed to fetch batch"
      ((empty_batches++))
    fi

    offset=$((offset + BATCH_SIZE))
    ((batch_num++))

    # Update progress
    progress_update "$total_fetched"

    # Rate limiting between batches
    sleep "$RATE_LIMIT_DELAY"
  done

  # Complete progress
  progress_complete

  # Clear checkpoint on success
  if [ $total_fetched -gt 0 ]; then
    clear_checkpoint
  fi

  log "Paginated export complete: $total_fetched items fetched"
  echo "$total_fetched"
}

# Merge paginated batch files into single JSON
# Usage: merge_paginated_batches "$output_dir" "dashboards" "$final_output.json"
merge_paginated_batches() {
  local output_dir="$1"
  local prefix="$2"
  local final_file="$3"

  $PYTHON_CMD -c "
import json
import glob
import os

output_dir = '$output_dir'
prefix = '$prefix'
final_file = '$final_file'

merged = {'entry': []}

# Find and sort batch files
batch_files = sorted(glob.glob(os.path.join(output_dir, f'{prefix}_batch_*.json')))

for batch_file in batch_files:
    try:
        with open(batch_file, 'r') as f:
            data = json.load(f)
        entries = data.get('entry', [])
        merged['entry'].extend(entries)
    except Exception as e:
        print(f'Warning: Could not process {batch_file}: {e}')

# Add metadata
merged['paging'] = {
    'total': len(merged['entry']),
    'merged_from_batches': len(batch_files)
}

# Write merged file
with open(final_file, 'w') as f:
    json.dump(merged, f, indent=2)

print(f'Merged {len(merged[\"entry\"])} entries from {len(batch_files)} batches')
" 2>/dev/null

  log "Merged paginated batches into $final_file"
}

# Finalize export progress file
# Usage: finalize_progress "completed"
finalize_progress() {
  local status="${1:-completed}"

  if [ -z "$PROGRESS_FILE" ] || [ ! -f "$PROGRESS_FILE" ]; then
    return
  fi

  $PYTHON_CMD -c "
import json
try:
    with open('$PROGRESS_FILE', 'r') as f:
        data = json.load(f)
    data['status'] = '$status'
    data['completed_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    data['statistics'] = {
        'api_calls': $STATS_API_CALLS,
        'api_retries': $STATS_API_RETRIES,
        'api_failures': $STATS_API_FAILURES,
        'batches_completed': $STATS_BATCHES_COMPLETED
    }
    with open('$PROGRESS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    pass
" 2>/dev/null
}

# Check for previous incomplete export and offer resume
# Usage: check_resume_export
check_resume_export() {
  if [ "$CHECKPOINT_ENABLED" != "true" ]; then
    return 1
  fi

  if load_checkpoint; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}⚠  PREVIOUS EXPORT DETECTED${NC}                                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}  Found checkpoint from previous export:                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    Category: ${WHITE}$LOADED_CATEGORY${NC}                                              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    Offset:   ${WHITE}$LOADED_OFFSET${NC}                                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if prompt_yn "Resume from last checkpoint?"; then
      return 0  # Resume
    else
      clear_checkpoint
      return 1  # Start fresh
    fi
  fi

  return 1
}

# =============================================================================
# PHASE 2: ENTERPRISE FEATURES - SHC DETECTION & EXPORT SCOPE
# =============================================================================
# Detect Search Head Cluster role and offer appropriate options for large envs

# Detect if running on SHC Captain, Member, or standalone
# Sets: DETECTED_SHC_ROLE (captain, member, standalone)
# Sets: SHC_MEMBER_COUNT (number of cluster members)
detect_shc_role() {
  DETECTED_SHC_ROLE="standalone"
  SHC_MEMBER_COUNT=0

  if [ -z "$SPLUNK_USER" ]; then
    return  # Can't detect without API access
  fi

  local temp_file=$(mktemp)

  # Try to get SHC member info
  if curl -k -s --connect-timeout "$CONNECT_TIMEOUT" --max-time "$API_TIMEOUT" \
      -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/shcluster/member/info?output_mode=json" \
      -o "$temp_file" 2>/dev/null; then

    # Check if this is an SHC member
    if grep -q '"is_registered"' "$temp_file" 2>/dev/null; then
      local is_registered=$($PYTHON_CMD -c "
import json
try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    entry = data.get('entry', [{}])[0].get('content', {})
    print('true' if entry.get('is_registered', False) else 'false')
except:
    print('false')
" 2>/dev/null)

      if [ "$is_registered" = "true" ]; then
        # Check if captain or member
        local status=$($PYTHON_CMD -c "
import json
try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    entry = data.get('entry', [{}])[0].get('content', {})
    print(entry.get('status', 'Unknown'))
except:
    print('Unknown')
" 2>/dev/null)

        if [ "$status" = "Captain" ]; then
          DETECTED_SHC_ROLE="captain"
          IS_SHC_CAPTAIN=true
        else
          DETECTED_SHC_ROLE="member"
        fi
        IS_SHC_MEMBER=true
      fi
    fi
  fi

  # If SHC detected, get member count
  if [ "$IS_SHC_MEMBER" = true ]; then
    if curl -k -s --connect-timeout "$CONNECT_TIMEOUT" --max-time "$API_TIMEOUT" \
        -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
        "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/shcluster/member/members?output_mode=json" \
        -o "$temp_file" 2>/dev/null; then

      SHC_MEMBER_COUNT=$($PYTHON_CMD -c "
import json
try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    print(len(data.get('entry', [])))
except:
    print(0)
" 2>/dev/null)
    fi
  fi

  rm -f "$temp_file"

  log "SHC Detection: role=$DETECTED_SHC_ROLE, members=$SHC_MEMBER_COUNT"
}

# Show SHC warning and options if running on Captain
# Returns: 0 to continue, 1 to exit
show_shc_captain_warning() {
  if [ "$DETECTED_SHC_ROLE" != "captain" ]; then
    return 0
  fi

  echo ""
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║${NC}  ${WHITE}⚠  SEARCH HEAD CLUSTER CAPTAIN DETECTED${NC}                                     ${YELLOW}║${NC}"
  echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}  You are running this script on the ${WHITE}Search Head Cluster Captain${NC}.           ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}  Cluster members: ${WHITE}${SHC_MEMBER_COUNT}${NC}                                                          ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}  ${RED}WARNING:${NC} Exporting from the Captain may cause:                               ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • REST API timeouts due to cluster coordination overhead                   ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • Slower response times for large datasets (4000+ dashboards)              ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • Potential impact on cluster operations                                   ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}  ${GREEN}RECOMMENDATION:${NC} Run this script from:                                        ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • A Search Head ${WHITE}member${NC} (not captain)                                       ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • The ${WHITE}Deployment Server${NC}                                                    ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    • A ${WHITE}standalone search head${NC} with access to configs                         ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${YELLOW}║${NC}  Choose an option:                                                             ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    ${WHITE}[1]${NC} Continue anyway (use smaller batch size: ${BATCH_SIZE})                     ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    ${WHITE}[2]${NC} Continue with reduced batch size (${WHITE}25${NC} items per request)              ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    ${WHITE}[3]${NC} Export local configs only (skip REST API calls)                        ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}    ${WHITE}[4]${NC} Exit and run from different server                                     ${YELLOW}║${NC}"
  echo -e "${YELLOW}║${NC}                                                                                ${YELLOW}║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local choice
  read -p "Enter choice [1-4]: " choice

  case "$choice" in
    1)
      info "Continuing with current settings (batch size: $BATCH_SIZE)"
      return 0
      ;;
    2)
      BATCH_SIZE=25
      API_TIMEOUT=120
      RATE_LIMIT_DELAY=1.0
      info "Reduced batch size to 25, increased timeout to 120s, rate limit to 1s"
      return 0
      ;;
    3)
      COLLECT_USAGE=false
      info "Skipping REST API usage analytics (local configs only)"
      return 0
      ;;
    4)
      echo ""
      echo -e "${YELLOW}Export cancelled. Run the script from an SHC member or deployment server.${NC}"
      exit 0
      ;;
    *)
      info "Invalid choice. Continuing with default settings."
      return 0
      ;;
  esac
}

# Show export scope selection for large environments
# Usage: select_export_scope
select_export_scope() {
  # Only show for large environments or if user requested
  local show_scope_menu=false

  # Get quick count estimates
  local dashboard_count=0
  local alert_count=0

  if [ -n "$SPLUNK_USER" ]; then
    dashboard_count=$(splunk_api_get_count "/servicesNS/-/-/data/ui/views")
    alert_count=$(splunk_api_get_count "/servicesNS/-/-/saved/searches")
  fi

  # Show scope menu for large environments
  if [ "$dashboard_count" -gt 500 ] || [ "$alert_count" -gt 2000 ]; then
    show_scope_menu=true
  fi

  if [ "$show_scope_menu" = false ]; then
    return 0
  fi

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}LARGE ENVIRONMENT DETECTED${NC}                                                   ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Detected: ${WHITE}${dashboard_count}${NC} dashboards, ${WHITE}${alert_count}${NC} saved searches/alerts                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  Choose export scope to optimize for your needs:                               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${WHITE}[1]${NC} Full export (all dashboards, alerts, configs) ${GREEN}[Recommended]${NC}           ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${WHITE}[2]${NC} Dashboards only (skip alerts/saved searches)                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${WHITE}[3]${NC} Alerts only (skip dashboards)                                           ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${WHITE}[4]${NC} Configs only (skip usage analytics, faster export)                      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local choice
  read -p "Enter choice [1-4] (default: 1): " choice
  choice=${choice:-1}

  case "$choice" in
    1)
      info "Full export selected"
      ;;
    2)
      COLLECT_ALERTS=false
      info "Dashboards only - alerts/saved searches will be skipped"
      ;;
    3)
      COLLECT_DASHBOARDS=false
      info "Alerts only - dashboards will be skipped"
      ;;
    4)
      COLLECT_USAGE=false
      COLLECT_AUDIT=false
      info "Configs only - usage analytics skipped for faster export"
      ;;
    *)
      info "Full export selected (default)"
      ;;
  esac

  echo ""
}

# =============================================================================
# PHASE 3: ADVANCED OPTIMIZATION
# =============================================================================
# Smart timeouts, memory-efficient processing, and parallel capabilities

# Calculate appropriate timeout based on expected data volume
# Usage: timeout=$(calculate_smart_timeout 5000 "dashboards")
calculate_smart_timeout() {
  local item_count="${1:-0}"
  local item_type="${2:-items}"

  # Base timeout: 30 seconds minimum
  local base_timeout=30

  # Per-item timeout factors (some operations are slower than others)
  local per_item_factor
  case "$item_type" in
    dashboards)
      per_item_factor=0.1   # 0.1s per dashboard
      ;;
    alerts|searches)
      per_item_factor=0.05  # 0.05s per alert (simpler)
      ;;
    users|rbac)
      per_item_factor=0.02  # Very fast
      ;;
    *)
      per_item_factor=0.1   # Default
      ;;
  esac

  # Calculate: base + (count * factor)
  # Use Python for floating point math
  local calculated=$($PYTHON_CMD -c "
import math
base = $base_timeout
count = $item_count
factor = $per_item_factor
result = int(math.ceil(base + (count * factor)))
# Cap at 10 minutes max
print(min(result, 600))
" 2>/dev/null)

  # Fallback if Python fails
  if [ -z "$calculated" ] || [ "$calculated" -eq 0 ]; then
    calculated=$API_TIMEOUT
  fi

  log "Smart timeout for $item_count $item_type: ${calculated}s"
  echo "$calculated"
}

# Memory-efficient batch merging using streaming
# For very large exports (10K+ items), avoids loading entire JSON into memory
# Usage: merge_batches_streaming "$batch_dir" "dashboards" "$output.json"
merge_batches_streaming() {
  local batch_dir="$1"
  local prefix="$2"
  local output_file="$3"

  $PYTHON_CMD << PYEOF
import json
import os
import glob

batch_dir = '$batch_dir'
prefix = '$prefix'
output_file = '$output_file'

# Find all batch files
batch_files = sorted(glob.glob(os.path.join(batch_dir, f'{prefix}_batch_*.json')))

if not batch_files:
    # No batches found, create empty result
    with open(output_file, 'w') as f:
        json.dump({'entry': [], 'paging': {'total': 0}}, f)
    print('0')
    exit(0)

# Stream write to avoid memory issues
total_count = 0
with open(output_file, 'w') as out:
    out.write('{"entry": [')

    first_entry = True
    for batch_file in batch_files:
        try:
            with open(batch_file, 'r') as f:
                data = json.load(f)

            entries = data.get('entry', [])
            for entry in entries:
                if not first_entry:
                    out.write(',')
                out.write(json.dumps(entry))
                first_entry = False
                total_count += 1

        except Exception as e:
            # Log error but continue with other batches
            print(f'Warning: Error processing {batch_file}: {e}', file=__import__('sys').stderr)
            continue

    out.write('], "paging": {"total": ' + str(total_count) + ', "merged_from_batches": ' + str(len(batch_files)) + '}}')

print(total_count)
PYEOF
}

# Cleanup batch files after successful merge
# Usage: cleanup_batch_files "$batch_dir" "dashboards"
cleanup_batch_files() {
  local batch_dir="$1"
  local prefix="$2"

  local batch_files=$(ls -1 "$batch_dir/${prefix}_batch_"*.json 2>/dev/null | wc -l | tr -d ' ')

  if [ "$batch_files" -gt 0 ]; then
    rm -f "$batch_dir/${prefix}_batch_"*.json
    log "Cleaned up $batch_files batch files for $prefix"
  fi
}

# Show export timing statistics
# Usage: show_export_timing_stats
show_export_timing_stats() {
  local end_time=$(date +%s)
  local total_seconds=$((end_time - EXPORT_START_TIME))

  # Format duration
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  local duration_str=""
  if [ $hours -gt 0 ]; then
    duration_str="${hours}h ${minutes}m ${seconds}s"
  elif [ $minutes -gt 0 ]; then
    duration_str="${minutes}m ${seconds}s"
  else
    duration_str="${seconds}s"
  fi

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}EXPORT STATISTICS${NC}                                                            ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}Total Duration:${NC}  ${WHITE}${duration_str}${NC}                                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}API Statistics:${NC}                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Total API Calls:     ${WHITE}${STATS_API_CALLS}${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Retried Requests:    ${WHITE}${STATS_API_RETRIES}${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Failed Requests:     ${WHITE}${STATS_API_FAILURES}${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Batches Completed:   ${WHITE}${STATS_BATCHES_COMPLETED}${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}Content Exported:${NC}                                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Applications:        ${WHITE}${STATS_APPS}${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Dashboards:          ${WHITE}${STATS_DASHBOARDS}${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Alerts:              ${WHITE}${STATS_ALERTS}${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Users:               ${WHITE}${STATS_USERS}${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    • Indexes:             ${WHITE}${STATS_INDEXES}${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"

  if [ "$STATS_ERRORS" -gt 0 ]; then
    echo -e "${CYAN}║${NC}  ${YELLOW}⚠ Errors:${NC}                ${WHITE}${STATS_ERRORS}${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    See export_errors.log inside the .tar.gz archive                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  fi

  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# =============================================================================
# BANNER AND WELCOME
# =============================================================================

show_banner() {
  # Only clear screen in interactive mode (when running in a terminal)
  if [ -t 0 ] && [ -t 1 ] && [ "$NON_INTERACTIVE" != "true" ]; then
    clear
  fi
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}██████╗ ██╗   ██╗███╗   ██╗ █████╗ ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗${NC} ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝${NC} ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗${NC}   ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝${NC}   ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}██████╔╝   ██║   ██║ ╚████║██║  ██║██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗${NC} ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝${NC} ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                 ${BOLD}${MAGENTA}🏢  SPLUNK ENTERPRISE EXPORT SCRIPT  🏢${NC}                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}          ${DIM}Complete Data Collection for Migration to Dynatrace Gen3${NC}            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                        ${DIM}Version $SCRIPT_VERSION${NC}                                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}   ${DIM}Developed for Dynatrace One by Enterprise Solutions & Architecture${NC}      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                  ${DIM}An ACE Services Division of Dynatrace${NC}                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

show_welcome() {
  print_info_box "WHAT THIS SCRIPT DOES" \
    "" \
    "This script collects data from your ${BOLD}Splunk Enterprise${NC} environment" \
    "to prepare for migration to Dynatrace Gen3 Grail." \
    "" \
    "${BOLD}Data Collected:${NC}" \
    "  ${GREEN}•${NC} Dashboards (Classic SimpleXML and Dashboard Studio)" \
    "  ${GREEN}•${NC} Alerts and Saved Searches (with SPL queries)" \
    "  ${GREEN}•${NC} Users, Roles, and RBAC configurations" \
    "  ${GREEN}•${NC} Search Macros, Eventtypes, and Tags" \
    "  ${GREEN}•${NC} Props.conf and Transforms.conf (field extractions)" \
    "  ${GREEN}•${NC} Index configurations and volume statistics" \
    "  ${GREEN}•${NC} Usage analytics (who uses what, how often)" \
    "  ${GREEN}•${NC} Lookup tables and KV Store collections" \
    "" \
    "${BOLD}Output:${NC}" \
    "  A .tar.gz archive compatible with Dynatrace Migration Assistant app"

  print_info_box "IMPORTANT: THIS IS FOR SPLUNK ENTERPRISE ONLY" \
    "" \
    "${YELLOW}⚠  This script requires SSH/shell access to your Splunk server${NC}" \
    "" \
    "If you have ${BOLD}Splunk Cloud${NC} (Classic or Victoria Experience), please use:" \
    "  ${GREEN}./dma-splunk-cloud-export.sh${NC}" \
    "" \
    "This script reads configuration files directly from \$SPLUNK_HOME"

  echo ""
  echo -e "  ${WHITE}Documentation:${NC} See README-SPLUNK-ENTERPRISE.md for prerequisites"
  echo ""
  print_line "─" 78

  echo ""
  if ! prompt_yn "Ready to begin?"; then
    echo ""
    echo -e "${YELLOW}Export cancelled. Run the script again when ready.${NC}"
    exit 0
  fi

  # Show pre-flight checklist after user confirms
  show_preflight_checklist
}

# Pre-flight checklist - shows requirements BEFORE proceeding
show_preflight_checklist() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}                     ${BOLD}${WHITE}PRE-FLIGHT CHECKLIST${NC}                                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}         ${DIM}Please confirm you have the following before continuing${NC}            ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}SHELL ACCESS:${NC}                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  SSH access to Splunk server (or running locally on Splunk server)    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  User with read access to \$SPLUNK_HOME directory                      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Root/sudo access (may be needed for some configs)                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}SPLUNK REST API ACCESS (Optional - for Usage Analytics):${NC}                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk username with admin privileges                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk password (for REST API searches)                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Access to _audit and _internal indexes                               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}NETWORK REQUIREMENTS:${NC}                                                      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Port 8089 accessible (for REST API - optional)                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}SYSTEM REQUIREMENTS:${NC}                                                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  bash 4.0+ (Linux default - check with: bash --version)               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  curl installed                                                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Python 3 (for JSON parsing) - uses Splunk's bundled Python         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  tar installed                                                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  ~500MB disk space for export                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}INFORMATION TO GATHER:${NC}                                                     ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  \$SPLUNK_HOME path (default: /opt/splunk)                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk role (indexer, search head, etc.)                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Apps to export (or export all)                                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}🔒 DATA PRIVACY & SECURITY:${NC}                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We do NOT collect or export:${NC}                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  User passwords or password hashes                                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  API tokens or session keys                                           ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  Private keys or certificates                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  Your actual log data (only metadata/structure)                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  SSL certificates or .pem files                                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We automatically REDACT:${NC}                                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  password = [REDACTED] in all .conf files                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  secret = [REDACTED] in outputs.conf                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  pass4SymmKey = [REDACTED] in server.conf                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  sslPassword = [REDACTED] in inputs.conf                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We DO collect (for migration):${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Usernames and role assignments (NOT passwords)                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Dashboard/alert ownership (who created what)                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Usage statistics (search counts, not search content)                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  .conf file structure (props, transforms, inputs, etc.)               ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${MAGENTA}TIP:${NC} If you don't have all items, you can still proceed - the script     ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}       will verify each requirement and provide specific guidance.          ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Quick system check
  echo -e "  ${BOLD}Quick System Check:${NC}"

  # Check bash version
  local bash_major="${BASH_VERSINFO[0]:-0}"
  if [ "$bash_major" -ge 4 ]; then
    echo -e "    ${GREEN}✓${NC} bash: ${BASH_VERSION} (4.0+ required)"
  else
    echo -e "    ${RED}✗${NC} bash: ${BASH_VERSION:-unknown} - ${YELLOW}bash 4.0+ REQUIRED${NC}"
    echo -e "      ${DIM}This script uses associative arrays (declare -A) which require bash 4.0+${NC}"
  fi

  # Check curl
  if command -v curl &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} curl: $(curl --version 2>/dev/null | head -1 | cut -d' ' -f2)"
  else
    echo -e "    ${RED}✗${NC} curl: NOT INSTALLED"
  fi

  # Check Python (for JSON processing)
  if [ -n "$PYTHON_CMD" ]; then
    echo -e "    ${GREEN}✓${NC} Python: $($PYTHON_CMD --version 2>&1)"
  elif [ -n "$SPLUNK_HOME" ] && [ -x "$SPLUNK_HOME/bin/python3" ]; then
    echo -e "    ${GREEN}✓${NC} Python: $($SPLUNK_HOME/bin/python3 --version 2>&1) (Splunk bundled)"
  elif command -v python3 &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} Python: $(python3 --version 2>&1)"
  else
    echo -e "    ${YELLOW}!${NC} Python: Using Splunk's bundled Python if available"
  fi

  # Check tar
  if command -v tar &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} tar: available"
  else
    echo -e "    ${RED}✗${NC} tar: NOT INSTALLED"
  fi

  # Check SPLUNK_HOME
  if [ -n "$SPLUNK_HOME" ] && [ -d "$SPLUNK_HOME" ]; then
    echo -e "    ${GREEN}✓${NC} SPLUNK_HOME: $SPLUNK_HOME"
  elif [ -d "/opt/splunk" ]; then
    echo -e "    ${YELLOW}~${NC} SPLUNK_HOME: Not set, but /opt/splunk exists"
  else
    echo -e "    ${YELLOW}~${NC} SPLUNK_HOME: Not set (will prompt later)"
  fi

  echo ""
  if ! prompt_yn "Ready to proceed?"; then
    echo ""
    echo -e "${YELLOW}Export cancelled. Install missing dependencies and try again.${NC}"
    exit 0
  fi
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
  print_box_header "CHECKING PREREQUISITES"
  print_box_line ""
  print_box_line "${WHITE}We need to verify your system has the required tools.${NC}"
  print_box_line ""
  print_box_footer

  echo ""
  local all_ok=true

  # Check bash version
  progress "Checking bash version..."
  if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    success "Bash version ${BASH_VERSION} (4.0+ required)"
  else
    warning "Bash version ${BASH_VERSION} (4.0+ recommended, may work)"
  fi

  # Check curl
  progress "Checking for curl (needed for REST API calls)..."
  if command_exists curl; then
    success "curl is installed"
  else
    error "curl is not installed"
    echo -e "  ${GRAY}Install with: apt-get install curl  OR  yum install curl${NC}"
    all_ok=false
  fi

  # Check tar
  progress "Checking for tar (needed for archive creation)..."
  if command_exists tar; then
    success "tar is installed"
  else
    error "tar is not installed"
    all_ok=false
  fi

  # Check gzip
  progress "Checking for gzip (needed for compression)..."
  if command_exists gzip; then
    success "gzip is installed"
  else
    error "gzip is not installed"
    all_ok=false
  fi

  # Check Python (uses Splunk's bundled Python or system Python)
  progress "Checking for Python 3 (needed for JSON processing)..."
  PYTHON_CMD=""
  # First try Splunk's bundled Python (guaranteed to exist on Splunk servers)
  if [ -n "$SPLUNK_HOME" ] && [ -x "$SPLUNK_HOME/bin/python3" ]; then
    PYTHON_CMD="$SPLUNK_HOME/bin/python3"
    local py_version=$("$PYTHON_CMD" --version 2>&1 | head -1)
    success "Using Splunk's bundled Python: $py_version"
  elif command_exists python3; then
    PYTHON_CMD="python3"
    local py_version=$(python3 --version 2>&1 | head -1)
    success "Using system Python: $py_version"
  elif command_exists python; then
    # Check if python is Python 3
    local py_ver=$(python --version 2>&1 | grep -oP 'Python \K[0-9]+')
    if [ "$py_ver" = "3" ]; then
      PYTHON_CMD="python"
      local py_version=$(python --version 2>&1 | head -1)
      success "Using system Python: $py_version"
    fi
  fi

  if [ -z "$PYTHON_CMD" ]; then
    error "Python 3 is not available"
    echo ""
    echo -e "  ${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}║${NC}  ${WHITE}PYTHON NOT FOUND:${NC}                                               ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}                                                                  ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  Splunk's bundled Python was not found at:                       ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}    \$SPLUNK_HOME/bin/python3                                      ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}                                                                  ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  Make sure SPLUNK_HOME is set correctly, or install Python 3:   ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}    ${CYAN}Ubuntu/Debian:${NC}  sudo apt-get install python3                 ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}    ${CYAN}RHEL/CentOS:${NC}    sudo yum install python3                     ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    all_ok=false
  fi

  # Check disk space
  progress "Checking available disk space in /tmp..."
  local free_space=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$free_space" ] && [ "$free_space" -ge 500 ]; then
    success "Sufficient disk space (${free_space}MB available, 500MB required)"
  else
    warning "Could not verify disk space. Ensure at least 500MB is free in /tmp"
  fi

  echo ""

  if [ "$all_ok" = false ]; then
    error "Some prerequisites are missing. Please install them and try again."
    exit 1
  fi

  success "All prerequisites satisfied!"
  echo ""
}

# =============================================================================
# SPLUNK HOME DETECTION
# =============================================================================

detect_splunk_home() {
  print_info_box "STEP 1: LOCATE SPLUNK INSTALLATION" \
    "" \
    "${WHITE}WHY WE NEED THIS:${NC}" \
    "We need to know where Splunk is installed to read configuration" \
    "files and access the Splunk CLI tools." \
    "" \
    "${WHITE}WHAT WE'LL DO:${NC}" \
    "Automatically detect common Splunk installation paths, or ask" \
    "you to provide the path if we can't find it."

  echo ""
  progress "Searching for Splunk installation..."

  # Check environment variable first
  if [ -n "${SPLUNK_HOME:-}" ] && [ -d "$SPLUNK_HOME" ]; then
    SPLUNK_HOME="${SPLUNK_HOME}"
    success "Found via \$SPLUNK_HOME environment variable: $SPLUNK_HOME"
    return 0
  fi

  # Common installation paths
  local paths=(
    "/opt/splunk"
    "/opt/splunkforwarder"
    "/Applications/Splunk"
    "/Applications/SplunkForwarder"
    "$HOME/splunk"
    "$HOME/splunkforwarder"
    "/usr/local/splunk"
  )

  for path in "${paths[@]}"; do
    if [ -d "$path/etc" ]; then
      SPLUNK_HOME="$path"
      success "Found Splunk installation: $SPLUNK_HOME"
      return 0
    fi
  done

  # Not found - ask user
  echo ""
  warning "Could not automatically detect Splunk installation"
  echo ""
  print_box_line "${WHITE}Please enter the path to your Splunk installation.${NC}"
  print_box_line "This is typically /opt/splunk or /opt/splunkforwarder"
  print_box_footer

  while true; do
    prompt_input "Enter SPLUNK_HOME path" "/opt/splunk" SPLUNK_HOME

    if [ -d "$SPLUNK_HOME/etc" ]; then
      success "Valid Splunk installation found: $SPLUNK_HOME"
      return 0
    else
      error "Invalid path: $SPLUNK_HOME/etc does not exist"
      echo ""
    fi
  done
}

# =============================================================================
# SPLUNK FLAVOR DETECTION
# =============================================================================

detect_splunk_flavor() {
  print_info_box "STEP 2: IDENTIFY SPLUNK DEPLOYMENT TYPE" \
    "" \
    "${WHITE}WHY WE NEED THIS:${NC}" \
    "Different Splunk deployment types (Enterprise, Forwarder, Cloud)" \
    "have different data available for export. We'll tailor the" \
    "collection process based on what's available." \
    "" \
    "${WHITE}WHAT WE'LL CHECK:${NC}" \
    "• Product type (Enterprise vs Universal Forwarder)" \
    "• Architecture (Standalone vs Distributed vs Cloud)" \
    "• Role (Search Head, Indexer, Forwarder, etc.)" \
    "• Cluster membership (SHC, Indexer Cluster)"

  echo ""
  progress "Analyzing Splunk installation..."

  # Check for Universal Forwarder
  if [ -f "$SPLUNK_HOME/etc/splunk-launch.conf" ]; then
    if grep -q "SPLUNK_ROLE=universalforwarder" "$SPLUNK_HOME/etc/splunk-launch.conf" 2>/dev/null; then
      SPLUNK_FLAVOR="uf"
      SPLUNK_ROLE="universal_forwarder"
      info "Detected: Universal Forwarder"
    fi
  fi

  # Check for splunkforwarder in path
  if [[ "$SPLUNK_HOME" == *"splunkforwarder"* ]] && [ -z "$SPLUNK_FLAVOR" ]; then
    SPLUNK_FLAVOR="uf"
    SPLUNK_ROLE="universal_forwarder"
    info "Detected: Universal Forwarder (based on path)"
  fi

  # If not UF, assume Enterprise
  if [ -z "$SPLUNK_FLAVOR" ]; then
    SPLUNK_FLAVOR="enterprise"
    info "Detected: Splunk Enterprise"
  fi

  # Detect architecture and role
  if [ "$SPLUNK_FLAVOR" = "enterprise" ]; then
    local server_conf="$SPLUNK_HOME/etc/system/local/server.conf"

    # Check for Search Head Cluster
    if [ -f "$server_conf" ] && grep -q "\[shclustering\]" "$server_conf" 2>/dev/null; then
      IS_SHC_MEMBER=true
      SPLUNK_ARCHITECTURE="distributed"

      # Check if captain
      local shc_mode=$(grep -A5 "\[shclustering\]" "$server_conf" | grep "mode" | cut -d= -f2 | tr -d ' ')
      if [ "$shc_mode" = "captain" ]; then
        IS_SHC_CAPTAIN=true
        SPLUNK_ROLE="shc_captain"
        info "Detected: Search Head Cluster Captain"
      else
        SPLUNK_ROLE="shc_member"
        info "Detected: Search Head Cluster Member"
      fi
    fi

    # Check for Indexer Cluster
    if [ -f "$server_conf" ] && grep -q "\[clustering\]" "$server_conf" 2>/dev/null; then
      IS_IDX_CLUSTER=true
      local cluster_mode=$(grep -A5 "\[clustering\]" "$server_conf" | grep "mode" | cut -d= -f2 | tr -d ' ')

      case "$cluster_mode" in
        master)
          SPLUNK_ROLE="cluster_master"
          info "Detected: Indexer Cluster Master/Manager"
          ;;
        slave)
          SPLUNK_ROLE="indexer_peer"
          info "Detected: Indexer Cluster Peer"
          ;;
      esac
      SPLUNK_ARCHITECTURE="distributed"
    fi

    # Check for distributed search (search head)
    if [ -f "$SPLUNK_HOME/etc/system/local/distsearch.conf" ]; then
      if grep -q "servers" "$SPLUNK_HOME/etc/system/local/distsearch.conf" 2>/dev/null; then
        SPLUNK_ARCHITECTURE="distributed"
        if [ -z "$SPLUNK_ROLE" ]; then
          SPLUNK_ROLE="search_head"
          info "Detected: Search Head (Distributed)"
        fi
      fi
    fi

    # Check for Heavy Forwarder (no local indexes, has outputs)
    if [ -f "$SPLUNK_HOME/etc/system/local/outputs.conf" ]; then
      local has_indexes=$(ls -1 "$SPLUNK_HOME/var/lib/splunk/" 2>/dev/null | grep -v "^kvstore" | grep -v "^modinput" | wc -l)
      if [ "$has_indexes" -le 2 ]; then
        SPLUNK_FLAVOR="hf"
        SPLUNK_ROLE="heavy_forwarder"
        info "Detected: Heavy Forwarder"
      fi
    fi

    # Check for Deployment Server
    if [ -d "$SPLUNK_HOME/etc/deployment-apps" ]; then
      local app_count=$(ls -1 "$SPLUNK_HOME/etc/deployment-apps/" 2>/dev/null | wc -l)
      if [ "$app_count" -gt 0 ]; then
        SPLUNK_ROLE="deployment_server"
        info "Detected: Deployment Server (${app_count} deployment apps)"
      fi
    fi

    # Check for Splunk Cloud indicators
    if [ -f "$server_conf" ]; then
      if grep -qi "splunkcloud.com" "$server_conf" 2>/dev/null; then
        IS_CLOUD=true
        SPLUNK_ARCHITECTURE="cloud"
        warning "Detected: Splunk Cloud connection"
        echo ""
        print_info_box "SPLUNK CLOUD DETECTED" \
          "" \
          "${RED}This script does NOT support Splunk Cloud.${NC}" \
          "" \
          "Splunk Cloud (Classic and Victoria Experience) does not allow" \
          "SSH access to the infrastructure, which this script requires." \
          "" \
          "For Splunk Cloud migrations, please contact the DMA" \
          "team for a REST API-only export solution." \
          "" \
          "If this is a hybrid environment with on-prem Search Heads" \
          "connected to Splunk Cloud indexers, you may continue."

        echo ""
        if ! prompt_yn "Continue anyway (hybrid environment)?" "N"; then
          echo ""
          echo -e "${YELLOW}Export cancelled. Contact DMA team for Cloud support.${NC}"
          exit 0
        fi
      fi
    fi

    # Default to standalone if no architecture detected
    if [ -z "$SPLUNK_ARCHITECTURE" ]; then
      SPLUNK_ARCHITECTURE="standalone"
      if [ -z "$SPLUNK_ROLE" ]; then
        SPLUNK_ROLE="standalone"
      fi
      info "Detected: Standalone deployment"
    fi
  fi

  # Get Splunk version
  local version_file="$SPLUNK_HOME/etc/splunk.version"
  local splunk_version="Unknown"
  if [ -f "$version_file" ]; then
    splunk_version=$(grep "VERSION" "$version_file" 2>/dev/null | cut -d= -f2)
  fi

  echo ""
  print_box_header "DETECTED ENVIRONMENT"
  print_box_line ""
  print_box_line "  ${WHITE}Product:${NC}       Splunk ${SPLUNK_FLAVOR^}"
  print_box_line "  ${WHITE}Version:${NC}       ${splunk_version}"
  print_box_line "  ${WHITE}Role:${NC}          ${SPLUNK_ROLE//_/ }"
  print_box_line "  ${WHITE}Architecture:${NC}  ${SPLUNK_ARCHITECTURE^}"
  print_box_line "  ${WHITE}SPLUNK_HOME:${NC}   ${SPLUNK_HOME}"
  print_box_line ""

  if [ "$IS_SHC_MEMBER" = true ]; then
    print_box_line "  ${CYAN}Search Head Cluster:${NC} Yes"
    if [ "$IS_SHC_CAPTAIN" = true ]; then
      print_box_line "  ${CYAN}SHC Role:${NC} Captain ${GREEN}(optimal for export)${NC}"
    else
      print_box_line "  ${CYAN}SHC Role:${NC} Member ${YELLOW}(consider exporting from Captain)${NC}"
    fi
  fi

  if [ "$IS_IDX_CLUSTER" = true ]; then
    print_box_line "  ${CYAN}Indexer Cluster:${NC} Yes"
  fi

  print_box_line ""
  print_box_footer

  # Show warnings for limited environments
  if [ "$SPLUNK_FLAVOR" = "uf" ]; then
    echo ""
    print_info_box "LIMITED EXPORT AVAILABLE" \
      "" \
      "${YELLOW}This is a Universal Forwarder installation.${NC}" \
      "" \
      "Universal Forwarders have limited data available:" \
      "  ${GREEN}✓${NC} inputs.conf (data sources being collected)" \
      "  ${GREEN}✓${NC} outputs.conf (forwarding destinations)" \
      "  ${GREEN}✓${NC} props.conf (local parsing rules, if any)" \
      "" \
      "  ${RED}✗${NC} Dashboards (UF has no search capability)" \
      "  ${RED}✗${NC} Alerts (UF cannot run searches)" \
      "  ${RED}✗${NC} Users/RBAC (minimal authentication)" \
      "  ${RED}✗${NC} Usage analytics (no search history)" \
      "" \
      "${WHITE}RECOMMENDATION:${NC} For full export, run this script on your" \
      "Search Head instead."

    echo ""
    if ! prompt_yn "Continue with limited forwarder export?"; then
      echo ""
      echo -e "${YELLOW}Export cancelled.${NC}"
      exit 0
    fi
  fi

  if [ "$IS_SHC_MEMBER" = true ] && [ "$IS_SHC_CAPTAIN" = false ]; then
    echo ""
    print_info_box "SEARCH HEAD CLUSTER NOTICE" \
      "" \
      "${YELLOW}This is an SHC Member, not the Captain.${NC}" \
      "" \
      "While we can export from this member, some shared knowledge" \
      "objects may be incomplete. For the most complete export," \
      "we recommend running on the SHC Captain." \
      "" \
      "To find the Captain:" \
      "  ${CYAN}\$SPLUNK_HOME/bin/splunk show shcluster-status${NC}"

    echo ""
    if ! prompt_yn "Continue exporting from this SHC member?"; then
      echo ""
      echo -e "${YELLOW}Export cancelled. Please run on the SHC Captain.${NC}"
      exit 0
    fi
  fi

  echo ""
  if prompt_yn "Is the detected environment correct?" "Y"; then
    success "Environment confirmed"
  else
    echo ""
    warning "If the detection is incorrect, the export may be incomplete."
    if ! prompt_yn "Continue anyway?" "Y"; then
      exit 0
    fi
  fi
}

# =============================================================================
# APPLICATION SELECTION
# =============================================================================

select_applications() {
  # If apps were pre-selected via --apps flag, skip interactive selection
  if [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    success "Using pre-selected apps from --apps flag: ${SELECTED_APPS[*]}"
    return 0
  fi

  print_info_box "STEP 3: SELECT APPLICATIONS TO EXPORT" \
    "" \
    "${WHITE}WHY WE ASK:${NC}" \
    "Splunk organizes content into \"Apps\" - containers that hold" \
    "dashboards, alerts, saved searches, and configurations. We need" \
    "to know which apps contain the content you want to migrate." \
    "" \
    "${WHITE}WHAT WE COLLECT FROM EACH APP:${NC}" \
    "  • Dashboards (Classic XML and Dashboard Studio JSON)" \
    "  • Alerts and Scheduled Searches (savedsearches.conf)" \
    "  • Field Extractions (props.conf, transforms.conf)" \
    "  • Lookup Tables (.csv files)" \
    "  • Search Macros (macros.conf)" \
    "  • Event Classifications (eventtypes.conf, tags.conf)" \
    "" \
    "${WHITE}RECOMMENDATION:${NC}" \
    "For a complete migration assessment, we recommend exporting" \
    "${GREEN}ALL apps${NC}. This gives DMA the full picture."

  echo ""

  # Discover apps
  progress "Discovering installed applications..."

  local apps_dir="$SPLUNK_HOME/etc/apps"
  declare -a all_apps=()
  declare -A app_dashboards=()
  declare -A app_alerts=()

  if [ -d "$apps_dir" ]; then
    for app_path in "$apps_dir"/*; do
      if [ -d "$app_path" ]; then
        local app_name=$(basename "$app_path")

        # Skip internal apps (start with _)
        if [[ "$app_name" =~ ^_ ]]; then
          continue
        fi

        # Skip Splunk's own system apps (splunk_* and Splunk_*)
        if [[ "$app_name" =~ ^[Ss]plunk_ ]]; then
          continue
        fi

        # Skip Splunk Support Add-ons (SA-*)
        if [[ "$app_name" =~ ^SA- ]]; then
          continue
        fi

        # Skip framework/system/default apps that have no user content
        if [[ "$app_name" =~ ^(framework|appsbrowser|introspection_generator_addon|legacy|learned|sample_app|gettingstarted|launcher|search|SplunkForwarder|SplunkLightForwarder|alert_logevent|alert_webhook)$ ]]; then
          continue
        fi

        all_apps+=("$app_name")

        # Count dashboards (use ls instead of find for container compatibility)
        local dash_count=0
        if [ -d "$app_path/default/data/ui/views" ]; then
          dash_count=$(ls -1 "$app_path/default/data/ui/views/"*.xml 2>/dev/null | wc -l | tr -d ' ')
        fi
        if [ -d "$app_path/local/data/ui/views" ]; then
          local local_dash=$(ls -1 "$app_path/local/data/ui/views/"*.xml 2>/dev/null | wc -l | tr -d ' ')
          dash_count=$((dash_count + local_dash))
        fi
        app_dashboards[$app_name]=$dash_count

        # Count alerts (from savedsearches.conf)
        local alert_count=0
        for conf_dir in "default" "local"; do
          if [ -f "$app_path/$conf_dir/savedsearches.conf" ]; then
            local alerts=$(grep -c "alert.track" "$app_path/$conf_dir/savedsearches.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
            [ -z "$alerts" ] || ! [[ "$alerts" =~ ^[0-9]+$ ]] && alerts=0
            alert_count=$((alert_count + alerts))
          fi
        done
        app_alerts[$app_name]=$alert_count
      fi
    done
  fi

  local app_count=${#all_apps[@]}
  success "Found ${app_count} applications"

  if [ $app_count -eq 0 ]; then
    warning "No user applications found. Only system configurations will be exported."
    return 0
  fi

  echo ""
  echo -e "${WHITE}Discovered Applications:${NC}"
  print_line "─" 72
  printf "  ${BOLD}%-4s %-30s %12s %12s${NC}\n" "#" "App Name" "Dashboards" "Alerts"
  print_line "─" 72

  local idx=1
  for app_name in "${all_apps[@]}"; do
    local dashes=${app_dashboards[$app_name]:-0}
    local alerts=${app_alerts[$app_name]:-0}
    printf "  %-4s %-30s %12s %12s\n" "$idx" "$app_name" "$dashes" "$alerts"
    ((idx++))
  done

  print_line "─" 72
  echo ""

  echo -e "${WHITE}How would you like to select applications?${NC}"
  echo ""
  echo -e "  ${GREEN}1.${NC} Export ${GREEN}ALL${NC} applications ${CYAN}(Recommended for full migration)${NC}"
  echo -e "     → Includes all ${app_count} apps with their complete configurations"
  echo -e "     → Best for comprehensive migration assessment"
  echo ""
  echo -e "  ${GREEN}2.${NC} Enter specific app names ${CYAN}(comma-separated)${NC}"
  echo -e "     → Example: ${GRAY}security_app, ops_monitoring, compliance${NC}"
  echo -e "     → Use this if you know exactly which apps to migrate"
  echo ""
  echo -e "  ${GREEN}3.${NC} Select from numbered list"
  echo -e "     → Enter numbers like: ${GRAY}1,2,5,7-10${NC}"
  echo -e "     → Interactive selection from the list above"
  echo ""
  echo -e "  ${GREEN}4.${NC} Export system configurations only ${CYAN}(no apps)${NC}"
  echo -e "     → Only collects indexes, inputs, system-level configs"
  echo -e "     → Use for infrastructure-only assessment"
  echo ""

  local choice
  prompt_input "Enter your choice" "1" choice

  case "$choice" in
    1)
      EXPORT_ALL_APPS=true
      SELECTED_APPS=("${all_apps[@]}")
      success "Will export ALL ${app_count} applications"
      ;;

    2)
      EXPORT_ALL_APPS=false
      echo ""
      echo -e "${WHITE}Enter app names separated by commas:${NC}"
      echo -e "${GRAY}Example: security_app, ops_monitoring, compliance${NC}"
      echo ""
      local app_input
      prompt_input "App names" "" app_input

      # Parse comma-separated list
      IFS=',' read -ra input_apps <<< "$app_input"

      echo ""
      progress "Validating app names..."

      for input_app in "${input_apps[@]}"; do
        # Trim whitespace
        # Trim whitespace (pure bash, portable)
        input_app="${input_app#"${input_app%%[![:space:]]*}"}"
        input_app="${input_app%"${input_app##*[![:space:]]}"}"

        # Check if app exists
        local found=false
        for known_app in "${all_apps[@]}"; do
          if [ "$known_app" = "$input_app" ]; then
            SELECTED_APPS+=("$input_app")
            success "$input_app - Found (${app_dashboards[$input_app]:-0} dashboards, ${app_alerts[$input_app]:-0} alerts)"
            found=true
            break
          fi
        done

        if [ "$found" = false ]; then
          error "$input_app - NOT FOUND (skipping)"
        fi
      done

      if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
        error "No valid apps selected!"
        echo ""
        if prompt_yn "Would you like to export ALL apps instead?" "Y"; then
          EXPORT_ALL_APPS=true
          SELECTED_APPS=("${all_apps[@]}")
        else
          exit 1
        fi
      fi
      ;;

    3)
      EXPORT_ALL_APPS=false
      echo ""
      echo -e "${WHITE}Enter app numbers (e.g., 1,2,5 or 1-5,8,10):${NC}"
      echo ""
      local num_input
      prompt_input "App numbers" "" num_input

      # Parse number ranges
      local selected_nums=()
      IFS=',' read -ra parts <<< "$num_input"
      for part in "${parts[@]}"; do
        # Trim whitespace (pure bash, no xargs needed)
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          # Range like 1-5
          for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do
            selected_nums+=($i)
          done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
          # Single number
          selected_nums+=($part)
        fi
      done

      echo ""
      progress "Selected apps:"
      for num in "${selected_nums[@]}"; do
        if [ $num -ge 1 ] && [ $num -le $app_count ]; then
          local app_name="${all_apps[$((num-1))]}"
          SELECTED_APPS+=("$app_name")
          success "$app_name (${app_dashboards[$app_name]:-0} dashboards, ${app_alerts[$app_name]:-0} alerts)"
        fi
      done

      if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
        error "No valid apps selected!"
        exit 1
      fi
      ;;

    4)
      EXPORT_ALL_APPS=false
      SELECTED_APPS=()
      info "System configurations only - no apps will be exported"
      ;;

    *)
      warning "Invalid choice. Defaulting to ALL apps."
      EXPORT_ALL_APPS=true
      SELECTED_APPS=("${all_apps[@]}")
      ;;
  esac

  echo ""
  local total_dashes=0
  local total_alerts=0
  for app_name in "${SELECTED_APPS[@]}"; do
    total_dashes=$((total_dashes + ${app_dashboards[$app_name]:-0}))
    total_alerts=$((total_alerts + ${app_alerts[$app_name]:-0}))
  done

  print_box_header "APPLICATION SELECTION SUMMARY"
  print_box_line ""
  print_box_line "  ${WHITE}Apps Selected:${NC}    ${#SELECTED_APPS[@]}"
  print_box_line "  ${WHITE}Total Dashboards:${NC} ${total_dashes}"
  print_box_line "  ${WHITE}Total Alerts:${NC}     ${total_alerts}"
  print_box_line ""
  print_box_footer

  STATS_APPS=${#SELECTED_APPS[@]}

  echo ""
  if ! prompt_yn "Proceed with this selection?" "Y"; then
    echo ""
    echo -e "${YELLOW}Export cancelled.${NC}"
    exit 0
  fi
}

# =============================================================================
# DATA CATEGORY SELECTION
# =============================================================================

select_data_categories() {
  print_info_box "STEP 4: SELECT DATA CATEGORIES TO COLLECT" \
    "" \
    "${WHITE}WHY WE ASK:${NC}" \
    "Different migration scenarios require different data. For" \
    "example, if you only want to migrate dashboards, you might" \
    "skip user activity data. However, for a complete migration" \
    "assessment, we recommend collecting everything." \
    "" \
    "${WHITE}RECOMMENDATION:${NC}" \
    "Accept the defaults (options 1-6) for comprehensive analysis."

  echo ""
  echo -e "${WHITE}Select data categories to collect:${NC}"
  echo ""

  echo -e "  ${GREEN}[✓]${NC} 1. ${WHITE}Configuration Files${NC} (props, transforms, indexes, inputs)"
  echo -e "      → ${GRAY}Required for understanding data pipeline${NC}"
  echo ""
  echo -e "  ${GREEN}[✓]${NC} 2. ${WHITE}Dashboards${NC} (Classic XML + Dashboard Studio JSON)"
  echo -e "      → ${GRAY}Visual content for conversion to Dynatrace apps${NC}"
  echo ""
  echo -e "  ${GREEN}[✓]${NC} 3. ${WHITE}Alerts & Saved Searches${NC} (savedsearches.conf)"
  echo -e "      → ${GRAY}Critical for operational continuity${NC}"
  echo ""
  echo -e "  ${YELLOW}[ ]${NC} 4. ${WHITE}Users, Roles & Groups${NC} (RBAC data - NO passwords)"
  echo -e "      → ${GRAY}Usernames and roles only - passwords are NEVER collected${NC}"
  echo -e "      → ${YELLOW}OFF by default - enable with toggle or --rbac flag${NC}"
  echo ""
  echo -e "  ${YELLOW}[ ]${NC} 5. ${WHITE}Usage Analytics${NC} (search frequency, dashboard views)"
  echo -e "      → ${GRAY}Identifies high-value assets worth migrating${NC}"
  echo -e "      → ${YELLOW}OFF by default - enable with toggle or --usage flag${NC}"
  echo ""
  echo -e "  ${GREEN}[✓]${NC} 6. ${WHITE}Index & Data Statistics${NC}"
  echo -e "      → ${GRAY}Volume metrics for capacity planning${NC}"
  echo ""
  echo -e "  ${YELLOW}[ ]${NC} 7. ${WHITE}Lookup Tables${NC} (.csv files)"
  echo -e "      → ${GRAY}Reference data used in searches${NC}"
  echo -e "      → ${YELLOW}May contain sensitive data - review before including${NC}"
  echo ""
  echo -e "  ${YELLOW}[ ]${NC} 8. ${WHITE}Audit Log Sample${NC} (last 10,000 entries)"
  echo -e "      → ${GRAY}Detailed search patterns for analysis${NC}"
  echo -e "      → ${YELLOW}May contain sensitive query content${NC}"
  echo ""
  echo -e "  ${GREEN}[✓]${NC} 9. ${WHITE}Anonymize Sensitive Data${NC} (emails, hostnames, IPs)"
  echo -e "      → ${GRAY}Replaces real data with consistent fake values${NC}"
  echo -e "      → ${CYAN}ON by default - recommended for security${NC}"
  echo ""

  echo -e "  ${DIM}🔒 Privacy: Passwords are NEVER collected. Secrets in .conf files are auto-redacted.${NC}"
  echo ""
  echo -e "${WHITE}Enter numbers to toggle (e.g., 7,8 to add lookups and audit)${NC}"
  echo -e "${GRAY}Or press Enter to accept defaults [1-3,6,9] (RBAC/Usage OFF):${NC}"
  echo ""

  local toggle_input
  prompt_input "Toggle categories" "" toggle_input

  if [ -n "$toggle_input" ]; then
    IFS=',' read -ra toggles <<< "$toggle_input"
    for toggle in "${toggles[@]}"; do
      # Trim whitespace (pure bash, portable)
      toggle="${toggle#"${toggle%%[![:space:]]*}"}"
      toggle="${toggle%"${toggle##*[![:space:]]}"}"
      case "$toggle" in
        1) COLLECT_CONFIGS=false; info "Configurations: OFF" ;;
        2) COLLECT_DASHBOARDS=false; info "Dashboards: OFF" ;;
        3) COLLECT_ALERTS=false; info "Alerts: OFF" ;;
        4) COLLECT_RBAC=true; info "Users/RBAC: ON" ;;
        5) COLLECT_USAGE=true; info "Usage Analytics: ON" ;;
        6) COLLECT_INDEXES=false; info "Index Stats: OFF" ;;
        7) COLLECT_LOOKUPS=true; info "Lookup Tables: ON" ;;
        8) COLLECT_AUDIT=true; info "Audit Sample: ON" ;;
        9) ANONYMIZE_DATA=false; info "Data Anonymization: OFF - Real emails, hostnames, and IPs will be preserved" ;;
      esac
    done
  fi

  echo ""
  success "Data categories configured"
}

# =============================================================================
# SPLUNK AUTHENTICATION
# =============================================================================

authenticate_splunk() {
  # Skip for Universal Forwarder
  if [ "$SPLUNK_FLAVOR" = "uf" ]; then
    info "Skipping authentication (not required for Universal Forwarder)"
    return 0
  fi

  print_info_box "STEP 5: SPLUNK AUTHENTICATION" \
    "" \
    "${WHITE}WHY WE NEED THIS:${NC}" \
    "Some data requires accessing Splunk's REST API, including:" \
    "  • Dashboard Studio dashboards (stored in KV Store)" \
    "  • User and role information" \
    "  • Usage analytics from internal indexes" \
    "  • Distributed environment topology" \
    "" \
    "${WHITE}REQUIRED PERMISSIONS:${NC}" \
    "The account needs: admin_all_objects, list_users, list_roles" \
    "" \
    "${WHITE}SECURITY NOTE:${NC}" \
    "Credentials are only used locally and are never stored or transmitted."

  echo ""

  prompt_input "Splunk admin username" "admin" SPLUNK_USER
  prompt_password "Splunk admin password" SPLUNK_PASSWORD

  echo ""
  progress "Testing authentication..."

  # Detect management port
  if [ -f "$SPLUNK_HOME/etc/system/local/web.conf" ]; then
    local mgmt_port=$(grep "^mgmtHostPort" "$SPLUNK_HOME/etc/system/local/web.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d: -f2)
    if [ -n "$mgmt_port" ]; then
      SPLUNK_PORT="$mgmt_port"
    fi
  fi

  # Test authentication (use GET request with query parameter)
  local auth_response
  auth_response=$(curl -k -s -w "%{http_code}" \
    -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/authentication/current-context?output_mode=json" \
    -o /tmp/dma_auth_test.json 2>&1)

  local http_code="${auth_response: -3}"

  if [ "$http_code" = "200" ]; then
    success "Authentication successful"

    # Check capabilities
    progress "Checking account capabilities..."

    local caps=$(cat /tmp/dma_auth_test.json 2>/dev/null)

    for cap in "admin_all_objects" "list_users" "list_roles"; do
      if echo "$caps" | grep -q "$cap"; then
        success "Capability: $cap"
      else
        warning "Missing capability: $cap (some data may not be collected)"
      fi
    done

    rm -f /tmp/dma_auth_test.json

  elif [ "$http_code" = "401" ]; then
    error "Authentication failed (invalid credentials)"
    echo ""
    # In AUTO_CONFIRM mode, don't retry - just continue without REST API
    if [ "$AUTO_CONFIRM" = true ]; then
      warning "Continuing without REST API access (AUTO_CONFIRM mode). Some data will not be collected."
      SPLUNK_USER=""
      SPLUNK_PASSWORD=""
    elif prompt_yn "Would you like to try again?" "Y"; then
      authenticate_splunk
      return $?
    else
      warning "Continuing without REST API access. Some data will not be collected."
      SPLUNK_USER=""
      SPLUNK_PASSWORD=""
    fi

  else
    error "Could not connect to Splunk REST API (HTTP $http_code)"
    echo ""
    echo -e "${GRAY}This could mean:${NC}"
    echo -e "${GRAY}  • Splunk is not running${NC}"
    echo -e "${GRAY}  • Management port is different from $SPLUNK_PORT${NC}"
    echo -e "${GRAY}  • Firewall blocking localhost connections${NC}"
    echo ""

    if prompt_yn "Continue without REST API access?" "N"; then
      warning "Some data will not be collected (Dashboard Studio, users, usage analytics)"
      SPLUNK_USER=""
      SPLUNK_PASSWORD=""
    else
      exit 1
    fi
  fi

  echo ""
}

# =============================================================================
# USAGE ANALYTICS PERIOD
# =============================================================================

select_usage_period() {
  if [ "$COLLECT_USAGE" = false ]; then
    return 0
  fi

  if [ -z "$SPLUNK_USER" ]; then
    warning "Skipping usage analytics configuration (no REST API access)"
    COLLECT_USAGE=false
    return 0
  fi

  print_info_box "STEP 6: USAGE ANALYTICS TIME PERIOD" \
    "" \
    "${WHITE}WHY WE ASK:${NC}" \
    "Usage analytics help identify which dashboards, alerts, and" \
    "searches are actively used. A longer period gives more accurate" \
    "data but takes longer to collect." \
    "" \
    "${WHITE}RECOMMENDATION:${NC}" \
    "30 days provides a good balance of accuracy and speed."

  echo ""
  echo -e "${WHITE}Select usage analytics collection period:${NC}"
  echo ""
  echo -e "  1. Last 7 days   ${GRAY}(fastest, limited data)${NC}"
  echo -e "  2. Last 30 days  ${GREEN}(recommended)${NC}"
  echo -e "  3. Last 90 days  ${GRAY}(more comprehensive)${NC}"
  echo -e "  4. Last 365 days ${GRAY}(full year, slowest)${NC}"
  echo -e "  5. Skip usage analytics"
  echo ""

  local choice
  prompt_input "Enter choice" "2" choice

  case "$choice" in
    1) USAGE_PERIOD="7d"; info "Will collect 7 days of usage data" ;;
    2) USAGE_PERIOD="30d"; info "Will collect 30 days of usage data" ;;
    3) USAGE_PERIOD="90d"; info "Will collect 90 days of usage data" ;;
    4) USAGE_PERIOD="365d"; info "Will collect 365 days of usage data" ;;
    5) COLLECT_USAGE=false; info "Usage analytics disabled" ;;
    *) USAGE_PERIOD="30d"; info "Defaulting to 30 days" ;;
  esac

  echo ""
}

# =============================================================================
# CREATE EXPORT DIRECTORY
# =============================================================================

create_export_directory() {
  print_info_box "STEP 7: PREPARING EXPORT" \
    "" \
    "${WHITE}Creating export directory structure...${NC}"

  echo ""

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local hostname=$(get_hostname short)
  EXPORT_NAME="dma_export_${hostname}_${TIMESTAMP}"
  EXPORT_DIR="/tmp/$EXPORT_NAME"
  LOG_FILE="$EXPORT_DIR/export.log"

  progress "Creating directory: $EXPORT_DIR"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"
  # DMA analytics - all migration-specific data collected by DMA
  mkdir -p "$EXPORT_DIR/dma_analytics"
  mkdir -p "$EXPORT_DIR/dma_analytics/system_info"
  mkdir -p "$EXPORT_DIR/dma_analytics/rbac"
  mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics"
  mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure"
  mkdir -p "$EXPORT_DIR/dma_analytics/indexes"
  # Splunk configurations
  mkdir -p "$EXPORT_DIR/_system/local"
  # NOTE: Dashboards are now stored in app-scoped folders (v2 structure)
  # $EXPORT_DIR/{AppName}/dashboards/classic/ and /studio/
  # This prevents name collisions when multiple apps have same-named dashboards

  touch "$LOG_FILE"
  log "DMA Export Started"
  log "Script Version: $SCRIPT_VERSION"
  log "Export Directory: $EXPORT_DIR"

  # Initialize debug logging if enabled
  init_debug_log

  # Initialize Phase 1 resilience tracking
  init_resilience_tracking
  log "Resilience config: BATCH_SIZE=$BATCH_SIZE, MAX_RETRIES=$MAX_RETRIES, API_TIMEOUT=${API_TIMEOUT}s"

  success "Export directory created"
  echo ""
}

# =============================================================================
# COLLECTION FUNCTIONS
# =============================================================================

collect_system_info() {
  progress "Collecting system information..."

  # Basic system info
  {
    echo "{"
    echo "  \"hostname\": \"$(get_hostname)\","
    echo "  \"platform\": \"$(uname -s)\","
    echo "  \"platformVersion\": \"$(uname -r)\","
    echo "  \"architecture\": \"$(uname -m)\","
    echo "  \"splunkHome\": \"$SPLUNK_HOME\","
    echo "  \"splunkFlavor\": \"$SPLUNK_FLAVOR\","
    echo "  \"splunkRole\": \"$SPLUNK_ROLE\","
    echo "  \"splunkArchitecture\": \"$SPLUNK_ARCHITECTURE\","
    echo "  \"exportTimestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"exportVersion\": \"$SCRIPT_VERSION\""
    echo "}"
  } > "$EXPORT_DIR/dma_analytics/system_info/environment.json"

  # Splunk version
  if [ -f "$SPLUNK_HOME/etc/splunk.version" ]; then
    cp "$SPLUNK_HOME/etc/splunk.version" "$EXPORT_DIR/dma_analytics/system_info/"
  fi

  # REST API system info (use -G to force GET request with query params)
  if [ -n "$SPLUNK_USER" ]; then
    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/server/info" \
      -d "output_mode=json" \
      > "$EXPORT_DIR/dma_analytics/system_info/server_info.json" 2>/dev/null

    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/apps/local" \
      -d "output_mode=json" -d "count=0" \
      > "$EXPORT_DIR/dma_analytics/system_info/installed_apps.json" 2>/dev/null

    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/distributed/peers" \
      -d "output_mode=json" \
      > "$EXPORT_DIR/dma_analytics/system_info/search_peers.json" 2>/dev/null

    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/licenser/licenses" \
      -d "output_mode=json" \
      > "$EXPORT_DIR/dma_analytics/system_info/license_info.json" 2>/dev/null
  fi

  success "System information collected"
}

# =============================================================================
# SYSTEM-LEVEL MACROS COLLECTION
# =============================================================================
# Splunk Enterprise stores global macros in multiple locations:
#
# 1. $SPLUNK_HOME/etc/system/local/macros.conf - System-level (automatically global)
# 2. $SPLUNK_HOME/etc/apps/<app>/local/macros.conf with export=system in metadata
#
# The configuration precedence order (highest to lowest):
#   1. etc/users/<user>/<app>/local/macros.conf (private)
#   2. etc/apps/<app>/local/macros.conf (app-level)
#   3. etc/apps/<app>/default/macros.conf (app defaults)
#   4. etc/system/local/macros.conf (GLOBAL - captured here)
#   5. etc/apps/*/local/macros.conf with export=system
#   6. etc/apps/*/default/macros.conf with export=system
#   7. etc/system/default/macros.conf (never modify)
#
# This function captures:
#   - System-level macros (etc/system/local/)
#   - User-level macros if COLLECT_USER_MACROS is enabled
#
# App-level macros and metadata are captured in collect_app_configs()
# =============================================================================
collect_system_macros() {
  progress "Collecting system-level macros..."

  local macros_found=0

  # Create system directory structure in export
  # Using _system prefix to distinguish from app directories
  mkdir -p "$EXPORT_DIR/_system/local"
  mkdir -p "$EXPORT_DIR/_system/default"

  # Capture system/local macros (administrator-created global macros)
  if [ -f "$SPLUNK_HOME/etc/system/local/macros.conf" ]; then
    cp "$SPLUNK_HOME/etc/system/local/macros.conf" "$EXPORT_DIR/_system/local/"
    local count=$(grep -c '^\[' "$SPLUNK_HOME/etc/system/local/macros.conf" 2>/dev/null || echo 0)
    macros_found=$((macros_found + count))
    log "Copied system/local/macros.conf ($count macros)"
  fi

  # Capture system/default macros (Splunk-provided, for reference only)
  if [ -f "$SPLUNK_HOME/etc/system/default/macros.conf" ]; then
    cp "$SPLUNK_HOME/etc/system/default/macros.conf" "$EXPORT_DIR/_system/default/"
    local count=$(grep -c '^\[' "$SPLUNK_HOME/etc/system/default/macros.conf" 2>/dev/null || echo 0)
    macros_found=$((macros_found + count))
    log "Copied system/default/macros.conf ($count macros, reference only)"
  fi

  # Also capture system-level metadata if it exists
  if [ -d "$SPLUNK_HOME/etc/system/metadata" ]; then
    mkdir -p "$EXPORT_DIR/_system/metadata"
    for meta_file in "default.meta" "local.meta"; do
      if [ -f "$SPLUNK_HOME/etc/system/metadata/$meta_file" ]; then
        cp "$SPLUNK_HOME/etc/system/metadata/$meta_file" "$EXPORT_DIR/_system/metadata/"
        log "Copied system/metadata/$meta_file"
      fi
    done
  fi

  # Optionally capture user-level macros (private macros per user)
  # This is disabled by default as user macros may contain sensitive/private searches
  if [ "${COLLECT_USER_MACROS:-false}" = true ] && [ -d "$SPLUNK_HOME/etc/users" ]; then
    info "Collecting user-level macros..."
    mkdir -p "$EXPORT_DIR/_users"

    local user_macro_count=0
    for user_dir in "$SPLUNK_HOME/etc/users/"*/; do
      if [ -d "$user_dir" ]; then
        local user=$(basename "$user_dir")

        for app_dir in "$user_dir"*/; do
          if [ -d "$app_dir" ]; then
            local app=$(basename "$app_dir")

            if [ -f "$app_dir/local/macros.conf" ]; then
              mkdir -p "$EXPORT_DIR/_users/$user/$app/local"
              cp "$app_dir/local/macros.conf" "$EXPORT_DIR/_users/$user/$app/local/"
              local count=$(grep -c '^\[' "$app_dir/local/macros.conf" 2>/dev/null || echo 0)
              user_macro_count=$((user_macro_count + count))
            fi

            # Also capture user-level metadata
            if [ -f "$app_dir/metadata/local.meta" ]; then
              mkdir -p "$EXPORT_DIR/_users/$user/$app/metadata"
              cp "$app_dir/metadata/local.meta" "$EXPORT_DIR/_users/$user/$app/metadata/"
            fi
          fi
        done
      fi
    done

    if [ "$user_macro_count" -gt 0 ]; then
      log "Collected $user_macro_count user-level macros"
      macros_found=$((macros_found + user_macro_count))
    fi
  fi

  if [ "$macros_found" -gt 0 ]; then
    success "System-level macros collected ($macros_found total)"
  else
    info "No system-level macros found (macros may be in app directories)"
  fi
}

collect_app_configs() {
  local app=$1
  local app_path="$SPLUNK_HOME/etc/apps/$app"

  if [ ! -d "$app_path" ]; then
    warning "App directory not found: $app"
    return 1
  fi

  info "Exporting app: $app"
  mkdir -p "$EXPORT_DIR/$app"

  # Configuration files to export
  local conf_files=(
    "props.conf"
    "transforms.conf"
    "eventtypes.conf"
    "tags.conf"
    "indexes.conf"
    "macros.conf"
    "savedsearches.conf"
    "inputs.conf"
    "outputs.conf"
    "collections.conf"
    "fields.conf"
    "workflow_actions.conf"
    "commands.conf"
  )

  # Export from default/ and local/
  for conf_dir in "default" "local"; do
    if [ -d "$app_path/$conf_dir" ]; then
      mkdir -p "$EXPORT_DIR/$app/$conf_dir"

      for conf_file in "${conf_files[@]}"; do
        if [ -f "$app_path/$conf_dir/$conf_file" ]; then
          cp "$app_path/$conf_dir/$conf_file" "$EXPORT_DIR/$app/$conf_dir/"
          log "Copied: $app/$conf_dir/$conf_file"
        fi
      done
    fi
  done

  # Export dashboards (XML) - use cp with glob instead of find for container compatibility
  if [ "$COLLECT_DASHBOARDS" = true ]; then
    for dash_dir in "default/data/ui/views" "local/data/ui/views"; do
      if [ -d "$app_path/$dash_dir" ]; then
        mkdir -p "$EXPORT_DIR/$app/$dash_dir"
        cp "$app_path/$dash_dir/"*.xml "$EXPORT_DIR/$app/$dash_dir/" 2>/dev/null
        local dash_count=$(ls -1 "$EXPORT_DIR/$app/$dash_dir/"*.xml 2>/dev/null | wc -l | tr -d ' ')
        if [ "$dash_count" -gt 0 ]; then
          log "Copied $dash_count dashboards from $app/$dash_dir"
          # NOTE: Don't increment STATS_DASHBOARDS here - it will be counted
          # via REST API in collect_dashboard_studio() to avoid double-counting.
          # The XML files are the same dashboards retrieved via REST API.
          STATS_DASHBOARDS_XML=$((STATS_DASHBOARDS_XML + dash_count))
        fi
      fi
    done
  fi

  # Export lookup tables (use cp with glob instead of find for container compatibility)
  if [ "$COLLECT_LOOKUPS" = true ] && [ -d "$app_path/lookups" ]; then
    mkdir -p "$EXPORT_DIR/$app/lookups"
    cp "$app_path/lookups/"*.csv "$EXPORT_DIR/$app/lookups/" 2>/dev/null
    log "Copied lookup tables from $app"
  fi

  # Export metadata files (essential for determining macro export scope)
  # The local.meta file contains [macros/<name>] export = system for globally shared macros
  if [ -d "$app_path/metadata" ]; then
    mkdir -p "$EXPORT_DIR/$app/metadata"
    for meta_file in "default.meta" "local.meta"; do
      if [ -f "$app_path/metadata/$meta_file" ]; then
        cp "$app_path/metadata/$meta_file" "$EXPORT_DIR/$app/metadata/"
        log "Copied metadata: $app/metadata/$meta_file"
      fi
    done
  fi

  # Count alerts
  local alert_count=0
  for conf_dir in "default" "local"; do
    if [ -f "$EXPORT_DIR/$app/$conf_dir/savedsearches.conf" ]; then
      local alerts=$(grep -c "alert.track" "$EXPORT_DIR/$app/$conf_dir/savedsearches.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
      [ -z "$alerts" ] || ! [[ "$alerts" =~ ^[0-9]+$ ]] && alerts=0
      alert_count=$((alert_count + alerts))
    fi
  done
  STATS_ALERTS=$((STATS_ALERTS + alert_count))

  return 0
}

collect_dashboard_studio() {
  if [ -z "$SPLUNK_USER" ]; then
    warning "Skipping dashboards (no REST API access)"
    return 0
  fi

  if [ "$COLLECT_DASHBOARDS" = false ]; then
    return 0
  fi

  progress "Collecting dashboards via REST API..."

  # Determine which apps to collect dashboards from
  local apps_to_query=()
  if [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    # Use selected apps - query per-app for efficiency
    apps_to_query=("${SELECTED_APPS[@]}")
    info "Collecting dashboards from ${#apps_to_query[@]} selected app(s): ${apps_to_query[*]}"
  else
    # No app filter - query all dashboards globally
    apps_to_query=("-")  # "-" means all apps in Splunk REST API
  fi

  # First pass: count total dashboards across selected apps for progress bar
  local total_dashboards=0
  local dashboard_data=()  # Array of "app|name" pairs

  for app in "${apps_to_query[@]}"; do
    local api_path
    if [ "$app" = "-" ]; then
      api_path="/servicesNS/-/-/data/ui/views"
    else
      api_path="/servicesNS/-/${app}/data/ui/views"
    fi

    local temp_list="$EXPORT_DIR/dma_analytics/system_info/.dashboards_${app//\//_}.json"
    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}${api_path}" \
      -H "Accept: application/json" \
      -d "output_mode=json" -d "count=0" \
      > "$temp_list" 2>/dev/null

    if [ -s "$temp_list" ]; then
      # Extract dashboard names and their owning apps
      while IFS= read -r line; do
        if [ -n "$line" ]; then
          dashboard_data+=("${app}|${line}")
          ((total_dashboards++))
        fi
      done < <(grep -o '"name":"[^"]*"' "$temp_list" | cut -d'"' -f4)
    fi
    rm -f "$temp_list" 2>/dev/null
  done

  if [ $total_dashboards -eq 0 ]; then
    warning "No dashboards found in selected apps"
    return 0
  fi

  # Show scale warning for large environments
  show_scale_warning "dashboards" "$total_dashboards" 200

  # Initialize progress bar
  progress_init "Exporting Dashboards (Classic & Studio)" "$total_dashboards"

  # Parse and export each dashboard with progress
  local classic_count=0
  local studio_count=0
  local failed_count=0

  for entry in "${dashboard_data[@]}"; do
    local query_app="${entry%%|*}"
    local dashboard_name="${entry#*|}"

    # Rate limit API calls
    sleep "$API_DELAY_SECONDS"

    # Fetch dashboard to temp file - use app-specific endpoint for accuracy
    local temp_file="$EXPORT_DIR/dma_analytics/system_info/.dashboard_temp.json"
    local fetch_path
    if [ "$query_app" = "-" ]; then
      fetch_path="/servicesNS/-/-/data/ui/views/$dashboard_name"
    else
      fetch_path="/servicesNS/-/${query_app}/data/ui/views/$dashboard_name"
    fi

    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}${fetch_path}" \
      -H "Accept: application/json" \
      -d "output_mode=json" \
      > "$temp_file" 2>/dev/null

    if [ -s "$temp_file" ]; then
      # Extract the owning app from the dashboard's ACL (v2 structure)
      local dashboard_app=""
      dashboard_app=$(grep -oP '"app"\s*:\s*"\K[^"]+' "$temp_file" 2>/dev/null | head -1)
      if [ -z "$dashboard_app" ]; then
        dashboard_app="${query_app}"
        [ "$dashboard_app" = "-" ] && dashboard_app="unknown_app"
      fi

      # Create app-scoped dashboard folders (v2 structure)
      mkdir -p "$EXPORT_DIR/$dashboard_app/dashboards/classic"
      mkdir -p "$EXPORT_DIR/$dashboard_app/dashboards/studio"

      # Determine dashboard type by examining content
      # Dashboard Studio v2 dashboards can be identified by:
      # 1. eai:data contains "splunk-dashboard-studio" template reference (example dashboards)
      # 2. eai:data contains '<dashboard version="2"' (user-created Studio dashboards)
      # 3. eai:data contains '<definition>' element (contains actual JSON definition)
      # 4. eai:data starts with { (direct JSON format - rare)
      # Classic dashboards have <dashboard> or <form> without version="2"

      local is_studio=false
      local has_json_definition=false
      local is_template_reference=false

      # Check for Dashboard Studio v2 format (user-created dashboards)
      # These have <dashboard version="2"> and <definition><![CDATA[{JSON}]]></definition>
      if grep -q 'version=\\"2\\"' "$temp_file" 2>/dev/null || grep -q 'version=\"2\"' "$temp_file" 2>/dev/null; then
        is_studio=true
        # Check if it has actual JSON definition embedded
        if grep -q '<definition>' "$temp_file" 2>/dev/null || grep -q '\\u003cdefinition\\u003e' "$temp_file" 2>/dev/null; then
          has_json_definition=true
          log "Dashboard Studio v2 with JSON definition: $dashboard_name"
        fi
      fi

      # Check for Dashboard Studio template reference (example dashboards)
      if grep -q "splunk-dashboard-studio" "$temp_file" 2>/dev/null; then
        is_studio=true
        is_template_reference=true
        log "Dashboard Studio template reference: $dashboard_name"
      fi

      # Also check if eai:data starts with { (direct JSON format - some Studio dashboards)
      local eai_data_start=""
      eai_data_start=$(grep -oP '"eai:data"\s*:\s*"\K.' "$temp_file" 2>/dev/null | head -1)
      if [ "$eai_data_start" = "{" ]; then
        is_studio=true
        has_json_definition=true
      fi

      if [ "$is_studio" = true ]; then
        # Dashboard Studio - save to app-scoped studio folder (v2 structure)
        mv "$temp_file" "$EXPORT_DIR/$dashboard_app/dashboards/studio/${dashboard_name}.json"
        ((studio_count++))

        # Extract JSON definition if present and save separately for easier processing
        if [ "$has_json_definition" = true ]; then
          # Try to extract the definition JSON from CDATA
          # The JSON is inside: <definition><![CDATA[{...}]]></definition>
          # In the JSON response, this is escaped as: \\u003cdefinition\\u003e\\u003c![CDATA[{...}]]\\u003e
          local definition_file="$EXPORT_DIR/$dashboard_app/dashboards/studio/${dashboard_name}_definition.json"

          # Extract definition content using Python for reliable JSON/CDATA parsing
          python3 -c "
import json
import re
import sys

try:
    with open('$EXPORT_DIR/$dashboard_app/dashboards/studio/${dashboard_name}.json') as f:
        data = json.load(f)

    eai_data = data.get('entry', [{}])[0].get('content', {}).get('eai:data', '')

    # Look for definition CDATA block
    # Pattern: <definition><![CDATA[{...}]]></definition>
    match = re.search(r'<definition><!\\[CDATA\\[(.+?)\\]\\]></definition>', eai_data, re.DOTALL)
    if match:
        json_content = match.group(1)
        # Validate it's valid JSON
        parsed = json.loads(json_content)
        # Save the extracted JSON
        with open('$definition_file', 'w') as out:
            json.dump(parsed, out, indent=2)
        print('extracted')
    else:
        print('no-definition')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null 1>/dev/null

          if [ -f "$definition_file" ]; then
            log "  → Extracted JSON definition to ${dashboard_name}_definition.json"
          fi
        elif [ "$is_template_reference" = true ]; then
          # Try to extract definition from splunk-dashboard-studio app's compiled JS
          local studio_js_path="$SPLUNK_HOME/etc/apps/splunk-dashboard-studio/appserver/static/build/examples/${dashboard_name}.js"
          if [ -f "$studio_js_path" ]; then
            local definition_file="$EXPORT_DIR/$dashboard_app/dashboards/studio/${dashboard_name}_definition.json"
            # Extract JSON definition from compiled JS using Python
            python3 -c "
import re
import json
import sys

try:
    with open('$studio_js_path', 'r') as f:
        js_content = f.read()

    # Dashboard Studio embeds JSON as: var e={visualizations:{...},dataSources:{...},...}
    # or: const e={...};
    # The definition ends with ,title:\"...\"}; followed by render code

    # Look for the dashboard definition pattern - it starts after '={' and contains layout:
    # Pattern: ={visualizations:...,dataSources:...,layout:...,title:\"...\"}
    # We need to find the balanced braces

    # Find potential start points (after '={' that contain 'visualizations')
    matches = list(re.finditer(r'[=,]\s*(\{[^}]*visualizations[^}]*\{)', js_content))

    for match in matches:
        start_idx = match.start() + 1  # Skip the '=' or ','
        while js_content[start_idx] in ' \t\n':
            start_idx += 1

        # Count braces to find matching close
        brace_count = 0
        idx = start_idx
        in_string = False
        escape_next = False

        while idx < len(js_content):
            char = js_content[idx]

            if escape_next:
                escape_next = False
                idx += 1
                continue

            if char == '\\\\':
                escape_next = True
                idx += 1
                continue

            if char == '\"' and not escape_next:
                in_string = not in_string

            if not in_string:
                if char == '{':
                    brace_count += 1
                elif char == '}':
                    brace_count -= 1
                    if brace_count == 0:
                        # Found the end
                        js_obj = js_content[start_idx:idx+1]

                        # Check if this looks like a dashboard definition
                        if 'layout' in js_obj and 'dataSources' in js_obj:
                            # Convert JS object notation to JSON
                            # Replace unquoted keys with quoted keys
                            json_str = re.sub(r'([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'\1\"\2\":', js_obj)
                            # Replace single quotes with double quotes
                            json_str = json_str.replace(\"'\", '\"')

                            try:
                                # Try to parse and re-serialize for valid JSON
                                # This is a simplified approach - may need refinement
                                with open('$definition_file', 'w') as out:
                                    out.write(js_obj)  # Write raw JS object for now
                                print('extracted')
                                sys.exit(0)
                            except:
                                pass
                        break
            idx += 1

    print('not_found')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null 1>/dev/null

            if [ -f "$definition_file" ]; then
              log "  → Extracted JSON definition from Studio JS: ${dashboard_name}_definition.json"
            else
              log "  → Template reference (JS file found but could not extract definition)"
            fi
          else
            log "  → Template reference (JS file not found: $studio_js_path)"
          fi
        fi

        log "Exported Dashboard Studio: $dashboard_app/$dashboard_name"
      else
        # Classic dashboard - save to app-scoped classic folder (v2 structure)
        mv "$temp_file" "$EXPORT_DIR/$dashboard_app/dashboards/classic/${dashboard_name}.json"
        ((classic_count++))
        log "Exported Classic Dashboard: $dashboard_app/$dashboard_name"
      fi
    else
      ((failed_count++))
      log "Failed to export: $dashboard_name"
      rm -f "$temp_file" 2>/dev/null
    fi

    ((batch_count++))

    # Update progress every batch_size items (reduces terminal I/O overhead)
    if [ $((batch_count % batch_size)) -eq 0 ] || [ "$batch_count" -eq "$total_dashboards" ]; then
      progress_update "$batch_count"
    fi
  done

  # Clean up temp file
  rm -f "$EXPORT_DIR/dma_analytics/system_info/.dashboard_temp.json" 2>/dev/null

  progress_complete

  if [ "$failed_count" -gt 0 ]; then
    warning "Failed to export $failed_count dashboards (see log for details)"
  fi

  success "Exported $classic_count Classic + $studio_count Dashboard Studio dashboards"
  STATS_DASHBOARDS=$((STATS_DASHBOARDS + classic_count + studio_count))

  # Also collect Dashboard Studio example JS files if available
  collect_dashboard_studio_examples
}

# Collect Dashboard Studio example definitions from compiled JS files
collect_dashboard_studio_examples() {
  local studio_examples_dir="$SPLUNK_HOME/etc/apps/splunk-dashboard-studio/appserver/static/build/examples"

  if [ ! -d "$studio_examples_dir" ]; then
    log "Dashboard Studio examples directory not found - skipping"
    return 0
  fi

  progress "Collecting Dashboard Studio example definitions..."

  # Create directory for studio example JS files
  mkdir -p "$EXPORT_DIR/dashboards_studio_examples"

  # Count and copy all example JS files
  local example_count=0
  for js_file in "$studio_examples_dir"/*.js; do
    if [ -f "$js_file" ]; then
      local basename=$(basename "$js_file")
      cp "$js_file" "$EXPORT_DIR/dashboards_studio_examples/"
      ((example_count++))
    fi
  done

  if [ "$example_count" -gt 0 ]; then
    success "Collected $example_count Dashboard Studio example JS files"
    log "  → These contain the actual JSON definitions for example dashboards"
  fi
}

collect_rbac() {
  if [ -z "$SPLUNK_USER" ]; then
    warning "Skipping RBAC collection (no REST API access)"
    return 0
  fi

  if [ "$COLLECT_RBAC" = false ]; then
    return 0
  fi

  progress "Collecting users, roles, and groups..."

  # =========================================================================
  # APP-SCOPED RBAC COLLECTION
  # When scoped mode is enabled, only collect users who have accessed the
  # selected apps. This dramatically reduces the user list in large environments.
  # =========================================================================
  if [ "$SCOPE_TO_APPS" = "true" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    info "App-scoped mode: Collecting users who accessed selected apps only"

    # Build app filter for audit search
    local app_filter=$(get_app_filter "app")

    # Get users who have activity in the selected apps (via _audit)
    # This searches audit logs for search activity within the selected apps
    local user_search="search index=_audit action=search ${app_filter} earliest=-${USAGE_PERIOD} | stats count as activity, latest(_time) as last_active by user | sort -activity"

    # Create a temporary search job to get active users in these apps
    local temp_file=$(mktemp)
    local http_code=$(curl -k -s -w "%{http_code}" -o "$temp_file" \
      -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs" \
      -d "output_mode=json" \
      -d "earliest_time=-${USAGE_PERIOD}" \
      -d "latest_time=now" \
      --data-urlencode "search=$user_search" \
      2>/dev/null)

    if [ "$http_code" = "201" ]; then
      local sid=$(grep -o '"sid":"[^"]*"' "$temp_file" | cut -d'"' -f4)
      if [ -n "$sid" ]; then
        # Wait for search to complete (max 60 seconds)
        local waited=0
        local is_done="false"
        while [ "$is_done" != "true" ] && [ $waited -lt 60 ]; do
          sleep 2
          waited=$((waited + 2))
          local status=$(curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
            "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid" \
            -d "output_mode=json" 2>/dev/null)
          is_done=$(echo "$status" | grep -o '"isDone":[^,}]*' | cut -d: -f2 | tr -d ' ')
        done

        if [ "$is_done" = "true" ]; then
          curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
            "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid/results" \
            -d "output_mode=json" -d "count=0" \
            > "$EXPORT_DIR/dma_analytics/rbac/users_active_in_apps.json" 2>/dev/null

          local active_users=$(grep -c '"user"' "$EXPORT_DIR/dma_analytics/rbac/users_active_in_apps.json" 2>/dev/null | tr -d ' ')
          success "Found $active_users users with activity in selected apps"
        fi
      fi
    fi
    rm -f "$temp_file"
  fi

  # Always collect full user list from REST API (for reference)
  # Users (use -G to force GET request)
  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/authentication/users" \
    -d "output_mode=json" -d "count=0" \
    > "$EXPORT_DIR/dma_analytics/rbac/users.json" 2>/dev/null

  local user_count=$(grep -o '"name"' "$EXPORT_DIR/dma_analytics/rbac/users.json" 2>/dev/null | wc -l | tr -d ' ')
  STATS_USERS=$user_count

  # Roles (use -G to force GET request)
  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/authorization/roles" \
    -d "output_mode=json" -d "count=0" \
    > "$EXPORT_DIR/dma_analytics/rbac/roles.json" 2>/dev/null

  # Auth config (with password redaction)
  if [ -f "$SPLUNK_HOME/etc/system/local/authentication.conf" ]; then
    sed 's/password\s*=.*/password = [REDACTED]/gi' \
      "$SPLUNK_HOME/etc/system/local/authentication.conf" \
      > "$EXPORT_DIR/dma_analytics/rbac/authentication.conf" 2>/dev/null
  fi

  # Authorization config
  if [ -f "$SPLUNK_HOME/etc/system/local/authorize.conf" ]; then
    cp "$SPLUNK_HOME/etc/system/local/authorize.conf" "$EXPORT_DIR/dma_analytics/rbac/"
  fi

  success "Collected $user_count users and roles"
}

# =============================================================================
# APP-SCOPED FILTER HELPERS
# =============================================================================

# Build SPL filter for selected apps
# Usage: get_app_filter "app" -> (app="app1" OR app="app2")
# Usage: get_app_filter "eai:acl.app" -> (eai:acl.app="app1" OR eai:acl.app="app2")
get_app_filter() {
  local field="${1:-app}"

  if [ "$SCOPE_TO_APPS" != "true" ] || [ ${#SELECTED_APPS[@]} -eq 0 ]; then
    # No filtering - return empty string
    echo ""
    return
  fi

  # Build OR clause: (app="app1" OR app="app2" OR ...)
  local filter="("
  local first=true
  for app in "${SELECTED_APPS[@]}"; do
    if [ "$first" = "true" ]; then
      filter+="${field}=\"${app}\""
      first=false
    else
      filter+=" OR ${field}=\"${app}\""
    fi
  done
  filter+=")"

  echo "$filter"
}

# Build SPL IN clause for selected apps
# Usage: get_app_in_clause "app" -> app IN ("app1", "app2")
get_app_in_clause() {
  local field="${1:-app}"

  if [ "$SCOPE_TO_APPS" != "true" ] || [ ${#SELECTED_APPS[@]} -eq 0 ]; then
    echo ""
    return
  fi

  # Build IN clause: app IN ("app1", "app2", ...)
  local apps_quoted=""
  local first=true
  for app in "${SELECTED_APPS[@]}"; do
    if [ "$first" = "true" ]; then
      apps_quoted+="\"${app}\""
      first=false
    else
      apps_quoted+=", \"${app}\""
    fi
  done

  echo "${field} IN (${apps_quoted})"
}

# Build where clause for pipe filtering
# Usage: get_app_where_clause "app" -> | where app IN ("app1", "app2")
get_app_where_clause() {
  local field="${1:-app}"
  local in_clause=$(get_app_in_clause "$field")

  if [ -n "$in_clause" ]; then
    echo "| where $in_clause"
  else
    echo ""
  fi
}

# =============================================================================
# APP-SCOPED ANALYTICS COLLECTION
# =============================================================================
# Collects usage analytics specific to a single app. This is called for each
# app during export to create app-level usage data that's more actionable
# for migration prioritization than global aggregates.
#
# Creates: $EXPORT_DIR/$app/splunk-analysis/
#   - dashboard_views.json      (views for THIS app's dashboards)
#   - alert_firing.json         (firing stats for THIS app's alerts)
#   - search_usage.json         (run counts for THIS app's saved searches)
#   - index_references.json     (which indexes THIS app queries)
# =============================================================================

collect_app_analytics() {
  local app="$1"

  # Skip if no REST API access
  if [ -z "$SPLUNK_USER" ]; then
    return 0
  fi

  # Skip if usage collection disabled
  if [ "$COLLECT_USAGE" = false ]; then
    return 0
  fi

  local analysis_dir="$EXPORT_DIR/$app/splunk-analysis"
  mkdir -p "$analysis_dir"

  log "Collecting app-scoped analytics for: $app"

  # Helper to run a quick search for this app (shorter timeout for per-app queries)
  run_app_search() {
    local search_query="$1"
    local output_file="$2"
    local description="$3"
    local max_wait="${4:-120}"  # 2 minute default for app-specific queries

    # Rate limiting
    sleep "$API_DELAY_SECONDS"

    local temp_file=$(mktemp)
    local http_code

    http_code=$(curl -k -s -w "%{http_code}" -o "$temp_file" \
      -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs" \
      -d "output_mode=json" \
      -d "earliest_time=-${USAGE_PERIOD}" \
      -d "latest_time=now" \
      --data-urlencode "search=$search_query" \
      2>/dev/null)

    local job_response=$(cat "$temp_file")
    rm -f "$temp_file"

    # Handle HTTP errors
    if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
      log "Search failed for $app/$description: HTTP $http_code"
      echo "{\"error\": \"http_$http_code\", \"app\": \"$app\", \"description\": \"$description\"}" > "$output_file"
      return 1
    fi

    local sid=$(echo "$job_response" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$sid" ]; then
      log "No SID returned for $app/$description"
      echo "{\"error\": \"no_sid\", \"app\": \"$app\", \"description\": \"$description\"}" > "$output_file"
      return 1
    fi

    # Wait for completion
    local waited=0
    local is_done="false"

    while [ "$is_done" != "true" ] && [ "$waited" -lt "$max_wait" ]; do
      sleep 3
      waited=$((waited + 3))

      local status=$(curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
        "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid" \
        -d "output_mode=json" 2>/dev/null)

      is_done=$(echo "$status" | grep -o '"isDone":[^,}]*' | cut -d: -f2 | tr -d ' ')
    done

    if [ "$is_done" = "true" ]; then
      curl -k -s -o "$output_file" \
        -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
        "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid/results?output_mode=json&count=0" \
        2>/dev/null
      return 0
    else
      echo "{\"error\": \"timeout\", \"app\": \"$app\", \"description\": \"$description\"}" > "$output_file"
      return 1
    fi
  }

  # -------------------------------------------------------------------------
  # 1. DASHBOARD VIEWS - Top dashboards in THIS app by view count
  # OPTIMIZED: Moved filters to search-time, changed latest() to max()
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_audit action=search search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} user!=splunk-system-user | stats count as view_count, dc(user) as unique_users, max(_time) as last_viewed by dashboard | sort -view_count | head 100" \
    "$analysis_dir/dashboard_views.json" \
    "Dashboard views for $app"

  # -------------------------------------------------------------------------
  # 2. ALERT FIRING STATS - Alert execution stats for THIS app's alerts
  # OPTIMIZED: Removed status=*, changed latest() to max(), simplified eval
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_internal sourcetype=scheduler app=\"$app\" earliest=-${USAGE_PERIOD} | stats count as total_runs, sum(eval(status=\"success\")) as successful, sum(eval(status=\"skipped\")) as skipped, sum(eval(status!=\"success\" AND status!=\"skipped\")) as failed, max(_time) as last_run by savedsearch_name | sort -total_runs | head 100" \
    "$analysis_dir/alert_firing.json" \
    "Alert firing stats for $app"

  # -------------------------------------------------------------------------
  # 3. SAVED SEARCH USAGE - Run frequency for THIS app's saved searches
  # OPTIMIZED: Added | fields early, changed latest() to max()
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_internal sourcetype=scheduler app=\"$app\" earliest=-${USAGE_PERIOD} | fields savedsearch_name, run_time, _time | stats count as run_count, avg(run_time) as avg_runtime, max(run_time) as max_runtime, max(_time) as last_run by savedsearch_name | sort -run_count | head 100" \
    "$analysis_dir/search_usage.json" \
    "Search usage for $app"

  # -------------------------------------------------------------------------
  # 4. INDEX REFERENCES - Which indexes does THIS app query?
  # OPTIMIZED: Added | sample 20 before expensive rex extraction
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_audit action=search app=\"$app\" earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"index\\s*=\\s*(?<idx>[\\w\\*_-]+)\" | stats count as sample_count, dc(user) as unique_users by idx | eval estimated_query_count=sample_count*20 | where isnotnull(idx) | sort -estimated_query_count | head 50" \
    "$analysis_dir/index_references.json" \
    "Index references for $app"

  # -------------------------------------------------------------------------
  # 5. SOURCETYPE REFERENCES - Which sourcetypes does THIS app query?
  # OPTIMIZED: Added | sample 20 before expensive rex extraction
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_audit action=search app=\"$app\" earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"sourcetype\\s*=\\s*(?<st>[\\w\\*_-]+)\" | stats count as sample_count by st | eval estimated_query_count=sample_count*20 | where isnotnull(st) | sort -estimated_query_count | head 50" \
    "$analysis_dir/sourcetype_references.json" \
    "Sourcetype references for $app"

  # -------------------------------------------------------------------------
  # 6a. DASHBOARD VIEW COUNTS - Simpler query for this app (Curator correlates later)
  # OPTIMIZED: Provides reliable data for Curator app to compute "never viewed"
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_audit action=search search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} user!=splunk-system-user savedsearch_name=* | stats count as views by savedsearch_name | rename savedsearch_name as dashboard" \
    "$analysis_dir/dashboard_view_counts.json" \
    "Dashboard view counts for $app"

  # -------------------------------------------------------------------------
  # 6b. DASHBOARDS NEVER VIEWED - Legacy query (uses | rest + | append)
  # Note: Kept for compatibility. Curator app can also compute this from view_counts + manifest
  # -------------------------------------------------------------------------
  run_app_search \
    "index=_audit action=search search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} | stats count by dashboard | append [| rest /servicesNS/-/$app/data/ui/views | table title | rename title as dashboard | eval count=0] | stats sum(count) as total_views by dashboard | where total_views=0 | table dashboard" \
    "$analysis_dir/dashboards_never_viewed.json" \
    "Never-viewed dashboards for $app"

  # -------------------------------------------------------------------------
  # 7. ALERTS NEVER FIRED - Alerts in THIS app that never triggered
  # -------------------------------------------------------------------------
  run_app_search \
    "search index=_internal sourcetype=scheduler app=\"$app\" | stats count by savedsearch_name | append [| rest /servicesNS/-/$app/saved/searches | search is_scheduled=1 | table title | rename title as savedsearch_name | eval count=0] | stats sum(count) as total_runs by savedsearch_name | where total_runs=0 | table savedsearch_name" \
    "$analysis_dir/alerts_never_fired.json" \
    "Never-fired alerts for $app"

  log "Completed app-scoped analytics for: $app"
}

# =============================================================================
# GLOBAL USAGE ANALYTICS (Infrastructure-level)
# =============================================================================
# Collects system-wide analytics that don't make sense at app level:
#   - Index sizes and volume (infrastructure)
#   - Ingestion infrastructure (how data arrives)
#   - RBAC/user mapping (org-level)
#   - License consumption (org-level)
# =============================================================================

collect_usage_analytics() {
  if [ -z "$SPLUNK_USER" ]; then
    warning "Skipping usage analytics (no REST API access)"
    return 0
  fi

  if [ "$COLLECT_USAGE" = false ]; then
    return 0
  fi

  # =========================================================================
  # APP-SCOPED ANALYTICS
  # When scoped mode is enabled, filter all searches to selected apps only.
  # This dramatically reduces search time and result size in large environments.
  # =========================================================================
  local app_filter=""
  local app_where=""
  if [ "$SCOPE_TO_APPS" = "true" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    app_filter=$(get_app_filter "app")
    app_where=$(get_app_where_clause "app")
    echo ""
    echo -e "  ${CYAN}ℹ APP-SCOPED ANALYTICS: Filtering to ${#SELECTED_APPS[@]} app(s)${NC}"
    echo -e "  ${DIM}  Apps: ${SELECTED_APPS[*]}${NC}"
    echo ""
  fi

  # Define collection tasks for progress tracking
  # NOTE: Per-app analytics (dashboard views, alert firing, search usage) are now
  # collected in each app's splunk-analysis/ folder. This function collects
  # GLOBAL/INFRASTRUCTURE analytics that span all apps.
  local tasks=(
    "user_activity:User activity metrics (org-level)"
    "data_source_usage:Data source consumption"
    "daily_volume:Daily volume analysis"
    "ingestion_infra:Ingestion infrastructure"
    "user_role_mapping:User/role mapping (RBAC)"
    "scheduler_status:Scheduler execution stats"
  )

  progress_init "Collecting Usage Intelligence (${USAGE_PERIOD})" "${#tasks[@]}"

  local task_num=0

  # Helper function to run a Splunk search and save results
  # Returns detailed error info for remote debugging
  # Includes rate limiting to avoid impacting Splunk performance
  run_usage_search() {
    local search_query="$1"
    local output_file="$2"
    local description="$3"
    local max_wait="${4:-300}"  # Default 5 minutes - enterprise searches can be slow
    local search_start_time=$(date +%s)

    debug_log "SEARCH" "Starting: $description"
    debug_log "SEARCH" "Query: $(echo "$search_query" | head -c 200)..."

    # Rate limiting: pause before making API call
    log "Rate limit: waiting ${API_DELAY_SECONDS}s before search..."
    sleep "$API_DELAY_SECONDS"

    # Create a search job with full error capture
    local http_code=""
    local job_response=""
    local temp_file=$(mktemp)

    http_code=$(curl -k -s -w "%{http_code}" -o "$temp_file" \
      -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs" \
      -d "output_mode=json" \
      -d "earliest_time=-${USAGE_PERIOD}" \
      -d "latest_time=now" \
      --data-urlencode "search=$search_query" \
      2>/dev/null)

    job_response=$(cat "$temp_file")
    rm -f "$temp_file"

    # Detailed error handling based on HTTP status
    case "$http_code" in
      000)
        log "NETWORK ERROR for '$description': Could not connect to ${SPLUNK_HOST}:${SPLUNK_PORT}"
        echo "{\"error\": \"network_error\", \"description\": \"$description\", \"message\": \"Could not connect to Splunk REST API at ${SPLUNK_HOST}:${SPLUNK_PORT}. Check: 1) Splunk is running 2) Port 8089 is accessible 3) No firewall blocking\", \"http_code\": \"$http_code\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
        ;;
      401)
        log "AUTH ERROR for '$description': Invalid credentials"
        echo "{\"error\": \"auth_error\", \"description\": \"$description\", \"message\": \"Authentication failed. Check username/password or API token.\", \"http_code\": \"$http_code\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
        ;;
      403)
        log "PERMISSION ERROR for '$description': User lacks required capabilities"
        echo "{\"error\": \"permission_error\", \"description\": \"$description\", \"message\": \"User lacks permission. Required capabilities: search, schedule_search. Check role assignments in Splunk.\", \"http_code\": \"$http_code\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
        ;;
      404)
        log "ENDPOINT ERROR for '$description': REST endpoint not found"
        echo "{\"error\": \"endpoint_not_found\", \"description\": \"$description\", \"message\": \"REST API endpoint not found. This may be a Splunk Cloud restriction.\", \"http_code\": \"$http_code\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
        ;;
      500|502|503)
        log "SERVER ERROR for '$description': Splunk server error ($http_code)"
        local escaped_response=$(echo "$job_response" | head -c 500 | $PYTHON_CMD -c "import json,sys; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '"truncated"')
        echo "{\"error\": \"server_error\", \"description\": \"$description\", \"message\": \"Splunk server error. Check splunkd.log for details.\", \"http_code\": \"$http_code\", \"response\": $escaped_response}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
        ;;
    esac

    local sid=$(echo "$job_response" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$sid" ]; then
      # Try to extract error message from response
      local error_msg=$(echo "$job_response" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
      [ -z "$error_msg" ] && error_msg="Unknown error creating search job"

      debug_log "ERROR" "Search job creation failed for '$description': $error_msg"
      log "SEARCH CREATE FAILED for '$description': $error_msg"
      echo "{\"error\": \"search_create_failed\", \"description\": \"$description\", \"message\": \"$error_msg\", \"http_code\": \"$http_code\", \"query_preview\": \"$(echo "$search_query" | head -c 200)\"}" > "$output_file"
      ((STATS_ERRORS++))
      return 1
    fi

    debug_search_job "CREATED" "$sid" "for '$description'"

    # Wait for search to complete with progress indication
    local waited=0
    local is_done="false"
    local last_event_count=0

    while [ "$is_done" != "true" ] && [ "$waited" -lt "$max_wait" ]; do
      sleep "$SEARCH_POLL_INTERVAL"
      waited=$((waited + SEARCH_POLL_INTERVAL))

      local status=$(curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
        "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid" \
        -d "output_mode=json" 2>/dev/null)

      is_done=$(echo "$status" | grep -o '"isDone":[^,}]*' | cut -d: -f2 | tr -d ' ')

      # Check for search errors
      local search_error=$(echo "$status" | grep -o '"isFailed":true')
      if [ -n "$search_error" ]; then
        local fail_msg=$(echo "$status" | grep -o '"messages":\[.*\]' | head -1)
        log "SEARCH FAILED for '$description': $fail_msg"
        echo "{\"error\": \"search_failed\", \"description\": \"$description\", \"message\": \"Search execution failed\", \"search_id\": \"$sid\", \"details\": \"$fail_msg\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
      fi
    done

    if [ "$is_done" = "true" ]; then
      # Get results with error checking (use GET request with query params)
      http_code=$(curl -k -s -w "%{http_code}" -o "$output_file" \
        -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
        "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs/$sid/results?output_mode=json&count=0" \
        2>/dev/null)

      if [ "$http_code" != "200" ]; then
        debug_log "ERROR" "Results fetch failed for sid=$sid: HTTP $http_code"
        log "RESULTS FETCH FAILED for '$description': HTTP $http_code"
        echo "{\"error\": \"results_fetch_failed\", \"description\": \"$description\", \"http_code\": \"$http_code\"}" > "$output_file"
        ((STATS_ERRORS++))
        return 1
      fi

      local search_duration=$(($(date +%s) - search_start_time))
      debug_search_job "COMPLETED" "$sid" "in ${search_duration}s"
      debug_timing "Search: $description" "$search_duration"
      log "Completed search: $description (${waited}s)"
      return 0
    else
      debug_search_job "TIMEOUT" "$sid" "after ${max_wait}s"
      log "TIMEOUT for '$description': Search did not complete in ${max_wait}s"
      echo "{\"error\": \"timeout\", \"description\": \"$description\", \"message\": \"Search timed out after ${max_wait} seconds. For large environments, this search may need more time. Consider running manually: $search_query\", \"search_id\": \"$sid\"}" > "$output_file"
      ((STATS_ERRORS++))
      return 1
    fi
  }

  # Build app filter string for use in searches (empty if not in scoped mode)
  local app_search_filter=""
  if [ -n "$app_filter" ]; then
    app_search_filter="$app_filter "
  fi

  # ==========================================================================
  # 1. USER ACTIVITY METRICS (Org-level)
  # ==========================================================================
  ((task_num++))
  info "Collecting user activity metrics..."

  # Most active users (filtered to selected apps in scoped mode)
  # OPTIMIZED: Moved user filter to search-time, changed latest() to max()
  run_usage_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} user!=splunk-system-user | stats count as search_count, dc(search) as unique_searches, max(_time) as last_active by user | sort -search_count | head 50" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/users_most_active.json" \
    "Most active users"

  # User activity by role
  # OPTIMIZED: Moved filter to search-time
  run_usage_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count as searches, dc(user) as users by roles | sort -searches" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/activity_by_role.json" \
    "Activity by role"

  # Inactive users (no activity in period)
  # OPTIMIZED: Moved filter to search-time, changed latest() to max()
  run_usage_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | stats max(_time) as last_active by user | where last_active < relative_time(now(), \"-30d\") | table user, last_active" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/users_inactive.json" \
    "Inactive users"

  # User sessions per day
  # OPTIMIZED: Moved filter to search-time
  run_usage_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} user!=splunk-system-user | timechart span=1d dc(user) as active_users" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/daily_active_users.json" \
    "Daily active users"

  progress_update "$task_num"
  task_complete "User activity metrics"

  # NOTE: Alert execution statistics are now collected per-app
  # See each app's splunk-analysis/alert_firing.json for app-specific data

  # ==========================================================================
  # 2. DATA SOURCE USAGE (Infrastructure-level)
  # ==========================================================================
  ((task_num++))
  info "Collecting data source usage patterns..."

  # Sourcetypes actually searched (vs configured)
  # OPTIMIZED: Added | sample 20 before expensive rex extraction
  run_usage_search \
    'index=_audit action=search earliest=-${USAGE_PERIOD} | sample 20 | rex field=search "sourcetype=(?<searched_sourcetype>[\w:_-]+)" | stats count as sample_count, dc(user) as users by searched_sourcetype | eval estimated_count=sample_count*20 | sort -estimated_count | head 50' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/sourcetypes_searched.json" \
    "Most searched sourcetypes"

  # Index usage (which indexes are actually queried)
  # OPTIMIZED: Added | sample 20 before expensive rex extraction
  run_usage_search \
    'index=_audit action=search earliest=-${USAGE_PERIOD} | sample 20 | rex field=search "index=(?<queried_index>[\w_-]+)" | stats count as sample_count, dc(user) as users by queried_index | eval estimated_count=sample_count*20 | sort -estimated_count' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/indexes_queried.json" \
    "Indexes actually queried"

  # Data volume by index (for capacity planning)
  run_usage_search \
    '| dbinspect index=* | stats sum(sizeOnDiskMB) as size_mb, sum(eventCount) as events by index | sort - size_mb' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/index_sizes.json" \
    "Index sizes and event counts"

  progress_update "$task_num"
  task_complete "Data source usage patterns"

  # ==========================================================================
  # 3. DAILY VOLUME ANALYSIS (Infrastructure - capacity planning)
  # ==========================================================================
  ((task_num++))
  info "Collecting daily volume statistics (last 30 days)..."

  # Daily volume by index (GB per day)
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by idx | eval gb=round(bytes/1024/1024/1024,2) | fields _time, idx, gb" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/daily_volume_by_index.json" \
    "Daily volume by index (GB)"

  # Daily volume by sourcetype
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by st | eval gb=round(bytes/1024/1024/1024,2) | fields _time, st, gb" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/daily_volume_by_sourcetype.json" \
    "Daily volume by sourcetype (GB)"

  # Total daily volume (for licensing)
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes | eval gb=round(bytes/1024/1024/1024,2) | stats avg(gb) as avg_daily_gb, max(gb) as peak_daily_gb, sum(gb) as total_30d_gb" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/daily_volume_summary.json" \
    "Daily volume summary"

  # Daily event count by index
  run_usage_search \
    "search index=_internal source=*metrics.log group=per_index_thruput earliest=-30d@d | timechart span=1d sum(ev) as events by series | rename series as index" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/daily_events_by_index.json" \
    "Daily event counts by index"

  # Hourly pattern analysis (to identify peak hours)
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-7d | eval hour=strftime(_time, \"%H\") | stats sum(b) as bytes by hour | eval gb=round(bytes/1024/1024/1024,2) | sort hour" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/hourly_volume_pattern.json" \
    "Hourly volume pattern (last 7 days)"

  # Top 20 indexes by daily average volume
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by idx | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/top_indexes_by_volume.json" \
    "Top 20 indexes by daily average volume"

  # Top 20 sourcetypes by daily average volume
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by st | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/top_sourcetypes_by_volume.json" \
    "Top 20 sourcetypes by daily average volume"

  # Volume by host (top 50)
  run_usage_search \
    "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by h | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 50" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/top_hosts_by_volume.json" \
    "Top 50 hosts by daily average volume"

  progress_update "$task_num"
  task_complete "Daily volume statistics"

  # ==========================================================================
  # 5c. INGESTION INFRASTRUCTURE (For understanding data collection methods)
  # ==========================================================================
  ((task_num++))
  info "Collecting ingestion infrastructure information..."

  # Create subdirectory for ingestion infrastructure
  mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure"

  # Connection type breakdown (UF cooked vs HF raw vs other)
  run_usage_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as unique_hosts, sum(kb) as total_kb by connectionType | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/by_connection_type.json" \
    "Ingestion by connection type (UF/HF/other)"

  # Input method breakdown (splunktcp, http, udp, tcp, monitor, etc.)
  run_usage_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | rex field=series "^(?<input_type>[^:]+):" | stats sum(kb) as total_kb, dc(series) as unique_sources by input_type | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2) | sort - total_kb' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/by_input_method.json" \
    "Ingestion by input method"

  # HEC (HTTP Event Collector) usage
  run_usage_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput series=http:* earliest=-7d | stats sum(kb) as total_kb, dc(series) as token_count | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/hec_usage.json" \
    "HTTP Event Collector usage"

  # Forwarding hosts inventory (unique hosts sending data)
  run_usage_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats sum(kb) as total_kb, latest(_time) as last_seen, values(connectionType) as connection_types by sourceHost | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb | head 500" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/forwarding_hosts.json" \
    "Forwarding hosts inventory (top 500)"

  # Sourcetype categorization (detect OTel, cloud, security, etc.)
  run_usage_search \
    'search index=_internal source=*license_usage.log type=Usage earliest=-30d | stats sum(b) as bytes, dc(h) as unique_hosts by st | eval daily_avg_gb=round((bytes/30)/1024/1024/1024,2) | eval category=case(match(st,"^otel|^otlp|opentelemetry"),"opentelemetry", match(st,"^aws:|^azure:|^gcp:|^cloud"),"cloud", match(st,"^WinEventLog|^windows|^wmi"),"windows", match(st,"^linux|^syslog|^nix"),"linux_unix", match(st,"^cisco:|^pan:|^juniper:|^fortinet:|^f5:|^checkpoint"),"network_security", match(st,"^access_combined|^nginx|^apache|^iis"),"web", match(st,"^docker|^kube|^container"),"containers", 1=1,"other") | stats sum(daily_avg_gb) as daily_avg_gb, sum(unique_hosts) as unique_hosts, values(st) as sourcetypes by category | sort - daily_avg_gb' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/by_sourcetype_category.json" \
    "Ingestion by sourcetype category"

  # Data inputs configuration summary
  run_usage_search \
    '| rest /servicesNS/-/-/data/inputs/all | stats count by eai:acl.app, disabled | eval status=if(disabled="0","enabled","disabled") | stats count by eai:acl.app, status' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/data_inputs_by_app.json" \
    "Data inputs by app"

  # Syslog inputs (UDP/TCP)
  run_usage_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | search series=udp:* OR series=tcp:* | stats sum(kb) as total_kb by series | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/syslog_inputs.json" \
    "Syslog inputs (UDP/TCP)"

  # Scripted inputs
  run_usage_search \
    '| rest /servicesNS/-/-/data/inputs/script | stats count by eai:acl.app, disabled, interval | eval status=if(disabled="0","enabled","disabled")' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/scripted_inputs.json" \
    "Scripted inputs inventory"

  # Summary: Total forwarding infrastructure
  run_usage_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as total_forwarding_hosts, sum(kb) as total_kb | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)" \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ingestion_infrastructure/summary.json" \
    "Ingestion infrastructure summary"

  progress_update "$task_num"
  task_complete "Ingestion infrastructure"

  # ==========================================================================
  # 5d. OWNERSHIP MAPPING (For user-centric migration)
  # ==========================================================================
  ((task_num++))
  info "Collecting ownership information..."

  # Dashboard ownership - maps each dashboard to its owner
  run_usage_search \
    '| rest /servicesNS/-/-/data/ui/views | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing | rename title as dashboard, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/dashboard_ownership.json" \
    "Dashboard ownership mapping"

  # Alert/Saved search ownership - maps each alert to its owner
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, is_scheduled, alert.track | rename title as alert_name, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_ownership.json" \
    "Alert/saved search ownership mapping"

  # Ownership summary by user (how many dashboards and alerts each user owns)
  run_usage_search \
    '| rest /servicesNS/-/-/data/ui/views | stats count as dashboards by eai:acl.owner | rename eai:acl.owner as owner | append [| rest /servicesNS/-/-/saved/searches | stats count as alerts by eai:acl.owner | rename eai:acl.owner as owner] | stats sum(dashboards) as dashboards, sum(alerts) as alerts by owner | sort - dashboards' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/ownership_summary.json" \
    "Ownership summary by user"

  progress_update "$task_num"
  task_complete "Ownership mapping"

  # ==========================================================================
  # 5e. ALERT MIGRATION DATA (Critical for Dynatrace Alert Migration)
  # ==========================================================================
  ((task_num++))
  info "Collecting comprehensive alert migration data..."

  # Create subdirectory for alert migration data
  mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration"

  # FULL ALERT DEFINITIONS - Complete alert configuration with ALL fields
  # This is THE critical file for alert migration - includes schedule, conditions, actions
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search is_scheduled=1 OR alert.track=1 | table title, search, cron_schedule, dispatch.earliest_time, dispatch.latest_time, alert.severity, alert.track, alert.digest_mode, alert.expires, alert_condition, alert_threshold, alert_comparator, alert_type, alert.suppress, alert.suppress.fields, alert.suppress.period, counttype, quantity, relation, actions, disabled, eai:acl.owner, eai:acl.app, eai:acl.sharing, description, next_scheduled_time, triggered_alert_count | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alert_definitions_full.json" \
    "Full alert definitions (schedules, conditions, thresholds)"

  # ALERT ACTION CONFIGURATIONS - Email recipients, webhook URLs, Slack channels, etc.
  # Critical for Action Dispatcher migration architecture
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search actions!="" | table title, actions, action.email, action.email.to, action.email.cc, action.email.bcc, action.email.subject, action.email.message.alert, action.email.sendresults, action.email.inline, action.email.format, action.webhook, action.webhook.param.url, action.slack, action.slack.channel, action.slack.message, action.pagerduty, action.pagerduty.integration_key, action.script, action.script.filename, action.summary_index, action.summary_index._name, action.notable, action.notable.param.severity, action.lookup, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alert_action_configs.json" \
    "Alert action configurations (email, webhook, Slack, PagerDuty)"

  # ALERTS BY ACTION TYPE - Categorize alerts by their action type for migration planning
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search actions!="" | eval action_types=split(actions, ",") | mvexpand action_types | stats count, values(title) as alerts by action_types | sort - count' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_by_action_type.json" \
    "Alerts categorized by action type"

  # ALERTS WITH EMAIL ACTIONS - Detailed email configuration for migration
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search action.email=1 | table title, action.email.to, action.email.cc, action.email.subject, action.email.sendresults, action.email.format, cron_schedule, alert.severity, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_with_email.json" \
    "Alerts with email action configuration"

  # ALERTS WITH WEBHOOK ACTIONS - Webhook URLs for Dynatrace Workflow migration
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search action.webhook=1 | table title, action.webhook.param.url, cron_schedule, alert.severity, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_with_webhook.json" \
    "Alerts with webhook action configuration"

  # ALERTS WITH SLACK ACTIONS - Slack channel configuration
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search action.slack=1 | table title, action.slack.channel, action.slack.message, cron_schedule, alert.severity, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_with_slack.json" \
    "Alerts with Slack action configuration"

  # ALERTS WITH PAGERDUTY ACTIONS - PagerDuty integration configuration
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search action.pagerduty=1 | table title, action.pagerduty.integration_key, cron_schedule, alert.severity, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_with_pagerduty.json" \
    "Alerts with PagerDuty action configuration"

  # ALERT SUPPRESSION SETTINGS - For deduplication migration
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search alert.suppress=1 | table title, alert.suppress, alert.suppress.fields, alert.suppress.period, cron_schedule, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_with_suppression.json" \
    "Alerts with suppression/throttling configuration"

  # ALERT SCHEDULE ANALYSIS - Group alerts by schedule frequency for capacity planning
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search is_scheduled=1 | stats count by cron_schedule | sort - count' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_by_schedule.json" \
    "Alerts grouped by schedule frequency"

  # ALERT SEVERITY DISTRIBUTION - For priority classification
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search alert.track=1 | stats count by alert.severity | sort - alert.severity' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_by_severity.json" \
    "Alerts grouped by severity level"

  # HIGH FREQUENCY ALERTS - Alerts that run every minute (need special handling)
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search cron_schedule="* * * * *" OR cron_schedule="*/1 * * * *" | table title, search, cron_schedule, actions, alert.severity, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_high_frequency.json" \
    "High frequency alerts (1-minute interval)"

  # ALERTS WITH COMPLEX SPL - Alerts using advanced SPL commands
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search alert.track=1 | eval has_join=if(match(search,"\\|\\s*join"),"yes","no"), has_transaction=if(match(search,"\\|\\s*transaction"),"yes","no"), has_eventstats=if(match(search,"\\|\\s*eventstats"),"yes","no"), has_streamstats=if(match(search,"\\|\\s*streamstats"),"yes","no"), has_append=if(match(search,"\\|\\s*append"),"yes","no") | where has_join="yes" OR has_transaction="yes" OR has_eventstats="yes" OR has_streamstats="yes" OR has_append="yes" | table title, has_join, has_transaction, has_eventstats, has_streamstats, has_append, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_complex_spl.json" \
    "Alerts using complex SPL commands"

  # ALERTS DATA SOURCE ANALYSIS - Which indexes/sourcetypes each alert queries
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | search alert.track=1 | rex field=search "index=(?<queried_index>[\\w_-]+)" | rex field=search "sourcetype=(?<queried_sourcetype>[\\w:_-]+)" | table title, queried_index, queried_sourcetype, eai:acl.owner, eai:acl.app | rename title as alert_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/alert_migration/alerts_data_sources.json" \
    "Alert data source mapping (index/sourcetype)"

  progress_update "$task_num"
  task_complete "Alert migration data"

  # ==========================================================================
  # 5f. USER/ROLE MAPPING (For Ownership Transfer)
  # ==========================================================================
  ((task_num++))
  info "Collecting user and role mapping data..."

  # Create subdirectory for RBAC data
  mkdir -p "$EXPORT_DIR/dma_analytics/usage_analytics/rbac"

  # ALL USERS - Complete user list with roles
  run_usage_search \
    '| rest /services/authentication/users | table title, realname, email, roles, defaultApp, type, last_successful_login | rename title as username' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/users_all.json" \
    "All users with roles"

  # USER ROLE SUMMARY - Which roles are assigned to which users
  run_usage_search \
    '| rest /services/authentication/users | eval role_list=split(roles, ";") | mvexpand role_list | stats count, values(title) as users by role_list | sort - count | rename role_list as role' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/users_by_role.json" \
    "Users grouped by role"

  # ALL ROLES - Complete role definitions with capabilities
  run_usage_search \
    '| rest /services/authorization/roles | table title, imported_roles, capabilities, srchIndexesAllowed, srchIndexesDefault | rename title as role_name' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/roles_all.json" \
    "All roles with capabilities"

  # ROLE CAPABILITIES - Which capabilities each role has
  run_usage_search \
    '| rest /services/authorization/roles | eval cap_list=split(capabilities, ";") | mvexpand cap_list | stats values(title) as roles by cap_list | sort cap_list | rename cap_list as capability' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/capabilities_by_role.json" \
    "Capabilities grouped by role"

  # USERS WITH ADMIN CAPABILITIES - Important for ownership transfer
  run_usage_search \
    '| rest /services/authentication/users | search roles="*admin*" | table title, realname, email, roles | rename title as username' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/users_admin.json" \
    "Users with admin roles"

  # EXTERNAL AUTHENTICATION CONFIGURATION (LDAP/SAML if configured)
  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/authentication/providers/LDAP" \
    -d "output_mode=json" \
    > "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/ldap_config.json" 2>/dev/null

  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/authentication/providers/SAML" \
    -d "output_mode=json" \
    > "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/saml_config.json" 2>/dev/null

  # TEAM MAPPING SUGGESTION - Group assets by app to suggest team ownership
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | stats dc(title) as alerts, values(eai:acl.owner) as owners by eai:acl.app | append [| rest /servicesNS/-/-/data/ui/views | stats dc(title) as dashboards, values(eai:acl.owner) as owners by eai:acl.app] | stats sum(alerts) as alerts, sum(dashboards) as dashboards, values(owners) as owners by eai:acl.app | rename eai:acl.app as app' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/rbac/team_mapping_by_app.json" \
    "Team mapping suggestion (by app)"

  progress_update "$task_num"
  task_complete "User/role mapping"

  # ==========================================================================
  # 6. SAVED SEARCH METADATA
  # ==========================================================================
  ((task_num++))
  info "Collecting saved search metadata..."

  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/saved/searches" \
    -d "output_mode=json" -d "count=0" \
    > "$EXPORT_DIR/dma_analytics/usage_analytics/saved_searches_all.json" 2>/dev/null

  # Saved searches by owner
  run_usage_search \
    '| rest /servicesNS/-/-/saved/searches | stats count by eai:acl.owner | sort - count | head 30' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/saved_searches_by_owner.json" \
    "Saved searches by owner"

  progress_update "$task_num"
  task_complete "Saved search metadata"

  # ==========================================================================
  # 7. SCHEDULER EXECUTION STATS
  # ==========================================================================
  ((task_num++))
  info "Collecting scheduler execution statistics..."

  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/search/jobs" \
    -d "output_mode=json" -d "count=1000" \
    > "$EXPORT_DIR/dma_analytics/usage_analytics/recent_searches.json" 2>/dev/null

  curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
    "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/server/introspection/kvstore" \
    -d "output_mode=json" \
    > "$EXPORT_DIR/dma_analytics/usage_analytics/kvstore_stats.json" 2>/dev/null

  # Scheduler load over time
  # OPTIMIZED: Added | fields early to reduce memory usage
  run_usage_search \
    'index=_internal sourcetype=scheduler earliest=-${USAGE_PERIOD} | fields _time, run_time | timechart span=1h count as scheduled_searches, avg(run_time) as avg_runtime' \
    "$EXPORT_DIR/dma_analytics/usage_analytics/scheduler_load.json" \
    "Scheduler load over time"

  progress_update "$task_num"
  task_complete "Scheduler execution stats"

  progress_complete

  # ==========================================================================
  # GENERATE USAGE INTELLIGENCE SUMMARY
  # ==========================================================================

  info "Generating usage intelligence summary..."

  local summary_file="$EXPORT_DIR/dma_analytics/usage_analytics/USAGE_INTELLIGENCE_SUMMARY.md"

  cat > "$summary_file" << 'USAGE_EOF'
# Usage Intelligence Summary

This folder contains detailed usage analytics to help prioritize your Splunk-to-Dynatrace migration.

## Key Files for Migration Prioritization

### HIGH PRIORITY (Migrate First)
| File | Description | Use For |
|------|-------------|---------|
| `dashboard_views_top100.json` | Most viewed dashboards | Prioritize these for migration |
| `alerts_most_fired.json` | Most active alerts | Critical operational alerts |
| `users_most_active.json` | Power users | Get their input on requirements |
| `sourcetypes_searched.json` | Most queried data | Ensure these sources are in Dynatrace |

### LOW PRIORITY (Consider Eliminating)
| File | Description | Use For |
|------|-------------|---------|
| `dashboards_never_viewed.json` | Unused dashboards | Skip migration or archive |
| `alerts_never_fired.json` | Alerts that never trigger | Review if still needed |
| `users_inactive.json` | Inactive users | Don't migrate their personal content |
| `alerts_failed.json` | Broken alerts | Fix or remove |

### CAPACITY PLANNING
| File | Description | Use For |
|------|-------------|---------|
| `index_sizes.json` | Data volume by index | Estimate Dynatrace Grail storage |
| `indexes_queried.json` | Which indexes are used | Prioritize data ingestion |
| `scheduler_load.json` | Alert/report load | Plan Dynatrace workflow capacity |

### ALERT MIGRATION (NEW in v4.0.0)
| File | Description | Use For |
|------|-------------|---------|
| `alert_migration/alert_definitions_full.json` | Complete alert configs | Full SPL, schedules, thresholds, conditions |
| `alert_migration/alert_action_configs.json` | Action configurations | Email, webhook, Slack, PagerDuty settings |
| `alert_migration/alerts_by_action_type.json` | Alerts grouped by action | Migration planning by action type |
| `alert_migration/alerts_with_email.json` | Email alert details | Email recipients, subjects, formats |
| `alert_migration/alerts_with_webhook.json` | Webhook alert details | Webhook URLs for workflow migration |
| `alert_migration/alerts_with_slack.json` | Slack alert details | Slack channels and messages |
| `alert_migration/alerts_with_pagerduty.json` | PagerDuty alert details | Integration keys |
| `alert_migration/alerts_with_suppression.json` | Suppression settings | Deduplication migration |
| `alert_migration/alerts_by_schedule.json` | Schedule distribution | Capacity planning |
| `alert_migration/alerts_by_severity.json` | Severity distribution | Priority classification |
| `alert_migration/alerts_high_frequency.json` | 1-minute interval alerts | Special handling required |
| `alert_migration/alerts_complex_spl.json` | Alerts with join/transaction | Complex SPL migration challenges |
| `alert_migration/alerts_data_sources.json` | Index/sourcetype per alert | Data dependency mapping |

### USER/ROLE MAPPING (NEW in v4.0.0)
| File | Description | Use For |
|------|-------------|---------|
| `rbac/users_all.json` | All users with roles | User inventory for ownership transfer |
| `rbac/users_by_role.json` | Users grouped by role | Team identification |
| `rbac/roles_all.json` | Role definitions | Capability mapping |
| `rbac/capabilities_by_role.json` | Capabilities by role | Permission analysis |
| `rbac/users_admin.json` | Admin users | Key stakeholders |
| `rbac/ldap_config.json` | LDAP configuration | External auth mapping |
| `rbac/saml_config.json` | SAML configuration | SSO integration details |
| `rbac/team_mapping_by_app.json` | Assets grouped by app | Team ownership suggestions |

## Migration Decision Framework

```
                    ┌─────────────────────────────────────┐
                    │         USAGE FREQUENCY             │
                    │    High              Low            │
        ┌───────────┼─────────────────────────────────────┤
        │   High    │  MIGRATE FIRST    INVESTIGATE      │
 VALUE  │           │  (Critical)       (Why not used?)  │
        ├───────────┼─────────────────────────────────────┤
        │   Low     │  MIGRATE LATER    ELIMINATE        │
        │           │  (Nice to have)   (Dead weight)    │
        └───────────┴─────────────────────────────────────┘
```

## Interpreting the Data

### Dashboard Views (`dashboard_views_top100.json`)
- `view_count`: Total views in the analysis period
- `unique_users`: Number of different users who viewed it
- `last_viewed`: When it was last accessed
- **Migration Priority**: High view_count + multiple unique_users = HIGH priority

### Alert Executions (`alerts_most_fired.json`)
- `fire_count`: Number of times the alert executed
- `avg_runtime`: Average execution time (seconds)
- `last_fired`: Most recent execution
- **Migration Priority**: Frequent firing + triggered actions = HIGH priority

### User Activity (`users_most_active.json`)
- `search_count`: Total searches run by user
- `unique_searches`: Variety of different searches
- `last_active`: Most recent activity
- **Stakeholder Priority**: High activity users should be consulted

## Recommended Migration Order

1. **Phase 1 - Critical Operations**
   - Top 20 most-viewed dashboards
   - Top 20 most-fired alerts with actions
   - Data sources used by these dashboards/alerts

2. **Phase 2 - Active Users**
   - Dashboards used by top 20 most active users
   - Saved searches from power users
   - Frequently searched indexes

3. **Phase 3 - Long Tail**
   - Remaining used dashboards
   - Remaining active alerts
   - Archive or document unused items

4. **Phase 4 - Cleanup**
   - Do NOT migrate items from "never viewed/fired" lists
   - Document decisions for audit trail
USAGE_EOF

  success "Usage intelligence collected (see _usage_analytics/USAGE_INTELLIGENCE_SUMMARY.md)"
}

collect_index_stats() {
  if [ "$COLLECT_INDEXES" = false ]; then
    return 0
  fi

  # Define collection tasks
  local tasks=(
    "indexes_conf:Index configuration files"
    "index_details:Index details via REST API"
    "data_inputs:Data input configurations"
    "system_configs:System-level configs"
  )

  progress_init "Collecting Index & Data Statistics" "${#tasks[@]}"

  local task_num=0

  # 1. System indexes.conf
  ((task_num++))
  if [ -f "$SPLUNK_HOME/etc/system/local/indexes.conf" ]; then
    cp "$SPLUNK_HOME/etc/system/local/indexes.conf" "$EXPORT_DIR/dma_analytics/indexes/"
  fi
  progress_update "$task_num"
  task_complete "System indexes.conf"

  # 2. REST API index details (use -G to force GET request)
  ((task_num++))
  if [ -n "$SPLUNK_USER" ]; then
    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/data/indexes" \
      -d "output_mode=json" -d "count=0" \
      > "$EXPORT_DIR/dma_analytics/indexes/indexes_detailed.json" 2>/dev/null

    local index_count=$(grep -o '"title"' "$EXPORT_DIR/dma_analytics/indexes/indexes_detailed.json" 2>/dev/null | wc -l | tr -d ' ')
    STATS_INDEXES=$index_count
  fi
  progress_update "$task_num"
  task_complete "Index details (REST API)"

  # 3. Data inputs (use -G to force GET request)
  ((task_num++))
  if [ -n "$SPLUNK_USER" ]; then
    curl -k -s -G -u "${SPLUNK_USER}:${SPLUNK_PASSWORD}" \
      "https://${SPLUNK_HOST}:${SPLUNK_PORT}/services/data/inputs/all" \
      -d "output_mode=json" -d "count=0" \
      > "$EXPORT_DIR/dma_analytics/indexes/data_inputs.json" 2>/dev/null
  fi
  progress_update "$task_num"
  task_complete "Data inputs"

  # 4. System-level inputs/outputs
  ((task_num++))
  for conf_file in "inputs.conf" "outputs.conf" "server.conf"; do
    if [ -f "$SPLUNK_HOME/etc/system/local/$conf_file" ]; then
      cp "$SPLUNK_HOME/etc/system/local/$conf_file" "$EXPORT_DIR/_system/local/"
    fi
  done
  progress_update "$task_num"
  task_complete "System configs"

  progress_complete

  # Show index histogram if we have data
  if [ -f "$EXPORT_DIR/dma_analytics/indexes/indexes_detailed.json" ] && [ -n "$SPLUNK_USER" ]; then
    # Try to extract index sizes for histogram using Python (no jq dependency)
    local index_sizes=()
    while IFS= read -r line; do
      # Parse each JSON line using Python inline
      local parsed=$($PYTHON_CMD -c "
import json
import sys
try:
    item = json.loads('''$line''')
    name = item.get('name', '')
    size = item.get('content', {}).get('currentDBSizeMB', 0)
    if name and size and size != 'null':
        print(f'{name}:{int(float(size))}')
except:
    pass
" 2>/dev/null)
      if [ -n "$parsed" ]; then
        index_sizes+=("$parsed")
      fi
    done < <(json_iterate "$EXPORT_DIR/dma_analytics/indexes/indexes_detailed.json" ".entry" 2>/dev/null | head -20)

    if [ ${#index_sizes[@]} -gt 0 ]; then
      show_histogram "Index Sizes (MB) - Top 20" "${index_sizes[@]}"
    fi
  fi

  success "Index statistics collected (${STATS_INDEXES} indexes)"
}

collect_audit_sample() {
  if [ "$COLLECT_AUDIT" = false ]; then
    return 0
  fi

  progress "Collecting audit log sample..."

  local audit_log="$SPLUNK_HOME/var/log/splunk/audit.log"

  if [ -f "$audit_log" ] && [ -r "$audit_log" ]; then
    mkdir -p "$EXPORT_DIR/_audit_sample"
    tail -10000 "$audit_log" > "$EXPORT_DIR/_audit_sample/audit_sample.log" 2>/dev/null
    success "Collected 10,000 most recent audit entries"
  else
    warning "Could not read audit log (permission denied or not found)"
  fi
}

# =============================================================================
# SUMMARY GENERATION
# =============================================================================

generate_summary() {
  progress "Generating environment summary..."

  local summary_file="$EXPORT_DIR/dma-env-summary.md"

  cat > "$summary_file" << EOF
# DMA Environment Summary

**Export Date**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Hostname**: $(get_hostname)
**Export Tool Version**: $SCRIPT_VERSION

---

## Environment Overview

| Attribute | Value |
|-----------|-------|
| **Product** | Splunk ${SPLUNK_FLAVOR^} |
| **Role** | ${SPLUNK_ROLE//_/ } |
| **Architecture** | ${SPLUNK_ARCHITECTURE^} |
| **SPLUNK_HOME** | $SPLUNK_HOME |

---

## Export Statistics

| Category | Count |
|----------|-------|
| **Applications Exported** | $STATS_APPS |
| **Dashboards** | $STATS_DASHBOARDS |
| **Alerts** | $STATS_ALERTS |
| **Users** | $STATS_USERS |
| **Indexes** | $STATS_INDEXES |
| **Errors** | $STATS_ERRORS |

---

## Applications Included

EOF

  for app in "${SELECTED_APPS[@]}"; do
    echo "- $app" >> "$summary_file"
  done

  cat >> "$summary_file" << EOF

---

## Data Categories Collected

| Category | Collected |
|----------|-----------|
| Configuration Files | $([ "$COLLECT_CONFIGS" = true ] && echo "Yes" || echo "No") |
| Dashboards | $([ "$COLLECT_DASHBOARDS" = true ] && echo "Yes" || echo "No") |
| Alerts & Saved Searches | $([ "$COLLECT_ALERTS" = true ] && echo "Yes" || echo "No") |
| Users & RBAC | $([ "$COLLECT_RBAC" = true ] && echo "Yes" || echo "No") |
| Usage Analytics | $([ "$COLLECT_USAGE" = true ] && echo "Yes (${USAGE_PERIOD})" || echo "No") |
| Index Statistics | $([ "$COLLECT_INDEXES" = true ] && echo "Yes" || echo "No") |
| Lookup Tables | $([ "$COLLECT_LOOKUPS" = true ] && echo "Yes" || echo "No") |
| Audit Log Sample | $([ "$COLLECT_AUDIT" = true ] && echo "Yes" || echo "No") |

---

## Next Steps

1. Download the export file from this server
2. Open Dynatrace Migration Assistant in Dynatrace
3. Navigate to: Migration Workspace → Project Initialization
4. Upload the .tar.gz file
5. DMA will analyze your environment and show:
   - Migration readiness assessment
   - Dashboard conversion preview
   - Alert conversion checklist
   - Data pipeline requirements

---

*Generated by DMA Splunk Export Tool v$SCRIPT_VERSION*
EOF

  success "Summary generated: dma-env-summary.md"
}

# =============================================================================
# MANIFEST GENERATION (Guaranteed Schema for DMA)
# =============================================================================

generate_manifest() {
  progress "Generating manifest.json (standardized schema)..."

  local manifest_file="$EXPORT_DIR/dma_analytics/manifest.json"

  # Get Splunk version
  local splunk_version="unknown"
  local splunk_build="unknown"
  if [ -f "$SPLUNK_HOME/etc/splunk.version" ]; then
    splunk_version=$(grep "^VERSION" "$SPLUNK_HOME/etc/splunk.version" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    splunk_build=$(grep "^BUILD" "$SPLUNK_HOME/etc/splunk.version" 2>/dev/null | cut -d= -f2 | tr -d ' ')
  fi

  # Get IP addresses using Python helper (no jq dependency)
  local ip_addresses=$(get_host_ips_json 2>/dev/null || echo "[]")
  [ -z "$ip_addresses" ] && ip_addresses="[]"

  # Calculate export duration
  local export_duration=$(($(date +%s) - EXPORT_START_TIME))

  # Count saved searches (separate from alerts)
  local saved_search_count=0
  for app in "${SELECTED_APPS[@]}"; do
    for conf_dir in "default" "local"; do
      if [ -f "$EXPORT_DIR/$app/$conf_dir/savedsearches.conf" ]; then
        local count=$(grep -c '^\[' "$EXPORT_DIR/$app/$conf_dir/savedsearches.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
        [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]] && count=0
        saved_search_count=$((saved_search_count + count))
      fi
    done
  done

  # Count macros
  local macro_count=0
  for app in "${SELECTED_APPS[@]}"; do
    for conf_dir in "default" "local"; do
      if [ -f "$EXPORT_DIR/$app/$conf_dir/macros.conf" ]; then
        local count=$(grep -c '^\[' "$EXPORT_DIR/$app/$conf_dir/macros.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
        [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]] && count=0
        macro_count=$((macro_count + count))
      fi
    done
  done

  # Count props stanzas
  local props_count=0
  for app in "${SELECTED_APPS[@]}"; do
    for conf_dir in "default" "local"; do
      if [ -f "$EXPORT_DIR/$app/$conf_dir/props.conf" ]; then
        local count=$(grep -c '^\[' "$EXPORT_DIR/$app/$conf_dir/props.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
        [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]] && count=0
        props_count=$((props_count + count))
      fi
    done
  done

  # Count transforms stanzas
  local transforms_count=0
  for app in "${SELECTED_APPS[@]}"; do
    for conf_dir in "default" "local"; do
      if [ -f "$EXPORT_DIR/$app/$conf_dir/transforms.conf" ]; then
        local count=$(grep -c '^\[' "$EXPORT_DIR/$app/$conf_dir/transforms.conf" 2>/dev/null | head -1 | tr -d '[:space:]')
        [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]] && count=0
        transforms_count=$((transforms_count + count))
      fi
    done
  done

  # Count dashboards from app-scoped folders (v2 structure)
  # NOTE: Only count .json files that are NOT _definition.json (those are extracted definitions, not separate dashboards)
  local studio_count=0
  local classic_count=0
  for dir in "$EXPORT_DIR"/*/dashboards/studio; do
    if [ -d "$dir" ]; then
      local count=$(ls -1 "$dir"/*.json 2>/dev/null | grep -v '_definition\.json$' | wc -l | tr -d ' ')
      studio_count=$((studio_count + count))
    fi
  done
  for dir in "$EXPORT_DIR"/*/dashboards/classic; do
    if [ -d "$dir" ]; then
      local count=$(ls -1 "$dir"/*.json 2>/dev/null | wc -l | tr -d ' ')
      classic_count=$((classic_count + count))
    fi
  done

  # Use REST API count if available, otherwise fall back to XML file count
  local dashboard_total=$STATS_DASHBOARDS
  if [ "$dashboard_total" -eq 0 ] && [ "$STATS_DASHBOARDS_XML" -gt 0 ]; then
    dashboard_total=$STATS_DASHBOARDS_XML
    log "Using XML file count for dashboards (REST API unavailable): $dashboard_total"
  fi

  # Count classic dashboards (total minus studio)
  local classic_count=$((dashboard_total - studio_count))
  if [ "$classic_count" -lt 0 ]; then classic_count=0; fi

  # Build apps array using Python helper (replaces jq)
  local apps_json=$(build_apps_json "$EXPORT_DIR" "${SELECTED_APPS[@]}")
  # Ensure we have valid JSON (fallback to empty array if empty or invalid)
  if [ -z "$apps_json" ] || [ "$apps_json" = "null" ]; then
    apps_json="[]"
  fi

  # Count total files (use ls -lR instead of find for container compatibility)
  local total_files=$(ls -lR "$EXPORT_DIR" 2>/dev/null | grep -c "^-" | tr -d ' ')
  local total_size=$(du -sb "$EXPORT_DIR" 2>/dev/null | cut -f1)

  # Build usage intelligence summary using Python helper (replaces jq)
  local usage_intel_json="{}"
  if [ -d "$EXPORT_DIR/dma_analytics/usage_analytics" ]; then
    progress "Extracting usage intelligence for manifest..."
    usage_intel_json=$(build_usage_intel_json "$EXPORT_DIR")
    # Ensure we have valid JSON (fallback to empty object if empty or invalid)
    if [ -z "$usage_intel_json" ] || [ "$usage_intel_json" = "null" ]; then
      usage_intel_json="{}"
    fi
  fi

  # Generate manifest
  cat > "$manifest_file" << MANIFEST_EOF
{
  "schema_version": "4.0",
  "archive_structure_version": "v2",
  "export_tool": "dma-splunk-export",
  "export_tool_version": "$SCRIPT_VERSION",
  "export_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "export_duration_seconds": $export_duration,

  "archive_structure": {
    "version": "v2",
    "description": "App-centric dashboard organization prevents name collisions",
    "dashboard_location": "{AppName}/dashboards/classic/ and {AppName}/dashboards/studio/"
  },

  "source": {
    "hostname": "$(get_hostname short)",
    "fqdn": "$(get_hostname fqdn)",
    "platform": "$(uname -s)",
    "platform_version": "$(uname -r)",
    "architecture": "$(uname -m)"
  },

  "splunk": {
    "home": "$SPLUNK_HOME",
    "version": "$splunk_version",
    "build": "$splunk_build",
    "flavor": "$SPLUNK_FLAVOR",
    "role": "$SPLUNK_ROLE",
    "architecture": "$SPLUNK_ARCHITECTURE",
    "is_shc_member": $IS_SHC_MEMBER,
    "is_shc_captain": $IS_SHC_CAPTAIN,
    "is_idx_cluster": $IS_IDX_CLUSTER,
    "is_cloud": $IS_CLOUD
  },

  "collection": {
    "configs": $COLLECT_CONFIGS,
    "dashboards": $COLLECT_DASHBOARDS,
    "alerts": $COLLECT_ALERTS,
    "rbac": $COLLECT_RBAC,
    "usage_analytics": $COLLECT_USAGE,
    "usage_period": "$USAGE_PERIOD",
    "indexes": $COLLECT_INDEXES,
    "lookups": $COLLECT_LOOKUPS,
    "audit_sample": $COLLECT_AUDIT,
    "data_anonymized": $ANONYMIZE_DATA
  },

  "statistics": {
    "apps_exported": $STATS_APPS,
    "dashboards_classic": $classic_count,
    "dashboards_studio": $studio_count,
    "dashboards_total": $dashboard_total,
    "alerts": $STATS_ALERTS,
    "saved_searches": $saved_search_count,
    "users": $STATS_USERS,
    "roles": 0,
    "indexes": $STATS_INDEXES,
    "macros": $macro_count,
    "props_stanzas": $props_count,
    "transforms_stanzas": $transforms_count,
    "errors": $STATS_ERRORS,
    "total_files": $total_files,
    "total_size_bytes": ${total_size:-0}
  },

  "apps": $apps_json,

  "usage_intelligence": $usage_intel_json
}
MANIFEST_EOF

  # Validate and format JSON using Python
  local validation_result=$(json_format "$manifest_file")
  if [ "$validation_result" = "valid" ]; then
    success "manifest.json generated and validated"
  else
    warning "manifest.json generated but may have JSON errors: $validation_result"
  fi

  # Update global STATS_DASHBOARDS with corrected total (for subsequent summaries)
  STATS_DASHBOARDS=$dashboard_total
}

# =============================================================================
# DATA ANONYMIZATION FUNCTIONS
# =============================================================================

# Generate a consistent hash-based ID for anonymization
# This ensures the same input always produces the same output
generate_anon_id() {
  local input="$1"
  local prefix="$2"
  local length="${3:-8}"

  # Use SHA256 and take first N characters (lowercase hex)
  local hash=""
  if command_exists sha256sum; then
    hash=$(echo -n "$input" | sha256sum | cut -c1-"$length")
  elif command_exists shasum; then
    hash=$(echo -n "$input" | shasum -a 256 | cut -c1-"$length")
  elif command_exists md5sum; then
    hash=$(echo -n "$input" | md5sum | cut -c1-"$length")
  elif command_exists md5; then
    hash=$(echo -n "$input" | md5 | cut -c1-"$length")
  else
    # Fallback: use base64 encoding of input
    hash=$(echo -n "$input" | base64 | tr -d '=' | tr '+/' 'ab' | cut -c1-"$length" | tr '[:upper:]' '[:lower:]')
  fi

  echo "${prefix}${hash}"
}

# Get or create anonymized email for a given real email
get_anon_email() {
  local real_email="$1"

  # Skip if empty or already anonymized
  if [ -z "$real_email" ] || [[ "$real_email" == *"@anon.dma.local"* ]]; then
    echo "$real_email"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${EMAIL_MAP[$real_email]:-}" ]; then
    echo "${EMAIL_MAP[$real_email]}"
    return
  fi

  # Generate new anonymized email
  local anon_id=$(generate_anon_id "$real_email" "user" 6)
  local anon_email="${anon_id}@anon.dma.local"

  # Store mapping
  EMAIL_MAP["$real_email"]="$anon_email"
  ((ANON_EMAIL_COUNTER++))

  echo "$anon_email"
}

# Get or create anonymized hostname for a given real hostname
get_anon_hostname() {
  local real_host="$1"

  # Skip if empty or already anonymized
  if [ -z "$real_host" ] || [[ "$real_host" == "host-"* && "$real_host" == *".anon.local" ]]; then
    echo "$real_host"
    return
  fi

  # Skip common non-sensitive hostnames
  if [[ "$real_host" == "localhost" || "$real_host" == "127.0.0.1" ]]; then
    echo "$real_host"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${HOST_MAP[$real_host]:-}" ]; then
    echo "${HOST_MAP[$real_host]}"
    return
  fi

  # Generate new anonymized hostname
  local anon_id=$(generate_anon_id "$real_host" "" 8)
  local anon_host="host-${anon_id}.anon.local"

  # Store mapping
  HOST_MAP["$real_host"]="$anon_host"
  ((ANON_HOST_COUNTER++))

  echo "$anon_host"
}

# Get or create anonymized webhook URL for a given real webhook URL
get_anon_webhook_url() {
  local real_url="$1"

  # Skip if empty or already anonymized
  if [ -z "$real_url" ] || [[ "$real_url" == *"webhook.anon.dma.local"* ]]; then
    echo "$real_url"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${WEBHOOK_MAP[$real_url]:-}" ]; then
    echo "${WEBHOOK_MAP[$real_url]}"
    return
  fi

  # Generate new anonymized webhook URL
  local anon_id=$(generate_anon_id "$real_url" "" 12)
  local anon_url="https://webhook.anon.dma.local/hook-${anon_id}"

  # Store mapping
  WEBHOOK_MAP["$real_url"]="$anon_url"
  ((ANON_WEBHOOK_COUNTER++))

  echo "$anon_url"
}

# Get or create anonymized API key/token for a given real key
get_anon_api_key() {
  local real_key="$1"
  local key_type="${2:-API}"  # Type prefix: API, PAGERDUTY, SLACK, etc.

  # Skip if empty or already anonymized
  if [ -z "$real_key" ] || [[ "$real_key" == "[${key_type}-KEY-"*"]" ]]; then
    echo "$real_key"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${APIKEY_MAP[$real_key]:-}" ]; then
    echo "${APIKEY_MAP[$real_key]}"
    return
  fi

  # Generate new anonymized key (preserve uniqueness for correlation)
  local anon_id=$(generate_anon_id "$real_key" "" 8)
  local anon_key="[${key_type}-KEY-${anon_id}]"

  # Store mapping
  APIKEY_MAP["$real_key"]="$anon_key"
  ((ANON_APIKEY_COUNTER++))

  echo "$anon_key"
}

# Get or create anonymized Slack channel for a given real channel
get_anon_slack_channel() {
  local real_channel="$1"

  # Skip if empty or already anonymized
  if [ -z "$real_channel" ] || [[ "$real_channel" == "#anon-channel-"* ]]; then
    echo "$real_channel"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${SLACK_CHANNEL_MAP[$real_channel]:-}" ]; then
    echo "${SLACK_CHANNEL_MAP[$real_channel]}"
    return
  fi

  # Generate new anonymized channel name
  local anon_id=$(generate_anon_id "$real_channel" "" 6)
  local anon_channel="#anon-channel-${anon_id}"

  # Store mapping
  SLACK_CHANNEL_MAP["$real_channel"]="$anon_channel"
  ((ANON_SLACK_COUNTER++))

  echo "$anon_channel"
}

# Get or create anonymized username for a given real username
get_anon_username() {
  local real_user="$1"

  # Skip if empty or already anonymized
  if [ -z "$real_user" ] || [[ "$real_user" == "anon-user-"* ]]; then
    echo "$real_user"
    return
  fi

  # Skip system/generic users
  if [[ "$real_user" == "nobody" || "$real_user" == "admin" || "$real_user" == "system" || \
        "$real_user" == "splunk-system-user" || "$real_user" == "root" ]]; then
    echo "$real_user"
    return
  fi

  # Check if we already have a mapping
  if [ -n "${USERNAME_MAP[$real_user]:-}" ]; then
    echo "${USERNAME_MAP[$real_user]}"
    return
  fi

  # Generate new anonymized username
  local anon_id=$(generate_anon_id "$real_user" "" 6)
  local anon_user="anon-user-${anon_id}"

  # Store mapping
  USERNAME_MAP["$real_user"]="$anon_user"
  ((ANON_USERNAME_COUNTER++))

  echo "$anon_user"
}

# Collect files recursively with specific extensions (container-compatible alternative to find)
# Usage: collect_files_recursive <directory> <extensions_array_name>
# Extensions should be space-separated, e.g., "json conf xml csv txt meta"
collect_files_recursive() {
  local dir="$1"
  local extensions="$2"  # Space-separated list: "json conf xml csv txt meta"

  # Process files in current directory
  for ext in $extensions; do
    for file in "$dir"/*."$ext"; do
      [ -f "$file" ] && echo "$file"
    done
  done

  # Recurse into subdirectories
  for subdir in "$dir"/*/; do
    [ -d "$subdir" ] && collect_files_recursive "$subdir" "$extensions"
  done
}

# Anonymize a single file
# =============================================================================
# PYTHON-BASED ANONYMIZATION (Reliable streaming for large files)
# =============================================================================
# This uses Python for file processing to avoid bash memory issues and
# regex catastrophic backtracking. Works with Splunk's bundled Python.

# Generate the Python anonymization script inline
generate_python_anonymizer() {
  local script_file="$1"
  cat > "$script_file" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
DMA Anonymizer - Streaming file anonymization
Handles large files without memory issues or regex backtracking

v2.0 - Fixed JSON corruption issues:
- Removed overly aggressive public IP pattern that matched version numbers
- Improved JSON escape fixing to handle all invalid escape sequences
- Added JSON validation before saving to prevent corrupt output
- Use surrogateescape encoding to preserve bytes that can't decode as UTF-8
"""
import sys
import re
import os
import json
import hashlib

# Anonymization mappings (consistent across files)
email_map = {}
host_map = {}
webhook_map = {}
apikey_map = {}
slack_map = {}
username_map = {}

def get_hash_id(value, prefix=""):
    """Generate consistent short hash for a value"""
    h = hashlib.md5(value.encode()).hexdigest()[:8]
    return f"{prefix}{h}"

def anonymize_email(email):
    """Anonymize email address consistently"""
    if email in email_map:
        return email_map[email]
    # Skip already anonymized or safe emails
    if '@anon.dma.local' in email or '@example.com' in email or '@localhost' in email:
        return email
    # Use 'anon' prefix instead of 'user' to avoid creating \u sequences
    # (e.g., \user becomes invalid JSON unicode escape)
    anon = f"anon{get_hash_id(email)}@anon.dma.local"
    email_map[email] = anon
    return anon

def anonymize_hostname(hostname):
    """Anonymize hostname consistently"""
    if hostname in host_map:
        return host_map[hostname]
    # Skip safe values
    if hostname in ('localhost', '127.0.0.1', 'null', 'none', '*', ''):
        return hostname
    if hostname.startswith('host-') and '.anon.local' in hostname:
        return hostname
    anon = f"host-{get_hash_id(hostname)}.anon.local"
    host_map[hostname] = anon
    return anon

def anonymize_webhook(url):
    """Anonymize webhook URL consistently"""
    if url in webhook_map:
        return webhook_map[url]
    if 'webhook.anon.dma.local' in url:
        return url
    anon = f"https://webhook.anon.dma.local/hook-{get_hash_id(url)}"
    webhook_map[url] = anon
    return anon

def anonymize_apikey(key, key_type="API"):
    """Anonymize API key consistently"""
    if key in apikey_map:
        return apikey_map[key]
    anon = f"[{key_type}-KEY-{get_hash_id(key)}]"
    apikey_map[key] = anon
    return anon

def anonymize_slack_channel(channel):
    """Anonymize Slack channel consistently"""
    if channel in slack_map:
        return slack_map[channel]
    if channel.startswith('#anon-channel-'):
        return channel
    anon = f"#anon-channel-{get_hash_id(channel)}"
    slack_map[channel] = anon
    return anon

def anonymize_username(username):
    """Anonymize username consistently"""
    if username in username_map:
        return username_map[username]
    # Skip system users
    if username in ('nobody', 'admin', 'system', 'splunk-system-user', 'root', 'null', 'none', ''):
        return username
    if username.startswith('anon-user-'):
        return username
    anon = f"anon-user-{get_hash_id(username)}"
    username_map[username] = anon
    return anon

def process_line(line):
    """Process a single line, applying all anonymization rules"""
    result = line

    # 1. Anonymize email addresses (simple pattern, non-greedy)
    email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}'
    for match in re.findall(email_pattern, result):
        anon = anonymize_email(match)
        if anon != match:
            result = result.replace(match, anon)

    # 2. Redact private IP addresses ONLY (RFC 1918)
    # These patterns are safe - they only match private ranges
    # 10.x.x.x
    result = re.sub(r'\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    # 172.16-31.x.x
    result = re.sub(r'\b172\.(1[6-9]|2[0-9]|3[01])\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    # 192.168.x.x
    result = re.sub(r'\b192\.168\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    # NOTE: Removed the overly broad public IP pattern that was matching version numbers
    # and other legitimate dot-separated values like "1.2.3.4" in SPL queries

    # 3. Anonymize hostnames in JSON format: "host": "value"
    host_json_pattern = r'"(host|hostname|splunk_server|server|serverName)"\s*:\s*"([^"]+)"'
    for match in re.finditer(host_json_pattern, result, re.IGNORECASE):
        key, hostname = match.groups()
        anon = anonymize_hostname(hostname)
        if anon != hostname:
            result = result.replace(f'"{key}": "{hostname}"', f'"{key}": "{anon}"')
            result = result.replace(f'"{key}":"{hostname}"', f'"{key}":"{anon}"')

    # 4. Anonymize hostnames in conf format: host = value
    host_conf_pattern = r'\b(host|hostname|splunk_server|server)\s*=\s*([^\s,\]"]+)'
    for match in re.finditer(host_conf_pattern, result, re.IGNORECASE):
        key, hostname = match.groups()
        anon = anonymize_hostname(hostname)
        if anon != hostname:
            result = result.replace(f'{key}={hostname}', f'{key}={anon}')
            result = result.replace(f'{key} = {hostname}', f'{key} = {anon}')

    # 5. Anonymize webhook URLs
    webhook_full_pattern = r'https?://[^\s"\'<>]+(?:slack\.com|pagerduty\.com|opsgenie\.com|webhook\.office\.com|hooks\.zapier\.com)[^\s"\'<>]*'
    for match in re.findall(webhook_full_pattern, result):
        anon = anonymize_webhook(match)
        if anon != match:
            result = result.replace(match, anon)

    # 6. Anonymize API keys in JSON: "api_key": "value"
    apikey_json_pattern = r'"(api_key|apikey|api_token|apiToken|token|secret|auth_token|access_token|integration_key|routing_key|pagerduty_key)"\s*:\s*"([^"]{16,})"'
    for match in re.finditer(apikey_json_pattern, result, re.IGNORECASE):
        key, value = match.groups()
        key_type = "PAGERDUTY" if "pagerduty" in key.lower() or "integration" in key.lower() or "routing" in key.lower() else "API"
        anon = anonymize_apikey(value, key_type)
        if anon != value:
            result = result.replace(f'"{key}": "{value}"', f'"{key}": "{anon}"')
            result = result.replace(f'"{key}":"{value}"', f'"{key}":"{anon}"')

    # 7. Anonymize Slack channels
    slack_pattern = r'"(action\.slack\.channel|slack_channel|channel)"\s*:\s*"(#[^"]+)"'
    for match in re.finditer(slack_pattern, result, re.IGNORECASE):
        key, channel = match.groups()
        anon = anonymize_slack_channel(channel)
        if anon != channel:
            result = result.replace(f'"{key}": "{channel}"', f'"{key}": "{anon}"')
            result = result.replace(f'"{key}":"{channel}"', f'"{key}":"{anon}"')

    # 8. Anonymize usernames in JSON: "owner": "value"
    username_json_pattern = r'"(owner|eai:acl\.owner|author|user|username|realname|created_by|updated_by)"\s*:\s*"([^"]+)"'
    for match in re.finditer(username_json_pattern, result, re.IGNORECASE):
        key, username = match.groups()
        anon = anonymize_username(username)
        if anon != username:
            result = result.replace(f'"{key}": "{username}"', f'"{key}": "{anon}"')
            result = result.replace(f'"{key}":"{username}"', f'"{key}":"{anon}"')

    return result

def fix_json_escapes(content):
    """Fix invalid JSON escape sequences created during anonymization.

    When anonymized values replace original data that had preceding backslashes,
    we can get invalid escape sequences. For example:
    - \\user... becomes \\u followed by non-hex (invalid unicode escape)
    - \\anon... becomes \\a followed by non-standard escape

    This function fixes these by properly escaping the backslash.
    """
    # Fix all invalid escape sequences in JSON strings
    # Valid JSON escapes are: \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
    # Anything else after a backslash needs the backslash escaped

    # Fix \\u followed by non-hex or incomplete hex (invalid unicode escape)
    result = re.sub(r'\\u([^0-9a-fA-F])', r'\\\\u\\1', content)
    result = re.sub(r'\\u([0-9a-fA-F]{1,3})([^0-9a-fA-F])', r'\\\\u\\1\\2', result)

    # Fix \\a (invalid escape - \a is not valid JSON)
    result = re.sub(r'\\a([^n])', r'\\\\a\\1', result)  # but preserve \an if followed by more

    # Fix \\h (invalid escape - appears from \host patterns)
    result = re.sub(r'\\h', r'\\\\h', result)

    # Fix other common invalid escapes that might appear
    result = re.sub(r'\\([^"\\/bfnrtu])', r'\\\\\\1', result)

    return result

def validate_json(content):
    """Check if content is valid JSON. Returns True if valid, False otherwise."""
    try:
        json.loads(content)
        return True
    except json.JSONDecodeError:
        return False

def process_file(filepath):
    """Process a file, applying anonymization rules while preserving file integrity"""
    try:
        # Read with surrogateescape to preserve bytes that can't decode as UTF-8
        # This prevents data corruption from invalid byte sequences
        with open(filepath, 'r', encoding='utf-8', errors='surrogateescape') as f:
            content = f.read()

        is_json = filepath.lower().endswith('.json')

        # For JSON files, validate it's parseable before modifying
        original_valid = True
        if is_json:
            original_valid = validate_json(content)

        # Process line by line
        lines = content.split('\n')
        modified = False
        new_lines = []
        for line in lines:
            new_line = process_line(line)
            new_lines.append(new_line)
            if new_line != line:
                modified = True

        if not modified:
            return False

        new_content = '\n'.join(new_lines)

        # For JSON files, apply escape fixes and validate
        if is_json:
            new_content = fix_json_escapes(new_content)

            # Only save if the result is valid JSON (or original was also invalid)
            if original_valid and not validate_json(new_content):
                print(f"WARNING: Anonymization would corrupt JSON in {filepath}, skipping", file=sys.stderr)
                return False

        # Write back with same encoding handling
        with open(filepath, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(new_content)

        return True
    except Exception as e:
        print(f"Error processing {filepath}: {e}", file=sys.stderr)
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: anonymizer.py <file1> [file2] ...", file=sys.stderr)
        sys.exit(1)

    for filepath in sys.argv[1:]:
        if os.path.isfile(filepath):
            process_file(filepath)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT
  chmod +x "$script_file"
}

# Anonymize a single file using Python (streaming, no memory issues)
anonymize_file() {
  local file="$1"
  local python_script="$EXPORT_DIR/.anonymizer.py"

  # Skip empty files and temp files
  if [ ! -s "$file" ] || [[ "$file" == *.tmp ]] || [[ "$file" == *.py ]]; then
    return
  fi

  # Check if file is text (skip binary)
  if ! file "$file" 2>/dev/null | grep -qE 'text|JSON|XML|ASCII'; then
    return
  fi

  # Generate Python script if not exists
  if [ ! -f "$python_script" ]; then
    generate_python_anonymizer "$python_script"
  fi

  # Find Python (prefer Splunk's bundled Python, fall back to system)
  # Check multiple locations since SPLUNK_HOME may not be set
  local python_cmd=""
  local splunk_python_paths=(
    "$SPLUNK_HOME/bin/python3"
    "$SPLUNK_HOME/bin/python"
    "/opt/splunk/bin/python3"
    "/opt/splunk/bin/python"
    "/opt/splunkforwarder/bin/python3"
    "/opt/splunkforwarder/bin/python"
    "/Applications/Splunk/bin/python3"
    "/Applications/Splunk/bin/python"
  )

  # Try Splunk's bundled Python first
  for py_path in "${splunk_python_paths[@]}"; do
    if [ -n "$py_path" ] && [ -x "$py_path" ]; then
      python_cmd="$py_path"
      break
    fi
  done

  # Fall back to system Python
  if [ -z "$python_cmd" ]; then
    if command -v python3 &>/dev/null; then
      python_cmd="python3"
    elif command -v python &>/dev/null; then
      python_cmd="python"
    else
      # Fallback to simple sed-based anonymization
      anonymize_file_sed_fallback "$file"
      return
    fi
  fi

  # Run Python anonymizer with 60-second timeout per file
  if command -v timeout &>/dev/null; then
    timeout 60 "$python_cmd" "$python_script" "$file" 2>/dev/null || true
  elif command -v gtimeout &>/dev/null; then
    gtimeout 60 "$python_cmd" "$python_script" "$file" 2>/dev/null || true
  else
    "$python_cmd" "$python_script" "$file" 2>/dev/null || true
  fi
}

# Fallback: Simple sed-based anonymization (no complex patterns that can backtrack)
anonymize_file_sed_fallback() {
  local file="$1"
  local temp_file="${file}.anon.tmp"

  # Use simple, non-backtracking patterns with in-place sed
  # These are safe patterns that won't cause catastrophic backtracking

  # Check for GNU sed vs BSD sed
  local sed_inplace=""
  if sed --version 2>/dev/null | grep -q GNU; then
    sed_inplace="-i"
  else
    sed_inplace="-i ''"
  fi

  # Apply simple patterns directly to file (in-place, streaming)
  # 1. Redact private IPs (simple patterns)
  sed $sed_inplace 's/\b10\.[0-9]*\.[0-9]*\.[0-9]*\b/[IP-REDACTED]/g' "$file" 2>/dev/null || true
  sed $sed_inplace 's/\b192\.168\.[0-9]*\.[0-9]*\b/[IP-REDACTED]/g' "$file" 2>/dev/null || true
  sed $sed_inplace 's/\b172\.1[6-9]\.[0-9]*\.[0-9]*\b/[IP-REDACTED]/g' "$file" 2>/dev/null || true
  sed $sed_inplace 's/\b172\.2[0-9]\.[0-9]*\.[0-9]*\b/[IP-REDACTED]/g' "$file" 2>/dev/null || true
  sed $sed_inplace 's/\b172\.3[0-1]\.[0-9]*\.[0-9]*\b/[IP-REDACTED]/g' "$file" 2>/dev/null || true

  # Clean up backup files on macOS
  rm -f "${file}''" 2>/dev/null || true
}

# Main anonymization function - processes all files in export directory
anonymize_export() {
  if [ "$ANONYMIZE_DATA" != true ]; then
    return 0
  fi

  print_info_box "STEP 7.5: ANONYMIZING SENSITIVE DATA" \
    "" \
    "${WHITE}Replacing sensitive data with anonymized values:${NC}" \
    "" \
    "  ${CYAN}→${NC} Email addresses → user######@anon.dma.local" \
    "  ${CYAN}→${NC} Hostnames → host-########.anon.local" \
    "  ${CYAN}→${NC} IP addresses → [IP-REDACTED]" \
    "  ${CYAN}→${NC} Webhook URLs → https://webhook.anon.dma.local/hook-###" \
    "  ${CYAN}→${NC} API keys/tokens → [API-KEY-########]" \
    "  ${CYAN}→${NC} PagerDuty keys → [PAGERDUTY-KEY-########]" \
    "  ${CYAN}→${NC} Slack channels → #anon-channel-######" \
    "  ${CYAN}→${NC} Usernames → anon-user-######" \
    "" \
    "${WHITE}NOTE:${NC} The same original value always maps to the same" \
    "anonymized value, preserving data relationships."

  echo ""
  progress "Scanning export directory for files to anonymize..."

  # Collect all text files to process (use helper function instead of find for container compatibility)
  local files_to_process=()
  while IFS= read -r file; do
    [ -n "$file" ] && files_to_process+=("$file")
  done < <(collect_files_recursive "$EXPORT_DIR" "json conf xml csv txt meta")

  local total_files=${#files_to_process[@]}

  if [ "$total_files" -eq 0 ]; then
    info "No text files found to anonymize"
    return 0
  fi

  progress "Found $total_files files to process..."

  # Initialize progress bar
  progress_init "Anonymizing sensitive data" "$total_files"

  local processed=0
  for file in "${files_to_process[@]}"; do
    anonymize_file "$file"
    ((processed++))
    progress_update "$processed"
  done

  progress_complete

  # Report statistics
  echo ""
  echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│${NC} ${WHITE}Anonymization Summary${NC}"
  echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────┤${NC}"
  echo -e "${CYAN}│${NC}   Files processed:        ${GREEN}$total_files${NC}"
  echo -e "${CYAN}│${NC}   Unique emails mapped:   ${GREEN}$ANON_EMAIL_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   Unique hosts mapped:    ${GREEN}$ANON_HOST_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   Unique webhooks mapped: ${GREEN}$ANON_WEBHOOK_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   API keys/tokens:        ${GREEN}$ANON_APIKEY_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   Slack channels:         ${GREEN}$ANON_SLACK_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   Usernames mapped:       ${GREEN}$ANON_USERNAME_COUNTER${NC}"
  echo -e "${CYAN}│${NC}   IP addresses:           ${GREEN}Redacted (all)${NC}"
  echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${NC}"

  # Write anonymization mapping report (for reference, stored in export)
  local anon_report="$EXPORT_DIR/_anonymization_report.json"
  cat > "$anon_report" << ANON_EOF
{
  "anonymization_applied": true,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "statistics": {
    "files_processed": $total_files,
    "unique_emails_anonymized": $ANON_EMAIL_COUNTER,
    "unique_hosts_anonymized": $ANON_HOST_COUNTER,
    "unique_webhooks_anonymized": $ANON_WEBHOOK_COUNTER,
    "unique_api_keys_anonymized": $ANON_APIKEY_COUNTER,
    "unique_slack_channels_anonymized": $ANON_SLACK_COUNTER,
    "unique_usernames_anonymized": $ANON_USERNAME_COUNTER,
    "ip_addresses": "all_redacted"
  },
  "transformations": {
    "emails": "original@domain.com → user######@anon.dma.local",
    "hostnames": "server.example.com → host-########.anon.local",
    "ipv4": "x.x.x.x → [IP-REDACTED]",
    "ipv6": "xxxx:xxxx:... → [IPv6-REDACTED]",
    "webhook_urls": "https://hooks.slack.com/... → https://webhook.anon.dma.local/hook-############",
    "pagerduty_keys": "abc123def456... → [PAGERDUTY-KEY-########]",
    "api_keys": "token_xyz... → [API-KEY-########]",
    "slack_channels": "#alerts-prod → #anon-channel-######",
    "usernames": "john.smith → anon-user-######"
  },
  "sensitive_fields_covered": [
    "action.email.to",
    "action.email.cc",
    "action.email.bcc",
    "action.webhook.param.url",
    "action.pagerduty.integration_key",
    "action.slack.channel",
    "eai:acl.owner",
    "owner",
    "author",
    "realname",
    "user",
    "username"
  ],
  "note": "This export has been anonymized for safe sharing. Original values cannot be recovered. The same input always produces the same anonymized output, preserving data relationships for analysis."
}
ANON_EOF

  success "Data anonymization complete"
  log "Anonymization: $ANON_EMAIL_COUNTER emails, $ANON_HOST_COUNTER hosts, $ANON_WEBHOOK_COUNTER webhooks, $ANON_APIKEY_COUNTER API keys, $ANON_SLACK_COUNTER Slack channels, $ANON_USERNAME_COUNTER usernames mapped"
}

# =============================================================================
# CREATE ARCHIVE
# =============================================================================

create_archive() {
  # Usage: create_archive [keep_dir] [suffix]
  # keep_dir: if "true", don't delete EXPORT_DIR after archiving (for masked workflow)
  # suffix: optional suffix like "_masked" to add to archive name
  local keep_dir="${1:-false}"
  local suffix="${2:-}"

  # Finalize resilience tracking before archive creation (only on first call)
  if [ "$keep_dir" != "true" ]; then
    finalize_progress "completed"
    # Phase 3: Show export timing statistics
    show_export_timing_stats >&2
  fi

  # All status messages go to stderr so only the tarball path goes to stdout
  if [ -z "$suffix" ]; then
    print_info_box "STEP 8: CREATING ARCHIVE" \
      "" \
      "${WHITE}Compressing all collected data into a single archive...${NC}" >&2
  fi

  # Log Phase 1 resilience statistics
  log "Resilience stats: API calls=$STATS_API_CALLS, retries=$STATS_API_RETRIES, failures=$STATS_API_FAILURES, batches=$STATS_BATCHES_COMPLETED"

  # Finalize debug log if enabled (redirect to stderr so it doesn't pollute tarball path)
  finalize_debug_log >&2

  echo "" >&2
  progress "Creating compressed archive${suffix:+ ($suffix)}..." >&2

  local tarball="/tmp/${EXPORT_NAME}${suffix}.tar.gz"

  # Create the archive
  tar -czf "$tarball" -C /tmp "$EXPORT_NAME" 2>/dev/null

  if [ ! -f "$tarball" ]; then
    error "Failed to create archive" >&2
    exit 1
  fi

  # Get size
  local size=$(du -h "$tarball" | cut -f1)

  # Generate checksum
  local checksum=""
  if command_exists sha256sum; then
    checksum=$(sha256sum "$tarball" | cut -d' ' -f1)
  elif command_exists shasum; then
    checksum=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
  fi

  # Set permissions
  chmod 600 "$tarball"

  success "Archive created: $tarball" >&2
  success "Size: $size" >&2

  if [ -n "$checksum" ]; then
    echo "$checksum  ${EXPORT_NAME}${suffix}.tar.gz" > "${tarball}.sha256"
    info "SHA256: $checksum" >&2
  fi

  # Cleanup export directory only if not keeping
  if [ "$keep_dir" != "true" ]; then
    rm -rf "$EXPORT_DIR"
  fi

  echo "" >&2
  # Only the tarball path goes to stdout (for capture)
  echo "$tarball"
}

# =============================================================================
# MASKED ARCHIVE CREATION (v4.2.3)
# Creates an anonymized copy while preserving the original
# =============================================================================

create_masked_archive() {
  local masked_dir="${EXPORT_DIR}_masked"
  local masked_export_name="${EXPORT_NAME}_masked"

  print_info_box "CREATING MASKED (ANONYMIZED) ARCHIVE" \
    "" \
    "${WHITE}The original archive has been preserved.${NC}" \
    "${WHITE}Now creating a separate anonymized copy...${NC}" >&2

  # Copy export directory to masked version
  progress "Copying export directory for anonymization..." >&2
  cp -r "$EXPORT_DIR" "$masked_dir"

  if [ ! -d "$masked_dir" ]; then
    error "Failed to create masked directory copy" >&2
    return 1
  fi

  # Temporarily switch EXPORT_DIR for anonymization
  # Note: masked_dir already has the correct _masked suffix since EXPORT_DIR=/tmp/EXPORT_NAME
  local original_export_dir="$EXPORT_DIR"
  local original_export_name="$EXPORT_NAME"
  EXPORT_DIR="$masked_dir"
  EXPORT_NAME="$masked_export_name"

  # Run anonymization on the masked copy
  anonymize_export

  # Create the masked archive
  progress "Creating masked archive..." >&2

  local tarball="/tmp/${masked_export_name}.tar.gz"
  tar -czf "$tarball" -C /tmp "$masked_export_name" 2>/dev/null

  if [ ! -f "$tarball" ]; then
    error "Failed to create masked archive" >&2
    EXPORT_DIR="$original_export_dir"
    EXPORT_NAME="$original_export_name"
    rm -rf "$masked_dir"
    return 1
  fi

  # Get size
  local size=$(du -h "$tarball" | cut -f1)

  # Generate checksum
  local checksum=""
  if command_exists sha256sum; then
    checksum=$(sha256sum "$tarball" | cut -d' ' -f1)
  elif command_exists shasum; then
    checksum=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
  fi

  # Set permissions
  chmod 600 "$tarball"

  success "Masked archive created: $tarball" >&2
  success "Size: $size" >&2

  if [ -n "$checksum" ]; then
    echo "$checksum  ${masked_export_name}.tar.gz" > "${tarball}.sha256"
    info "SHA256: $checksum" >&2
  fi

  # Clean up masked directory
  rm -rf "$masked_dir"

  echo "" >&2
  echo -e "  ${YELLOW}Note:${NC} Share the ${BOLD}_masked${NC} archive with third parties." >&2
  echo -e "        Keep the original archive for your records." >&2
  echo "" >&2

  # Restore original EXPORT_DIR/EXPORT_NAME and clean up original
  EXPORT_DIR="$original_export_dir"
  EXPORT_NAME="$original_export_name"
  rm -rf "$EXPORT_DIR"

  # Return the masked tarball path
  echo "$tarball"
}

# =============================================================================
# TROUBLESHOOTING REPORT GENERATOR
# =============================================================================

generate_troubleshooting_report() {
  local report_file="$EXPORT_DIR/TROUBLESHOOTING.md"

  cat > "$report_file" << 'TROUBLESHOOT_HEADER'
# DMA Export Troubleshooting Report

This report was generated because errors occurred during the export.
Use this information to diagnose and resolve issues.

---

TROUBLESHOOT_HEADER

  # Add environment info
  cat >> "$report_file" << EOF
## Environment Information

| Setting | Value |
|---------|-------|
| Script Version | $SCRIPT_VERSION |
| Timestamp | $(date -Iseconds) |
| Hostname | $(get_hostname) |
| OS | $(uname -s) $(uname -r) |
| Splunk Host | ${SPLUNK_HOST}:${SPLUNK_PORT} |
| Splunk Home | ${SPLUNK_HOME:-Not set} |
| Splunk Flavor | ${SPLUNK_FLAVOR:-Unknown} |
| Splunk Role | ${SPLUNK_ROLE:-Unknown} |
| Is Cloud | ${IS_CLOUD} |

---

## Error Summary

**Total Errors:** ${STATS_ERRORS}

## Phase 1 Resilience Statistics

| Metric | Value |
|--------|-------|
| API Calls | ${STATS_API_CALLS} |
| API Retries | ${STATS_API_RETRIES} |
| API Failures | ${STATS_API_FAILURES} |
| Batches Completed | ${STATS_BATCHES_COMPLETED} |
| Batch Size | ${BATCH_SIZE} |
| Max Retries | ${MAX_RETRIES} |
| API Timeout | ${API_TIMEOUT}s |

EOF

  # Scan for error files in _usage_analytics
  if [ -d "$EXPORT_DIR/dma_analytics/usage_analytics" ]; then
    echo "## Failed Searches" >> "$report_file"
    echo "" >> "$report_file"

    local error_count=0
    for json_file in "$EXPORT_DIR/dma_analytics/usage_analytics"/*.json; do
      if [ -f "$json_file" ] && grep -q '"error":' "$json_file" 2>/dev/null; then
        ((error_count++))
        local filename=$(basename "$json_file")
        local error_type=$(grep -o '"error": *"[^"]*"' "$json_file" | head -1 | cut -d'"' -f4)
        local error_msg=$(grep -o '"message": *"[^"]*"' "$json_file" | head -1 | cut -d'"' -f4)

        cat >> "$report_file" << EOF
### Error $error_count: $filename

- **Error Type:** \`$error_type\`
- **Message:** $error_msg

EOF
      fi
    done

    if [ "$error_count" -eq 0 ]; then
      echo "_No search errors detected in output files._" >> "$report_file"
      echo "" >> "$report_file"
    fi
  fi

  # Add common troubleshooting guides
  cat >> "$report_file" << 'TROUBLESHOOT_GUIDES'
---

## Common Issues and Solutions

### 1. Network/Connection Errors (HTTP 000)

**Symptoms:** "Could not connect to Splunk REST API"

**Causes & Solutions:**
- **Splunk not running:** Run `$SPLUNK_HOME/bin/splunk status`
- **Wrong port:** Default is 8089. Check with `netstat -tlnp | grep splunk`
- **Firewall blocking:** Check `iptables -L` or firewall rules
- **SSL issues:** The script uses `-k` flag but some proxies may interfere

**Diagnostic command:**
```bash
curl -k -u admin:password https://localhost:8089/services/server/info
```

---

### 2. Authentication Errors (HTTP 401)

**Symptoms:** "Authentication failed"

**Causes & Solutions:**
- **Wrong password:** Verify credentials work in Splunk Web
- **Account locked:** Check for lockout in `$SPLUNK_HOME/var/log/splunk/splunkd.log`
- **Token expired:** If using API tokens, generate a new one

**Diagnostic command:**
```bash
curl -k -u YOUR_USER:YOUR_PASSWORD https://localhost:8089/services/authentication/current-context
```

---

### 3. Permission Errors (HTTP 403)

**Symptoms:** "User lacks required capabilities"

**Causes & Solutions:**
- **Missing role capabilities:** User needs these capabilities:
  - `search` - Run searches
  - `schedule_search` - Access search job API
  - `list_settings` - Read configurations
  - `rest_properties_get` - REST API access

**To add capabilities:**
1. Go to Settings → Access controls → Roles
2. Edit the user's role
3. Add required capabilities

---

### 4. Search Timeouts

**Symptoms:** "Search timed out after X seconds"

**Causes & Solutions:**
- **Large data volume:** Searches over _audit and _internal can be slow
- **Resource constraints:** Check Splunk scheduler load
- **Network latency:** If Splunk is remote, increase timeout

**Workaround:** Run the failing search manually in Splunk and export results

---

### 5. REST Command Blocked (Splunk Cloud)

**Symptoms:** "REST API endpoint not found" or searches using `| rest` fail

**Causes & Solutions:**
- **Splunk Cloud restriction:** The `| rest` command may be disabled
- Use the **Cloud export script** instead: `dma-splunk-cloud-export.sh`
- Contact Splunk Cloud support to enable REST API access

---

### 6. _audit or _internal Index Empty

**Symptoms:** Usage analytics files have zero results

**Causes & Solutions:**
- **Audit logging disabled:** Check `audit.conf`
- **Retention expired:** Check `indexes.conf` for index retention
- **Different index names:** Some deployments rename internal indexes

**Diagnostic command:**
```bash
# Check if _audit has data
$SPLUNK_HOME/bin/splunk search "index=_audit | head 1" -auth admin:password
```

---

## Getting Help

If you continue to have issues:

1. **Collect these files:**
   - This TROUBLESHOOTING.md
   - export.log
   - $SPLUNK_HOME/var/log/splunk/splunkd.log (last 500 lines)

2. **Contact DMA support** with the above files

3. **Useful commands to run:**
   ```bash
   # Splunk version and health
   $SPLUNK_HOME/bin/splunk version
   $SPLUNK_HOME/bin/splunk status

   # Check REST API is accessible
   curl -k -u admin:password https://localhost:8089/services/server/info?output_mode=json

   # Check user capabilities
   curl -k -u YOUR_USER:YOUR_PASSWORD https://localhost:8089/services/authentication/current-context?output_mode=json
   ```

---

*Report generated by DMA Splunk Export v${SCRIPT_VERSION}*
TROUBLESHOOT_GUIDES

  log "Generated troubleshooting report: $report_file"
}

# =============================================================================
# COMPLETION
# =============================================================================

show_completion() {
  local tarball="$1"
  local masked_tarball="${2:-}"  # Optional: masked archive path (v4.2.3)

  # Calculate total elapsed time
  EXPORT_END_TIME=$(date +%s)
  local total_elapsed=$((EXPORT_END_TIME - EXPORT_START_TIME))
  local elapsed_str=""

  if [ "$total_elapsed" -lt 60 ]; then
    elapsed_str="${total_elapsed} seconds"
  elif [ "$total_elapsed" -lt 3600 ]; then
    elapsed_str="$((total_elapsed / 60))m $((total_elapsed % 60))s"
  else
    elapsed_str="$((total_elapsed / 3600))h $(((total_elapsed % 3600) / 60))m"
  fi

  echo ""
  echo -e "${GREEN}"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════════════════════════════╗
  ║                                                                       ║
  ║                    EXPORT COMPLETED SUCCESSFULLY!                     ║
  ║                                                                       ║
  ╚═══════════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"

  # v4.2.3: Show both archives if masked version was created
  if [ -n "$masked_tarball" ] && [ -f "$masked_tarball" ]; then
    echo -e "  ${WHITE}Original Archive:${NC}  $tarball"
    echo -e "  ${WHITE}                     Size: $(du -h "$tarball" | cut -f1)${NC}"
    echo ""
    echo -e "  ${CYAN}Masked Archive:${NC}    $masked_tarball"
    echo -e "  ${CYAN}                     Size: $(du -h "$masked_tarball" | cut -f1)${NC}"
    echo ""
    echo -e "  ${YELLOW}→ Share the _masked archive with third parties${NC}"
    echo -e "  ${YELLOW}→ Keep the original archive for your records${NC}"
  else
    echo -e "  ${WHITE}Export File:${NC} $tarball"
    echo -e "  ${WHITE}Size:${NC}        $(du -h "$tarball" | cut -f1)"
  fi
  echo -e "  ${WHITE}Duration:${NC}    ${elapsed_str}"
  echo ""

  print_box_header "EXPORT STATISTICS"
  print_box_line ""
  print_box_line "  Applications:    ${STATS_APPS}"
  print_box_line "  Dashboards:      ${STATS_DASHBOARDS}"
  print_box_line "  Alerts:          ${STATS_ALERTS}"
  print_box_line "  Users:           ${STATS_USERS}"
  print_box_line "  Indexes:         ${STATS_INDEXES}"
  print_box_line ""
  print_box_line "  ${CYAN}Total Time:      ${elapsed_str}${NC}"
  print_box_line ""
  if [ "$STATS_ERRORS" -gt 0 ]; then
    print_box_line "  ${YELLOW}Warnings/Errors: ${STATS_ERRORS}${NC}"
    print_box_line "  ${YELLOW}See: TROUBLESHOOTING.md in archive${NC}"
  fi
  print_box_footer

  # Show error warning prominently if there were errors
  if [ "$STATS_ERRORS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}⚠  EXPORT COMPLETED WITH ERRORS${NC}                                     ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${STATS_ERRORS} error(s) occurred during the export. The export file is      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  still usable, but some data may be missing.                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}TO DIAGNOSE:${NC}                                                       ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  1. Extract the archive:                                             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     tar -xzf $(basename "$tarball")                         ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  2. Log files are located at:                                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     ${CYAN}$(pwd)/${EXPORT_NAME}/export.log${NC}              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     ${CYAN}$(pwd)/${EXPORT_NAME}/export_errors.log${NC}       ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  3. Also read: ${EXPORT_NAME}/TROUBLESHOOTING.md                     ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}COMMON FIXES:${NC}                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • Verify user has 'search' and 'admin' capabilities               ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • Check _audit and _internal indexes have data                    ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • For Splunk Cloud, some REST commands may be blocked             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  fi

  echo ""
  echo -e "${WHITE}NEXT STEPS:${NC}"
  echo ""
  echo "  1. Download the export file from this server:"
  echo -e "     ${CYAN}$tarball${NC}"
  echo ""
  echo "  2. Open Dynatrace Migration Assistant in Dynatrace"
  echo ""
  echo "  3. Navigate to: Migration Workspace → Project Initialization"
  echo ""
  echo "  4. Drag and drop the .tar.gz file into the upload area"
  echo ""
  echo "  5. DMA will analyze your environment and show:"
  echo "     • Migration readiness assessment"
  echo "     • Dashboard conversion preview"
  echo "     • Alert conversion checklist"
  echo "     • Data pipeline requirements"
  echo ""

  print_line "─" 75

  echo ""
  echo -e "${GREEN}Thank you for using DMA!${NC}"
  echo ""
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
  # Parse command line arguments for non-interactive mode
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user|--username)
        SPLUNK_USER="$2"
        shift 2
        ;;
      -p|--pass|--password)
        SPLUNK_PASSWORD="$2"
        shift 2
        ;;
      -h|--host)
        SPLUNK_HOST="$2"
        shift 2
        ;;
      -P|--port)
        SPLUNK_PORT="$2"
        shift 2
        ;;
      --splunk-home)
        SPLUNK_HOME="$2"
        shift 2
        ;;
      --anonymize)
        ANONYMIZE_DATA=true
        shift
        ;;
      --no-anonymize)
        ANONYMIZE_DATA=false
        shift
        ;;
      --yes|-y)
        AUTO_CONFIRM=true
        shift
        ;;
      --all-apps)
        EXPORT_ALL_APPS=true
        shift
        ;;
      --apps)
        # Check if value is provided
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
          echo "[ERROR] --apps requires a value (comma-separated app names)" >&2
          exit 1
        fi
        # Clear array first, then populate from comma-separated list
        SELECTED_APPS=()
        IFS=',' read -ra _apps_temp <<< "$2"
        for _app in "${_apps_temp[@]}"; do
          # Trim whitespace
          # Trim whitespace (pure bash)
          _app="${_app#"${_app%%[![:space:]]*}"}"
          _app="${_app%"${_app##*[![:space:]]}"}"
          [ -n "$_app" ] && SELECTED_APPS+=("$_app")
        done
        EXPORT_ALL_APPS=false
        if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
          echo "[WARNING] --apps was specified but no valid apps were parsed from '$2'" >&2
        fi
        shift 2
        ;;
      --quick)
        # Quick mode - dramatically faster exports by skipping global analytics
        QUICK_MODE=true
        SCOPE_TO_APPS=true
        shift
        ;;
      --scoped)
        # Scope all collections to selected apps (auto-enabled with --apps)
        SCOPE_TO_APPS=true
        shift
        ;;
      --no-usage)
        COLLECT_USAGE=false
        shift
        ;;
      --no-rbac)
        COLLECT_RBAC=false
        shift
        ;;
      --debug|-d)
        # Enable verbose debug logging for troubleshooting
        DEBUG_MODE=true
        shift
        ;;
      --help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -u, --username USER     Splunk admin username"
        echo "  -p, --password PASS     Splunk admin password"
        echo "  -h, --host HOST         Splunk host (default: localhost)"
        echo "  -P, --port PORT         Splunk port (default: 8089)"
        echo "  --splunk-home PATH      Splunk installation path"
        echo "  --apps LIST             Comma-separated list of apps to export"
        echo "  --all-apps              Export all applications"
        echo "  --quick                 Quick mode - TESTING ONLY (skips critical migration data)"
        echo "  --scoped                Scope all collections to selected apps only"
        echo "  --no-usage              Skip usage analytics collection"
        echo "  --no-rbac               Skip RBAC/user collection"
        echo "  --anonymize             Enable data anonymization (default)"
        echo "  --no-anonymize          Disable data anonymization"
        echo "  -y, --yes               Auto-confirm all prompts"
        echo "  -d, --debug             Enable verbose debug logging (writes to export_debug.log)"
        echo "  --help                  Show this help message"
        echo ""
        echo "WARNING: --quick is for TESTING/VALIDATION ONLY"
        echo "  Do NOT use --quick for migration analysis. It skips:"
        echo "    - Usage analytics (who uses what, how often)"
        echo "    - User/RBAC data (migration audience identification)"
        echo "    - Priority assessment data"
        echo "  For migration analysis, use full export (default) or --scoped."
        echo ""
        echo "Performance Tips:"
        echo "  For large environments, use --scoped (not --quick) with --apps:"
        echo "    $0 -u admin -p pass --apps myapp --scoped"
        echo ""
        echo "  This exports app configs + app-specific users/usage for migration analysis."
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done

  # Fall back to environment variables if CLI args not provided
  # This is useful for container environments where credentials are in env vars
  if [ -z "$SPLUNK_USER" ] && [ -n "$SPLUNK_ADMIN_USER" ]; then
    SPLUNK_USER="$SPLUNK_ADMIN_USER"
  fi
  # Note: SPLUNK_PASSWORD is already a script variable, so we need to check
  # if it was set via CLI. If not, check environment variables.
  if [ -z "$SPLUNK_PASSWORD" ]; then
    # Check common env var names for Splunk password
    # Try SPLUNK_ADMIN_PASSWORD first (to avoid name collision with script var)
    if [ -n "$SPLUNK_ADMIN_PASSWORD" ]; then
      SPLUNK_PASSWORD="$SPLUNK_ADMIN_PASSWORD"
    fi
  fi

  # =========================================================================
  # DETERMINE INTERACTIVE VS NON-INTERACTIVE MODE
  # Non-interactive requires: -y flag AND (username AND password)
  # Environment variables alone should NOT trigger non-interactive mode
  # =========================================================================
  if [ "$AUTO_CONFIRM" = "true" ] && [ -n "$SPLUNK_USER" ] && [ -n "$SPLUNK_PASSWORD" ]; then
    NON_INTERACTIVE=true
  fi

  # Start overall timer
  EXPORT_START_TIME=$(date +%s)

  # Show welcome
  show_banner

  # Show mode info in non-interactive mode
  if [ "$NON_INTERACTIVE" = "true" ]; then
    echo -e "  ${CYAN}Running in NON-INTERACTIVE mode${NC}"
    echo -e "  ${DIM}User: $SPLUNK_USER${NC}"
    if [ ${#SELECTED_APPS[@]} -gt 0 ]; then
      echo -e "  ${DIM}Apps: ${SELECTED_APPS[*]}${NC}"
    else
      echo -e "  ${DIM}Apps: all (will discover from filesystem)${NC}"
    fi
    if [ "$QUICK_MODE" = "true" ]; then
      echo -e "  ${DIM}Mode: QUICK (no global analytics)${NC}"
    elif [ "$SCOPE_TO_APPS" = "true" ]; then
      echo -e "  ${DIM}Mode: App-scoped analytics${NC}"
    fi
    echo ""
  fi

  show_welcome

  # Check prerequisites
  check_prerequisites

  # Detect environment
  detect_splunk_home
  detect_splunk_flavor

  # Select what to export
  if [ "$SPLUNK_FLAVOR" != "uf" ]; then
    select_applications
    select_data_categories
    authenticate_splunk
    select_usage_period

    # Phase 2: Detect SHC role and show warning if on Captain
    detect_shc_role
    show_shc_captain_warning

    # Phase 2: Check for resume from previous export
    if [ -d "/tmp/dma_export_"* ] 2>/dev/null; then
      check_resume_export
    fi

    # Phase 2: Large environment scope selection
    select_export_scope
  fi

  # Log configuration state for debugging
  debug_config_state

  # =========================================================================
  # WARNING IF NO APP FILTER SPECIFIED
  # =========================================================================
  if [ "$EXPORT_ALL_APPS" = "true" ]; then
    local app_count=${#SELECTED_APPS[@]}
    echo ""
    echo -e "  ${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}║${NC}  ${BOLD}⚠ WARNING: No --apps filter specified${NC}                                ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  The script will export ALL applications from this Splunk Enterprise  ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  environment. In large systems (1000+ dashboards), this may take      ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  several hours to complete.                                           ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  ${DIM}To export specific apps with usage data, use:${NC}                        ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  ${DIM}  --apps \"app1,app2\" --scoped${NC}                                         ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}║${NC}  ${DIM}(--quick is for testing only - skips migration-critical data)${NC}        ${YELLOW}║${NC}"
    echo -e "  ${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Continuing with full export...${NC}"
    echo ""

    # Additional warning for very large environments
    if [ "$app_count" -gt 50 ]; then
      warning "Found ${app_count} apps - this is a large environment!"
      warning "Consider using --apps to filter for faster exports"
    fi
  fi

  # =========================================================================
  # AUTO-ENABLE APP-SCOPED MODE FOR PERFORMANCE
  # =========================================================================
  if [ "$EXPORT_ALL_APPS" = "false" ] && [ "$QUICK_MODE" != "true" ]; then
    # Specific apps were selected - auto-enable scoped mode
    if [ "$SCOPE_TO_APPS" != "true" ]; then
      info "App-scoped mode auto-enabled (specific apps selected)"
      info "  → Usage analytics will be scoped to: ${SELECTED_APPS[*]}"
      info "  → Use --all-apps to collect global analytics"
      SCOPE_TO_APPS=true
    fi
  fi

  # Handle quick mode - skip expensive global collections
  if [ "$QUICK_MODE" = "true" ]; then
    info "Quick mode enabled - skipping global analytics collections"
    COLLECT_RBAC=false
    COLLECT_USAGE=false
    COLLECT_INDEXES=false
  fi

  # Prepare export
  create_export_directory

  # Collect data
  print_box_header "COLLECTING DATA"
  print_box_line ""
  print_box_line "This may take several minutes depending on your environment size."
  print_box_line ""
  print_box_footer
  echo ""

  # Show scale warning if large environment
  local total_apps=${#SELECTED_APPS[@]}
  show_scale_warning "applications" "$total_apps" 50

  collect_system_info

  # Collect system-level macros (global macros from etc/system/local)
  # This captures macros that are automatically available to all apps
  if [ "$COLLECT_CONFIGS" = true ]; then
    collect_system_macros
  fi

  if [ "$COLLECT_CONFIGS" = true ]; then
    # Initialize progress for app collection (same style as Dashboard Studio export)
    progress_init "Exporting Application Configurations" "$total_apps"

    local app_index=0
    local histogram_data=()

    for app in "${SELECTED_APPS[@]}"; do
      ((app_index++))

      # Collect app configs (the actual work)
      collect_app_configs "$app"

      # Collect data for histogram (dashboards per app) - use ls instead of find for container compatibility
      local app_dash_count=0
      for dash_dir in "default/data/ui/views" "local/data/ui/views"; do
        if [ -d "$EXPORT_DIR/$app/$dash_dir" ]; then
          local count=$(ls -1 "$EXPORT_DIR/$app/$dash_dir/"*.xml 2>/dev/null | wc -l | tr -d ' ')
          app_dash_count=$((app_dash_count + count))
        fi
      done
      if [ "$app_dash_count" -gt 0 ]; then
        histogram_data+=("$app:$app_dash_count")
      fi

      # Update progress (single line, updates in place like Dashboard Studio)
      progress_update "$app_index"
    done

    progress_complete

    # Show histogram of dashboards by app (top 15)
    if [ ${#histogram_data[@]} -gt 0 ]; then
      # Sort by count (descending) and take top 15
      local sorted_data=()
      while IFS= read -r line; do
        sorted_data+=("$line")
      done < <(printf '%s\n' "${histogram_data[@]}" | sort -t':' -k2 -nr | head -15)

      if [ ${#sorted_data[@]} -gt 0 ]; then
        show_histogram "Dashboards by Application (Top 15)" "${sorted_data[@]}"
      fi
    fi
  fi

  # =========================================================================
  # APP-SCOPED ANALYTICS COLLECTION
  # Collect usage analytics for each app (dashboard views, alert firing, etc.)
  # This runs after configs so we know which apps have content worth analyzing.
  # =========================================================================
  if [ "$SPLUNK_FLAVOR" != "uf" ] && [ "$COLLECT_USAGE" = true ] && [ -n "$SPLUNK_USER" ]; then
    echo ""
    info "Collecting app-scoped usage analytics..."

    progress_init "Collecting App Usage Analytics" "$total_apps"

    local analytics_index=0
    for app in "${SELECTED_APPS[@]}"; do
      ((analytics_index++))

      # Only collect analytics for apps that have content
      if [ -d "$EXPORT_DIR/$app" ]; then
        collect_app_analytics "$app"
      fi

      progress_update "$analytics_index"
    done

    progress_complete
    success "App-scoped analytics collected (see each app's splunk-analysis/ folder)"
  fi

  if [ "$SPLUNK_FLAVOR" != "uf" ]; then
    collect_dashboard_studio
    collect_rbac
    collect_usage_analytics
  fi

  collect_index_stats
  collect_audit_sample

  # Generate summary and manifest
  generate_summary
  generate_manifest

  # Generate troubleshooting report if there were errors
  if [ "$STATS_ERRORS" -gt 0 ]; then
    warning "Export encountered ${STATS_ERRORS} error(s). Generating troubleshooting report..."
    generate_troubleshooting_report
  fi

  # v4.2.3: Two-archive approach for anonymization
  # Always create original archive first (untouched), then create masked copy if needed
  local tarball
  if [ "$ANONYMIZE_DATA" = true ]; then
    # Create original archive first, keeping EXPORT_DIR for masked copy
    tarball=$(create_archive "true")  # keep_dir=true

    # Create masked (anonymized) archive from a copy
    local masked_tarball
    masked_tarball=$(create_masked_archive)

    # Show completion with both archives
    show_completion "$tarball" "$masked_tarball"
  else
    # No anonymization - just create single archive
    tarball=$(create_archive)

    # Show completion
    show_completion "$tarball"
  fi
}

# Run main
main "$@"
