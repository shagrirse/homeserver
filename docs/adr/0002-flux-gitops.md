# 0002. Flux for GitOps delivery

- Status: Accepted
- Date: 2026-11-16

## Context

The cluster should converge on whatever is in git, with ordered tiers
(provision, infrastructure, apps), Helm releases, and encrypted secrets. Both
Flux and Argo CD are graduated CNCF projects and fit the repo layout.

## Decision

Use Flux with HelmRelease and Kustomize. Tiers are expressed with `dependsOn`
between Kustomizations. Secrets are SOPS + age, decrypted natively by Flux
in-cluster.

## Alternatives considered

Argo CD offers a better built-in UI and wider recruiter recognition, but:

- It uses more RAM at rest (server, repo-server, controller, Redis), which
  matters on an 8GB node.
- SOPS needs a plugin (KSOPS or helm-secrets) wired into the repo-server.
- It renders Helm charts with `helm template`, so there are no real Helm
  hooks or `helm list`.

Visibility with Flux comes from Grafana dashboards and `flux get`.

## Consequences

- No bundled web UI; optional third-party UIs can be added later.
- `flux bootstrap github` commits its own manifests, so Flux manages itself.
- Swapping to Argo CD later would change bootstrap and secrets wiring, not the
  repo layout.
