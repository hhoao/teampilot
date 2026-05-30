# rtk-hook-version: 3
# RTK Claude Code hook — rewrites commands to use rtk for token savings.
# Requires: rtk >= 0.23.0, jq
$ErrorActionPreference = 'Stop'

function Test-Command([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'jq')) {
  Write-Warning '[rtk] WARNING: jq is not installed. Hook cannot rewrite commands. Install jq: https://jqlang.github.io/jq/download/'
  exit 0
}

if (-not (Test-Command 'rtk')) {
  Write-Warning '[rtk] WARNING: rtk is not installed or not in PATH. Hook cannot rewrite commands. Install: https://github.com/rtk-ai/rtk#installation'
  exit 0
}

$cacheDir = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $env:USERPROFILE '.cache' }
$cacheFile = Join-Path $cacheDir 'rtk-hook-version-ok'
if (-not (Test-Path $cacheFile)) {
  $rtkVersionRaw = (& rtk --version 2>$null) -join ' '
  $rtkVersion = ($rtkVersionRaw -replace '^rtk\s*', '').Split(' ')[0]
  if ($rtkVersion) {
    $parts = $rtkVersion.Split('.')
    $major = [int]($parts[0])
    $minor = if ($parts.Length -gt 1) { [int]($parts[1]) } else { 0 }
    if ($major -eq 0 -and $minor -lt 23) {
      Write-Warning "[rtk] WARNING: rtk $rtkVersion is too old (need >= 0.23.0). Upgrade: cargo install rtk"
      exit 0
    }
  }
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  New-Item -ItemType File -Force -Path $cacheFile | Out-Null
}

$inputRaw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputRaw)) { exit 0 }

try {
  $payload = $inputRaw | ConvertFrom-Json
} catch {
  exit 0
}

$cmd = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

$rewritten = (& rtk rewrite $cmd 2>$null) -join "`n"
$exitCode = $LASTEXITCODE

switch ($exitCode) {
  0 {
    if ($cmd -eq $rewritten) { exit 0 }
  }
  1 { exit 0 }
  2 { exit 0 }
  default { exit 0 }
}

$payload.tool_input.command = $rewritten

if ($exitCode -eq 3) {
  @{
    hookSpecificOutput = @{
      hookEventName = 'PreToolUse'
      updatedInput    = $payload.tool_input
    }
  } | ConvertTo-Json -Compress -Depth 10
} else {
  @{
    hookSpecificOutput = @{
      hookEventName            = 'PreToolUse'
      permissionDecision       = 'allow'
      permissionDecisionReason = 'RTK auto-rewrite'
      updatedInput             = $payload.tool_input
    }
  } | ConvertTo-Json -Compress -Depth 10
}
