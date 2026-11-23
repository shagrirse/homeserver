#!/usr/bin/env bash
# Print the SHAs of the commits a hook should inspect, one per line, oldest first.
#   - During a push (PRE_COMMIT_REMOTE_NAME set): every local branch and tag commit
#     the remote does not have yet, including a detached HEAD. An empty selection is valid and prints nothing.
#   - Otherwise, with PRE_COMMIT_FROM_REF and PRE_COMMIT_TO_REF set: FROM..TO.
#   - Otherwise: print "no range" to stderr and exit 1, so a scan never covers nothing.
set -euo pipefail

if [[ -n "${PRE_COMMIT_REMOTE_NAME:-}" ]]; then
  git rev-list --reverse --branches --tags HEAD --not --remotes="$PRE_COMMIT_REMOTE_NAME"
elif [[ -n "${PRE_COMMIT_FROM_REF:-}" && -n "${PRE_COMMIT_TO_REF:-}" ]]; then
  git rev-list --reverse "$PRE_COMMIT_FROM_REF..$PRE_COMMIT_TO_REF"
else
  echo "no range" >&2
  exit 1
fi
