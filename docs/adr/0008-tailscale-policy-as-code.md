# 0008. Tailnet policy managed from git

- Status: Accepted
- Date: 2026-11-20

## Context

Who can reach the node, and who can open a shell on it (ADR 0007), is set by
the tailnet policy file. Edited in the Tailscale admin console, it has no
review, no history next to the rest of the infrastructure, and no record in
the repo that is meant to describe the whole system. The repo is public, so
anything committed is visible to everyone.

## Decision

`tailscale/policy.hujson` is the tailnet policy. The
`.github/workflows/tailscale-policy.yaml` workflow runs Tailscale's
[gitops-acl-action](https://github.com/tailscale/gitops-acl-action): `test` on
pull requests, which validates the file against the Tailscale API without
changing it, and `apply` on pushes to `main`.

- The workflow authenticates with a Tailscale federated identity that trusts
  GitHub's OIDC tokens for this repository, scoped to `policy_file`. No
  Tailscale credential is stored in GitHub; the client ID and audience are
  Actions secrets only to keep identifiers out of logs.
- The tailnet is addressed as `-`, the credential's own tailnet, so its name
  is not committed.
- The policy uses autogroups, tags and wildcards only. User emails, device
  names and IPs are never written into it.
- The admin console policy editor is locked so the file is the only way to
  change the policy.

## Alternatives considered

- OpenTofu with the Tailscale provider's `tailscale_acl` resource: the same
  file, but it needs remote state and a runner, which only pay off alongside
  other managed resources.
- Applying from the cluster with Flux: no controller exists for the policy
  file, and the policy governs access to the cluster itself, so the cluster
  should not be its only path to recovery.

## Consequences

- Policy changes are pull requests with a Tailscale-side check before merge.
- The action keeps the ETag of the last applied policy in the Actions cache.
  If the live policy changed since then, `apply` fails rather than
  overwriting it. A cleared cache only removes that guard.
- Policy `tests` and `sshTests` need concrete users or tags as sources, so
  the file has none while access is defined by autogroups alone. They become
  possible once the node and other devices carry tags.
- Recovering from a policy that locks out access is done from the admin
  console after unlocking the editor, then the fix is committed.
- Reopen if other Tailscale resources need managing as code, at which point
  OpenTofu covers the policy and the rest together.
