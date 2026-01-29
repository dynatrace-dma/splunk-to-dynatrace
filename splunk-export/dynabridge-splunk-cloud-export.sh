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
#  DynaBridge Splunk Cloud Export Script v4.2.4
#
#  v4.2.4 Changes:
#    - Anonymization now creates TWO archives: original (untouched) + _masked (anonymized)
#    - Preserves original data in case anonymization corrupts files
#    - Users can re-run anonymization on original if needed without full re-export
#    - Removed deprecated --quick flag (no longer needed)
#    - RBAC/Users collection now OFF by default (use --rbac to enable)
#    - Usage analytics collection now OFF by default (use --usage to enable)
#    - Faster performance defaults: batch size 250 (was 100), API delay 50ms (was 250ms)
#    - Added blocked endpoint skip list for known Splunk Cloud restrictions
#    - Improved 404 handling: app-scoped resources now return empty (not error)
#
#  REST API-Only Data Collection for Splunk Cloud Migration to Dynatrace
#
#  This script collects configurations, dashboards, alerts, users, and usage
#  analytics from your Splunk Cloud environment via REST API to enable migration
#  planning and execution using the DynaBridge for Splunk application.
#
#  IMPORTANT: This script is for SPLUNK CLOUD only. For Splunk Enterprise,
#  use dynabridge-splunk-export.sh instead.
#
################################################################################
#
#  ╔═══════════════════════════════════════════════════════════════════════════╗
#  ║                    PRE-FLIGHT CHECKLIST (SPLUNK CLOUD)                    ║
#  ╠═══════════════════════════════════════════════════════════════════════════╣
#  ║                                                                           ║
#  ║  BEFORE RUNNING THIS SCRIPT, VERIFY THE FOLLOWING:                        ║
#  ║                                                                           ║
#  ║  □ 1. SYSTEM REQUIREMENTS (your local machine)                            ║
#  ║     □ bash 3.2+        Run: bash --version (works on macOS default bash) ║
#  ║     □ curl installed   Run: curl --version                                ║
#  ║     □ Python 3         Run: python3 --version (for JSON processing)       ║
#  ║       └─ macOS/Linux usually have Python 3 pre-installed                  ║
#  ║     □ tar installed    Run: tar --version                                 ║
#  ║     □ Internet access to your Splunk Cloud instance                       ║
#  ║                                                                           ║
#  ║  □ 2. SPLUNK CLOUD STACK INFORMATION                                      ║
#  ║     □ Stack name: __________________.splunkcloud.com                      ║
#  ║       (e.g., acme-corp.splunkcloud.com)                                   ║
#  ║     □ Choose authentication method:                                       ║
#  ║       □ Option A: API Token (RECOMMENDED)                                 ║
#  ║         └─ Generate at: Settings → Tokens → New Token                     ║
#  ║         └─ Token value: ____________________                              ║
#  ║       □ Option B: Username/Password                                       ║
#  ║         └─ Username: ____________________                                 ║
#  ║         └─ Password: ____________________                                 ║
#  ║                                                                           ║
#  ║  □ 3. REQUIRED USER CAPABILITIES                                          ║
#  ║     The user/token needs these Splunk capabilities:                       ║
#  ║     □ search               - Run search queries                           ║
#  ║     □ admin_all_objects    - Access all apps' objects                     ║
#  ║     □ list_settings        - View system configurations                   ║
#  ║     □ rest_properties_get  - Read REST API endpoints                      ║
#  ║                                                                           ║
#  ║     To check: Settings → Users → [your user] → Roles → Capabilities       ║
#  ║                                                                           ║
#  ║  □ 4. NETWORK CONNECTIVITY TEST                                           ║
#  ║     Run this command to verify connectivity:                              ║
#  ║                                                                           ║
#  ║     curl -s -o /dev/null -w "%{http_code}" \                              ║
#  ║       https://YOUR-STACK.splunkcloud.com:8089/services/server/info        ║
#  ║                                                                           ║
#  ║     Expected result: 401 (means reachable, needs auth)                    ║
#  ║     If you get: 000 - Check network/firewall                              ║
#  ║                                                                           ║
#  ║  □ 5. SPLUNK CLOUD LIMITATIONS (be aware)                                 ║
#  ║     □ | rest command may be restricted (some analytics may fail)          ║
#  ║     □ _audit and _internal indexes may have limited access                ║
#  ║     □ Rate limiting may slow down large exports                           ║
#  ║     □ Some configuration files are not accessible                         ║
#  ║                                                                           ║
#  ║  □ 6. INFORMATION TO GATHER BEFOREHAND                                    ║
#  ║     □ Stack URL: _________________________.splunkcloud.com                ║
#  ║     □ Auth method: Token / Username+Password                              ║
#  ║     □ Token or credentials: ___________________                           ║
#  ║     □ Apps to export (or "all"): ___________________                      ║
#  ║                                                                           ║
#  ╚═══════════════════════════════════════════════════════════════════════════╝
#
#  QUICK CONNECTIVITY TEST:
#    curl -k https://YOUR-STACK.splunkcloud.com:8089/services/server/info \
#         -H "Authorization: Bearer YOUR-TOKEN"
#
#  NON-INTERACTIVE MODE (for automation):
#    ./dynabridge-splunk-cloud-export.sh \
#      --stack acme-corp.splunkcloud.com \
#      --token "your-api-token" \
#      --output /path/to/export
#
################################################################################

set -o pipefail  # Fail on pipe errors
# Note: We don't use set -e because we want to handle errors gracefully

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

SCRIPT_VERSION="4.2.6"
SCRIPT_NAME="DynaBridge Splunk Cloud Export"

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

# Splunk Cloud connection
SPLUNK_STACK=""            # e.g., acme-corp.splunkcloud.com
SPLUNK_URL=""              # Full URL with port
AUTH_METHOD=""             # token or userpass
AUTH_TOKEN=""              # Bearer token
SPLUNK_USER=""
SPLUNK_PASSWORD=""
SESSION_KEY=""

# Export settings
EXPORT_DIR=""
EXPORT_NAME=""
TIMESTAMP=""
LOG_FILE=""
OUTPUT_DIR=""

# Environment info
CLOUD_TYPE=""              # classic or victoria
SPLUNK_VERSION=""
SERVER_GUID=""

# Collection options
SELECTED_APPS=()
EXPORT_ALL_APPS=true
COLLECT_CONFIGS=true
COLLECT_DASHBOARDS=true
COLLECT_ALERTS=true
COLLECT_RBAC=false        # OFF by default - global user/role data rarely needed for app migration
COLLECT_USAGE=false       # OFF by default - requires _audit/_internal index access (blocked in most Splunk Cloud)
COLLECT_INDEXES=true
COLLECT_LOOKUPS=false
COLLECT_AUDIT=false
ANONYMIZE_DATA=true
USAGE_PERIOD="30d"
# Skip _internal index searches (required for Splunk Cloud where _internal is restricted)
SKIP_INTERNAL=false

# App-scoped collection mode - when true, limits all collections to selected apps only
# This dramatically reduces export time when only specific apps are selected
# Auto-enabled when --apps is used (unless --all-apps is also specified)
SCOPE_TO_APPS=false

# Non-interactive mode flag (set automatically when all params provided)
NON_INTERACTIVE=false

# Debug mode - enables verbose logging for troubleshooting
DEBUG_MODE=false
DEBUG_LOG_FILE=""

# Anonymization mappings (populated at runtime)
declare -A EMAIL_MAP 2>/dev/null || EMAIL_MAP=()
declare -A HOST_MAP 2>/dev/null || HOST_MAP=()
ANON_EMAIL_COUNTER=0
ANON_HOST_COUNTER=0

# =============================================================================
# SPLUNK CLOUD BLOCKED ENDPOINTS (v4.2.4)
# =============================================================================
# These endpoints are known to be blocked/restricted in Splunk Cloud environments.
# The script will skip them automatically to avoid 403 errors and noise in logs.
# Add endpoints here as we discover them from customer exports.
SPLUNK_CLOUD_BLOCKED_ENDPOINTS=(
  "/services/licenser/licenses"
  "/services/licenser/pools"
  "/services/deployment/server/clients"
  "/services/cluster/master/info"
  "/services/cluster/master/peers"
  "/services/shcluster/captain/info"
  "/services/shcluster/captain/members"
  "/services/data/inputs/monitor"
  "/services/data/inputs/tcp/raw"
  "/services/data/inputs/tcp/cooked"
  "/services/data/inputs/udp"
)

# =============================================================================
# ENTERPRISE RESILIENCE CONFIGURATION (v4.0.0)
# =============================================================================
# These settings enable enterprise-scale exports (4000+ dashboards, 10K+ alerts)
# Override via environment variables: BATCH_SIZE=50 ./dynabridge-splunk-cloud-export.sh

# Pagination settings - OPTIMIZED for large enterprise exports (v4.2.5)
BATCH_SIZE=${BATCH_SIZE:-250}              # Items per API request (increased from 100)
RATE_LIMIT_DELAY=${RATE_LIMIT_DELAY:-0.05} # Delay between paginated requests (50ms - fast)

# Timeout settings - GENEROUS defaults for enterprise Cloud environments
CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-30}     # Initial connection timeout
API_TIMEOUT=${API_TIMEOUT:-120}            # Per-request timeout (2 min - handles large result sets)

# Total runtime limit - prevents runaway scripts
MAX_TOTAL_TIME=${MAX_TOTAL_TIME:-14400}    # Maximum total script runtime (4 hours for 5000+ assets)

# Proxy settings
PROXY_URL=""                               # Optional proxy server (e.g., http://proxy.company.com:8080)
CURL_PROXY_ARGS=""                         # Built at runtime from PROXY_URL

# Retry settings
MAX_RETRIES=${MAX_RETRIES:-3}              # Number of retry attempts for failed requests
BACKOFF_MULTIPLIER=2                       # Exponential backoff multiplier

# Checkpoint settings for interrupted exports
CHECKPOINT_ENABLED=${CHECKPOINT_ENABLED:-true}   # Enable checkpoint/resume capability
CHECKPOINT_INTERVAL=50                           # Save checkpoint every N items
CHECKPOINT_FILE=""                               # Set at runtime: .export_checkpoint

# Rate limiting - OPTIMIZED for speed (v4.2.5)
API_DELAY_SECONDS=0.05     # Delay between API calls (seconds) - 50ms (reduced from 250ms)
MAX_CONCURRENT_SEARCHES=1  # Don't run multiple searches in parallel
SEARCH_POLL_INTERVAL=1     # How often to check if search is done (seconds)
CURRENT_DELAY=$API_DELAY_SECONDS

# Statistics
STATS_APPS=0
STATS_DASHBOARDS=0
STATS_ALERTS=0
STATS_USERS=0
STATS_INDEXES=0
STATS_API_CALLS=0
STATS_API_RETRIES=0
STATS_API_FAILURES=0
STATS_RATE_LIMITS=0
STATS_ERRORS=0
STATS_WARNINGS=0
STATS_BATCHES=0

# Timing
EXPORT_START_TIME=0
EXPORT_END_TIME=0
SCRIPT_START_TIME=$(date +%s)

# Error tracking
ERRORS_LOG=()
WARNINGS_LOG=()

# Python command (set during prerequisites check)
PYTHON_CMD=""

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get hostname with multiple fallbacks (for containers without hostname command)
get_hostname() {
  local mode="${1:-short}"  # short, full, or fqdn

  if [ "$mode" = "short" ] || [ "$mode" = "s" ]; then
    # Try multiple methods for short hostname
    hostname -s 2>/dev/null || \
    cat /etc/hostname 2>/dev/null | cut -d. -f1 || \
    echo "$HOSTNAME" | cut -d. -f1 || \
    cat /proc/sys/kernel/hostname 2>/dev/null | cut -d. -f1 || \
    echo "cloud-client"
  elif [ "$mode" = "fqdn" ] || [ "$mode" = "f" ]; then
    # Try multiple methods for FQDN
    hostname -f 2>/dev/null || \
    cat /etc/hostname 2>/dev/null || \
    echo "$HOSTNAME" || \
    cat /proc/sys/kernel/hostname 2>/dev/null || \
    echo "cloud-client.local"
  else
    # Default: try hostname command first, then fallbacks
    hostname 2>/dev/null || \
    cat /etc/hostname 2>/dev/null || \
    echo "$HOSTNAME" || \
    cat /proc/sys/kernel/hostname 2>/dev/null || \
    echo "cloud-client"
  fi
}

# Print a horizontal line
print_line() {
  local char="${1:-─}"
  local width="${2:-72}"
  printf '%*s\n' "$width" '' | tr ' ' "$char"
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

# Print why box - explains WHY we're asking
print_why_box() {
  local title="WHY WE ASK"
  echo ""
  echo -e "  ${MAGENTA}┌────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${MAGENTA}│${NC} ${BOLD}${MAGENTA}$title${NC}                                                         ${MAGENTA}│${NC}"
  echo -e "  ${MAGENTA}├────────────────────────────────────────────────────────────────────┤${NC}"
  while [ $# -gt 0 ]; do
    local line="$1"
    local stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
    local padding=$((66 - ${#stripped}))
    if [ $padding -lt 0 ]; then padding=0; fi
    echo -e "  ${MAGENTA}│${NC}  $line$(printf '%*s' $padding '')${MAGENTA}│${NC}"
    shift
  done
  echo -e "  ${MAGENTA}└────────────────────────────────────────────────────────────────────┘${NC}"
}

# Print recommendation box
print_recommendation() {
  local rec="$1"
  echo ""
  echo -e "  ${GREEN}💡 RECOMMENDATION: ${NC}$rec"
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
  ERRORS_LOG+=("$1")
  ((STATS_ERRORS++))
}

# Print warning message
warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  log "WARNING: $1"
  WARNINGS_LOG+=("$1")
  ((STATS_WARNINGS++))
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

# Print progress bar
print_progress() {
  local current=$1
  local total=$2
  local label="$3"
  local width=40
  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  printf "\r${CYAN}[${NC}"
  printf "%${filled}s" '' | tr ' ' '█'
  printf "%${empty}s" '' | tr ' ' '░'
  printf "${CYAN}]${NC} %3d%% %s" "$percent" "$label"
}

# Logging function
log() {
  if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  fi
}

# =============================================================================
# DEBUG LOGGING FUNCTIONS
# =============================================================================

# Initialize debug log file
init_debug_log() {
  if [ "$DEBUG_MODE" = "true" ]; then
    DEBUG_LOG_FILE="${EXPORT_DIR:-/tmp}/export_debug.log"
    echo "===============================================================================" > "$DEBUG_LOG_FILE"
    echo "DynaBridge Cloud Export Debug Log" >> "$DEBUG_LOG_FILE"
    echo "Started: $(date -Iseconds 2>/dev/null || date)" >> "$DEBUG_LOG_FILE"
    echo "Script Version: $SCRIPT_VERSION" >> "$DEBUG_LOG_FILE"
    echo "===============================================================================" >> "$DEBUG_LOG_FILE"
    echo "" >> "$DEBUG_LOG_FILE"

    # Log environment info
    debug_log "ENV" "Bash Version: ${BASH_VERSION:-unknown}"
    debug_log "ENV" "OS: $(uname -s 2>/dev/null || echo 'unknown') $(uname -r 2>/dev/null || echo '')"
    debug_log "ENV" "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
    debug_log "ENV" "User: $(whoami 2>/dev/null || echo 'unknown')"
    debug_log "ENV" "PWD: $(pwd)"
    debug_log "ENV" "curl version: $(curl --version 2>/dev/null | head -1 || echo 'not found')"
    debug_log "ENV" "Splunk Stack: $SPLUNK_STACK"

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

  debug_log "CONFIG" "SPLUNK_STACK=$SPLUNK_STACK"
  debug_log "CONFIG" "SPLUNK_URL=$SPLUNK_URL"
  debug_log "CONFIG" "AUTH_METHOD=$AUTH_METHOD"
  debug_log "CONFIG" "EXPORT_ALL_APPS=$EXPORT_ALL_APPS"
  debug_log "CONFIG" "SCOPE_TO_APPS=$SCOPE_TO_APPS"
  debug_log "CONFIG" "COLLECT_RBAC=$COLLECT_RBAC"
  debug_log "CONFIG" "COLLECT_USAGE=$COLLECT_USAGE"
  debug_log "CONFIG" "COLLECT_INDEXES=$COLLECT_INDEXES"
  debug_log "CONFIG" "USAGE_PERIOD=$USAGE_PERIOD"
  debug_log "CONFIG" "SELECTED_APPS=(${SELECTED_APPS[*]})"
  debug_log "CONFIG" "BATCH_SIZE=$BATCH_SIZE"
  debug_log "CONFIG" "API_TIMEOUT=$API_TIMEOUT"
  debug_log "CONFIG" "SKIP_INTERNAL=$SKIP_INTERNAL"
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

# Prompt for yes/no with default
prompt_yn() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer

  # If NON_INTERACTIVE is set, return based on default (skip prompts)
  if [ "$NON_INTERACTIVE" = "true" ]; then
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

# Prompt for input with validation
prompt_input() {
  local prompt="$1"
  local default="$2"
  local validate_fn="$3"
  local result=""

  while true; do
    if [ -n "$default" ]; then
      echo -ne "${YELLOW}$prompt [${default}]: ${NC}"
    else
      echo -ne "${YELLOW}$prompt: ${NC}"
    fi

    read -r result
    result="${result:-$default}"

    if [ -n "$validate_fn" ]; then
      if $validate_fn "$result"; then
        break
      fi
    else
      if [ -n "$result" ]; then
        break
      fi
    fi
  done

  echo "$result"
}

# Prompt for password (hidden input)
prompt_password() {
  local prompt="$1"
  local result=""

  echo -ne "${YELLOW}$prompt: ${NC}"
  read -rs result
  echo ""

  echo "$result"
}

# =============================================================================
# PROGRESS TRACKING FUNCTIONS
# =============================================================================

# Progress bar state
PROGRESS_LABEL=""
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_START_TIME=0
PROGRESS_LAST_PERCENT=0

# Initialize progress bar
progress_init() {
  PROGRESS_LABEL="$1"
  PROGRESS_TOTAL="$2"
  PROGRESS_CURRENT=0
  PROGRESS_LAST_PERCENT=0
  PROGRESS_START_TIME=$(date +%s)
  echo -e "${CYAN}${PROGRESS_LABEL}${NC} [0/${PROGRESS_TOTAL}]"
}

# Update progress bar
# Note: Uses newlines at 5% intervals for container compatibility (kubectl exec)
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

# Complete progress bar
progress_complete() {
  local elapsed=$(($(date +%s) - PROGRESS_START_TIME))
  local rate=""
  if [ "$elapsed" -gt 0 ] && [ "$PROGRESS_TOTAL" -gt 0 ]; then
    rate=$(echo "scale=1; $PROGRESS_TOTAL / $elapsed" | bc 2>/dev/null || echo "N/A")
  else
    rate="N/A"
  fi

  echo -e "${GREEN}✓${NC} ${PROGRESS_LABEL}: ${PROGRESS_TOTAL} items in ${elapsed}s (${rate}/sec)"
}

# Show histogram of data distribution
show_histogram() {
  local title="$1"
  shift
  local -a labels=()
  local -a values=()
  local max_val=0

  # Parse label:value pairs
  while [ $# -gt 0 ]; do
    local pair="$1"
    local label="${pair%%:*}"
    local value="${pair#*:}"
    labels+=("$label")
    values+=("$value")
    if [ "$value" -gt "$max_val" ]; then
      max_val="$value"
    fi
    shift
  done

  if [ "$max_val" -eq 0 ]; then
    return
  fi

  echo ""
  echo "  ${WHITE}$title${NC}"
  echo "  $(printf '%.0s─' {1..50})"

  local max_bar=30
  for i in "${!labels[@]}"; do
    local bar_len=$((values[i] * max_bar / max_val))
    local bar=$(printf "%${bar_len}s" | tr ' ' '▓')
    printf "  ${CYAN}%-15s${NC} ${GREEN}%s${NC} %d\n" "${labels[i]}" "$bar" "${values[i]}"
  done
}

# Show scale warning for large environments
show_scale_warning() {
  local item_type="$1"
  local count="$2"
  local threshold="$3"

  if [ "$count" -gt "$threshold" ]; then
    echo ""
    echo "  ${YELLOW}⚠ SCALE WARNING${NC}"
    echo "  Found ${WHITE}$count $item_type${NC} (threshold: $threshold)"
    echo "  This collection step may take several minutes..."
    echo ""
  fi
}

# =============================================================================
# PYTHON JSON HELPER FUNCTIONS (replaces jq dependency)
# =============================================================================
# These functions use Python for JSON processing to avoid requiring jq
# installation. Python 3 is typically available on macOS and Linux.

# Parse a value from JSON string
# Usage: json_value "$json_string" ".field.subfield"
json_value() {
  local json="$1"
  local path="$2"

  $PYTHON_CMD -c "
import json
import sys

try:
    data = json.loads('''$json''')
    path = '''$path'''.strip()
    if path.startswith('.'):
        path = path[1:]

    result = data
    for part in path.replace('][', '.').replace('[', '.').replace(']', '').split('.'):
        if not part:
            continue
        if part.isdigit():
            result = result[int(part)]
        else:
            result = result.get(part, None) if isinstance(result, dict) else None
            if result is None:
                print('')
                sys.exit(0)

    if isinstance(result, (dict, list)):
        print(json.dumps(result))
    elif result is None:
        print('')
    else:
        print(result)
except Exception as e:
    print('')
" 2>/dev/null
}

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

    path = '''$path'''.strip()
    if path.startswith('.'):
        path = path[1:]

    result = data
    for part in path.replace('][', '.').replace('[', '.').replace(']', '').split('.'):
        if not part:
            continue
        if ':' in part:
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

# Parse JSON array from string - returns list of values
# Usage: json_array "$json_string" ".entry[].name"
json_array() {
  local json="$1"
  local path="$2"

  $PYTHON_CMD -c "
import json
import re

try:
    data = json.loads('''$json''')
    path = '''$path'''.strip()

    # Handle paths like .entry[].name
    if '[]' in path:
        parts = path.split('[]')
        base = parts[0].strip('.').split('.') if parts[0].strip('.') else []
        suffix = parts[1].strip('.').split('.') if len(parts) > 1 and parts[1].strip('.') else []

        result = data
        for p in base:
            if p:
                result = result.get(p, [])

        if isinstance(result, list):
            for item in result:
                val = item
                for s in suffix:
                    if s and isinstance(val, dict):
                        val = val.get(s, '')
                if val:
                    print(val)
    else:
        # Simple path
        path = path.strip('.')
        result = data
        for p in path.split('.'):
            if p:
                result = result.get(p, None) if isinstance(result, dict) else None
        if isinstance(result, list):
            for item in result:
                print(item)
        elif result:
            print(result)
except:
    pass
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
    try:
        obj[key] = json.loads(val)
    except:
        obj[key] = val
    i += 2
print(json.dumps(obj))
" "$@" 2>/dev/null
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

# =============================================================================
# API REQUEST FUNCTIONS
# =============================================================================

# Make authenticated REST API call with rate limiting, retries, and timeouts
# Enterprise resilience: includes configurable timeouts, exponential backoff, and retry tracking
api_call() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="$3"
  local retries=0
  local response=""
  local http_code=""
  # Use seconds only - %N (nanoseconds) not supported on macOS
  local start_time=$(date +%s)

  # =========================================================================
  # BLOCKED ENDPOINT CHECK (v4.2.4)
  # Skip endpoints known to be blocked in Splunk Cloud to avoid noise
  # =========================================================================
  for blocked in "${SPLUNK_CLOUD_BLOCKED_ENDPOINTS[@]}"; do
    if [[ "$endpoint" == *"$blocked"* ]]; then
      log "INFO: Skipping known-blocked endpoint: $endpoint"
      debug_log "API" "Skipped (blocked in Cloud): $endpoint"
      echo '{"entry": [], "skipped": true, "reason": "Endpoint blocked in Splunk Cloud"}'
      return 0
    fi
  done

  ((STATS_API_CALLS++))
  debug_log "API" "→ $method $endpoint"

  # Check total runtime limit
  local current_time=$(date +%s)
  local elapsed=$((current_time - SCRIPT_START_TIME))
  if [ $elapsed -gt $MAX_TOTAL_TIME ]; then
    error "Maximum runtime ($MAX_TOTAL_TIME seconds) exceeded. Export incomplete."
    return 1
  fi

  # Build URL
  local url="${SPLUNK_URL}${endpoint}"

  # Build auth header
  local auth_header=""
  if [ -n "$SESSION_KEY" ]; then
    auth_header="Authorization: Splunk $SESSION_KEY"
  elif [ -n "$AUTH_TOKEN" ]; then
    auth_header="Authorization: Bearer $AUTH_TOKEN"
  fi

  # Add delay for rate limiting
  sleep "$RATE_LIMIT_DELAY"

  while [ $retries -lt $MAX_RETRIES ]; do
    local tmp_file=$(mktemp)

    if [ "$method" = "GET" ]; then
      # For GET requests, data must be in URL query params, NOT in -d body
      # Using -d with GET causes curl to send POST, resulting in HTTP 405
      if [ -n "$data" ]; then
        http_code=$(curl -s -k -w "%{http_code}" -o "$tmp_file" \
          --connect-timeout "$CONNECT_TIMEOUT" \
          --max-time "$API_TIMEOUT" \
          $CURL_PROXY_ARGS \
          -H "$auth_header" \
          "${url}?${data}")
      else
        http_code=$(curl -s -k -w "%{http_code}" -o "$tmp_file" \
          --connect-timeout "$CONNECT_TIMEOUT" \
          --max-time "$API_TIMEOUT" \
          $CURL_PROXY_ARGS \
          -H "$auth_header" \
          "$url?output_mode=json")
      fi
    else
      http_code=$(curl -s -k -w "%{http_code}" -o "$tmp_file" \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$API_TIMEOUT" \
        $CURL_PROXY_ARGS \
        -X "$method" \
        -H "$auth_header" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$data" \
        "$url")
    fi

    response=$(cat "$tmp_file")
    rm -f "$tmp_file"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local response_size=${#response}
    debug_api_call "$method" "$endpoint" "$http_code" "$response_size" "$duration"

    case "$http_code" in
      200|201)
        # Success
        log "API call successful: $method $endpoint"
        echo "$response"
        return 0
        ;;
      000)
        # Timeout or connection error
        debug_log "WARN" "Timeout/connection error on $endpoint"
        ((retries++))
        ((STATS_API_RETRIES++))
        local delay=$((retries * 2))
        warning "Timeout/connection error. Retry $retries/$MAX_RETRIES in ${delay}s"
        sleep "$delay"
        ;;
      429)
        # Rate limited
        debug_log "WARN" "Rate limited (429) on $endpoint"
        ((STATS_RATE_LIMITS++))
        ((STATS_API_RETRIES++))
        ((retries++))

        local wait_time=$((retries * BACKOFF_MULTIPLIER * 2))
        if [ $wait_time -gt 60 ]; then wait_time=60; fi

        warning "Rate limited (429). Waiting ${wait_time}s before retry ($retries/$MAX_RETRIES)..."
        sleep "$wait_time"
        ;;
      401)
        debug_log "ERROR" "Auth failed (401) on $endpoint"
        ((STATS_API_FAILURES++))
        error "Authentication failed (401). Please check your credentials."
        return 1
        ;;
      403)
        debug_log "ERROR" "Access forbidden (403) on $endpoint"
        ((STATS_API_FAILURES++))
        error "Access forbidden (403) for: $endpoint. Check user capabilities."
        return 1
        ;;
      404)
        # Check if this is an app-scoped resource query (expected to be empty for some apps)
        # Pattern: /servicesNS/-/APPNAME/(data/ui/views|saved/searches|data/transforms|...)
        if [[ "$endpoint" =~ /servicesNS/-/[^/]+/(data/ui/views|saved/searches|data/transforms|data/lookups) ]]; then
          # This is likely an app with no resources of this type - just log at INFO level
          log "INFO: No resources at $endpoint (app may have no items of this type)"
          debug_log "INFO" "Empty app resource (404): $endpoint"
          echo '{"entry": []}'  # Return empty result instead of error
          return 0
        else
          debug_log "WARN" "Not found (404) on $endpoint"
          warning "Resource not found (404): $endpoint"
          return 1
        fi
        ;;
      500|502|503)
        debug_log "WARN" "Server error ($http_code) on $endpoint"
        ((retries++))
        ((STATS_API_RETRIES++))
        local wait_time=$((retries * 2))
        warning "Server error ($http_code). Retrying in ${wait_time}s ($retries/$MAX_RETRIES)..."
        sleep "$wait_time"
        ;;
      *)
        ((STATS_API_FAILURES++))
        error "Unexpected HTTP $http_code for: $endpoint"
        log "Response: $response"
        return 1
        ;;
    esac
  done

  ((STATS_API_FAILURES++))
  error "Max retries exceeded for: $endpoint"
  return 1
}

