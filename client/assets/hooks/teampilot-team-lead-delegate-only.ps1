# TeamPilot PreToolUse: team-lead delegate-only mode — block local execution tools.
$ErrorActionPreference = 'Stop'
# Emit UTF-8 so non-ASCII chars (em-dash, quotes) in deny reasons reach Claude intact.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$inputRaw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($inputRaw)) { exit 0 }

try {
  $payload = $inputRaw | ConvertFrom-Json
} catch {
  exit 0
}

$tool = [string]$payload.tool_name

# Keep in sync with TeamLeadDelegateSettingsMerge.blockedToolsMatcher in Dart.
$blocked = @(
  'Bash', 'Edit', 'Write', 'NotebookEdit', 'PowerShell',
  'Skill', 'ExecuteExtraTool', 'REPL', 'workflow',
  'EnterWorktree', 'ExitWorktree', 'RemoteTrigger', 'CronCreate'
)

if ($blocked -contains $tool) {
  $obj = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName          = 'PreToolUse'
      permissionDecision     = 'deny'
      permissionDecisionReason = "Team lead delegate-only mode is on: $tool is disabled in this tab. Inspect with Read/Glob/Grep and plan here, then hand all execution to your teammates through your team's messaging and shared task list — do not run it yourself."
    }
  }
  $obj | ConvertTo-Json -Compress -Depth 5
  exit 0
}

exit 0
