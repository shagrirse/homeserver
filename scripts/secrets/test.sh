#!/usr/bin/env bash
# Regression test for the secret checks (gitleaks.sh, range.sh, check-sops-commits.sh).
# Builds throwaway repos and bare remotes, writes canary-only redaction rules into each
# repo's git dir, and asserts that scans fail on a runtime canary and pass on clean
# input, both when the scripts are called as pre-commit calls them and through a real
# `git push` with a pre-push hook installed. Needs gitleaks and pre-commit on PATH.
set -uo pipefail

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$scripts/../.." && pwd)"

# Keep the host git config, hooks and pre-commit state out of the test.
for v in $(compgen -e | grep -E '^(PRE_COMMIT_(FROM|TO|REMOTE|LOCAL|ORIGIN|SOURCE|CHECKOUT|COMMIT|MERGE)|GIT_(DIR|INDEX_FILE|WORK_TREE)|GITLEAKS_)'); do
  unset "$v"
done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
canaries=()

canary() {
  local c
  c="hs-canary-$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')"
  canaries+=("$c")
  printf '%s' "$c"
}

pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  failures=$((failures + 1))
}

# check <name> pass|fail <command>...  Runs in the current directory and also fails
# when the output contains any canary generated so far.
check() {
  local name=$1 expect=$2 out rc=0 c
  shift 2
  out="$("$@" 2>&1)" || rc=$?
  if [[ $expect == pass && $rc == 0 ]] || [[ $expect == fail && $rc != 0 ]]; then
    pass "$name"
  else
    fail "$name (expected $expect, exit $rc)"
    printf '%s\n' "$out" | sed 's/^/     | /' | head -20
  fi
  for c in "${canaries[@]}"; do
    if grep -qF -- "$c" <<<"$out"; then
      fail "$name: output contains the canary value"
    fi
  done
}

# new_repo <name>: repo with a clean base commit pushed to the bare remote "origin",
# redaction rules in its git dir and a pre-push hook that runs the secret scripts.
new_repo() {
  R="$tmp/$1"
  REMOTE="$tmp/$1-origin.git"
  git init -q -b main "$R"
  git init -q --bare -b main "$REMOTE"
  cd "$R" || exit 1
  cp "$root/.gitleaks.toml" .gitleaks.toml
  cat >.git/gitleaks-redact.toml <<'TOML'
[extend]
path = ".gitleaks.toml"

[[rules]]
id = "redact-canary"
description = "redaction canary"
regex = '''hs-canary-[0-9a-f]{10}'''
TOML
  cat >.git/pre-commit-test.yaml <<YAML
repos:
  - repo: local
    hooks:
      - id: range
        name: range
        entry: $scripts/gitleaks.sh range
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-push]
      - id: meta
        name: meta
        entry: $scripts/gitleaks.sh meta
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-push]
      - id: sops-commits
        name: sops-commits
        entry: $scripts/check-sops-commits.sh
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-push]
YAML
  printf 'base\n' >README
  git add .
  git commit -q -m "chore: base"
  git remote add origin "$REMOTE"
  git push -q origin main
  pre-commit install -c .git/pre-commit-test.yaml -t pre-push >/dev/null
}

commit_file() { # <path> <content> <message>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
  git add -- "$1"
  git commit -q -m "$3"
}

range_of() { # <from>: scan from..HEAD like a pre-commit --from-ref run
  PRE_COMMIT_FROM_REF=$1 PRE_COMMIT_TO_REF=HEAD "${@:2}"
}

push_meta() { PRE_COMMIT_REMOTE_NAME=origin "$scripts/gitleaks.sh" meta; }

remote_has() { git --git-dir="$REMOTE" rev-parse --verify -q "refs/heads/$1" >/dev/null; }

# --- range: contents -----------------------------------------------------------------

new_repo range-clean
base=$(git rev-parse HEAD)
commit_file notes.txt "nothing to see" "docs: add notes"
check "range passes a clean range" pass range_of "$base" "$scripts/gitleaks.sh" range

