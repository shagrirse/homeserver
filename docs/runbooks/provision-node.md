# Provision the node

Takes a freshly flashed Raspberry Pi 5 to a hardened single-node k3s host. The
same procedure rebuilds a dead node and moves from microSD to an SSD.

This runbook ends at a `Ready` node. Bootstrapping Flux, recreating the age key
secret and restoring volumes into the cluster are outside its scope.

## What the playbook does

| Role | Effect |
| --- | --- |
| `base` | Hostname, timezone, apt upgrade, automatic security updates |
| `rpi_eeprom` | Boot order NVMe, then USB, then SD |
| `storage_tuning` | `noatime` root, zram swap, journal kept in RAM |
| `tailscale` | Installs Tailscale and joins the tailnet |
| `hardening` | Key-only SSH, ufw deny-by-default (SSH from the LAN, everything on `tailscale0`) |
| `k3s` | Checks memory cgroups, k3s without Traefik, memory reserved for the host, volumes under `/srv/k8s` |

No ports are opened to the internet. Public apps go out through a Cloudflare
Tunnel and private apps over Tailscale.

ufw only filters traffic addressed to the host itself. Kubernetes NodePort,
hostPort and ServiceLB ports are forwarded by k3s's own iptables rules before
ufw sees them, so anything exposed that way is reachable from the LAN
regardless of ufw. The home router's NAT is what keeps it off the internet.

## One-time workstation setup

Prerequisites: [uv](https://docs.astral.sh/uv/), `just`, `pre-commit` and
`sops` (the `community.sops` collection calls the `sops` binary).

```sh
uv tool install ansible-core==2.22.0
uv tool install ansible-lint      # the pre-commit hook runs the local install
just provision-deps               # installs the pinned Ansible collections
cp provision/inventory.example.yml provision/inventory.yml   # then edit
```

The real inventory is gitignored. Create the encrypted secrets file from the
shape in `provision/secrets.example.yaml`:

```sh
sops provision/secrets.sops.yaml
```

The Tailscale auth key comes from the Tailscale admin console (a one-off,
non-ephemeral key). It is used once, when the node joins; every fresh flash
needs a new key, see [Rebuild the node](#rebuild-the-node). After the node
joins, disable key expiry for it in the admin console, otherwise it drops off
the tailnet after about 180 days. The age key is described in
[secrets.md](secrets.md).

## Flash

1. Flash Ubuntu Server 24.04 LTS (arm64) to the microSD card.
2. Put `provision/cloud-init/user-data.example.yaml`, with your SSH public key
   and the inventory host name as `hostname`, on the boot partition as
   `user-data`.
3. Boot the Pi and confirm `ssh ubuntu@<address>` works with your key.

## Run

```sh
just provision-check   # dry run
just provision         # apply; reboots the node when needed (twice for a kernel update)
just kubeconfig        # writes ~/.kube/homeserver.yaml (0600), pointed at Tailscale
kubectl --kubeconfig ~/.kube/homeserver.yaml get nodes
```

The node should report `Ready`. Re-running `just provision` changes nothing
when the node already matches.

On a freshly flashed node the dry run reports the Tailscale install and
service and the zram restart as ignored errors, because check
mode only simulates the package installs they depend on. The real run installs
them.

## Rebuild the node

Any fresh flash (a dead disk, a reinstall, or moving to an SSD) is a new
machine to Tailscale and to SSH:

1. Make sure a recent backup of `/srv/k8s` exists. If the old node still
   runs, take one now; if its disk is dead, the last backup is what you have.
2. Remove the old machine in the Tailscale admin console, so the new one can
   register under the same name and `k3s_api_host` keeps resolving.
3. Create a new auth key and put it in the secrets file with
   `sops provision/secrets.sops.yaml`.
4. Flash the boot disk and boot as above.
5. Forget the old SSH host key, otherwise Ansible refuses to connect:
   `ssh-keygen -R <address>`.
6. Run the steps above and verify the node reports `Ready`.
7. Disable key expiry for the new machine in the Tailscale admin console. It is
   a new identity, so the setting from the old machine does not carry over.

## Moving to an SSD

Follow [Rebuild the node](#rebuild-the-node), with these differences:

- Flash the same image to the SSD with the same `user-data`.
- Power off, **remove the microSD card**, attach the SSD and boot. Both disks
  carry a root partition labelled `writable`, so with both present the root
  filesystem may be mounted from the wrong one.
- Keep the microSD as a cold rollback. Its Tailscale identity was removed in
  step 2, so rolling back is a rebuild too. First take a backup of
  `/srv/k8s` from the SSD while it still boots, otherwise everything written
  since the migration is lost. Then power off, remove the SSD, reinsert the
  card, and repeat steps 2, 3 and 5 to 7 with the SD card booted.

The boot order set by `rpi_eeprom` prefers NVMe and USB over the SD card.
Hardware notes, both in `/boot/firmware/config.txt`:

- A PCIe NVMe HAT may need `dtparam=pciex1`.
- Booting from a USB SSD on a power supply other than the official 27W one may
  need `usb_max_current_enable=1`.
