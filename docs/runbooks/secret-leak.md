# Secret leak

What to do when a secret or a redacted value (domain, LAN subnet, node
address, hostname) reaches a pushed commit, a pull request or its text. A
pushed commit is public at once and stays fetchable through
`refs/pull/N/head` after a squash merge and branch deletion, so treat every
pushed leak as exposed. Design: [ADR 0015](../adr/0015-secret-checks.md).
Key and rules file details: [secrets](secrets.md).

## 1. Rotate

Rotate first, before cleaning anything up.

| Leaked | Rotation |
| --- | --- |
| Cloudflare API token or tunnel credentials | Revoke in the Cloudflare dashboard, create a new one, update its `*.sops.yaml` secret |
| Flux deploy key | [Deploy key](secrets.md#deploy-key) procedure |
| Tailscale auth key, OAuth client or API credentials | Revoke in the Tailscale admin console, create new ones, update the repo secrets and any `*.sops.yaml` that holds them |
| Cluster age key | [Cluster key](secrets.md#cluster-key) procedure; `sops updatekeys` on every `kubernetes/**/*.sops.yaml` re-encrypts to the new recipient set |
| Personal age key | [Personal key](secrets.md#personal-key) procedure; `sops updatekeys` on every `*.sops.yaml`, then rotate every secret the old key could read, since old ciphertext stays in history |
| Any other credential | Revoke at the provider and issue a new one |

A redaction value cannot be rotated. Assess the exposure instead: where it
appeared (file contents, commit messages, paths, branch names, pull request
titles, descriptions and comments, issue text), for how long, and whether
the repository was already public. Then continue with the cleanup.

## 2. Clean up

1. Delete the branch carrying the leak.
2. Ask GitHub Support to purge cached views and `refs/pull/N/head` for the
   affected commits. Forks and existing clones keep their copies.
3. Dismiss the secret-scanning alert, if one was raised, once the credential
   is revoked.
4. Rewrite history if the leaked content reached `main` or a kept ref (next
   section).

## 3. Rewrite history

Needed when `just scan-history` finds a real value. The branch ruleset on
`main` blocks force pushes with no bypass, so the force-push happens before
the ruleset is applied, or after it is removed.

1. Write a replacement expressions file in the git directory next to the
   redaction rules, never in the work tree. Replacements are placeholders
   following the repo's redaction convention.
2. Run `git filter-repo --replace-text <expressions>` for file contents and
   `--replace-message <expressions>` for commit messages, over every branch
   and tag.
3. Force-push `main` and every other rewritten branch and tag. Rebase open
   pull requests onto the new `main` or close them.
4. Check read-only that the Flux `GitRepository` follows the new tip and the
   Kustomizations reach Ready on the rewritten revision (`flux get
   kustomizations`).
5. Ask GitHub Support to purge the old objects, which stay reachable through
   `refs/pull/*/head`. Re-clone local worktrees, restoring the redaction
   rules file from backup first.
6. Re-run `just scan-history`. It must be clean apart from canary hits.

The old values stay exposed regardless of the rewrite.

## Scan history

`just scan-history` fetches the pull request refs
(`+refs/pull/*/head:refs/remotes/origin/pr/*`) and scans every ref, every
commit message and every changed path with the redaction rules. Findings of
the canary rule are ignored, since canary test pull requests stay in
`refs/pull/*`.

Text that exists only on GitHub is not in git: titles, bodies, comments and
branch names of pull requests, and titles, bodies and comments of issues.
Scan it once through the file hook:

```sh
f=$(mktemp)
gh pr list --state all --limit 1000 --json title,body,headRefName,comments | jq -r '.. | strings' >> "$f"
gh issue list --state all --limit 1000 --json title,body,comments | jq -r '.. | strings' >> "$f"
pre-commit run --hook-stage manual gitleaks-file --files "$f"
rm "$f"
```

The squash message is the pull request title and description, which
`checks` scans. A message edited in the merge dialog is not scanned until
the next history scan.

## GitHub settings

Enable secret scanning, push protection and non-provider patterns:

```sh
gh api -X PATCH repos/{owner}/{repo} \
  -F 'security_and_analysis[secret_scanning][status]=enabled' \
  -F 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
  -F 'security_and_analysis[secret_scanning_non_provider_patterns][status]=enabled'
```

Merge settings: squash only, with the pull request title and description as
the commit message.

```sh
gh api -X PATCH repos/{owner}/{repo} \
  -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

Branch ruleset ([main.json](../../.github/rulesets/main.json)): apply it once
`checks` has passed on a pull request, then update by id after edits.

```sh
gh api -X POST repos/{owner}/{repo}/rulesets --input .github/rulesets/main.json
gh api repos/{owner}/{repo}/rulesets --jq '.[] | [.id, .name, .enforcement]'
gh api -X PUT repos/{owner}/{repo}/rulesets/<id> --input .github/rulesets/main.json
```

Verify read-only:

```sh
gh api repos/{owner}/{repo} --jq '.security_and_analysis, .allow_merge_commit, .allow_rebase_merge, .allow_squash_merge, .squash_merge_commit_title'
gh api repos/{owner}/{repo}/rules/branches/main
```

## Redaction rules in CI

After every edit of the redaction rules file, sync it to the Actions secret:

```sh
gh secret set GITLEAKS_CONFIG_TOML < "$(git rev-parse --git-common-dir)/gitleaks-redact.toml"
```

Dependabot pull requests read the separate Dependabot secrets store. When
Dependabot is enabled, set the same secret there with `gh secret set
GITLEAKS_CONFIG_TOML --app dependabot`, or its pull requests fail the
`checks` self-test.
