# AGENTS.md
Single source of truth for a Raspberry Pi 5 homeserver running k3s, delivered by Flux GitOps. Every change goes through git. Canonical; CLAUDE.md only imports it.
## Invariants
- No plaintext secrets, real domain, LAN IPs/subnets or host inventory in git: secrets are `*.sops.yaml` (SOPS + age), and only `provision/inventory.example.yml` is committed (`inventory.yml` is gitignored).
- Never `sops -d` to stdout or read the age key (`~/.config/sops/age/keys.txt`); edit with `sops <file>`.
- Agents are read-only against the node and cluster: changes arrive only via a merged PR (Flux applies it within minutes) or provisioning the human runs.
- Allowed: `kubectl get/describe/logs/wait`, `flux get`, `just provision-check`, requests to served endpoints. Never: other `kubectl` writes (incl. `rollout restart`), `flux reconcile/suspend/resume`, `just provision`, changes over SSH.
- Never read Secret values from the cluster; `kubectl describe secret` shows key names.
- Work on a branch; never `git push` unless the human says so; the human merges PRs.
- Images pinned by digest and arm64-capable; the cluster has 8GB, so every workload sets requests and limits.
- Verify end to end after Flux applies a change before calling it done.
- Conventional Commits with the app as scope (`feat(grafana): ...`).
## Repo map
- `provision/`: Ansible for the Pi (OS, k3s, Flux install).
- `kubernetes/cluster/`: Flux entry point; `flux-system/flux-instance.yaml` defines Flux, `infrastructure.yaml` orders the platform layers.
- `kubernetes/infrastructure/`: `controllers/` (Traefik, cert-manager), then `configs/` (Gateway, issuers, wildcard cert, cloudflared).
- `tailscale/`: tailnet policy, applied by `.github/workflows/`.
- `templates/app/`: skeleton for `kubernetes/apps/<app>/`.
- `docs/adr/`: decision records; add one for any architectural choice.
- `docs/runbooks/`: operational procedures.
- `.claude/`: agent permissions and hooks.
## App contract
- Each `kubernetes/apps/<app>/` has `kustomization.yaml`, a `helmrelease.yaml` or plain manifests, `secret.sops.yaml` if needed, and `README.md`; start from `templates/app/`.
- It owns its namespace, sets requests and limits, defines probes, and is exposed only by an HTTPRoute on the shared Gateway ([Traefik](kubernetes/infrastructure/controllers/traefik/README.md)).
## Commands
- `just lint`: all pre-commit checks. `just scan-history`: gitleaks over full history.
- `just provision-deps` / `provision-check` / `provision` / `kubeconfig`: node provisioning ([runbook](docs/runbooks/provision-node.md)).
## Docs
- Runbooks: [secrets](docs/runbooks/secrets.md), [Flux](docs/runbooks/maintain-flux.md), [kernel updates](docs/runbooks/kernel-updates.md), [tailnet policy](docs/runbooks/tailscale-policy.md). Decisions: [ADRs](docs/adr/README.md).
