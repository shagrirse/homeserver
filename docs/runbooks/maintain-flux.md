# Maintain Flux

Flux runs as two pieces with different owners, see
[ADR 0005](../adr/0005-flux-operator.md):

| Piece | Defined in | Changed by |
| --- | --- | --- |
| Flux Operator | `provision/roles/flux/defaults/main.yml` | `just provision --tags flux` |
| Flux controllers and sync | `kubernetes/cluster/flux-system/flux-instance.yaml` | A PR; Flux reconciles it |

Installing Flux on a new node is part of
[provision-node.md](provision-node.md). The deploy key and the cluster age
key are in [secrets.md](secrets.md).

## Check health

```sh
export KUBECONFIG=~/.kube/homeserver.yaml
kubectl -n flux-system get fluxinstance flux
flux get all -A
kubectl -n flux-system get fluxinstance flux \
  -o jsonpath='{range .status.components[*]}{.name} {.tag}@{.digest}{"\n"}{end}'
```

The instance is `Ready`, its revision names the Flux version, and every
component lists a digest.

## Upgrade Flux

1. Check that the running operator ships the release. Each operator version
   carries digests up to a given Flux version:

   ```sh
   gh api repos/controlplaneio-fluxcd/flux-operator/contents/config/data/flux-images/VERSION?ref=v<operator> \
     --jq .content | base64 -d
   ```

   If the release is newer, upgrade the operator first.
2. Read the Flux release notes for breaking changes.
3. Set `spec.distribution.version` in `flux-instance.yaml` to the exact new
   version, open a PR and merge it.
4. Check health as above; the revision shows the new version.

## Upgrade the operator

1. Read the release notes at
   <https://github.com/controlplaneio-fluxcd/flux-operator/releases>.
2. Get the image index digest and confirm it lists `linux/arm64`:

   ```sh
   docker buildx imagetools inspect ghcr.io/controlplaneio-fluxcd/flux-operator:v<version>
   ```

3. Set `flux_operator_version` and `flux_operator_image_digest` in
   `provision/roles/flux/defaults/main.yml`, open a PR and merge it.
4. From main, run `just provision --tags flux`. k3s upgrades the release; the
   controllers keep running throughout.
5. Confirm the new image and check health:

   ```sh
   kubectl -n flux-system get deploy flux-operator \
     -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   ```

## Remove Flux

Workloads Flux applied keep running; only Flux and the operator go away.

1. Install the `flux-operator` CLI matching the running operator from its
   release page and verify the checksum.
2. Remove the `flux` role from `provision/playbooks/site.yml` and merge that,
   so provisioning does not reinstall it.
3. Uninstall the instance and the operator. This removes their deployments,
   CRDs and the `flux-system` namespace, including both Secrets:

   ```sh
   KUBECONFIG=~/.kube/homeserver.yaml flux-operator -n flux-system uninstall
   ```

4. On the node, stop k3s from reinstalling the chart and drop its record:

   ```sh
   sudo rm /var/lib/rancher/k3s/server/manifests/flux-operator.yaml
   sudo k3s kubectl -n kube-system delete helmchart flux-operator
   ```

5. Remove the `flux-homeserver` deploy key from the repository's settings on
   GitHub.
