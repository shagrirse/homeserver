# 0012. Observability stack: Alloy into VictoriaMetrics, VictoriaLogs and Grafana

- Status: Accepted
- Date: 2026-11-21

## Context

The platform layer is live and [0011](0011-slo-targets.md) defines four
SLOs that need measuring: per-route request success and latency, Flux
readiness, and a full-path probe of the public site. The node is one Pi 5
with 8 GB, every image must be arm64 and digest-pinned, and the stack is
maintained by one person, so component count and RAM matter.

## Decision

- Grafana Alloy runs as one DaemonSet: Prometheus-style scraping with
  ServiceMonitor/PodMonitor discovery, node metrics through its embedded
  unix exporter, and log collection forwarded to VictoriaLogs over the Loki
  protocol. It accepts OTLP for future app tracing.
- VictoriaMetrics single-node stores metrics with 30-day retention;
  VictoriaLogs stores logs with 14-day retention. Both are capped by
  container limits and VictoriaMetrics' `memory.allowedPercent`, since its
  default reserves 60% of node RAM.
- Grafana serves dashboards and, per [0013](0013-alerting.md), alerting.
- kube-state-metrics supplies cluster object metrics, and Flux's own
  `gotk_*` metrics feed SLO 4.
- The public journey is probed by Grafana Synthetic Monitoring hosted
  probes from outside the tailnet, exercising DNS, Cloudflare edge, tunnel,
  Traefik and the app.
- The stack lives in `kubernetes/infrastructure/controllers/observability/`
  with requests and limits on every component.

## Alternatives considered

- **vmagent + Vector**: comparable RAM, but vmagent has no native
  ServiceMonitor discovery without an operator, so scrape configs would be
  hand-maintained per app. Promtail, the other usual log agent, is
  deprecated.
- **In-cluster blackbox_exporter for the public path**: no external
  account, but the probe shares the home uplink, so an ISP outage blinds
  the probe and the site together.
- **Prometheus + Loki**: heavier TSDB, and VictoriaMetrics was already
  chosen for the plan.

## Consequences

- The stack costs roughly 1.5 GB of the 8 GB node budget; capacity is
  tracked as a budget, see the node's memory tickets.
- Apps self-declare their scrape endpoints through ServiceMonitor CRDs and
  are picked up without agent changes.
- Self-hosted alerting dies with the node; the hosted probe carries the
  external, node-independent signal.
