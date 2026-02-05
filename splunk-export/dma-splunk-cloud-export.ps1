<#
.SYNOPSIS
    DMA Splunk Cloud Export Script v4.3.0 (PowerShell Edition)

.DESCRIPTION
    REST API-Only Data Collection for Splunk Cloud Migration to Dynatrace.

    This script collects configurations, dashboards, alerts, users, and usage
    analytics from your Splunk Cloud environment via REST API to enable migration
    planning and execution using the Dynatrace Migration Assistant.

    IMPORTANT: This script is for SPLUNK CLOUD only. For Splunk Enterprise,
    use dma-splunk-export.sh instead.

    This is a functionally identical PowerShell conversion of
    dma-splunk-cloud-export.sh v4.3.0 for Windows environments.

    REQUIREMENTS:
      - PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+ (PowerShell Core)
      - Windows 10 1803+ (for built-in tar.exe)
      - Network access to your Splunk Cloud instance (port 8089)
      - No external dependencies (no Python, no jq, no curl)

    v4.3.0 Changes:
      - Added -Proxy parameter for environments requiring proxy servers
      - Added -ResumeCollect parameter to resume interrupted exports from .tar.gz archive
      - Increased max timeout from 4 hours to 12 hours for very large environments
      - Interactive proxy prompt with default No

    v4.2.6 Changes (PowerShell Edition):
      - Zero external dependencies - pure PowerShell implementation
      - Replaces Python JSON processing with native ConvertFrom-Json/ConvertTo-Json
      - Replaces curl with Invoke-WebRequest
      - Replaces jq with native PowerShell property access
      - Creates .tar.gz archives using Windows built-in tar.exe
      - Compatible with both PowerShell 5.1 and 7+

    v4.2.4 Changes (from bash):
      - Anonymization creates TWO archives: original (untouched) + _masked (anonymized)
      - RBAC/Users collection OFF by default (use -Rbac to enable)
      - Usage analytics collection OFF by default (use -Usage to enable)
      - Faster defaults: batch size 250, API delay 50ms
      - Blocked endpoint skip list for known Splunk Cloud restrictions

.PARAMETER Stack
    Splunk Cloud stack URL (e.g., acme-corp.splunkcloud.com)

.PARAMETER Token
    Splunk API Bearer token for authentication

.PARAMETER User
    Splunk username (alternative to token auth)

.PARAMETER Password
    Splunk password (used with -User)

.PARAMETER AllApps
    Export all applications (default behavior)

.PARAMETER Apps
    Comma-separated list of specific app names to export

.PARAMETER Output
    Output directory path (default: current directory)

.PARAMETER Rbac
    Enable RBAC/Users collection (off by default)

.PARAMETER Usage
    Enable usage analytics collection (off by default)

.PARAMETER Debug_Mode
    Enable verbose debug logging

.PARAMETER NonInteractive
    Run without interactive prompts (requires -Stack and -Token or -User/-Password)

.PARAMETER SkipAnonymization
    Skip data anonymization step

.PARAMETER Proxy
    Route all connections through a proxy server (e.g., http://proxy.company.com:8080)

.PARAMETER ResumeCollect
    Resume a previous interrupted export from a .tar.gz archive

.PARAMETER SkipInternal
    Skip _internal index searches (for restricted Splunk Cloud environments)

.PARAMETER Version
    Display script version and exit

.PARAMETER Help
    Display help information and exit

.EXAMPLE
    .\dma-splunk-cloud-export.ps1

    Interactive mode - prompts for all settings.

.EXAMPLE
    .\dma-splunk-cloud-export.ps1 -Stack "acme-corp.splunkcloud.com" -Token "your-token"

    Non-interactive mode with token authentication.

.EXAMPLE
    .\dma-splunk-cloud-export.ps1 -Stack "acme-corp" -User "admin" -Password "pass" -Apps "search,my_app" -Rbac -Usage

    Export specific apps with RBAC and usage analytics enabled.

.NOTES
    Developed for Dynatrace One by Enterprise Solutions & Architecture
    An ACE Services Division of Dynatrace
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Splunk Cloud stack URL (e.g., acme-corp.splunkcloud.com)")]
    [string]$Stack = "",

    [Parameter(HelpMessage = "Splunk API Bearer token")]
    [string]$Token = "",

    [Parameter(HelpMessage = "Splunk username")]
    [string]$User = "",

    [Parameter(HelpMessage = "Splunk password")]
    [string]$Password = "",

    [Parameter(HelpMessage = "Export all applications")]
    [switch]$AllApps,

    [Parameter(HelpMessage = "Comma-separated list of app names to export")]
    [string]$Apps = "",

    [Parameter(HelpMessage = "Output directory path")]
    [string]$Output = "",

    [Parameter(HelpMessage = "Enable RBAC/Users collection")]
    [switch]$Rbac,

    [Parameter(HelpMessage = "Enable usage analytics collection")]
    [switch]$Usage,

    [Parameter(HelpMessage = "Enable verbose debug logging")]
    [switch]$Debug_Mode,

    [Parameter(HelpMessage = "Run without interactive prompts")]
    [switch]$NonInteractive,

    [Parameter(HelpMessage = "Skip data anonymization")]
    [switch]$SkipAnonymization,

    [Parameter(HelpMessage = "Route all connections through a proxy server")]
    [string]$Proxy = "",

    [Parameter(HelpMessage = "Resume a previous interrupted export from a .tar.gz archive")]
    [string]$ResumeCollect = "",

    [Parameter(HelpMessage = "Skip _internal index searches")]
    [switch]$SkipInternal,

    [Parameter(HelpMessage = "Display version and exit")]
    [switch]$Version,

    [Parameter(HelpMessage = "Display help and exit")]
    [switch]$ShowHelp
)

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

$Script:SCRIPT_VERSION = "4.3.0"
$Script:SCRIPT_NAME = "DMA Splunk Cloud Export (PowerShell)"

# Detect PowerShell version for compatibility
$Script:IsPSCore = $PSVersionTable.PSVersion.Major -ge 7

# UTF-8 encoding without BOM (for JSON file output)
$Script:UTF8NoBOM = [System.Text.UTF8Encoding]::new($false)

# =============================================================================
# VERSION AND HELP HANDLING
# =============================================================================

if ($Version) {
    Write-Host "$Script:SCRIPT_NAME v$Script:SCRIPT_VERSION"
    exit 0
}

if ($ShowHelp) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# =============================================================================
# ANSI COLOR CODES (PowerShell supports ANSI escape sequences)
# =============================================================================

$Script:RED = "`e[0;31m"
$Script:GREEN = "`e[0;32m"
$Script:YELLOW = "`e[1;33m"
$Script:BLUE = "`e[0;34m"
$Script:CYAN = "`e[0;36m"
$Script:MAGENTA = "`e[0;35m"
$Script:WHITE = "`e[1;37m"
$Script:GRAY = "`e[0;90m"
$Script:NC = "`e[0m"  # No Color
$Script:BOLD = "`e[1m"
$Script:DIM = "`e[2m"

# PowerShell 5.1 does not support `e escape - use [char]27
if (-not $Script:IsPSCore) {
    $ESC = [char]27
    $Script:RED = "$ESC[0;31m"
    $Script:GREEN = "$ESC[0;32m"
    $Script:YELLOW = "$ESC[1;33m"
    $Script:BLUE = "$ESC[0;34m"
    $Script:CYAN = "$ESC[0;36m"
    $Script:MAGENTA = "$ESC[0;35m"
    $Script:WHITE = "$ESC[1;37m"
    $Script:GRAY = "$ESC[0;90m"
    $Script:NC = "$ESC[0m"
    $Script:BOLD = "$ESC[1m"
    $Script:DIM = "$ESC[2m"
}

# Box drawing characters
$Script:BOX_TL = [char]0x2554  # ╔
$Script:BOX_TR = [char]0x2557  # ╗
$Script:BOX_BL = [char]0x255A  # ╚
$Script:BOX_BR = [char]0x255D  # ╝
$Script:BOX_H  = [char]0x2550  # ═
$Script:BOX_V  = [char]0x2551  # ║
$Script:BOX_T  = [char]0x2560  # ╠
$Script:BOX_B  = [char]0x2563  # ╣

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Splunk Cloud connection
$Script:SPLUNK_STACK = ""
$Script:SPLUNK_URL = ""
$Script:AUTH_METHOD = ""
$Script:AUTH_TOKEN = ""
$Script:SPLUNK_USER = ""
$Script:SPLUNK_PASSWORD = ""
$Script:SESSION_KEY = ""

# Export settings
$Script:EXPORT_DIR = ""
$Script:EXPORT_NAME = ""
$Script:TIMESTAMP = ""
$Script:LOG_FILE = ""
$Script:OUTPUT_DIR = ""

# Environment info
$Script:CLOUD_TYPE = ""
$Script:SPLUNK_VERSION = ""
$Script:SERVER_GUID = ""

# Collection options
$Script:SELECTED_APPS = @()
$Script:EXPORT_ALL_APPS = $true
$Script:COLLECT_CONFIGS = $true
$Script:COLLECT_DASHBOARDS = $true
$Script:COLLECT_ALERTS = $true
$Script:COLLECT_RBAC = $false         # OFF by default
$Script:COLLECT_USAGE = $false        # OFF by default
$Script:COLLECT_INDEXES = $true
$Script:COLLECT_LOOKUPS = $false
$Script:COLLECT_AUDIT = $false
$Script:ANONYMIZE_DATA = $true
$Script:USAGE_PERIOD = "30d"
$Script:SKIP_INTERNAL = $false

# App-scoped collection mode
$Script:SCOPE_TO_APPS = $false

# Proxy settings
$Script:PROXY_URL = ""

# Resume settings
$Script:RESUME_ARCHIVE = ""
$Script:RESUME_MODE = $false

# Non-interactive mode flag
$Script:NON_INTERACTIVE = $false

# Debug mode
$Script:DEBUG_MODE = $false
$Script:DEBUG_LOG_FILE = ""

# =============================================================================
# SPLUNK CLOUD BLOCKED ENDPOINTS (v4.2.4)
# =============================================================================
$Script:SPLUNK_CLOUD_BLOCKED_ENDPOINTS = @(
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

# Pagination settings
$Script:BATCH_SIZE = if ($env:BATCH_SIZE) { [int]$env:BATCH_SIZE } else { 250 }
$Script:RATE_LIMIT_DELAY = if ($env:RATE_LIMIT_DELAY) { [double]$env:RATE_LIMIT_DELAY } else { 0.05 }

# Timeout settings (seconds)
$Script:CONNECT_TIMEOUT = if ($env:CONNECT_TIMEOUT) { [int]$env:CONNECT_TIMEOUT } else { 30 }
$Script:API_TIMEOUT = if ($env:API_TIMEOUT) { [int]$env:API_TIMEOUT } else { 120 }

# Total runtime limit
$Script:MAX_TOTAL_TIME = if ($env:MAX_TOTAL_TIME) { [int]$env:MAX_TOTAL_TIME } else { 43200 }  # 12 hours

# Retry settings
$Script:MAX_RETRIES = if ($env:MAX_RETRIES) { [int]$env:MAX_RETRIES } else { 3 }
$Script:BACKOFF_MULTIPLIER = 2

# Checkpoint settings
$Script:CHECKPOINT_ENABLED = if ($env:CHECKPOINT_ENABLED -eq 'false') { $false } else { $true }
$Script:CHECKPOINT_INTERVAL = 50
$Script:CHECKPOINT_FILE = ""

# Rate limiting
$Script:API_DELAY_MS = 50  # 50ms between API calls
$Script:SEARCH_POLL_INTERVAL = 1
$Script:CURRENT_DELAY_MS = $Script:API_DELAY_MS

# Statistics
$Script:STATS_APPS = 0
$Script:STATS_DASHBOARDS = 0
$Script:STATS_ALERTS = 0
$Script:STATS_SAVED_SEARCHES = 0
$Script:STATS_USERS = 0
$Script:STATS_INDEXES = 0
$Script:STATS_API_CALLS = 0
$Script:STATS_API_RETRIES = 0
$Script:STATS_API_FAILURES = 0
$Script:STATS_RATE_LIMITS = 0
$Script:STATS_ERRORS = 0
$Script:STATS_WARNINGS = 0
$Script:STATS_BATCHES = 0

# Timing
$Script:EXPORT_START_TIME = $null
$Script:EXPORT_END_TIME = $null
$Script:SCRIPT_START_TIME = Get-Date

# Error tracking
$Script:ERRORS_LOG = [System.Collections.ArrayList]::new()
$Script:WARNINGS_LOG = [System.Collections.ArrayList]::new()

# Progress tracking state
$Script:PROGRESS_LABEL = ""
$Script:PROGRESS_TOTAL = 0
$Script:PROGRESS_CURRENT = 0
$Script:PROGRESS_START_TIME = $null
$Script:PROGRESS_LAST_PERCENT = 0

# =============================================================================
# APPLY CLI PARAMETER OVERRIDES
# =============================================================================

if ($Stack) {
    $Script:SPLUNK_STACK = $Stack
}
if ($Token) {
    $Script:AUTH_TOKEN = $Token
    $Script:AUTH_METHOD = "token"
}
if ($User) {
    $Script:SPLUNK_USER = $User
    $Script:AUTH_METHOD = "userpass"
}
if ($Password) {
    $Script:SPLUNK_PASSWORD = $Password
}
if ($Apps) {
    $Script:SELECTED_APPS = @($Apps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $Script:EXPORT_ALL_APPS = $false
    $Script:SCOPE_TO_APPS = $true
}
if ($AllApps) {
    $Script:EXPORT_ALL_APPS = $true
    $Script:SCOPE_TO_APPS = $false
}
if ($Output) {
    $Script:OUTPUT_DIR = $Output
}
if ($Rbac) {
    $Script:COLLECT_RBAC = $true
}
if ($Usage) {
    $Script:COLLECT_USAGE = $true
}
if ($Debug_Mode) {
    $Script:DEBUG_MODE = $true
}
if ($NonInteractive) {
    $Script:NON_INTERACTIVE = $true
}
if ($SkipAnonymization) {
    $Script:ANONYMIZE_DATA = $false
}
if ($Proxy) {
    $Script:PROXY_URL = $Proxy
}
if ($ResumeCollect) {
    $Script:RESUME_ARCHIVE = $ResumeCollect
    $Script:RESUME_MODE = $true
}
if ($SkipInternal) {
    $Script:SKIP_INTERNAL = $true
}

# Auto-detect non-interactive mode when all required params are provided
if ($Script:SPLUNK_STACK -and ($Script:AUTH_TOKEN -or ($Script:SPLUNK_USER -and $Script:SPLUNK_PASSWORD))) {
    $Script:NON_INTERACTIVE = $true
}

# =============================================================================
# TLS CERTIFICATE BYPASS CONFIGURATION
# =============================================================================
# Splunk Cloud uses self-signed or internal certificates on port 8089.
# We need to bypass certificate validation (equivalent to curl -k).

function Initialize-TlsConfiguration {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

    if (-not $Script:IsPSCore) {
        # PowerShell 5.1: Use ICertificatePolicy
        try {
            Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@ -ErrorAction SilentlyContinue
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
        catch {
            # Type may already be added in this session
            try {
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
            }
            catch {
                Write-Warning "Could not configure TLS certificate bypass. Self-signed certs may cause errors."
            }
        }
    }
    # PowerShell 7+: Uses -SkipCertificateCheck on each Invoke-WebRequest call
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Write to log file
function Write-Log {
    param([string]$Message)
    if ($Script:LOG_FILE -and (Test-Path $Script:LOG_FILE -ErrorAction SilentlyContinue)) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $Script:LOG_FILE -Value "[$timestamp] $Message" -Encoding UTF8
    }
}

# Print success message
function Write-Success {
    param([string]$Message)
    Write-Host "${Script:GREEN}$([char]0x2713)${Script:NC} $Message"
    Write-Log "SUCCESS: $Message"
}

# Print error message
function Write-Error2 {
    param([string]$Message)
    Write-Host "${Script:RED}$([char]0x2717)${Script:NC} $Message"
    Write-Log "ERROR: $Message"
    [void]$Script:ERRORS_LOG.Add($Message)
    $Script:STATS_ERRORS++
}

# Print warning message
function Write-Warning2 {
    param([string]$Message)
    Write-Host "${Script:YELLOW}$([char]0x26A0)${Script:NC} $Message"
    Write-Log "WARNING: $Message"
    [void]$Script:WARNINGS_LOG.Add($Message)
    $Script:STATS_WARNINGS++
}

# Print info message
function Write-Info {
    param([string]$Message)
    Write-Host "${Script:CYAN}$([char]0x2192)${Script:NC} $Message"
    Write-Log "INFO: $Message"
}

# Print progress message
function Write-Progress2 {
    param([string]$Message)
    Write-Host "${Script:BLUE}$([char]0x25D0)${Script:NC} $Message"
    Write-Log "PROGRESS: $Message"
}

# Print a horizontal line
function Write-Line {
    param(
        [string]$Char = [string][char]0x2500,
        [int]$Width = 72
    )
    # Use [string]::new() for PowerShell 5.1 compatibility (string multiplication only works in PS 7+)
    Write-Host ([string]::new($Char[0], $Width))
}

# Print a box header
function Write-BoxHeader {
    param([string]$Title)
    $width = 72
    $padding = [math]::Max(0, [math]::Floor(($width - $Title.Length - 4) / 2))
    $rightPad = [math]::Max(0, $width - $padding - $Title.Length - 4)
    # Use [string]::new() for PowerShell 5.1 compatibility
    $hLine = [string]::new([char]0x2500, $width)
    $padSpaces = [string]::new(' ', $padding)
    $rightSpaces = [string]::new(' ', $rightPad)
    Write-Host ""
    Write-Host "${Script:CYAN}${Script:BOX_TL}${hLine}${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}${padSpaces}  ${Script:BOLD}${Script:WHITE}$Title${Script:NC}  ${rightSpaces}${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}${hLine}${Script:BOX_B}${Script:NC}"
}

# Print a box content line
function Write-BoxLine {
    param([string]$Content)
    $width = 72
    # Strip ANSI codes for length calculation
    $stripped = $Content -replace '\e\[[0-9;]*m', ''
    $padding = [math]::Max(0, $width - $stripped.Length)
    # Use [string]::new() for PowerShell 5.1 compatibility
    $padSpaces = [string]::new(' ', $padding)
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC} $Content${padSpaces}${Script:CYAN}${Script:BOX_V}${Script:NC}"
}

# Print a box footer
function Write-BoxFooter {
    $width = 72
    # Use [string]::new() for PowerShell 5.1 compatibility
    $hLine = [string]::new([char]0x2500, $width)
    Write-Host "${Script:CYAN}${Script:BOX_BL}${hLine}${Script:BOX_BR}${Script:NC}"
}

# Print an info box with multiple lines
function Write-InfoBox {
    param(
        [string]$Title,
        [string[]]$Lines
    )
    Write-BoxHeader $Title
    foreach ($line in $Lines) {
        Write-BoxLine $line
    }
    Write-BoxFooter
}

# Print why box
function Write-WhyBox {
    param([string[]]$Lines)
    $title = "WHY WE ASK"
    # Use [string]::new() for PowerShell 5.1 compatibility
    $hLine = [string]::new([char]0x2500, 68)
    $titlePad = [string]::new(' ', 57)
    Write-Host ""
    Write-Host "  ${Script:MAGENTA}$([char]0x250C)${hLine}$([char]0x2510)${Script:NC}"
    Write-Host "  ${Script:MAGENTA}${Script:BOX_V}${Script:NC} ${Script:BOLD}${Script:MAGENTA}$title${Script:NC}${titlePad}${Script:MAGENTA}${Script:BOX_V}${Script:NC}"
    Write-Host "  ${Script:MAGENTA}$([char]0x251C)${hLine}$([char]0x2524)${Script:NC}"
    foreach ($line in $Lines) {
        $stripped = $line -replace '\e\[[0-9;]*m', ''
        $padding = [math]::Max(0, 66 - $stripped.Length)
        $padSpaces = [string]::new(' ', $padding)
        Write-Host "  ${Script:MAGENTA}$([char]0x2502)${Script:NC}  $line${padSpaces}${Script:MAGENTA}$([char]0x2502)${Script:NC}"
    }
    Write-Host "  ${Script:MAGENTA}$([char]0x2514)${hLine}$([char]0x2518)${Script:NC}"
}

# Print recommendation
function Write-Recommendation {
    param([string]$Text)
    Write-Host ""
    Write-Host "  ${Script:GREEN}$([char]0x1F4A1) RECOMMENDATION: ${Script:NC}$Text"
}

# Prompt for yes/no with default
function Read-YesNo {
    param(
        [string]$Prompt,
        [string]$Default = "Y"
    )

    if ($Script:NON_INTERACTIVE) {
        Write-Host "${Script:DIM}[AUTO] ${Prompt}: ${Default}${Script:NC}"
        if ($Default -match '^[Yy]') { return $true } else { return $false }
    }

    if ($Default -eq "Y") {
        $suffix = "(Y/n)"
    } else {
        $suffix = "(y/N)"
    }

    Write-Host -NoNewline "${Script:YELLOW}${Prompt} ${suffix}: ${Script:NC}"
    $answer = Read-Host
    if (-not $answer) { $answer = $Default }

    return ($answer -match '^[Yy]')
}

# Prompt for input
function Read-Input {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    if ($Default) {
        Write-Host -NoNewline "${Script:YELLOW}${Prompt} [${Default}]: ${Script:NC}"
    } else {
        Write-Host -NoNewline "${Script:YELLOW}${Prompt}: ${Script:NC}"
    }

    $result = Read-Host
    if (-not $result -and $Default) { $result = $Default }

    return $result
}

# Prompt for password (hidden input)
function Read-Password {
    param([string]$Prompt)
    Write-Host -NoNewline "${Script:YELLOW}${Prompt}: ${Script:NC}"
    $secure = Read-Host -AsSecureString
    # Convert SecureString back to plain text
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# URL encode a string
function ConvertTo-UrlEncoded {
    param([string]$Value)
    return [System.Uri]::EscapeDataString($Value)
}

# Sanitize a filename
function ConvertTo-SafeFilename {
    param([string]$Name)
    return ($Name -replace '[^a-zA-Z0-9_\-]', '_')
}

# =============================================================================
# PROGRESS TRACKING FUNCTIONS
# =============================================================================

function Initialize-Progress {
    param(
        [string]$Label,
        [int]$Total
    )
    $Script:PROGRESS_LABEL = $Label
    $Script:PROGRESS_TOTAL = $Total
    $Script:PROGRESS_CURRENT = 0
    $Script:PROGRESS_LAST_PERCENT = 0
    $Script:PROGRESS_START_TIME = Get-Date
    Write-Host "${Script:CYAN}${Script:PROGRESS_LABEL}${Script:NC} [0/${Script:PROGRESS_TOTAL}]"
}

function Update-Progress {
    param([int]$Current)
    $Script:PROGRESS_CURRENT = $Current
    $percent = 0
    $elapsed = ((Get-Date) - $Script:PROGRESS_START_TIME).TotalSeconds
    $eta = "calculating..."

    if ($Script:PROGRESS_TOTAL -gt 0) {
        $percent = [math]::Floor(($Script:PROGRESS_CURRENT * 100) / $Script:PROGRESS_TOTAL)
    }

    # Only print at 5% intervals
    $interval = 5
    $rounded = [math]::Floor($percent / $interval) * $interval
    if ($rounded -eq $Script:PROGRESS_LAST_PERCENT -and $percent -lt 100) { return }
    $Script:PROGRESS_LAST_PERCENT = $rounded

    # Calculate ETA
    if ($elapsed -gt 0 -and $Script:PROGRESS_CURRENT -gt 0) {
        $rate = $Script:PROGRESS_CURRENT / $elapsed
        if ($rate -gt 0) {
            $remaining = $Script:PROGRESS_TOTAL - $Script:PROGRESS_CURRENT
            $etaSeconds = [math]::Floor($remaining / $rate)
            if ($etaSeconds -lt 60) {
                $eta = "${etaSeconds}s"
            } elseif ($etaSeconds -lt 3600) {
                $m = [math]::Floor($etaSeconds / 60)
                $s = $etaSeconds % 60
                $eta = "${m}m ${s}s"
            } else {
                $h = [math]::Floor($etaSeconds / 3600)
                $m = [math]::Floor(($etaSeconds % 3600) / 60)
                $eta = "${h}h ${m}m"
            }
        }
    }

    # Build progress bar
    $barWidth = 30
    $filled = [math]::Floor(($percent * $barWidth) / 100)
    $empty = $barWidth - $filled
    # Use [string]::new() for PowerShell 5.1 compatibility
    $filledBar = if ($filled -gt 0) { [string]::new([char]0x2588, $filled) } else { "" }
    $emptyBar = if ($empty -gt 0) { [string]::new([char]0x2591, $empty) } else { "" }
    $bar = $filledBar + $emptyBar

    Write-Host "${Script:CYAN}$([char]0x2502)${Script:NC} ${Script:GREEN}${bar}${Script:NC} ${percent}% [${Script:PROGRESS_CURRENT}/${Script:PROGRESS_TOTAL}] ${Script:GRAY}ETA: ${eta}${Script:NC}"
}

function Complete-Progress {
    $elapsed = [math]::Floor(((Get-Date) - $Script:PROGRESS_START_TIME).TotalSeconds)
    $rate = "N/A"
    if ($elapsed -gt 0 -and $Script:PROGRESS_TOTAL -gt 0) {
        $rate = [math]::Round($Script:PROGRESS_TOTAL / $elapsed, 1)
    }
    Write-Host "${Script:GREEN}$([char]0x2713)${Script:NC} ${Script:PROGRESS_LABEL}: ${Script:PROGRESS_TOTAL} items in ${elapsed}s (${rate}/sec)"
}

# Show scale warning for large environments
function Show-ScaleWarning {
    param(
        [string]$ItemType,
        [int]$Count,
        [int]$Threshold
    )
    if ($Count -gt $Threshold) {
        Write-Host ""
        Write-Host "  ${Script:YELLOW}$([char]0x26A0) SCALE WARNING${Script:NC}"
        Write-Host "  Found ${Script:WHITE}$Count $ItemType${Script:NC} (threshold: $Threshold)"
        Write-Host "  This collection step may take several minutes..."
        Write-Host ""
    }
}

# =============================================================================
# DEBUG LOGGING FUNCTIONS
# =============================================================================

function Initialize-DebugLog {
    if (-not $Script:DEBUG_MODE) { return }

    $Script:DEBUG_LOG_FILE = Join-Path ($Script:EXPORT_DIR -replace '^$', $env:TEMP) "export_debug.log"
    $header = @(
        "==============================================================================="
        "DMA Cloud Export Debug Log (PowerShell)"
        "Started: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')"
        "Script Version: $Script:SCRIPT_VERSION"
        "==============================================================================="
        ""
    )
    [System.IO.File]::WriteAllLines($Script:DEBUG_LOG_FILE, $header, $Script:UTF8NoBOM)

    Write-DebugLog "ENV" "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-DebugLog "ENV" "OS: $([System.Environment]::OSVersion.VersionString)"
    Write-DebugLog "ENV" "Hostname: $([System.Net.Dns]::GetHostName())"
    Write-DebugLog "ENV" "User: $([System.Environment]::UserName)"
    Write-DebugLog "ENV" "PWD: $(Get-Location)"
    Write-DebugLog "ENV" "Splunk Stack: $Script:SPLUNK_STACK"

    Write-Host "${Script:CYAN}[DEBUG] Debug logging enabled -> $Script:DEBUG_LOG_FILE${Script:NC}"
}

function Write-DebugLog {
    param(
        [string]$Category = "INFO",
        [string]$Message
    )
    if (-not $Script:DEBUG_MODE) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($Script:DEBUG_LOG_FILE -and (Test-Path (Split-Path $Script:DEBUG_LOG_FILE -Parent) -ErrorAction SilentlyContinue)) {
        Add-Content -Path $Script:DEBUG_LOG_FILE -Value "[$timestamp] [$Category] $Message" -Encoding UTF8
    }

    # Console output with color coding
    switch ($Category) {
        "ERROR"  { Write-Host "${Script:RED}[DEBUG:$Category] $Message${Script:NC}" }
        "WARN"   { Write-Host "${Script:YELLOW}[DEBUG:$Category] $Message${Script:NC}" }
        "API"    { Write-Host "${Script:CYAN}[DEBUG:$Category] $Message${Script:NC}" }
        "SEARCH" { Write-Host "${Script:MAGENTA}[DEBUG:$Category] $Message${Script:NC}" }
        "TIMING" { Write-Host "${Script:BLUE}[DEBUG:$Category] $Message${Script:NC}" }
        default  { Write-Host "${Script:GRAY}[DEBUG:$Category] $Message${Script:NC}" }
    }
}

function Write-DebugApiCall {
    param(
        [string]$Method,
        [string]$Url,
        [string]$HttpCode,
        [string]$ResponseSize = "unknown",
        [string]$DurationMs = "unknown"
    )
    if (-not $Script:DEBUG_MODE) { return }

    # Redact sensitive parts
    $safeUrl = $Url -replace 'password=[^&]*', 'password=REDACTED' -replace 'token=[^&]*', 'token=REDACTED'
    Write-DebugLog "API" "$Method $safeUrl -> HTTP $HttpCode (${ResponseSize} bytes, ${DurationMs}ms)"
}

function Write-DebugSearchJob {
    param(
        [string]$Action,
        [string]$Sid,
        [string]$Details = ""
    )
    if (-not $Script:DEBUG_MODE) { return }
    Write-DebugLog "SEARCH" "[$Action] sid=$Sid $Details"
}

function Write-DebugTiming {
    param(
        [string]$Operation,
        [double]$DurationSeconds
    )
    if (-not $Script:DEBUG_MODE) { return }
    Write-DebugLog "TIMING" "$Operation completed in ${DurationSeconds}s"
}

function Write-DebugConfigState {
    if (-not $Script:DEBUG_MODE) { return }
    Write-DebugLog "CONFIG" "SPLUNK_STACK=$Script:SPLUNK_STACK"
    Write-DebugLog "CONFIG" "SPLUNK_URL=$Script:SPLUNK_URL"
    Write-DebugLog "CONFIG" "AUTH_METHOD=$Script:AUTH_METHOD"
    Write-DebugLog "CONFIG" "EXPORT_ALL_APPS=$Script:EXPORT_ALL_APPS"
    Write-DebugLog "CONFIG" "SCOPE_TO_APPS=$Script:SCOPE_TO_APPS"
    Write-DebugLog "CONFIG" "COLLECT_RBAC=$Script:COLLECT_RBAC"
    Write-DebugLog "CONFIG" "COLLECT_USAGE=$Script:COLLECT_USAGE"
    Write-DebugLog "CONFIG" "COLLECT_INDEXES=$Script:COLLECT_INDEXES"
    Write-DebugLog "CONFIG" "USAGE_PERIOD=$Script:USAGE_PERIOD"
    Write-DebugLog "CONFIG" "SELECTED_APPS=($($Script:SELECTED_APPS -join ', '))"
    Write-DebugLog "CONFIG" "BATCH_SIZE=$Script:BATCH_SIZE"
    Write-DebugLog "CONFIG" "API_TIMEOUT=$Script:API_TIMEOUT"
    Write-DebugLog "CONFIG" "SKIP_INTERNAL=$Script:SKIP_INTERNAL"
}

function Complete-DebugLog {
    if (-not $Script:DEBUG_MODE -or -not $Script:DEBUG_LOG_FILE) { return }
    $footer = @(
        ""
        "==============================================================================="
        "Export Completed: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')"
        "Total Errors: $Script:STATS_ERRORS"
        "Total API Calls: $Script:STATS_API_CALLS"
        "Total Retries: $Script:STATS_API_RETRIES"
        "==============================================================================="
    )
    Add-Content -Path $Script:DEBUG_LOG_FILE -Value ($footer -join "`n") -Encoding UTF8
    Write-Host "${Script:GREEN}[DEBUG] Debug log saved to: $Script:DEBUG_LOG_FILE${Script:NC}"
}

# =============================================================================
# JSON HELPER FUNCTIONS (Native PowerShell - replaces Python/jq)
# =============================================================================

# Write JSON to file with BOM-free UTF-8 encoding and depth 20
function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    $json = $Data | ConvertTo-Json -Depth 20 -Compress:$false
    [System.IO.File]::WriteAllText($Path, $json, $Script:UTF8NoBOM)
}

# Read JSON from file safely
function Read-JsonFile {
    param(
        [string]$Path,
        [object]$Default = $null
    )
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) {
        return $Default
    }
    try {
        $content = [System.IO.File]::ReadAllText($Path, $Script:UTF8NoBOM)
        return ($content | ConvertFrom-Json)
    }
    catch {
        return $Default
    }
}

# Get nested property from a PSObject (replaces json_value / json_get)
function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Path
    )
    if ($null -eq $Object) { return $null }

    $path = $Path.TrimStart('.')
    $parts = $path -split '\.'

    $current = $Object
    foreach ($part in $parts) {
        if (-not $part) { continue }

        if ($part -match '^\d+$') {
            # Array index
            $idx = [int]$part
            if ($current -is [array] -and $idx -lt $current.Count) {
                $current = $current[$idx]
            } else {
                return $null
            }
        } else {
            # Property access - handle hyphenated property names
            try {
                $current = $current.$part
            }
            catch {
                try {
                    $current = $current.PSObject.Properties[$part].Value
                }
                catch {
                    return $null
                }
            }
            if ($null -eq $current) { return $null }
        }
    }

    return $current
}

