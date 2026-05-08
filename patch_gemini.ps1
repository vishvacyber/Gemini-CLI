<#
.SYNOPSIS
Unofficial Katteni Fix for Gemini CLI (PR-26392) - Yuzuko Edition

.DESCRIPTION
This script patches the Gemini CLI bundle to improve reliability on Windows.
Features:
- Model selection loop (Auto-fallback from Flash to Pro/Lite)
- Dynamic token limits (Up to 10M for Gemini 3)
- Enhanced UI feedback during retries
- Safe process termination (Taskkill with self-kill protection)

Tested on: Gemini CLI v0.41.2
License: MIT
Maintainer: DovahkiinYuzuko
#>

param(
    [switch]$Restore,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " Unofficial Katteni Fix for Gemini CLI (Yuzuko Edition)" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

# --- 0. Environment Checks ---
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    Write-Host "[ERROR] This script is strictly for Windows." -ForegroundColor Red
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[WARN] Not running as Administrator. File write operations may fail." -ForegroundColor Yellow
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] npm is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# --- 1. Detect target directory ---
Write-Host "`n[INFO] Detecting npm global modules path..."
try {
    $npmRoot = (& npm root -g 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($npmRoot)) {
        throw "npm root -g failed or returned empty."
    }
} catch {
    Write-Host "[ERROR] Failed to execute 'npm root -g'." -ForegroundColor Red
    exit 1
}

$targetDir = Join-Path $npmRoot "@google/gemini-cli/bundle"
if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] Gemini CLI bundle not found at: $targetDir" -ForegroundColor Red
    exit 1
}

Set-Location $targetDir
Write-Host "[INFO] Target directory: $targetDir`n" -ForegroundColor Green

# --- 2. Restore Mode ---
if ($Restore) {
    Write-Host "[INFO] Initiating Restore Mode..." -ForegroundColor Yellow
    $restoredCount = 0
    Get-ChildItem -File -Filter "*.js" | ForEach-Object {
        $file = $_.FullName
        $fileName = $_.Name
        $backups = Get-ChildItem -Path (Split-Path $file) -Filter "$fileName.*.bak" -File | Sort-Object CreationTime -Descending
        
        if ($backups.Count -gt 0) {
            $latestBackup = $backups[0]
            if (-not $DryRun) {
                Copy-Item -Path $latestBackup.FullName -Destination $file -Force
            }
            Write-Host "  [RESTORED] $fileName <- $($latestBackup.Name)" -ForegroundColor Green
            $restoredCount++
        }
    }
    Write-Host "`n[SUCCESS] Processed $restoredCount files." -ForegroundColor Magenta
    exit 0
}

