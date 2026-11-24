# Tailnet DNS

Pi-hole answers DNS for tailnet devices and blocks ads and trackers
([ADR 0016](../adr/0016-pihole-tailnet-dns.md)). The node itself does not use it.

## Enable

In the Tailscale admin console, open DNS, then:

1. Add the node's tailnet IP as a global nameserver. It is the only one.
2. Turn on Override DNS servers.

## Verify from a tailnet device

```sh
dig +short <ad domain, e.g. doubleclick.net>   # 0.0.0.0
dig +short example.com                          # a public address
dig +short <a MagicDNS name>                    # a tailnet address
```

The admin UI is at `https://pihole.<domain>` over the tailnet.

Check the node, which must not use Pi-hole:

```sh
getent hosts github.com           # resolves
grep nameserver /etc/resolv.conf  # upstream servers only
```

## When the Pi is down

Devices lose DNS because Pi-hole is their only nameserver. Disconnect the
device from the tailnet, or turn off Override DNS servers in the console, until
the node is back.

## Revert

Remove the nameserver from the Tailscale DNS settings. Devices go back to their
own resolvers at once.

## Availability

`kube_deployment_status_replicas_available{namespace="pihole"}` is `1` while
Pi-hole is up. Pi-hole logs are in VictoriaLogs.
