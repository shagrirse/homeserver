# 0014. Backups: restic into Cloudflare R2 with tested restores

- Status: Accepted
- Date: 2026-11-21

## Context

Everything cluster-side is reconstructible: git is the source of truth and
provisioning rebuilds the node. The irreplaceable items are the personal
age key (without it every SOPS secret in git is unreadable, see
[0004](0004-cluster-age-key.md)), `provision/inventory.yml`, and future app
data on PVCs. Cloudflare R2 is the agreed backup target.

## Decision

- restic backs up into a private Cloudflare R2 bucket with client-side
  encryption. The passphrase lives only in the operator's password manager
  (and on paper), never in git or on the node.
- Two writers share the repo: a workstation restic job pushes the age key
  and `inventory.yml` daily, and a cluster CronJob mounts PVCs read-only to
  back up app data from the first stateful app onward.
- Retention is 14 daily, 8 weekly, 6 monthly snapshots. RPO is 24 hours;
  RTO is the existing rebuild path (`just provision` plus Flux) followed by
  a restic restore.
- A monthly test restore runs automatically: restore the latest snapshot to
  a scratch location, run `restic check`, decrypt a known test ciphertext
  with the restored age key, and parse `inventory.yml`. Failures raise a
  Grafana ticket.
- A yearly drill rebuilds the node from R2, git and Ansible alone,
  exercising the full RTO path.
- The cluster side lives in `kubernetes/infrastructure/configs/backups/`
  with R2 credentials as a SOPS secret; the restore procedure is a runbook
  in `docs/runbooks/`.

## Alternatives considered

- **Ad hoc copies of the key**: a missed manual step is exactly the
  coverage gap a plan exists to prevent.
- **Backing up cluster state**: redundant with git plus provisioning, and
  it would double the stored volume.
- **Velero or k8up**: full-featured but multi-component, aimed at clusters
  with many workloads; a single restic CronJob covers one node.

## Consequences

- The risk of losing the age key moves to custody of the restic
  passphrase.
- Backup jobs are monitored; silent failure is an alert.
- Restoring is the tested path, not a script written during the incident.
