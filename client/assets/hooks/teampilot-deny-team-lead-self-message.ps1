# TeamPilot PreToolUse: block team-lead self-targeting on SendMessage / TaskUpdate / Agent.
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

function Write-Deny([string]$Reason) {
  $obj = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName          = 'PreToolUse'
      permissionDecision     = 'deny'
      permissionDecisionReason = $Reason
    }
  }
  $obj | ConvertTo-Json -Compress -Depth 5
  exit 0
}

switch ($tool) {
  'SendMessage' {
    $to = [string]$payload.tool_input.to
    if ($to.ToLowerInvariant() -eq 'team-lead') {
      Write-Deny 'Team lead cannot SendMessage to team-lead. Reply in this terminal or message other roster names.'
    }
  }
  'TaskUpdate' {
    $owner = [string]$payload.tool_input.owner
    if ($owner.ToLowerInvariant() -eq 'team-lead') {
      Write-Deny 'Team lead cannot set task owner to team-lead. Assign tasks to other teammate names from the roster.'
    }
  }
  'Agent' {
    Write-Deny 'Team lead cannot use Agent in TeamPilot teams. Each teammate has its own terminal — assign work via SendMessage and the shared task list (TaskCreate/TaskUpdate); teammates run Bash/Read/Edit/Write.'
  }
}

exit 0