new_repo range-canary
base=$(git rev-parse HEAD)
c=$(canary)
commit_file notes.txt "token $c" "docs: add notes"
check "range catches a canary in file content" fail range_of "$base" "$scripts/gitleaks.sh" range

# --- meta: messages, paths, ref names --------------------------------------------------

new_repo meta-message
base=$(git rev-parse HEAD)
c=$(canary)
commit_file notes.txt "clean" "docs: mention $c"
check "meta catches a canary in a commit message" fail range_of "$base" "$scripts/gitleaks.sh" meta

new_repo meta-path
base=$(git rev-parse HEAD)
c=$(canary)
commit_file "dir/$c.txt" "clean" "docs: add file"
check "meta catches a canary in a file path" fail range_of "$base" "$scripts/gitleaks.sh" meta

new_repo meta-branch
c=$(canary)
git branch "feat-$c"
check "meta catches a canary in a branch name" fail push_meta

new_repo meta-clean
base=$(git rev-parse HEAD)
commit_file notes.txt "clean" "docs: add notes"
check "meta passes a clean range" pass range_of "$base" "$scripts/gitleaks.sh" meta
check "meta passes clean refs in push mode" pass push_meta

# --- real pushes through the pre-push hook -----------------------------------------------

new_repo push-two-branches
git checkout -q -b one
commit_file one.txt "clean" "feat: one"
git checkout -q main
git checkout -q -b two
c=$(canary)
commit_file two.txt "token $c" "feat: two"
check "push of two new branches is rejected when only the second has a canary" fail git push origin one two
if remote_has one || remote_has two; then fail "rejected push left refs on the remote"; else pass "rejected push left the remote untouched"; fi
git checkout -q main
git branch -q -D two
check "push of two clean new branches is accepted" pass git push origin one

new_repo push-empty-remote
c=$(canary)
git checkout -q --orphan root
git rm -q README
commit_file root.txt "token $c" "chore: root"
git init -q --bare "$tmp/empty-canary.git"
git remote add empty "$tmp/empty-canary.git"
check "push of a canary root commit to an empty remote is rejected" fail git push empty root

new_repo push-empty-remote-clean
git checkout -q --orphan root
git rm -q README
commit_file root.txt "clean" "chore: root"
git init -q --bare "$tmp/empty-clean.git"
git remote add empty "$tmp/empty-clean.git"
check "push of a clean root commit to an empty remote is accepted" pass git push empty root

new_repo push-detached
git checkout -q --detach
c=$(canary)
commit_file notes.txt "token $c" "docs: add notes"
check "push from a detached HEAD with a canary is rejected" fail git push origin HEAD:refs/heads/detached
if remote_has detached; then fail "rejected detached push reached the remote"; else pass "rejected detached push left the remote untouched"; fi

new_repo push-detached-clean
git checkout -q --detach
commit_file notes.txt "clean" "docs: add notes"
check "push from a detached HEAD, clean, is accepted" pass git push origin HEAD:refs/heads/detached

# --- merge commits -------------------------------------------------------------------------

merge_conflict() { # <resolution text>
  base=$(git rev-parse HEAD)
  git checkout -q -b side
  commit_file shared.txt "side" "feat: side"
  git checkout -q main
  commit_file shared.txt "main" "feat: main"
  git merge -q side >/dev/null 2>&1 || true
  printf '%s\n' "$1" >shared.txt
  git add shared.txt
  git commit -q --no-edit
}

new_repo merge-resolution
c=$(canary)
merge_conflict "resolved with $c"
check "range catches a canary introduced by a conflict resolution" fail range_of "$base" "$scripts/gitleaks.sh" range

new_repo merge-resolution-clean
merge_conflict "resolved cleanly"
check "range passes a clean conflict resolution" pass range_of "$base" "$scripts/gitleaks.sh" range

