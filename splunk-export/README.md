# DMA Splunk Export Scripts

**Version**: 4.3.0
**Last Updated**: February 2026

## What's New in v4.3.0

### Resume Collection from Partial Archives

Cloud scripts now support the `--resume-collect` flag (Bash) or `-ResumeCollect` parameter (PowerShell). Pass a previous `.tar.gz` archive and the script will extract it, detect already-collected data, fill in any gaps, and output versioned archives with `-v1`, `-v2`, `-v3` suffixes. This is also useful for adding `--rbac` or `--usage` to an already-complete export without re-collecting everything.

```bash
# Bash: Resume a partial Cloud export
./dma-splunk-cloud-export.sh --resume-collect dma_export_acme_20260115_120000.tar.gz

# Bash: Add RBAC and usage to a complete export
./dma-splunk-cloud-export.sh --resume-collect dma_export_acme_20260115_120000.tar.gz --rbac --usage
```

```powershell
# PowerShell: Resume a partial Cloud export
.\dma-splunk-cloud-export.ps1 -ResumeCollect dma_export_acme_20260115_120000.tar.gz

# PowerShell: Add RBAC and usage to a complete export
.\dma-splunk-cloud-export.ps1 -ResumeCollect dma_export_acme_20260115_120000.tar.gz -Rbac -Usage
```

### 12-Hour Maximum Runtime

All scripts now support `MAX_TOTAL_TIME=43200` (12 hours, up from 4 hours), allowing large-scale enterprise exports to complete without timing out.

### PowerShell Cloud Export Script

New `dma-splunk-cloud-export.ps1` provides full feature parity with the Bash Cloud script for Windows environments. Zero external dependencies required — works with PowerShell 5.1+ and PowerShell 7+. Supports the same collection categories, flags, anonymization, resume collection, and automation features as the Bash Cloud script.

### Proxy Support

Cloud scripts (both Bash and PowerShell) now support routing all connections through a corporate proxy server. This is essential for enterprise environments where direct internet access to Splunk Cloud is blocked.

```bash
# Bash: Route through corporate proxy
./dma-splunk-cloud-export.sh --proxy http://proxy.company.com:8080 --stack acme.splunkcloud.com --token "$TOKEN"
```

```powershell
# PowerShell: Route through corporate proxy
.\dma-splunk-cloud-export.ps1 -Proxy "http://proxy.company.com:8080" -Stack "acme.splunkcloud.com" -Token $TOKEN
```

Key behaviors:
- **Interactive prompt**: If not provided via flag, the script asks during setup whether a proxy is needed (default: No)
- **Adaptive connectivity tests**: DNS and TCP port tests are skipped when a proxy is configured (the proxy handles routing)
- **All API calls routed**: Every `curl` / `Invoke-WebRequest` call uses the proxy
- **Non-interactive support**: Pass `--proxy` / `-Proxy` for fully automated exports

---

### Previous v4.2.4 Changes

### Two-Archive Anonymization (Preserves Original Data)
When anonymization is enabled, the script now creates **TWO archives**:
- `{export_name}.tar.gz` - **Original, untouched data**
- `{export_name}_masked.tar.gz` - **Anonymized copy for sharing**

This preserves the original data in case anonymization corrupts files. Users can re-run anonymization on the original without re-running the entire export.

### Performance Optimizations
- **RBAC/Users collection now OFF by default** - Use `--rbac` to enable
- **Usage analytics now OFF by default** - Use `--usage` to enable
- **Faster defaults**: Batch size 250 (was 100), API delay 50ms (was 250ms)
- **Optimized queries**: Sampling for expensive regex extractions, `max()` instead of `latest()` for faster aggregations
- **Savedsearches ACL fix**: Now correctly filters searches by app ownership

### Previous v4.2.0 Changes
- **App-Centric Dashboard Structure (v2)**: Dashboards saved to `{AppName}/dashboards/classic/` and `{AppName}/dashboards/studio/`
- **Manifest Schema v4.0**: Added `archive_structure_version: "v2"`

---

> **Developed for Dynatrace One by Enterprise Solutions & Architecture**
> *An ACE Services Division of Dynatrace*

---

## Overview

This directory contains the **DMA Export Scripts** - comprehensive tools for extracting configuration data, dashboards, alerts, and usage analytics from Splunk environments to enable migration to Dynatrace Gen3.

These scripts are the first step in the Dynatrace Migration Assistant migration workflow. The export archive they produce is uploaded to the DMA app in Dynatrace, where it powers dashboard conversion, alert migration, and data pipeline planning.

---

## Quick Start

### Splunk Enterprise (On-Premises)

```bash
# Copy script to your Splunk Search Head
scp dma-splunk-export.sh splunk-server:/tmp/

# SSH to the server and run as splunk user
ssh splunk-server
sudo -u splunk bash /tmp/dma-splunk-export.sh

# Follow the interactive prompts
# Download the .tar.gz export file when complete
```

