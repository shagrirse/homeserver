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
| Grafana | `grafana` | grafana-community chart, OCI | Admin credentials in `secret.sops.yaml`; datasources and dashboards provisioned from git |

- Alloy's config lives in the `alloy` HelmRelease values. Apps self-declare
  scrape endpoints with ServiceMonitor and PodMonitor CRDs (installed from
  the prometheus-operator repo by `kubernetes/cluster/infrastructure.yaml`).
- Node metrics come from Alloy's embedded unix exporter, which reads the
  node's `/proc`, `/sys` and root filesystem through read-only host mounts, so
  CPU, memory, disks and temperature describe the node. Network interface
  metrics come from the Alloy pod's own network namespace; per-pod traffic
  is in the cAdvisor series. Alloy runs as root with all capabilities dropped
  to read the root-owned pod logs.
- Grafana is served at `grafana.<domain>` through the shared Gateway, so it
  is reachable over the tailnet like every other route.
- Datasources have fixed UIDs (`victoria-metrics`, `victoria-logs`).
  VictoriaLogs ingests the Loki protocol but does not serve its query API, so
  Grafana reads logs through the `victoriametrics-logs-datasource` plugin,
  pinned in the HelmRelease and downloaded at pod start. Plugin
  auto-updates are off, so Prometheus and the other core datasources stay at
  the versions shipped in the pinned image. Only the Prometheus datasource
  and the VictoriaLogs plugin are enabled: each other bundled datasource
  runs as a separate backend process, and loading them all stalls Grafana 13's
  startup inside its memory limit.
- Dashboards (`Node`, `Flux`, `Traefik requests`) are JSON files in
  `dashboards/`, turned into the `grafana-dashboards` ConfigMap by
  `kustomization.yaml`. Grafana has no persistent volume, so changes made in
  the UI do not survive a restart; edit the files instead.
- Memory: VictoriaMetrics and VictoriaLogs cap their caches with
  `memory.allowedPercent` (the default is 60% of node RAM) on top of their
  container limits, keeping the whole stack around 1.5 GB.
- Flux substitutes `${...}` in this layer from the `cluster-settings`
  Secret, so a literal `${` in Alloy config or Helm values needs escaping
  as `$${`.
- Upgrade notes: VictoriaMetrics charts have no digest field, so image
  digests ride on the `image.tag` value as `tag@sha256:...`.
