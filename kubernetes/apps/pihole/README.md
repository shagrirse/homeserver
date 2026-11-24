# pihole

Pi-hole blocks ads and trackers for the devices on the tailnet. It is the
only nameserver the tailnet hands out ([ADR 0016](../../../docs/adr/0016-pihole-tailnet-dns.md)).

- Namespace: `pihole`
- Exposure: DNS on 53/UDP and 53/TCP through a ServiceLB LoadBalancer limited
  to the tailnet range (`100.64.0.0/10`); the admin UI at `pihole.<domain>`
  through the shared Gateway
- Secrets: `pihole-admin` in `secret.sops.yaml`, key `password` (admin UI and
  API password)
- Data: `/etc/pihole` is an `emptyDir`. Nothing is backed up, the blocklist is
  rebuilt on every start, and query history is lost when the pod is replaced
- Configuration: only through `FTLCONF_*` environment variables in
  `deployment.yaml`; the UI shows those settings as locked
- Upgrade notes: bump the image tag and digest together and check that the
  index lists `linux/arm64`. A rollout surges a second pod and retires the old
  one once the new one is Ready, so DNS keeps answering. The image runs FTL
  as the `pihole` user with file capabilities, which needs
  `allowPrivilegeEscalation: true`; as root, dnsmasq's `setgid` fails on arm64
  and DNS stops answering while the pod stays up. After a bump, confirm a
  query to the pod IP is answered (`dig @<pod ip> example.com`), because the
  probes only test `127.0.0.1`
