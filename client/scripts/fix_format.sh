#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FORMAT_DIRS=(lib test tool)

echo "Formatting..."
dart format "${FORMAT_DIRS[@]}"

echo "Applying fixes..."
for dir in "${FORMAT_DIRS[@]}"; do
  dart fix --apply "$dir"
done

echo "Done. Run scripts/check_format.sh to verify."
