# Secrets with SOPS and age

All secrets are committed encrypted with [SOPS](https://github.com/getsops/sops)
using an [age](https://github.com/FiloSottile/age) key. Flux decrypts them
in-cluster. Plaintext never enters git.

## Key handling

- The age private key lives at `~/.config/sops/age/keys.txt` (mode 600) and is
  never committed. Only the public key is in [.sops.yaml](../../.sops.yaml).
- Back the private key up in at least two places outside this repo, for example
  a password manager entry and an offline copy. Losing it means every secret
  must be re-created and re-encrypted.
- Rotation: generate a new key, add it to `.sops.yaml`, run
  `sops updatekeys <file>` on each secret, then remove the old key.

## Everyday use

```sh
sops kubernetes/apps/<app>/secret.sops.yaml   # edit in place, re-encrypts on save
```

Never run `sops -d` to stdout in a shared terminal or agent session.
