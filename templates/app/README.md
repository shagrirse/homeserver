# APP_NAME

What this app is and why it runs here.

- Namespace: `APP_NAME`
- Exposure: private (Tailscale) or public (Cloudflare Tunnel), via a shared
  Traefik route
- Secrets: list the keys in `secret.sops.yaml`, never the values
- Data: PVC path under `/srv/k8s`, and how it is backed up
- Upgrade notes: anything non-obvious when bumping the chart or image
