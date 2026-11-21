# 0011. Service level objectives

- Status: Accepted
- Date: 2026-11-21

## Context

The platform layer is live (Traefik, cert-manager, cloudflared) and the
first app is next. Before telemetry exists, agree what "working" means for
the people who use the system, so the monitoring stack measures those
things instead of whatever is easy to scrape. Targets are reviewed monthly
against telemetry and tuned when a journey's reality changes.

## Decision

- Four SLOs over rolling 28-day windows. Internal targets, no SLA.
- Public visitor loads the portfolio site: availability 99.5% (successful /
  valid requests), latency 99% of requests under 500 ms.
- Operator uses self-hosted apps over the tailnet: availability 99% across
  tailnet routes.
- Operator ships a change: 99% of 5-minute samples have all Flux
  Kustomizations Ready.
- The public journey is measured along its full path by a synthetic probe
  from outside the tailnet (DNS, Cloudflare edge, tunnel, Traefik, app);
  Traefik metrics separate tunnel failures from app failures.
- Error budget policy: a fast budget burn notifies the operator; an
  exhausted budget pauses new apps and infrastructure experiments until
  reliability recovers.

## Alternatives considered

- **99.9% availability**: the common default for paying services, but
  deliberate reboots and tunnel reconnects would burn it on a home server
  and train the operator to ignore the signal.
- **Component-focused SLOs** (CPU, disk, pod restarts): easy to scrape, but
  they describe causes, not what users experience.
- **No SLOs**: alert thresholds get picked ad hoc per alert instead of
  deriving from an agreed target.

## Consequences

- The telemetry stack must measure per-route request success and latency,
  Flux readiness, and a full-path probe of the public site.
- Alerting derives from burn rates against these targets.
- About 3.4 h of public downtime and 6.7 h of tailnet downtime per month
  are tolerated by design; worse than that is a signal to fix reliability
  first.
