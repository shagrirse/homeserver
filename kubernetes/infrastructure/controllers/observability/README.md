# Observability

The telemetry stack that measures the SLOs in
[ADR 0011](../../../../docs/adr/0011-slo-targets.md): Grafana Alloy scrapes
and tails the cluster, VictoriaMetrics stores metrics for 30 days,
VictoriaLogs stores logs for 14 days, kube-state-metrics exposes cluster
object metrics, and Grafana queries both stores. See
[ADR 0012](../../../../docs/adr/0012-observability-stack.md) for the
decision record.

| Component | Release | Source | Notes |
| --- | --- | --- | --- |
| Grafana Alloy | `alloy` | Grafana chart, OCI | One DaemonSet: ServiceMonitor/PodMonitor discovery, node, kubelet and cAdvisor scrapes, pod log tails |
| VictoriaMetrics | `victoria-metrics` | victoria-metrics-single chart, OCI | Single node, 30d retention, 20 Gi PVC |
| VictoriaLogs | `victoria-logs` | victoria-logs-single chart, OCI | Single node, 14d retention, 10 Gi PVC, Loki protocol ingest on port 9428 |
| kube-state-metrics | `kube-state-metrics` | prometheus-community chart, classic Helm repo | Its chart has no OCI release |
| Grafana | `grafana` | Grafana chart, OCI | Admin credentials in `secret.sops.yaml`; VM and VL datasources provisioned from the Helm values |

- Alloy's config lives in the `alloy` HelmRelease values. Apps self-declare
  scrape endpoints with ServiceMonitor and PodMonitor CRDs (installed from
  the prometheus-operator repo by `kubernetes/cluster/infrastructure.yaml`).
- Grafana is served at `grafana.<domain>` through the shared Gateway, so it
  is reachable over the tailnet like every other route.
- Memory: VictoriaMetrics and VictoriaLogs cap their caches with
  `memory.allowedPercent` (the default is 60% of node RAM) on top of their
  container limits, keeping the whole stack around 1.5 GB.
- Upgrade notes: VictoriaMetrics charts have no digest field, so image
  digests ride on the `image.tag` value as `tag@sha256:...`.
