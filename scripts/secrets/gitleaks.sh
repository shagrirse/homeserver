#!/usr/bin/env bash
# Run gitleaks with the local redaction rules (domain, LAN, hostname, canary) on top of
# the repo config. Usage: gitleaks.sh <mode> [args]
#   staged         staged changes
#   range          commit contents of the commits chosen by range.sh, plus the
#                  combined diff of each merge commit among them
#   meta           commit messages and changed paths of that range, plus branch and
#                  tag names when pushing
#   files <path>.. each path as a directory or file
#   history        every ref, every commit message and every path ever changed; findings
#                  of the canary rule are ignored
#
# Config, first match wins:
#   1. GITLEAKS_CONFIG_TOML (rules content, used in CI)
#   2. <git common dir>/gitleaks-redact.toml
#   3. GITLEAKS_REQUIRE_REDACTION=1: fail with "redaction rules missing"
#   4. the repo .gitleaks.toml alone, with a notice
# Whenever redaction rules are loaded, a runtime canary must be detected first,
# otherwise the script fails with "redaction rules self-test failed".
set -euo pipefail

mode="${1:-}"
[[ $# -gt 0 ]] && shift

cd "$(git rev-parse --show-toplevel)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules="$(git rev-parse --git-common-dir)/gitleaks-redact.toml"
common=(--redact --no-banner --verbose)
leak_exit=42 # distinguishes "findings" from gitleaks errors (exit 1)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -n "${GITLEAKS_CONFIG_TOML:-}" ]]; then
  loaded=1
elif [[ -f "$rules" ]]; then
  export GITLEAKS_CONFIG="$rules"
  loaded=1
elif [[ "${GITLEAKS_REQUIRE_REDACTION:-}" == 1 ]]; then
  echo "redaction rules missing" >&2
  exit 1
else
  echo "gitleaks: no redaction rules, using .gitleaks.toml" >&2
  export GITLEAKS_CONFIG=.gitleaks.toml
  loaded=0
fi

if [[ $loaded == 1 ]]; then
  canary="hs-canary-$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')"
  rc=0
  printf '%s\n' "$canary" |
    gitleaks stdin "${common[@]}" --enable-rule redact-canary --exit-code "$leak_exit" >/dev/null 2>&1 || rc=$?
  if [[ $rc != "$leak_exit" ]]; then
    echo "redaction rules self-test failed" >&2
    exit 1
  fi
fi

# Print the messages and changed paths of the commits given as arguments.
commit_metadata() {
  local sha
  for sha in "$@"; do
    git log -1 --format=%B "$sha"
    git -c core.quotepath=false diff-tree -r -c --root --no-commit-id --name-only "$sha"
  done
}

case "$mode" in
  staged)
    exec gitleaks git --pre-commit --staged "${common[@]}"
    ;;
  range)
    shas="$("$here/range.sh")"
    [[ -z "$shas" ]] && exit 0
    status=0
    gitleaks git "${common[@]}" --log-opts="--no-walk ${shas//$'\n'/ }" || status=$?
    # gitleaks git skips merge commits; scan what each merge adds through its combined diff.
    # shellcheck disable=SC2086 # SHAs contain no whitespace
    for merge in $(git rev-list --no-walk --merges $shas); do
      git show --cc --format= "$merge" | gitleaks stdin "${common[@]}" || status=$?
    done
    exit "$status"
    ;;
  meta)
    shas="$("$here/range.sh")"
    {
      # shellcheck disable=SC2086 # SHAs contain no whitespace
      commit_metadata $shas
      if [[ -n "${PRE_COMMIT_REMOTE_NAME:-}" ]]; then
        git for-each-ref --format='%(refname)' refs/heads refs/tags
      fi
    } | gitleaks stdin "${common[@]}"
    ;;
  files)
    status=0
    for path in "$@"; do
      gitleaks dir "${common[@]}" "$path" || status=1
    done
    exit "$status"
    ;;
  history)
    gitleaks git "${common[@]}" --log-opts=--all --exit-code 0 \
      --report-format json --report-path "$tmp/content.json"
    git log --all --format=%B |
      gitleaks stdin "${common[@]}" --exit-code 0 --report-format json --report-path "$tmp/messages.json"
    git -c core.quotepath=false log --all --name-only --format= |
      gitleaks stdin "${common[@]}" --exit-code 0 --report-format json --report-path "$tmp/paths.json"
    if ! jq -e -s '[.[][] | select(.RuleID != "redact-canary")] | length == 0' \
      "$tmp"/content.json "$tmp"/messages.json "$tmp"/paths.json >/dev/null; then
      jq -s -r '.[][] | select(.RuleID != "redact-canary") | "\(.RuleID) \(.File) \(.Commit)"' \
        "$tmp"/content.json "$tmp"/messages.json "$tmp"/paths.json >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: ${0##*/} staged|range|meta|files <path>...|history" >&2
    exit 2
    ;;
esac
