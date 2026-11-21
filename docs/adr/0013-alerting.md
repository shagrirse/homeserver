# 0013. Alerting: SLO burn rates and hard-down pages to Telegram

- Status: Accepted
- Date: 2026-11-21

## Context

[0011](0011-slo-targets.md) sets four SLOs with 28-day windows. A solo
operator tolerates almost no alert noise, and most routes see traffic too
low for error-rate statistics to be meaningful, so alerts must derive from
SLO burn rates and hard-down detection rather than static thresholds.

## Decision

- Grafana Alerting runs in the self-hosted Grafana against VictoriaMetrics,
  with rules provisioned from files in git.
- Pages go to Telegram: public site hard down (3 consecutive Synthetic
  Monitoring probe failures, fired from Grafana Cloud so it survives a dead
  node), public site fast burn (2% of budget in 1 h, multiwindow), all
  Kustomizations not Ready for 15 minutes, and per-route tailnet app hard
  down once apps exist.
- Tickets stay quiet in Grafana: slow burns on all four SLOs (10% of
  budget in 3 days), node disk over 80%, RAM pressure, wildcard certificate
  expiring within 14 days, backup job failures, and observability storage
  headroom.
- Low-traffic routes get no error-rate alerts; consecutive probe failures
  replace statistics where samples are too small.
- Synthetic Monitoring checks are configured in the Grafana Cloud console
  and move into OpenTofu when Cloudflare and Tailscale IaC lands.

## Alternatives considered

- **vmalert + Alertmanager**: matches VictoriaMetrics natively, but adds
  two components for no gain at one-person scale.
- **Static thresholds** on error counts: noisy at low traffic, the exact
  failure mode the burn-rate approach removes.
- **Email**: works from both Grafanas, but push notifications are the point
  of a pager.

## Consequences

- Pages are rare and each one names a user-facing failure.
- The dead-node gap for tailnet apps stays open: they have no external
  witness, so node death is noticed when the apps are next used. A
  heartbeat check against an external service closes it if it ever matters.
- Alert rules change through PRs, so alert changes are reviewed like code.
