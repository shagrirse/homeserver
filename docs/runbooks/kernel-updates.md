# Apply kernel updates

Automatic security updates install new kernels but never reboot the node, so a
new kernel only runs after a manual reboot. Every app on the cluster is down
for the few minutes the reboot takes.

## How a kernel update boots

Ubuntu on the Pi keeps two sets of boot files on the boot partition:
`/boot/firmware/current` (the running kernel) and `/boot/firmware/new` (a
staged one). Installing a kernel writes it to `new/` with state `unknown`.

On the next reboot the node boots twice. The first boot sees the staged kernel
and reboots straight into it in trial mode. If that boot comes up,
`piboot-try-validate` promotes `new/` to `current/`. If it does not, the
firmware falls back to the previous kernel and marks the staged one `bad`.

## Check for a pending kernel

On the node:

```sh
cat /var/run/reboot-required.pkgs   # packages waiting for a reboot
cat /boot/firmware/new/state        # unknown = a kernel is staged
uname -r                            # the running kernel
```

No `/var/run/reboot-required` file means nothing is pending.

## Reboot

From the workstation:

```sh
just provision
```

The playbook upgrades packages, reboots the node when
`/var/run/reboot-required` exists, and
waits for both boots and the promotion to finish before it continues. It fails
if the staged kernel ends up `bad`.

A plain `sudo reboot` on the node works too; then follow the checks below
yourself.

## Verify

```sh
uname -r                                          # matches the new kernel
cat /boot/firmware/new/state 2>/dev/null          # not unknown, trying or bad
kubectl --kubeconfig ~/.kube/homeserver.yaml get nodes   # Ready
```

## If the new kernel fails to boot

The node is back on the previous kernel and keeps running. The journal lives
in RAM, so the failed boot leaves no logs; to see why it failed, attach a
monitor or a serial console and reboot again. The staged kernel stays marked
`bad` until a later kernel update replaces it.
