# AGENTS.md

Single source of truth for a homeserver: a Raspberry Pi 5 running k3s, delivered
with Flux GitOps. Every change goes through git. This file is canonical;
CLAUDE.md only imports it.

## Invariants

- No plaintext secrets, real domain, LAN IPs/subnets or host inventory in git.
  Secrets are `*.sops.yaml` (SOPS + age). The real inventory is
  `provision/inventory.yml` (gitignored); commit only `inventory.example.yml`.
- Never run `sops -d` to stdout. Never read or print the age key
  (`~/.config/sops/age/keys.txt`). Use `sops <file>` to edit in place.
- Never `kubectl apply/delete/edit/patch`. Change manifests in git, open a PR,
  and let Flux reconcile. Read-only `kubectl get/describe/logs` and `flux get`
  are fine. Never read Secret values from the cluster; use
  `kubectl describe secret` to see key names.
- Do not `git push` unless the human explicitly says so. Work on a branch; the
  human merges PRs.
- Images are pinned by digest and must support arm64. Memory is 8GB for the
  whole cluster, so every workload sets requests and limits.
- Verify end to end after a reconcile before calling a change done.
- Conventional Commits, with the app name as scope (`feat(grafana): ...`).

## Repo map

| Path | Purpose |
| --- | --- |
| `provision/` | Tier 0: Ansible for the Pi (OS, k3s) |
| `templates/app/` | Skeleton for an app under `kubernetes/apps/<app>/` |
| `docs/adr/` | Decision records; add one for any architectural choice |
| `docs/runbooks/` | Operational procedures (secrets, provisioning) |
| `.claude/` | Agent permissions and hooks |

## App contract

Each app under `kubernetes/apps/<app>/` has `kustomization.yaml`, a
`helmrelease.yaml` or plain manifests, `secret.sops.yaml` if it needs secrets,
and a `README.md`. It owns its namespace, sets requests and limits, defines
probes, and is exposed only through a shared Traefik route. Start from
`templates/app/`.

## Commands

- `just lint` - run all pre-commit checks
- `just scan-history` - gitleaks over full history
- `just provision-deps` / `provision-check` / `provision` / `kubeconfig` - node
  provisioning, see [docs/runbooks/provision-node.md](docs/runbooks/provision-node.md)

## Docs

Secrets handling: [docs/runbooks/secrets.md](docs/runbooks/secrets.md).
Decisions: [docs/adr/](docs/adr/README.md).
