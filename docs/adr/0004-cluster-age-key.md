# 0004. A dedicated age key for the cluster, installed by provisioning

- Status: Accepted
- Date: 2026-11-18

## Context

Flux decrypts SOPS secrets in-cluster, so a private age key has to live in
the cluster as the `flux-system/sops-age` Secret. A rebuilt node needs the
same Secret before Flux can apply anything encrypted.

## Decision

The cluster has its own age key. Kubernetes secrets are encrypted to both the
personal key and the cluster key; node secrets under `provision/` only to the
personal key. The cluster private key is stored in
`provision/secrets.sops.yaml`, and the `flux` Ansible role installs it as the
`sops-age` Secret, passing it to kubectl over stdin.

## Alternatives considered

- Reusing the personal key: simpler, but the cluster could then decrypt the
  node secrets as well.
- Generating the cluster key at bootstrap and never storing it: every rebuild
  would need a new key and `sops updatekeys` over all secrets before anything
  decrypts.
- Installing the Secret from a workstation recipe: a second imperative path
  to the cluster, outside both Ansible and Flux.

## Consequences

- A rebuild is `just provision`, with no re-encryption.
- Provisioning reaches into cluster state for the Secrets Flux needs before
  it can sync, see [ADR 0005](0005-flux-operator.md).
- The personal key decrypts everything, so its backup also covers the cluster
  key. Rotating the cluster key means updating `.sops.yaml`, the secrets file
  and `sops updatekeys` on every Kubernetes secret.
