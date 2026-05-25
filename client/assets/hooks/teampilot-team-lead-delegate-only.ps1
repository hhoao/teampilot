# TeamPilot PreToolUse: team-lead delegate-only mode — block local execution tools.
$ErrorActionPreference = 'Stop'

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
      permissionDecisionReason = "Team lead delegate-only mode is on: $tool is disabled in this tab. Plan here; assign via SendMessage to roster teammate names and the shared task list (TaskCreate/TaskUpdate)."
    }
  }
  $obj | ConvertTo-Json -Compress -Depth 5
  exit 0
}

exit 0
