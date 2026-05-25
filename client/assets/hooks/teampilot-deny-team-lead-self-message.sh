#!/usr/bin/env bash
# TeamPilot PreToolUse: block team-lead self-targeting on SendMessage / TaskUpdate / Agent.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "teampilot-deny-team-lead-self-message: jq is required" >&2
  exit 0
fi

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")

deny() {
  local reason=$1
  jq -nc --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

case "$TOOL" in
  SendMessage)
    TO=$(jq -r '.tool_input.to // empty' <<<"$INPUT")
    TO_LC=$(printf '%s' "$TO" | tr '[:upper:]' '[:lower:]')
    if [ "$TO_LC" = "team-lead" ]; then
      deny "Team lead cannot SendMessage to team-lead. Reply in this terminal or message other roster names."
      exit 0
    fi
    ;;
  TaskUpdate)
    OWNER=$(jq -r '.tool_input.owner // empty' <<<"$INPUT")
    OWNER_LC=$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')
    if [ "$OWNER_LC" = "team-lead" ]; then
      deny "Team lead cannot set task owner to team-lead. Assign tasks to other teammate names from the roster."
      exit 0
    fi
    ;;
  Agent)
    deny "Team lead cannot use Agent in TeamPilot teams. Each teammate has its own terminal — assign work via SendMessage and the shared task list (TaskCreate/TaskUpdate); teammates run Bash/Read/Edit/Write."
    exit 0
    ;;
esac

exit 0
