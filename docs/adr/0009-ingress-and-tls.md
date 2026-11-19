# 0009. Traefik on the Gateway API with a cert-manager wildcard certificate

- Status: Accepted
- Date: 2026-11-20

## Context

Apps need HTTPS hostnames with publicly trusted certificates. The node has
no open ports to the internet: ufw admits host services only from the
tailnet, and public
traffic arrives through an outbound tunnel. The real domain must not appear
in git. Memory is tight, so the platform should run few, small pods.

## Decision

- Traefik, installed by Flux with the k3s bundle disabled, routes only
  Gateway API resources. One shared Gateway `main` in the `traefik`
  namespace has an HTTPS listener for `*.<domain>` and an HTTP listener that
  only redirects to HTTPS. Apps attach HTTPRoutes from their own namespaces.
- The Gateway API CRDs come from the upstream release tag through a Flux
  GitRepository, not from a chart.
- cert-manager keeps one wildcard certificate for the apex and
  `*.<domain>`, issued by Let's Encrypt over DNS-01 on Cloudflare.
- Flux applies the platform in three ordered layers: Gateway API CRDs,
  controllers, then the resources the controllers own.
- The domain and ACME email live in the encrypted `cluster-settings` Secret
  and are filled into manifests by Flux `postBuild` substitution.
- Traefik's Service uses k3s ServiceLB, so 80 and 443 bind on the node.
  ServiceLB's forwarding bypasses ufw's incoming rules, so the Service's
  `loadBalancerSourceRanges` admits only the Tailscale range, and kube-proxy
  serves NodePorts only on tailnet and loopback addresses.

## Alternatives considered

- **Ingress or Traefik IngressRoute**: Ingress is frozen upstream and
  IngressRoute ties every app to Traefik. The Gateway API splits ownership
  cleanly: the platform owns the Gateway, apps own routes.
- **Gateway API CRDs from the Traefik chart**: Helm never upgrades CRDs in a
  chart's `crds/` directory, and the CRDs are shared by every controller.
- **HTTP-01 or a certificate per app**: HTTP-01 needs an open port 80 and
  cannot issue wildcards. Per-app certificates multiply ACME orders and
  publish every hostname in Certificate Transparency logs.
- **Encrypting whole manifests to hide the domain**: makes routes and
  certificates unreviewable in diffs.

## Consequences

- Exposing an app is one HTTPRoute, with no certificate work.
- The wildcard key is a single secret that serves every app. Losing it
  exposes all hostnames, so it never leaves the `traefik` namespace.
- A Traefik upgrade may require a matching Gateway API CRD bump.
- Moving DNS off Cloudflare means changing the DNS-01 solver.
- ServiceLB masquerades connections, so Traefik never sees the client IP.
  Needing it, for logs or IP allow lists, would reopen how Traefik is
  exposed (for example hostPort instead of ServiceLB).