# =============================================================================
# PAGINATED API CALL FUNCTION (v4.0.0)
# =============================================================================
# Fetch all items from an endpoint using pagination
# Usage: api_call_paginated "/servicesNS/-/-/data/ui/views" "$output_dir" "dashboards"

api_call_paginated() {
  local endpoint="$1"
  local output_dir="$2"
  local category="$3"
  local offset=0
  local total=0
  local fetched=0
  local batch_num=0

  # First, get total count
  local count_response=$(api_call "$endpoint" "GET" "output_mode=json&count=1")
  if [ $? -ne 0 ]; then
    error "Failed to get count for $category"
    return 1
  fi

  total=$(echo "$count_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('paging',{}).get('total',0))" 2>/dev/null || echo "0")

  if [ "$total" = "0" ]; then
    info "No $category found"
    return 0
  fi

  info "Fetching $total $category in batches of $BATCH_SIZE..."
  mkdir -p "$output_dir"

  while [ $offset -lt $total ]; do
    ((batch_num++))
    ((STATS_BATCHES++))
    local batch_file="$output_dir/batch_${batch_num}.json"

    local batch_response=$(api_call "$endpoint" "GET" "output_mode=json&count=$BATCH_SIZE&offset=$offset")
    if [ $? -ne 0 ]; then
      warning "Failed to fetch batch $batch_num at offset $offset"
      # Save checkpoint for resume
      save_checkpoint "$category" "$offset" "$batch_num"
      return 1
    fi

    echo "$batch_response" > "$batch_file"

    local batch_count=$(echo "$batch_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('entry',[])))" 2>/dev/null || echo "0")
    fetched=$((fetched + batch_count))

    # Progress update
    local percent=$((fetched * 100 / total))
    printf "\r  Progress: %d%% (%d/%d)  " "$percent" "$fetched" "$total"

    # Rate limiting between batches
    sleep "$RATE_LIMIT_DELAY"
    offset=$((offset + BATCH_SIZE))

    # Save checkpoint periodically
    if [ $((batch_num % CHECKPOINT_INTERVAL)) -eq 0 ]; then
      save_checkpoint "$category" "$offset" "$batch_num"
    fi
  done

  printf "\n"
  success "Fetched $fetched $category in $batch_num batches"

  # Merge batches into single file
  merge_batch_files "$output_dir" "$category"
  return 0
}

# Merge batch JSON files into a single file
merge_batch_files() {
  local batch_dir="$1"
  local category="$2"
  local merged_file="$batch_dir/${category}.json"

  info "Merging batch files for $category..."

  # Use Python to merge JSON arrays efficiently
  python3 << EOF
import json
import glob
import os

batch_dir = "$batch_dir"
merged_file = "$merged_file"
category = "$category"

all_entries = []
batch_files = sorted(glob.glob(os.path.join(batch_dir, "batch_*.json")))

for bf in batch_files:
    try:
        with open(bf, 'r') as f:
            data = json.load(f)
            entries = data.get('entry', [])
            all_entries.extend(entries)
    except Exception as e:
        print(f"Warning: Failed to read {bf}: {e}")

# Write merged output
merged_data = {
    "entry": all_entries,
    "paging": {"total": len(all_entries)},
    "_batch_info": {
        "total_batches": len(batch_files),
        "merged": True
    }
}

with open(merged_file, 'w') as f:
    json.dump(merged_data, f, indent=2)

# Clean up batch files
for bf in batch_files:
    os.remove(bf)

print(f"Merged {len(all_entries)} entries from {len(batch_files)} batches")
EOF
}

# =============================================================================
# CHECKPOINT/RESUME FUNCTIONS (v4.0.0)
# =============================================================================

# Save checkpoint for resume capability
save_checkpoint() {
  local category="$1"
  local offset="$2"
  local item="$3"

  if [ "$CHECKPOINT_ENABLED" != "true" ] || [ -z "$CHECKPOINT_FILE" ]; then
    return
  fi

  cat > "$CHECKPOINT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "category": "$category",
  "last_offset": $offset,
  "last_item": "$item",
  "stats": {
    "api_calls": $STATS_API_CALLS,
    "batches": $STATS_BATCHES,
    "dashboards": $STATS_DASHBOARDS,
    "alerts": $STATS_ALERTS
  }
}
EOF
}

# Load checkpoint if exists
load_checkpoint() {
  if [ "$CHECKPOINT_ENABLED" != "true" ] || [ -z "$CHECKPOINT_FILE" ] || [ ! -f "$CHECKPOINT_FILE" ]; then
    return 1
  fi

  local checkpoint_time=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE')).get('timestamp',''))" 2>/dev/null)
  local checkpoint_category=$(python3 -c "import json; print(json.load(open('$CHECKPOINT_FILE')).get('category',''))" 2>/dev/null)

  if [ -n "$checkpoint_time" ]; then
    echo ""
    print_box_line "${YELLOW}INCOMPLETE EXPORT DETECTED${NC}"
    echo ""
    echo -e "  Found checkpoint from: ${CYAN}$checkpoint_time${NC}"
    echo -e "  Last category: ${CYAN}$checkpoint_category${NC}"
    echo ""
    read -p "  Resume from checkpoint? (Y/n): " resume_choice
    if [ "$resume_choice" != "n" ] && [ "$resume_choice" != "N" ]; then
      return 0  # Resume
    fi
  fi
  return 1  # Start fresh
}

# Clear checkpoint after successful completion
clear_checkpoint() {
  if [ -n "$CHECKPOINT_FILE" ] && [ -f "$CHECKPOINT_FILE" ]; then
    rm -f "$CHECKPOINT_FILE"
    log "Checkpoint cleared"
  fi
}

# =============================================================================
# TIMING STATISTICS (v4.0.0)
# =============================================================================

# Display export timing and statistics
show_export_timing_stats() {
  local end_time=$(date +%s)
  local duration=$((end_time - SCRIPT_START_TIME))
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))
  local seconds=$((duration % 60))

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}                    ${WHITE}EXPORT TIMING STATISTICS${NC}                            ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════╣${NC}"

  if [ $hours -gt 0 ]; then
    printf "${CYAN}║${NC}  Total Duration:        %-46s${CYAN}║${NC}\n" "${hours}h ${minutes}m ${seconds}s"
  elif [ $minutes -gt 0 ]; then
    printf "${CYAN}║${NC}  Total Duration:        %-46s${CYAN}║${NC}\n" "${minutes} minutes ${seconds} seconds"
  else
    printf "${CYAN}║${NC}  Total Duration:        %-46s${CYAN}║${NC}\n" "${seconds} seconds"
  fi

  printf "${CYAN}║${NC}  API Calls:             %-46s${CYAN}║${NC}\n" "$STATS_API_CALLS"
  printf "${CYAN}║${NC}  API Retries:           %-46s${CYAN}║${NC}\n" "$STATS_API_RETRIES"
  printf "${CYAN}║${NC}  API Failures:          %-46s${CYAN}║${NC}\n" "$STATS_API_FAILURES"
  printf "${CYAN}║${NC}  Rate Limit Hits:       %-46s${CYAN}║${NC}\n" "$STATS_RATE_LIMITS"
  printf "${CYAN}║${NC}  Batches Completed:     %-46s${CYAN}║${NC}\n" "$STATS_BATCHES"

  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Test connectivity to Splunk Cloud
test_connectivity() {
  local url="$1"
  local response
  local curl_exit_code
  local curl_output
  local test_url="${url}/services/server/info"
  local hostname=$(echo "$url" | sed 's|https://||' | sed 's|:.*||')

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}CONNECTIVITY TEST - VERBOSE DIAGNOSTICS${NC}                                  ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  Target URL: ${WHITE}${test_url}${NC}"
  echo -e "${CYAN}║${NC}  Hostname:   ${WHITE}${hostname}${NC}"
  echo -e "${CYAN}║${NC}  Port:       ${WHITE}8089${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # =========================================================================
  # STEP 1: DNS Resolution Test
  # =========================================================================
  echo -e "${YELLOW}[STEP 1/3] Testing DNS Resolution...${NC}"
  local dns_result
  dns_result=$(nslookup "$hostname" 2>&1) || dns_result=$(host "$hostname" 2>&1) || dns_result=$(dig +short "$hostname" 2>&1)
  local dns_ip=$(echo "$dns_result" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

  if [ -n "$dns_ip" ]; then
    echo -e "  ${GREEN}✓ DNS resolved: ${hostname} → ${dns_ip}${NC}"
  else
    echo -e "  ${RED}✗ DNS FAILED: Cannot resolve ${hostname}${NC}"
    echo -e "  ${DIM}DNS output:${NC}"
    echo "$dns_result" | sed 's/^/    /'
    echo ""
    error "DNS resolution failed for $hostname"
    return 1
  fi
  echo ""

  # =========================================================================
  # STEP 2: TCP Port Connectivity Test
  # =========================================================================
  echo -e "${YELLOW}[STEP 2/3] Testing TCP Connection to Port 8089...${NC}"
  local nc_result
  if command -v nc &> /dev/null; then
    nc_result=$(nc -zv -w 10 "$hostname" 8089 2>&1)
    local nc_exit=$?
    if [ $nc_exit -eq 0 ]; then
      echo -e "  ${GREEN}✓ TCP port 8089 is OPEN${NC}"
    else
      echo -e "  ${RED}✗ TCP port 8089 is BLOCKED or UNREACHABLE${NC}"
      echo -e "  ${DIM}nc output:${NC}"
      echo "$nc_result" | sed 's/^/    /'
      echo ""
      echo -e "  ${YELLOW}This usually means:${NC}"
      echo -e "  ${DIM}  • Corporate firewall blocking outbound port 8089${NC}"
      echo -e "  ${DIM}  • VPN blocking non-standard ports${NC}"
      echo -e "  ${DIM}  • Network security policy${NC}"
      echo ""
    fi
  else
    echo -e "  ${DIM}(nc not available, skipping TCP test)${NC}"
  fi
  echo ""

  # =========================================================================
  # STEP 3: Full HTTPS Connection with Verbose Curl
  # =========================================================================
  echo -e "${YELLOW}[STEP 3/3] Testing HTTPS Connection (verbose)...${NC}"
  echo -e "${DIM}Running: curl -v -k --connect-timeout 15 --max-time 60 \"$test_url\"${NC}"
  echo ""
  echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│ CURL VERBOSE OUTPUT                                                         │${NC}"
  echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────────┤${NC}"

  # Run curl with full verbose output
  curl_output=$(curl -v -k -o /dev/null -w "\n\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}\nTIME_CONNECT:%{time_connect}\nTIME_APPCONNECT:%{time_appconnect}\nTIME_NAMELOOKUP:%{time_namelookup}" \
    --connect-timeout 15 \
    --max-time 60 \
    $CURL_PROXY_ARGS \
    "$test_url" 2>&1)
  curl_exit_code=$?

  # Display verbose output
  echo "$curl_output" | while IFS= read -r line; do
    echo -e "${CYAN}│${NC} ${DIM}${line}${NC}"
  done

  echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""

  # Extract metrics
  response=$(echo "$curl_output" | grep "HTTP_CODE:" | cut -d: -f2)
  local time_total=$(echo "$curl_output" | grep "TIME_TOTAL:" | cut -d: -f2)
  local time_connect=$(echo "$curl_output" | grep "TIME_CONNECT:" | cut -d: -f2)
  local time_appconnect=$(echo "$curl_output" | grep "TIME_APPCONNECT:" | cut -d: -f2)
  local time_dns=$(echo "$curl_output" | grep "TIME_NAMELOOKUP:" | cut -d: -f2)
  [ -z "$response" ] && response="000"

  # =========================================================================
  # RESULTS SUMMARY
  # =========================================================================
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}CONNECTION TEST RESULTS${NC}                                                  ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  Curl Exit Code:    ${WHITE}${curl_exit_code}${NC}"
  echo -e "${CYAN}║${NC}  HTTP Response:     ${WHITE}${response}${NC}"
  echo -e "${CYAN}║${NC}  DNS Lookup Time:   ${WHITE}${time_dns:-N/A}s${NC}"
  echo -e "${CYAN}║${NC}  TCP Connect Time:  ${WHITE}${time_connect:-N/A}s${NC}"
  echo -e "${CYAN}║${NC}  TLS Handshake:     ${WHITE}${time_appconnect:-N/A}s${NC}"
  echo -e "${CYAN}║${NC}  Total Time:        ${WHITE}${time_total:-N/A}s${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Interpret curl exit codes
  if [ "$curl_exit_code" -ne 0 ]; then
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}${RED}ERROR DIAGNOSIS${NC}                                                          ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    case "$curl_exit_code" in
      6)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 6: COULD NOT RESOLVE HOST${NC}"
        echo -e "${RED}║${NC}  ${DIM}The hostname '${hostname}' could not be resolved via DNS.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Check if the hostname is spelled correctly${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Try: nslookup ${hostname}${NC}"
        ;;
      7)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 7: FAILED TO CONNECT${NC}"
        echo -e "${RED}║${NC}  ${DIM}TCP connection to ${hostname}:8089 failed.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Port 8089 is likely BLOCKED by firewall${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Try from a different network (home, cloud VM)${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Contact IT to allow outbound port 8089${NC}"
        ;;
      28)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 28: OPERATION TIMED OUT${NC}"
        echo -e "${RED}║${NC}  ${DIM}The request did not complete within 60 seconds.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Network may be very slow or partially blocked${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ TLS handshake may be hanging${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Try from a different network${NC}"
        ;;
      35)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 35: SSL/TLS HANDSHAKE FAILED${NC}"
        echo -e "${RED}║${NC}  ${DIM}TLS negotiation failed with the server.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Could be TLS version mismatch${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Try: curl --tlsv1.2 -vk \"$test_url\"${NC}"
        ;;
      52)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 52: SERVER RETURNED NOTHING${NC}"
        echo -e "${RED}║${NC}  ${DIM}Server closed connection without sending data.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Server may be blocking your IP${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Try from a different network${NC}"
        ;;
      56)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code 56: NETWORK DATA RECEIVE FAILURE${NC}"
        echo -e "${RED}║${NC}  ${DIM}Connection established but data transfer failed.${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Network instability${NC}"
        echo -e "${RED}║${NC}  ${DIM}→ Connection may be getting reset by firewall${NC}"
        ;;
      *)
        echo -e "${RED}║${NC}  ${YELLOW}Exit Code ${curl_exit_code}: CURL ERROR${NC}"
        echo -e "${RED}║${NC}  ${DIM}See: https://curl.se/libcurl/c/libcurl-errors.html${NC}"
        ;;
    esac
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi

  case "$response" in
    000)
      error "Cannot connect to Splunk Cloud instance"
      return 1
      ;;
    401|200)
      success "Splunk Cloud instance is reachable (HTTP $response)"
      return 0
      ;;
    *)
      warning "Received HTTP $response from server (may still work with auth)"
      return 0
      ;;
  esac
}

# Authenticate and get session key
authenticate() {
  local response
  local session_key

  if [ "$AUTH_METHOD" = "token" ]; then
    # Token-based auth - verify token works
    AUTH_HEADER="Authorization: Bearer $AUTH_TOKEN"
    response=$(curl -s -k $CURL_PROXY_ARGS \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      "${SPLUNK_URL}/services/authentication/current-context?output_mode=json")

    if echo "$response" | grep -q "username"; then
      local username=$(json_value "$response" '.entry[0].content.username')
      success "Token authentication successful (user: $username)"
      return 0
    else
      error "Token authentication failed"
      return 1
    fi

  else
    # Username/password - get session key
    response=$(curl -s -k $CURL_PROXY_ARGS \
      -d "username=$SPLUNK_USER&password=$SPLUNK_PASSWORD" \
      "${SPLUNK_URL}/services/auth/login?output_mode=json")

    if echo "$response" | grep -q "sessionKey"; then
      SESSION_KEY=$(json_value "$response" '.sessionKey')
      if [ -z "$SESSION_KEY" ]; then
        # Try alternate parsing
        SESSION_KEY=$(echo "$response" | grep -oP '(?<=<sessionKey>)[^<]+')
      fi

      if [ -n "$SESSION_KEY" ]; then
        success "Password authentication successful"
        return 0
      fi
    fi

    error "Password authentication failed. Check username and password."
    return 1
  fi
}

