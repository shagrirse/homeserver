# 0010. Public access through a Cloudflare Tunnel configured in git

- Status: Accepted
- Date: 2026-11-21

## Context

Some hostnames need to be reachable from the internet, while the router
keeps zero port forwards and everything else stays tailnet-only. DNS is on
Cloudflare, and `*.<domain>` points at the node's tailnet address. Every
change to what the cluster exposes should be a reviewed change in git.

## Decision

- cloudflared runs in the cluster and connects out to Cloudflare over a
  named, locally managed tunnel.
- Its ingress rules live in git as the allow list of public hostnames,
  ending in a catch-all 404. Each rule forwards to Traefik's Service on 443
  and verifies the wildcard certificate.
- The tunnel credentials are a SOPS Secret, and the tunnel ID is in
  `cluster-settings`.
- A public hostname gets a proxied `CNAME` to the tunnel, created in
  Cloudflare by hand, which overrides the tailnet wildcard for that name.

## Alternatives considered

- **Tunnel configured in the Cloudflare dashboard** (token-run): fewer
  moving parts, but what is public would live outside git and could change
  without review.
- **OpenTofu for the tunnel, its routes and DNS**: everything as code, but it
  needs remote state and a runner, which outweighs one record per public
  hostname. The git config moves over cleanly if Cloudflare IaC is adopted.
- **Port forwarding to Traefik**: exposes the home IP and needs open ports.

## Consequences

- Publishing a hostname is a PR plus one DNS record.
- Public requests reach Traefik from the cloudflared pod; the client IP is in
  the `CF-Connecting-IP` header.
- Requests through the tunnel pass Cloudflare's edge, so its WAF and Access
  can be put in front of a hostname without cluster changes.
