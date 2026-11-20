# cloudflared

The public entry point. cloudflared dials out to Cloudflare over a named
tunnel and forwards requests for listed hostnames to Traefik, so the router
has no open ports. Decision: [ADR 0010](../../../../docs/adr/0010-cloudflare-tunnel.md).

- [config.yaml](config.yaml) is the allow list. A hostname is public only if
  it has a rule there; everything else gets a 404 at the tunnel. The tunnel
  ID comes from `${TUNNEL_ID}` in `cluster-settings`.
- Rules point at Traefik's Service on 443 with `originServerName` set to the
  hostname, so cloudflared verifies the wildcard certificate.
- cloudflared reaches Traefik through the cluster network, so the Service's
  tailnet-only source ranges do not apply to it.
- `secret.sops.yaml` holds the tunnel credentials. Flux substitution is
  disabled on it.

## Creating the tunnel

Run once on the machine that holds your sops key. The `cloudflared` CLI is
only needed here; `docker run --rm -it -v ~/.cloudflared:/home/nonroot/.cloudflared cloudflare/cloudflared:<tag>`
works in its place.

```sh
cloudflared tunnel login                  # browser login, writes ~/.cloudflared/cert.pem
cloudflared tunnel create homeserver      # writes ~/.cloudflared/<tunnel-id>.json
id=$(cloudflared tunnel list -o json | jq -r '.[] | select(.name=="homeserver") | .id')
jq -Rs . < ~/.cloudflared/"$id".json \
  | sops set --value-stdin kubernetes/infrastructure/configs/cloudflared/secret.sops.yaml '["stringData"]["credentials.json"]'
printf '"%s"' "$id" \
  | sops set --value-stdin kubernetes/cluster/cluster-settings.sops.yaml '["stringData"]["TUNNEL_ID"]'
shred -u ~/.cloudflared/"$id".json ~/.cloudflared/cert.pem
unset id
```

## Publishing a hostname

1. Add a rule above the catch-all in [config.yaml](config.yaml), and an
   HTTPRoute for the hostname on the shared Gateway.
2. In Cloudflare DNS, replace the hostname's record with a proxied `CNAME`
   to `<tunnel-id>.cfargotunnel.com`. It then overrides the tailnet
   wildcard for that one name.

## Checking the tunnel

```sh
kubectl logs -n cloudflared deploy/cloudflared | grep -i "registered tunnel connection"
```

The Cloudflare dashboard lists the tunnel as Healthy with four connections.
