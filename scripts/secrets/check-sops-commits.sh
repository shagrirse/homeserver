#!/usr/bin/env bash
# Fail when any commit in the selected range adds, modifies, renames or copies a
# <name>.sops.yaml or <name>.sops.yml file (not the root .sops.yaml rules file) whose content in that commit is not SOPS-encrypted.
# Commits come from range.sh. Deletions are ignored; paths are handled NUL-delimited.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
commits="$("$here/range.sh")"

status=0
while IFS= read -r commit; do
  [[ -n "$commit" ]] || continue
  while IFS= read -r -d '' path; do
    [[ "$path" =~ \.sops\.ya?ml$ ]] || continue
    [[ "$path" =~ ^\.sops\.ya?ml$ ]] && continue # root SOPS creation rules, not a secret
    content="$(git show "$commit:$path")"
    if [[ "$content" != *'ENC[AES256_GCM'* ]]; then
      printf '%s %s: not SOPS-encrypted\n' "$(git rev-parse --short "$commit")" "$path"
      status=1
    fi
  done < <(git diff-tree --no-commit-id -r --root -z --name-only --diff-filter=AMRC "$commit")
done <<<"$commits"

exit "$status"