# Count entries in a JSON array (replaces json_length)
function Get-JsonArrayLength {
    param(
        [string]$FilePath,
        [string]$Path = "."
    )
    $data = Read-JsonFile -Path $FilePath
    if ($null -eq $data) { return 0 }

    if ($Path -ne ".") {
        $data = Get-JsonProperty -Object $data -Path $Path
    }

    if ($data -is [array]) {
        return $data.Count
    }
    return 0
}

# Format JSON file (validate + pretty-print) - replaces json_format
function Format-JsonFile {
    param([string]$Path)
    try {
        $content = [System.IO.File]::ReadAllText($Path, $Script:UTF8NoBOM)
        $parsed = $content | ConvertFrom-Json
        $formatted = $parsed | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($Path, $formatted, $Script:UTF8NoBOM)
        return "valid"
    }
    catch {
        return "invalid: $($_.Exception.Message)"
    }
}

# =============================================================================
# API REQUEST FUNCTIONS
# =============================================================================

# Core REST API call with rate limiting, retries, and timeouts
# Equivalent to bash api_call() function
function Invoke-SplunkApi {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet("GET", "POST", "PUT", "DELETE")]
        [string]$Method = "GET",

        [string]$Data = "",

        [switch]$RawResponse
    )

    # =========================================================================
    # BLOCKED ENDPOINT CHECK (v4.2.4)
    # =========================================================================
    foreach ($blocked in $Script:SPLUNK_CLOUD_BLOCKED_ENDPOINTS) {
        if ($Endpoint -like "*$blocked*") {
            Write-Log "INFO: Skipping known-blocked endpoint: $Endpoint"
            Write-DebugLog "API" "Skipped (blocked in Cloud): $Endpoint"
            return @{
                entry = @()
                skipped = $true
                reason = "Endpoint blocked in Splunk Cloud"
            }
        }
    }

    $Script:STATS_API_CALLS++
    Write-DebugLog "API" "-> $Method $Endpoint"

    # Check total runtime limit
    $elapsed = ((Get-Date) - $Script:SCRIPT_START_TIME).TotalSeconds
    if ($elapsed -gt $Script:MAX_TOTAL_TIME) {
        Write-Error2 "Maximum runtime ($Script:MAX_TOTAL_TIME seconds) exceeded. Export incomplete."
        return $null
    }

    # Build URL
    $url = "$Script:SPLUNK_URL$Endpoint"

    # Build auth headers
    $headers = @{}
    if ($Script:SESSION_KEY) {
        $headers["Authorization"] = "Splunk $Script:SESSION_KEY"
    } elseif ($Script:AUTH_TOKEN) {
        $headers["Authorization"] = "Bearer $Script:AUTH_TOKEN"
    }

    # Rate limiting delay
    Start-Sleep -Milliseconds $Script:API_DELAY_MS

    $retries = 0
    $startTime = Get-Date

    while ($retries -lt $Script:MAX_RETRIES) {
        try {
            $params = @{
                Uri             = $url
                Method          = $Method
                Headers         = $headers
                TimeoutSec      = $Script:API_TIMEOUT
                UseBasicParsing = $true
                ErrorAction     = "Stop"
            }

            # PowerShell 7+: add SkipCertificateCheck
            if ($Script:IsPSCore) {
                $params["SkipCertificateCheck"] = $true
            }

            # Proxy support (v4.3.0)
            if ($Script:PROXY_URL) {
                $params["Proxy"] = $Script:PROXY_URL
            }

            if ($Method -eq "GET") {
                # For GET requests, data goes in URL query string (not body)
                if ($Data) {
                    $params.Uri = "${url}?${Data}"
                } else {
                    $params.Uri = "${url}?output_mode=json"
                }
            } else {
                # POST/PUT - data goes in body
                $headers["Content-Type"] = "application/x-www-form-urlencoded"
                $params.Headers = $headers
                if ($Data) {
                    $params["Body"] = $Data
                }
            }

            $response = Invoke-WebRequest @params
            $httpCode = $response.StatusCode
            $responseBody = $response.Content

            $duration = [math]::Floor(((Get-Date) - $startTime).TotalMilliseconds)
            Write-DebugApiCall -Method $Method -Url $Endpoint -HttpCode $httpCode -ResponseSize $responseBody.Length -DurationMs $duration

            # Success
            Write-Log "API call successful: $Method $Endpoint"

            if ($RawResponse) {
                return $responseBody
            }

            # Try to parse as JSON
            try {
                return ($responseBody | ConvertFrom-Json)
            }
            catch {
                return $responseBody
            }
        }
        catch {
            $statusCode = 0
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $duration = [math]::Floor(((Get-Date) - $startTime).TotalMilliseconds)
            Write-DebugApiCall -Method $Method -Url $Endpoint -HttpCode $statusCode -ResponseSize 0 -DurationMs $duration

            switch ($statusCode) {
                0 {
                    # Timeout or connection error
                    Write-DebugLog "WARN" "Timeout/connection error on $Endpoint"
                    $retries++
                    $Script:STATS_API_RETRIES++
                    $delay = $retries * 2
                    Write-Warning2 "Timeout/connection error. Retry $retries/$Script:MAX_RETRIES in ${delay}s"
                    Start-Sleep -Seconds $delay
                }
                429 {
                    # Rate limited
                    Write-DebugLog "WARN" "Rate limited (429) on $Endpoint"
                    $Script:STATS_RATE_LIMITS++
                    $Script:STATS_API_RETRIES++
                    $retries++
                    $waitTime = [math]::Min($retries * $Script:BACKOFF_MULTIPLIER * 2, 60)
                    Write-Warning2 "Rate limited (429). Waiting ${waitTime}s before retry ($retries/$Script:MAX_RETRIES)..."
                    Start-Sleep -Seconds $waitTime
                }
                401 {
                    Write-DebugLog "ERROR" "Auth failed (401) on $Endpoint"
                    $Script:STATS_API_FAILURES++
                    Write-Error2 "Authentication failed (401). Please check your credentials."
                    return $null
                }
                403 {
                    Write-DebugLog "ERROR" "Access forbidden (403) on $Endpoint"
                    $Script:STATS_API_FAILURES++
                    Write-Error2 "Access forbidden (403) for: $Endpoint. Check user capabilities."
                    return $null
                }
                404 {
                    # Check if this is an app-scoped resource query (expected to be empty for some apps)
                    if ($Endpoint -match '/servicesNS/-/[^/]+/(data/ui/views|saved/searches|data/transforms|data/lookups)') {
                        Write-Log "INFO: No resources at $Endpoint (app may have no items of this type)"
                        Write-DebugLog "INFO" "Empty app resource (404): $Endpoint"
                        return @{ entry = @() }
                    } else {
                        Write-DebugLog "WARN" "Not found (404) on $Endpoint"
                        Write-Warning2 "Resource not found (404): $Endpoint"
                        return $null
                    }
                }
                { $_ -in 500, 502, 503 } {
                    Write-DebugLog "WARN" "Server error ($statusCode) on $Endpoint"
                    $retries++
                    $Script:STATS_API_RETRIES++
                    $waitTime = $retries * 2
                    Write-Warning2 "Server error ($statusCode). Retrying in ${waitTime}s ($retries/$Script:MAX_RETRIES)..."
                    Start-Sleep -Seconds $waitTime
                }
                default {
                    $Script:STATS_API_FAILURES++
                    Write-Error2 "Unexpected HTTP $statusCode for: $Endpoint"
                    Write-Log "Error: $($_.Exception.Message)"
                    return $null
                }
            }
        }
    }

    $Script:STATS_API_FAILURES++
    Write-Error2 "Max retries exceeded for: $Endpoint"
    return $null
}

# =============================================================================
# PAGINATED API CALL FUNCTION (v4.0.0)
# =============================================================================

function Invoke-SplunkApiPaginated {
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [Parameter(Mandatory)]
        [string]$Category
    )

    $offset = 0
    $total = 0
    $fetched = 0
    $batchNum = 0

    # First, get total count
    $countResponse = Invoke-SplunkApi -Endpoint $Endpoint -Data "output_mode=json&count=1"
    if ($null -eq $countResponse) {
        Write-Error2 "Failed to get count for $Category"
        return $false
    }

    # Extract total from paging
    $total = 0
    if ($countResponse.paging -and $countResponse.paging.total) {
        $total = [int]$countResponse.paging.total
    }

    if ($total -eq 0) {
        Write-Info "No $Category found"
        return $true
    }

    Write-Info "Fetching $total $Category in batches of $Script:BATCH_SIZE..."
    if (-not (Test-Path $OutputDir)) {
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    }

    while ($offset -lt $total) {
        $batchNum++
        $Script:STATS_BATCHES++
        $batchFile = Join-Path $OutputDir "batch_${batchNum}.json"

        $batchResponse = Invoke-SplunkApi -Endpoint $Endpoint -Data "output_mode=json&count=$Script:BATCH_SIZE&offset=$offset"
        if ($null -eq $batchResponse) {
            Write-Warning2 "Failed to fetch batch $batchNum at offset $offset"
            Save-Checkpoint -Category $Category -Offset $offset -Item $batchNum
            return $false
        }

        Write-JsonFile -Path $batchFile -Data $batchResponse

        $batchCount = 0
        if ($batchResponse.entry) {
            $batchCount = @($batchResponse.entry).Count
        }
        $fetched += $batchCount

        # Progress update
        $percent = [math]::Floor($fetched * 100 / $total)
        Write-Host -NoNewline "`r  Progress: ${percent}% (${fetched}/${total})  "

        # Rate limiting between batches
        Start-Sleep -Milliseconds ([int]($Script:RATE_LIMIT_DELAY * 1000))
        $offset += $Script:BATCH_SIZE

        # Save checkpoint periodically
        if (($batchNum % $Script:CHECKPOINT_INTERVAL) -eq 0) {
            Save-Checkpoint -Category $Category -Offset $offset -Item $batchNum
        }
    }

    Write-Host ""
    Write-Success "Fetched $fetched $Category in $batchNum batches"

    # Merge batches into single file
    Merge-BatchFiles -BatchDir $OutputDir -Category $Category
    return $true
}

