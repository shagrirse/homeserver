# Traefik

Ingress for the cluster, configured through the Gateway API only. Decision:
[ADR 0009](../../../../docs/adr/0009-ingress-and-tls.md).

- The chart installs Traefik and the `traefik` GatewayClass. The shared
  Gateway `main`, the wildcard Certificate and the HTTP-to-HTTPS redirect
  live in [configs/traefik](../../configs/traefik/).
- The Service is a LoadBalancer served by k3s ServiceLB, which binds 80 and
  443 on every node address. ServiceLB forwards around ufw's incoming rules,
  so `loadBalancerSourceRanges` limits clients to the Tailscale range
  (`100.64.0.0/10`). The Service's NodePorts are kept off the LAN by the
  k3s `nodeport-addresses` setting in `provision/`.
- ServiceLB masquerades every connection, so access logs show its pod
  address, not the client's.
- Pods cannot reach apps through the public hostname, because their
  addresses are outside the allowed range. Call the app's Service by its
  cluster DNS name instead.
- Only IPv4 is served. Publish `A` records for the domain, never `AAAA`:
  tailnet clients prefer IPv6 and would fail to connect.
- The Ingress provider is off. The CRD provider is on for `Middleware`.
- Access logs are JSON on stdout. The dashboard is not exposed.

## Exposing an app

Attach an HTTPRoute in the app's namespace to the `https` listener, or to
`https-apex` for the bare domain. The certificate already covers both:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
spec:
  parentRefs:
    - name: main
      namespace: traefik
      sectionName: https
  hostnames:
    - myapp.${DOMAIN}
  rules:
    - backendRefs:
        - name: myapp
          port: 80
```

`${DOMAIN}` is filled in by Flux from `cluster-settings`, so the Flux
Kustomization that applies the route needs `postBuild.substituteFrom` on it.

## Upgrading

Bump the tag in `ocirepository.yaml` and the image digest in
`helmrelease.yaml`. Check the chart changelog for the Gateway API version
the new Traefik expects, and bump the `gateway-api` tag in
[infrastructure.yaml](../../../cluster/infrastructure.yaml) to match.