### Splunk Cloud (Linux/macOS)

```bash
# Run from YOUR machine (not on Splunk Cloud)
# You need network access to your Splunk Cloud instance

./dma-splunk-cloud-export.sh

# Enter your stack URL and credentials when prompted
```

### Splunk Cloud (Windows)

```powershell
# Run from YOUR Windows machine (not on Splunk Cloud)
.\dma-splunk-cloud-export.ps1

# Or non-interactive with token
.\dma-splunk-cloud-export.ps1 -Stack "acme-corp.splunkcloud.com" -Token "your-token"
```

---

## Available Scripts

| Script | Target Environment | Platform | Access Method |
|--------|-------------------|----------|---------------|
| `dma-splunk-export.sh` | Splunk Enterprise (on-premises) | Bash (Linux/macOS) | SSH + File System + REST API |
| `dma-splunk-cloud-export.sh` | Splunk Cloud (Classic & Victoria) | Bash (Linux/macOS) | REST API only |
| `dma-splunk-cloud-export.ps1` | Splunk Cloud (Classic & Victoria) | PowerShell (Windows) | REST API only |

### Key Differences

| Aspect | Enterprise Script | Cloud Script |
|--------|------------------|--------------|
| **Where to run** | ON the Splunk Search Head | ANYWHERE (your laptop, jump host) |
| **Access method** | SSH + file system + REST API | REST API only |
| **What you need** | SSH access + splunk user | Network access + API token |
| **Configuration files** | Direct file system access | Reconstructed from REST API |
| **PowerShell script** | N/A | Full parity with Cloud Bash script for Windows environments |

---

## What Gets Exported

Both scripts collect the same categories of data:

| Category | Description | Migration Use |
|----------|-------------|---------------|
| **Dashboards** | Classic XML + Dashboard Studio JSON | Visual conversion to Dynatrace apps |
| **Alerts & Saved Searches** | savedsearches.conf with all definitions | SPL to DQL conversion, alert migration |
| **Configuration Files** | props.conf, transforms.conf, indexes.conf, inputs.conf | OpenPipeline generation, field extraction |
| **Users & RBAC** | Users, roles, capabilities (NO passwords) | Ownership mapping, stakeholder identification |
| **Usage Analytics** | Dashboard views, search frequency, alert executions | Prioritization, elimination candidates |
| **Index Statistics** | Sizes, retention, sourcetypes, volume metrics | Dynatrace bucket planning, capacity estimation |

### What Does NOT Get Exported

- User passwords or password hashes
- API tokens or session keys
- Actual log data (only metadata and structure)
- SSL certificates or private keys

---

## New in v4.1.0

### App-Scoped Export Mode

Target specific apps for faster exports in large environments:

| Flag | Description |
|------|-------------|
| `--apps "app1,app2"` | Export only specified apps |
| `--scoped` | Scope all collections (users, usage) to selected apps |
| `--quick` | **TESTING ONLY** - Skip usage analytics and RBAC |
| `--no-usage` | Skip usage analytics collection |
| `--rbac` | Enable RBAC/user collection (off by default) |
| `--no-rbac` | Skip RBAC/user collection (Enterprise only) |
| `--resume-collect FILE` | Resume collection from a previous partial archive (Cloud only) |
| `--proxy URL` | Route all connections through a proxy server (Cloud only) |
| `--debug` or `-d` | Enable verbose debug logging |

> **⚠️ WARNING: `--quick` is for TESTING ONLY**
>
> Do NOT use `--quick` for migration analysis. It skips usage analytics, user/RBAC data, and priority assessment data critical for migration planning. Use full export (default) or `--scoped` for actual migrations.

### Debug Mode

Enable detailed logging for troubleshooting with `--debug`:
- Color-coded console output (ERROR, WARN, API, SEARCH, TIMING)
- Debug log file: `export_debug.log` included in the export archive
- API call tracking with response times and sizes

---

## Enterprise Resilience Features

Both scripts include enterprise-scale features for large environments:

| Feature | Default | Description |
|---------|---------|-------------|
| Batch Processing | **250 items/request** | Handles 4000+ dashboards, 10K+ alerts |
| API Timeout | 120 seconds | Extended timeout for large queries |
| Max Runtime | 12 hours | Prevents runaway exports |
| Retry Logic | 3 attempts | Exponential backoff on failures |
| Checkpoint/Resume | Enabled | Resume interrupted exports |
| Rate Limiting | **50ms delay** | Faster while preventing API throttling |
| RBAC Collection | **OFF** (use `--rbac`) | Enable when you need user/role data |
| Usage Analytics | **OFF** (use `--usage`) | Enable when you need usage metrics |
| Resume Collection | `--resume-collect` | Resume from partial archive, output versioned archives (Cloud only) |
| Proxy Support | `--proxy` / `-Proxy` | Route all connections through a corporate proxy (Cloud only) |

