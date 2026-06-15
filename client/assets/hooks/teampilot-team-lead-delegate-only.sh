#!/usr/bin/env bash
# TeamPilot PreToolUse: team-lead delegate-only mode — block local execution tools.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "teampilot-team-lead-delegate-only: jq is required" >&2
  exit 0
fi

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")

# Keep in sync with TeamLeadDelegateSettingsMerge.blockedToolsMatcher in Dart.
BLOCKED_RE='^(Bash|Edit|Write|NotebookEdit|PowerShell|Skill|ExecuteExtraTool|REPL|workflow|EnterWorktree|ExitWorktree|RemoteTrigger|CronCreate)$'

if [[ "$TOOL" =~ $BLOCKED_RE ]]; then
  jq -nc --arg tool "$TOOL" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Team lead delegate-only mode is on: " + $tool + " is disabled in this tab. Inspect with Read/Glob/Grep and plan here, then hand all execution to your teammates through your team's messaging and shared task list — do not run it yourself.")
    }
  }'
  exit 0
fi

exit 0