new_repo merge-added-file
base=$(git rev-parse HEAD)
git checkout -q -b side
commit_file side.txt "side" "feat: side"
git checkout -q main
commit_file main.txt "main" "feat: main"
git merge -q --no-ff --no-commit side >/dev/null 2>&1
c=$(canary)
printf 'token %s\n' "$c" >extra.txt
git add extra.txt
git commit -q -m "merge: side"
check "range catches a canary in a file added by a merge commit" fail range_of "$base" "$scripts/gitleaks.sh" range

new_repo merge-added-path
base=$(git rev-parse HEAD)
git checkout -q -b side
commit_file side.txt "side" "feat: side"
git checkout -q main
commit_file main.txt "main" "feat: main"
git merge -q --no-ff --no-commit side >/dev/null 2>&1
c=$(canary)
mkdir dir
printf 'clean\n' >"dir/$c.txt"
git add dir
git commit -q -m "merge: side"
check "meta catches a canary in a path added by a merge commit" fail range_of "$base" "$scripts/gitleaks.sh" meta

new_repo merge-push
merge_conflict "resolved with $(canary)"
check "push of a merge that adds a canary is rejected" fail git push origin main

# --- sops-commits ---------------------------------------------------------------------------

enc='data: ENC[AES256_GCM,data:abc,tag:def]'
plain='password: not-encrypted'

new_repo sops
base=$(git rev-parse HEAD)
commit_file app/secret.sops.yaml "$plain" "feat(app): add secret"
check "sops-commits fails on a plaintext secret.sops.yaml" fail range_of "$base" "$scripts/check-sops-commits.sh"

base=$(git rev-parse HEAD)
commit_file app/secret.sops.yaml "$enc" "fix(app): encrypt secret"
check "sops-commits passes once the file is encrypted" pass range_of "$base" "$scripts/check-sops-commits.sh"

base=$(git rev-parse HEAD)
git rm -q app/secret.sops.yaml
git commit -q -m "chore(app): remove secret"
check "sops-commits ignores a deletion" pass range_of "$base" "$scripts/check-sops-commits.sh"

commit_file app/secret.sops.yaml "$enc" "feat(app): restore secret"
base=$(git rev-parse HEAD)
git mv app/secret.sops.yaml app/renamed.sops.yaml
git commit -q -m "refactor(app): rename secret"
check "sops-commits passes a renamed encrypted file" pass range_of "$base" "$scripts/check-sops-commits.sh"

base=$(git rev-parse HEAD)
git rm -q app/renamed.sops.yaml
commit_file app/other.sops.yaml "$plain" "feat(app): plaintext again"
base=$(git rev-parse HEAD)
git mv app/other.sops.yaml app/moved.sops.yaml
git commit -q -m "refactor(app): rename plaintext"
check "sops-commits fails a renamed plaintext file" fail range_of "$base" "$scripts/check-sops-commits.sh"

new_repo sops-space
base=$(git rev-parse HEAD)
commit_file "my app/my secret.sops.yaml" "$plain" "feat(app): spaced path"
check "sops-commits fails a plaintext file with a space in its path" fail range_of "$base" "$scripts/check-sops-commits.sh"

new_repo sops-space-encrypted
base=$(git rev-parse HEAD)
commit_file "my app/my secret.sops.yaml" "$enc" "feat(app): spaced path"
check "sops-commits passes an encrypted file with a space in its path" pass range_of "$base" "$scripts/check-sops-commits.sh"

new_repo sops-rules
base=$(git rev-parse HEAD)
commit_file .sops.yaml "creation_rules: []" "chore: sops rules"
check "sops-commits skips the root .sops.yaml" pass range_of "$base" "$scripts/check-sops-commits.sh"

new_repo sops-nested
base=$(git rev-parse HEAD)
commit_file dir/.sops.yaml "$plain" "chore: nested rules"
check "sops-commits catches a plaintext dir/.sops.yaml" fail range_of "$base" "$scripts/check-sops-commits.sh"

new_repo sops-push
commit_file app/secret.sops.yaml "$plain" "feat(app): add secret"
check "push of a plaintext sops file is rejected" fail git push origin main

# --- summary --------------------------------------------------------------------------------

if ((failures > 0)); then
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
printf 'all checks passed\n'
