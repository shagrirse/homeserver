# Secrets with SOPS and age

All secrets are committed encrypted with [SOPS](https://github.com/getsops/sops)
using [age](https://github.com/FiloSottile/age) keys. Plaintext never enters
git. [.sops.yaml](../../.sops.yaml) decides who can read what:

| Files | Readable by |
| --- | --- |
| `provision/*.sops.yaml` | Personal key |
| `kubernetes/**/*.sops.yaml` | Personal key and cluster key (Flux decrypts in-cluster) |

Why the cluster has its own key: [ADR 0004](../adr/0004-cluster-age-key.md).

## Personal key

- Lives at `~/.config/sops/age/keys.txt` (mode 600) and is never committed.
- Back it up in at least two places outside this repo, for example a password
  manager entry and an offline copy. It decrypts everything, including the
  cluster key, so losing it means re-creating every secret.
- Rotation: generate a new key, replace it in `.sops.yaml`, then run
  `sops updatekeys <file>` on every `*.sops.yaml`.

## Cluster key

- The private key is the `flux_age_key` entry in
  `provision/secrets.sops.yaml`. The `flux` Ansible role installs it as the
  `flux-system/sops-age` Secret.
- Its public key is the second recipient of the `kubernetes/` rule.
- Rotation, which pipes the new key straight into the secrets file without
  printing it:

  ```sh
  key=$(age-keygen 2>/dev/null)
  printf '%s\n' "$key" | age-keygen -y      # new public key
  printf '%s\n' "$key" | jq -Rs . \
    | sops set --value-stdin provision/secrets.sops.yaml '["flux_age_key"]'
  unset key
  ```

  Replace the old public key in `.sops.yaml`, run
  `sops updatekeys <file>` on every `kubernetes/**/*.sops.yaml`, open a PR,
  and after the merge run `just provision --tags flux`.

## Deploy key

Flux pulls this repo over SSH with a read-only deploy key named
`flux-homeserver`.

- The private key is the `flux_deploy_key` entry in
  `provision/secrets.sops.yaml`. The `flux` Ansible role installs it, with
  GitHub's host key, as the `flux-system/flux-system` Secret.
- The public key is registered on the repository, read-only.
- Creation and rotation are the same procedure. The private key exists on
  disk only between `ssh-keygen` and `shred`:

  ```sh
  d=$(mktemp -d) && chmod 700 "$d"
  ssh-keygen -q -t ed25519 -N '' -C flux-homeserver -f "$d/k"
  jq -Rs . < "$d/k" \
    | sops set --value-stdin provision/secrets.sops.yaml '["flux_deploy_key"]'
  gh repo deploy-key add "$d/k.pub" --title flux-homeserver
  shred -u "$d/k" && rm -rf "$d"
  ```

  Open a PR with the secrets file, and after the merge run
  `just provision --tags flux`. Once `flux get sources git` shows the
  repository `Ready`, delete the old key with `gh repo deploy-key list` and
  `gh repo deploy-key delete <id>`.
- Rotate it whenever the secrets file or the cluster may have leaked, and if
  GitHub rotates its host key, update `flux_github_known_hosts` in
  `provision/roles/flux/defaults/main.yml` from
  <https://api.github.com/meta>.

## Everyday use

```sh
sops kubernetes/apps/<app>/secret.sops.yaml   # edit in place, re-encrypts on save
```

Never run `sops -d` to stdout in a shared terminal or agent session.
