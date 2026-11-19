# Traefik

Ingress for the cluster, configured through the Gateway API only. Decision:
[ADR 0009](../../../../docs/adr/0009-ingress-and-tls.md).

- The chart installs Traefik and the `traefik` GatewayClass. The shared
  Gateway `main`, the wildcard Certificate and the HTTP-to-HTTPS redirect
  live in [configs/traefik](../../configs/traefik/).
- The Service is a LoadBalancer served by k3s ServiceLB, which binds 80 and
  443 on the node. ufw admits them only on `tailscale0`.
- The Ingress provider is off. The CRD provider is on for `Middleware`.
- Access logs are JSON on stdout. The dashboard is not exposed.

## Exposing an app

Attach an HTTPRoute in the app's namespace to the `https` listener. The
wildcard certificate already covers the hostname:

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
