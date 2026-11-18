# Provision the node

Takes a freshly flashed Raspberry Pi 5 to a hardened single-node k3s host. The
same procedure rebuilds a dead node and moves from microSD to an SSD.

This runbook ends at a `Ready` node with Flux syncing `main`. Restoring
volumes into the cluster is outside its scope.

## What the playbook does

| Role | Effect |
| --- | --- |
| `base` | Hostname, timezone, apt upgrade, automatic security updates (kernels need a manual reboot, see [kernel-updates.md](kernel-updates.md)) |
| `rpi_eeprom` | Boot order NVMe, then USB, then SD |
| `storage_tuning` | `noatime` root, zram swap, journal kept in RAM, TRIM on USB SSDs |
| `tailscale` | Installs Tailscale and joins the tailnet |
| `hardening` | Key-only SSH, ufw deny-by-default (SSH from the LAN, everything on `tailscale0`) |
| `k3s` | Checks memory cgroups, k3s without Traefik, memory reserved for the host, volumes under `/srv/k8s` |
| `flux` | The cluster age key and the deploy key as Secrets, the Flux Operator, and the `FluxInstance` from git on first install, see [maintain-flux.md](maintain-flux.md) |

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
the tailnet after about 180 days. The age keys, including the cluster key
in `flux_age_key`, and the deploy key in `flux_deploy_key` are described in
[secrets.md](secrets.md).

Before the first run, add the SSH rule from
[ADR 0007](../adr/0007-tailscale-ssh.md) to the tailnet policy. Once the node
runs Tailscale SSH, every login over its Tailscale name, Ansible's included,
is allowed or denied by that rule. With the default `check` rule Ansible
waits on a browser prompt; with no rule it is denied. The LAN address still
reaches OpenSSH with your key.

## Flash

1. Flash Ubuntu Server 26.04 LTS (arm64, Raspberry Pi preinstalled image) to
   the microSD card with Raspberry Pi Imager. Skip its OS customisation, since
   `user-data` below configures first boot.
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

Run it from an up-to-date `main`: on a new node the `FluxInstance` is created
from the checked-out `kubernetes/cluster/flux-system/flux-instance.yaml`, and
after that Flux syncs `main`. Then check that Flux is up:

```sh
export KUBECONFIG=~/.kube/homeserver.yaml
kubectl -n flux-system get fluxinstance flux   # Ready
flux get all -A                                # every source and Kustomization Ready
```

On a freshly flashed node the dry run reports the Tailscale install and
service, the zram restart and the k3s service as ignored errors, because check
mode only simulates the installs they depend on. The real run installs them.

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
6. Run the steps above and verify the node and Flux report `Ready`.
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

### Checking a USB SSD

A USB enclosure connects with a USB 3 rated USB-C to USB-A cable to a blue USB
3 port, with no hub, see [ADR 0006](../adr/0006-usb-nvme-boot-disk.md). After
the first boot from the SSD:

```sh
findmnt /                       # root is on /dev/sda2, not /dev/mmcblk0p2
lsusb                           # names the bridge chip (Realtek, ASMedia or JMicron)
lsusb -t                        # the enclosure shows Driver=uas and 5000M
lsblk -D /dev/sda               # DISC-GRAN and DISC-MAX non-zero, so TRIM works
sudo fstrim -v /                # reports bytes trimmed, not an error
vcgencmd get_throttled          # throttled=0x0, so power is sufficient
sudo dmesg | grep -iE 'uas_eh|reset SuperSpeed|offline|I/O error'   # no output
```

- `480M` in `lsusb -t` means a USB 2 cable or port.
- `Driver=usb-storage` instead of `uas` means the kernel disabled UAS for the
  bridge chip, which is slower and points to a JMicron bridge.
- Zero discard values mean TRIM is off for the enclosure. The
  `storage_tuning` role turns it on with a udev rule for the bridges listed in
  `storage_tuning_trim_usb_bridges`. For a new enclosure, test with
  `echo unmap | sudo tee /sys/block/sda/device/scsi_disk/*/provisioning_mode`
  and `sudo fstrim -v /`, then add its `lsusb` ID to that list.

Run the `dmesg` check again after a few days of normal load. Repeated resets
point to the bridge chip, power or cable.
