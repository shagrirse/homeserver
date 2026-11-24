# 0016. Pi-hole as the tailnet nameserver

- Status: Accepted
- Date: 2026-11-24

## Context

The operator wants ads and trackers blocked on their own phone and laptop, not
for the household. Both devices are on the tailnet, so the tailnet's global
nameserver setting can point them at a DNS server that runs in the cluster.

The cluster has 8GB of memory shared with the observability stack, so the
resolver has to be small. Node name resolution (image pulls, CoreDNS upstream
lookups, Flux) must not depend on a workload that the node itself runs.

## Decision

- Pi-hole v6 runs as plain manifests in `kubernetes/apps/pihole/`. It is the
  only nameserver in the tailnet DNS settings, with no public fallback, so a
  device never silently loses blocking.
- DNS is published by a `LoadBalancer` Service on 53/UDP and 53/TCP. k3s
  ServiceLB serves it and `loadBalancerSourceRanges` limits it to the tailnet
  range `100.64.0.0/10`. This is the one exception to HTTPRoute-only
  exposure: DNS is not HTTP. The admin UI goes through the shared Gateway.
- ServiceLB publishes a Service port as a host port that matches every
  address on the node, loopback included. A port 53 Service would therefore
  capture the systemd-resolved stub on 127.0.0.53. The node resolves through
  its upstream servers directly with the stub off, and Tailscale is set not
  to accept tailnet DNS, so no node lookup reaches Pi-hole.
- Configuration is `FTLCONF_*` environment variables, which the UI shows as
  locked. Upstreams are Quad9 over plain DNS, with the default blocklist only,
  and the per-client rate limit is off because every tailnet device arrives
  from the same masqueraded source address.
- `/etc/pihole` is an `emptyDir`. Rollouts surge a second pod first
  (`maxSurge: 1`, `maxUnavailable: 0`), so DNS keeps answering while the
  blocklist is rebuilt. Readiness requires FTL answering and a non-empty
  blocklist.
- There is no metrics exporter. Availability comes from
  `kube_deployment_status_replicas_available{namespace="pihole"}`.
- Memory is 64Mi requested and 256Mi limit. A blocklist rebuild under load
  peaked at 87Mi when measured.

## Alternatives considered

- **hostNetwork bound to the tailscale interface:** couples the pod to node
  networking and the interface name, and still captures port 53 on the node.
- **Tailscale Kubernetes operator:** adds a controller and a tailnet device per
  Service for a single DNS endpoint.
- **A public fallback nameserver:** a device would bypass blocking whenever
  Pi-hole is slow or down, and that failure would not show.
- **AdGuard Home:** comparable blocking. Pi-hole wins on the maintained v6
  image, the `FTLCONF_*` configuration that locks settings in the UI, and the
  measured memory use.
- **A PVC with a `Recreate` strategy:** every rollout would drop DNS, and
  nothing worth keeping lives on the volume.
- **An Alloy blackbox probe:** the Deployment's available replicas already
  show whether the pod is up.

## Consequences

- There are no per-device statistics, because ServiceLB masquerades clients
  to one source address.
- The tailnet path is not probed. A routing or ServiceLB failure is invisible
  until a device fails to resolve.
- After a node reboot, DNS stays down if the blocklist sources are
  unreachable, because readiness needs a built blocklist.
- A tailnet device with no connection to the node has no DNS. Disconnecting
  from the tailnet or turning off the DNS override restores it.
- Query history and the blocklist database are lost when the pod is replaced.
- Reopen this if the tailnet gains devices that need per-device policy, or if
  a second DNS consumer needs the node to resolve through Pi-hole.