# --- 3. Patch Mode ---
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$totalApplied = 0
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$patchRules = @(
    # Existing PR fixes
    @{
        Name = "Slash Commands Trim"
        Match = '(?<!\.trim\(\))\.startsWith\("\/"\)'
        ReplaceTarget = '([a-zA-Z0-9_$]+)\.(?!trim\(\)\.)startsWith\("\/"\)'
        ReplaceWith = '$1.trim().startsWith("/")'
    },
    @{
        Name = "Zombie Process (SIGKILL/SIGTERM) with Guard"
        Match = '(?<!pid===process\.pid\|\|pid===process\.ppid\?undefined:)process\.kill\(-pid,\s*(initialSignal|"SIGKILL")\)'
        ReplaceTarget = '(?<!pid===process\.pid\|\|pid===process\.ppid\?undefined:)process\.kill\(-pid,\s*(initialSignal|"SIGKILL")\)'
        ReplaceWith = '(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,$1))'
    },
    @{
        Name = "API Retry (Add POST)"
        Match = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceTarget = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceWith = 'var retryMethods = ["get", "post", "put", "head", "delete", "options", "trace"];'
    },

    # New Yuzuko Edition fixes
    @{
        Name = "Model Selection Loop (Auto-Fallback)"
        Match = 'resolvePolicyChain\(([a-zA-Z0-9_$]+),\s*([a-zA-Z0-9_$]+)\)(?!\s*,\s*true)'
        ReplaceTarget = 'resolvePolicyChain\(([a-zA-Z0-9_$]+),\s*([a-zA-Z0-9_$]+)\)'
        ReplaceWith = 'resolvePolicyChain($1, $2, true)'
    },
    @{
        Name = "Dynamic Token Limits (Gemini 3 Support)"
        Match = 'function tokenLimit\([a-zA-Z0-9_$]+\)\s*\{\s*(?!if\(.*\.includes\("gemini-3"\)\))'
        ReplaceTarget = 'function tokenLimit\(([a-zA-Z0-9_$]+)\)\s*\{\s*(?!if\(.*\.includes\("gemini-3"\)\))switch\s*\(\$1\)\s*\{'
        ReplaceWith = 'function tokenLimit($1){if($1.includes("gemini-3"))return 10000000;switch($1){'
    },
    @{
        Name = "Token Limit Default (2M)"
        Match = 'var DEFAULT_TOKEN_LIMIT = 1048576;'
        ReplaceTarget = 'var DEFAULT_TOKEN_LIMIT = 1048576;'
        ReplaceWith = 'var DEFAULT_TOKEN_LIMIT = 2000000;'
    },
    @{
        Name = "Retry UI Feedback (Model Switching Message)"
        Match = 'onRetry:\s*\((attempt,\s*error[a-zA-Z0-9_$]*,\s*delayMs)\)\s*=>\s*\{\s*(?!const isModelChanged)'
        ReplaceTarget = 'onRetry:\s*\((attempt,\s*error[a-zA-Z0-9_$]*,\s*delayMs)\)\s*=>\s*\{\s*(?!const isModelChanged)'
        ReplaceWith = 'onRetry: ($1) => { const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to ${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined;'
    },
    @{
        Name = "Retry Payload Expansion (Emit Message)"
        Match = 'model:\s*getDisplayString\(currentAttemptModel\)(?!,\s*message)'
        ReplaceTarget = 'model:\s*getDisplayString\(currentAttemptModel\)(?!,\s*message)'
        ReplaceWith = 'model: getDisplayString(currentAttemptModel), message'
    },
    @{
        Name = "UI Loader Message Support"
        Match = '(?<!retryStatus\.message \? retryStatus\.message : )retryStatus\.attempt\s*>=\s*[A-Z_]+_RETRY_HINT_ATTEMPT_THRESHOLD\s*\?\s*"[^"]*"\s*:\s*null'
        ReplaceTarget = '(?<!retryStatus\.message \? retryStatus\.message : )retryStatus\.attempt\s*>=\s*[A-Z_]+_RETRY_HINT_ATTEMPT_THRESHOLD\s*\?\s*"[^"]*"\s*:\s*null'
        ReplaceWith = 'retryStatus.message ? retryStatus.message : $&'
    }
)

if ($DryRun) {
    Write-Host "[INFO] Running in DRY-RUN mode.`n" -ForegroundColor Yellow
}

# Apply patches across all bundle files
$targetFiles = Get-ChildItem -File -Filter "*.js"
foreach ($file in $targetFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $filePatched = $false

    foreach ($rule in $patchRules) {
        if ($content -match $rule.Match) {
            $content = $content -replace $rule.ReplaceTarget, $rule.ReplaceWith
            $filePatched = $true
        }
    }

    if ($filePatched -and ($originalContent -ne $content)) {
        if (-not $DryRun) {
            $backupPath = "$($file.FullName).$timestamp.bak"
            Copy-Item $file.FullName $backupPath
            Write-Utf8NoBom -Path $file.FullName -Content $content
            $totalApplied++
        }
        Write-Host "  [PATCHED] $($file.Name)" -ForegroundColor Green
    }
}

Write-Host "-----------------------------------------------------------"
if ($totalApplied -gt 0 -or $DryRun) {
    Write-Host "[SUCCESS] Operation complete." -ForegroundColor Magenta
} else {
    Write-Host "[WARN] No patches were applied." -ForegroundColor Yellow
}