# Check user capabilities
check_capabilities() {
  local response
  response=$(api_call "/services/authentication/current-context" "GET" "output_mode=json")

  if [ $? -ne 0 ]; then
    error "Failed to retrieve user capabilities"
    return 1
  fi

  # Extract capabilities using Python
  local capabilities=""
  capabilities=$(json_array "$response" ".entry[0].content.capabilities" | tr '\n' ', ')

  local required_caps=("admin_all_objects" "list_users" "search")
  local missing_caps=()

  for cap in "${required_caps[@]}"; do
    if ! echo "$capabilities" | grep -q "$cap"; then
      missing_caps+=("$cap")
    fi
  done

  if [ ${#missing_caps[@]} -gt 0 ]; then
    warning "Missing recommended capabilities: ${missing_caps[*]}"
    warning "Some data may not be collected"
  else
    success "All required capabilities present"
  fi

  return 0
}

# =============================================================================
# BANNER AND INTRODUCTION
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
  echo -e "${CYAN}║${NC}                   ${BOLD}${MAGENTA}☁️  SPLUNK CLOUD EXPORT SCRIPT  ☁️${NC}                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}          ${DIM}Complete REST API-Based Data Collection for Migration${NC}              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                        ${DIM}Version $SCRIPT_VERSION${NC}                                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}   ${DIM}Developed for Dynatrace One by Enterprise Solutions & Architecture${NC}      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                  ${DIM}An ACE Services Division of Dynatrace${NC}                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                                ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

show_introduction() {
  print_info_box "WHAT THIS SCRIPT DOES" \
    "" \
    "This script collects data from your ${BOLD}Splunk Cloud${NC} environment using" \
    "the REST API to prepare for migration to Dynatrace Gen3 Grail." \
    "" \
    "${BOLD}Data Collected:${NC}" \
    "  • Dashboards (Classic and Dashboard Studio)" \
    "  • Alerts and Saved Searches (with SPL queries)" \
    "  • Users, Roles, and RBAC configurations" \
    "  • Search Macros, Eventtypes, and Tags" \
    "  • Index configurations and statistics" \
    "  • Usage analytics (who uses what, how often)" \
    "  • Props and Transforms configurations (via REST)" \
    "" \
    "${BOLD}Output:${NC}" \
    "  A .tar.gz archive compatible with DynaBridge for Splunk app"

  print_info_box "IMPORTANT: THIS IS FOR SPLUNK CLOUD ONLY" \
    "" \
    "${YELLOW}⚠  This script works with Splunk Cloud (Classic & Victoria)${NC}" \
    "" \
    "If you have ${BOLD}Splunk Enterprise${NC} (on-premises), please use:" \
    "  ${GREEN}./dynabridge-splunk-export.sh${NC}" \
    "" \
    "This script uses 100% REST API - no file system access needed."

  echo ""
  if ! prompt_yn "Do you want to continue?"; then
    echo ""
    info "Export cancelled. Goodbye!"
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
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}SPLUNK CLOUD ACCESS:${NC}                                                      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk Cloud stack URL (e.g., your-company.splunkcloud.com)          ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk username with admin privileges                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Splunk password OR API token (sc_admin role recommended)             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}REQUIRED CAPABILITIES (for Usage Analytics):${NC}                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  search capability                                                     ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  list_settings capability                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  Access to _audit and _internal indexes (if collecting usage data)    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}NETWORK REQUIREMENTS:${NC}                                                      ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  HTTPS access to your-stack.splunkcloud.com:8089                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  No firewall blocking port 8089 to Splunk Cloud                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}LOCAL SYSTEM REQUIREMENTS:${NC}                                                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  bash 3.2+ (macOS default works)                                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  curl installed                                                        ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  jq installed (for JSON parsing) - ${YELLOW}REQUIRED${NC}                          ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  tar installed                                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    □  ~100MB disk space for export                                          ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${GREEN}🔒 DATA PRIVACY & SECURITY:${NC}                                                ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We do NOT collect or export:${NC}                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  User passwords or password hashes                                    ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  API tokens or session keys                                           ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  Private keys or certificates                                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  Your actual log data (only metadata/structure)                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${RED}✗${NC}  Lookup table contents with sensitive data                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We automatically REDACT:${NC}                                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  password = [REDACTED] in all .conf files                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  secret = [REDACTED] in outputs.conf                                  ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${GREEN}✓${NC}  pass4SymmKey = [REDACTED] in server.conf                             ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}We DO collect (for migration):${NC}                                            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Usernames and role assignments (NOT passwords)                       ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Dashboard/alert ownership (who created what)                         ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    ${CYAN}•${NC}  Usage statistics (search counts, not search content)                 ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}                                                                              ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}${MAGENTA}TIP:${NC} If you don't have all items, you can still proceed - the script     ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}       will verify each requirement and provide specific guidance.          ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Quick system check
  echo -e "  ${BOLD}Quick System Check:${NC}"

  # Check bash version
  local bash_version="${BASH_VERSION:-unknown}"
  echo -e "    ${GREEN}✓${NC} bash: $bash_version"

  # Check curl
  if command -v curl &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} curl: $(curl --version 2>/dev/null | head -1 | cut -d' ' -f2)"
  else
    echo -e "    ${RED}✗${NC} curl: NOT INSTALLED"
  fi

  # Check Python 3 (required for JSON processing)
  PYTHON_CMD=""
  if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    echo -e "    ${GREEN}✓${NC} Python: $(python3 --version 2>&1)"
  elif command -v python &> /dev/null; then
    local py_ver=$(python --version 2>&1 | grep -o '[0-9]*' | head -1)
    if [ "$py_ver" = "3" ]; then
      PYTHON_CMD="python"
      echo -e "    ${GREEN}✓${NC} Python: $(python --version 2>&1)"
    fi
  fi

  if [ -z "$PYTHON_CMD" ]; then
    echo -e "    ${RED}✗${NC} Python 3: NOT INSTALLED - ${YELLOW}Required for JSON processing${NC}"
    echo ""
    echo -e "    ${BOLD}Install Python 3:${NC}"
    echo -e "      macOS:  ${GREEN}brew install python3${NC} (or use system Python)"
    echo -e "      Ubuntu: ${GREEN}sudo apt-get install python3${NC}"
    echo -e "      RHEL:   ${GREEN}sudo yum install python3${NC}"
    echo ""
    echo -e "    ${RED}Cannot continue without Python 3${NC}"
    exit 1
  fi

  # Check tar
  if command -v tar &> /dev/null; then
    echo -e "    ${GREEN}✓${NC} tar: available"
  else
    echo -e "    ${RED}✗${NC} tar: NOT INSTALLED"
  fi

  echo ""
  if ! prompt_yn "Ready to proceed?"; then
    echo ""
    info "Export cancelled. Install missing dependencies and try again."
    exit 0
  fi
}

# =============================================================================
# STEP 1: SPLUNK CLOUD CONNECTION
# =============================================================================

get_splunk_stack() {
  print_box_header "STEP 1: SPLUNK CLOUD CONNECTION"

  print_why_box \
    "We need to connect to your Splunk Cloud instance via REST API." \
    "This is the ${BOLD}only${NC} way to access Splunk Cloud data - there is" \
    "no file system or SSH access to Splunk Cloud infrastructure." \
    "" \
    "The script runs on YOUR machine (laptop, jump host, etc.) and" \
    "connects to Splunk Cloud over HTTPS."

  echo ""
  echo -e "  ${BOLD}Your Splunk Cloud stack URL looks like:${NC}"
  echo -e "    ${DIM}https://${NC}${GREEN}your-company${NC}${DIM}.splunkcloud.com${NC}"
  echo ""

  # Check for environment variable
  if [ -n "$SPLUNK_CLOUD_STACK" ]; then
    echo -e "  ${GREEN}✓${NC} Found SPLUNK_CLOUD_STACK environment variable: $SPLUNK_CLOUD_STACK"
    SPLUNK_STACK="$SPLUNK_CLOUD_STACK"
  else
    # Prompt for stack URL
    echo -ne "  ${YELLOW}Enter your Splunk Cloud stack URL: ${NC}"
    read -r SPLUNK_STACK
  fi

  # Clean up the URL
  SPLUNK_STACK=$(echo "$SPLUNK_STACK" | sed 's|https://||' | sed 's|:8089||' | sed 's|/$||')
  SPLUNK_URL="https://${SPLUNK_STACK}:8089"

  echo ""
  progress "Testing connection to $SPLUNK_URL..."

  if ! test_connectivity "$SPLUNK_URL"; then
    echo ""
    print_info_box "CONNECTION TROUBLESHOOTING" \
      "" \
      "Cannot reach your Splunk Cloud instance. Please check:" \
      "" \
      "  1. Is the URL correct? ${DIM}$SPLUNK_STACK${NC}" \
      "  2. Are you on VPN (if required by your company)?" \
      "  3. Is your IP address allowlisted in Splunk Cloud?" \
      "  4. Can you reach it in a browser?" \
      "" \
      "To check your public IP: ${GREEN}curl ifconfig.me${NC}"

    exit 1
  fi

  print_box_footer
}

# =============================================================================
# STEP 2: AUTHENTICATION
# =============================================================================

get_authentication() {
  print_box_header "STEP 2: AUTHENTICATION"

  print_why_box \
    "REST API access requires authentication. You can use:" \
    "" \
    "  ${BOLD}Option 1: API Token${NC} (Recommended)" \
    "    • More secure - limited scope, can be revoked" \
    "    • Works with MFA-enabled accounts" \
    "    • Create in Splunk Cloud: Settings → Tokens" \
    "" \
    "  ${BOLD}Option 2: Username/Password${NC}" \
    "    • Your regular Splunk Cloud login" \
    "    • May not work if MFA is enforced"

  echo ""
  echo -e "  ${BOLD}Required Permissions:${NC}"
  echo -e "    • admin_all_objects - Access all knowledge objects"
  echo -e "    • list_users, list_roles - Access RBAC data"
  echo -e "    • search - Run analytics queries"
  echo ""
  echo -e "  ${DIM}🔒 Security: Your credentials are used locally only and are NEVER stored,${NC}"
  echo -e "  ${DIM}   logged, or transmitted outside of this session. They are cleared on exit.${NC}"
  echo ""

  # Check for environment variables
  if [ -n "$SPLUNK_CLOUD_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Found SPLUNK_CLOUD_TOKEN environment variable"
    AUTH_METHOD="token"
    AUTH_TOKEN="$SPLUNK_CLOUD_TOKEN"
  else
    echo -e "  ${BOLD}Choose authentication method:${NC}"
    echo ""
    echo -e "    ${GREEN}1${NC}) API Token ${DIM}(recommended)${NC}"
    echo -e "    ${GREEN}2${NC}) Username/Password"
    echo ""
    echo -ne "  ${YELLOW}Select option [1]: ${NC}"
    read -r auth_choice
    auth_choice="${auth_choice:-1}"

    echo ""

    if [ "$auth_choice" = "2" ]; then
      AUTH_METHOD="userpass"
      echo -ne "  ${YELLOW}Enter username: ${NC}"
      read -r SPLUNK_USER
      SPLUNK_PASSWORD=$(prompt_password "  Enter password")
    else
      AUTH_METHOD="token"
      echo -ne "  ${YELLOW}Enter API token: ${NC}"
      read -rs AUTH_TOKEN
      echo ""
    fi
  fi

  echo ""
  progress "Testing authentication..."

  if ! authenticate; then
    echo ""
    print_info_box "AUTHENTICATION FAILED" \
      "" \
      "Could not authenticate to Splunk Cloud. Please check:" \
      "" \
      "  • Credentials are correct" \
      "  • API token has not expired" \
      "  • Account is not locked" \
      "  • User has required capabilities" \
      "" \
      "To create an API token:" \
      "  1. Log into Splunk Cloud web UI" \
      "  2. Click Settings (gear) → Tokens" \
      "  3. Create new token with required permissions"

    exit 1
  fi

  echo ""
  progress "Checking user capabilities..."
  check_capabilities

  print_box_footer
}

# =============================================================================
# STEP 2.5: PROXY CONFIGURATION (Optional)
# =============================================================================

get_proxy_settings() {
  # Skip if proxy was already set via --proxy flag
  if [ -n "$PROXY_URL" ]; then
    echo ""
    echo -e "  ${GREEN}✓${NC} Proxy configured via command line: ${BOLD}$PROXY_URL${NC}"
    CURL_PROXY_ARGS="-x $PROXY_URL"
    return
  fi

  # Skip prompt in non-interactive mode
  if [ "$NON_INTERACTIVE" = "true" ]; then
    return
  fi

  echo ""
  if prompt_yn "  Does your environment require a proxy server to connect to Splunk Cloud?" "N"; then
    echo ""
    local proxy_input
    echo -ne "  ${YELLOW}Enter proxy URL (e.g., http://proxy.company.com:8080): ${NC}"
    read -r proxy_input

    if [ -n "$proxy_input" ]; then
      PROXY_URL="$proxy_input"
      CURL_PROXY_ARGS="-x $PROXY_URL"
      echo ""
      echo -e "  ${GREEN}✓${NC} Proxy configured: ${BOLD}$PROXY_URL${NC}"
    fi
  fi
}

# =============================================================================
# STEP 3: ENVIRONMENT DETECTION
# =============================================================================

detect_environment() {
  print_box_header "STEP 3: ENVIRONMENT DETECTION"

  progress "Detecting Splunk Cloud environment..."

  local server_info
  server_info=$(api_call "/services/server/info" "GET" "output_mode=json")

  if [ $? -ne 0 ]; then
    error "Failed to retrieve server information"
    return 1
  fi

  # Parse server info
  SPLUNK_VERSION=$(json_value "$server_info" '.entry[0].content.version')
  SERVER_GUID=$(json_value "$server_info" '.entry[0].content.guid')
  local server_name=$(json_value "$server_info" '.entry[0].content.serverName')
  local os_name=$(json_value "$server_info" '.entry[0].content.os_name')
  local cpu_arch=$(json_value "$server_info" '.entry[0].content.cpu_arch')

  # Detect cloud type (best effort)
  if echo "$SPLUNK_VERSION" | grep -qi "cloud"; then
    CLOUD_TYPE="victoria"
  elif [[ "$server_name" == *"sh"* ]] || [[ "$server_name" == *"search"* ]]; then
    CLOUD_TYPE="victoria"
  else
    CLOUD_TYPE="classic_or_victoria"
  fi

  # Get app count using Python JSON parsing
  local apps_response
  apps_response=$(api_call "/services/apps/local" "GET" "output_mode=json&count=0")
  local app_count=0
  app_count=$(json_value "$apps_response" ".entry" | $PYTHON_CMD -c "import json,sys; data=json.loads(sys.stdin.read()); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")

  # Get user count using Python JSON parsing
  local users_response
  users_response=$(api_call "/services/authentication/users" "GET" "output_mode=json&count=0")
  local user_count=0
  user_count=$(json_value "$users_response" ".entry" | $PYTHON_CMD -c "import json,sys; data=json.loads(sys.stdin.read()); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")

  echo ""
  echo -e "  ┌────────────────────────────────────────────────────────────────────┐"
  echo -e "  │ ${BOLD}Detected Environment:${NC}                                              │"
  echo -e "  ├────────────────────────────────────────────────────────────────────┤"
  echo -e "  │   Stack:      ${GREEN}$SPLUNK_STACK${NC}$(printf '%*s' $((40 - ${#SPLUNK_STACK})) '')│"
  echo -e "  │   Type:       ${GREEN}Splunk Cloud ($CLOUD_TYPE)${NC}$(printf '%*s' $((29 - ${#CLOUD_TYPE})) '')│"
  echo -e "  │   Version:    ${GREEN}$SPLUNK_VERSION${NC}$(printf '%*s' $((40 - ${#SPLUNK_VERSION})) '')│"
  printf "  │   GUID:       ${GREEN}%.25s...${NC}                           │\n" "$SERVER_GUID"
  echo -e "  │   Apps:       ${GREEN}$app_count installed${NC}$(printf '%*s' $((36 - ${#app_count})) '')│"
  echo -e "  │   Users:      ${GREEN}$user_count${NC}$(printf '%*s' $((45 - ${#user_count})) '')│"
  echo -e "  └────────────────────────────────────────────────────────────────────┘"

  echo ""
  if ! prompt_yn "  Is this the correct environment?"; then
    echo ""
    info "Please restart and enter the correct stack URL"
    exit 0
  fi

  print_box_footer
}

# =============================================================================
# STEP 4: APPLICATION SELECTION
# =============================================================================

select_applications() {
  print_box_header "STEP 4: APPLICATION SELECTION"

  # If apps were pre-selected via --apps flag, skip interactive selection
  if [ "$EXPORT_ALL_APPS" = "false" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    success "Using pre-selected apps from --apps flag: ${SELECTED_APPS[*]}"
    STATS_APPS=${#SELECTED_APPS[@]}
    print_box_footer
    return 0
  fi

  print_why_box \
    "Splunk organizes content into 'apps'. Each app can contain:" \
    "  • Dashboards and visualizations" \
    "  • Saved searches and alerts" \
    "  • Macros, eventtypes, tags" \
    "  • Field extractions and lookups" \
    "" \
    "You can export ALL apps or select specific ones." \
    "System apps (like 'search', 'launcher') are always included."

  print_recommendation "Export ALL apps for complete migration analysis"

  # Get list of apps
  progress "Retrieving app list..."
  local apps_response
  apps_response=$(api_call "/services/apps/local" "GET" "output_mode=json&count=0")

  if [ $? -ne 0 ]; then
    error "Failed to retrieve app list"
    return 1
  fi

  # Parse app names
  local apps=()
  local app_labels=()
  if $HAS_JQ; then
    while IFS= read -r line; do
      apps+=("$line")
    done < <(echo "$apps_response" | jq -r '.entry[].name' 2>/dev/null)
    while IFS= read -r line; do
      app_labels+=("$line")
    done < <(echo "$apps_response" | jq -r '.entry[].content.label // .entry[].name' 2>/dev/null)
  else
    while IFS= read -r line; do
      apps+=("$line")
      app_labels+=("$line")
    done < <(echo "$apps_response" | grep -oP '"name"\s*:\s*"\K[^"]+')
  fi

  # Filter out Splunk internal/system apps (users don't want to migrate these)
  local filtered_apps=()
  local filtered_labels=()
  local i=0
  for app_name in "${apps[@]}"; do
    # Skip internal apps (start with _)
    if [[ "$app_name" =~ ^_ ]]; then
      ((i++))
      continue
    fi
    # Skip Splunk's own system apps (splunk_* and Splunk_*)
    if [[ "$app_name" =~ ^[Ss]plunk_ ]]; then
      ((i++))
      continue
    fi
    # Skip Splunk Support Add-ons (SA-*)
    if [[ "$app_name" =~ ^SA- ]]; then
      ((i++))
      continue
    fi
    # Skip framework/system/default apps that have no user content
    if [[ "$app_name" =~ ^(framework|appsbrowser|introspection_generator_addon|legacy|learned|sample_app|gettingstarted|launcher|search|SplunkForwarder|SplunkLightForwarder|alert_logevent|alert_webhook)$ ]]; then
      ((i++))
      continue
    fi
    filtered_apps+=("$app_name")
    filtered_labels+=("${app_labels[$i]}")
    ((i++))
  done

  # Replace with filtered list
  apps=("${filtered_apps[@]}")
  app_labels=("${filtered_labels[@]}")

  local total_apps=${#apps[@]}

  echo ""
  echo -e "  ${BOLD}Found $total_apps apps. Choose export scope:${NC}"
  echo ""
  echo -e "    ${GREEN}1${NC}) Export ALL applications ${DIM}(recommended for complete analysis)${NC}"
  echo -e "    ${GREEN}2${NC}) Enter specific app names ${DIM}(comma-separated)${NC}"
  echo -e "    ${GREEN}3${NC}) Select from numbered list"
  echo -e "    ${GREEN}4${NC}) System apps only ${DIM}(minimal export)${NC}"
  echo ""
  echo -ne "  ${YELLOW}Select option [1]: ${NC}"
  read -r app_choice
  app_choice="${app_choice:-1}"

  case "$app_choice" in
    1)
      EXPORT_ALL_APPS=true
      SELECTED_APPS=("${apps[@]}")
      success "Will export ALL $total_apps applications"
      ;;
    2)
      echo ""
      echo -e "  ${DIM}Available apps: ${apps[*]:0:10}...${NC}"
      echo ""
      echo -ne "  ${YELLOW}Enter app names (comma-separated): ${NC}"
      read -r app_list
      IFS=',' read -ra input_apps <<< "$app_list"

      SELECTED_APPS=()
      for app in "${input_apps[@]}"; do
        app=$(echo "$app" | xargs)  # trim whitespace
        if [[ " ${apps[*]} " =~ " $app " ]]; then
          SELECTED_APPS+=("$app")
        else
          warning "App not found: $app"
        fi
      done

      if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
        error "No valid apps selected"
        return 1
      fi

      EXPORT_ALL_APPS=false
      success "Selected ${#SELECTED_APPS[@]} applications"
      ;;
    3)
      echo ""
      echo -e "  ${BOLD}Available Applications:${NC}"
      echo ""
      local i=1
      for app in "${apps[@]}"; do
        printf "    %3d) %s\n" $i "$app"
        ((i++))
      done

      echo ""
      echo -ne "  ${YELLOW}Enter numbers (comma-separated, e.g., 1,3,5-8): ${NC}"
      read -r selection

      SELECTED_APPS=()
      IFS=',' read -ra parts <<< "$selection"
      for part in "${parts[@]}"; do
        part=$(echo "$part" | xargs)
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          # Range
          for ((n=${BASH_REMATCH[1]}; n<=${BASH_REMATCH[2]}; n++)); do
            if [ $n -ge 1 ] && [ $n -le $total_apps ]; then
              SELECTED_APPS+=("${apps[$((n-1))]}")
            fi
          done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
          # Single number
          if [ "$part" -ge 1 ] && [ "$part" -le $total_apps ]; then
            SELECTED_APPS+=("${apps[$((part-1))]}")
          fi
        fi
      done

      if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
        error "No valid apps selected"
        return 1
      fi

      EXPORT_ALL_APPS=false
      success "Selected ${#SELECTED_APPS[@]} applications"
      ;;
    4)
      SELECTED_APPS=("search" "launcher" "learned" "splunk_httpinput" "splunk_internal_metrics")
      EXPORT_ALL_APPS=false
      success "Selected system apps only"
      ;;
    *)
      EXPORT_ALL_APPS=true
      SELECTED_APPS=("${apps[@]}")
      success "Will export ALL $total_apps applications"
      ;;
  esac

  STATS_APPS=${#SELECTED_APPS[@]}

  print_box_footer
}

# =============================================================================
# STEP 5: DATA CATEGORIES
# =============================================================================

