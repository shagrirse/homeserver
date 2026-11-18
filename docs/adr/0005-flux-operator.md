# 0005. Flux installed by the Flux Operator

- Status: Accepted
- Date: 2026-11-18

## Context

`flux bootstrap github` commits about 10,000 lines of generated manifests
under fixed file names, which have to be regenerated, re-pinned by digest and
re-bootstrapped from a workstation on every upgrade. A rebuilt node also
needed a second step after provisioning, with a GitHub token and a `flux` CLI
matching the repo.

## Decision

Install Flux with the [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator):

- The `flux` Ansible role installs the operator as a k3s `HelmChart`, with the
  chart version and image digest pinned in the role defaults, plus the
  `sops-age` and deploy key Secrets.
- `kubernetes/cluster/flux-system/flux-instance.yaml` is a `FluxInstance`
  with an exact Flux version, the components, the sync source and the SOPS
  patch. Ansible creates it once on a new node; it syncs its own path, so
  from then on git is its only owner.
- Flux pulls over SSH with a read-only deploy key kept in
  `provision/secrets.sops.yaml`.

## Alternatives considered

- `flux bootstrap github`: the generated files and the separate bootstrap
  step above. Bootstrap does register the deploy key itself.
- Flux managing the operator through a `HelmRelease`: operator upgrades
  would go through a PR, but the first install would still need a manual
  `helm install`, and a broken operator release could only be fixed by hand.
- Placing the `FluxInstance` in the k3s manifests directory: k3s re-applies
  that directory on restart, which would roll back changes merged since the
  last provisioning run.

## Consequences

- A rebuild is `just provision`; there is no separate bootstrap step.
- A Flux upgrade is a one-line PR. The operator pins controller images by
  the digests it ships for that exact version, so the Flux version cannot be
  newer than what the running operator knows.
- Operator upgrades are a provisioning run, not a Flux reconcile.
- The operator is one more pod (64Mi requested, 256Mi limit) and one more
  project to track. It is licensed AGPL-3.0.
- The deploy key is created and rotated by hand, see
  [secrets.md](../runbooks/secrets.md).