### Automation Support

```bash
# Non-interactive mode - full export
./dma-splunk-export.sh \
  -u admin \
  -p 'YourPassword' \
  --splunk-home /opt/splunk \
  --anonymize \
  -y  # Auto-confirm all prompts

# App-scoped export with usage data (recommended for large environments)
./dma-splunk-export.sh \
  -u admin \
  -p 'YourPassword' \
  --apps "myapp1,myapp2" \
  --scoped \
  --debug
```

```powershell
# Non-interactive PowerShell export
.\dma-splunk-cloud-export.ps1 `
  -Stack "acme-corp.splunkcloud.com" `
  -Token $env:SPLUNK_CLOUD_TOKEN `
  -AllApps `
  -Rbac -Usage
```

---

## Export Output

Both scripts produce a `.tar.gz` archive with the **v2 app-centric structure**:

```
dma_export_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
├── manifest.json                    # Export metadata (schema v4.0)
├── dma-env-summary.md        # Human-readable summary
├── export.log                       # Export process log
├── _systeminfo/                     # System information
├── _rbac/                           # Users and roles (no passwords)
├── _indexes/                        # Index configurations
├── _usage_analytics/                # Usage data for prioritization
├── _system/                         # System-level configs
└── <app_name>/                      # Per-app configurations
    ├── dashboards/
    │   ├── classic/                 # Classic XML dashboards for this app
    │   │   └── *.xml
    │   └── studio/                  # Dashboard Studio JSON for this app
    │       └── *.json
    ├── default/
    │   ├── props.conf
    │   ├── transforms.conf
    │   └── savedsearches.conf
    ├── local/
    └── lookups/                     # CSV lookup tables
```

**Why App-Centric Structure?**
- Multiple apps can have dashboards with the same name (no collisions)
- Preserves app ownership context for migration planning
- Cleaner organization aligned with Splunk's app model

---

## Documentation

This directory contains comprehensive documentation:

### Prerequisites & Setup

| Document | Description |
|----------|-------------|
| [README-SPLUNK-ENTERPRISE.md](README-SPLUNK-ENTERPRISE.md) | Complete prerequisites guide for Splunk Enterprise exports |
| [README-SPLUNK-CLOUD.md](README-SPLUNK-CLOUD.md) | Complete prerequisites guide for Splunk Cloud exports |

These documents cover:
- Where to run the script (Search Head, SHC Captain, etc.)
- Required Splunk user permissions and capabilities
- Server access requirements (OS user, file system access)
- Step-by-step walkthrough with expected output
- Troubleshooting common issues

### Technical Specifications

| Document | Description |
|----------|-------------|
| [EXPORT-SCHEMA.md](EXPORT-SCHEMA.md) | Guaranteed output schema (v3.4) for all exports |
| [SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md](SPLUNK-ENTERPRISE-EXPORT-SPECIFICATION.md) | Detailed specification for Enterprise script |
| [SPLUNK-CLOUD-EXPORT-SPECIFICATION.md](SPLUNK-CLOUD-EXPORT-SPECIFICATION.md) | Detailed specification for Cloud script |
| [SCRIPT-GENERATED-ANALYTICS-REFERENCE.md](SCRIPT-GENERATED-ANALYTICS-REFERENCE.md) | Reference for all SPL queries used to generate usage analytics |

### HTML Versions (In-App Viewing)

Each markdown document has a corresponding `.dialog.html` version for viewing within the DMA app. These are generated by `generate-html-docs.cjs`.

---

## Data Anonymization

Both scripts support data anonymization for secure sharing with third parties.

### Two-Archive Approach (v4.2.4)

When anonymization is enabled, the script creates **TWO separate archives**:

```
{export_name}.tar.gz          ← Original data (keep for your records)
{export_name}_masked.tar.gz   ← Anonymized copy (safe to share)
```

**Why Two Archives?**
- **Preserves original** - If anonymization corrupts any files, you have the original
- **Re-run without re-export** - Can re-anonymize the original if needed
- **Clear naming** - Obvious which file is safe to share

### What Gets Anonymized

| Data Type | Anonymization Pattern |
|-----------|----------------------|
| Email addresses | `user######@anon.dma.local` |
| Hostnames | `host-########.anon.local` |
| IP addresses | `[IP-REDACTED]` |
| Webhook URLs | `https://webhook.anon.dma.local/hook-###` |
| API keys/tokens | `[API-KEY-########]` |

**Key Properties:**
- **Consistent mapping** - Same original value always produces same anonymized value
- **Irreversible** - SHA-256 hashing, originals cannot be recovered
- **Relationship preserved** - Data relationships remain intact