# Merge batch JSON files into a single file (replaces Python merge script)
function Merge-BatchFiles {
    param(
        [string]$BatchDir,
        [string]$Category
    )

    Write-Info "Merging batch files for $Category..."

    $mergedFile = Join-Path $BatchDir "${Category}.json"
    $allEntries = [System.Collections.ArrayList]::new()

    $batchFiles = Get-ChildItem -Path $BatchDir -Filter "batch_*.json" | Sort-Object Name
    foreach ($bf in $batchFiles) {
        try {
            $data = Read-JsonFile -Path $bf.FullName
            if ($data -and $data.entry) {
                $entries = @($data.entry)
                foreach ($entry in $entries) {
                    [void]$allEntries.Add($entry)
                }
            }
        }
        catch {
            Write-Warning2 "Failed to read $($bf.Name): $($_.Exception.Message)"
        }
    }

    # Write merged output
    $mergedData = [PSCustomObject]@{
        entry = @($allEntries.ToArray())
        paging = [PSCustomObject]@{ total = $allEntries.Count }
        _batch_info = [PSCustomObject]@{
            total_batches = $batchFiles.Count
            merged = $true
        }
    }

    Write-JsonFile -Path $mergedFile -Data $mergedData

    # Clean up batch files
    foreach ($bf in $batchFiles) {
        Remove-Item -Path $bf.FullName -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Merged $($allEntries.Count) entries from $($batchFiles.Count) batches"
}

# =============================================================================
# CHECKPOINT/RESUME FUNCTIONS (v4.0.0)
# =============================================================================

function Save-Checkpoint {
    param(
        [string]$Category,
        [int]$Offset,
        [string]$Item
    )

    if (-not $Script:CHECKPOINT_ENABLED -or -not $Script:CHECKPOINT_FILE) { return }

    $checkpoint = [PSCustomObject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        category = $Category
        last_offset = $Offset
        last_item = $Item
        stats = [PSCustomObject]@{
            api_calls = $Script:STATS_API_CALLS
            batches = $Script:STATS_BATCHES
            dashboards = $Script:STATS_DASHBOARDS
            alerts = $Script:STATS_ALERTS
        }
    }

    Write-JsonFile -Path $Script:CHECKPOINT_FILE -Data $checkpoint
}

function Restore-Checkpoint {
    if (-not $Script:CHECKPOINT_ENABLED -or -not $Script:CHECKPOINT_FILE) { return $false }
    if (-not (Test-Path $Script:CHECKPOINT_FILE -ErrorAction SilentlyContinue)) { return $false }

    $checkpoint = Read-JsonFile -Path $Script:CHECKPOINT_FILE
    if (-not $checkpoint -or -not $checkpoint.timestamp) { return $false }

    Write-Host ""
    Write-BoxLine "${Script:YELLOW}INCOMPLETE EXPORT DETECTED${Script:NC}"
    Write-Host ""
    Write-Host "  Found checkpoint from: ${Script:CYAN}$($checkpoint.timestamp)${Script:NC}"
    Write-Host "  Last category: ${Script:CYAN}$($checkpoint.category)${Script:NC}"
    Write-Host ""

    $resume = Read-Input -Prompt "  Resume from checkpoint? (Y/n)" -Default "Y"
    if ($resume -match '^[Yy]') {
        return $true
    }
    return $false
}

function Clear-Checkpoint {
    if ($Script:CHECKPOINT_FILE -and (Test-Path $Script:CHECKPOINT_FILE -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $Script:CHECKPOINT_FILE -Force -ErrorAction SilentlyContinue
        Write-Log "Checkpoint cleared"
    }
}

# =============================================================================
# TIMING STATISTICS (v4.0.0)
# =============================================================================

function Show-ExportTimingStats {
    $endTime = Get-Date
    $duration = ($endTime - $Script:SCRIPT_START_TIME).TotalSeconds
    $hours = [math]::Floor($duration / 3600)
    $minutes = [math]::Floor(($duration % 3600) / 60)
    $seconds = [math]::Floor($duration % 60)

    Write-Host ""
    Write-Host "${Script:CYAN}${Script:BOX_TL}$([string]::new($Script:BOX_H, 74))${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                    ${Script:WHITE}EXPORT TIMING STATISTICS${Script:NC}                            ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 74))${Script:BOX_B}${Script:NC}"

    if ($hours -gt 0) {
        $durationStr = "${hours}h ${minutes}m ${seconds}s"
    } elseif ($minutes -gt 0) {
        $durationStr = "$minutes minutes $seconds seconds"
    } else {
        $durationStr = "$seconds seconds"
    }

    Write-Host ("{0}{1}{2}  Total Duration:        {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $durationStr)
    Write-Host ("{0}{1}{2}  API Calls:             {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $Script:STATS_API_CALLS)
    Write-Host ("{0}{1}{2}  API Retries:           {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $Script:STATS_API_RETRIES)
    Write-Host ("{0}{1}{2}  API Failures:          {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $Script:STATS_API_FAILURES)
    Write-Host ("{0}{1}{2}  Rate Limit Hits:       {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $Script:STATS_RATE_LIMITS)
    Write-Host ("{0}{1}{2}  Batches Completed:     {3,-46}{0}{1}{2}" -f $Script:CYAN, $Script:BOX_V, $Script:NC, $Script:STATS_BATCHES)

    Write-Host "${Script:CYAN}${Script:BOX_BL}$([string]::new($Script:BOX_H, 74))${Script:BOX_BR}${Script:NC}"
}

# =============================================================================
# CONNECTIVITY & AUTHENTICATION
# =============================================================================

function Test-SplunkConnectivity {
    param([string]$Url)

    $testUrl = "$Url/services/server/info"
    $hostname = ($Url -replace 'https://', '') -replace ':.*', ''

    Write-Host ""
    Write-Host "${Script:CYAN}${Script:BOX_TL}$([string]::new($Script:BOX_H, 74))${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}CONNECTIVITY TEST - VERBOSE DIAGNOSTICS${Script:NC}                                  ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 74))${Script:BOX_B}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  Target URL: ${Script:WHITE}${testUrl}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  Hostname:   ${Script:WHITE}${hostname}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  Port:       ${Script:WHITE}8089${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_BL}$([string]::new($Script:BOX_H, 74))${Script:BOX_BR}${Script:NC}"
    Write-Host ""

    # =========================================================================
    # STEP 1 & 2: DNS and TCP tests (skipped when proxy is configured)
    # =========================================================================
    if ($Script:PROXY_URL) {
        Write-Host "  ${Script:CYAN}Proxy configured: $($Script:PROXY_URL)${Script:NC}"
        Write-Host "  ${Script:DIM}Skipping direct DNS/TCP tests (traffic goes through proxy)${Script:NC}"
        Write-Host ""
    } else {
        # STEP 1: DNS Resolution Test
        Write-Host "${Script:YELLOW}[STEP 1/3] Testing DNS Resolution...${Script:NC}"
        try {
            $dnsResult = [System.Net.Dns]::GetHostAddresses($hostname)
            if ($dnsResult.Count -gt 0) {
                $dnsIp = $dnsResult[0].IPAddressToString
                Write-Host "  ${Script:GREEN}$([char]0x2713) DNS resolved: $hostname -> $dnsIp${Script:NC}"
            } else {
                Write-Host "  ${Script:RED}$([char]0x2717) DNS FAILED: Cannot resolve $hostname${Script:NC}"
                Write-Error2 "DNS resolution failed for $hostname"
                return $false
            }
        }
        catch {
            Write-Host "  ${Script:RED}$([char]0x2717) DNS FAILED: Cannot resolve $hostname${Script:NC}"
            Write-Host "  ${Script:DIM}Error: $($_.Exception.Message)${Script:NC}"
            Write-Error2 "DNS resolution failed for $hostname"
            return $false
        }
        Write-Host ""

        # STEP 2: TCP Port Connectivity Test
        Write-Host "${Script:YELLOW}[STEP 2/3] Testing TCP Connection to Port 8089...${Script:NC}"
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connectTask = $tcp.ConnectAsync($hostname, 8089)
            if ($connectTask.Wait(10000)) {
                Write-Host "  ${Script:GREEN}$([char]0x2713) TCP port 8089 is OPEN${Script:NC}"
            } else {
                Write-Host "  ${Script:RED}$([char]0x2717) TCP port 8089 is BLOCKED or UNREACHABLE (timeout)${Script:NC}"
                Write-Host ""
                Write-Host "  ${Script:YELLOW}This usually means:${Script:NC}"
                Write-Host "  ${Script:DIM}  - Corporate firewall blocking outbound port 8089${Script:NC}"
                Write-Host "  ${Script:DIM}  - VPN blocking non-standard ports${Script:NC}"
                Write-Host "  ${Script:DIM}  - Network security policy${Script:NC}"
            }
            $tcp.Close()
        }
        catch {
            Write-Host "  ${Script:RED}$([char]0x2717) TCP port 8089 connection failed${Script:NC}"
            Write-Host "  ${Script:DIM}Error: $($_.Exception.Message)${Script:NC}"
        }
        Write-Host ""
    }

    # =========================================================================
    # STEP 3: Full HTTPS Connection Test
    # =========================================================================
    Write-Host "${Script:YELLOW}[STEP 3/3] Testing HTTPS Connection...${Script:NC}"

    $httpCode = 0
    $startTime = Get-Date
    try {
        $webParams = @{
            Uri             = $testUrl
            Method          = "GET"
            TimeoutSec      = 60
            UseBasicParsing = $true
            ErrorAction     = "Stop"
        }
        if ($Script:IsPSCore) {
            $webParams["SkipCertificateCheck"] = $true
        }
        if ($Script:PROXY_URL) {
            $webParams["Proxy"] = $Script:PROXY_URL
        }

        $webResponse = Invoke-WebRequest @webParams
        $httpCode = $webResponse.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            $httpCode = [int]$_.Exception.Response.StatusCode
        } else {
            $httpCode = 0
        }
    }

    $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)

    # =========================================================================
    # RESULTS SUMMARY
    # =========================================================================
    Write-Host "${Script:CYAN}${Script:BOX_TL}$([string]::new($Script:BOX_H, 74))${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}CONNECTION TEST RESULTS${Script:NC}                                                  ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 74))${Script:BOX_B}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  HTTP Response:     ${Script:WHITE}${httpCode}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  Total Time:        ${Script:WHITE}${totalTime}s${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_BL}$([string]::new($Script:BOX_H, 74))${Script:BOX_BR}${Script:NC}"
    Write-Host ""

    # Interpret results
    if ($httpCode -eq 0) {
        Write-Host "${Script:RED}${Script:BOX_TL}$([string]::new($Script:BOX_H, 74))${Script:BOX_TR}${Script:NC}"
        Write-Host "${Script:RED}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:RED}ERROR: Cannot connect to Splunk Cloud instance${Script:NC}"
        Write-Host "${Script:RED}${Script:BOX_V}${Script:NC}  ${Script:DIM}Check network connectivity, firewall rules, and VPN status${Script:NC}"
        Write-Host "${Script:RED}${Script:BOX_BL}$([string]::new($Script:BOX_H, 74))${Script:BOX_BR}${Script:NC}"
        Write-Error2 "Cannot connect to Splunk Cloud instance"
        return $false
    }

    if ($httpCode -in 200, 401) {
        Write-Success "Splunk Cloud instance is reachable (HTTP $httpCode)"
        return $true
    }

    Write-Warning2 "Received HTTP $httpCode from server (may still work with auth)"
    return $true
}

function Connect-SplunkCloud {
    if ($Script:AUTH_METHOD -eq "token") {
        # Token-based auth - verify token works
        try {
            $webParams = @{
                Uri             = "$Script:SPLUNK_URL/services/authentication/current-context?output_mode=json"
                Method          = "GET"
                Headers         = @{ "Authorization" = "Bearer $Script:AUTH_TOKEN" }
                TimeoutSec      = $Script:API_TIMEOUT
                UseBasicParsing = $true
                ErrorAction     = "Stop"
            }
            if ($Script:IsPSCore) {
                $webParams["SkipCertificateCheck"] = $true
            }
            if ($Script:PROXY_URL) {
                $webParams["Proxy"] = $Script:PROXY_URL
            }

            $response = Invoke-WebRequest @webParams
            $data = $response.Content | ConvertFrom-Json

            if ($data.entry -and $data.entry.Count -gt 0) {
                $username = $data.entry[0].content.username
                Write-Success "Token authentication successful (user: $username)"
                return $true
            }
        }
        catch {
            # Fall through to error
        }
        Write-Error2 "Token authentication failed"
        return $false
    }
    else {
        # Username/password - get session key
        try {
            $body = "username=$(ConvertTo-UrlEncoded $Script:SPLUNK_USER)&password=$(ConvertTo-UrlEncoded $Script:SPLUNK_PASSWORD)"
            $webParams = @{
                Uri             = "$Script:SPLUNK_URL/services/auth/login?output_mode=json"
                Method          = "POST"
                Body            = $body
                Headers         = @{ "Content-Type" = "application/x-www-form-urlencoded" }
                TimeoutSec      = $Script:API_TIMEOUT
                UseBasicParsing = $true
                ErrorAction     = "Stop"
            }
            if ($Script:IsPSCore) {
                $webParams["SkipCertificateCheck"] = $true
            }
            if ($Script:PROXY_URL) {
                $webParams["Proxy"] = $Script:PROXY_URL
            }

            $response = Invoke-WebRequest @webParams
            $data = $response.Content | ConvertFrom-Json

            if ($data.sessionKey) {
                $Script:SESSION_KEY = $data.sessionKey
                Write-Success "Password authentication successful"
                return $true
            }
        }
        catch {
            # Fall through to error
        }
        Write-Error2 "Password authentication failed. Check username and password."
        return $false
    }
}

function Test-UserCapabilities {
    $response = Invoke-SplunkApi -Endpoint "/services/authentication/current-context" -Data "output_mode=json"
    if ($null -eq $response) {
        Write-Error2 "Failed to retrieve user capabilities"
        return
    }

    $capabilities = @()
    if ($response.entry -and @($response.entry).Count -gt 0) {
        $entry = @($response.entry)[0]
        if ($entry.content -and $entry.content.capabilities) {
            $capabilities = @($entry.content.capabilities)
        }
    }

    $requiredCaps = @("admin_all_objects", "list_users", "search")
    $missingCaps = @()

    foreach ($cap in $requiredCaps) {
        if ($cap -notin $capabilities) {
            $missingCaps += $cap
        }
    }

    if ($missingCaps.Count -gt 0) {
        Write-Warning2 "Missing recommended capabilities: $($missingCaps -join ', ')"
        Write-Warning2 "Some data may not be collected"
    } else {
        Write-Success "All required capabilities present"
    }
}

# =============================================================================
# BANNER AND INTRODUCTION
# =============================================================================

function Show-Banner {
    # Only clear screen in interactive mode
    if (-not $Script:NON_INTERACTIVE) {
        Clear-Host
    }
    Write-Host ""
    Write-Host "${Script:CYAN}${Script:BOX_TL}$([string]::new($Script:BOX_H, 78))${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:WHITE}$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588)   $([char]0x2588)$([char]0x2588) $([char]0x2588)$([char]0x2588)$([char]0x2588)   $([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588) $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588) $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)  $([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)$([char]0x2588)${Script:NC} ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                   ${Script:BOLD}${Script:MAGENTA}SPLUNK CLOUD EXPORT SCRIPT (PowerShell)${Script:NC}                   ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}          ${Script:DIM}Complete REST API-Based Data Collection for Migration${Script:NC}              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                        ${Script:DIM}Version $Script:SCRIPT_VERSION (PowerShell)${Script:NC}                        ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}   ${Script:DIM}Developed for Dynatrace One by Enterprise Solutions & Architecture${Script:NC}      ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                  ${Script:DIM}An ACE Services Division of Dynatrace${Script:NC}                    ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_BL}$([string]::new($Script:BOX_H, 78))${Script:BOX_BR}${Script:NC}"
    Write-Host ""
}

function Show-Introduction {
    Write-InfoBox "WHAT THIS SCRIPT DOES" @(
        ""
        "This script collects data from your ${Script:BOLD}Splunk Cloud${Script:NC} environment using"
        "the REST API to prepare for migration to Dynatrace Gen3 Grail."
        ""
        "${Script:BOLD}Data Collected:${Script:NC}"
        "  - Dashboards (Classic and Dashboard Studio)"
        "  - Alerts and Saved Searches (with SPL queries)"
        "  - Users, Roles, and RBAC configurations"
        "  - Search Macros, Eventtypes, and Tags"
        "  - Index configurations and statistics"
        "  - Usage analytics (who uses what, how often)"
        "  - Props and Transforms configurations (via REST)"
        ""
        "${Script:BOLD}Output:${Script:NC}"
        "  A .tar.gz archive compatible with the Dynatrace Migration Assistant"
    )

    Write-InfoBox "IMPORTANT: THIS IS FOR SPLUNK CLOUD ONLY" @(
        ""
        "${Script:YELLOW}$([char]0x26A0)  This script works with Splunk Cloud (Classic & Victoria)${Script:NC}"
        ""
        "If you have ${Script:BOLD}Splunk Enterprise${Script:NC} (on-premises), please use:"
        "  ${Script:GREEN}./dma-splunk-export.sh${Script:NC}"
        ""
        "This script uses 100% REST API - no file system access needed."
    )

    Write-Host ""
    if (-not (Read-YesNo "Do you want to continue?")) {
        Write-Host ""
        Write-Info "Export cancelled. Goodbye!"
        exit 0
    }

    Show-PreflightChecklist
}

function Show-PreflightChecklist {
    Write-Host ""
    Write-Host "${Script:CYAN}${Script:BOX_TL}$([string]::new($Script:BOX_H, 78))${Script:BOX_TR}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                     ${Script:BOLD}${Script:WHITE}PRE-FLIGHT CHECKLIST${Script:NC}                                    ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}         ${Script:DIM}Please confirm you have the following before continuing${Script:NC}            ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 78))${Script:BOX_B}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:GREEN}SPLUNK CLOUD ACCESS:${Script:NC}                                                      ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  Splunk Cloud stack URL (e.g., your-company.splunkcloud.com)          ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  Splunk username with admin privileges                                ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  Splunk password OR API token (sc_admin role recommended)             ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:GREEN}NETWORK REQUIREMENTS:${Script:NC}                                                      ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  HTTPS access to your-stack.splunkcloud.com:8089                       ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  No firewall blocking port 8089 to Splunk Cloud                        ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:GREEN}LOCAL SYSTEM REQUIREMENTS:${Script:NC}                                                 ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  PowerShell 5.1+ (Windows PowerShell) or 7+ (PowerShell Core)         ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  tar.exe (built-in on Windows 10 1803+)                               ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    $([char]0x25A1)  ~100MB disk space for export                                         ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 78))${Script:BOX_B}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:GREEN}DATA PRIVACY & SECURITY:${Script:NC}                                                   ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}We do NOT collect or export:${Script:NC}                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:RED}$([char]0x2717)${Script:NC}  User passwords or password hashes                                    ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:RED}$([char]0x2717)${Script:NC}  API tokens or session keys                                           ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:RED}$([char]0x2717)${Script:NC}  Private keys or certificates                                         ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:RED}$([char]0x2717)${Script:NC}  Your actual log data (only metadata/structure)                       ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}We automatically REDACT:${Script:NC}                                                  ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:GREEN}$([char]0x2713)${Script:NC}  password = [REDACTED] in all .conf files                             ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:GREEN}$([char]0x2713)${Script:NC}  secret = [REDACTED] in outputs.conf                                  ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}    ${Script:GREEN}$([char]0x2713)${Script:NC}  pass4SymmKey = [REDACTED] in server.conf                             ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}                                                                              ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_T}$([string]::new($Script:BOX_H, 78))${Script:BOX_B}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}  ${Script:BOLD}${Script:MAGENTA}TIP:${Script:NC} If you don't have all items, you can still proceed - the script     ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_V}${Script:NC}       will verify each requirement and provide specific guidance.          ${Script:CYAN}${Script:BOX_V}${Script:NC}"
    Write-Host "${Script:CYAN}${Script:BOX_BL}$([string]::new($Script:BOX_H, 78))${Script:BOX_BR}${Script:NC}"
    Write-Host ""

    # Quick system check
    Write-Host "  ${Script:BOLD}Quick System Check:${Script:NC}"

    # Check PowerShell version
    Write-Host "    ${Script:GREEN}$([char]0x2713)${Script:NC} PowerShell: $($PSVersionTable.PSVersion)"

    # Check tar.exe
    $tarPath = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tarPath) {
        Write-Host "    ${Script:GREEN}$([char]0x2713)${Script:NC} tar.exe: available ($(tar.exe --version 2>&1 | Select-Object -First 1))"
    } else {
        Write-Host "    ${Script:RED}$([char]0x2717)${Script:NC} tar.exe: NOT FOUND - ${Script:YELLOW}Required for archive creation${Script:NC}"
        Write-Host ""
        Write-Host "    ${Script:BOLD}tar.exe is built into Windows 10 version 1803 and later.${Script:NC}"
        Write-Host "    Please update Windows or ensure tar.exe is in your PATH."
        Write-Host ""
        Write-Host "    ${Script:RED}Cannot continue without tar.exe${Script:NC}"
        exit 1
    }

    Write-Host ""
    if (-not (Read-YesNo "Ready to proceed?")) {
        Write-Host ""
        Write-Info "Export cancelled. Goodbye!"
        exit 0
    }
}

# =============================================================================
# INTERACTIVE WIZARD - STEP 1: SPLUNK CLOUD CONNECTION
# =============================================================================

function Get-SplunkStack {
    Write-BoxHeader "STEP 1: SPLUNK CLOUD CONNECTION"

    Write-WhyBox @(
        "We need to connect to your Splunk Cloud instance via REST API."
        "This is the ${Script:BOLD}only${Script:NC} way to access Splunk Cloud data - there is"
        "no file system or SSH access to Splunk Cloud infrastructure."
        ""
        "The script runs on YOUR machine (laptop, jump host, etc.) and"
        "connects to Splunk Cloud over HTTPS."
    )

    Write-Host ""
    Write-Host "  ${Script:BOLD}Your Splunk Cloud stack URL looks like:${Script:NC}"
    Write-Host "    ${Script:DIM}https://${Script:NC}${Script:GREEN}your-company${Script:NC}${Script:DIM}.splunkcloud.com${Script:NC}"
    Write-Host ""

    # Check for environment variable
    if ($env:SPLUNK_CLOUD_STACK) {
        Write-Host "  ${Script:GREEN}$([char]0x2713)${Script:NC} Found SPLUNK_CLOUD_STACK environment variable: $($env:SPLUNK_CLOUD_STACK)"
        $Script:SPLUNK_STACK = $env:SPLUNK_CLOUD_STACK
    } elseif (-not $Script:SPLUNK_STACK) {
        Write-Host -NoNewline "  ${Script:YELLOW}Enter your Splunk Cloud stack URL: ${Script:NC}"
        $Script:SPLUNK_STACK = Read-Host
    }

    # Clean up the URL
    $Script:SPLUNK_STACK = $Script:SPLUNK_STACK -replace '^https://', '' -replace ':8089$', '' -replace '/$', ''
    $Script:SPLUNK_URL = "https://$($Script:SPLUNK_STACK):8089"

    Write-Host ""
    Write-Progress2 "Testing connection to $Script:SPLUNK_URL..."

    if (-not (Test-SplunkConnectivity $Script:SPLUNK_URL)) {
        Write-Host ""
        Write-InfoBox "CONNECTION TROUBLESHOOTING" @(
            ""
            "Cannot reach your Splunk Cloud instance. Please check:"
            ""
            "  1. Is the URL correct? ${Script:DIM}$Script:SPLUNK_STACK${Script:NC}"
            "  2. Are you on VPN (if required by your company)?"
            "  3. Is your IP address allowlisted in Splunk Cloud?"
            "  4. Can you reach it in a browser?"
            ""
            "To check your public IP: ${Script:GREEN}Invoke-RestMethod ifconfig.me${Script:NC}"
        )
        exit 1
    }

    Write-BoxFooter
}

# =============================================================================
# INTERACTIVE WIZARD - PROXY SETTINGS (v4.3.0)
# =============================================================================

function Get-ProxySettings {
    if ($Script:NON_INTERACTIVE) { return }
    if ($Script:PROXY_URL) { return }  # Already set via -Proxy parameter

    Write-Host ""
    Write-Host -NoNewline "  ${Script:YELLOW}Does your environment require a proxy server to connect to Splunk Cloud? (y/N): ${Script:NC}"
    $proxyAnswer = Read-Host
    if ($proxyAnswer -match '^[Yy]') {
        Write-Host -NoNewline "  ${Script:YELLOW}Enter proxy URL (e.g., http://proxy.company.com:8080): ${Script:NC}"
        $Script:PROXY_URL = Read-Host
        if ($Script:PROXY_URL) {
            Write-Success "Proxy configured: $($Script:PROXY_URL)"
        } else {
            Write-Info "No proxy URL entered - connecting directly"
        }
    } else {
        Write-Info "No proxy required - connecting directly"
    }
    Write-Host ""
}

# =============================================================================
# INTERACTIVE WIZARD - STEP 2: AUTHENTICATION
# =============================================================================

function Get-Authentication {
    Write-BoxHeader "STEP 2: AUTHENTICATION"

    Write-WhyBox @(
        "REST API access requires authentication. You can use:"
        ""
        "  ${Script:BOLD}Option 1: API Token${Script:NC} (Recommended)"
        "    - More secure - limited scope, can be revoked"
        "    - Works with MFA-enabled accounts"
        "    - Create in Splunk Cloud: Settings -> Tokens"
        ""
        "  ${Script:BOLD}Option 2: Username/Password${Script:NC}"
        "    - Your regular Splunk Cloud login"
        "    - May not work if MFA is enforced"
    )

    Write-Host ""
    Write-Host "  ${Script:BOLD}Required Permissions:${Script:NC}"
    Write-Host "    - admin_all_objects - Access all knowledge objects"
    Write-Host "    - list_users, list_roles - Access RBAC data"
    Write-Host "    - search - Run analytics queries"
    Write-Host ""
    Write-Host "  ${Script:DIM}Security: Your credentials are used locally only and are NEVER stored,${Script:NC}"
    Write-Host "  ${Script:DIM}logged, or transmitted outside of this session. They are cleared on exit.${Script:NC}"
    Write-Host ""

    # Check for environment variables
    if ($env:SPLUNK_CLOUD_TOKEN) {
        Write-Host "  ${Script:GREEN}$([char]0x2713)${Script:NC} Found SPLUNK_CLOUD_TOKEN environment variable"
        $Script:AUTH_METHOD = "token"
        $Script:AUTH_TOKEN = $env:SPLUNK_CLOUD_TOKEN
    } elseif (-not $Script:AUTH_METHOD) {
        Write-Host "  ${Script:BOLD}Choose authentication method:${Script:NC}"
        Write-Host ""
        Write-Host "    ${Script:GREEN}1${Script:NC}) API Token ${Script:DIM}(recommended)${Script:NC}"
        Write-Host "    ${Script:GREEN}2${Script:NC}) Username/Password"
        Write-Host ""
        Write-Host -NoNewline "  ${Script:YELLOW}Select option [1]: ${Script:NC}"
        $authChoice = Read-Host
        if (-not $authChoice) { $authChoice = "1" }

        Write-Host ""

        if ($authChoice -eq "2") {
            $Script:AUTH_METHOD = "userpass"
            Write-Host -NoNewline "  ${Script:YELLOW}Enter username: ${Script:NC}"
            $Script:SPLUNK_USER = Read-Host
            $Script:SPLUNK_PASSWORD = Read-Password "  Enter password"
        } else {
            $Script:AUTH_METHOD = "token"
            Write-Host -NoNewline "  ${Script:YELLOW}Enter API token: ${Script:NC}"
            $secure = Read-Host -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $Script:AUTH_TOKEN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    Write-Host ""
    Write-Progress2 "Testing authentication..."

    if (-not (Connect-SplunkCloud)) {
        Write-Host ""
        Write-InfoBox "AUTHENTICATION FAILED" @(
            ""
            "Could not authenticate to Splunk Cloud. Please check:"
            ""
            "  - Credentials are correct"
            "  - API token has not expired"
            "  - Account is not locked"
            "  - User has required capabilities"
            ""
            "To create an API token:"
            "  1. Log into Splunk Cloud web UI"
            "  2. Click Settings (gear) -> Tokens"
            "  3. Create new token with required permissions"
        )
        exit 1
    }

    Write-Host ""
    Write-Progress2 "Checking user capabilities..."
    Test-UserCapabilities

    Write-BoxFooter
}

# =============================================================================
# INTERACTIVE WIZARD - STEP 3: ENVIRONMENT DETECTION
# =============================================================================

function Find-SplunkEnvironment {
    Write-BoxHeader "STEP 3: ENVIRONMENT DETECTION"

    Write-Progress2 "Detecting Splunk Cloud environment..."

    $serverInfo = Invoke-SplunkApi -Endpoint "/services/server/info" -Data "output_mode=json"
    if ($null -eq $serverInfo) {
        Write-Error2 "Failed to retrieve server information"
        return $false
    }

    # Parse server info
    $entry = @($serverInfo.entry)[0]
    $Script:SPLUNK_VERSION = $entry.content.version
    $Script:SERVER_GUID = $entry.content.guid
    $serverName = $entry.content.serverName
    $osName = $entry.content.os_name
    $cpuArch = $entry.content.cpu_arch

    # Detect cloud type
    if ($Script:SPLUNK_VERSION -match 'cloud') {
        $Script:CLOUD_TYPE = "victoria"
    } elseif ($serverName -match 'sh|search') {
        $Script:CLOUD_TYPE = "victoria"
    } else {
        $Script:CLOUD_TYPE = "classic_or_victoria"
    }

    # Get app count
    $appsResponse = Invoke-SplunkApi -Endpoint "/services/apps/local" -Data "output_mode=json&count=0"
    $appCount = 0
    if ($appsResponse -and $appsResponse.entry) {
        $appCount = @($appsResponse.entry).Count
    }

    # Get user count
    $usersResponse = Invoke-SplunkApi -Endpoint "/services/authentication/users" -Data "output_mode=json&count=0"
    $userCount = 0
    if ($usersResponse -and $usersResponse.entry) {
        $userCount = @($usersResponse.entry).Count
    }

    # Use [string]::new() for PowerShell 5.1 compatibility
    $hLine = [string]::new([char]0x2500, 68)
    Write-Host ""
    Write-Host "  $([char]0x250C)${hLine}$([char]0x2510)"
    Write-Host "  $([char]0x2502) ${Script:BOLD}Detected Environment:${Script:NC}$([string]::new(' ', 46))$([char]0x2502)"
    Write-Host "  $([char]0x251C)${hLine}$([char]0x2524)"
    Write-Host ("  $([char]0x2502)   Stack:      ${Script:GREEN}{0}${Script:NC}{1}$([char]0x2502)" -f $Script:SPLUNK_STACK, ([string]::new(' ', [math]::Max(0, 40 - $Script:SPLUNK_STACK.Length))))
    Write-Host ("  $([char]0x2502)   Type:       ${Script:GREEN}Splunk Cloud ({0})${Script:NC}{1}$([char]0x2502)" -f $Script:CLOUD_TYPE, ([string]::new(' ', [math]::Max(0, 29 - $Script:CLOUD_TYPE.Length))))
    Write-Host ("  $([char]0x2502)   Version:    ${Script:GREEN}{0}${Script:NC}{1}$([char]0x2502)" -f $Script:SPLUNK_VERSION, ([string]::new(' ', [math]::Max(0, 40 - $Script:SPLUNK_VERSION.Length))))
    $guidDisplay = if ($Script:SERVER_GUID.Length -gt 25) { $Script:SERVER_GUID.Substring(0, 25) + "..." } else { $Script:SERVER_GUID }
    Write-Host "  $([char]0x2502)   GUID:       ${Script:GREEN}${guidDisplay}${Script:NC}$([string]::new(' ', [math]::Max(0, 37 - $guidDisplay.Length)))$([char]0x2502)"
    Write-Host ("  $([char]0x2502)   Apps:       ${Script:GREEN}{0} installed${Script:NC}{1}$([char]0x2502)" -f $appCount, ([string]::new(' ', [math]::Max(0, 36 - $appCount.ToString().Length))))
    Write-Host ("  $([char]0x2502)   Users:      ${Script:GREEN}{0}${Script:NC}{1}$([char]0x2502)" -f $userCount, ([string]::new(' ', [math]::Max(0, 45 - $userCount.ToString().Length))))
    Write-Host "  $([char]0x2514)${hLine}$([char]0x2518)"

    Write-Host ""
    if (-not (Read-YesNo "  Is this the correct environment?")) {
        Write-Host ""
        Write-Info "Please restart and enter the correct stack URL"
        exit 0
    }

    Write-BoxFooter
    return $true
}

# =============================================================================
# INTERACTIVE WIZARD - STEP 4: APPLICATION SELECTION
# =============================================================================

function Select-Applications {
    Write-BoxHeader "STEP 4: APPLICATION SELECTION"

    # If apps were pre-selected via -Apps flag, skip interactive selection
    if (-not $Script:EXPORT_ALL_APPS -and $Script:SELECTED_APPS.Count -gt 0) {
        Write-Success "Using pre-selected apps from -Apps flag: $($Script:SELECTED_APPS -join ', ')"
        $Script:STATS_APPS = $Script:SELECTED_APPS.Count
        Write-BoxFooter
        return
    }

    Write-WhyBox @(
        "Splunk organizes content into 'apps'. Each app can contain:"
        "  - Dashboards and visualizations"
        "  - Saved searches and alerts"
        "  - Macros, eventtypes, tags"
        "  - Field extractions and lookups"
        ""
        "You can export ALL apps or select specific ones."
        "System apps (like 'search', 'launcher') are always included."
    )

    Write-Recommendation "Export ALL apps for complete migration analysis"

    # Get list of apps
    Write-Progress2 "Retrieving app list..."
    $appsResponse = Invoke-SplunkApi -Endpoint "/services/apps/local" -Data "output_mode=json&count=0"

    if ($null -eq $appsResponse) {
        Write-Error2 "Failed to retrieve app list"
        return
    }

    # Parse app names
    $allApps = @()
    if ($appsResponse.entry) {
        foreach ($entry in @($appsResponse.entry)) {
            $allApps += $entry.name
        }
    }

    # Filter out Splunk internal/system apps
    $filteredApps = @()
    foreach ($appName in $allApps) {
        # Skip internal apps (start with _)
        if ($appName -match '^_') { continue }
        # Skip Splunk's own system apps
        if ($appName -match '^[Ss]plunk_') { continue }
        # Skip Splunk Support Add-ons
        if ($appName -match '^SA-') { continue }
        # Skip framework/system/default apps
        if ($appName -match '^(framework|appsbrowser|introspection_generator_addon|legacy|learned|sample_app|gettingstarted|launcher|search|SplunkForwarder|SplunkLightForwarder|alert_logevent|alert_webhook)$') { continue }
        $filteredApps += $appName
    }

    $totalApps = $filteredApps.Count

    Write-Host ""
    Write-Host "  ${Script:BOLD}Found $totalApps apps. Choose export scope:${Script:NC}"
    Write-Host ""
    Write-Host "    ${Script:GREEN}1${Script:NC}) Export ALL applications ${Script:DIM}(recommended for complete analysis)${Script:NC}"
    Write-Host "    ${Script:GREEN}2${Script:NC}) Enter specific app names ${Script:DIM}(comma-separated)${Script:NC}"
    Write-Host "    ${Script:GREEN}3${Script:NC}) Select from numbered list"
    Write-Host "    ${Script:GREEN}4${Script:NC}) System apps only ${Script:DIM}(minimal export)${Script:NC}"
    Write-Host ""
    Write-Host -NoNewline "  ${Script:YELLOW}Select option [1]: ${Script:NC}"
    $appChoice = Read-Host
    if (-not $appChoice) { $appChoice = "1" }

    switch ($appChoice) {
        "1" {
            $Script:EXPORT_ALL_APPS = $true
            $Script:SELECTED_APPS = $filteredApps
            Write-Success "Will export ALL $totalApps applications"
        }
        "2" {
            Write-Host ""
            $preview = ($filteredApps | Select-Object -First 10) -join ", "
            Write-Host "  ${Script:DIM}Available apps: ${preview}...${Script:NC}"
            Write-Host ""
            Write-Host -NoNewline "  ${Script:YELLOW}Enter app names (comma-separated): ${Script:NC}"
            $appList = Read-Host
            $inputApps = $appList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

            $Script:SELECTED_APPS = @()
            foreach ($app in $inputApps) {
                if ($app -in $filteredApps) {
                    $Script:SELECTED_APPS += $app
                } else {
                    Write-Warning2 "App not found: $app"
                }
            }

            if ($Script:SELECTED_APPS.Count -eq 0) {
                Write-Error2 "No valid apps selected"
                return
            }

            $Script:EXPORT_ALL_APPS = $false
            Write-Success "Selected $($Script:SELECTED_APPS.Count) applications"
        }
        "3" {
            Write-Host ""
            Write-Host "  ${Script:BOLD}Available Applications:${Script:NC}"
            Write-Host ""
            for ($i = 0; $i -lt $filteredApps.Count; $i++) {
                Write-Host ("    {0,3}) {1}" -f ($i + 1), $filteredApps[$i])
            }

            Write-Host ""
            Write-Host -NoNewline "  ${Script:YELLOW}Enter numbers (comma-separated, e.g., 1,3,5-8): ${Script:NC}"
            $selection = Read-Host

            $Script:SELECTED_APPS = @()
            $parts = $selection -split ','
            foreach ($part in $parts) {
                $part = $part.Trim()
                if ($part -match '^(\d+)-(\d+)$') {
                    $start = [int]$Matches[1]
                    $end = [int]$Matches[2]
                    for ($n = $start; $n -le $end; $n++) {
                        if ($n -ge 1 -and $n -le $totalApps) {
                            $Script:SELECTED_APPS += $filteredApps[$n - 1]
                        }
                    }
                } elseif ($part -match '^\d+$') {
                    $num = [int]$part
                    if ($num -ge 1 -and $num -le $totalApps) {
                        $Script:SELECTED_APPS += $filteredApps[$num - 1]
                    }
                }
            }

            if ($Script:SELECTED_APPS.Count -eq 0) {
                Write-Error2 "No valid apps selected"
                return
            }

            $Script:EXPORT_ALL_APPS = $false
            Write-Success "Selected $($Script:SELECTED_APPS.Count) applications"
        }
        "4" {
            $Script:SELECTED_APPS = @("search", "launcher", "learned", "splunk_httpinput", "splunk_internal_metrics")
            $Script:EXPORT_ALL_APPS = $false
            Write-Success "Selected system apps only"
        }
        default {
            $Script:EXPORT_ALL_APPS = $true
            $Script:SELECTED_APPS = $filteredApps
            Write-Success "Will export ALL $totalApps applications"
        }
    }

    $Script:STATS_APPS = $Script:SELECTED_APPS.Count

    Write-BoxFooter
}

# =============================================================================
# INTERACTIVE WIZARD - STEP 5: DATA CATEGORIES
# =============================================================================

function Select-DataCategories {
    Write-BoxHeader "STEP 5: DATA CATEGORIES"

    Write-WhyBox @(
        "You can customize which data categories to collect."
        ""
        "Different data helps with different migration aspects:"
        "  - ${Script:BOLD}Dashboards${Script:NC}: Visual migration planning"
        "  - ${Script:BOLD}Alerts${Script:NC}: Monitoring continuity"
        "  - ${Script:BOLD}Users/RBAC${Script:NC}: Permission mapping"
        "  - ${Script:BOLD}Usage${Script:NC}: Prioritize high-value content"
        ""
        "${Script:YELLOW}Note: Some data may be limited due to Cloud restrictions${Script:NC}"
    )

    Write-Recommendation "Accept defaults for comprehensive analysis"

    Write-Host ""
    Write-Host "  ${Script:BOLD}Select data categories to collect:${Script:NC}"
    Write-Host ""

    # Display category toggles
    $categories = @(
        @{ Num = "1"; Name = "Configurations"; Var = "COLLECT_CONFIGS"; Desc = "(via REST - reconstructed from API)" }
        @{ Num = "2"; Name = "Dashboards"; Var = "COLLECT_DASHBOARDS"; Desc = "(Classic + Dashboard Studio)" }
        @{ Num = "3"; Name = "Alerts & Saved Searches"; Var = "COLLECT_ALERTS"; Desc = "" }
        @{ Num = "4"; Name = "Users & RBAC"; Var = "COLLECT_RBAC"; Desc = "(global user/role data - use -Rbac to enable)" }
        @{ Num = "5"; Name = "Usage Analytics"; Var = "COLLECT_USAGE"; Desc = "(requires _audit - often blocked in Cloud)" }
        @{ Num = "6"; Name = "Index Statistics"; Var = "COLLECT_INDEXES"; Desc = "" }
        @{ Num = "7"; Name = "Lookup Contents"; Var = "COLLECT_LOOKUPS"; Desc = "(may be large)" }
        @{ Num = "8"; Name = "Anonymize Data"; Var = "ANONYMIZE_DATA"; Desc = "(emails->fake, hosts->fake, IPs->redacted)" }
    )

    foreach ($cat in $categories) {
        $currentVal = (Get-Variable -Name $cat.Var -Scope Script).Value
        if ($currentVal) {
            Write-Host "    ${Script:GREEN}[$([char]0x2713)]${Script:NC} $($cat.Num). $($cat.Name) ${Script:DIM}$($cat.Desc)${Script:NC}"
        } else {
            Write-Host "    ${Script:RED}[ ]${Script:NC} $($cat.Num). $($cat.Name) ${Script:DIM}$($cat.Desc)${Script:NC}"
        }
    }

    Write-Host ""
    Write-Host "  ${Script:DIM}Privacy: User data includes names/roles only. Passwords are NEVER collected.${Script:NC}"
    Write-Host "  ${Script:CYAN}Tips:${Script:NC}"
    Write-Host "  ${Script:DIM}   - Options 4 (RBAC) and 5 (Usage) are OFF by default for faster exports${Script:NC}"
    Write-Host "  ${Script:DIM}   - Option 5 requires _audit/_internal access (often blocked in Cloud)${Script:NC}"
    Write-Host "  ${Script:DIM}   - Enable option 8 when sharing export with third parties${Script:NC}"
    Write-Host ""
    Write-Host -NoNewline "  ${Script:YELLOW}Accept defaults? (Y/n): ${Script:NC}"
    $acceptDefaults = Read-Host
    if (-not $acceptDefaults) { $acceptDefaults = "Y" }

    if ($acceptDefaults -match '^[Nn]') {
        Write-Host ""
        Write-Host "  ${Script:DIM}Enter numbers to toggle (e.g., 5,7 to disable Usage and Lookups):${Script:NC}"
        Write-Host -NoNewline "  ${Script:YELLOW}Toggle: ${Script:NC}"
        $toggles = Read-Host

        $toggleNums = $toggles -split ',' | ForEach-Object { $_.Trim() }
        foreach ($num in $toggleNums) {
            switch ($num) {
                "1" { $Script:COLLECT_CONFIGS = -not $Script:COLLECT_CONFIGS }
                "2" { $Script:COLLECT_DASHBOARDS = -not $Script:COLLECT_DASHBOARDS }
                "3" { $Script:COLLECT_ALERTS = -not $Script:COLLECT_ALERTS }
                "4" { $Script:COLLECT_RBAC = -not $Script:COLLECT_RBAC }
                "5" { $Script:COLLECT_USAGE = -not $Script:COLLECT_USAGE }
                "6" { $Script:COLLECT_INDEXES = -not $Script:COLLECT_INDEXES }
                "7" { $Script:COLLECT_LOOKUPS = -not $Script:COLLECT_LOOKUPS }
                "8" { $Script:ANONYMIZE_DATA = -not $Script:ANONYMIZE_DATA }
            }
        }
    }

    # Usage period
    if ($Script:COLLECT_USAGE) {
        Write-Host ""
        Write-Host "  ${Script:BOLD}Usage Analytics Period:${Script:NC}"
        Write-Host ""
        Write-Host "    ${Script:GREEN}1${Script:NC}) Last 7 days"
        Write-Host "    ${Script:GREEN}2${Script:NC}) Last 30 days ${Script:DIM}(recommended)${Script:NC}"
        Write-Host "    ${Script:GREEN}3${Script:NC}) Last 90 days"
        Write-Host "    ${Script:GREEN}4${Script:NC}) Last 365 days"
        Write-Host ""
        Write-Host -NoNewline "  ${Script:YELLOW}Select period [2]: ${Script:NC}"
        $periodChoice = Read-Host
        if (-not $periodChoice) { $periodChoice = "2" }

        switch ($periodChoice) {
            "1" { $Script:USAGE_PERIOD = "7d" }
            "2" { $Script:USAGE_PERIOD = "30d" }
            "3" { $Script:USAGE_PERIOD = "90d" }
            "4" { $Script:USAGE_PERIOD = "365d" }
            default { $Script:USAGE_PERIOD = "30d" }
        }

        Write-Info "Usage analytics will cover the last $Script:USAGE_PERIOD"
    }

    Write-BoxFooter
}

# =============================================================================
# PHASE 3: DATA COLLECTION
# =============================================================================

# =============================================================================
# EXPORT DIRECTORY SETUP
# =============================================================================

function Initialize-ExportDirectory {
    $Script:TIMESTAMP = Get-Date -Format 'yyyyMMdd_HHmmss'
    $stackClean = ($Script:SPLUNK_STACK -replace '\.splunkcloud\.com', '') -replace '[^a-zA-Z0-9_-]', '_'
    $Script:EXPORT_NAME = "dma_cloud_export_${stackClean}_${Script:TIMESTAMP}"
    $Script:EXPORT_DIR = Join-Path (Get-Location) $Script:EXPORT_NAME
    $Script:LOG_FILE = Join-Path $Script:EXPORT_DIR "_export.log"

    # Create directory tree
    New-Item -ItemType Directory -Path $Script:EXPORT_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics/ingestion_infrastructure") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/indexes") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Script:EXPORT_DIR "_configs") -Force | Out-Null

    # NOTE: Dashboards are stored in app-scoped folders (v2 structure)
    # $EXPORT_DIR/{AppName}/dashboards/classic/ and /studio/

    [System.IO.File]::WriteAllText($Script:LOG_FILE, "", $Script:UTF8NoBOM)
    Write-Log "Export started: $Script:EXPORT_NAME"
    Write-Log "Stack: $Script:SPLUNK_STACK"
    Write-Log "Version: $Script:SPLUNK_VERSION"

    # Initialize debug logging if enabled
    Initialize-DebugLog
}

# =============================================================================
# SYSTEM INFO COLLECTION
# =============================================================================

function Export-SystemInfo {
    Write-Progress2 "Collecting server information..."

    # Server info
    $response = Invoke-SplunkApi -Endpoint "/services/server/info" -Data "output_mode=json"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/server_info.json") -Data $response
        Write-Success "Server info collected"
    }

    # Installed apps
    $response = Invoke-SplunkApi -Endpoint "/services/apps/local" -Data "output_mode=json&count=0"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/installed_apps.json") -Data $response
        Write-Success "Installed apps collected"
    }

    # License info (may be restricted)
    $response = Invoke-SplunkApi -Endpoint "/services/licenser/licenses" -Data "output_mode=json"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/license_info.json") -Data $response
    }

    # Server settings
    $response = Invoke-SplunkApi -Endpoint "/services/server/settings" -Data "output_mode=json"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/server_settings.json") -Data $response
    }
}

