# 0003. Ubuntu Server 26.04 LTS as the host OS

- Status: Accepted
- Date: 2026-11-17

## Context

The node is a Raspberry Pi 5 (8GB, arm64) running single-node k3s, provisioned
with Ansible and first-boot cloud-init. The host OS decides which package
manager, kernel, first-boot mechanism and update model the provisioning code
targets, and how long the node runs before a forced OS migration. The node is
rebuilt from scratch rather than upgraded in place, so a longer support runway
and a recent kernel matter more than a conservative base.

## Decision

Run Ubuntu Server 26.04 LTS (arm64, Raspberry Pi preinstalled image). First
boot is configured through cloud-init `user-data` on the boot partition
([user-data.example.yaml](../../provision/cloud-init/user-data.example.yaml)),
and everything after that is Ansible under `provision/`.

## Alternatives considered

- Ubuntu Server 24.04 LTS: the original choice. Supported until 2029 and
  well documented for k3s on Pi, but it is the older base for a new build and
  carries an older Pi kernel.
- Raspberry Pi OS Lite (Debian 13): the lightest footprint and the best
  first-party Pi 5 hardware support. It has no cloud-init first boot, and its
  support lifetime follows Debian rather than an LTS commitment. It is the
  closest runner-up and needs only small changes to the Ansible roles.
- Debian arm64: minimal and stable, but Pi 5 support is the weakest of the
  Debian-family options.
- Talos Linux: immutable, API-driven and configured from git, which fits the
  repo's philosophy. It replaces k3s with full Kubernetes and most of the
  Ansible, so it is a different architecture, not an OS swap, and would need
  its own record.
- Flatcar, Fedora IoT, openSUSE MicroOS: immutable, but Pi 5 support is
  thinner than the options above.

## Consequences

- The provisioning roles target apt, cloud-init and the Ubuntu Pi kernel
  packages. Package names such as `linux-modules-extra-raspi` and the
  `/boot/firmware/cmdline.txt` path are validated by running
  `just provision-check` on the node.
- Ubuntu carries more background services than Raspberry Pi OS Lite (snapd,
  cloud-init, apt timers). The base role works around the first-boot ones.
- The OS is mutable, so drift is possible. Ansible enforces configuration on
  every run but does not prevent changes made by hand.
- Reopen this decision if memory pressure from the host becomes a constraint
  (Raspberry Pi OS Lite) or if the node should become fully declarative and
  immutable (Talos).
