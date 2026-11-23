#!/usr/bin/env bash
# PostToolUse: run the repo's pre-commit checks on the file just edited.
# Thin adapter only; the checks and their exclusions live in .pre-commit-config.yaml.
# Exit 2 feeds failures back to the agent.
set -euo pipefail

file=$(jq -r '.tool_input.file_path // ""' <<<"$(cat)")
[[ -f "$file" ]] || exit 0
command -v pre-commit >/dev/null || { echo "pre-commit missing" >&2; exit 2; }

cd "${CLAUDE_PROJECT_DIR:-.}"
case "$(realpath "$file")" in
  "$(realpath .)"/*) ;;
  *) exit 0 ;;
esac

if ! out=$(SKIP=gitleaks pre-commit run --files "$file" 2>&1); then
  echo "$out" >&2
  exit 2
fi

if ! out=$(pre-commit run --hook-stage manual gitleaks-file --files "$file" 2>&1); then
  echo "$out" >&2
  exit 2
fi