# =============================================================================
# CONFIGURATIONS COLLECTION
# =============================================================================

function Export-Configurations {
    if (-not $Script:COLLECT_CONFIGS) { return }

    Write-Progress2 "Collecting configurations via REST API..."

    # IMPORTANT (v4.0.1): Only collect TRULY GLOBAL configs here
    # Props, transforms, and savedsearches are collected PER-APP in Export-KnowledgeObjects()
    # and Export-Alerts() functions. Including them here with /servicesNS/-/-/ would export
    # data from ALL apps regardless of which apps the user selected.
    $configs = @("indexes", "inputs", "outputs")

    foreach ($conf in $configs) {
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/-/configs/conf-$conf" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "_configs/${conf}.json") -Data $response
            Write-Log "Collected conf-$conf"
        } else {
            Write-Warning2 "Could not collect conf-$conf"
        }
    }

    Write-Success "Configurations collected (via REST reconstruction)"
}

# =============================================================================
# APP-SCOPED FILTER HELPERS
# =============================================================================

function Get-AppFilter {
    param([string]$Field = "app")

    if (-not $Script:SCOPE_TO_APPS -or $Script:SELECTED_APPS.Count -eq 0) {
        return ""
    }

    # Build OR clause: (app="app1" OR app="app2" OR ...)
    $parts = @()
    foreach ($app in $Script:SELECTED_APPS) {
        $parts += "${Field}=`"${app}`""
    }
    return "(" + ($parts -join " OR ") + ")"
}

function Get-AppInClause {
    param([string]$Field = "app")

    if (-not $Script:SCOPE_TO_APPS -or $Script:SELECTED_APPS.Count -eq 0) {
        return ""
    }

    # Build IN clause: app IN ("app1", "app2", ...)
    $quoted = @()
    foreach ($app in $Script:SELECTED_APPS) {
        $quoted += "`"${app}`""
    }
    return "${Field} IN (" + ($quoted -join ", ") + ")"
}

function Get-AppWhereClause {
    param([string]$Field = "app")

    $inClause = Get-AppInClause -Field $Field
    if ($inClause) {
        return "| where $inClause"
    }
    return ""
}

# =============================================================================
# DASHBOARD COLLECTION
# =============================================================================

function Export-Dashboards {
    if (-not $Script:COLLECT_DASHBOARDS) { return }

    Write-Progress2 "Collecting dashboards..."

    $classicCount = 0
    $studioCount = 0

    # Get all views
    $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/-/data/ui/views" -Data "output_mode=json&count=0"
    if ($null -eq $response) {
        Write-Error2 "Failed to retrieve dashboards"
        return
    }

    # Save master list
    Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/all_dashboards.json") -Data $response

    # Process each app
    foreach ($app in $Script:SELECTED_APPS) {
        # v2 structure: app-scoped dashboard folders by type
        $classicDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/classic"
        $studioDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/studio"
        New-Item -ItemType Directory -Path $classicDir -Force | Out-Null
        New-Item -ItemType Directory -Path $studioDir -Force | Out-Null

        # Get dashboards for this app - filter by eai:acl.app
        $appDashboards = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/ui/views" -Data "output_mode=json&count=0&search=eai:acl.app=$app"
        if ($null -eq $appDashboards) { continue }

        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "$app/dashboards/dashboard_list.json") -Data $appDashboards

        # Extract dashboard names - only from dashboards owned by this app
        $entries = @()
        if ($appDashboards.entry) {
            foreach ($entry in @($appDashboards.entry)) {
                if ($entry.acl -and $entry.acl.app -eq $app) {
                    $entries += $entry
                }
            }
        }

        $dashCount = $entries.Count
        Write-Host "  App: $app ($dashCount dashboards)"

        foreach ($entry in $entries) {
            $name = $entry.name
            if (-not $name) { continue }

            $dashDetail = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/ui/views/$(ConvertTo-UrlEncoded $name)" -Data "output_mode=json"
            if ($null -eq $dashDetail) { continue }

            # Determine dashboard type
            $isStudio = $false
            $hasJsonDefinition = $false
            $isTemplateReference = $false

            $dashJson = $dashDetail | ConvertTo-Json -Depth 20 -Compress

            # Check for Dashboard Studio v2 format
            if ($dashJson -match 'version=\\"2\\"' -or $dashJson -match 'version=\"2\"' -or $dashJson -match 'version=\\u00222\\u0022') {
                $isStudio = $true
                if ($dashJson -match '<definition>' -or $dashJson -match '\\u003cdefinition\\u003e') {
                    $hasJsonDefinition = $true
                    Write-Log "Dashboard Studio v2 with JSON definition: $name"
                }
            }

            # Check for Dashboard Studio template reference
            if ($dashJson -match 'splunk-dashboard-studio') {
                $isStudio = $true
                $isTemplateReference = $true
                Write-Log "Dashboard Studio template reference: $name"
            }

            # Check if eai:data starts with { (direct JSON format)
            $eaiData = $null
            if ($dashDetail.entry) {
                $detailEntry = @($dashDetail.entry)[0]
                if ($detailEntry.content) {
                    $eaiData = $detailEntry.content.'eai:data'
                }
            }
            if ($eaiData -and $eaiData.TrimStart().StartsWith('{')) {
                $isStudio = $true
                $hasJsonDefinition = $true
            }

            if ($isStudio) {
                # Dashboard Studio - save to app-scoped studio folder (v2 structure)
                Write-JsonFile -Path (Join-Path $studioDir "${name}.json") -Data $dashDetail
                $studioCount++

                # Extract JSON definition if present and save separately
                if ($hasJsonDefinition -and $eaiData) {
                    try {
                        $defMatch = [regex]::Match($eaiData, '<definition><!\[CDATA\[(.+?)\]\]></definition>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                        if ($defMatch.Success) {
                            $jsonContent = $defMatch.Groups[1].Value
                            $parsed = $jsonContent | ConvertFrom-Json
                            $defJson = $parsed | ConvertTo-Json -Depth 20
                            [System.IO.File]::WriteAllText((Join-Path $studioDir "${name}_definition.json"), $defJson, $Script:UTF8NoBOM)
                            Write-Log "  -> Extracted JSON definition to ${name}_definition.json"
                        }
                    } catch {
                        # Silent failure - definition extraction is best-effort
                    }
                } elseif ($isTemplateReference) {
                    Write-Log "  -> Template reference (actual JSON in splunk-dashboard-studio app)"
                }

                Write-Log "Exported Dashboard Studio: $app/$name"
                Write-Host "    -> Studio: $name"
            } else {
                # Classic dashboard - save to app-scoped classic folder (v2 structure)
                Write-JsonFile -Path (Join-Path $classicDir "${name}.json") -Data $dashDetail
                $classicCount++
                Write-Log "Exported Classic Dashboard: $app/$name"
                Write-Host "    -> Classic: $name"
            }
        }
    }

    $Script:STATS_DASHBOARDS = $classicCount + $studioCount
    Write-Success "Collected $classicCount Classic + $studioCount Dashboard Studio dashboards"
}

# =============================================================================
# ALERT COLLECTION
# =============================================================================

function Test-IsAlert {
    param($Content)
    # Alert detection logic - MUST match bash exactly (SINGLE SOURCE OF TRUTH)
    # An entry is an alert if ANY of these are true:

    $alertTrack = "$($Content.'alert.track')"
    if ($alertTrack -eq "1" -or $alertTrack -eq "true" -or $alertTrack -eq "True") { return $true }

    $alertType = "$($Content.'alert_type')".ToLower()
    if ($alertType -eq "always" -or $alertType -eq "custom" -or $alertType -match '^number of') { return $true }

    $alertCondition = "$($Content.'alert_condition')"
    if ($alertCondition.Length -gt 0) { return $true }

    $alertComparator = "$($Content.'alert_comparator')"
    if ($alertComparator.Length -gt 0) { return $true }

    $alertThreshold = "$($Content.'alert_threshold')"
    if ($alertThreshold.Length -gt 0) { return $true }

    $counttype = "$($Content.'counttype')"
    if ($counttype -match 'number of') { return $true }

    $actions = "$($Content.'actions')"
    if ($actions) {
        $actionList = $actions -split ',' | Where-Object { $_.Trim().Length -gt 0 }
        if ($actionList.Count -gt 0) { return $true }
    }

    # Check individual action flags
    foreach ($actionKey in @('action.email', 'action.webhook', 'action.script', 'action.slack', 'action.pagerduty', 'action.summary_index', 'action.populate_lookup')) {
        $val = "$($Content.$actionKey)"
        if ($val -eq "1" -or $val -eq "true" -or $val -eq "True") { return $true }
    }

    return $false
}

