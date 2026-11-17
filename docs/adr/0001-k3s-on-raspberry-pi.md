# 0001. k3s on a Raspberry Pi 5

- Status: Accepted
- Date: 2026-11-16

## Context

The homeserver runs on a single Raspberry Pi 5 (8GB, arm64) with Ubuntu Server
(see [0003](0003-ubuntu-26-04-host-os.md)), booting from microSD or an SSD. The repo should showcase real
deployment practice, so workloads are declared and reproducible rather than
hand-run containers. Memory is the main constraint.

## Decision

Run single-node k3s. Disable its bundled Traefik so ingress is managed through
Flux like everything else. Persistent volumes use the local-path provisioner
rooted at `/srv/k8s`, so all app data lives under one path. Provisioning is
Ansible under `provision/`.

The microSD-to-SSD move is the same procedure as disaster recovery: back up to
object storage, flash the new disk, provision, let Flux reconcile, restore
volumes. No device paths are hard-coded; the EEPROM boot order is
NVMe, USB, SD.

## Alternatives considered

- Docker Compose: lighter, but no declarative reconciliation, drift detection
  or Helm ecosystem.
- Full Kubernetes (kubeadm): far heavier than 8GB shared with workloads allows.
- Talos or k0s: viable, but k3s has the widest documentation for arm64
  homelabs and runs on a stock Ubuntu host.

## Consequences

- Single node means no high availability; recovery is rebuild-and-restore.
- Everything except app data, the age key, the real inventory and the
  kubeconfig lives in git.
- Disk wear, which matters most on microSD, is reduced with noatime, zram and
  in-RAM journald.