**When to Use:**
- Share the `_masked` archive with consultants, support teams, or uploading to shared environments
- Keep the original archive for your internal records

---

## Security & Privacy

### What We Do

- Automatically redact passwords in all .conf files
- Redact API tokens and session keys
- Redact SSL passwords and private key references
- Keep all data local (no external transmission)
- Generate exports with restrictive file permissions

### What You Should Do

1. **Transfer securely** - Use SCP, SFTP, or encrypted channels
2. **Delete after upload** - Remove the export file after uploading to DMA
3. **Enable anonymization** - When sharing with external parties
4. **Review before sharing** - Examine export contents if needed

---

## Support Files

| File | Purpose |
|------|---------|
| `dma-style.css` | Styling for HTML documentation |
| `dma-symbol.png` | DMA logo for HTML docs |
| `generate-html-docs.cjs` | Node.js script to generate HTML from markdown |
| `html-template.html` | Template for standalone HTML docs |
| `html-template-dialog.html` | Template for in-app dialog HTML docs |
| `sync-export-script.cjs` | Utility to sync embedded scripts with source |
| `docs_html/` | Generated HTML documentation output |

---

## Workflow Integration

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     DMA MIGRATION WORKFLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. EXPORT (This Directory)                                             │
│     • Run dma-splunk-export.sh on Search Head                    │
│     • OR run dma-splunk-cloud-export.sh from any machine         │
│     • Download .tar.gz export file                                      │
│                                                                          │
│  2. UPLOAD (DMA App in Dynatrace)                                      │
│     • Open Dynatrace Migration Assistant app                            │
│     • Navigate to: Splunk Migration → Import                            │
│     • Drag & drop the .tar.gz file                                     │
│                                                                          │
│  3. ANALYZE & CONVERT                                                   │
│     • View migration analysis report                                    │
│     • Preview dashboard conversions                                     │
│     • Review alert migration recommendations                            │
│     • Generate OpenPipeline templates                                   │
│                                                                          │
│  4. DEPLOY                                                              │
│     • Publish converted dashboards to Dynatrace                         │
│     • Deploy OpenPipeline configurations                                │
│     • Create Dynatrace alerts from SPL queries                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Requirements

### Enterprise Script

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| bash | 4.0+ | `bash --version` |
| curl | Any | `curl --version` |
| Python | 3.x (Splunk bundled) | `$SPLUNK_HOME/bin/python3 --version` |
| tar | Any | `tar --version` |
| jq | Optional | `jq --version` |

### Cloud Script (Bash)

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| bash | 4.0+ | `bash --version` |
| curl | Any | `curl --version` |
| Python 3 | 3.6+ | `python3 --version` |
| jq | Recommended | `jq --version` |

### PowerShell Cloud Script

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| PowerShell | 5.1+ or 7+ | `$PSVersionTable.PSVersion` |
| Windows | 10 1803+ | For built-in tar.exe |
| Network access | Port 8089 | To Splunk Cloud instance |

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Permission denied" | Run as `splunk` user or root |
| "Connection refused" on REST API | Check Splunk is running, port 8089 is open |
| "Unauthorized" (401) | Verify credentials, check user capabilities |
| "Forbidden" (403) | Add `admin_all_objects` capability to user |
| Export takes too long | Reduce batch size, run during off-peak hours |

### Getting Help

1. Check the relevant README document for your environment
2. Review `export.log` in the export directory for detailed error messages
3. Check `TROUBLESHOOTING.md` generated with partial exports
4. Contact the DMA team with error details

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.3.0 | Feb 2026 | Resume collection (`--resume-collect`), PowerShell Cloud script, 12-hour max runtime |
| 4.2.4 | Jan 2026 | Two-archive anonymization, RBAC/usage OFF by default, query optimizations |
| 4.2.0 | Jan 2026 | App-centric dashboard structure (v2), manifest schema v4.0 |
| 4.1.0 | Jan 2026 | App-scoped export mode (`--apps`, `--scoped`, `--quick`), debug mode |
| 4.0.2 | Jan 2026 | Auto-fix for CRLF line endings (Windows download compatibility) |
| 4.0.1 | Jan 2026 | Container-friendly progress display for kubectl/docker |
| 4.0.0 | Jan 2026 | Enterprise resilience: pagination, checkpoints, retry logic |
| 3.4.0 | Dec 2025 | Added ownership mapping for user-centric migration |
| 3.3.0 | Dec 2025 | Added daily volume analysis and volume intelligence |
| 3.2.0 | Dec 2025 | Added usage_intelligence to manifest for prioritization |

---

## License

These scripts are part of the Dynatrace Migration Assistant application and are intended for use with valid Dynatrace licenses.

---

*For complete documentation, see the individual README files for your environment type.*