function Export-Alerts {
    if (-not $Script:COLLECT_ALERTS) { return }

    Write-Progress2 "Collecting alerts and saved searches..."

    $alertCount = 0
    $totalSavedSearches = 0

    foreach ($app in $Script:SELECTED_APPS) {
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/saved/searches" -Data "output_mode=json&count=0"
        if ($null -eq $response) { continue }

        # CRITICAL FIX (v4.2.1): Filter by ACL app to get ONLY searches owned by this app
        $filteredEntries = @()
        $allEntries = @()
        if ($response.entry) {
            $allEntries = @($response.entry)
            foreach ($entry in $allEntries) {
                if ($entry.acl -and $entry.acl.app -eq $app) {
                    $filteredEntries += $entry
                }
            }
        }

        # Build filtered response object
        $filteredResponse = [PSCustomObject]@{
            links = $response.links
            origin = $response.origin
            updated = $response.updated
            generator = $response.generator
            entry = $filteredEntries
            paging = $response.paging
        }

        $appDir = Join-Path $Script:EXPORT_DIR $app
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null
        Write-JsonFile -Path (Join-Path $appDir "savedsearches.json") -Data $filteredResponse

        $appSaved = $filteredEntries.Count
        $totalSavedSearches += $appSaved

        # Count alerts using SAME LOGIC as TypeScript parser
        $appAlerts = 0
        foreach ($entry in $filteredEntries) {
            if ($entry.content -and (Test-IsAlert -Content $entry.content)) {
                $appAlerts++
            }
        }
        $alertCount += $appAlerts

        Write-DebugLog "  ${app}: $appSaved saved searches ($appAlerts alerts)"
    }

    $Script:STATS_ALERTS = $alertCount
    $Script:STATS_SAVED_SEARCHES = $totalSavedSearches
    Write-Success "Collected $totalSavedSearches saved searches ($alertCount alerts found)"
}

# =============================================================================
# RBAC COLLECTION
# =============================================================================