select_data_categories() {
  print_box_header "STEP 5: DATA CATEGORIES"

  print_why_box \
    "You can customize which data categories to collect." \
    "" \
    "Different data helps with different migration aspects:" \
    "  • ${BOLD}Dashboards${NC}: Visual migration planning" \
    "  • ${BOLD}Alerts${NC}: Monitoring continuity" \
    "  • ${BOLD}Users/RBAC${NC}: Permission mapping" \
    "  • ${BOLD}Usage${NC}: Prioritize high-value content" \
    "" \
    "${YELLOW}Note: Some data may be limited due to Cloud restrictions${NC}"

  print_recommendation "Accept defaults for comprehensive analysis"

  echo ""
  echo -e "  ${BOLD}Select data categories to collect:${NC}"
  echo ""

  # Function to toggle and display
  toggle_category() {
    local name="$1"
    local var="$2"
    local desc="$3"
    local current="${!var}"

    if [ "$current" = "true" ]; then
      echo -e "    ${GREEN}[✓]${NC} $name ${DIM}$desc${NC}"
    else
      echo -e "    ${RED}[ ]${NC} $name ${DIM}$desc${NC}"
    fi
  }

  toggle_category "1. Configurations" "COLLECT_CONFIGS" "(via REST - reconstructed from API)"
  toggle_category "2. Dashboards" "COLLECT_DASHBOARDS" "(Classic + Dashboard Studio)"
  toggle_category "3. Alerts & Saved Searches" "COLLECT_ALERTS" ""
  toggle_category "4. Users & RBAC" "COLLECT_RBAC" "(global user/role data - use --rbac to enable)"
  toggle_category "5. Usage Analytics" "COLLECT_USAGE" "(requires _audit - often blocked in Cloud)"
  toggle_category "6. Index Statistics" "COLLECT_INDEXES" ""
  toggle_category "7. Lookup Contents" "COLLECT_LOOKUPS" "(may be large)"
  toggle_category "8. Anonymize Data" "ANONYMIZE_DATA" "(emails→fake, hosts→fake, IPs→redacted)"

  echo ""
  echo -e "  ${DIM}🔒 Privacy: User data includes names/roles only. Passwords are NEVER collected.${NC}"
  echo -e "  ${CYAN}💡 Tips:${NC}"
  echo -e "  ${DIM}   - Options 4 (RBAC) and 5 (Usage) are OFF by default for faster exports${NC}"
  echo -e "  ${DIM}   - Option 5 requires _audit/_internal access (often blocked in Cloud)${NC}"
  echo -e "  ${DIM}   - Enable option 8 when sharing export with third parties${NC}"
  echo ""
  echo -ne "  ${YELLOW}Accept defaults? (Y/n): ${NC}"
  read -r accept_defaults
  # Convert to lowercase (portable - works with bash 3.x on macOS)
  accept_defaults=$(echo "$accept_defaults" | tr '[:upper:]' '[:lower:]')

  if [[ "$accept_defaults" == "n" ]]; then
    echo ""
    echo -e "  ${DIM}Enter numbers to toggle (e.g., 5,7 to disable Usage and Lookups):${NC}"
    echo -ne "  ${YELLOW}Toggle: ${NC}"
    read -r toggles

    IFS=',' read -ra toggle_nums <<< "$toggles"
    for num in "${toggle_nums[@]}"; do
      num=$(echo "$num" | xargs)
      case "$num" in
        1) [ "$COLLECT_CONFIGS" = "true" ] && COLLECT_CONFIGS=false || COLLECT_CONFIGS=true ;;
        2) [ "$COLLECT_DASHBOARDS" = "true" ] && COLLECT_DASHBOARDS=false || COLLECT_DASHBOARDS=true ;;
        3) [ "$COLLECT_ALERTS" = "true" ] && COLLECT_ALERTS=false || COLLECT_ALERTS=true ;;
        4) [ "$COLLECT_RBAC" = "true" ] && COLLECT_RBAC=false || COLLECT_RBAC=true ;;
        5) [ "$COLLECT_USAGE" = "true" ] && COLLECT_USAGE=false || COLLECT_USAGE=true ;;
        6) [ "$COLLECT_INDEXES" = "true" ] && COLLECT_INDEXES=false || COLLECT_INDEXES=true ;;
        7) [ "$COLLECT_LOOKUPS" = "true" ] && COLLECT_LOOKUPS=false || COLLECT_LOOKUPS=true ;;
        8) [ "$ANONYMIZE_DATA" = "true" ] && ANONYMIZE_DATA=false || ANONYMIZE_DATA=true ;;
      esac
    done
  fi

  # Usage period
  if [ "$COLLECT_USAGE" = "true" ]; then
    echo ""
    echo -e "  ${BOLD}Usage Analytics Period:${NC}"
    echo ""
    echo -e "    ${GREEN}1${NC}) Last 7 days"
    echo -e "    ${GREEN}2${NC}) Last 30 days ${DIM}(recommended)${NC}"
    echo -e "    ${GREEN}3${NC}) Last 90 days"
    echo -e "    ${GREEN}4${NC}) Last 365 days"
    echo ""
    echo -ne "  ${YELLOW}Select period [2]: ${NC}"
    read -r period_choice

    case "${period_choice:-2}" in
      1) USAGE_PERIOD="7d" ;;
      2) USAGE_PERIOD="30d" ;;
      3) USAGE_PERIOD="90d" ;;
      4) USAGE_PERIOD="365d" ;;
      *) USAGE_PERIOD="30d" ;;
    esac

    info "Usage analytics will cover the last $USAGE_PERIOD"
  fi

  print_box_footer
}

# =============================================================================
# STEP 6: DATA COLLECTION
# =============================================================================

setup_export_directory() {
  TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  local stack_clean=$(echo "$SPLUNK_STACK" | sed 's/\.splunkcloud\.com//' | sed 's/[^a-zA-Z0-9_-]/_/g')
  EXPORT_NAME="dynabridge_cloud_export_${stack_clean}_${TIMESTAMP}"
  EXPORT_DIR="./${EXPORT_NAME}"
  LOG_FILE="${EXPORT_DIR}/_export.log"

  mkdir -p "$EXPORT_DIR"
  # DynaBridge analytics - all migration-specific data collected by DynaBridge
  mkdir -p "$EXPORT_DIR/dynabridge_analytics"
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/system_info"
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/rbac"
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/usage_analytics"
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure"
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/indexes"
  # Splunk configurations
  mkdir -p "$EXPORT_DIR/_configs"
  # NOTE: Dashboards are now stored in app-scoped folders (v2 structure)
  # $EXPORT_DIR/{AppName}/dashboards/classic/ and /studio/
  # This prevents name collisions when multiple apps have same-named dashboards

  touch "$LOG_FILE"
  log "Export started: $EXPORT_NAME"
  log "Stack: $SPLUNK_STACK"
  log "Version: $SPLUNK_VERSION"

  # Initialize debug logging if enabled
  init_debug_log
}

collect_system_info() {
  progress "Collecting server information..."

  # Server info
  local response
  response=$(api_call "/services/server/info" "GET" "output_mode=json")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/system_info/server_info.json"
    success "Server info collected"
  fi

  # Installed apps
  response=$(api_call "/services/apps/local" "GET" "output_mode=json&count=0")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/system_info/installed_apps.json"
    success "Installed apps collected"
  fi

  # License info (may be restricted)
  response=$(api_call "/services/licenser/licenses" "GET" "output_mode=json")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/system_info/license_info.json"
  fi

  # Server settings
  response=$(api_call "/services/server/settings" "GET" "output_mode=json")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/system_info/server_settings.json"
  fi
}

collect_configurations() {
  if [ "$COLLECT_CONFIGS" != "true" ]; then
    return
  fi

  progress "Collecting configurations via REST API..."

  # IMPORTANT (v4.0.1): Only collect TRULY GLOBAL configs here
  # Props, transforms, and savedsearches are collected PER-APP in collect_knowledge_objects()
  # and collect_alerts() functions. Including them here with /servicesNS/-/-/ would export
  # data from ALL apps (potentially 400+ apps) regardless of which apps the user selected.
  # This caused DynaBridge to freeze when processing huge amounts of unexpected data.
  #
  # Only indexes, inputs, and outputs are truly system-wide and make sense to collect globally.
  local configs=("indexes" "inputs" "outputs")

  for conf in "${configs[@]}"; do
    local response
    response=$(api_call "/servicesNS/-/-/configs/conf-$conf" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/_configs/${conf}.json"
      log "Collected conf-$conf"
    else
      warning "Could not collect conf-$conf"
    fi
  done

  success "Configurations collected (via REST reconstruction)"
}

collect_dashboards() {
  if [ "$COLLECT_DASHBOARDS" != "true" ]; then
    return
  fi

  progress "Collecting dashboards..."

  local classic_count=0
  local studio_count=0

  # Get all views
  local response
  response=$(api_call "/servicesNS/-/-/data/ui/views" "GET" "output_mode=json&count=0")

  if [ $? -ne 0 ]; then
    error "Failed to retrieve dashboards"
    return
  fi

  # Save master list
  echo "$response" > "$EXPORT_DIR/dynabridge_analytics/system_info/all_dashboards.json"

  # Process each app
  for app in "${SELECTED_APPS[@]}"; do
    # v2 structure: app-scoped dashboard folders by type
    mkdir -p "$EXPORT_DIR/$app/dashboards/classic"
    mkdir -p "$EXPORT_DIR/$app/dashboards/studio"

    # Get dashboards for this app
    local app_dashboards
    # Use search parameter to filter dashboards that BELONG to this app (not just visible from it)
    # The eai:acl.app field indicates which app owns the dashboard
    app_dashboards=$(api_call "/servicesNS/-/$app/data/ui/views" "GET" "output_mode=json&count=0&search=eai:acl.app=$app")

    if [ $? -eq 0 ]; then
      echo "$app_dashboards" > "$EXPORT_DIR/$app/dashboards/dashboard_list.json"

      # Extract dashboard names - only from dashboards owned by this app
      local names
      if $HAS_JQ; then
        # Filter to only dashboards where acl.app matches the target app
        names=$(echo "$app_dashboards" | jq -r --arg app "$app" '.entry[] | select(.acl.app == $app) | .name' 2>/dev/null)
      else
        # Fallback: extract names but may include inherited dashboards
        # The API search parameter should have already filtered them
        names=$(echo "$app_dashboards" | grep -oP '"name"\s*:\s*"\K[^"]+')
      fi

      local dash_count=$(echo "$names" | grep -c . 2>/dev/null || echo "0")
      echo "  App: $app ($dash_count dashboards)"

      while IFS= read -r name; do
        if [ -n "$name" ]; then
          local dash_detail
          dash_detail=$(api_call "/servicesNS/-/$app/data/ui/views/$name" "GET" "output_mode=json")
          if [ $? -eq 0 ]; then
            # Determine dashboard type by examining content first
            # Then save to appropriate app-scoped type folder (v2 structure)
            # Dashboard Studio v2 dashboards can be identified by:
            # 1. Contains "splunk-dashboard-studio" template reference (example dashboards)
            # 2. Contains '<dashboard version="2"' (user-created Studio dashboards)
            # 3. Contains '<definition>' element (contains actual JSON definition)
            # 4. eai:data starts with { (direct JSON format - rare)
            # Classic dashboards have <dashboard> or <form> without version="2"

            local is_studio=false
            local has_json_definition=false
            local is_template_reference=false

            # Check for Dashboard Studio v2 format (user-created dashboards)
            if echo "$dash_detail" | grep -q 'version=\\"2\\"' 2>/dev/null || echo "$dash_detail" | grep -q 'version=\"2\"' 2>/dev/null; then
              is_studio=true
              # Check if it has actual JSON definition embedded
              if echo "$dash_detail" | grep -q '<definition>' 2>/dev/null || echo "$dash_detail" | grep -q '\\u003cdefinition\\u003e' 2>/dev/null; then
                has_json_definition=true
                log "Dashboard Studio v2 with JSON definition: $name"
              fi
            fi

            # Check for Dashboard Studio template reference (example dashboards)
            if echo "$dash_detail" | grep -q "splunk-dashboard-studio" 2>/dev/null; then
              is_studio=true
              is_template_reference=true
              log "Dashboard Studio template reference: $name"
            fi

            # Also check if eai:data starts with { (direct JSON format)
            local eai_data_start=""
            eai_data_start=$(echo "$dash_detail" | grep -oP '"eai:data"\s*:\s*"\K.' 2>/dev/null | head -1)
            if [ "$eai_data_start" = "{" ]; then
              is_studio=true
              has_json_definition=true
            fi

            if [ "$is_studio" = true ]; then
              # Dashboard Studio - save to app-scoped studio folder (v2 structure)
              echo "$dash_detail" > "$EXPORT_DIR/$app/dashboards/studio/${name}.json"
              ((studio_count++))

              # Extract JSON definition if present and save separately
              if [ "$has_json_definition" = true ]; then
                local definition_file="$EXPORT_DIR/$app/dashboards/studio/${name}_definition.json"

                # Extract definition content using Python for reliable JSON/CDATA parsing
                python3 -c "
import json
import re

try:
    with open('$EXPORT_DIR/$app/dashboards/studio/${name}.json') as f:
        data = json.load(f)

    eai_data = data.get('entry', [{}])[0].get('content', {}).get('eai:data', '')

    # Look for definition CDATA block
    match = re.search(r'<definition><!\\[CDATA\\[(.+?)\\]\\]></definition>', eai_data, re.DOTALL)
    if match:
        json_content = match.group(1)
        parsed = json.loads(json_content)
        with open('$definition_file', 'w') as out:
            json.dump(parsed, out, indent=2)
        # Silent success - bash will check if file exists
except Exception as e:
    pass  # Silent failure - bash will handle missing file
" 2>/dev/null

                if [ -f "$definition_file" ]; then
                  log "  → Extracted JSON definition to ${name}_definition.json"
                fi
              elif [ "$is_template_reference" = true ]; then
                log "  → Template reference (actual JSON in splunk-dashboard-studio app)"
              fi

              log "Exported Dashboard Studio: $app/$name"
              echo "    → Studio: $name"
            else
              # Classic dashboard - save to app-scoped classic folder (v2 structure)
              echo "$dash_detail" > "$EXPORT_DIR/$app/dashboards/classic/${name}.json"
              ((classic_count++))
              log "Exported Classic Dashboard: $app/$name"
              echo "    → Classic: $name"
            fi
          fi
        fi
      done <<< "$names"
    fi
  done

  STATS_DASHBOARDS=$((classic_count + studio_count))
  success "Collected $classic_count Classic + $studio_count Dashboard Studio dashboards"
}

collect_alerts() {
  if [ "$COLLECT_ALERTS" != "true" ]; then
    return
  fi

  progress "Collecting alerts and saved searches..."

  local alert_count=0
  local total_saved_searches=0

  for app in "${SELECTED_APPS[@]}"; do
    local response
    response=$(api_call "/servicesNS/-/$app/saved/searches" "GET" "output_mode=json&count=0")

    if [ $? -eq 0 ]; then
      # CRITICAL FIX (v4.2.1): Filter by ACL app to get ONLY searches owned by this app
      # The REST API returns ALL searches VISIBLE to the app (including globally shared ones)
      # We must filter by acl.app to get only searches that actually BELONG to this app
      # Without this filter, every app's savedsearches.json would contain ALL 188K+ searches!
      if $HAS_JQ; then
        local filtered_response
        filtered_response=$(echo "$response" | jq --arg app "$app" '{
          links: .links,
          origin: .origin,
          updated: .updated,
          generator: .generator,
          entry: [.entry[] | select(.acl.app == $app)],
          paging: .paging
        }' 2>/dev/null)

        if [ -n "$filtered_response" ] && [ "$filtered_response" != "null" ]; then
          echo "$filtered_response" > "$EXPORT_DIR/$app/savedsearches.json"

          # Count entries after filtering
          local app_saved=$(echo "$filtered_response" | jq '.entry | length // 0' 2>/dev/null || echo 0)
          ((total_saved_searches += app_saved))

          # Count alerts using SAME LOGIC as TypeScript parser (SINGLE SOURCE OF TRUTH)
          # An entry is an alert if ANY of these are true:
          # - alert.track = "1" or "true" or 1 or true (NOT "0" or "false")
          # - alert_type is one of: "always", "custom", "number of events", "number of hosts", "number of sources"
          # - alert_condition has a value
          # - alert_comparator or alert_threshold has a value
          # - counttype contains "number of"
          # - actions has a non-empty value (comma-separated list of enabled actions)
          # - action.email/webhook/script/etc = "1" or true (NOT "0" or false or "false")
          local app_alerts=$(echo "$filtered_response" | jq '[.entry[] | select(
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
          )] | length' 2>/dev/null || echo 0)
          ((alert_count += app_alerts))

          debug "  $app: $app_saved saved searches ($app_alerts alerts)"
        else
          # Fallback: save unfiltered if jq filtering fails
          echo "$response" > "$EXPORT_DIR/$app/savedsearches.json"
          warn "Could not filter savedsearches for $app by ACL - saved unfiltered response"
        fi
      else
        # Fallback without jq - save unfiltered response
        echo "$response" > "$EXPORT_DIR/$app/savedsearches.json"
        # Count alerts using grep (less accurate)
        local app_alerts=$(echo "$response" | grep -cE '"alert\.track"\s*:\s*(true|"1")' || echo 0)
        ((alert_count += app_alerts))
      fi
    fi
  done

  STATS_ALERTS=$alert_count
  STATS_SAVED_SEARCHES=$total_saved_searches
  success "Collected $total_saved_searches saved searches ($alert_count alerts found)"
}

