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
BLOCKED_RE='^(Bash|Read|Edit|Write|Glob|Grep|NotebookEdit|PowerShell)$'

if [[ "$TOOL" =~ $BLOCKED_RE ]]; then
  jq -nc --arg tool "$TOOL" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Team lead delegate-only mode is on: " + $tool + " is disabled in this tab. Plan here; assign via SendMessage to roster teammate names and the shared task list (TaskCreate/TaskUpdate). Teammates run Bash/Read/Edit/Write.")
    }
  }'
  exit 0
fi

exit 0
