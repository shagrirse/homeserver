#!/usr/bin/env bash
# PreToolUse: block reads of the age key, decrypted secrets, the real inventory
# and cluster Secret values. Exit 2 blocks the call and shows stderr to the agent.
# Best-effort defense in depth on the raw command text, not a complete guard.
set -euo pipefail

command -v jq >/dev/null || { echo "block-secrets: jq missing, refusing to run unchecked." >&2; exit 2; }

input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
target=$(jq -r '.tool_input.file_path // .tool_input.command // ""' <<<"$input")

files='sops/age|keys\.txt|\.agekey|age\.key|\.dec\.ya?ml|provision/inventory\.yml'
sops_decrypt='\bsops\b.*([[:space:]]-d\b|--decrypt|[[:space:]]decrypt\b|[[:space:]]exec-(env|file)\b)'
kubectl_secret='\bkubectl\b.*\bget\b.*[^[:alnum:]_-][Ss][Ee][Cc][Rr][Ee][Tt][Ss]?([^[:alnum:]_-]|$)'

if [[ "$tool" == "Read" || "$tool" == "Bash" ]] && grep -Eq "$files|$sops_decrypt|$kubectl_secret" <<<"$target"; then
  echo "Blocked: touches the age key, decrypted secrets, real inventory or Secret values. Use 'sops <file>' to edit in place and 'kubectl describe' for key names." >&2
  exit 2
fi
