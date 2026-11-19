# 0007. Tailscale SSH for remote shell access

- Status: Accepted
- Date: 2026-11-19

## Context

The node needs a shell from devices away from home, such as a phone running an
SSH client, and the set of devices changes over time. The node has no open
ports; remote access goes through the tailnet. OpenSSH accepts only the key
placed by cloud-init when the boot media was flashed, so any other device
needs its own credential and a way to revoke it.

## Decision

Tailscale SSH runs on the node. The `tailscale` role passes `--ssh` when the
node joins and turns it on for a node that has already joined. Tailnet devices
log in by tailnet identity instead of SSH keys.

Access is set by one rule in the tailnet policy:

```json
"ssh": [
  {
    "action": "accept",
    "src": ["autogroup:member"],
    "dst": ["autogroup:self"],
    "users": ["autogroup:nonroot"]
  }
]
```

`accept` skips the periodic browser re-authentication of `check` mode, since
reaching the node already requires a device admitted to the tailnet. Root
logins are not allowed.

OpenSSH stays as configured by the `hardening` role and serves the LAN and
the fallback when Tailscale is unavailable.

## Alternatives considered

- Adding each device's public key to `authorized_keys` by hand: lost on a
  rebuild, and revoking a device means editing the node.
- Managing `authorized_keys` from a key list in the Ansible inventory: keeps
  keys reproducible, but every device still needs its own key lifecycle, which
  Tailscale identity already provides.

## Consequences

- Adding a device means adding it to the tailnet; removing it from the tailnet
  revokes its shell access.
- Logins over the tailnet are handled by Tailscale, not OpenSSH, so the sshd
  settings in the `hardening` role apply only to LAN logins.
- Ansible and `just kubeconfig` connect over the Tailscale name, so they also
  depend on the policy rule.
- With `accept`, any device in the tailnet owner's account gets a shell as
  `ubuntu`, which has sudo. Losing a device means removing it from the tailnet
  promptly.
- Tagging the node takes it out of `autogroup:self`, so the rule would need
  the tag as its destination.
- The policy rule lives in `tailscale/policy.hujson`
  ([ADR 0008](0008-tailscale-policy-as-code.md)).
- Reopen if shell access is needed for people outside the tailnet owner's
  account, or if Tailscale becomes unavailable for long periods.
