#!/usr/bin/env bash
# TeamPilot PreToolUse: block team lead from SendMessage to team-lead (self-loop).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "teampilot-deny-team-lead-self-message: jq is required" >&2
  exit 0
fi

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
[ "$TOOL" = "SendMessage" ] || exit 0

TO=$(jq -r '.tool_input.to // empty' <<<"$INPUT")
TO_LC=$(printf '%s' "$TO" | tr '[:upper:]' '[:lower:]')

if [ "$TO_LC" = "team-lead" ]; then
  jq -nc '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Team lead cannot SendMessage to team-lead (self-loop). Reply in this terminal or message other teammate names."
    }
  }'
  exit 0
fi

exit 0
