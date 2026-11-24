# Architecture decision records

One short record per architectural decision, numbered in order. Copy
[template.md](template.md) for a new one. Superseded records stay in place and
link to their replacement.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-k3s-on-raspberry-pi.md) | k3s on a Raspberry Pi 5 | Accepted |
| [0002](0002-flux-gitops.md) | Flux for GitOps delivery | Accepted |
| [0003](0003-ubuntu-26-04-host-os.md) | Ubuntu Server 26.04 LTS as the host OS | Accepted |
| [0004](0004-cluster-age-key.md) | A dedicated age key for the cluster, installed by provisioning | Accepted |
| [0005](0005-flux-operator.md) | Flux installed by the Flux Operator | Accepted |
| [0006](0006-usb-nvme-boot-disk.md) | NVMe SSD over USB as the boot disk | Accepted |
| [0007](0007-tailscale-ssh.md) | Tailscale SSH for remote shell access | Accepted |
| [0008](0008-tailscale-policy-as-code.md) | Tailnet policy managed from git | Accepted |
| [0009](0009-ingress-and-tls.md) | Traefik on the Gateway API with a cert-manager wildcard certificate | Accepted |
| [0010](0010-cloudflare-tunnel.md) | Public access through a Cloudflare Tunnel configured in git | Accepted |
| [0011](0011-slo-targets.md) | Service level objectives | Accepted |
| [0012](0012-observability-stack.md) | Observability stack: Alloy into VictoriaMetrics, VictoriaLogs and Grafana | Accepted |
| [0013](0013-alerting.md) | Alerting: SLO burn rates and hard-down pages to Telegram | Accepted |
| [0014](0014-backups.md) | Backups: restic into Cloudflare R2 with tested restores | Accepted |
| [0015](0015-secret-checks.md) | Layered secret checks with a squash-only protected main | Accepted |
| [0016](0016-pihole-tailnet-dns.md) | Pi-hole as the tailnet nameserver | Accepted |