function Export-RbacData {
    if (-not $Script:COLLECT_RBAC) { return }

    Write-Progress2 "Collecting users and roles..."

    # App-scoped user collection optimization
    if ($Script:SCOPE_TO_APPS -and $Script:SELECTED_APPS.Count -gt 0) {
        Write-Info "App-scoped mode: Collecting users who accessed selected apps only"
        Write-Info "  -> Skipping full user list (saves significant time in large environments)"

        $appFilter = Get-AppFilter -Field "app"
        if ($appFilter) {
            $userSearch = "search index=_audit action=search ${appFilter} earliest=-$($Script:USAGE_PERIOD) | stats count as activity, latest(_time) as last_active by user | sort -activity"
            Invoke-AnalyticsSearch -SearchQuery $userSearch -OutputFile (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/users_active_in_apps.json") -Label "Users active in selected apps"

            $resultFile = Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/users_active_in_apps.json"
            if (Test-Path $resultFile) {
                $resultData = Read-JsonFile -Path $resultFile
                if ($resultData -and $resultData.results) {
                    $Script:STATS_USERS = @($resultData.results).Count
                    Write-Success "Collected $($Script:STATS_USERS) users with activity in selected apps"
                }
            }
        }

        # Create placeholder for full users.json
        $appsJson = ($Script:SELECTED_APPS | ForEach-Object { "`"$_`"" }) -join ','
        $placeholder = "{`"scoped`": true, `"reason`": `"App-scoped mode - only users with activity in selected apps collected`", `"apps`": [$appsJson]}"
        [System.IO.File]::WriteAllText((Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/users.json"), $placeholder, $Script:UTF8NoBOM)
    } else {
        # Full collection mode
        $response = Invoke-SplunkApi -Endpoint "/services/authentication/users" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/users.json") -Data $response
            if ($response.entry) {
                $Script:STATS_USERS = @($response.entry).Count
            }
            Write-Success "Collected $($Script:STATS_USERS) users"
        }
    }

    # Roles - always collect
    $response = Invoke-SplunkApi -Endpoint "/services/authorization/roles" -Data "output_mode=json&count=0"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/roles.json") -Data $response
        Write-Log "Collected roles"
    }

    # SAML groups (may not be available) - skip in scoped mode
    if (-not $Script:SCOPE_TO_APPS) {
        $response = Invoke-SplunkApi -Endpoint "/services/admin/SAML-groups" -Data "output_mode=json"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/saml_groups.json") -Data $response
            Write-Log "Collected SAML groups"
        }
    }

    # Current user context
    $response = Invoke-SplunkApi -Endpoint "/services/authentication/current-context" -Data "output_mode=json"
    if ($null -ne $response) {
        Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/current_context.json") -Data $response
    }
}

# =============================================================================
# INDEX COLLECTION
# =============================================================================

function Export-IndexData {
    if (-not $Script:COLLECT_INDEXES) { return }

    Write-Progress2 "Collecting index information..."

    if ($Script:SCOPE_TO_APPS -and $Script:SELECTED_APPS.Count -gt 0) {
        Write-Info "App-scoped mode: Collecting indexes used by selected apps only"

        $appFilter = Get-AppFilter -Field "app"
        if ($appFilter) {
            $indexSearch = "search index=_audit action=search ${appFilter} earliest=-$($Script:USAGE_PERIOD) | rex field=search `"index\s*=\s*(?<idx>[\w_-]+)`" | where isnotnull(idx) | stats count as searches, dc(user) as users by idx | sort -searches"
            Invoke-AnalyticsSearch -SearchQuery $indexSearch -OutputFile (Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes_used_by_apps.json") -Label "Indexes used by selected apps"

            $resultFile = Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes_used_by_apps.json"
            if (Test-Path $resultFile) {
                $resultData = Read-JsonFile -Path $resultFile
                if ($resultData -and $resultData.results) {
                    $Script:STATS_INDEXES = @($resultData.results).Count
                    Write-Success "Collected $($Script:STATS_INDEXES) indexes used by selected apps"
                }
            }
        }

        # Placeholder
        $appsJson = ($Script:SELECTED_APPS | ForEach-Object { "`"$_`"" }) -join ','
        $placeholder = "{`"scoped`": true, `"reason`": `"App-scoped mode - only indexes used by selected apps collected`", `"apps`": [$appsJson]}"
        [System.IO.File]::WriteAllText((Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes.json"), $placeholder, $Script:UTF8NoBOM)
    } else {
        # Full collection mode
        $response = Invoke-SplunkApi -Endpoint "/services/data/indexes" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes.json") -Data $response
            if ($response.entry) {
                $Script:STATS_INDEXES = @($response.entry).Count
            }
            Write-Success "Collected $($Script:STATS_INDEXES) indexes"
        }

        # Extended stats (may be limited in cloud)
        $response = Invoke-SplunkApi -Endpoint "/services/data/indexes-extended" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes_extended.json") -Data $response
        }
    }
}

# =============================================================================
# KNOWLEDGE OBJECTS COLLECTION
# =============================================================================

function Export-KnowledgeObjects {
    Write-Progress2 "Collecting knowledge objects..."

    foreach ($app in $Script:SELECTED_APPS) {
        $appDir = Join-Path $Script:EXPORT_DIR $app
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null

        # CRITICAL (v4.2.2): Filter ALL knowledge objects by acl.app
        # The REST API returns ALL objects VISIBLE to the app (including globally shared ones)

        # Macros
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/admin/macros" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "macros.json") -ObjectType "macros"
        }

        # Eventtypes
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/saved/eventtypes" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "eventtypes.json") -ObjectType "eventtypes"
        }

        # Tags
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/configs/conf-tags" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "tags.json") -ObjectType "tags"
        }

        # Field extractions
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/transforms/extractions" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "field_extractions.json") -ObjectType "field_extractions"
        }

        # Inputs
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/inputs/all" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "inputs.json") -ObjectType "inputs"
        }

        # Props (sourcetype configurations)
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/configs/conf-props" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "props.json") -ObjectType "props"
        }

        # Transforms (field extractions and routing)
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/configs/conf-transforms" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Save-FilteredByAcl -Response $response -TargetApp $app -OutputFile (Join-Path $appDir "transforms.json") -ObjectType "transforms"
        }

        # Lookups
        $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/lookup-table-files" -Data "output_mode=json&count=0"
        if ($null -ne $response) {
            Write-JsonFile -Path (Join-Path $appDir "lookups.json") -Data $response

            # Download lookup contents if enabled
            if ($Script:COLLECT_LOOKUPS) {
                $lookupDir = Join-Path $appDir "lookup_files"
                New-Item -ItemType Directory -Path $lookupDir -Force | Out-Null

                if ($response.entry) {
                    foreach ($lookupEntry in @($response.entry)) {
                        $lookupName = $lookupEntry.name
                        if (-not $lookupName) { continue }

                        $lookupData = Invoke-SplunkApi -Endpoint "/servicesNS/-/$app/data/lookup-table-files/$(ConvertTo-UrlEncoded $lookupName)" -Data "output_mode=json"
                        if ($null -ne $lookupData) {
                            Write-JsonFile -Path (Join-Path $lookupDir "${lookupName}.json") -Data $lookupData
                        }
                    }
                }
            }
        }
    }

    Write-Success "Knowledge objects collected"
}

# Helper: Filter REST response by acl.app and save
function Save-FilteredByAcl {
    param(
        $Response,
        [string]$TargetApp,
        [string]$OutputFile,
        [string]$ObjectType
    )

    $filteredEntries = @()
    if ($Response.entry) {
        foreach ($entry in @($Response.entry)) {
            if ($entry.acl -and $entry.acl.app -eq $TargetApp) {
                $filteredEntries += $entry
            }
        }
    }

    if ($filteredEntries.Count -gt 0) {
        $filteredResponse = [PSCustomObject]@{
            links = $Response.links
            origin = $Response.origin
            updated = $Response.updated
            generator = $Response.generator
            entry = $filteredEntries
            paging = $Response.paging
        }
        Write-JsonFile -Path $OutputFile -Data $filteredResponse
        Write-DebugLog "  ${TargetApp}/${ObjectType}: $($filteredEntries.Count) entries (after filtering)"
    } else {
        Write-DebugLog "  ${TargetApp}/${ObjectType}: 0 entries belong to this app (skipped)"
    }
}

# =============================================================================
# PHASE 4: USAGE ANALYTICS
# =============================================================================

# =============================================================================
# ANALYTICS SEARCH ENGINE
# =============================================================================

function Invoke-AnalyticsSearch {
    param(
        [string]$SearchQuery,
        [string]$OutputFile,
        [string]$Label,
        [int]$Timeout = 300
    )

    Write-Info "Running: $Label"

    $startTime = Get-Date

    # Create search job (blocking mode)
    $postData = "search=$([System.Uri]::EscapeDataString($SearchQuery))&output_mode=json&exec_mode=blocking&timeout=$Timeout"
    $jobResponse = Invoke-SplunkApi -Endpoint "/services/search/jobs" -Method "POST" -Data $postData

    if ($null -eq $jobResponse) {
        $Script:STATS_ERRORS++
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $queryPreview = if ($SearchQuery.Length -gt 200) { $SearchQuery.Substring(0, 200) } else { $SearchQuery }
        $queryPreview = $queryPreview -replace '"', '\"'

        $errorJson = @{
            error = "search_create_failed"
            description = $Label
            message = "Failed to create search job. This may be due to permissions, API restrictions, or query syntax."
            elapsed_seconds = $elapsed
            query_preview = $queryPreview
            troubleshooting = @(
                "1. Verify user has 'search' capability",
                "2. Check if this search command is allowed in Splunk Cloud",
                "3. Try running the search manually in Splunk Web",
                "4. Some REST commands (| rest) may be restricted"
            )
        }
        Write-JsonFile -Path $OutputFile -Data ([PSCustomObject]$errorJson)
        Write-Warning2 "Failed to run search: $Label"
        return $false
    }

    # Get SID
    $sid = $null
    if ($jobResponse.sid) {
        $sid = $jobResponse.sid
    } elseif ($jobResponse.entry) {
        $entry = @($jobResponse.entry)[0]
        if ($entry.content -and $entry.content.sid) {
            $sid = $entry.content.sid
        }
    }

    if (-not $sid) {
        $Script:STATS_ERRORS++
        $errorMsg = "Unknown error"
        if ($jobResponse.messages) {
            $msgs = @($jobResponse.messages)
            if ($msgs.Count -gt 0 -and $msgs[0].text) {
                $errorMsg = $msgs[0].text
            }
        }

        $errorJson = @{
            error = "no_search_id"
            description = $Label
            message = $errorMsg
            troubleshooting = @(
                "1. The search syntax may be invalid",
                "2. Required indexes may not be accessible",
                "3. Try a simpler version of this search first"
            )
        }
        Write-JsonFile -Path $OutputFile -Data ([PSCustomObject]$errorJson)
        Write-Warning2 "Could not get SID for search: $Label"
        return $false
    }

    # Get results
    $results = Invoke-SplunkApi -Endpoint "/services/search/jobs/$sid/results" -Data "output_mode=json&count=0"

    if ($null -ne $results) {
        Write-JsonFile -Path $OutputFile -Data $results
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        Write-Log "Completed search: $Label (${elapsed}s)"
        return $true
    } else {
        $Script:STATS_ERRORS++
        $errorJson = @{
            error = "results_fetch_failed"
            description = $Label
            message = "Search completed but could not retrieve results"
            search_id = $sid
            troubleshooting = @(
                "1. Search may have returned too many results",
                "2. Session may have timed out",
                "3. Try running the search manually"
            )
        }
        Write-JsonFile -Path $OutputFile -Data ([PSCustomObject]$errorJson)
        return $false
    }
}

# =============================================================================
# APP-SCOPED ANALYTICS COLLECTION
# =============================================================================

function Export-AppAnalytics {
    param([string]$AppName)

    if (-not $Script:COLLECT_USAGE) { return }

    $analysisDir = Join-Path $Script:EXPORT_DIR "$AppName/splunk-analysis"
    New-Item -ItemType Directory -Path $analysisDir -Force | Out-Null

    Write-Log "Collecting app-scoped analytics for: $AppName"

    # 1. Dashboard views for this app
    Invoke-AnalyticsSearch `
        -SearchQuery "search index=_audit action=search info=granted search_type=dashboard app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) | where user!=`"splunk-system-user`" | stats count as view_count, dc(user) as unique_users, latest(_time) as last_viewed by savedsearch_name | rename savedsearch_name as dashboard | where isnotnull(dashboard) | sort -view_count | head 100" `
        -OutputFile "$analysisDir/dashboard_views.json" `
        -Label "Dashboard views for $AppName" | Out-Null

    # 2. Alert firing stats (requires _internal)
    if (-not $Script:SKIP_INTERNAL) {
        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler app=`"$AppName`" status=* earliest=-$($Script:USAGE_PERIOD) | stats count as total_runs, sum(eval(if(status=`"success`",1,0))) as successful, sum(eval(if(status=`"skipped`",1,0))) as skipped, sum(eval(if(status!=`"success`" AND status!=`"skipped`",1,0))) as failed, latest(_time) as last_run by savedsearch_name | sort - total_runs | head 100" `
            -OutputFile "$analysisDir/alert_firing.json" `
            -Label "Alert firing stats for $AppName" | Out-Null
    } else {
        $note = '{"note": "_internal index not accessible in Splunk Cloud. Check Monitoring Console for scheduler statistics."}'
        [System.IO.File]::WriteAllText("$analysisDir/alert_firing.json", $note, $Script:UTF8NoBOM)
    }

    # 3. Saved search usage (requires _internal)
    if (-not $Script:SKIP_INTERNAL) {
        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) | stats count as run_count, avg(run_time) as avg_runtime, max(run_time) as max_runtime, latest(_time) as last_run by savedsearch_name | sort - run_count | head 100" `
            -OutputFile "$analysisDir/search_usage.json" `
            -Label "Search usage for $AppName" | Out-Null
    } else {
        $note = '{"note": "_internal index not accessible in Splunk Cloud."}'
        [System.IO.File]::WriteAllText("$analysisDir/search_usage.json", $note, $Script:UTF8NoBOM)
    }

    # 4. Index references
    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) | sample 20 | rex field=search `"index\s*=\s*(?<idx>[\w\*_-]+)`" | stats count as sample_count, dc(user) as unique_users by idx | eval estimated_query_count=sample_count*20 | where isnotnull(idx) | sort -estimated_query_count | head 50" `
        -OutputFile "$analysisDir/index_references.json" `
        -Label "Index references for $AppName" | Out-Null

    # 5. Sourcetype references
    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) | sample 20 | rex field=search `"sourcetype\s*=\s*(?<st>[\w\*_-]+)`" | stats count as sample_count by st | eval estimated_query_count=sample_count*20 | where isnotnull(st) | sort -estimated_query_count | head 50" `
        -OutputFile "$analysisDir/sourcetype_references.json" `
        -Label "Sourcetype references for $AppName" | Out-Null

    # 6a. Dashboard view counts
    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search search_type=dashboard app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" savedsearch_name=* | stats count as views by savedsearch_name | rename savedsearch_name as dashboard" `
        -OutputFile "$analysisDir/dashboard_view_counts.json" `
        -Label "Dashboard view counts for $AppName" | Out-Null

    # 6b. Dashboards never viewed (legacy - often fails in Cloud)
    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/$AppName/data/ui/views | rename title as dashboard | table dashboard | join type=left dashboard [search index=_audit action=search search_type=dashboard app=`"$AppName`" earliest=-$($Script:USAGE_PERIOD) | where user!=`"splunk-system-user`" | stats count as views by savedsearch_name | rename savedsearch_name as dashboard] | where isnull(views) OR views=0 | table dashboard" `
        -OutputFile "$analysisDir/dashboards_never_viewed.json" `
        -Label "Never-viewed dashboards for $AppName" | Out-Null

    # 7. Alerts inventory
    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/$AppName/saved/searches | search (is_scheduled=1 OR alert.track=1) | table title, cron_schedule, alert.severity, alert.track, actions, disabled | rename title as alert_name" `
        -OutputFile "$analysisDir/alerts_inventory.json" `
        -Label "Alerts inventory for $AppName" | Out-Null

    Write-Log "Completed app-scoped analytics for: $AppName"
}

# =============================================================================
# REST API FALLBACK FUNCTIONS
# =============================================================================

function Get-DashboardOwnershipRest {
    param([string]$OutputFile)

    Write-Info "Collecting dashboard ownership via REST API (fallback)..."

    $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/-/data/ui/views" -Data "output_mode=json&count=0"

    if ($null -ne $response -and $response.entry) {
        $results = @()
        foreach ($entry in @($response.entry)) {
            $results += [PSCustomObject]@{
                dashboard = $entry.name
                app = $entry.acl.app
                owner = $entry.acl.owner
                sharing = $entry.acl.sharing
            }
        }
        $output = [PSCustomObject]@{ results = $results }
        Write-JsonFile -Path $OutputFile -Data $output
        Write-Success "Dashboard ownership collected via REST API ($($results.Count) dashboards)"
        return $true
    }

    Write-Warning2 "Failed to collect dashboard ownership via REST API"
    return $false
}

function Get-AlertOwnershipRest {
    param([string]$OutputFile)

    Write-Info "Collecting alert ownership via REST API (fallback)..."

    $response = Invoke-SplunkApi -Endpoint "/servicesNS/-/-/saved/searches" -Data "output_mode=json&count=0"

    if ($null -ne $response -and $response.entry) {
        $results = @()
        foreach ($entry in @($response.entry)) {
            $results += [PSCustomObject]@{
                alert_name = $entry.name
                app = $entry.acl.app
                owner = $entry.acl.owner
                sharing = $entry.acl.sharing
                is_scheduled = if ($entry.content.'is_scheduled') { $entry.content.'is_scheduled' } else { "0" }
                alert_track = if ($entry.content.'alert.track') { $entry.content.'alert.track' } else { "0" }
            }
        }
        $output = [PSCustomObject]@{ results = $results }
        Write-JsonFile -Path $OutputFile -Data $output
        Write-Success "Alert ownership collected via REST API ($($results.Count) alerts)"
        return $true
    }

    Write-Warning2 "Failed to collect alert ownership via REST API"
    return $false
}

function Get-OwnershipSummaryFromRest {
    param([string]$OutputFile)

    Write-Info "Computing ownership summary from REST API data..."

    $dashFile = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics/dashboard_ownership.json"
    $alertFile = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics/alert_ownership.json"

    if (-not (Test-Path $dashFile) -or -not (Test-Path $alertFile)) {
        Write-Warning2 "Could not compute ownership summary from REST data"
        return $false
    }

    $dashData = Read-JsonFile -Path $dashFile
    $alertData = Read-JsonFile -Path $alertFile

    # Check for error entries
    if ($dashData.error -or $alertData.error) {
        Write-Warning2 "Could not compute ownership summary - source data has errors"
        return $false
    }

    $ownerMap = @{}

    # Count dashboards per owner
    $dashResults = if ($dashData.results) { @($dashData.results) } elseif ($dashData.entry) { @($dashData.entry) } else { @() }
    foreach ($item in $dashResults) {
        $owner = $item.owner
        if (-not $owner) { continue }
        if (-not $ownerMap.ContainsKey($owner)) {
            $ownerMap[$owner] = @{ dashboards = 0; alerts = 0 }
        }
        $ownerMap[$owner].dashboards++
    }

    # Count alerts per owner
    $alertResults = if ($alertData.results) { @($alertData.results) } elseif ($alertData.entry) { @($alertData.entry) } else { @() }
    foreach ($item in $alertResults) {
        $owner = $item.owner
        if (-not $owner) { continue }
        if (-not $ownerMap.ContainsKey($owner)) {
            $ownerMap[$owner] = @{ dashboards = 0; alerts = 0 }
        }
        $ownerMap[$owner].alerts++
    }

    # Build results sorted by dashboard count
    $results = @()
    foreach ($kv in ($ownerMap.GetEnumerator() | Sort-Object { $_.Value.dashboards } -Descending)) {
        $results += [PSCustomObject]@{
            owner = $kv.Key
            dashboards = $kv.Value.dashboards
            alerts = $kv.Value.alerts
        }
    }

    $output = [PSCustomObject]@{ results = $results }
    Write-JsonFile -Path $OutputFile -Data $output
    Write-Success "Ownership summary computed from REST API data"
    return $true
}

function Get-DashboardsNeverViewedFallback {
    param([string]$OutputFile)

    Write-Info "Computing dashboards never viewed using REST API data..."

    $dashOwnerFile = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics/dashboard_ownership.json"
    $dashViewsFile = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics/dashboard_views_top100.json"

    if (-not (Test-Path $dashOwnerFile)) {
        Write-Warning2 "Could not generate dashboards never viewed fallback"
        return $false
    }

    $ownerData = Read-JsonFile -Path $dashOwnerFile
    if ($ownerData.error) {
        Write-Warning2 "Could not generate dashboards never viewed fallback"
        return $false
    }

    $allDashboards = if ($ownerData.results) { @($ownerData.results) } elseif ($ownerData.entry) { @($ownerData.entry) } else { @() }

    # Check if we have valid view data
    $hasViews = $false
    if (Test-Path $dashViewsFile) {
        $viewData = Read-JsonFile -Path $dashViewsFile
        if ($viewData -and -not $viewData.error -and $viewData.results) {
            $hasViews = $true
        }
    }

    if ($hasViews) {
        $viewedNames = @($viewData.results | ForEach-Object { $_.dashboard.ToLower() })
        $neverViewed = @()
        foreach ($dash in $allDashboards) {
            $dashName = if ($dash.dashboard) { $dash.dashboard } else { $dash.name }
            if ($dashName -and ($dashName.ToLower() -notin $viewedNames)) {
                $neverViewed += $dash
            }
        }
        $output = [PSCustomObject]@{
            results = $neverViewed
            note = "Dashboards with no recorded views in the analysis period"
        }
    } else {
        $output = [PSCustomObject]@{
            results = $allDashboards
            warning = "Dashboard view counts unavailable - _audit search failed"
            note = "This list contains all dashboards. View statistics could not be retrieved due to permissions or timeout."
        }
    }

    Write-JsonFile -Path $OutputFile -Data $output
    Write-Success "Dashboards never viewed list generated (fallback)"
    return $true
}

# =============================================================================
# GLOBAL USAGE ANALYTICS COLLECTION
# =============================================================================

function Export-UsageAnalytics {
    if (-not $Script:COLLECT_USAGE) { return }

    Write-Host ""
    Write-Host "  ${Script:WHITE}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host "  ${Script:CYAN}USAGE INTELLIGENCE COLLECTION${Script:NC}"
    Write-Host "  ${Script:DIM}Gathering comprehensive usage data for migration prioritization${Script:NC}"
    Write-Host "  ${Script:WHITE}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host ""

    if ($Script:SKIP_INTERNAL) {
        Write-Host "  ${Script:YELLOW}$([char]0x26A0) SPLUNK CLOUD MODE: Skipping _internal index searches${Script:NC}"
        Write-Host "  ${Script:DIM}  Some analytics (scheduler, volume, ingestion) will be limited.${Script:NC}"
        Write-Host "  ${Script:DIM}  Dashboard views and user activity from _audit will still be collected.${Script:NC}"
        Write-Host ""
    }

    # Build app filter for scoped mode
    $appSearchFilter = ""
    $appWhere = ""
    if ($Script:SCOPE_TO_APPS -and $Script:SELECTED_APPS.Count -gt 0) {
        $appFilter = Get-AppFilter -Field "app"
        $appSearchFilter = "$appFilter "
        $appWhere = Get-AppWhereClause -Field "app"
        Write-Host "  ${Script:CYAN}$([char]0x2139) APP-SCOPED ANALYTICS: Filtering to $($Script:SELECTED_APPS.Count) app(s)${Script:NC}"
        Write-Host "  ${Script:DIM}  Apps: $($Script:SELECTED_APPS -join ', ')${Script:NC}"
        Write-Host ""
    }

    $analyticsDir = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics"

    # =========================================================================
    # CATEGORY 1: DASHBOARD VIEW STATISTICS
    # =========================================================================
    Write-Progress2 "Collecting dashboard view statistics..."

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search search_type=dashboard ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" savedsearch_name=* | stats count as view_count, dc(user) as unique_users, max(_time) as last_viewed by app, savedsearch_name | rename savedsearch_name as dashboard | sort -view_count | head 100" `
        -OutputFile "$analyticsDir/dashboard_views_top100.json" `
        -Label "Top 100 viewed dashboards" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search search_type=dashboard ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" savedsearch_name=* | bucket _time span=1w | stats count as views by _time, app, savedsearch_name | rename savedsearch_name as dashboard | sort -_time | head 200" `
        -OutputFile "$analyticsDir/dashboard_views_trend.json" `
        -Label "Dashboard view trends" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search search_type=dashboard ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" savedsearch_name=* | stats count as views by app, savedsearch_name | rename savedsearch_name as dashboard" `
        -OutputFile "$analyticsDir/dashboard_view_counts.json" `
        -Label "Dashboard view counts" | Out-Null

    # Legacy never-viewed query (may fail in Cloud)
    $restAppFilter = ""
    if ($appWhere) { $restAppFilter = $appWhere }
    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/-/data/ui/views | rename title as dashboard, eai:acl.app as app | table dashboard, app $restAppFilter | join type=left dashboard [search index=_audit action=search search_type=dashboard ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" | stats count as views by savedsearch_name | rename savedsearch_name as dashboard] | where isnull(views) OR views=0 | table dashboard, app" `
        -OutputFile "$analyticsDir/dashboards_never_viewed.json" `
        -Label "Never viewed dashboards (legacy)" | Out-Null

    # Check if legacy query failed, use fallback
    $neverViewedFile = "$analyticsDir/dashboards_never_viewed.json"
    if (Test-Path $neverViewedFile) {
        $content = Get-Content $neverViewedFile -Raw -ErrorAction SilentlyContinue
        if ($content -match '"error"') {
            Write-Info "Legacy never-viewed query failed (expected in Splunk Cloud) - using view counts file instead"
            Get-DashboardsNeverViewedFallback -OutputFile $neverViewedFile | Out-Null
        }
    }

    Write-Success "Dashboard statistics collected"

    # =========================================================================
    # CATEGORY 2: USER ACTIVITY METRICS
    # =========================================================================
    Write-Progress2 "Collecting user activity metrics..."

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" | stats count as searches, dc(search) as unique_searches, max(_time) as last_active by user | sort -searches | head 100" `
        -OutputFile "$analyticsDir/users_most_active.json" `
        -Label "Most active users" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" | stats count by user | join user [| rest /services/authentication/users | rename title as user | table user, roles] | stats sum(count) as searches by roles" `
        -OutputFile "$analyticsDir/activity_by_role.json" `
        -Label "Activity by role" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /services/authentication/users | rename title as user | where user!=`"splunk-system-user`" | table user, realname, email | join type=left user [index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count by user] | where isnull(count) | table user, realname, email" `
        -OutputFile "$analyticsDir/users_inactive.json" `
        -Label "Inactive users" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) user!=`"splunk-system-user`" | timechart span=1d dc(user) as daily_active_users" `
        -OutputFile "$analyticsDir/daily_active_users.json" `
        -Label "Daily active users" | Out-Null

    Write-Success "User activity collected"

    # =========================================================================
    # CATEGORY 3: ALERT EXECUTION STATISTICS
    # =========================================================================
    if ($Script:SKIP_INTERNAL) {
        Write-Info "Skipping alert execution statistics (_internal index restricted)"
        foreach ($f in @("alerts_most_fired", "alerts_with_actions", "alerts_failed", "alerts_never_fired", "alert_firing_trend")) {
            $placeholder = '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud"}'
            [System.IO.File]::WriteAllText("$analyticsDir/${f}.json", $placeholder, $Script:UTF8NoBOM)
        }
    } else {
        Write-Progress2 "Collecting alert execution statistics..."

        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler status=success savedsearch_name=* ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count as executions, latest(_time) as last_run by savedsearch_name, app | sort -executions | head 100" `
            -OutputFile "$analyticsDir/alerts_most_fired.json" `
            -Label "Most fired alerts" | Out-Null

        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler result_count>0 ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count as triggers, sum(result_count) as total_results by savedsearch_name, app | sort -triggers | head 50" `
            -OutputFile "$analyticsDir/alerts_with_actions.json" `
            -Label "Alerts with actions" | Out-Null

        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler status=failed ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count as failures, latest(_time) as last_failure by savedsearch_name, app | sort -failures" `
            -OutputFile "$analyticsDir/alerts_failed.json" `
            -Label "Failed alerts" | Out-Null

        $alertsRestFilter = ""
        if ($appWhere) {
            $alertsRestFilter = Get-AppWhereClause -Field "eai:acl.app"
        }
        Invoke-AnalyticsSearch `
            -SearchQuery "| rest /servicesNS/-/-/saved/searches | search is_scheduled=1 | rename title as savedsearch_name $alertsRestFilter | table savedsearch_name, eai:acl.app | join type=left savedsearch_name [search index=_internal sourcetype=scheduler ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count by savedsearch_name] | where isnull(count) | table savedsearch_name, eai:acl.app" `
            -OutputFile "$analyticsDir/alerts_never_fired.json" `
            -Label "Never fired alerts" | Out-Null

        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal sourcetype=scheduler status=success ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | timechart span=1d count by savedsearch_name | head 20" `
            -OutputFile "$analyticsDir/alert_firing_trend.json" `
            -Label "Alert firing trend" | Out-Null

        Write-Success "Alert statistics collected"
    }

    # =========================================================================
    # CATEGORY 4: SEARCH USAGE PATTERNS
    # =========================================================================
    Write-Progress2 "Collecting search usage patterns..."

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | sample 10 | rex field=search `"\|\s*(?<command>\w+)`" | stats count as sample_count by command | eval estimated_count=sample_count*10 | sort -estimated_count | head 50" `
        -OutputFile "$analyticsDir/search_commands_popular.json" `
        -Label "Popular search commands" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | stats count by search_type | sort -count" `
        -OutputFile "$analyticsDir/search_by_type.json" `
        -Label "Search by type" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search total_run_time>30 ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | fields total_run_time, search, app | stats avg(total_run_time) as avg_time, count as runs by search, app | sort -avg_time | head 50" `
        -OutputFile "$analyticsDir/searches_slow.json" `
        -Label "Slow searches" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | sample 20 | rex field=search `"index\s*=\s*(?<searched_index>\w+)`" | stats count as sample_count by searched_index | eval estimated_count=sample_count*20 | sort -estimated_count | head 30" `
        -OutputFile "$analyticsDir/indexes_searched.json" `
        -Label "Indexes searched" | Out-Null

    Write-Success "Search patterns collected"

    # =========================================================================
    # CATEGORY 5: DATA SOURCE USAGE
    # =========================================================================
    Write-Progress2 "Collecting data source usage..."

    Invoke-AnalyticsSearch `
        -SearchQuery "index=_audit action=search ${appSearchFilter}earliest=-$($Script:USAGE_PERIOD) | sample 20 | rex field=search `"sourcetype\s*=\s*(?<st>\w+)`" | stats count as sample_count by st | eval estimated_count=sample_count*20 | sort -estimated_count | head 30" `
        -OutputFile "$analyticsDir/sourcetypes_searched.json" `
        -Label "Sourcetypes searched" | Out-Null

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /services/data/indexes | table title, currentDBSizeMB, totalEventCount, maxTime, minTime | sort -currentDBSizeMB" `
        -OutputFile "$analyticsDir/index_sizes.json" `
        -Label "Index sizes" | Out-Null

    if ($Script:SKIP_INTERNAL) {
        Write-Info "Skipping index query patterns (_internal index restricted)"
        [System.IO.File]::WriteAllText("$analyticsDir/indexes_queried.json", '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud"}', $Script:UTF8NoBOM)
    } else {
        Invoke-AnalyticsSearch `
            -SearchQuery "search index=_internal source=*metrics.log group=per_index_thruput earliest=-$($Script:USAGE_PERIOD) | stats sum(kb) as total_kb, avg(ev) as avg_events by series | eval total_gb=round(total_kb/1024/1024,2) | sort -total_gb | head 30" `
            -OutputFile "$analyticsDir/indexes_queried.json" `
            -Label "Indexes queried" | Out-Null
    }

    Write-Success "Data source usage collected"

    # =========================================================================
    # CATEGORY 5b: DAILY VOLUME ANALYSIS
    # =========================================================================
    if ($Script:SKIP_INTERNAL) {
        Write-Info "Skipping daily volume statistics (_internal index restricted)"
        Write-Info "  -> Use Splunk Cloud Monitoring Console for license usage data"
        foreach ($f in @("daily_volume_by_index", "daily_volume_by_sourcetype", "daily_volume_summary", "daily_events_by_index", "hourly_volume_pattern", "top_indexes_by_volume", "top_sourcetypes_by_volume", "top_hosts_by_volume")) {
            $placeholder = '{"skipped": true, "reason": "_internal index not accessible in Splunk Cloud", "alternative": "Use Monitoring Console > License Usage"}'
            [System.IO.File]::WriteAllText("$analyticsDir/${f}.json", $placeholder, $Script:UTF8NoBOM)
        }
    } else {
        Write-Progress2 "Collecting daily volume statistics (last 30 days)..."

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by idx | eval gb=round(bytes/1024/1024/1024,2) | fields _time, idx, gb' -OutputFile "$analyticsDir/daily_volume_by_index.json" -Label "Daily volume by index (GB)" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes by st | eval gb=round(bytes/1024/1024/1024,2) | fields _time, st, gb' -OutputFile "$analyticsDir/daily_volume_by_sourcetype.json" -Label "Daily volume by sourcetype (GB)" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | timechart span=1d sum(b) as bytes | eval gb=round(bytes/1024/1024/1024,2) | stats avg(gb) as avg_daily_gb, max(gb) as peak_daily_gb, sum(gb) as total_30d_gb' -OutputFile "$analyticsDir/daily_volume_summary.json" -Label "Daily volume summary" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*metrics.log group=per_index_thruput earliest=-30d@d | timechart span=1d sum(ev) as events by series | rename series as index' -OutputFile "$analyticsDir/daily_events_by_index.json" -Label "Daily event counts by index" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-7d | eval hour=strftime(_time, "%H") | stats sum(b) as bytes by hour | eval gb=round(bytes/1024/1024/1024,2) | sort hour' -OutputFile "$analyticsDir/hourly_volume_pattern.json" -Label "Hourly volume pattern (last 7 days)" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by idx | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20' -OutputFile "$analyticsDir/top_indexes_by_volume.json" -Label "Top 20 indexes by daily average volume" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by st | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 20' -OutputFile "$analyticsDir/top_sourcetypes_by_volume.json" -Label "Top 20 sourcetypes by daily average volume" | Out-Null

        Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d@d | stats sum(b) as total_bytes by h | eval daily_avg_gb=round((total_bytes/30)/1024/1024/1024,2) | sort - daily_avg_gb | head 50' -OutputFile "$analyticsDir/top_hosts_by_volume.json" -Label "Top 50 hosts by daily average volume" | Out-Null

        Write-Success "Daily volume statistics collected"
    }

    # =========================================================================
    # CATEGORY 5c: INGESTION INFRASTRUCTURE
    # =========================================================================
    Write-Progress2 "Collecting ingestion infrastructure information..."

    $infraDir = Join-Path $analyticsDir "ingestion_infrastructure"
    # Directory already created in Initialize-ExportDirectory

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as unique_hosts, sum(kb) as total_kb by connectionType | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)' -OutputFile "$infraDir/by_connection_type.json" -Label "Ingestion by connection type (UF/HF/other)" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | rex field=series "^(?<input_type>[^:]+):" | stats sum(kb) as total_kb, dc(series) as unique_sources by input_type | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2) | sort - total_kb' -OutputFile "$infraDir/by_input_method.json" -Label "Ingestion by input method" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput series=http:* earliest=-7d | stats sum(kb) as total_kb, dc(series) as token_count | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)' -OutputFile "$infraDir/hec_usage.json" -Label "HTTP Event Collector usage" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats sum(kb) as total_kb, latest(_time) as last_seen, values(connectionType) as connection_types by sourceHost | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb | head 500' -OutputFile "$infraDir/forwarding_hosts.json" -Label "Forwarding hosts inventory (top 500)" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal source=*license_usage.log type=Usage earliest=-30d | stats sum(b) as bytes, dc(h) as unique_hosts by st | eval daily_avg_gb=round((bytes/30)/1024/1024/1024,2) | eval category=case(match(st,"^otel|^otlp|opentelemetry"),"opentelemetry", match(st,"^aws:|^azure:|^gcp:|^cloud"),"cloud", match(st,"^WinEventLog|^windows|^wmi"),"windows", match(st,"^linux|^syslog|^nix"),"linux_unix", match(st,"^cisco:|^pan:|^juniper:|^fortinet:|^f5:|^checkpoint"),"network_security", match(st,"^access_combined|^nginx|^apache|^iis"),"web", match(st,"^docker|^kube|^container"),"containers", 1=1,"other") | stats sum(daily_avg_gb) as daily_avg_gb, sum(unique_hosts) as unique_hosts, values(st) as sourcetypes by category | sort - daily_avg_gb' -OutputFile "$infraDir/by_sourcetype_category.json" -Label "Ingestion by sourcetype category" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=per_source_thruput earliest=-7d | search series=udp:* OR series=tcp:* | stats sum(kb) as total_kb by series | eval total_gb=round(total_kb/1024/1024,2) | sort - total_kb' -OutputFile "$infraDir/syslog_inputs.json" -Label "Syslog inputs (UDP/TCP)" | Out-Null

    Invoke-AnalyticsSearch -SearchQuery 'search index=_internal sourcetype=splunkd source=*metrics.log group=tcpin_connections earliest=-7d | stats dc(sourceHost) as total_forwarding_hosts, sum(kb) as total_kb | eval total_gb=round(total_kb/1024/1024,2), daily_avg_gb=round(total_gb/7,2)' -OutputFile "$infraDir/summary.json" -Label "Ingestion infrastructure summary" | Out-Null

    Write-Success "Ingestion infrastructure information collected"

    # =========================================================================
    # CATEGORY 5d: OWNERSHIP MAPPING
    # =========================================================================
    Write-Progress2 "Collecting ownership information..."

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/-/data/ui/views | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing | rename title as dashboard, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing" `
        -OutputFile "$analyticsDir/dashboard_ownership.json" `
        -Label "Dashboard ownership mapping" | Out-Null

    # REST API fallback for dashboard ownership
    $dashOwnFile = "$analyticsDir/dashboard_ownership.json"
    if (Test-Path $dashOwnFile) {
        $content = Get-Content $dashOwnFile -Raw -ErrorAction SilentlyContinue
        if ($content -match '"error"') {
            Write-Info "SPL | rest failed for dashboard ownership, trying REST API fallback..."
            Get-DashboardOwnershipRest -OutputFile $dashOwnFile | Out-Null
        }
    }

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/-/saved/searches | table title, eai:acl.app, eai:acl.owner, eai:acl.sharing, is_scheduled, alert.track | rename title as alert_name, eai:acl.app as app, eai:acl.owner as owner, eai:acl.sharing as sharing" `
        -OutputFile "$analyticsDir/alert_ownership.json" `
        -Label "Alert/saved search ownership mapping" | Out-Null

    # REST API fallback for alert ownership
    $alertOwnFile = "$analyticsDir/alert_ownership.json"
    if (Test-Path $alertOwnFile) {
        $content = Get-Content $alertOwnFile -Raw -ErrorAction SilentlyContinue
        if ($content -match '"error"') {
            Write-Info "SPL | rest failed for alert ownership, trying REST API fallback..."
            Get-AlertOwnershipRest -OutputFile $alertOwnFile | Out-Null
        }
    }

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/-/data/ui/views | stats count as dashboards by eai:acl.owner | rename eai:acl.owner as owner | append [| rest /servicesNS/-/-/saved/searches | stats count as alerts by eai:acl.owner | rename eai:acl.owner as owner] | stats sum(dashboards) as dashboards, sum(alerts) as alerts by owner | sort - dashboards" `
        -OutputFile "$analyticsDir/ownership_summary.json" `
        -Label "Ownership summary by user" | Out-Null

    # REST fallback for ownership summary
    $ownSummFile = "$analyticsDir/ownership_summary.json"
    if (Test-Path $ownSummFile) {
        $content = Get-Content $ownSummFile -Raw -ErrorAction SilentlyContinue
        if ($content -match '"error"') {
            Write-Info "SPL search failed for ownership summary, computing from REST data..."
            Get-OwnershipSummaryFromRest -OutputFile $ownSummFile | Out-Null
        }
    }

    Write-Success "Ownership information collected"

    # =========================================================================
    # CATEGORY 6: SAVED SEARCH METADATA
    # =========================================================================
    Write-Progress2 "Collecting saved search metadata..."

    $savedSearchAll = Invoke-SplunkApi -Endpoint "/servicesNS/-/-/saved/searches" -Data "output_mode=json&count=0"
    if ($null -ne $savedSearchAll) {
        Write-JsonFile -Path "$analyticsDir/saved_searches_all.json" -Data $savedSearchAll
    }

    Invoke-AnalyticsSearch `
        -SearchQuery "| rest /servicesNS/-/-/saved/searches | stats count by eai:acl.owner | sort -count | head 20" `
        -OutputFile "$analyticsDir/saved_searches_by_owner.json" `
        -Label "Saved searches by owner" | Out-Null

    Write-Success "Saved search metadata collected"

    # =========================================================================
    # CATEGORY 7: SCHEDULER EXECUTION STATS
    # =========================================================================
    Write-Progress2 "Collecting scheduler statistics..."

    $recentJobs = Invoke-SplunkApi -Endpoint "/services/search/jobs" -Data "output_mode=json&count=100"
    if ($null -ne $recentJobs) {
        Write-JsonFile -Path "$analyticsDir/recent_searches.json" -Data $recentJobs
    }

    $kvStoreStats = Invoke-SplunkApi -Endpoint "/services/kvstore/status" -Data "output_mode=json"
    if ($null -ne $kvStoreStats) {
        Write-JsonFile -Path "$analyticsDir/kvstore_stats.json" -Data $kvStoreStats
    }

    Invoke-AnalyticsSearch `
        -SearchQuery "search index=_internal sourcetype=scheduler earliest=-$($Script:USAGE_PERIOD) | stats count as total, count(eval(status=`"success`")) as success, count(eval(status=`"failed`")) as failed by date_hour | sort date_hour" `
        -OutputFile "$analyticsDir/scheduler_load.json" `
        -Label "Scheduler load" | Out-Null

    Write-Success "Scheduler statistics collected"

    # =========================================================================
    # USAGE INTELLIGENCE SUMMARY (Markdown)
    # =========================================================================
    Write-Host ""
    Write-Progress2 "Generating usage intelligence summary..."

    $summaryFile = Join-Path $analyticsDir "USAGE_INTELLIGENCE_SUMMARY.md"
    $summaryContent = @"
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
| ``dashboard_views_top100.json`` | Most viewed dashboards | Prioritize migration order |
| ``dashboards_never_viewed.json`` | Unused dashboards | Consider not migrating |
| ``users_most_active.json`` | Power users | Training priorities |
| ``users_inactive.json`` | Inactive accounts | Skip in migration |
| ``alerts_most_fired.json`` | Active alerts | Critical to migrate |
| ``alerts_never_fired.json`` | Unused alerts | Consider removing |
| ``sourcetypes_searched.json`` | Important data types | Data ingestion priorities |
| ``indexes_searched.json`` | Important indexes | Bucket mapping priorities |

### Recommended Migration Order

1. **Phase 1**: Top 10 dashboards + their dependent alerts
2. **Phase 2**: Data sources used by Phase 1
3. **Phase 3**: Remaining active dashboards/alerts
4. **Phase 4**: Review never-used items with stakeholders

---
*Generated by DMA Splunk Cloud Export*
"@
    [System.IO.File]::WriteAllText($summaryFile, $summaryContent, $Script:UTF8NoBOM)
    Write-Success "Usage intelligence summary generated"
}

# =============================================================================
# PHASE 5: FINALIZATION
# =============================================================================

# =============================================================================
# SUMMARY REPORT GENERATION
# =============================================================================

function New-ExportSummary {
    Write-Progress2 "Generating summary report..."

    $summaryFile = Join-Path $Script:EXPORT_DIR "dma-env-summary.md"
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'

    $collectStatus = @{
        Configs = if ($Script:COLLECT_CONFIGS) { "Collected" } else { "Skipped" }
        Dashboards = if ($Script:COLLECT_DASHBOARDS) { "Collected" } else { "Skipped" }
        Alerts = if ($Script:COLLECT_ALERTS) { "Collected" } else { "Skipped" }
        RBAC = if ($Script:COLLECT_RBAC) { "Collected" } else { "Skipped (use --rbac to enable)" }
        Usage = if ($Script:COLLECT_USAGE) { "Collected" } else { "Skipped (use --usage to enable, requires _audit index)" }
        Indexes = if ($Script:COLLECT_INDEXES) { "Collected" } else { "Skipped" }
        Lookups = if ($Script:COLLECT_LOOKUPS) { "Collected" } else { "Skipped" }
    }

    $appList = ($Script:SELECTED_APPS | ForEach-Object { "- $_" }) -join "`n"

    $errorList = "No errors occurred."
    if ($Script:ERRORS_LOG.Count -gt 0) {
        $errorList = ($Script:ERRORS_LOG | ForEach-Object { "- $_" }) -join "`n"
    }
    $warnList = "No warnings."
    if ($Script:WARNINGS_LOG.Count -gt 0) {
        $warnList = ($Script:WARNINGS_LOG | ForEach-Object { "- $_" }) -join "`n"
    }

    $summary = @"
# DMA Splunk Cloud Environment Summary

**Export Date**: $now
**Export Script Version**: $($Script:SCRIPT_VERSION)
**Export Type**: Splunk Cloud (REST API)

---

## Environment Overview

| Property | Value |
|----------|-------|
| **Stack URL** | $($Script:SPLUNK_STACK) |
| **Cloud Type** | $($Script:CLOUD_TYPE) |
| **Splunk Version** | $($Script:SPLUNK_VERSION) |
| **Server GUID** | $($Script:SERVER_GUID) |

---

## Collection Summary

| Category | Count | Status |
|----------|-------|--------|
| **Applications** | $($Script:STATS_APPS) | Collected |
| **Dashboards** | $($Script:STATS_DASHBOARDS) | $($collectStatus.Dashboards) |
| **Alerts** | $($Script:STATS_ALERTS) | $($collectStatus.Alerts) |
| **Users** | $($Script:STATS_USERS) | $($collectStatus.RBAC) |
| **Indexes** | $($Script:STATS_INDEXES) | $($collectStatus.Indexes) |

---

## Collection Statistics

| Metric | Value |
|--------|-------|
| **API Calls Made** | $($Script:STATS_API_CALLS) |
| **Rate Limit Hits** | $($Script:STATS_RATE_LIMITS) |
| **Errors** | $($Script:STATS_ERRORS) |
| **Warnings** | $($Script:STATS_WARNINGS) |

---

## Data Categories Collected

- $(if ($collectStatus.Configs -eq 'Collected') { 'Configurations (via REST API reconstruction)' } else { 'Configurations (skipped)' })
- $(if ($collectStatus.Dashboards -eq 'Collected') { 'Dashboards (Classic and Dashboard Studio)' } else { 'Dashboards (skipped)' })
- $(if ($collectStatus.Alerts -eq 'Collected') { 'Alerts and Saved Searches' } else { 'Alerts (skipped)' })
- $($collectStatus.RBAC)
- $($collectStatus.Usage)
- $($collectStatus.Indexes)
- $($collectStatus.Lookups)

---

## Applications Exported

$appList

---

## Cloud Export Notes

This export was collected via REST API from Splunk Cloud. Some differences from Enterprise exports:

1. **Configuration Files**: Reconstructed from REST API endpoints (not direct file access)
2. **Usage Analytics**: Collected via search queries on \_audit and \_internal indexes
3. **Index Statistics**: Limited to what's available via REST API
4. **No File System Access**: Cannot access raw bucket data, audit logs, etc.

---

## Errors and Warnings

### Errors ($($Script:STATS_ERRORS))
$errorList

### Warnings ($($Script:STATS_WARNINGS))
$warnList

---

## Next Steps

1. **Upload to Dynatrace**: Upload the ``.tar.gz`` file to the Dynatrace Migration Assistant
2. **Review Dashboards**: Check the dashboard conversion preview
3. **Review Alerts**: Check alert conversion recommendations
4. **Plan Data Ingestion**: Use OpenPipeline templates for log ingestion

---

*Generated by DMA Splunk Cloud Export Script v$($Script:SCRIPT_VERSION)*
"@

    [System.IO.File]::WriteAllText($summaryFile, $summary, $Script:UTF8NoBOM)
    Write-Success "Summary report generated"
}

# =============================================================================
# MANIFEST GENERATION
# =============================================================================

function New-ExportManifest {
    Write-Progress2 "Generating manifest.json (standardized schema)..."

    $manifestFile = Join-Path $Script:EXPORT_DIR "dma_analytics/manifest.json"

    # Calculate export duration
    $exportDuration = [int]((Get-Date) - $Script:EXPORT_START_TIME).TotalSeconds

    # Count saved searches (separate from alerts)
    $savedSearchCount = 0
    foreach ($app in $Script:SELECTED_APPS) {
        $ssFile = Join-Path $Script:EXPORT_DIR "$app/savedsearches.json"
        if (Test-Path $ssFile) {
            $ssData = Read-JsonFile -Path $ssFile
            if ($ssData -and $ssData.entry) {
                $savedSearchCount += @($ssData.entry).Count
            }
        }
    }

    # Count Dashboard Studio and Classic from app-scoped folders (v2 structure)
    $studioCount = 0
    $classicCount = 0
    foreach ($app in $Script:SELECTED_APPS) {
        $studioDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/studio"
        $classicDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/classic"

        if (Test-Path $studioDir) {
            $studioFiles = @(Get-ChildItem -Path $studioDir -Filter "*.json" -File | Where-Object { $_.Name -notmatch '_definition\.json$' })
            $studioCount += $studioFiles.Count
        }
        if (Test-Path $classicDir) {
            $classicFiles = @(Get-ChildItem -Path $classicDir -Filter "*.json" -File)
            $classicCount += $classicFiles.Count
        }
    }

    # Count total files and size
    $totalFiles = @(Get-ChildItem -Path $Script:EXPORT_DIR -Recurse -File).Count
    $totalSize = (Get-ChildItem -Path $Script:EXPORT_DIR -Recurse -File | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $totalSize) { $totalSize = 0 }

    # Build apps array with per-app counts
    $appsArray = @()
    foreach ($app in $Script:SELECTED_APPS) {
        $appClassic = 0
        $appStudio = 0
        $appAlerts = 0
        $appSaved = 0

        $cDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/classic"
        $sDir = Join-Path $Script:EXPORT_DIR "$app/dashboards/studio"

        if (Test-Path $cDir) {
            $appClassic = @(Get-ChildItem -Path $cDir -Filter "*.json" -File).Count
        }
        if (Test-Path $sDir) {
            $appStudio = @(Get-ChildItem -Path $sDir -Filter "*.json" -File | Where-Object { $_.Name -notmatch '_definition\.json$' }).Count
        }
        $appDashboards = $appClassic + $appStudio

        $ssFile = Join-Path $Script:EXPORT_DIR "$app/savedsearches.json"
        if (Test-Path $ssFile) {
            $ssData = Read-JsonFile -Path $ssFile
            if ($ssData -and $ssData.entry) {
                $appSaved = @($ssData.entry).Count
                foreach ($entry in @($ssData.entry)) {
                    if ($entry.content -and (Test-IsAlert -Content $entry.content)) {
                        $appAlerts++
                    }
                }
            }
        }

        $appsArray += [PSCustomObject]@{
            name = $app
            dashboards = $appDashboards
            dashboards_classic = $appClassic
            dashboards_studio = $appStudio
            alerts = $appAlerts
            saved_searches = $appSaved
        }
    }

    # Build usage intelligence summary
    $usageIntel = [PSCustomObject]@{}
    $analyticsDir = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics"
    if (Test-Path $analyticsDir) {
        Write-Progress2 "Extracting usage intelligence for manifest..."

        # Helper to safely read top N results from analytics file
        function Get-TopResults {
            param([string]$FilePath, [int]$Count = 10)
            if (-not (Test-Path $FilePath)) { return @() }
            $data = Read-JsonFile -Path $FilePath
            if ($null -eq $data -or $data.error -or $data.skipped) { return @() }
            if ($data.results) { return @($data.results | Select-Object -First $Count) }
            return @()
        }

        function Get-ResultCount {
            param([string]$FilePath)
            if (-not (Test-Path $FilePath)) { return 0 }
            $data = Read-JsonFile -Path $FilePath
            if ($null -eq $data -or $data.error -or $data.skipped) { return 0 }
            if ($data.results) { return @($data.results).Count }
            return 0
        }

        function Get-ResultField {
            param([string]$FilePath, [string]$Field, $Default = 0)
            if (-not (Test-Path $FilePath)) { return $Default }
            $data = Read-JsonFile -Path $FilePath
            if ($null -eq $data -or $data.error -or $data.skipped) { return $Default }
            if ($data.results -and @($data.results).Count -gt 0) {
                $val = @($data.results)[0].$Field
                if ($null -ne $val) { return $val }
            }
            return $Default
        }

        $neverViewedCount = Get-ResultCount "$analyticsDir/dashboards_never_viewed.json"
        $neverFiredCount = Get-ResultCount "$analyticsDir/alerts_never_fired.json"
        $inactiveUsersCount = Get-ResultCount "$analyticsDir/users_inactive.json"
        $failedAlertsCount = Get-ResultCount "$analyticsDir/alerts_failed.json"

        $avgDailyGb = Get-ResultField "$analyticsDir/daily_volume_summary.json" "avg_daily_gb" 0
        $peakDailyGb = Get-ResultField "$analyticsDir/daily_volume_summary.json" "peak_daily_gb" 0
        $total30dGb = Get-ResultField "$analyticsDir/daily_volume_summary.json" "total_30d_gb" 0

        $totalForwardingHosts = Get-ResultField "$analyticsDir/ingestion_infrastructure/summary.json" "total_forwarding_hosts" 0
        $ingestionDailyGb = Get-ResultField "$analyticsDir/ingestion_infrastructure/summary.json" "daily_avg_gb" 0

        $hecDailyGb = Get-ResultField "$analyticsDir/ingestion_infrastructure/hec_usage.json" "daily_avg_gb" 0
        $hecTokenCount = Get-ResultField "$analyticsDir/ingestion_infrastructure/hec_usage.json" "token_count" 0
        $hecEnabled = ($hecTokenCount -ne 0 -and $hecTokenCount -ne "0")

        $usageIntel = [PSCustomObject]@{
            summary = [PSCustomObject]@{
                dashboards_never_viewed = $neverViewedCount
                alerts_never_fired = $neverFiredCount
                users_inactive_30d = $inactiveUsersCount
                alerts_with_failures = $failedAlertsCount
            }
            volume = [PSCustomObject]@{
                avg_daily_gb = $avgDailyGb
                peak_daily_gb = $peakDailyGb
                total_30d_gb = $total30dGb
                top_indexes_by_volume = @(Get-TopResults "$analyticsDir/top_indexes_by_volume.json")
                top_sourcetypes_by_volume = @(Get-TopResults "$analyticsDir/top_sourcetypes_by_volume.json")
                top_hosts_by_volume = @(Get-TopResults "$analyticsDir/top_hosts_by_volume.json")
                note = "See _usage_analytics/daily_volume_*.json for full daily breakdown"
            }
            ingestion_infrastructure = [PSCustomObject]@{
                summary = [PSCustomObject]@{
                    total_forwarding_hosts = $totalForwardingHosts
                    daily_ingestion_gb = $ingestionDailyGb
                    hec_enabled = $hecEnabled
                    hec_daily_gb = $hecDailyGb
                }
                by_connection_type = @(Get-TopResults "$analyticsDir/ingestion_infrastructure/by_connection_type.json" 100)
                by_input_method = @(Get-TopResults "$analyticsDir/ingestion_infrastructure/by_input_method.json" 100)
                by_sourcetype_category = @(Get-TopResults "$analyticsDir/ingestion_infrastructure/by_sourcetype_category.json" 100)
                note = "See _usage_analytics/ingestion_infrastructure/ for detailed breakdown"
            }
            prioritization = [PSCustomObject]@{
                top_dashboards = @(Get-TopResults "$analyticsDir/dashboard_views_top100.json")
                top_users = @(Get-TopResults "$analyticsDir/users_most_active.json")
                top_alerts = @(Get-TopResults "$analyticsDir/alerts_most_fired.json")
                top_sourcetypes = @(Get-TopResults "$analyticsDir/sourcetypes_searched.json")
                top_indexes = @(Get-TopResults "$analyticsDir/indexes_searched.json")
            }
            elimination_candidates = [PSCustomObject]@{
                dashboards_never_viewed_count = $neverViewedCount
                alerts_never_fired_count = $neverFiredCount
                note = "See _usage_analytics/ for full lists of candidates"
            }
        }
    }

    # Build manifest object
    $manifest = [PSCustomObject]@{
        schema_version = "4.0"
        archive_structure_version = "v2"
        export_tool = "dma-splunk-cloud-export"
        export_tool_version = $Script:SCRIPT_VERSION
        export_timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        export_duration_seconds = $exportDuration
        archive_structure = [PSCustomObject]@{
            version = "v2"
            description = "App-centric dashboard organization prevents name collisions"
            dashboard_location = "{AppName}/dashboards/classic/ and {AppName}/dashboards/studio/"
        }
        source = [PSCustomObject]@{
            hostname = $Script:SPLUNK_STACK
            fqdn = $Script:SPLUNK_STACK
            platform = "Splunk Cloud"
            platform_version = $Script:CLOUD_TYPE
        }
        splunk = [PSCustomObject]@{
            home = "cloud"
            version = $Script:SPLUNK_VERSION
            build = "cloud"
            flavor = "cloud"
            role = "search_head"
            architecture = "cloud"
            is_cloud = $true
            cloud_type = $Script:CLOUD_TYPE
            server_guid = $Script:SERVER_GUID
        }
        collection = [PSCustomObject]@{
            configs = $Script:COLLECT_CONFIGS
            dashboards = $Script:COLLECT_DASHBOARDS
            alerts = $Script:COLLECT_ALERTS
            rbac = $Script:COLLECT_RBAC
            usage_analytics = $Script:COLLECT_USAGE
            usage_period = $Script:USAGE_PERIOD
            indexes = $Script:COLLECT_INDEXES
            lookups = $Script:COLLECT_LOOKUPS
            data_anonymized = $Script:ANONYMIZE_DATA
        }
        statistics = [PSCustomObject]@{
            apps_exported = $Script:STATS_APPS
            dashboards_classic = $classicCount
            dashboards_studio = $studioCount
            dashboards_total = $Script:STATS_DASHBOARDS
            alerts = $Script:STATS_ALERTS
            saved_searches = $savedSearchCount
            users = $Script:STATS_USERS
            roles = 0
            indexes = $Script:STATS_INDEXES
            api_calls_made = $Script:STATS_API_CALLS
            rate_limit_hits = $Script:STATS_RATE_LIMITS
            errors = $Script:STATS_ERRORS
            warnings = $Script:STATS_WARNINGS
            total_files = $totalFiles
            total_size_bytes = $totalSize
        }
        apps = $appsArray
        usage_intelligence = $usageIntel
    }

    Write-JsonFile -Path $manifestFile -Data $manifest
    Write-Success "manifest.json generated and validated"
}

# =============================================================================
# DATA ANONYMIZATION (Pure PowerShell - no Python dependency)
# =============================================================================

# Anonymization state
$Script:AnonEmailMap = @{}
$Script:AnonHostMap = @{}
$Script:ANON_EMAIL_COUNTER = 0
$Script:ANON_HOST_COUNTER = 0

function Get-AnonHash {
    param([string]$Input, [string]$Prefix = "", [int]$Length = 8)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Input)
    $hash = $sha.ComputeHash($bytes)
    $hex = ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
    $sha.Dispose()
    return "${Prefix}$($hex.Substring(0, $Length))"
}

function Get-AnonEmail {
    param([string]$RealEmail)
    if (-not $RealEmail -or $RealEmail -match '@anon\.dma\.local') {
        return $RealEmail
    }
    if ($Script:AnonEmailMap.ContainsKey($RealEmail)) {
        return $Script:AnonEmailMap[$RealEmail]
    }
    $anonId = Get-AnonHash -Input $RealEmail -Prefix "anon" -Length 6
    $anonEmail = "${anonId}@anon.dma.local"
    $Script:AnonEmailMap[$RealEmail] = $anonEmail
    $Script:ANON_EMAIL_COUNTER++
    return $anonEmail
}

function Get-AnonHostname {
    param([string]$RealHost)
    if (-not $RealHost) { return $RealHost }
    if ($RealHost -match '^host-.*\.anon\.local$') { return $RealHost }
    if ($RealHost -in @('localhost', '127.0.0.1')) { return $RealHost }

    if ($Script:AnonHostMap.ContainsKey($RealHost)) {
        return $Script:AnonHostMap[$RealHost]
    }
    $anonId = Get-AnonHash -Input $RealHost -Length 8
    $anonHost = "host-${anonId}.anon.local"
    $Script:AnonHostMap[$RealHost] = $anonHost
    $Script:ANON_HOST_COUNTER++
    return $anonHost
}

function Invoke-AnonymizeContent {
    param([string]$Content, [string]$FilePath)

    $result = $Content
    $modified = $false

    # 1. Anonymize email addresses
    $emailPattern = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}'
    $emailMatches = [regex]::Matches($result, $emailPattern)
    foreach ($match in $emailMatches) {
        $email = $match.Value
        if ($email -notmatch '@anon\.dma\.local|@example\.com|@localhost') {
            $anon = Get-AnonEmail -RealEmail $email
            if ($anon -ne $email) {
                $result = $result.Replace($email, $anon)
                $modified = $true
            }
        }
    }

    # 2. Redact private IP addresses (RFC 1918)
    $result = [regex]::Replace($result, '\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]')
    $result = [regex]::Replace($result, '\b172\.(1[6-9]|2[0-9]|3[01])\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]')
    $result = [regex]::Replace($result, '\b192\.168\.\d{1,3}\.\d{1,3}\b', '[IP-REDACTED]')
    if ($result -ne $Content) { $modified = $true }

    # 3. Anonymize hostnames in JSON format
    $hostJsonPattern = '"(host|hostname|splunk_server|server|serverName)"\s*:\s*"([^"]+)"'
    $hostMatches = [regex]::Matches($result, $hostJsonPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $hostMatches) {
        $key = $match.Groups[1].Value
        $hostname = $match.Groups[2].Value
        $anon = Get-AnonHostname -RealHost $hostname
        if ($anon -ne $hostname) {
            $result = $result.Replace("`"$key`": `"$hostname`"", "`"$key`": `"$anon`"")
            $result = $result.Replace("`"$key`":`"$hostname`"", "`"$key`":`"$anon`"")
            $modified = $true
        }
    }

    # 4. Anonymize hostnames in conf format
    $hostConfPattern = '\b(host|hostname|splunk_server|server)\s*=\s*([^\s,\]"]+)'
    $confMatches = [regex]::Matches($result, $hostConfPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($match in $confMatches) {
        $key = $match.Groups[1].Value
        $hostname = $match.Groups[2].Value
        $anon = Get-AnonHostname -RealHost $hostname
        if ($anon -ne $hostname) {
            $result = $result.Replace("${key}=${hostname}", "${key}=${anon}")
            $result = $result.Replace("${key} = ${hostname}", "${key} = ${anon}")
            $modified = $true
        }
    }

    if ($modified) { return $result }
    return $null  # Signals no changes needed
}

function Invoke-ExportAnonymization {
    if (-not $Script:ANONYMIZE_DATA) { return }

    Write-BoxHeader "ANONYMIZING SENSITIVE DATA"

    Write-Host "  ${Script:WHITE}Replacing sensitive data with anonymized values:${Script:NC}"
    Write-Host ""
    Write-Host "    ${Script:CYAN}$([char]0x2192)${Script:NC} Email addresses $([char]0x2192) anon######@anon.dma.local"
    Write-Host "    ${Script:CYAN}$([char]0x2192)${Script:NC} Hostnames $([char]0x2192) host-########.anon.local"
    Write-Host "    ${Script:CYAN}$([char]0x2192)${Script:NC} IP addresses $([char]0x2192) [IP-REDACTED]"
    Write-Host ""
    Write-Host "  ${Script:DIM}The same original value always maps to the same anonymized value.${Script:NC}"
    Write-Host ""

    Write-Progress2 "Scanning export directory for files to anonymize..."

    # Find all text files to process
    $extensions = @("*.json", "*.conf", "*.xml", "*.csv", "*.txt", "*.meta")
    $filesToProcess = @()
    foreach ($ext in $extensions) {
        $filesToProcess += @(Get-ChildItem -Path $Script:EXPORT_DIR -Filter $ext -Recurse -File)
    }

    $totalFiles = $filesToProcess.Count

    if ($totalFiles -eq 0) {
        Write-Info "No text files found to anonymize"
        return
    }

    Write-Progress2 "Processing $totalFiles files..."

    $processed = 0
    foreach ($file in $filesToProcess) {
        # Skip temp/script files
        if ($file.Extension -eq '.py' -or $file.Extension -eq '.tmp') { continue }
        if ($file.Length -eq 0) { continue }

        try {
            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $isJson = $file.Extension -eq '.json'

            # Validate JSON before modifying
            $originalValid = $true
            if ($isJson) {
                try { $null = $content | ConvertFrom-Json } catch { $originalValid = $false }
            }

            $newContent = Invoke-AnonymizeContent -Content $content -FilePath $file.FullName

            if ($null -ne $newContent) {
                # For JSON files, validate after anonymization
                if ($isJson -and $originalValid) {
                    try {
                        $null = $newContent | ConvertFrom-Json
                    } catch {
                        Write-DebugLog "WARNING: Anonymization would corrupt JSON in $($file.FullName), skipping"
                        continue
                    }
                }

                [System.IO.File]::WriteAllText($file.FullName, $newContent, $Script:UTF8NoBOM)
            }
        } catch {
            # Silent failure per file
        }

        $processed++
        if ($processed % 10 -eq 0) {
            Write-Host -NoNewline "`r  Processing: $processed/$totalFiles files..."
        }
    }

    Write-Host "`r  Processing: $totalFiles/$totalFiles files... Done!     "

    # Report statistics
    Write-Host ""
    Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host "  ${Script:WHITE}Anonymization Summary${Script:NC}"
    Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host ""
    Write-Host "    Files processed:        ${Script:GREEN}${totalFiles}${Script:NC}"
    Write-Host "    Unique emails mapped:   ${Script:GREEN}$($Script:ANON_EMAIL_COUNTER)${Script:NC}"
    Write-Host "    Unique hosts mapped:    ${Script:GREEN}$($Script:ANON_HOST_COUNTER)${Script:NC}"
    Write-Host "    IP addresses:           ${Script:GREEN}Redacted (all)${Script:NC}"
    Write-Host ""

    # Write anonymization report
    $anonReport = [PSCustomObject]@{
        anonymization_applied = $true
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        statistics = [PSCustomObject]@{
            files_processed = $totalFiles
            unique_emails_anonymized = $Script:ANON_EMAIL_COUNTER
            unique_hosts_anonymized = $Script:ANON_HOST_COUNTER
            ip_addresses = "all_redacted"
        }
        transformations = [PSCustomObject]@{
            emails = "original@domain.com -> anon######@anon.dma.local"
            hostnames = "server.example.com -> host-########.anon.local"
            ipv4 = "x.x.x.x -> [IP-REDACTED]"
            ipv6 = "xxxx:xxxx:... -> [IPv6-REDACTED]"
        }
        note = "This export has been anonymized. Original values cannot be recovered from this data."
    }
    Write-JsonFile -Path (Join-Path $Script:EXPORT_DIR "_anonymization_report.json") -Data $anonReport

    Write-Success "Data anonymization complete"
}

# =============================================================================
# ARCHIVE CREATION
# =============================================================================

function New-ExportArchive {
    param(
        [bool]$KeepDir = $false,
        [string]$Suffix = ""
    )

    # Finalize debug log before archiving
    Complete-DebugLog

    Write-Progress2 "Creating compressed archive${Suffix}..."

    $archiveName = "$($Script:EXPORT_NAME)${Suffix}.tar.gz"

    # Use Windows built-in tar.exe (Windows 10 1803+)
    $tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tarExe) {
        $tarExe = Get-Command tar -ErrorAction SilentlyContinue
    }

    if (-not $tarExe) {
        Write-Error2 "tar.exe not found. Windows 10 1803+ includes tar.exe by default."
        Write-Error2 "The export directory is preserved at: $($Script:EXPORT_DIR)"
        Write-Error2 "You can manually create the archive using: tar -czf `"$archiveName`" -C `"$(Split-Path $Script:EXPORT_DIR)`" `"$(Split-Path $Script:EXPORT_DIR -Leaf)`""
        return $false
    }

    $parentDir = Split-Path $Script:EXPORT_DIR
    $dirName = Split-Path $Script:EXPORT_DIR -Leaf

    # Run tar from parent directory
    $currentDir = Get-Location
    try {
        Set-Location $parentDir
        & tar.exe -czf $archiveName $dirName 2>$null
        $tarResult = $LASTEXITCODE
    } finally {
        Set-Location $currentDir
    }

    if ($tarResult -eq 0) {
        $archivePath = Join-Path $parentDir $archiveName
        $size = (Get-Item $archivePath).Length
        $sizeDisplay = if ($size -gt 1GB) { "{0:N2} GB" -f ($size / 1GB) }
                       elseif ($size -gt 1MB) { "{0:N2} MB" -f ($size / 1MB) }
                       else { "{0:N2} KB" -f ($size / 1KB) }
        Write-Success "Archive created: $archiveName ($sizeDisplay)"

        # Move archive to working directory if needed
        $targetPath = Join-Path (Get-Location) $archiveName
        if ($archivePath -ne $targetPath) {
            Move-Item -Path $archivePath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }

        # Clean up export directory if not keeping
        if (-not $KeepDir) {
            Remove-Item -Path $Script:EXPORT_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
        Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
        Write-Host "  ${Script:GREEN}  ARCHIVE CREATED${Script:NC}"
        Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
        Write-Host ""
        Write-Host "  ${Script:BOLD}Archive:${Script:NC} $(Get-Location)/$archiveName"
        Write-Host "  ${Script:BOLD}Size:${Script:NC}    $sizeDisplay"
        Write-Host ""
        return $true
    } else {
        Write-Error2 "Failed to create archive"
        return $false
    }
}

# =============================================================================
# MASKED ARCHIVE CREATION (v4.2.5)
# =============================================================================

function New-MaskedArchive {
    $maskedDir = "$($Script:EXPORT_DIR)_masked"

    Write-Host ""
    Write-Host "  ${Script:CYAN}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host "  ${Script:CYAN}  CREATING MASKED (ANONYMIZED) ARCHIVE${Script:NC}"
    Write-Host "  ${Script:CYAN}$([string]::new([char]0x2501, 68))${Script:NC}"
    Write-Host ""
    Write-Host "  ${Script:DIM}The original archive has been preserved.${Script:NC}"
    Write-Host "  ${Script:DIM}Now creating a separate anonymized copy...${Script:NC}"
    Write-Host ""

    # Copy export directory
    Write-Progress2 "Copying export directory for anonymization..."
    Copy-Item -Path $Script:EXPORT_DIR -Destination $maskedDir -Recurse -Force

    if (-not (Test-Path $maskedDir)) {
        Write-Error2 "Failed to create masked directory copy"
        return
    }

    # Temporarily switch EXPORT_DIR for anonymization
    $originalExportDir = $Script:EXPORT_DIR
    $Script:EXPORT_DIR = $maskedDir

    # Reset anonymization state for clean mapping
    $Script:AnonEmailMap = @{}
    $Script:AnonHostMap = @{}
    $Script:ANON_EMAIL_COUNTER = 0
    $Script:ANON_HOST_COUNTER = 0

    # Run anonymization on the masked copy
    Invoke-ExportAnonymization

    # Create masked archive
    $maskedArchive = "$($Script:EXPORT_NAME)_masked.tar.gz"
    Write-Progress2 "Creating masked archive..."

    $parentDir = Split-Path $maskedDir
    $dirName = Split-Path $maskedDir -Leaf

    $currentDir = Get-Location
    try {
        Set-Location $parentDir
        & tar.exe -czf $maskedArchive $dirName 2>$null
        $tarResult = $LASTEXITCODE
    } finally {
        Set-Location $currentDir
    }

    if ($tarResult -eq 0) {
        $archivePath = Join-Path $parentDir $maskedArchive
        $size = (Get-Item $archivePath).Length
        $sizeDisplay = if ($size -gt 1GB) { "{0:N2} GB" -f ($size / 1GB) }
                       elseif ($size -gt 1MB) { "{0:N2} MB" -f ($size / 1MB) }
                       else { "{0:N2} KB" -f ($size / 1KB) }
        Write-Success "Masked archive created: $maskedArchive ($sizeDisplay)"

        # Move archive to working directory
        $targetPath = Join-Path (Get-Location) $maskedArchive
        if ($archivePath -ne $targetPath) {
            Move-Item -Path $archivePath -Destination $targetPath -Force -ErrorAction SilentlyContinue
        }

        # Clean up masked directory
        Remove-Item -Path $maskedDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host ""
        Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
        Write-Host "  ${Script:GREEN}  MASKED ARCHIVE CREATED${Script:NC}"
        Write-Host "  ${Script:GREEN}$([string]::new([char]0x2501, 68))${Script:NC}"
        Write-Host ""
        Write-Host "  ${Script:BOLD}Masked Archive:${Script:NC} $(Get-Location)/$maskedArchive"
        Write-Host "  ${Script:BOLD}Size:${Script:NC}           $sizeDisplay"
        Write-Host ""
        Write-Host "  ${Script:YELLOW}Note:${Script:NC} Share the ${Script:BOLD}_masked${Script:NC} archive with third parties."
        Write-Host "        Keep the original archive for your records."
        Write-Host ""
    } else {
        Write-Error2 "Failed to create masked archive"
        Remove-Item -Path $maskedDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Restore original EXPORT_DIR and clean it up
    $Script:EXPORT_DIR = $originalExportDir
    Remove-Item -Path $Script:EXPORT_DIR -Recurse -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# TROUBLESHOOTING REPORT
# =============================================================================

function New-TroubleshootingReport {
    $reportFile = Join-Path $Script:EXPORT_DIR "TROUBLESHOOTING.md"

    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'

    $reportContent = @"
# DMA Splunk Cloud Export Troubleshooting Report

This report was generated because errors occurred during the export.
Use this information to diagnose and resolve issues.

---

## Environment Information

| Setting | Value |
|---------|-------|
| Script Version | $($Script:SCRIPT_VERSION) |
| Timestamp | $now |
| Splunk Cloud Stack | $($Script:SPLUNK_STACK) |
| Auth Method | $($Script:AUTH_METHOD) |
| Cloud Type | $($Script:CLOUD_TYPE) |
| Splunk Version | $($Script:SPLUNK_VERSION) |

---

## Error Summary

**Total Errors:** $($Script:STATS_ERRORS)
**Rate Limit Events:** $($Script:STATS_RATE_LIMITS)

"@

    # Scan for error files in usage_analytics
    $analyticsDir = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics"
    if (Test-Path $analyticsDir) {
        $reportContent += "## Failed Analytics Searches`n`n"
        $errorCount = 0
        $jsonFiles = Get-ChildItem -Path $analyticsDir -Filter "*.json" -File -ErrorAction SilentlyContinue
        foreach ($jsonFile in $jsonFiles) {
            $fileContent = Get-Content $jsonFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($fileContent -match '"error"') {
                $errorCount++
                $errorType = "unknown"
                $errorMsg = "No message"
                try {
                    $parsed = $fileContent | ConvertFrom-Json
                    if ($parsed.error) { $errorType = $parsed.error }
                    if ($parsed.message) { $errorMsg = $parsed.message }
                } catch {}
                $reportContent += "### Error ${errorCount}: $($jsonFile.Name)`n`n"
                $reportContent += "- **Error Type:** ``$errorType```n"
                $reportContent += "- **Message:** $errorMsg`n`n"
            }
        }
        if ($errorCount -eq 0) {
            $reportContent += "_No search errors detected in output files._`n`n"
        }
    }

    $reportContent += @"
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
- Generate a new API token from Splunk Web -> Settings -> Tokens
- Ensure token has sufficient permissions
- Token should have at least these capabilities:
  - ``search``, ``admin_all_objects``, ``list_settings``

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
- Verify user has the ``admin`` role or equivalent
- Required capabilities:
  - ``search`` - Run searches
  - ``list_settings`` - View configurations
  - ``admin_all_objects`` - Access all apps' objects
  - ``rest_properties_get`` - REST API read access

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
   - _export.log
   - manifest.json

2. **Diagnostic commands to run in Splunk Web:**
   ``````splunk
   | rest /services/authentication/current-context | table username, roles, capabilities
   ``````

3. **Test basic search access:**
   ``````splunk
   | makeresults | eval test="Export script connectivity test"
   ``````

---

*Report generated by DMA Splunk Cloud Export v$($Script:SCRIPT_VERSION)*
"@

    [System.IO.File]::WriteAllText($reportFile, $reportContent, $Script:UTF8NoBOM)
    Write-Log "Generated troubleshooting report: $reportFile"
}

# =============================================================================
# FINAL SUMMARY DISPLAY
# =============================================================================

function Show-ExportSummary {
    Write-BoxHeader "EXPORT COMPLETE"

    Write-BoxLine ""
    Write-BoxLine "${Script:BOLD}Export Statistics:${Script:NC}"
    Write-BoxLine "  $([char]0x2022) Applications:    $($Script:STATS_APPS)"
    Write-BoxLine "  $([char]0x2022) Dashboards:      $($Script:STATS_DASHBOARDS)"
    Write-BoxLine "  $([char]0x2022) Alerts:          $($Script:STATS_ALERTS)"
    Write-BoxLine "  $([char]0x2022) Users:           $($Script:STATS_USERS)"
    Write-BoxLine "  $([char]0x2022) Indexes:         $($Script:STATS_INDEXES)"
    Write-BoxLine ""
    Write-BoxLine "${Script:BOLD}API Statistics:${Script:NC}"
    Write-BoxLine "  $([char]0x2022) Total API calls: $($Script:STATS_API_CALLS)"
    Write-BoxLine "  $([char]0x2022) Rate limit hits: $($Script:STATS_RATE_LIMITS)"
    Write-BoxLine "  $([char]0x2022) Errors:          $($Script:STATS_ERRORS)"
    Write-BoxLine "  $([char]0x2022) Warnings:        $($Script:STATS_WARNINGS)"

    if ($Script:STATS_ERRORS -gt 0) {
        Write-BoxLine ""
        Write-BoxLine "  ${Script:YELLOW}$([char]0x26A0) See TROUBLESHOOTING.md in archive for error details${Script:NC}"
    }

    Write-BoxLine ""
    Write-BoxLine "${Script:BOLD}Next Steps:${Script:NC}"
    Write-BoxLine "  1. Upload the .tar.gz file to the Dynatrace Migration Assistant"
    Write-BoxLine "  2. Review the migration analysis"
    Write-BoxLine "  3. Begin dashboard and alert conversion"
    Write-BoxLine ""

    Write-BoxFooter

    # Show prominent error warning
    if ($Script:STATS_ERRORS -gt 0) {
        Write-Host ""
        Write-Host "${Script:YELLOW}$([string]::new([char]0x2550, 70))${Script:NC}"
        Write-Host "${Script:YELLOW}$([char]0x2551)${Script:NC}  ${Script:WHITE}$([char]0x26A0)  EXPORT COMPLETED WITH $($Script:STATS_ERRORS) ERROR(S)${Script:NC}"
        Write-Host "${Script:YELLOW}$([string]::new([char]0x2550, 70))${Script:NC}"
        Write-Host ""
        Write-Host "  The export is still usable but some analytics data may be missing."
        Write-Host ""
        Write-Host "  ${Script:WHITE}TO DIAGNOSE:${Script:NC}"
        Write-Host ""
        Write-Host "  1. Extract the archive:"
        Write-Host "     tar -xzf $($Script:EXPORT_NAME).tar.gz"
        Write-Host ""
        Write-Host "  2. Check:"
        Write-Host "     - $($Script:EXPORT_NAME)/TROUBLESHOOTING.md"
        Write-Host "     - $($Script:EXPORT_NAME)/_export.log"
        Write-Host ""
        Write-Host "  ${Script:WHITE}COMMON SPLUNK CLOUD ISSUES:${Script:NC}"
        Write-Host "  $([char]0x2022) REST command (| rest) may be restricted"
        Write-Host "  $([char]0x2022) _audit and _internal indexes may have limited access"
        Write-Host "  $([char]0x2022) API rate limiting during peak hours"
        Write-Host ""
    }
}

# =============================================================================
# RESUME SUPPORT (v4.3.0)
# =============================================================================

function Resume-FromArchive {
    param([string]$ArchivePath)

    if (-not (Test-Path $ArchivePath)) {
        Write-Error2 "Resume archive not found: $ArchivePath"
        exit 1
    }

    Write-Progress2 "Extracting previous export archive for resume..."

    # Get the directory name inside the archive
    $tarOutput = & tar.exe -tzf $ArchivePath 2>$null | Select-Object -First 1
    if (-not $tarOutput) {
        Write-Error2 "Could not determine export directory from archive"
        exit 1
    }
    $dirName = ($tarOutput -split '/')[0]

    if (-not $dirName) {
        Write-Error2 "Could not determine export directory from archive"
        exit 1
    }

    $targetDir = Join-Path (Get-Location) $dirName

    # Check if directory already exists
    if (Test-Path $targetDir) {
        Write-Warning2 "Directory $dirName already exists - using existing directory"
    } else {
        # Extract the archive
        & tar.exe -xzf $ArchivePath 2>$null

        if (-not (Test-Path $targetDir)) {
            Write-Error2 "Failed to extract archive - directory $dirName not found"
            exit 1
        }
    }

    # Set globals to match the extracted export
    $Script:EXPORT_NAME = $dirName
    $Script:EXPORT_DIR = $targetDir
    $Script:LOG_FILE = Join-Path $Script:EXPORT_DIR "_export.log"

    # Re-initialize debug log path if debug mode
    if ($Script:DEBUG_MODE) {
        $Script:DEBUG_LOG_FILE = Join-Path $Script:EXPORT_DIR "_export_debug.log"
    }

    Write-Log "=== RESUME MODE ==="
    Write-Log "Resumed from archive: $ArchivePath"
    Write-Log "Export directory: $($Script:EXPORT_DIR)"

    Write-Success "Extracted previous export: $dirName"
}

function Test-HasCollectedData {
    param([string]$CheckType)

    switch ($CheckType) {
        "system_info" {
            $file = Join-Path $Script:EXPORT_DIR "dma_analytics/system_info/server_info.json"
            return (Test-Path $file) -and ((Get-Item $file).Length -gt 0)
        }
        "configurations" {
            $configDir = Join-Path $Script:EXPORT_DIR "_configs"
            if (-not (Test-Path $configDir)) { return $false }
            return @(Get-ChildItem -Path $configDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count -gt 0
        }
        "dashboards" {
            foreach ($app in $Script:SELECTED_APPS) {
                $dashDir = Join-Path $Script:EXPORT_DIR "$app/dashboards"
                if (Test-Path $dashDir) {
                    $count = @(Get-ChildItem -Path $dashDir -Filter "*.json" -File -Recurse -ErrorAction SilentlyContinue).Count
                    if ($count -gt 0) { return $true }
                }
            }
            return $false
        }
        "alerts" {
            foreach ($app in $Script:SELECTED_APPS) {
                $file = Join-Path $Script:EXPORT_DIR "$app/savedsearches.json"
                if ((Test-Path $file) -and ((Get-Item $file).Length -gt 0)) { return $true }
            }
            return $false
        }
        "rbac" {
            $file = Join-Path $Script:EXPORT_DIR "dma_analytics/rbac/users.json"
            return (Test-Path $file) -and ((Get-Item $file).Length -gt 0)
        }
        "knowledge_objects" {
            foreach ($app in $Script:SELECTED_APPS) {
                $appDir = Join-Path $Script:EXPORT_DIR $app
                if (Test-Path $appDir) {
                    $files = Get-ChildItem -Path $appDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
                             Where-Object { $_.DirectoryName -notlike "*dashboards*" -and $_.Name -ne "savedsearches.json" -and $_.DirectoryName -notlike "*splunk-analysis*" }
                    if (@($files).Count -gt 0) { return $true }
                }
            }
            return $false
        }
        "app_analytics" {
            foreach ($app in $Script:SELECTED_APPS) {
                $analysisDir = Join-Path $Script:EXPORT_DIR "$app/splunk-analysis"
                if (Test-Path $analysisDir) {
                    $count = @(Get-ChildItem -Path $analysisDir -Filter "*.json" -File -ErrorAction SilentlyContinue).Count
                    if ($count -gt 0) { return $true }
                }
            }
            return $false
        }
        "usage_analytics" {
            $usageDir = Join-Path $Script:EXPORT_DIR "dma_analytics/usage_analytics"
            if (-not (Test-Path $usageDir)) { return $false }
            return @(Get-ChildItem -Path $usageDir -Filter "*.json" -File -Recurse -ErrorAction SilentlyContinue).Count -gt 0
        }
        "indexes" {
            $file = Join-Path $Script:EXPORT_DIR "dma_analytics/indexes/indexes.json"
            return (Test-Path $file) -and ((Get-Item $file).Length -gt 0)
        }
        default { return $false }
    }
}

# =============================================================================
# COLLECTION ORCHESTRATOR
# =============================================================================

function Start-Collection {
    Write-BoxHeader "STEP 6: DATA COLLECTION"

    Write-Host ""

    if ($Script:RESUME_MODE) {
        Write-Info "RESUME MODE - skipping previously collected data"
        Write-Host ""
    }

    Write-Info "Starting data collection..."
    Write-Host ""

    # In resume mode, use existing directory; otherwise create new one
    if (-not $Script:RESUME_MODE) {
        Initialize-ExportDirectory
    }

    $totalSteps = 9
    $currentStep = 0
    $skipped = 0
    $collected = 0

    # System info
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "system_info")) {
        Write-Host "  [$currentStep/$totalSteps] Server information... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting server information..."
        Export-SystemInfo
        $collected++
    }

    # Configurations
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "configurations")) {
        Write-Host "  [$currentStep/$totalSteps] Configurations... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting configurations..."
        Export-Configurations
        $collected++
    }

    # Dashboards
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "dashboards")) {
        Write-Host "  [$currentStep/$totalSteps] Dashboards... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting dashboards..."
        Export-Dashboards
        $collected++
    }

    # Alerts
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "alerts")) {
        Write-Host "  [$currentStep/$totalSteps] Alerts and saved searches... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting alerts and saved searches..."
        Export-Alerts
        $collected++
    }

    # RBAC
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "rbac")) {
        Write-Host "  [$currentStep/$totalSteps] Users and roles... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting users and roles..."
        Export-RbacData
        $collected++
    }

    # Knowledge objects
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "knowledge_objects")) {
        Write-Host "  [$currentStep/$totalSteps] Knowledge objects... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting knowledge objects..."
        Export-KnowledgeObjects
        $collected++
    }

    # App-scoped analytics
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "app_analytics")) {
        Write-Host "  [$currentStep/$totalSteps] App-scoped analytics... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting app-scoped analytics..."
        if ($Script:COLLECT_USAGE) {
            foreach ($app in $Script:SELECTED_APPS) {
                if (Test-Path (Join-Path $Script:EXPORT_DIR $app)) {
                    Export-AppAnalytics -AppName $app
                }
            }
            Write-Success "App-scoped analytics collected (see each app's splunk-analysis/ folder)"
        }
        $collected++
    }

    # Global usage analytics
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "usage_analytics")) {
        Write-Host "  [$currentStep/$totalSteps] Global usage analytics... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Running global usage analytics..."
        Export-UsageAnalytics
        $collected++
    }

    # Indexes
    $currentStep++
    if ($Script:RESUME_MODE -and (Test-HasCollectedData "indexes")) {
        Write-Host "  [$currentStep/$totalSteps] Index information... ${Script:GREEN}SKIP (already collected)${Script:NC}"
        $skipped++
    } else {
        Write-Host "  [$currentStep/$totalSteps] Collecting index information..."
        Export-IndexData
        $collected++
    }

    if ($Script:RESUME_MODE) {
        Write-Host ""
        Write-Info "Resume summary: $collected collected, $skipped skipped (already had data)"
    }

    Write-Host ""
    Write-BoxFooter
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Invoke-Main {
    # Handle --version
    if ($Script:Version) {
        Write-Host "DMA Splunk Cloud Export v$($Script:SCRIPT_VERSION)"
        return
    }

    # Handle --help
    if ($Script:ShowHelp) {
        Write-Host "Usage: .\dma-splunk-cloud-export.ps1 [OPTIONS]"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -Stack URL          Splunk Cloud stack URL"
        Write-Host "  -Token TOKEN        API token for authentication"
        Write-Host "  -User USER          Username (if not using token)"
        Write-Host "  -Password PASS      Password (if not using token)"
        Write-Host "  -AllApps            Export all applications"
        Write-Host "  -Apps LIST          Comma-separated list of apps"
        Write-Host "  -Output DIR         Output directory"
        Write-Host "  -Rbac               Collect RBAC/users data (OFF by default)"
        Write-Host "  -Usage              Collect usage analytics (OFF by default)"
        Write-Host "  -Proxy URL          Route all connections through a proxy server (e.g., http://proxy:8080)"
        Write-Host "  -ResumeCollect FILE Resume a previous interrupted export from a .tar.gz archive"
        Write-Host "  -SkipInternal       Skip searches requiring _internal index"
        Write-Host "  -Debug_Mode         Enable verbose debug logging"
        Write-Host "  -NonInteractive     Force non-interactive mode"
        Write-Host "  -SkipAnonymization  Skip data anonymization"
        Write-Host "  -Version            Show version"
        Write-Host "  -Help               Show this help"
        Write-Host ""
        Write-Host "Performance Tips:"
        Write-Host "  For large environments, use -Apps with specific apps:"
        Write-Host "    .\dma-splunk-cloud-export.ps1 -Stack acme.splunkcloud.com -Token XXX -Apps 'myapp'"
        return
    }

    # Handle resume mode - extract previous archive early
    if ($Script:RESUME_MODE) {
        Resume-FromArchive -ArchivePath $Script:RESUME_ARCHIVE
    }

    # Determine interactive vs non-interactive mode
    $hasStack = [bool]$Script:SPLUNK_STACK
    $hasAuth = [bool]$Script:AUTH_TOKEN -or ([bool]$Script:SPLUNK_USER -and [bool]$Script:SPLUNK_PASSWORD)

    # Provide helpful feedback for partial params
    if ($hasStack -and -not $hasAuth) {
        Write-Host ""
        Write-Host "${Script:YELLOW}$([char]0x26A0) WARNING: -Stack provided but no authentication${Script:NC}"
        Write-Host "${Script:DIM}  For non-interactive mode, also provide:${Script:NC}"
        Write-Host "${Script:DIM}    -Token YOUR_TOKEN${Script:NC}"
        Write-Host "${Script:DIM}    OR -User USER -Password PASS${Script:NC}"
        Write-Host ""
        Write-Host "${Script:DIM}  Falling back to interactive mode...${Script:NC}"
        Write-Host ""
    }

    if (-not $hasStack -and $hasAuth) {
        Write-Host ""
        Write-Host "${Script:YELLOW}$([char]0x26A0) WARNING: Authentication provided but no -Stack${Script:NC}"
        Write-Host "${Script:DIM}  For non-interactive mode, also provide:${Script:NC}"
        Write-Host "${Script:DIM}    -Stack your-stack.splunkcloud.com${Script:NC}"
        Write-Host ""
        Write-Host "${Script:DIM}  Falling back to interactive mode...${Script:NC}"
        Write-Host ""
    }

    if ($hasStack -and $hasAuth) {
        $Script:NON_INTERACTIVE = $true
    }

    Show-Banner

    if ($Script:NON_INTERACTIVE) {
        # =====================================================================
        # NON-INTERACTIVE MODE
        # =====================================================================
        $Script:SPLUNK_STACK = $Script:SPLUNK_STACK -replace '^https://', '' -replace ':8089$', '' -replace '/$', ''
        $Script:SPLUNK_URL = "https://$($Script:SPLUNK_STACK):8089"

        Write-Info "Running in NON-INTERACTIVE mode (all required parameters provided)"
        Write-Info "  Stack: $($Script:SPLUNK_STACK)"
        Write-Info "  Auth:  $($Script:AUTH_METHOD)"

        if ($Script:SELECTED_APPS.Count -gt 0) {
            Write-Info "  Apps:  $($Script:SELECTED_APPS -join ', ')"
        } else {
            Write-Info "  Apps:  all (will fetch from API)"
        }
        if ($Script:SCOPE_TO_APPS) { Write-Info "  Mode:  App-scoped analytics" }
        if ($Script:PROXY_URL) { Write-Info "  Proxy: $($Script:PROXY_URL)" }
        if ($Script:DEBUG_MODE) { Write-Info "  Debug: ENABLED (verbose logging)" }
        if ($Script:COLLECT_RBAC) { Write-Info "  RBAC:  ENABLED" } else { Write-Info "  RBAC:  DISABLED (use -Rbac to enable)" }
        if ($Script:COLLECT_USAGE) { Write-Info "  Usage: ENABLED" } else { Write-Info "  Usage: DISABLED (use -Usage to enable)" }
        Write-Host ""

        Write-DebugConfigState

        if (-not (Test-SplunkConnectivity $Script:SPLUNK_URL)) { exit 1 }
        if (-not (Connect-SplunkCloud)) { exit 1 }
        Test-UserCapabilities

        # Get server info
        $serverInfo = Invoke-SplunkApi -Endpoint "/services/server/info" -Data "output_mode=json"
        if ($serverInfo -and $serverInfo.entry) {
            $entry = @($serverInfo.entry)[0]
            $Script:SPLUNK_VERSION = $entry.content.version
            $Script:SERVER_GUID = $entry.content.guid
        }
        $Script:CLOUD_TYPE = "cloud"
        Write-Info "Connected to Splunk Cloud v$($Script:SPLUNK_VERSION)"

        # Get apps if exporting all
        if ($Script:EXPORT_ALL_APPS -or $Script:SELECTED_APPS.Count -eq 0) {
            Write-Host ""
            Write-Host "  ${Script:YELLOW}$([char]0x26A0) WARNING: No -Apps filter specified${Script:NC}"
            Write-Host "  ${Script:DIM}Will export ALL applications. This may be slow in large environments.${Script:NC}"
            Write-Host ""

            Write-Info "Fetching app list from Splunk Cloud..."
            $appsResponse = Invoke-SplunkApi -Endpoint "/services/apps/local" -Data "output_mode=json&count=0"
            if ($appsResponse -and $appsResponse.entry) {
                $Script:SELECTED_APPS = @()
                foreach ($entry in @($appsResponse.entry)) {
                    $Script:SELECTED_APPS += $entry.name
                }
            }

            if ($Script:SELECTED_APPS.Count -gt 50) {
                Write-Warning2 "Found $($Script:SELECTED_APPS.Count) apps - this is a large environment!"
                Write-Warning2 "Consider using -Apps to filter for faster exports"
            }
        }

        $Script:STATS_APPS = $Script:SELECTED_APPS.Count
        Write-Info "Will export $($Script:STATS_APPS) app(s)"
    } else {
        # =====================================================================
        # INTERACTIVE MODE
        # =====================================================================
        Show-Introduction
        Show-PreflightChecklist
        Get-SplunkStack
        Get-ProxySettings
        Get-Authentication
        Find-SplunkEnvironment
        Select-Applications
        Select-DataCategories
    }

    # Set export start time
    $Script:EXPORT_START_TIME = Get-Date

    # Auto-enable app-scoped mode when specific apps selected
    if (-not $Script:EXPORT_ALL_APPS) {
        if (-not $Script:SCOPE_TO_APPS) {
            Write-Info "App-scoped mode auto-enabled (specific apps selected)"
            Write-Info "  -> Usage analytics will be scoped to: $($Script:SELECTED_APPS -join ', ')"
            Write-Info "  -> Use -AllApps to collect global analytics"
            $Script:SCOPE_TO_APPS = $true
        }
    }

    # Display mode info
    if ($Script:SCOPE_TO_APPS) {
        Write-Host ""
        Write-Host "  ${Script:CYAN}APP-SCOPED MODE${Script:NC}"
        Write-Host "  ${Script:DIM}Collections scoped to selected apps: $($Script:SELECTED_APPS -join ', ')${Script:NC}"
        Write-Host "  ${Script:DIM}Global user/usage analytics will be filtered to these apps${Script:NC}"
        Write-Host ""
    }

    # Run collection
    Start-Collection

    # Generate reports
    New-ExportSummary
    New-ExportManifest

    # Generate troubleshooting report if errors
    if ($Script:STATS_ERRORS -gt 0) {
        Write-Warning2 "Export encountered $($Script:STATS_ERRORS) error(s). Generating troubleshooting report..."
        New-TroubleshootingReport
    }

    # v4.3.0: Versioned archive naming for resumed exports
    $originalExportName = $null
    if ($Script:RESUME_MODE) {
        $version = 2
        while ((Test-Path "$($Script:EXPORT_NAME)-v${version}.tar.gz") -or (Test-Path "$($Script:EXPORT_NAME)-v${version}_masked.tar.gz")) {
            $version++
        }
        $originalExportName = $Script:EXPORT_NAME
        $Script:EXPORT_NAME = "$($originalExportName)-v${version}"
        Write-Info "Resume archive will be named: $($Script:EXPORT_NAME).tar.gz"
    }

    # v4.2.5: Two-archive approach for anonymization
    if ($Script:ANONYMIZE_DATA) {
        # Create original archive first, keeping EXPORT_DIR for masked copy
        New-ExportArchive -KeepDir $true

        # Create masked (anonymized) archive from a copy
        New-MaskedArchive
    } else {
        # No anonymization - just create single archive
        New-ExportArchive
    }

    # Restore original EXPORT_NAME if it was modified for versioning
    if ($Script:RESUME_MODE -and $originalExportName) {
        $Script:EXPORT_NAME = $originalExportName
    }

    # Show export timing statistics
    Show-ExportTimingStats

    # Clear checkpoint on success
    Clear-Checkpoint

    # Show completion
    Show-ExportSummary

    # Clear sensitive data
    $Script:AUTH_TOKEN = ""
    $Script:SPLUNK_PASSWORD = ""
    $Script:SESSION_KEY = ""
}

# =============================================================================
# ENTRY POINT
# =============================================================================
Invoke-Main
