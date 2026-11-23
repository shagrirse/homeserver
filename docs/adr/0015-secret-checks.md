# 0015. Layered secret checks with a squash-only protected main

- Status: Accepted
- Date: 2026-11-23

## Context

The repository is public and Flux applies whatever merges to `main`. A pushed
commit is public at once, and GitHub keeps it fetchable through
`refs/pull/N/head` even after a squash merge and branch deletion, so a leak
caught at pull request time already means rotation. Local pre-commit hooks
are skippable (`--no-verify`, the web editor, an unhooked clone), and a
secret is not the only thing that must stay out: the real domain, LAN
subnet, node address and hostname are redacted from git as well.

GitHub custom secret-scanning patterns are not available on user-owned
repositories, so GitHub push protection cannot enforce the redaction values.

## Decision

- Five layers check for secrets and redaction leaks, earliest first: the
  agent edit hook, the commit hook, the pre-push hook, GitHub secret
  scanning with push protection, and the `checks` workflow on pull
  requests.
- One redaction ruleset holds the real values as gitleaks rules. It lives in
  the clone's git directory, so it cannot be committed and every worktree
  shares it, and CI receives the same content from an Actions secret. A
  canary rule matching a value built at runtime proves the rules are loaded:
  a layer that loads rules without detecting the canary fails, and where
  `GITLEAKS_REQUIRE_REDACTION=1` is set missing rules fail instead of
  falling back to the repo config.
- gitleaks is pinned once, as the `.pre-commit-config.yaml` rev. Every use
  runs through hooks from that repository, and ansible-lint runs from its
  upstream hook with a pinned `ansible-core`.
- The pre-push hooks scan every local commit the remote lacks: contents,
  commit messages, changed paths, branch and tag names, and the encryption
  of each `*.sops.yaml` in each commit. gitleaks skips merge commits, so
  the combined diff of each merge is scanned as well.
- The `checks` workflow first runs `scripts/secrets/test.sh`, then the
  range hooks over the pull request's commits, scans the title,
  description, branch name and the diff the squash lands, then runs every
  pre-commit hook over the tree. It is the single required status check.
- `main` accepts squash merges only. The squash message is the pull request
  title and description, which the workflow scans.
- A branch ruleset on `main` requires a pull request with no approvals (a
  sole author cannot approve their own), requires `checks` bound to the
  GitHub Actions app, requires linear history, blocks force pushes and
  deletion, and has no bypass actors, admins included. Its JSON is
  `.github/rulesets/main.json`.
- `just scan-history` scans every ref, including fetched pull request refs,
  and all commit messages and paths, with the redaction rules. If it finds
  a real value, history is rewritten and force-pushed before the ruleset
  blocks force pushes; the procedure is in the
  [secret leak runbook](../runbooks/secret-leak.md).

## Alternatives considered

- **Secret checks only in CI**: smallest, but the linters stay skippable
  locally and a leak is public before CI runs.
- **Secrets-only CI, no other hooks**: leaves yamllint and ansible-lint
  skippable, and the merge gate would not cover them.
- **Full manifest validation (kustomize build, kubeconform) in the same
  change**: the secret gate would wait on the hardest part, since several
  HelmReleases and substituted Kustomizations need rendering. It is a
  separate piece of work.

## Consequences

- Redaction values rely on gitleaks alone, because GitHub custom patterns
  are unavailable; GitHub push protection covers known provider secrets.
- `git push --no-verify` skips the local layer: only known provider secrets
  are then stopped before publication, and redaction values and plaintext
  SOPS files are caught by CI after they are public.
- A squash message edited in the merge dialog is not scanned by CI; the
  next `just scan-history` catches it.
- The pre-push hooks scan every unpushed local commit, not only the pushed
  branch, so a flagged commit on a local-only branch blocks pushes until it
  is fixed.
- The redaction rules sync to CI by hand (`gh secret set`). The canary
  proves CI's copy is loaded, not that it matches the local file. The file
  is part of the workstation backup ([0014](0014-backups.md)).
- Dependabot pull requests read the separate Dependabot secrets store, so
  the rules secret must exist there too or those pull requests fail closed.
- Redaction values cannot be rotated, so a leak of one is an exposure to
  assess, not a credential to replace.
