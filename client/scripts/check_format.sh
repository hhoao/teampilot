#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FORMAT_DIRS=(lib test tool)

echo "Checking format..."
dart format --output=none --set-exit-if-changed "${FORMAT_DIRS[@]}"

echo "Checking fixes..."
fix_needed=0
for dir in "${FORMAT_DIRS[@]}"; do
  fix_output="$(dart fix --dry-run "$dir" 2>&1)" || true
  printf '%s\n' "$fix_output"
  if printf '%s\n' "$fix_output" | grep -q 'proposed fix'; then
    fix_needed=1
  fi
done
if [ "$fix_needed" -ne 0 ]; then
  echo "Pending dart fix changes. Run scripts/fix_format.sh"
  exit 1
fi

echo "Analyzing..."
flutter analyze --no-fatal-infos --no-fatal-warnings

echo "All checks passed."