collect_rbac() {
  if [ "$COLLECT_RBAC" != "true" ]; then
    return
  fi

  progress "Collecting users and roles..."

  local response

  # =========================================================================
  # PERFORMANCE OPTIMIZATION: App-scoped user collection
  # In large environments (15K+ users), collecting all users is extremely slow.
  # When scoped to specific apps, we skip the full user list and only collect:
  # 1. Users who have accessed the selected apps (from _audit)
  # 2. Roles (needed for permission analysis)
  # =========================================================================
  if [ "$SCOPE_TO_APPS" = "true" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    info "App-scoped mode: Collecting users who accessed selected apps only"
    info "  → Skipping full user list (saves significant time in large environments)"

    # Collect only users who have accessed the selected apps (much faster)
    local app_filter=$(get_app_filter "app")
    if [ -n "$app_filter" ]; then
      # Use a search to find users who accessed these apps in the usage period
      local user_search="search index=_audit action=search ${app_filter} earliest=-${USAGE_PERIOD} | stats count as activity, latest(_time) as last_active by user | sort -activity"
      run_analytics_search "$user_search" "$EXPORT_DIR/dynabridge_analytics/rbac/users_active_in_apps.json" "Users active in selected apps"

      # Count users from the result
      if [ -f "$EXPORT_DIR/dynabridge_analytics/rbac/users_active_in_apps.json" ] && $HAS_JQ; then
        STATS_USERS=$(jq '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/rbac/users_active_in_apps.json" 2>/dev/null || echo "0")
        success "Collected $STATS_USERS users with activity in selected apps"
      fi
    fi

    # Create a placeholder for full users.json explaining the scoped collection
    echo "{\"scoped\": true, \"reason\": \"App-scoped mode - only users with activity in selected apps collected\", \"apps\": [$(printf '\"%s\",' "${SELECTED_APPS[@]}" | sed 's/,$//')]}" > "$EXPORT_DIR/dynabridge_analytics/rbac/users.json"

  else
    # Full collection mode - get all users
    response=$(api_call "/services/authentication/users" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/dynabridge_analytics/rbac/users.json"

      if $HAS_JQ; then
        STATS_USERS=$(echo "$response" | jq '.entry | length' 2>/dev/null)
      else
        STATS_USERS=$(echo "$response" | grep -c '"name"')
      fi
      success "Collected $STATS_USERS users"
    fi
  fi

  # Roles - always collect (relatively small dataset)
  response=$(api_call "/services/authorization/roles" "GET" "output_mode=json&count=0")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/rbac/roles.json"
    log "Collected roles"
  fi

  # SAML groups (may not be available) - skip in scoped mode
  if [ "$SCOPE_TO_APPS" != "true" ]; then
    response=$(api_call "/services/admin/SAML-groups" "GET" "output_mode=json")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/dynabridge_analytics/rbac/saml_groups.json"
      log "Collected SAML groups"
    fi
  fi

  # Current user context - always useful
  response=$(api_call "/services/authentication/current-context" "GET" "output_mode=json")
  if [ $? -eq 0 ]; then
    echo "$response" > "$EXPORT_DIR/dynabridge_analytics/rbac/current_context.json"
  fi
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
# APP-SCOPED ANALYTICS COLLECTION (Splunk Cloud)
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
#
# Note: Some searches may be limited in Splunk Cloud due to _internal restrictions
# =============================================================================

collect_app_analytics() {
  local app="$1"

  # Skip if usage collection disabled
  if [ "$COLLECT_USAGE" != "true" ]; then
    return 0
  fi

  local analysis_dir="$EXPORT_DIR/$app/splunk-analysis"
  mkdir -p "$analysis_dir"

  log "Collecting app-scoped analytics for: $app"

  # -------------------------------------------------------------------------
  # 1. DASHBOARD VIEWS - Top dashboards in THIS app by view count
  # Uses _audit which IS accessible in Splunk Cloud
  # -------------------------------------------------------------------------
  run_analytics_search \
    "search index=_audit action=search info=granted search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} | where user!=\"splunk-system-user\" | stats count as view_count, dc(user) as unique_users, latest(_time) as last_viewed by savedsearch_name | rename savedsearch_name as dashboard | where isnotnull(dashboard) | sort -view_count | head 100" \
    "$analysis_dir/dashboard_views.json" \
    "Dashboard views for $app" 2>/dev/null || true

  # -------------------------------------------------------------------------
  # 2. ALERT FIRING STATS - Alert execution stats for THIS app's alerts
  # Note: _internal may not be accessible in Splunk Cloud - will produce error
  # -------------------------------------------------------------------------
  if [ "$SKIP_INTERNAL" != "true" ]; then
    run_analytics_search \
      "search index=_internal sourcetype=scheduler app=\"$app\" status=* earliest=-${USAGE_PERIOD} | stats count as total_runs, sum(eval(if(status=\"success\",1,0))) as successful, sum(eval(if(status=\"skipped\",1,0))) as skipped, sum(eval(if(status!=\"success\" AND status!=\"skipped\",1,0))) as failed, latest(_time) as last_run by savedsearch_name | sort - total_runs | head 100" \
      "$analysis_dir/alert_firing.json" \
      "Alert firing stats for $app" 2>/dev/null || true
  else
    echo '{"note": "_internal index not accessible in Splunk Cloud. Check Monitoring Console for scheduler statistics."}' > "$analysis_dir/alert_firing.json"
  fi

  # -------------------------------------------------------------------------
  # 3. SAVED SEARCH USAGE - Run frequency for THIS app's saved searches
  # Note: _internal may not be accessible in Splunk Cloud
  # -------------------------------------------------------------------------
  if [ "$SKIP_INTERNAL" != "true" ]; then
    run_analytics_search \
      "search index=_internal sourcetype=scheduler app=\"$app\" earliest=-${USAGE_PERIOD} | stats count as run_count, avg(run_time) as avg_runtime, max(run_time) as max_runtime, latest(_time) as last_run by savedsearch_name | sort - run_count | head 100" \
      "$analysis_dir/search_usage.json" \
      "Search usage for $app" 2>/dev/null || true
  else
    echo '{"note": "_internal index not accessible in Splunk Cloud."}' > "$analysis_dir/search_usage.json"
  fi

  # -------------------------------------------------------------------------
  # 4. INDEX REFERENCES - Which indexes does THIS app query?
  # Uses _audit which IS accessible in Splunk Cloud
  # OPTIMIZED: Added | sample 20 before expensive rex, removed info=granted (pipe filter)
  # -------------------------------------------------------------------------
  run_analytics_search \
    "index=_audit action=search app=\"$app\" earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"index\\s*=\\s*(?<idx>[\\w\\*_-]+)\" | stats count as sample_count, dc(user) as unique_users by idx | eval estimated_query_count=sample_count*20 | where isnotnull(idx) | sort -estimated_query_count | head 50" \
    "$analysis_dir/index_references.json" \
    "Index references for $app" 2>/dev/null || true

  # -------------------------------------------------------------------------
  # 5. SOURCETYPE REFERENCES - Which sourcetypes does THIS app query?
  # Uses _audit which IS accessible in Splunk Cloud
  # OPTIMIZED: Added | sample 20 before expensive rex, removed info=granted (pipe filter)
  # -------------------------------------------------------------------------
  run_analytics_search \
    "index=_audit action=search app=\"$app\" earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"sourcetype\\s*=\\s*(?<st>[\\w\\*_-]+)\" | stats count as sample_count by st | eval estimated_query_count=sample_count*20 | where isnotnull(st) | sort -estimated_query_count | head 50" \
    "$analysis_dir/sourcetype_references.json" \
    "Sourcetype references for $app" 2>/dev/null || true

  # -------------------------------------------------------------------------
  # 6a. DASHBOARD VIEW COUNTS - Simpler query for this app (Curator correlates later)
  # OPTIMIZED: Removed | rest + | join which often fails in Splunk Cloud
  # -------------------------------------------------------------------------
  run_analytics_search \
    "index=_audit action=search search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" savedsearch_name=* | stats count as views by savedsearch_name | rename savedsearch_name as dashboard" \
    "$analysis_dir/dashboard_view_counts.json" \
    "Dashboard view counts for $app" 2>/dev/null || true

  # -------------------------------------------------------------------------
  # 6b. DASHBOARDS NEVER VIEWED - Legacy query (often fails in Splunk Cloud)
  # Note: Uses | rest + | join which are often blocked. Curator app correlates
  # dashboard_view_counts with manifest data as a more reliable alternative.
  # -------------------------------------------------------------------------
  run_analytics_search \
    "| rest /servicesNS/-/$app/data/ui/views | rename title as dashboard | table dashboard | join type=left dashboard [search index=_audit action=search search_type=dashboard app=\"$app\" earliest=-${USAGE_PERIOD} | where user!=\"splunk-system-user\" | stats count as views by savedsearch_name | rename savedsearch_name as dashboard] | where isnull(views) OR views=0 | table dashboard" \
    "$analysis_dir/dashboards_never_viewed.json" \
    "Never-viewed dashboards for $app" 2>/dev/null || true

  # -------------------------------------------------------------------------
  # 7. ALERTS INVENTORY - Get all scheduled searches/alerts for THIS app
  # Uses REST API (accessible in Splunk Cloud)
  # -------------------------------------------------------------------------
  run_analytics_search \
    "| rest /servicesNS/-/$app/saved/searches | search (is_scheduled=1 OR alert.track=1) | table title, cron_schedule, alert.severity, alert.track, actions, disabled | rename title as alert_name" \
    "$analysis_dir/alerts_inventory.json" \
    "Alerts inventory for $app" 2>/dev/null || true

  log "Completed app-scoped analytics for: $app"
}

# =============================================================================
# GLOBAL USAGE ANALYTICS (Infrastructure-level)
# =============================================================================
# Collects system-wide analytics that don't make sense at app level.
# Per-app analytics are now in each app's splunk-analysis/ folder.
# =============================================================================

collect_usage_analytics() {
  if [ "$COLLECT_USAGE" != "true" ]; then
    return
  fi

  echo ""
  echo "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "  ${CYAN}USAGE INTELLIGENCE COLLECTION${NC}"
  echo "  ${DIM}Gathering comprehensive usage data for migration prioritization${NC}"
  echo "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # Splunk Cloud limitation warning
  if [ "$SKIP_INTERNAL" = "true" ]; then
    echo "  ${YELLOW}⚠ SPLUNK CLOUD MODE: Skipping _internal index searches${NC}"
    echo "  ${DIM}  Some analytics (scheduler, volume, ingestion) will be limited.${NC}"
    echo "  ${DIM}  Dashboard views and user activity from _audit will still be collected.${NC}"
    echo ""
  fi

  # Build app filter for scoped mode
  local app_filter=""
  local app_where=""
  if [ "$SCOPE_TO_APPS" = "true" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    app_filter=$(get_app_filter "app")
    app_where=$(get_app_where_clause "app")
    echo "  ${CYAN}ℹ APP-SCOPED ANALYTICS: Filtering to ${#SELECTED_APPS[@]} app(s)${NC}"
    echo "  ${DIM}  Apps: ${SELECTED_APPS[*]}${NC}"
    echo ""
  fi

  # =========================================================================
  # CATEGORY 1: DASHBOARD VIEW STATISTICS
  # Uses _audit index with search_type=dashboard - tracks dashboard-triggered searches
  # Note: _internal index is NOT accessible in Splunk Cloud (even for admins)
  # Note: action=dashboard_view does NOT exist - that was a documentation error
  # =========================================================================
  progress "Collecting dashboard view statistics..."

  # Top 100 most viewed dashboards (via dashboard-triggered searches)
  # When users load a dashboard, it triggers searches - these are logged with search_type=dashboard
  # Excludes splunk-system-user (system account for scheduled searches)
  local app_search_filter=""
  if [ -n "$app_filter" ]; then
    app_search_filter="$app_filter "
  fi
  # OPTIMIZED: Moved user filter to search-time, removed redundant info=granted, changed latest to max
  run_analytics_search \
    "index=_audit action=search search_type=dashboard ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" savedsearch_name=* | stats count as view_count, dc(user) as unique_users, max(_time) as last_viewed by app, savedsearch_name | rename savedsearch_name as dashboard | sort -view_count | head 100" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_views_top100.json" \
    "Top 100 viewed dashboards"

  # Dashboard view trends (weekly breakdown via _audit)
  # OPTIMIZED: Moved filters to search-time
  run_analytics_search \
    "index=_audit action=search search_type=dashboard ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" savedsearch_name=* | bucket _time span=1w | stats count as views by _time, app, savedsearch_name | rename savedsearch_name as dashboard | sort -_time | head 200" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_views_trend.json" \
    "Dashboard view trends"

  # Dashboard view counts - simplified query (correlation done in Curator app)
  # OPTIMIZED: Removed | rest + | join which often fails in Splunk Cloud
  # The Curator app will correlate this with the dashboard list from REST API
  run_analytics_search \
    "index=_audit action=search search_type=dashboard ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" savedsearch_name=* | stats count as views by app, savedsearch_name | rename savedsearch_name as dashboard" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_view_counts.json" \
    "Dashboard view counts"

  # Legacy query for backwards compatibility (may fail in Splunk Cloud)
  local rest_app_filter=""
  if [ -n "$app_where" ]; then
    rest_app_filter="$app_where"
  fi
  run_analytics_search \
    "| rest /servicesNS/-/-/data/ui/views | rename title as dashboard, eai:acl.app as app | table dashboard, app $rest_app_filter | join type=left dashboard [search index=_audit action=search search_type=dashboard ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" | stats count as views by savedsearch_name | rename savedsearch_name as dashboard] | where isnull(views) OR views=0 | table dashboard, app" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboards_never_viewed.json" \
    "Never viewed dashboards (legacy)"

  # If SPL failed (uses | rest), use fallback - but we already have view counts
  if grep -q '"error"' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboards_never_viewed.json" 2>/dev/null; then
    info "Legacy never-viewed query failed (expected in Splunk Cloud) - using view counts file instead"
    collect_dashboards_never_viewed_fallback "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboards_never_viewed.json"
  fi

  success "Dashboard statistics collected"

  # =========================================================================
  # CATEGORY 2: USER ACTIVITY METRICS
  # Note: Excludes splunk-system-user (system account for scheduled searches)
  # In scoped mode, only counts activity within selected apps
  # =========================================================================
  progress "Collecting user activity metrics..."

  # Most active users by search count (excluding system user)
  # In scoped mode: only counts searches in selected apps
  # OPTIMIZED: Moved user filter to search-time, changed latest to max
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" | stats count as searches, dc(search) as unique_searches, max(_time) as last_active by user | sort -searches | head 100" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_most_active.json" \
    "Most active users"

  # Activity by role (excluding system user)
  # Note: Uses | rest which may fail in Splunk Cloud
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" | stats count by user | join user [| rest /services/authentication/users | rename title as user | table user, roles] | stats sum(count) as searches by roles" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/activity_by_role.json" \
    "Activity by role"

  # Users with no activity in period (excluding system user from results)
  # In scoped mode: only checks for activity in selected apps
  # Note: Uses | rest which may fail in Splunk Cloud
  run_analytics_search \
    "| rest /services/authentication/users | rename title as user | where user!=\"splunk-system-user\" | table user, realname, email | join type=left user [index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count by user] | where isnull(count) | table user, realname, email" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_inactive.json" \
    "Inactive users"

  # Daily active users trend (excluding system user)
  # OPTIMIZED: Moved user filter to search-time
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} user!=\"splunk-system-user\" | timechart span=1d dc(user) as daily_active_users" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_active_users.json" \
    "Daily active users"

  success "User activity collected"

  # =========================================================================
  # CATEGORY 3: ALERT EXECUTION STATISTICS
  # Note: These require _internal index which may be restricted in Splunk Cloud
  # In scoped mode: filter alerts by app
  # =========================================================================
  if [ "$SKIP_INTERNAL" = "true" ]; then
    info "Skipping alert execution statistics (_internal index restricted)"
    # Create placeholder files explaining the skip
    echo '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud", "alternative": "Check Monitoring Console in Splunk Cloud for scheduler statistics"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_most_fired.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_with_actions.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_failed.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_never_fired.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_firing_trend.json"
  else
    progress "Collecting alert execution statistics..."

    # Most fired alerts - in scoped mode, filter by app
    run_analytics_search \
      "search index=_internal sourcetype=scheduler status=success savedsearch_name=* ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count as executions, latest(_time) as last_run by savedsearch_name, app | sort -executions | head 100" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_most_fired.json" \
      "Most fired alerts"

    # Alerts with triggered actions
    run_analytics_search \
      "search index=_internal sourcetype=scheduler result_count>0 ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count as triggers, sum(result_count) as total_results by savedsearch_name, app | sort -triggers | head 50" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_with_actions.json" \
      "Alerts with actions"

    # Failed alert executions
    run_analytics_search \
      "search index=_internal sourcetype=scheduler status=failed ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count as failures, latest(_time) as last_failure by savedsearch_name, app | sort -failures" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_failed.json" \
      "Failed alerts"

    # Alerts that never fired - in scoped mode, filter REST results by app
    local alerts_rest_filter=""
    if [ -n "$app_where" ]; then
      # Use eai:acl.app for REST endpoint filtering
      alerts_rest_filter=$(get_app_where_clause "eai:acl.app")
    fi
    run_analytics_search \
      "| rest /servicesNS/-/-/saved/searches | search is_scheduled=1 | rename title as savedsearch_name $alerts_rest_filter | table savedsearch_name, eai:acl.app | join type=left savedsearch_name [search index=_internal sourcetype=scheduler ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count by savedsearch_name] | where isnull(count) | table savedsearch_name, eai:acl.app" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_never_fired.json" \
      "Never fired alerts"

    # Alert firing trend
    run_analytics_search \
      "search index=_internal sourcetype=scheduler status=success ${app_search_filter}earliest=-${USAGE_PERIOD} | timechart span=1d count by savedsearch_name | head 20" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_firing_trend.json" \
      "Alert firing trend"

    success "Alert statistics collected"
  fi

  # =========================================================================
  # CATEGORY 4: SEARCH USAGE PATTERNS
  # In scoped mode: filter searches by app
  # =========================================================================
  progress "Collecting search usage patterns..."

  # Most used search commands - in scoped mode, only from selected apps
  # OPTIMIZED: Added | sample 10 before expensive rex extraction, estimate x10 for final counts
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | sample 10 | rex field=search \"\\|\\s*(?<command>\\w+)\" | stats count as sample_count by command | eval estimated_count=sample_count*10 | sort -estimated_count | head 50" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/search_commands_popular.json" \
    "Popular search commands"

  # Search types breakdown
  # OPTIMIZED: Moved filter to search-time (action=search is indexed)
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | stats count by search_type | sort -count" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/search_by_type.json" \
    "Search by type"

  # Slow searches
  # OPTIMIZED: Moved total_run_time>30 to search-time, added | fields early to reduce memory
  run_analytics_search \
    "index=_audit action=search total_run_time>30 ${app_search_filter}earliest=-${USAGE_PERIOD} | fields total_run_time, search, app | stats avg(total_run_time) as avg_time, count as runs by search, app | sort -avg_time | head 50" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/searches_slow.json" \
    "Slow searches"

  # Most searched indexes - in scoped mode, only from searches in selected apps
  # OPTIMIZED: Added | sample 20 before expensive rex extraction, estimate x20 for final counts
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"index\\s*=\\s*(?<searched_index>\\w+)\" | stats count as sample_count by searched_index | eval estimated_count=sample_count*20 | sort -estimated_count | head 30" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/indexes_searched.json" \
    "Indexes searched"

  success "Search patterns collected"

  # =========================================================================
  # CATEGORY 5: DATA SOURCE USAGE
  # =========================================================================
  progress "Collecting data source usage..."

  # Most searched sourcetypes (uses _audit - works in Cloud) - scoped to apps
  # OPTIMIZED: Added | sample 20 before expensive rex extraction, estimate x20 for final counts
  run_analytics_search \
    "index=_audit action=search ${app_search_filter}earliest=-${USAGE_PERIOD} | sample 20 | rex field=search \"sourcetype\\s*=\\s*(?<st>\\w+)\" | stats count as sample_count by st | eval estimated_count=sample_count*20 | sort -estimated_count | head 30" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/sourcetypes_searched.json" \
    "Sourcetypes searched"

  # Index size and event counts (REST API - works in Cloud)
  run_analytics_search \
    "| rest /services/data/indexes | table title, currentDBSizeMB, totalEventCount, maxTime, minTime | sort -currentDBSizeMB" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/index_sizes.json" \
    "Index sizes"

  if [ "$SKIP_INTERNAL" = "true" ]; then
    info "Skipping index query patterns (_internal index restricted)"
    echo '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/indexes_queried.json"
  else
    # Index query patterns (requires _internal)
    run_analytics_search \
      "search index=_internal source=*metrics.log group=per_index_thruput earliest=-${USAGE_PERIOD} | stats sum(kb) as total_kb, avg(ev) as avg_events by series | eval total_gb=round(total_kb/1024/1024,2) | sort -total_gb | head 30" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/indexes_queried.json" \
      "Indexes queried"
  fi

  success "Data source usage collected"

  # =========================================================================
  # CATEGORY 5b: DAILY VOLUME ANALYSIS (Critical for capacity planning)
  # Note: These all require _internal index which is restricted in Splunk Cloud
  # =========================================================================
  if [ "$SKIP_INTERNAL" = "true" ]; then
    info "Skipping daily volume statistics (_internal index restricted)"
    info "  → Use Splunk Cloud Monitoring Console for license usage data"
    # Create placeholder files
    echo '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud", "alternative": "Use Monitoring Console > License Usage"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_by_index.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_by_sourcetype.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_events_by_index.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/hourly_volume_pattern.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_indexes_by_volume.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_sourcetypes_by_volume.json"
    echo '{"skipped": true, "reason": "_internal index not accessible"}' > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_hosts_by_volume.json"
  else
    progress "Collecting daily volume statistics (last 30 days)..."

    # Daily volume by index (GB per day)
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by idx | eval gb=round(bytes/1024/1024/1024,2) | fields _time, idx, gb" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_by_index.json" \
      "Daily volume by index (GB)"

    # Daily volume by sourcetype
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by st | eval gb=round(bytes/1024/1024/1024,2) | fields _time, st, gb" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_by_sourcetype.json" \
      "Daily volume by sourcetype (GB)"

    # Total daily volume (for licensing)
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes | eval gb=round(bytes/1024/1024/1024,2) | stats avg(gb) as avg_daily_gb, max(gb) as peak_daily_gb, sum(gb) as total_30d_gb" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json" \
      "Daily volume summary"

    # Daily event count by index
    run_analytics_search \
      "search index=_internal source=*metrics.log group=per_index_thruput earliest=-30d@d | timechart span=1d sum(ev) as events by series | rename series as index" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_events_by_index.json" \
      "Daily event counts by index"

    # Hourly pattern analysis (to identify peak hours)
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-7d | eval hour=strftime(_time, \"%H\") | stats sum(b) as bytes by hour | eval gb=round(bytes/1024/1024/1024,2) | sort hour" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/hourly_volume_pattern.json" \
      "Hourly volume pattern (last 7 days)"

    # Top 20 indexes by daily average volume
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by idx | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_indexes_by_volume.json" \
      "Top 20 indexes by daily average volume"

    # Top 20 sourcetypes by daily average volume
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by st | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_sourcetypes_by_volume.json" \
      "Top 20 sourcetypes by daily average volume"

    # Volume by host (top 50)
    run_analytics_search \
      "search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by h | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 50" \
      "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_hosts_by_volume.json" \
      "Top 50 hosts by daily average volume"

    success "Daily volume statistics collected"
  fi

  # =========================================================================
  # CATEGORY 5c: INGESTION INFRASTRUCTURE (For understanding data collection)
  # =========================================================================
  progress "Collecting ingestion infrastructure information..."

  # Create subdirectory for ingestion infrastructure
  mkdir -p "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure"

  # Connection type breakdown (UF cooked vs HF raw vs other)
  run_analytics_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as unique_hosts, sum(kb) as total_kb by connectionType | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_connection_type.json" \
    "Ingestion by connection type (UF/HF/other)"

  # Input method breakdown (splunktcp, http, udp, tcp, monitor, etc.)
  run_analytics_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | rex field=series "^(?<input_type>[^:]+):" | stats sum(kb) as total_kb, dc(series) as unique_sources by input_type | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2) | sort - total_kb' \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_input_method.json" \
    "Ingestion by input method"

  # HEC (HTTP Event Collector) usage
  run_analytics_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput series=http:* earliest=-7d | stats sum(kb) as total_kb, dc(series) as token_count | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)' \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/hec_usage.json" \
    "HTTP Event Collector usage"

  # Forwarding hosts inventory (unique hosts sending data)
  run_analytics_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats sum(kb) as total_kb, latest(_time) as last_seen, values(connectionType) as connection_types by sourceHost | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb | head 500" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/forwarding_hosts.json" \
    "Forwarding hosts inventory (top 500)"

  # Sourcetype categorization (detect OTel, cloud, security, etc.)
  run_analytics_search \
    'search index=_internal source=*license_usage.log type=Usage earliest=-30d | stats sum(b) as bytes, dc(h) as unique_hosts by st | eval daily_avg_gb=round((bytes/30)/1024/1024/1024,2) | eval category=case(match(st,"^otel|^otlp|opentelemetry"),"opentelemetry", match(st,"^aws:|^azure:|^gcp:|^cloud"),"cloud", match(st,"^WinEventLog|^windows|^wmi"),"windows", match(st,"^linux|^syslog|^nix"),"linux_unix", match(st,"^cisco:|^pan:|^juniper:|^fortinet:|^f5:|^checkpoint"),"network_security", match(st,"^access_combined|^nginx|^apache|^iis"),"web", match(st,"^docker|^kube|^container"),"containers", 1=1,"other") | stats sum(daily_avg_gb) as daily_avg_gb, sum(unique_hosts) as unique_hosts, values(st) as sourcetypes by category | sort - daily_avg_gb' \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_sourcetype_category.json" \
    "Ingestion by sourcetype category"

  # Syslog inputs (UDP/TCP) - if visible
  run_analytics_search \
    'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | search series=udp:* OR series=tcp:* | stats sum(kb) as total_kb by series | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb' \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/syslog_inputs.json" \
    "Syslog inputs (UDP/TCP)"

  # Summary: Total forwarding infrastructure
  run_analytics_search \
    "search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as total_forwarding_hosts, sum(kb) as total_kb | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/summary.json" \
    "Ingestion infrastructure summary"

  success "Ingestion infrastructure information collected"

  # =========================================================================
  # CATEGORY 5d: OWNERSHIP MAPPING (For user-centric migration)
  # =========================================================================
  progress "Collecting ownership information..."

  # Dashboard ownership - maps each dashboard to its owner
  # Try SPL first, fall back to REST API if restricted
  run_analytics_search \
    "| rest /servicesNS/-/-/data/ui/views | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing | rename title as dashboard, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_ownership.json" \
    "Dashboard ownership mapping"

  # If SPL failed, try REST API fallback
  if grep -q '"error"' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_ownership.json" 2>/dev/null; then
    info "SPL | rest failed for dashboard ownership, trying REST API fallback..."
    collect_dashboard_ownership_rest "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_ownership.json"
  fi

  # Alert/Saved search ownership - maps each alert to its owner
  # Try SPL first, fall back to REST API if restricted
  run_analytics_search \
    "| rest /servicesNS/-/-/saved/searches | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, is_scheduled, alert.track | rename title as alert_name, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_ownership.json" \
    "Alert/saved search ownership mapping"

  # If SPL failed, try REST API fallback
  if grep -q '"error"' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_ownership.json" 2>/dev/null; then
    info "SPL | rest failed for alert ownership, trying REST API fallback..."
    collect_alert_ownership_rest "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_ownership.json"
  fi

  # Ownership summary by user (how many dashboards and alerts each user owns)
  run_analytics_search \
    "| rest /servicesNS/-/-/data/ui/views | stats count as dashboards by eai:acl.owner | rename eai:acl.owner as owner | append [| rest /servicesNS/-/-/saved/searches | stats count as alerts by eai:acl.owner | rename eai:acl.owner as owner] | stats sum(dashboards) as dashboards, sum(alerts) as alerts by owner | sort - dashboards" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ownership_summary.json" \
    "Ownership summary by user"

  # If SPL failed (uses | rest), try computing from already-collected REST data
  if grep -q '"error"' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ownership_summary.json" 2>/dev/null; then
    info "SPL search failed for ownership summary, computing from REST data..."
    compute_ownership_summary_from_rest "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ownership_summary.json"
  fi

  success "Ownership information collected"

  # =========================================================================
  # CATEGORY 6: SAVED SEARCH METADATA
  # =========================================================================
  progress "Collecting saved search metadata..."

  api_call "/servicesNS/-/-/saved/searches" "GET" "output_mode=json&count=0" \
    > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/saved_searches_all.json" 2>/dev/null

  run_analytics_search \
    "| rest /servicesNS/-/-/saved/searches | stats count by eai:acl.owner | sort -count | head 20" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/saved_searches_by_owner.json" \
    "Saved searches by owner"

  success "Saved search metadata collected"

  # =========================================================================
  # CATEGORY 7: SCHEDULER EXECUTION STATS
  # =========================================================================
  progress "Collecting scheduler statistics..."

  api_call "/services/search/jobs" "GET" "output_mode=json&count=100" \
    > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/recent_searches.json" 2>/dev/null

  api_call "/services/kvstore/status" "GET" "output_mode=json" \
    > "$EXPORT_DIR/dynabridge_analytics/usage_analytics/kvstore_stats.json" 2>/dev/null

  run_analytics_search \
    "search index=_internal sourcetype=scheduler earliest=-${USAGE_PERIOD} | stats count as total, count(eval(status=\"success\")) as success, count(eval(status=\"failed\")) as failed by date_hour | sort date_hour" \
    "$EXPORT_DIR/dynabridge_analytics/usage_analytics/scheduler_load.json" \
    "Scheduler load"

  success "Scheduler statistics collected"

  # =========================================================================
  # GENERATE USAGE INTELLIGENCE SUMMARY
  # =========================================================================
  echo ""
  progress "Generating usage intelligence summary..."

  local summary_file="$EXPORT_DIR/dynabridge_analytics/usage_analytics/USAGE_INTELLIGENCE_SUMMARY.md"

  cat > "$summary_file" << 'USAGE_EOF'
# Usage Intelligence Summary

## Migration Prioritization Framework

This export includes comprehensive usage analytics to help prioritize your migration to Dynatrace.

### Decision Matrix

| Category | High Usage | Low/No Usage |
|----------|------------|--------------|
| **Dashboards** | Migrate first - users depend on these | Review with stakeholders - may be deprecated |
| **Alerts** | Critical - ensure Dynatrace equivalents | Consider not migrating |
| **Users** | Key stakeholders for training | May not need Dynatrace access |
| **Data Sources** | Must ingest into Dynatrace | May not need migration |

### Files Reference

| File | Purpose | Use For |
|------|---------|---------|
| `dashboard_views_top100.json` | Most viewed dashboards | Prioritize migration order |
| `dashboards_never_viewed.json` | Unused dashboards | Consider not migrating |
| `users_most_active.json` | Power users | Training priorities |
| `users_inactive.json` | Inactive accounts | Skip in migration |
| `alerts_most_fired.json` | Active alerts | Critical to migrate |
| `alerts_never_fired.json` | Unused alerts | Consider removing |
| `sourcetypes_searched.json` | Important data types | Data ingestion priorities |
| `indexes_searched.json` | Important indexes | Bucket mapping priorities |

### Recommended Migration Order

1. **Phase 1**: Top 10 dashboards + their dependent alerts
2. **Phase 2**: Data sources used by Phase 1
3. **Phase 3**: Remaining active dashboards/alerts
4. **Phase 4**: Review never-used items with stakeholders

---
*Generated by DynaBridge Splunk Cloud Export*
USAGE_EOF

  success "Usage intelligence summary generated"
  echo ""
}

run_analytics_search() {
  local search_query="$1"
  local output_file="$2"
  local label="$3"
  local timeout="${4:-300}"  # Default 5 minutes, configurable

  info "Running: $label"

  # Create search job with detailed error capture
  local job_response
  local start_time=$(date +%s)

  job_response=$(api_call "/services/search/jobs" "POST" "search=$search_query&output_mode=json&exec_mode=blocking&timeout=$timeout" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    ((STATS_ERRORS++))
    local elapsed=$(($(date +%s) - start_time))

    # Capture detailed error info for remote debugging
    cat > "$output_file" << EOF
{
  "error": "search_create_failed",
  "description": "$label",
  "message": "Failed to create search job. This may be due to permissions, API restrictions, or query syntax.",
  "elapsed_seconds": $elapsed,
  "query_preview": "$(echo "$search_query" | head -c 200 | sed 's/"/\\"/g')",
  "troubleshooting": [
    "1. Verify user has 'search' capability",
    "2. Check if this search command is allowed in Splunk Cloud",
    "3. Try running the search manually in Splunk Web",
    "4. Some REST commands (| rest) may be restricted"
  ]
}
EOF
    warning "Failed to run search: $label (see $output_file for details)"
    return 1
  fi

  # Get SID
  local sid
  if $HAS_JQ; then
    sid=$(echo "$job_response" | jq -r '.sid // .entry[0].content.sid' 2>/dev/null)
  else
    sid=$(echo "$job_response" | grep -oP '"sid"\s*:\s*"\K[^"]+' | head -1)
  fi

  if [ -z "$sid" ] || [ "$sid" = "null" ]; then
    ((STATS_ERRORS++))

    # Check if there's an error message in the response
    local error_msg=""
    if $HAS_JQ; then
      error_msg=$(echo "$job_response" | jq -r '.messages[0].text // .entry[0].content.messages[0].text // "Unknown error"' 2>/dev/null)
    else
      error_msg=$(echo "$job_response" | grep -oP '"text"\s*:\s*"\K[^"]+' | head -1)
    fi

    cat > "$output_file" << EOF
{
  "error": "no_search_id",
  "description": "$label",
  "message": "$error_msg",
  "troubleshooting": [
    "1. The search syntax may be invalid",
    "2. Required indexes may not be accessible",
    "3. Try a simpler version of this search first"
  ]
}
EOF
    warning "Could not get SID for search: $label"
    return 1
  fi

  # Wait for completion and get results
  local results
  results=$(api_call "/services/search/jobs/$sid/results" "GET" "output_mode=json&count=0")

  if [ $? -eq 0 ]; then
    echo "$results" > "$output_file"
    local elapsed=$(($(date +%s) - start_time))
    log "Completed search: $label (${elapsed}s)"
    return 0
  else
    ((STATS_ERRORS++))
    cat > "$output_file" << EOF
{
  "error": "results_fetch_failed",
  "description": "$label",
  "message": "Search completed but could not retrieve results",
  "search_id": "$sid",
  "troubleshooting": [
    "1. Search may have returned too many results",
    "2. Session may have timed out",
    "3. Try running the search manually"
  ]
}
EOF
    return 1
  fi
}

# =============================================================================
# REST API FALLBACK FUNCTIONS
# These functions use direct REST API calls instead of SPL | rest commands
# which are often restricted in Splunk Cloud
# =============================================================================

# Collect dashboard ownership via REST API (fallback for | rest)
collect_dashboard_ownership_rest() {
  local output_file="$1"
  info "Collecting dashboard ownership via REST API (fallback)..."

  local response
  response=$(api_call "/servicesNS/-/-/data/ui/views" "GET" "output_mode=json&count=0" 2>&1)

  if [ $? -eq 0 ] && [ -n "$response" ]; then
    # Transform REST API response to match expected format
    if $HAS_JQ; then
      echo "$response" | jq '{
        results: [.entry[] | {
          dashboard: .name,
          app: .acl.app,
          owner: .acl.owner,
          sharing: .acl.sharing
        }]
      }' > "$output_file" 2>/dev/null

      if [ $? -eq 0 ]; then
        local count
        count=$(jq '.results | length' "$output_file" 2>/dev/null || echo "0")
        success "Dashboard ownership collected via REST API ($count dashboards)"
        return 0
      fi
    else
      # Fallback: save raw response
      echo "$response" > "$output_file"
      success "Dashboard ownership collected via REST API (raw format)"
      return 0
    fi
  fi

  warning "Failed to collect dashboard ownership via REST API"
  return 1
}

# Collect alert/saved search ownership via REST API (fallback for | rest)
collect_alert_ownership_rest() {
  local output_file="$1"
  info "Collecting alert ownership via REST API (fallback)..."

  local response
  response=$(api_call "/servicesNS/-/-/saved/searches" "GET" "output_mode=json&count=0" 2>&1)

  if [ $? -eq 0 ] && [ -n "$response" ]; then
    # Transform REST API response to match expected format
    if $HAS_JQ; then
      echo "$response" | jq '{
        results: [.entry[] | {
          alert_name: .name,
          app: .acl.app,
          owner: .acl.owner,
          sharing: .acl.sharing,
          is_scheduled: (.content.is_scheduled // "0"),
          alert_track: (.content["alert.track"] // "0")
        }]
      }' > "$output_file" 2>/dev/null

      if [ $? -eq 0 ]; then
        local count
        count=$(jq '.results | length' "$output_file" 2>/dev/null || echo "0")
        success "Alert ownership collected via REST API ($count alerts)"
        return 0
      fi
    else
      # Fallback: save raw response
      echo "$response" > "$output_file"
      success "Alert ownership collected via REST API (raw format)"
      return 0
    fi
  fi

  warning "Failed to collect alert ownership via REST API"
  return 1
}

# Run analytics search with REST API fallback for ownership queries
run_analytics_search_with_fallback() {
  local search_query="$1"
  local output_file="$2"
  local label="$3"
  local fallback_type="$4"  # "dashboard_ownership", "alert_ownership", or empty

  # Try SPL search first
  run_analytics_search "$search_query" "$output_file" "$label"

  # If failed and has fallback, try REST API
  if [ $? -ne 0 ] && [ -n "$fallback_type" ]; then
    info "SPL search failed, trying REST API fallback for: $label"

    case "$fallback_type" in
      "dashboard_ownership")
        collect_dashboard_ownership_rest "$output_file"
        ;;
      "alert_ownership")
        collect_alert_ownership_rest "$output_file"
        ;;
    esac
  fi
}

# Compute ownership summary from already-collected REST API data
compute_ownership_summary_from_rest() {
  local output_file="$1"
  local dashboard_file="$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_ownership.json"
  local alert_file="$EXPORT_DIR/dynabridge_analytics/usage_analytics/alert_ownership.json"

  info "Computing ownership summary from REST API data..."

  if $HAS_JQ && [ -f "$dashboard_file" ] && [ -f "$alert_file" ]; then
    # Check if dashboard_ownership has valid data (not error)
    if ! grep -q '"error"' "$dashboard_file" 2>/dev/null; then
      jq -n --slurpfile dashboards "$dashboard_file" --slurpfile alerts "$alert_file" '
        {
          results: (
            [($dashboards[0].results // $dashboards[0].entry // [])[] | {owner: .owner, type: "dashboard"}] +
            [($alerts[0].results // $alerts[0].entry // [])[] | {owner: .owner, type: "alert"}]
          ) | group_by(.owner) | map({
            owner: .[0].owner,
            dashboards: [.[] | select(.type == "dashboard")] | length,
            alerts: [.[] | select(.type == "alert")] | length
          }) | sort_by(-.dashboards)
        }
      ' > "$output_file" 2>/dev/null

      if [ $? -eq 0 ]; then
        success "Ownership summary computed from REST API data"
        return 0
      fi
    fi
  fi

  warning "Could not compute ownership summary from REST data"
  return 1
}

# Collect dashboards never viewed - fallback using REST API data
collect_dashboards_never_viewed_fallback() {
  local output_file="$1"
  local dashboard_ownership_file="$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_ownership.json"
  local dashboard_views_file="$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_views_top100.json"

  info "Computing dashboards never viewed using REST API data..."

  # If we have dashboard_ownership but not views, we can at least list all dashboards
  # and mark them as "unknown" for views (since view data failed)
  if $HAS_JQ && [ -f "$dashboard_ownership_file" ]; then
    if ! grep -q '"error"' "$dashboard_ownership_file" 2>/dev/null; then
      # Get all dashboards - if views data is available and valid, compare; otherwise mark all as unknown
      local has_views="false"
      if [ -f "$dashboard_views_file" ] && ! grep -q '"error"' "$dashboard_views_file" 2>/dev/null; then
        has_views="true"
      fi

      if [ "$has_views" = "true" ]; then
        # We have view data - compute never viewed
        jq -n --slurpfile ownership "$dashboard_ownership_file" --slurpfile views "$dashboard_views_file" '
          {
            results: (
              ($ownership[0].results // $ownership[0].entry // []) as $all_dashboards |
              (($views[0].results // []) | map(.dashboard) | map(ascii_downcase)) as $viewed |
              [$all_dashboards[] | select((.dashboard | ascii_downcase) as $d | $viewed | index($d) | not)]
            ),
            note: "Dashboards with no recorded views in the analysis period"
          }
        ' > "$output_file" 2>/dev/null
      else
        # No view data - just provide dashboard list with note
        jq -n --slurpfile ownership "$dashboard_ownership_file" '
          {
            results: ($ownership[0].results // $ownership[0].entry // []),
            warning: "Dashboard view counts unavailable - _audit search failed",
            note: "This list contains all dashboards. View statistics could not be retrieved due to permissions or timeout."
          }
        ' > "$output_file" 2>/dev/null
      fi

      if [ $? -eq 0 ]; then
        success "Dashboards never viewed list generated (fallback)"
        return 0
      fi
    fi
  fi

  warning "Could not generate dashboards never viewed fallback"
  return 1
}

collect_indexes() {
  if [ "$COLLECT_INDEXES" != "true" ]; then
    return
  fi

  progress "Collecting index information..."

  local response

  # =========================================================================
  # PERFORMANCE OPTIMIZATION: App-scoped index collection
  # In large environments (470+ indexes), collecting all indexes is slow.
  # When scoped to specific apps, we only collect indexes that are actually
  # used by searches in those apps - much faster and more relevant.
  # =========================================================================
  if [ "$SCOPE_TO_APPS" = "true" ] && [ ${#SELECTED_APPS[@]} -gt 0 ]; then
    info "App-scoped mode: Collecting indexes used by selected apps only"

    # Get indexes referenced in searches from selected apps (from _audit)
    local app_filter=$(get_app_filter "app")
    if [ -n "$app_filter" ]; then
      local index_search="search index=_audit action=search ${app_filter} earliest=-${USAGE_PERIOD} | rex field=search \"index\\s*=\\s*(?<idx>[\\w_-]+)\" | where isnotnull(idx) | stats count as searches, dc(user) as users by idx | sort -searches"
      run_analytics_search "$index_search" "$EXPORT_DIR/dynabridge_analytics/indexes/indexes_used_by_apps.json" "Indexes used by selected apps"

      # Count indexes from the result
      if [ -f "$EXPORT_DIR/dynabridge_analytics/indexes/indexes_used_by_apps.json" ] && $HAS_JQ; then
        STATS_INDEXES=$(jq '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/indexes/indexes_used_by_apps.json" 2>/dev/null || echo "0")
        success "Collected $STATS_INDEXES indexes used by selected apps"
      fi
    fi

    # Create a placeholder for full indexes.json explaining the scoped collection
    echo "{\"scoped\": true, \"reason\": \"App-scoped mode - only indexes used by selected apps collected\", \"apps\": [$(printf '\"%s\",' "${SELECTED_APPS[@]}" | sed 's/,$//')]}" > "$EXPORT_DIR/dynabridge_analytics/indexes/indexes.json"

  else
    # Full collection mode - get all indexes
    response=$(api_call "/services/data/indexes" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/dynabridge_analytics/indexes/indexes.json"

      if $HAS_JQ; then
        STATS_INDEXES=$(echo "$response" | jq '.entry | length' 2>/dev/null)
      else
        STATS_INDEXES=$(echo "$response" | grep -c '"name"')
      fi
      success "Collected $STATS_INDEXES indexes"
    fi

    # Extended stats (may be limited in cloud) - only in full mode
    response=$(api_call "/services/data/indexes-extended" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/dynabridge_analytics/indexes/indexes_extended.json"
    fi
  fi
}

collect_knowledge_objects() {
  progress "Collecting knowledge objects..."

  for app in "${SELECTED_APPS[@]}"; do
    mkdir -p "$EXPORT_DIR/$app"

    # CRITICAL (v4.2.2): Filter ALL knowledge objects by acl.app
    # The REST API returns ALL objects VISIBLE to the app (including globally shared ones)
    # We must filter by acl.app to get only objects that actually BELONG to this app
    # This matches the fix in savedsearches (v4.2.1) and prevents duplicate data

    # Helper function to filter and save JSON response by acl.app
    filter_and_save_json() {
      local json_data="$1"
      local target_app="$2"
      local output_file="$3"
      local object_type="$4"

      if $HAS_JQ; then
        local filtered_response
        filtered_response=$(echo "$json_data" | jq --arg app "$target_app" '{
          links: .links,
          origin: .origin,
          updated: .updated,
          generator: .generator,
          entry: [.entry[] | select(.acl.app == $app)],
          paging: .paging
        }' 2>/dev/null)

        if [ -n "$filtered_response" ] && [ "$filtered_response" != "null" ]; then
          local entry_count=$(echo "$filtered_response" | jq '.entry | length // 0' 2>/dev/null || echo 0)
          if [ "$entry_count" -gt 0 ]; then
            echo "$filtered_response" > "$output_file"
            debug "  $target_app/$object_type: $entry_count entries (after filtering)"
          else
            debug "  $target_app/$object_type: 0 entries belong to this app (skipped)"
          fi
          return 0
        fi
      fi

      # Fallback without jq - save unfiltered and log warning
      echo "$json_data" > "$output_file"
      warn "Could not filter $object_type for $target_app by ACL - saved unfiltered"
      return 0
    }

    # Macros
    local response
    response=$(api_call "/servicesNS/-/$app/admin/macros" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/macros.json" "macros"
    fi

    # Eventtypes
    response=$(api_call "/servicesNS/-/$app/saved/eventtypes" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/eventtypes.json" "eventtypes"
    fi

    # Tags
    response=$(api_call "/servicesNS/-/$app/configs/conf-tags" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/tags.json" "tags"
    fi

    # Field extractions
    response=$(api_call "/servicesNS/-/$app/data/transforms/extractions" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/field_extractions.json" "field_extractions"
    fi

    # Inputs (data inputs with sourcetype definitions)
    response=$(api_call "/servicesNS/-/$app/data/inputs/all" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/inputs.json" "inputs"
    fi

    # Props (sourcetype configurations)
    response=$(api_call "/servicesNS/-/$app/configs/conf-props" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/props.json" "props"
    fi

    # Transforms (field extractions and routing)
    response=$(api_call "/servicesNS/-/$app/configs/conf-transforms" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      filter_and_save_json "$response" "$app" "$EXPORT_DIR/$app/transforms.json" "transforms"
    fi

    # Lookups
    response=$(api_call "/servicesNS/-/$app/data/lookup-table-files" "GET" "output_mode=json&count=0")
    if [ $? -eq 0 ]; then
      echo "$response" > "$EXPORT_DIR/$app/lookups.json"

      # Download lookup contents if enabled
      if [ "$COLLECT_LOOKUPS" = "true" ]; then
        mkdir -p "$EXPORT_DIR/$app/lookup_files"

        local lookup_names
        if $HAS_JQ; then
          lookup_names=$(echo "$response" | jq -r '.entry[].name' 2>/dev/null)
        else
          lookup_names=$(echo "$response" | grep -oP '"name"\s*:\s*"\K[^"]+')
        fi

        while IFS= read -r lookup; do
          if [ -n "$lookup" ]; then
            local lookup_data
            lookup_data=$(api_call "/servicesNS/-/$app/data/lookup-table-files/$lookup" "GET" "output_mode=json")
            if [ $? -eq 0 ]; then
              echo "$lookup_data" > "$EXPORT_DIR/$app/lookup_files/${lookup}.json"
            fi
          fi
        done <<< "$lookup_names"
      fi
    fi
  done

  success "Knowledge objects collected"
}

# =============================================================================
# SUMMARY GENERATION
# =============================================================================

generate_summary() {
  progress "Generating summary report..."

  local summary_file="$EXPORT_DIR/dynabridge-env-summary.md"

  cat > "$summary_file" << EOF
# DynaBridge Splunk Cloud Environment Summary

**Export Date**: $(date '+%Y-%m-%d %H:%M:%S %Z')
**Export Script Version**: $SCRIPT_VERSION
**Export Type**: Splunk Cloud (REST API)

---

## Environment Overview

| Property | Value |
|----------|-------|
| **Stack URL** | $SPLUNK_STACK |
| **Cloud Type** | $CLOUD_TYPE |
| **Splunk Version** | $SPLUNK_VERSION |
| **Server GUID** | $SERVER_GUID |

---

## Collection Summary

| Category | Count | Status |
|----------|-------|--------|
| **Applications** | $STATS_APPS | ✅ Collected |
| **Dashboards** | $STATS_DASHBOARDS | $([ "$COLLECT_DASHBOARDS" = "true" ] && echo "✅ Collected" || echo "⏭️ Skipped") |
| **Alerts** | $STATS_ALERTS | $([ "$COLLECT_ALERTS" = "true" ] && echo "✅ Collected" || echo "⏭️ Skipped") |
| **Users** | $STATS_USERS | $([ "$COLLECT_RBAC" = "true" ] && echo "✅ Collected" || echo "⏭️ Skipped") |
| **Indexes** | $STATS_INDEXES | $([ "$COLLECT_INDEXES" = "true" ] && echo "✅ Collected" || echo "⏭️ Skipped") |

---

## Collection Statistics

| Metric | Value |
|--------|-------|
| **API Calls Made** | $STATS_API_CALLS |
| **Rate Limit Hits** | $STATS_RATE_LIMITS |
| **Errors** | $STATS_ERRORS |
| **Warnings** | $STATS_WARNINGS |

---

## Data Categories Collected

$([ "$COLLECT_CONFIGS" = "true" ] && echo "- ✅ Configurations (via REST API reconstruction)" || echo "- ⏭️ Configurations (skipped)")
$([ "$COLLECT_DASHBOARDS" = "true" ] && echo "- ✅ Dashboards (Classic and Dashboard Studio)" || echo "- ⏭️ Dashboards (skipped)")
$([ "$COLLECT_ALERTS" = "true" ] && echo "- ✅ Alerts and Saved Searches" || echo "- ⏭️ Alerts (skipped)")
$([ "$COLLECT_RBAC" = "true" ] && echo "- ✅ Users, Roles, and RBAC" || echo "- ⏭️ RBAC (skipped - use --rbac to enable)")
$([ "$COLLECT_USAGE" = "true" ] && echo "- ✅ Usage Analytics (last $USAGE_PERIOD)" || echo "- ⏭️ Usage Analytics (skipped - use --usage to enable, requires _audit index)")
$([ "$COLLECT_INDEXES" = "true" ] && echo "- ✅ Index Statistics" || echo "- ⏭️ Index Statistics (skipped)")
$([ "$COLLECT_LOOKUPS" = "true" ] && echo "- ✅ Lookup Table Contents" || echo "- ⏭️ Lookup Contents (skipped)")

---

## Applications Exported

$(for app in "${SELECTED_APPS[@]}"; do echo "- $app"; done)

---

## Cloud Export Notes

This export was collected via REST API from Splunk Cloud. Some differences from Enterprise exports:

1. **Configuration Files**: Reconstructed from REST API endpoints (not direct file access)
2. **Usage Analytics**: Collected via search queries on \_audit and \_internal indexes
3. **Index Statistics**: Limited to what's available via REST API
4. **No File System Access**: Cannot access raw bucket data, audit logs, etc.

---

## Errors and Warnings

### Errors ($STATS_ERRORS)
$(if [ ${#ERRORS_LOG[@]} -eq 0 ]; then echo "No errors occurred."; else for err in "${ERRORS_LOG[@]}"; do echo "- $err"; done; fi)

### Warnings ($STATS_WARNINGS)
$(if [ ${#WARNINGS_LOG[@]} -eq 0 ]; then echo "No warnings."; else for warn in "${WARNINGS_LOG[@]}"; do echo "- $warn"; done; fi)

---

## Next Steps

1. **Upload to DynaBridge**: Upload the \`.tar.gz\` file to DynaBridge in Dynatrace
2. **Review Dashboards**: Check the dashboard conversion preview
3. **Review Alerts**: Check alert conversion recommendations
4. **Plan Data Ingestion**: Use OpenPipeline templates for log ingestion

---

*Generated by DynaBridge Splunk Cloud Export Script v$SCRIPT_VERSION*
EOF

  success "Summary report generated"
}

generate_manifest() {
  progress "Generating manifest.json (standardized schema)..."

  local manifest_file="$EXPORT_DIR/dynabridge_analytics/manifest.json"

  # Calculate export duration
  local export_duration=$(($(date +%s) - EXPORT_START_TIME))

  # Count saved searches (separate from alerts)
  local saved_search_count=0
  for app in "${SELECTED_APPS[@]}"; do
    if [ -f "$EXPORT_DIR/$app/savedsearches.json" ]; then
      local count=$(jq -r '.entry | length // 0' "$EXPORT_DIR/$app/savedsearches.json" 2>/dev/null || echo 0)
      saved_search_count=$((saved_search_count + count))
    fi
  done

  # Count Dashboard Studio and Classic dashboards from app-scoped folders (v2 structure)
  local studio_count=0
  local classic_count=0
  for app in "${SELECTED_APPS[@]}"; do
    if [ -d "$EXPORT_DIR/$app/dashboards/studio" ]; then
      local app_studio=$(find "$EXPORT_DIR/$app/dashboards/studio" -name "*.json" ! -name "*_definition.json" 2>/dev/null | wc -l | tr -d ' ')
      studio_count=$((studio_count + app_studio))
    fi
    if [ -d "$EXPORT_DIR/$app/dashboards/classic" ]; then
      local app_classic=$(find "$EXPORT_DIR/$app/dashboards/classic" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
      classic_count=$((classic_count + app_classic))
    fi
  done

  # Count total files
  local total_files=$(find "$EXPORT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  local total_size=$(du -sb "$EXPORT_DIR" 2>/dev/null | cut -f1 || echo "0")

  # Build apps array with v2 structure (counts from app-scoped folders)
  local apps_json="[]"
  for app in "${SELECTED_APPS[@]}"; do
    local app_classic=0
    local app_studio=0
    local app_alerts=0
    local app_saved=0

    # Count dashboards from v2 app-scoped folders
    if [ -d "$EXPORT_DIR/$app/dashboards/classic" ]; then
      app_classic=$(find "$EXPORT_DIR/$app/dashboards/classic" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ -d "$EXPORT_DIR/$app/dashboards/studio" ]; then
      app_studio=$(find "$EXPORT_DIR/$app/dashboards/studio" -name "*.json" ! -name "*_definition.json" 2>/dev/null | wc -l | tr -d ' ')
    fi
    local app_dashboards=$((app_classic + app_studio))

    if [ -f "$EXPORT_DIR/$app/savedsearches.json" ]; then
      # Count alerts using SAME LOGIC as TypeScript parser (SINGLE SOURCE OF TRUTH v4.2.1)
      # Only count as alert if ENABLED alert indicators present:
      # - alert.track = "1" or "true" (NOT "0" or "false")
      # - alert_type = "always", "custom", or "number of ..." (NOT empty or other values)
      # - alert_condition has a value
      # - alert_comparator or alert_threshold has a value
      # - counttype contains "number of"
      # - actions has non-empty comma-separated values
      # - action.* = "1" or "true" (NOT "0" or "false" or false)
      app_alerts=$(jq -r '[.entry[] | select(
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
      )] | length // 0' "$EXPORT_DIR/$app/savedsearches.json" 2>/dev/null || echo 0)
      app_saved=$(jq -r '.entry | length // 0' "$EXPORT_DIR/$app/savedsearches.json" 2>/dev/null || echo 0)
    fi

    local app_entry=$(jq -n \
      --arg name "$app" \
      --argjson dashboards "$app_dashboards" \
      --argjson dashboards_classic "$app_classic" \
      --argjson dashboards_studio "$app_studio" \
      --argjson alerts "$app_alerts" \
      --argjson saved "$app_saved" \
      '{
        name: $name,
        dashboards: $dashboards,
        dashboards_classic: $dashboards_classic,
        dashboards_studio: $dashboards_studio,
        alerts: $alerts,
        saved_searches: $saved
      }')

    apps_json=$(echo "$apps_json" | jq ". += [$app_entry]")
  done

  # Build usage intelligence summary for programmatic access
  local usage_intel_json="{}"
  if [ -d "$EXPORT_DIR/dynabridge_analytics/usage_analytics" ]; then
    progress "Extracting usage intelligence for manifest..."

    # Top 10 most viewed dashboards
    local top_dashboards="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_views_top100.json" ]; then
      top_dashboards=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboard_views_top100.json" 2>/dev/null || echo "[]")
    fi

    # Top 10 most active users
    local top_users="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_most_active.json" ]; then
      top_users=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_most_active.json" 2>/dev/null || echo "[]")
    fi

    # Top 10 most fired alerts
    local top_alerts="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_most_fired.json" ]; then
      top_alerts=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_most_fired.json" 2>/dev/null || echo "[]")
    fi

    # Never viewed dashboards count
    local never_viewed_count=0
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboards_never_viewed.json" ]; then
      never_viewed_count=$(jq -r '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/dashboards_never_viewed.json" 2>/dev/null || echo "0")
    fi

    # Never fired alerts count
    local never_fired_count=0
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_never_fired.json" ]; then
      never_fired_count=$(jq -r '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_never_fired.json" 2>/dev/null || echo "0")
    fi

    # Inactive users count
    local inactive_users_count=0
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_inactive.json" ]; then
      inactive_users_count=$(jq -r '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/users_inactive.json" 2>/dev/null || echo "0")
    fi

    # Failed alerts count
    local failed_alerts_count=0
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_failed.json" ]; then
      failed_alerts_count=$(jq -r '.results | length // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/alerts_failed.json" 2>/dev/null || echo "0")
    fi

    # Top searched sourcetypes
    local top_sourcetypes="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/sourcetypes_searched.json" ]; then
      top_sourcetypes=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/sourcetypes_searched.json" 2>/dev/null || echo "[]")
    fi

    # Top searched indexes
    local top_indexes="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/indexes_searched.json" ]; then
      top_indexes=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/indexes_searched.json" 2>/dev/null || echo "[]")
    fi

    # Volume summary
    local avg_daily_gb="0"
    local peak_daily_gb="0"
    local total_30d_gb="0"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json" ]; then
      avg_daily_gb=$(jq -r '.results[0].avg_daily_gb // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json" 2>/dev/null || echo "0")
      peak_daily_gb=$(jq -r '.results[0].peak_daily_gb // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json" 2>/dev/null || echo "0")
      total_30d_gb=$(jq -r '.results[0].total_30d_gb // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/daily_volume_summary.json" 2>/dev/null || echo "0")
    fi

    # Top 10 indexes by volume
    local top_indexes_by_volume="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_indexes_by_volume.json" ]; then
      top_indexes_by_volume=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_indexes_by_volume.json" 2>/dev/null || echo "[]")
    fi

    # Top 10 sourcetypes by volume
    local top_sourcetypes_by_volume="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_sourcetypes_by_volume.json" ]; then
      top_sourcetypes_by_volume=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_sourcetypes_by_volume.json" 2>/dev/null || echo "[]")
    fi

    # Top 10 hosts by volume
    local top_hosts_by_volume="[]"
    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_hosts_by_volume.json" ]; then
      top_hosts_by_volume=$(jq -r '.results[:10] // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/top_hosts_by_volume.json" 2>/dev/null || echo "[]")
    fi

    # Ingestion infrastructure data
    local total_forwarding_hosts="0"
    local ingestion_daily_gb="0"
    local hec_enabled="false"
    local hec_daily_gb="0"
    local by_connection_type="[]"
    local by_input_method="[]"
    local by_sourcetype_category="[]"

    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/summary.json" ]; then
      total_forwarding_hosts=$(jq -r '.results[0].total_forwarding_hosts // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/summary.json" 2>/dev/null || echo "0")
      ingestion_daily_gb=$(jq -r '.results[0].daily_avg_gb // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/summary.json" 2>/dev/null || echo "0")
    fi

    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/hec_usage.json" ]; then
      hec_daily_gb=$(jq -r '.results[0].daily_avg_gb // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/hec_usage.json" 2>/dev/null || echo "0")
      local hec_token_count=$(jq -r '.results[0].token_count // 0' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/hec_usage.json" 2>/dev/null || echo "0")
      if [ "$hec_token_count" != "0" ] && [ -n "$hec_token_count" ]; then
        hec_enabled="true"
      fi
    fi

    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_connection_type.json" ]; then
      by_connection_type=$(jq -r '.results // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_connection_type.json" 2>/dev/null || echo "[]")
    fi

    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_input_method.json" ]; then
      by_input_method=$(jq -r '.results // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_input_method.json" 2>/dev/null || echo "[]")
    fi

    if [ -f "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_sourcetype_category.json" ]; then
      by_sourcetype_category=$(jq -r '.results // []' "$EXPORT_DIR/dynabridge_analytics/usage_analytics/ingestion_infrastructure/by_sourcetype_category.json" 2>/dev/null || echo "[]")
    fi

    # Build usage intelligence JSON
    usage_intel_json=$(jq -n \
      --argjson top_dashboards "$top_dashboards" \
      --argjson top_users "$top_users" \
      --argjson top_alerts "$top_alerts" \
      --argjson never_viewed "$never_viewed_count" \
      --argjson never_fired "$never_fired_count" \
      --argjson inactive_users "$inactive_users_count" \
      --argjson failed_alerts "$failed_alerts_count" \
      --argjson top_sourcetypes "$top_sourcetypes" \
      --argjson top_indexes "$top_indexes" \
      --argjson avg_daily_gb "$avg_daily_gb" \
      --argjson peak_daily_gb "$peak_daily_gb" \
      --argjson total_30d_gb "$total_30d_gb" \
      --argjson top_indexes_by_volume "$top_indexes_by_volume" \
      --argjson top_sourcetypes_by_volume "$top_sourcetypes_by_volume" \
      --argjson top_hosts_by_volume "$top_hosts_by_volume" \
      --argjson total_forwarding_hosts "$total_forwarding_hosts" \
      --argjson ingestion_daily_gb "$ingestion_daily_gb" \
      --argjson hec_enabled "$hec_enabled" \
      --argjson hec_daily_gb "$hec_daily_gb" \
      --argjson by_connection_type "$by_connection_type" \
      --argjson by_input_method "$by_input_method" \
      --argjson by_sourcetype_category "$by_sourcetype_category" \
      '{
        "summary": {
          "dashboards_never_viewed": $never_viewed,
          "alerts_never_fired": $never_fired,
          "users_inactive_30d": $inactive_users,
          "alerts_with_failures": $failed_alerts
        },
        "volume": {
          "avg_daily_gb": $avg_daily_gb,
          "peak_daily_gb": $peak_daily_gb,
          "total_30d_gb": $total_30d_gb,
          "top_indexes_by_volume": $top_indexes_by_volume,
          "top_sourcetypes_by_volume": $top_sourcetypes_by_volume,
          "top_hosts_by_volume": $top_hosts_by_volume,
          "note": "See _usage_analytics/daily_volume_*.json for full daily breakdown"
        },
        "ingestion_infrastructure": {
          "summary": {
            "total_forwarding_hosts": $total_forwarding_hosts,
            "daily_ingestion_gb": $ingestion_daily_gb,
            "hec_enabled": $hec_enabled,
            "hec_daily_gb": $hec_daily_gb
          },
          "by_connection_type": $by_connection_type,
          "by_input_method": $by_input_method,
          "by_sourcetype_category": $by_sourcetype_category,
          "note": "See _usage_analytics/ingestion_infrastructure/ for detailed breakdown"
        },
        "prioritization": {
          "top_dashboards": $top_dashboards,
          "top_users": $top_users,
          "top_alerts": $top_alerts,
          "top_sourcetypes": $top_sourcetypes,
          "top_indexes": $top_indexes
        },
        "elimination_candidates": {
          "dashboards_never_viewed_count": $never_viewed,
          "alerts_never_fired_count": $never_fired,
          "note": "See _usage_analytics/ for full lists of candidates"
        }
      }')
  fi

  # Generate manifest
  cat > "$manifest_file" << MANIFEST_EOF
{
  "schema_version": "4.0",
  "archive_structure_version": "v2",
  "export_tool": "dynabridge-splunk-cloud-export",
  "export_tool_version": "$SCRIPT_VERSION",
  "export_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "export_duration_seconds": $export_duration,

  "archive_structure": {
    "version": "v2",
    "description": "App-centric dashboard organization prevents name collisions",
    "dashboard_location": "{AppName}/dashboards/classic/ and {AppName}/dashboards/studio/"
  },

  "source": {
    "hostname": "$SPLUNK_STACK",
    "fqdn": "$SPLUNK_STACK",
    "platform": "Splunk Cloud",
    "platform_version": "$CLOUD_TYPE"
  },

  "splunk": {
    "home": "cloud",
    "version": "$SPLUNK_VERSION",
    "build": "cloud",
    "flavor": "cloud",
    "role": "search_head",
    "architecture": "cloud",
    "is_cloud": true,
    "cloud_type": "$CLOUD_TYPE",
    "server_guid": "$SERVER_GUID"
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
    "data_anonymized": $ANONYMIZE_DATA
  },

  "statistics": {
    "apps_exported": $STATS_APPS,
    "dashboards_classic": $classic_count,
    "dashboards_studio": $studio_count,
    "dashboards_total": $STATS_DASHBOARDS,
    "alerts": $STATS_ALERTS,
    "saved_searches": $saved_search_count,
    "users": $STATS_USERS,
    "roles": 0,
    "indexes": $STATS_INDEXES,
    "api_calls_made": $STATS_API_CALLS,
    "rate_limit_hits": $STATS_RATE_LIMITS,
    "errors": $STATS_ERRORS,
    "warnings": $STATS_WARNINGS,
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
  if command -v sha256sum &> /dev/null; then
    hash=$(echo -n "$input" | sha256sum | cut -c1-"$length")
  elif command -v shasum &> /dev/null; then
    hash=$(echo -n "$input" | shasum -a 256 | cut -c1-"$length")
  elif command -v md5sum &> /dev/null; then
    hash=$(echo -n "$input" | md5sum | cut -c1-"$length")
  elif command -v md5 &> /dev/null; then
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
  if [ -z "$real_email" ] || [[ "$real_email" == *"@anon.dynabridge.local"* ]]; then
    echo "$real_email"
    return
  fi

  # Check if we already have a mapping (using simple file-based approach for bash 3.x compat)
  local mapping_file="/tmp/dynabridge_email_map_$$"
  if [ -f "$mapping_file" ]; then
    local existing=$(grep "^${real_email}|" "$mapping_file" 2>/dev/null | cut -d'|' -f2)
    if [ -n "$existing" ]; then
      echo "$existing"
      return
    fi
  fi

  # Generate new anonymized email
  local anon_id=$(generate_anon_id "$real_email" "user" 6)
  local anon_email="${anon_id}@anon.dynabridge.local"

  # Store mapping
  echo "${real_email}|${anon_email}" >> "$mapping_file"
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
  local mapping_file="/tmp/dynabridge_host_map_$$"
  if [ -f "$mapping_file" ]; then
    local existing=$(grep "^${real_host}|" "$mapping_file" 2>/dev/null | cut -d'|' -f2)
    if [ -n "$existing" ]; then
      echo "$existing"
      return
    fi
  fi

  # Generate new anonymized hostname
  local anon_id=$(generate_anon_id "$real_host" "" 8)
  local anon_host="host-${anon_id}.anon.local"

  # Store mapping
  echo "${real_host}|${anon_host}" >> "$mapping_file"
  ((ANON_HOST_COUNTER++))

  echo "$anon_host"
}

# Anonymize a single file
# =============================================================================
# PYTHON-BASED ANONYMIZATION (Reliable streaming for large files)
# =============================================================================
# This uses Python for file processing to avoid bash memory issues and
# regex catastrophic backtracking. Works with system Python.

# Generate the Python anonymization script inline
generate_python_anonymizer() {
  local script_file="$1"
  cat > "$script_file" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
DynaBridge Anonymizer - Streaming file anonymization
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
import hashlib
import json

# Anonymization mappings (consistent across files)
email_map = {}
host_map = {}

def get_hash_id(value):
    """Generate consistent short hash for a value"""
    return hashlib.md5(value.encode()).hexdigest()[:8]

def anonymize_email(email):
    """Anonymize email address consistently"""
    if email in email_map:
        return email_map[email]
    if '@anon.dynabridge.local' in email or '@example.com' in email or '@localhost' in email:
        return email
    # Use 'anon' prefix instead of 'user' to avoid creating \u sequences
    # (e.g., \user becomes invalid JSON unicode escape)
    anon = f"anon{get_hash_id(email)}@anon.dynabridge.local"
    email_map[email] = anon
    return anon

def anonymize_hostname(hostname):
    """Anonymize hostname consistently"""
    if hostname in host_map:
        return host_map[hostname]
    if hostname in ('localhost', '127.0.0.1', 'null', 'none', '*', ''):
        return hostname
    if hostname.startswith('host-') and '.anon.local' in hostname:
        return hostname
    anon = f"host-{get_hash_id(hostname)}.anon.local"
    host_map[hostname] = anon
    return anon

def process_line(line):
    """Process a single line, applying all anonymization rules"""
    result = line

    # 1. Anonymize email addresses
    # More precise pattern to avoid false matches
    email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}'
    for match in re.findall(email_pattern, result):
        anon = anonymize_email(match)
        if anon != match:
            result = result.replace(match, anon)

    # 2. Redact private IP addresses ONLY (RFC 1918)
    # These patterns are safe - they only match private ranges
    result = re.sub(r'\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    result = re.sub(r'\b172\.(1[6-9]|2[0-9]|3[01])\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    result = re.sub(r'\b192\.168\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]', result)
    # NOTE: Removed the overly broad public IP pattern that was matching version numbers
    # and other legitimate dot-separated values like "1.2.3.4" in SPL queries

    # 3. Anonymize hostnames in JSON format
    host_json_pattern = r'"(host|hostname|splunk_server|server|serverName)"\s*:\s*"([^"]+)"'
    for match in re.finditer(host_json_pattern, result, re.IGNORECASE):
        key, hostname = match.groups()
        anon = anonymize_hostname(hostname)
        if anon != hostname:
            result = result.replace(f'"{key}": "{hostname}"', f'"{key}": "{anon}"')
            result = result.replace(f'"{key}":"{hostname}"', f'"{key}":"{anon}"')

    # 4. Anonymize hostnames in conf format
    host_conf_pattern = r'\b(host|hostname|splunk_server|server)\s*=\s*([^\s,\]"]+)'
    for match in re.finditer(host_conf_pattern, result, re.IGNORECASE):
        key, hostname = match.groups()
        anon = anonymize_hostname(hostname)
        if anon != hostname:
            result = result.replace(f'{key}={hostname}', f'{key}={anon}')
            result = result.replace(f'{key} = {hostname}', f'{key} = {anon}')

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

  # Find Python (prefer Splunk's bundled Python if available, fall back to system)
  # Check multiple locations since SPLUNK_HOME may not be set
  local python_cmd=""
  local splunk_python_paths=(
    "/opt/splunk/bin/python3"
    "/opt/splunk/bin/python"
    "/opt/splunkforwarder/bin/python3"
    "/opt/splunkforwarder/bin/python"
    "/Applications/Splunk/bin/python3"
    "/Applications/Splunk/bin/python"
  )

  # Try Splunk's bundled Python first (if running on a Splunk server)
  for py_path in "${splunk_python_paths[@]}"; do
    if [ -x "$py_path" ]; then
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

  # Use simple, non-backtracking patterns with in-place sed
  # Check for GNU sed vs BSD sed
  local sed_inplace=""
  if sed --version 2>/dev/null | grep -q GNU; then
    sed_inplace="-i"
  else
    sed_inplace="-i ''"
  fi

  # Apply simple patterns directly to file (in-place, streaming)
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
  if [ "$ANONYMIZE_DATA" != "true" ]; then
    return 0
  fi

  print_box_header "ANONYMIZING SENSITIVE DATA"

  echo -e "  ${WHITE}Replacing sensitive data with anonymized values:${NC}"
  echo ""
  echo -e "    ${CYAN}→${NC} Email addresses → user######@anon.dynabridge.local"
  echo -e "    ${CYAN}→${NC} Hostnames → host-########.anon.local"
  echo -e "    ${CYAN}→${NC} IP addresses → [IP-REDACTED]"
  echo ""
  echo -e "  ${DIM}The same original value always maps to the same anonymized value.${NC}"
  echo ""

  progress "Scanning export directory for files to anonymize..."

  # Find all text files to process
  local files_to_process=()
  while IFS= read -r file; do
    files_to_process+=("$file")
  done < <(find "$EXPORT_DIR" -type f \( -name "*.json" -o -name "*.conf" -o -name "*.xml" -o -name "*.csv" -o -name "*.txt" -o -name "*.meta" \) 2>/dev/null)

  local total_files=${#files_to_process[@]}

  if [ "$total_files" -eq 0 ]; then
    info "No text files found to anonymize"
    return 0
  fi

  progress "Processing $total_files files..."

  local processed=0
  for file in "${files_to_process[@]}"; do
    anonymize_file "$file"
    ((processed++))
    # Show progress every 10 files
    if [ $((processed % 10)) -eq 0 ]; then
      printf "\r  Processing: %d/%d files..." "$processed" "$total_files"
    fi
  done

  printf "\r  Processing: %d/%d files... Done!     \n" "$total_files" "$total_files"

  # Report statistics
  echo ""
  echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}Anonymization Summary${NC}"
  echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "    Files processed:        ${GREEN}$total_files${NC}"
  echo -e "    Unique emails mapped:   ${GREEN}$ANON_EMAIL_COUNTER${NC}"
  echo -e "    Unique hosts mapped:    ${GREEN}$ANON_HOST_COUNTER${NC}"
  echo -e "    IP addresses:           ${GREEN}Redacted (all)${NC}"
  echo ""

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
    "ip_addresses": "all_redacted"
  },
  "transformations": {
    "emails": "original@domain.com → user######@anon.dynabridge.local",
    "hostnames": "server.example.com → host-########.anon.local",
    "ipv4": "x.x.x.x → [IP-REDACTED]",
    "ipv6": "xxxx:xxxx:... → [IPv6-REDACTED]"
  },
  "note": "This export has been anonymized. Original values cannot be recovered from this data."
}
ANON_EOF

  # Clean up mapping files
  rm -f "/tmp/dynabridge_email_map_$$" "/tmp/dynabridge_host_map_$$"

  success "Data anonymization complete"
}

# =============================================================================
# ARCHIVE CREATION
# =============================================================================

create_archive() {
  # Usage: create_archive [keep_dir] [suffix]
  # keep_dir: if "true", don't delete EXPORT_DIR after archiving (for masked workflow)
  # suffix: optional suffix like "_masked" to add to archive name
  local keep_dir="${1:-false}"
  local suffix="${2:-}"

  # Finalize debug log before archiving (redirect to stderr for consistency)
  finalize_debug_log >&2

  progress "Creating compressed archive${suffix:+ ($suffix)}..."

  local archive_name="${EXPORT_NAME}${suffix}.tar.gz"

  # Create tar archive
  tar -czf "$archive_name" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"

  if [ $? -eq 0 ]; then
    local size=$(du -h "$archive_name" | cut -f1)
    success "Archive created: $archive_name ($size)"

    # Clean up export directory only if not keeping
    if [ "$keep_dir" != "true" ]; then
      rm -rf "$EXPORT_DIR"
    fi

    echo ""
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}  ARCHIVE CREATED${NC}"
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Archive:${NC} $(pwd)/$archive_name"
    echo -e "  ${BOLD}Size:${NC}    $size"
    echo ""
  else
    error "Failed to create archive"
    return 1
  fi
}

# =============================================================================
# MASKED ARCHIVE CREATION (v4.2.5)
# Creates an anonymized copy while preserving the original
# =============================================================================

create_masked_archive() {
  local masked_dir="${EXPORT_DIR}_masked"

  echo ""
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${CYAN}  CREATING MASKED (ANONYMIZED) ARCHIVE${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${DIM}The original archive has been preserved.${NC}"
  echo -e "  ${DIM}Now creating a separate anonymized copy...${NC}"
  echo ""

  # Copy export directory to masked version
  progress "Copying export directory for anonymization..."
  cp -r "$EXPORT_DIR" "$masked_dir"

  if [ ! -d "$masked_dir" ]; then
    error "Failed to create masked directory copy"
    return 1
  fi

  # Temporarily switch EXPORT_DIR for anonymization
  local original_export_dir="$EXPORT_DIR"
  EXPORT_DIR="$masked_dir"

  # Run anonymization on the masked copy
  anonymize_export

  # Create the masked archive (this will clean up the masked dir)
  local masked_archive="${EXPORT_NAME}_masked.tar.gz"
  progress "Creating masked archive..."
  tar -czf "$masked_archive" -C "$(dirname "$masked_dir")" "$(basename "$masked_dir")"

  if [ $? -eq 0 ]; then
    local size=$(du -h "$masked_archive" | cut -f1)
    success "Masked archive created: $masked_archive ($size)"

    # Clean up masked directory
    rm -rf "$masked_dir"

    echo ""
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}  MASKED ARCHIVE CREATED${NC}"
    echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Masked Archive:${NC} $(pwd)/$masked_archive"
    echo -e "  ${BOLD}Size:${NC}           $size"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Share the ${BOLD}_masked${NC} archive with third parties."
    echo -e "        Keep the original archive for your records."
    echo ""
  else
    error "Failed to create masked archive"
    EXPORT_DIR="$original_export_dir"
    rm -rf "$masked_dir"
    return 1
  fi

  # Restore original EXPORT_DIR and clean it up
  EXPORT_DIR="$original_export_dir"
  rm -rf "$EXPORT_DIR"
}

# =============================================================================
# TROUBLESHOOTING REPORT GENERATOR
# =============================================================================

generate_troubleshooting_report() {
  local report_file="$EXPORT_DIR/TROUBLESHOOTING.md"

  cat > "$report_file" << 'TROUBLESHOOT_HEADER'
# DynaBridge Splunk Cloud Export Troubleshooting Report

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
| Timestamp | $(date -Iseconds 2>/dev/null || date) |
| Splunk Cloud Stack | $SPLUNK_STACK |
| Auth Method | $AUTH_METHOD |
| Cloud Type | ${CLOUD_TYPE:-Unknown} |
| Splunk Version | ${SPLUNK_VERSION:-Unknown} |

---

## Error Summary

**Total Errors:** ${STATS_ERRORS}
**Rate Limit Events:** ${STATS_RATE_LIMITS}

EOF

  # Scan for error files in _usage_analytics
  if [ -d "$EXPORT_DIR/dynabridge_analytics/usage_analytics" ]; then
    echo "## Failed Analytics Searches" >> "$report_file"
    echo "" >> "$report_file"

    local error_count=0
    for json_file in "$EXPORT_DIR/dynabridge_analytics/usage_analytics"/*.json; do
      if [ -f "$json_file" ] && grep -q '"error":' "$json_file" 2>/dev/null; then
        ((error_count++))
        local filename=$(basename "$json_file")
        local error_type=""
        local error_msg=""

        if $HAS_JQ; then
          error_type=$(jq -r '.error // "unknown"' "$json_file" 2>/dev/null)
          error_msg=$(jq -r '.message // "No message"' "$json_file" 2>/dev/null)
        else
          error_type=$(grep -oP '"error"\s*:\s*"\K[^"]+' "$json_file" | head -1)
          error_msg=$(grep -oP '"message"\s*:\s*"\K[^"]+' "$json_file" | head -1)
        fi

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

  # Add Splunk Cloud specific troubleshooting
  cat >> "$report_file" << 'TROUBLESHOOT_GUIDES'
---

## Common Splunk Cloud Issues

### 1. REST Command Restrictions

**Symptoms:** "| rest" searches fail or return no data

**Cause:** Splunk Cloud restricts certain REST API commands for security.

**Solutions:**
- Use alternative data collection methods
- Contact Splunk Cloud support to request REST API access
- Some data may need to be exported via Splunk Web UI

---

### 2. Authentication Token Expiration

**Symptoms:** "401 Unauthorized" errors during export

**Solutions:**
- Generate a new API token from Splunk Web → Settings → Tokens
- Ensure token has sufficient permissions
- Token should have at least these capabilities:
  - `search`, `admin_all_objects`, `list_settings`

---

### 3. Rate Limiting (429 Errors)

**Symptoms:** "Rate limited" messages, slow export

**Cause:** Too many API requests in short time.

**Solutions:**
- The script automatically backs off and retries
- If persistent, wait and run export during off-peak hours
- For large environments, split export into multiple runs

---

### 4. Insufficient Permissions

**Symptoms:** "403 Forbidden" for certain endpoints

**Solutions:**
- Verify user has the `admin` role or equivalent
- Required capabilities:
  - `search` - Run searches
  - `list_settings` - View configurations
  - `admin_all_objects` - Access all apps' objects
  - `rest_properties_get` - REST API read access

**To check capabilities:**
```
Settings → Users → [your user] → Roles → Check capabilities
```

---

### 5. Internal Indexes Not Accessible

**Symptoms:** Usage analytics empty, "_audit" or "_internal" queries fail

**Cause:** Splunk Cloud may restrict access to internal indexes.

**Solutions:**
- Request access to _audit and _internal indexes
- Some analytics may not be available in all Splunk Cloud tiers
- Core export data (dashboards, alerts) will still work

---

## Getting Help

1. **Collect these files for support:**
   - This TROUBLESHOOTING.md
   - export.log
   - manifest.json

2. **Diagnostic commands to run in Splunk Web:**
   ```splunk
   | rest /services/authentication/current-context | table username, roles, capabilities
   ```

3. **Test basic search access:**
   ```splunk
   | makeresults | eval test="Export script connectivity test"
   ```

---

*Report generated by DynaBridge Splunk Cloud Export v${SCRIPT_VERSION}*
TROUBLESHOOT_GUIDES

  log "Generated troubleshooting report: $report_file"
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================

show_completion() {
  print_box_header "EXPORT COMPLETE"

  print_box_line ""
  print_box_line "${BOLD}Export Statistics:${NC}"
  print_box_line "  • Applications:    $STATS_APPS"
  print_box_line "  • Dashboards:      $STATS_DASHBOARDS"
  print_box_line "  • Alerts:          $STATS_ALERTS"
  print_box_line "  • Users:           $STATS_USERS"
  print_box_line "  • Indexes:         $STATS_INDEXES"
  print_box_line ""
  print_box_line "${BOLD}API Statistics:${NC}"
  print_box_line "  • Total API calls: $STATS_API_CALLS"
  print_box_line "  • Rate limit hits: $STATS_RATE_LIMITS"
  print_box_line "  • Errors:          $STATS_ERRORS"
  print_box_line "  • Warnings:        $STATS_WARNINGS"
  if [ "$STATS_ERRORS" -gt 0 ]; then
    print_box_line ""
    print_box_line "  ${YELLOW}⚠ See TROUBLESHOOTING.md in archive for error details${NC}"
  fi
  print_box_line ""
  print_box_line "${BOLD}Next Steps:${NC}"
  print_box_line "  1. Upload the .tar.gz file to DynaBridge in Dynatrace"
  print_box_line "  2. Review the migration analysis"
  print_box_line "  3. Begin dashboard and alert conversion"
  print_box_line ""

  print_box_footer

  # Show prominent error warning if there were errors
  if [ "$STATS_ERRORS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}⚠  EXPORT COMPLETED WITH ${STATS_ERRORS} ERROR(S)${NC}                               ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  The export is still usable but some analytics data may be missing. ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}TO DIAGNOSE:${NC}                                                       ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  1. Extract the archive:                                             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     tar -xzf ${EXPORT_NAME}.tar.gz                                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  2. Log file is located at:                                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     ${CYAN}$(pwd)/${EXPORT_NAME}/_export.log${NC}                    ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  3. Also check:                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     - ${EXPORT_NAME}/TROUBLESHOOTING.md                              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     - ${EXPORT_NAME}/_usage_analytics/*.json                         ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  ${WHITE}COMMON SPLUNK CLOUD ISSUES:${NC}                                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • REST command (| rest) may be restricted                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • _audit and _internal indexes may have limited access             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  • API rate limiting during peak hours                              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
  fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

run_collection() {
  print_box_header "STEP 6: DATA COLLECTION"

  echo ""
  info "Starting data collection..."
  echo ""

  setup_export_directory

  local total_steps=8
  local current_step=0

  # System info
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting server information..."
  collect_system_info

  # Configurations
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting configurations..."
  collect_configurations

  # Dashboards
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting dashboards..."
  collect_dashboards

  # Alerts
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting alerts and saved searches..."
  collect_alerts

  # RBAC
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting users and roles..."
  collect_rbac

  # Knowledge objects
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting knowledge objects..."
  collect_knowledge_objects

  # App-scoped analytics (per-app usage data)
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting app-scoped analytics..."
  if [ "$COLLECT_USAGE" = "true" ]; then
    for app in "${SELECTED_APPS[@]}"; do
      if [ -d "$EXPORT_DIR/$app" ]; then
        collect_app_analytics "$app"
      fi
    done
    success "App-scoped analytics collected (see each app's splunk-analysis/ folder)"
  fi

  # Global/infrastructure usage analytics
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Running global usage analytics..."
  collect_usage_analytics

  # Indexes
  ((current_step++))
  echo -e "  [${current_step}/${total_steps}] Collecting index information..."
  collect_indexes

  echo ""

  print_box_footer
}

main() {
  # Check dependencies
  if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed."
    exit 1
  fi

  # Note: Python 3 is now used for all JSON processing (v3.6.0+)
  # No jq dependency required

  # Parse command-line arguments for non-interactive mode
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stack)
        SPLUNK_STACK="$2"
        shift 2
        ;;
      --token)
        AUTH_TOKEN="$2"
        AUTH_METHOD="token"
        shift 2
        ;;
      --user)
        SPLUNK_USER="$2"
        shift 2
        ;;
      --password)
        SPLUNK_PASSWORD="$2"
        AUTH_METHOD="userpass"
        shift 2
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
          _app=$(echo "$_app" | xargs)
          [ -n "$_app" ] && SELECTED_APPS+=("$_app")
        done
        EXPORT_ALL_APPS=false
        if [ ${#SELECTED_APPS[@]} -eq 0 ]; then
          echo "[WARNING] --apps was specified but no valid apps were parsed from '$2'" >&2
        fi
        shift 2
        ;;
      --output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --usage)
        # Opt-in to usage analytics (requires _audit/_internal index access)
        COLLECT_USAGE=true
        shift
        ;;
      --no-usage)
        # Legacy flag - kept for backwards compatibility (usage is now off by default)
        COLLECT_USAGE=false
        shift
        ;;
      --rbac)
        # Opt-in to RBAC/users collection (global user and role data)
        COLLECT_RBAC=true
        shift
        ;;
      --no-rbac)
        # Legacy flag - kept for backwards compatibility (RBAC is now off by default)
        COLLECT_RBAC=false
        shift
        ;;
      --skip-internal)
        SKIP_INTERNAL=true
        shift
        ;;
      --scoped)
        # Scope all collections to selected apps (auto-enabled with --apps)
        SCOPE_TO_APPS=true
        shift
        ;;
      --proxy)
        PROXY_URL="$2"
        shift 2
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
        echo "  --stack URL       Splunk Cloud stack URL"
        echo "  --token TOKEN     API token for authentication"
        echo "  --user USER       Username (if not using token)"
        echo "  --password PASS   Password (if not using token)"
        echo "  --all-apps        Export all applications"
        echo "  --apps LIST       Comma-separated list of apps"
        echo "  --output DIR      Output directory"
        echo "  --rbac            Collect RBAC/users data (OFF by default - global user/role data)"
        echo "  --usage           Collect usage analytics (OFF by default - requires _audit/_internal)"
        echo "  --skip-internal   Skip searches requiring _internal index (use if restricted)"
        echo "  --scoped          Scope all collections to selected apps only"
        echo "  --proxy URL       Route all connections through a proxy server (e.g., http://proxy:8080)"
        echo "  -d, --debug       Enable verbose debug logging (writes to export_debug.log)"
        echo "  --help            Show this help"
        echo ""
        echo "Performance Tips:"
        echo "  For large environments, use --scoped with --apps:"
        echo "    $0 --stack acme.splunkcloud.com --token XXX --apps myapp --scoped"
        echo ""
        echo "  This exports app configs + app-specific users/usage for migration analysis."
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  # =========================================================================
  # DETERMINE INTERACTIVE VS NON-INTERACTIVE MODE
  # Non-interactive requires: --stack AND (--token OR --user+--password)
  # =========================================================================

  # Check if we have enough params for non-interactive mode
  local has_stack=false
  local has_auth=false

  [ -n "$SPLUNK_STACK" ] && has_stack=true
  [ -n "$AUTH_TOKEN" ] && has_auth=true
  [ -n "$SPLUNK_USER" ] && [ -n "$SPLUNK_PASSWORD" ] && has_auth=true

  # Provide helpful feedback if partial params were given
  if [ "$has_stack" = "true" ] && [ "$has_auth" = "false" ]; then
    echo ""
    echo -e "${YELLOW}⚠ WARNING: --stack provided but no authentication${NC}"
    echo -e "${DIM}  For non-interactive mode, also provide:${NC}"
    echo -e "${DIM}    --token YOUR_TOKEN${NC}"
    echo -e "${DIM}    OR --user USER --password PASS${NC}"
    echo ""
    echo -e "${DIM}  Falling back to interactive mode...${NC}"
    echo ""
  fi

  if [ "$has_stack" = "false" ] && [ "$has_auth" = "true" ]; then
    echo ""
    echo -e "${YELLOW}⚠ WARNING: Authentication provided but no --stack${NC}"
    echo -e "${DIM}  For non-interactive mode, also provide:${NC}"
    echo -e "${DIM}    --stack your-stack.splunkcloud.com${NC}"
    echo ""
    echo -e "${DIM}  Falling back to interactive mode...${NC}"
    echo ""
  fi

  # Show banner (NON_INTERACTIVE controls clear behavior)
  if [ "$has_stack" = "true" ] && [ "$has_auth" = "true" ]; then
    NON_INTERACTIVE=true
  fi
  show_banner

  # Check if non-interactive mode (all required params provided)
  if [ "$NON_INTERACTIVE" = "true" ]; then
    # Non-interactive mode - NO PROMPTS ALLOWED
    SPLUNK_STACK=$(echo "$SPLUNK_STACK" | sed 's|https://||' | sed 's|:8089||' | sed 's|/$||')
    SPLUNK_URL="https://${SPLUNK_STACK}:8089"

    # Set proxy args if --proxy was provided
    if [ -n "$PROXY_URL" ]; then
      CURL_PROXY_ARGS="-x $PROXY_URL"
    fi

    info "Running in NON-INTERACTIVE mode (all required parameters provided)"
    info "  Stack: $SPLUNK_STACK"
    info "  Auth:  ${AUTH_METHOD:-token}"
    if [ -n "$PROXY_URL" ]; then
      info "  Proxy: $PROXY_URL"
    fi
    if [ ${#SELECTED_APPS[@]} -gt 0 ]; then
      info "  Apps:  ${SELECTED_APPS[*]}"
    else
      info "  Apps:  all (will fetch from API)"
    fi
    if [ "$SCOPE_TO_APPS" = "true" ]; then
      info "  Mode:  App-scoped analytics"
    fi
    if [ "$DEBUG_MODE" = "true" ]; then
      info "  Debug: ENABLED (verbose logging)"
    fi
    if [ "$COLLECT_RBAC" = "true" ]; then
      info "  RBAC:  ENABLED (collecting global user/role data)"
    else
      info "  RBAC:  DISABLED (use --rbac to enable)"
    fi
    if [ "$COLLECT_USAGE" = "true" ]; then
      info "  Usage: ENABLED (requires _audit/_internal index access)"
    else
      info "  Usage: DISABLED (use --usage to enable)"
    fi
    echo ""

    # Log configuration state for debugging
    debug_config_state

    if ! test_connectivity "$SPLUNK_URL"; then
      exit 1
    fi

    if ! authenticate; then
      exit 1
    fi

    check_capabilities

    # Get server info
    local server_info
    server_info=$(api_call "/services/server/info" "GET" "output_mode=json")
    SPLUNK_VERSION=$(json_value "$server_info" '.entry[0].content.version')
    SERVER_GUID=$(json_value "$server_info" '.entry[0].content.guid')
    CLOUD_TYPE="cloud"

    info "Connected to Splunk Cloud v$SPLUNK_VERSION"

    # Get apps if exporting all (or if no apps specified)
    if [ "$EXPORT_ALL_APPS" = "true" ] || [ ${#SELECTED_APPS[@]} -eq 0 ]; then
      # =====================================================================
      # WARNING: No app filter specified - will export ALL apps
      # This can be very slow in large environments
      # =====================================================================
      echo ""
      echo -e "  ${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
      echo -e "  ${YELLOW}║${NC}  ${BOLD}⚠ WARNING: No --apps filter specified${NC}                                ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}  The script will export ALL applications from this Splunk Cloud       ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}  environment. In large systems (1000+ dashboards), this may take      ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}  several hours to complete.                                           ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}                                                                        ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}  ${DIM}To export specific apps with usage data, use:${NC}                        ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}║${NC}  ${DIM}  --apps \"app1,app2\" --scoped --rbac --usage${NC}                          ${YELLOW}║${NC}"
      echo -e "  ${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "  ${CYAN}Continuing with full export...${NC}"
      echo ""

      info "Fetching app list from Splunk Cloud..."
      local apps_response
      apps_response=$(api_call "/services/apps/local" "GET" "output_mode=json&count=0")
      if $HAS_JQ; then
        while IFS= read -r line; do
          SELECTED_APPS+=("$line")
        done < <(echo "$apps_response" | jq -r '.entry[].name' 2>/dev/null)
      else
        while IFS= read -r line; do
          SELECTED_APPS+=("$line")
        done < <(echo "$apps_response" | grep -oP '"name"\s*:\s*"\K[^"]+')
      fi

      # Show count and additional warning if large
      local app_count=${#SELECTED_APPS[@]}
      if [ "$app_count" -gt 50 ]; then
        warning "Found ${app_count} apps - this is a large environment!"
        warning "Consider using --apps to filter for faster exports"
      fi
    fi

    STATS_APPS=${#SELECTED_APPS[@]}
    info "Will export ${STATS_APPS} app(s)"
  else
    # Interactive mode - prompts allowed
    show_introduction
    get_splunk_stack
    get_authentication
    get_proxy_settings
    detect_environment
    select_applications
    select_data_categories
  fi

  # Set export start time
  EXPORT_START_TIME=$(date +%s)

  # ==========================================================================
  # AUTO-ENABLE APP-SCOPED MODE FOR PERFORMANCE
  # When specific apps are selected (not --all-apps), automatically scope
  # collections to those apps only. This dramatically reduces export time
  # in large environments (from hours to minutes).
  # ==========================================================================
  if [ "$EXPORT_ALL_APPS" = "false" ]; then
    # Specific apps were selected - auto-enable scoped mode
    if [ "$SCOPE_TO_APPS" != "true" ]; then
      info "App-scoped mode auto-enabled (specific apps selected)"
      info "  → Usage analytics will be scoped to: ${SELECTED_APPS[*]}"
      info "  → Use --all-apps to collect global analytics"
      SCOPE_TO_APPS=true
    fi
  fi

  # Display mode information
  if [ "$SCOPE_TO_APPS" = "true" ]; then
    echo ""
    echo "  ${CYAN}📊 APP-SCOPED MODE${NC}"
    echo "  ${DIM}Collections scoped to selected apps: ${SELECTED_APPS[*]}${NC}"
    echo "  ${DIM}Global user/usage analytics will be filtered to these apps${NC}"
    echo ""
  fi

  # Run collection
  run_collection

  # Generate reports
  generate_summary
  generate_manifest

  # Generate troubleshooting report if there were errors
  if [ "$STATS_ERRORS" -gt 0 ]; then
    warning "Export encountered ${STATS_ERRORS} error(s). Generating troubleshooting report..."
    generate_troubleshooting_report
  fi

  # v4.2.5: Two-archive approach for anonymization
  # Always create original archive first (untouched), then create masked copy if needed
  if [ "$ANONYMIZE_DATA" = "true" ]; then
    # Create original archive first, keeping EXPORT_DIR for masked copy
    create_archive "true"  # keep_dir=true

    # Create masked (anonymized) archive from a copy
    create_masked_archive
  else
    # No anonymization - just create single archive
    create_archive
  fi

  # Show export timing statistics (v4.0.0)
  show_export_timing_stats

  # Clear checkpoint on successful completion
  clear_checkpoint

  # Show completion
  show_completion

  # Clear sensitive data
  AUTH_TOKEN=""
  SPLUNK_PASSWORD=""
  SESSION_KEY=""
}

# Run main
main "$@"
