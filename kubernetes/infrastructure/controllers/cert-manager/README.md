# cert-manager

Issues TLS certificates from Let's Encrypt with DNS-01 on Cloudflare.
Decision: [ADR 0009](../../../../docs/adr/0009-ingress-and-tls.md).

- ClusterIssuers `letsencrypt-staging` and `letsencrypt-production` live in
  [configs/cert-manager](../../configs/cert-manager/). The one wildcard
  Certificate lives in [configs/traefik](../../configs/traefik/).
- The wildcard Certificate is issued by `letsencrypt-staging`, which browsers
  do not trust. To serve a trusted certificate, set its `issuerRef.name` to
  `letsencrypt-production`; cert-manager reissues it on the next reconcile.
- `secret.sops.yaml` holds a Cloudflare API token with Zone:DNS:Edit on the
  one zone. Edit it with `sops`.
- Propagation checks use 1.1.1.1 and 1.0.0.1 rather than the node's resolver.
- The chart installs and upgrades its own CRDs, and keeps them on uninstall.

## Checking issuance

```sh
kubectl get certificate,certificaterequest,order,challenge -A
kubectl describe certificate -n traefik wildcard
```

## Upgrading

Bump the tag in `ocirepository.yaml` and every image digest in
`helmrelease.yaml`.
