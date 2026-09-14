# Pangolin chart example install profiles

These values files are intended to be copy/pasteable starting points.

## Prerequisites

- Helm repositories:
  - `helm repo add cloudnative-pg https://cloudnative-pg.github.io/charts`
  - `helm repo add traefik https://traefik.github.io/charts`
- Traefik CRDs/controller (for `deployment.type=controller` profiles)
- CloudNativePG operator/CRDs for CloudNativePG-backed profiles (`database.mode=cloudnativepg`)
- A working default StorageClass (or set explicit `*.persistence.storageClass`)

## Profile matrix

| Profile | File | Use when | Namespace creation behavior |
|---|---|---|---|
| Controller + CloudNativePG (recommended production starting point) | `values-controller-cnpg.yaml` | Kubernetes production-like controller setup with CNPG and Gerbil persistence | **No** (uses `namespace.create=true`) |
| E2E kind CloudNativePG | `values-e2e-kind.yaml` | Deterministic CI smoke install on kind with chart-managed namespace and CNPG cluster | **No** (uses `namespace.create=true`) |
| Controller + external PostgreSQL | `values-controller-external-db.yaml` | You already manage PostgreSQL externally | Usually **Yes** (unless you also set `namespace.create=true`) |
| Controller + SQLite (dev/test only) | `values-controller-sqlite-dev.yaml` | Local/dev/test only, non-production | **No** (uses `namespace.create=true`) |
| Standalone + Traefik | `values-standalone-traefik.yaml` | Standalone topology close to installer style; less recommended for K8s production | **No** (uses `namespace.create=true`) |
| Gerbil LoadBalancer | `values-gerbil-loadbalancer.yaml` | Expose Gerbil WireGuard ports via Kubernetes LoadBalancer | **No** (uses `namespace.create=true`) |
| Gerbil host gateway | `values-host-gateway.yaml` | Make tunnel backends reachable from an externally installed Traefik in controller + multi mode | **No** (uses `namespace.create=true`) |
| Gerbil tunnel bridge | `values-tunnel-bridge.yaml` | Same goal without hostNetwork, privileged PSA or Traefik co-location; needs Gerbil and controller images that support the bridge | **No** (uses `namespace.create=true`) |
| Single mode controller | `values-single-controller.yaml` | Demonstrate `deployment.mode=single` in controller mode (trade-off profile) | **No** (uses `namespace.create=true`) |
| Single mode standalone | `values-single-standalone.yaml` | Demonstrate `deployment.mode=single` in standalone mode (trade-off profile) | **No** (uses `namespace.create=true`) |

## Install commands

From repository root:

```bash
helm dependency build charts/pangolin
helm install demo charts/pangolin --namespace pangolin-demo -f charts/pangolin/examples/values-controller-cnpg.yaml
```

Swap the values file for your scenario.  
If your selected values file does **not** set `namespace.create=true`, add `--create-namespace`.

## Notes on database and secrets

- CloudNativePG examples intentionally avoid external-db fallback workarounds.
- External DB profile uses placeholders only (`<REPLACE_WITH_ACTUAL_PASSWORD>`, `*.example.test`) and demonstrates `sslMode` guidance:
  - internal/self-signed testing: `sslMode=disable`
  - production external DB: `sslMode=require` / `verify-ca` / `verify-full`

## Tunnel data path

Pangolin advertises Newt-site backends as WireGuard peer addresses, and Gerbil
creates that interface inside its own Pod network namespace. In
`deployment.type=controller` + `deployment.mode=multi` an externally installed
Traefik therefore cannot reach those backends and returns 502 for every
tunnel-backed resource, while still reporting the router as healthy.

Two profiles fix this:

- `values-tunnel-bridge.yaml` forwards through Gerbil's own Pod IP, so Traefik
  runs anywhere and nothing needs `hostNetwork`, a `privileged` PSA level or the
  CNI's masquerade. Prefer this where the Gerbil and controller images support
  it.
- `values-host-gateway.yaml` moves the tunnel interface into the node network
  namespace and pins Traefik to that node. Works with any image version, at the
  cost of those requirements.

See the "Tunnel data path" section of the chart README for both mechanisms, the
full comparison, and their limits.

## First-run behavior and Gerbil notes

- Gerbil requires `NET_ADMIN`; examples that set `namespace.create=true` include PSA labels with `enforce=privileged`.
- E2E profile sets `gerbil.startupMode=delayed` to reduce first-run instability during deterministic CI/kind installs.
- After first-run setup, switch Gerbil to normal startup:
  `helm upgrade pangolin-e2e charts/pangolin -f charts/pangolin/examples/values-e2e-kind.yaml --namespace pangolin-e2e --set gerbil.startupMode=normal`
- Keep Gerbil persistence enabled unless you intentionally want ephemeral WireGuard keys (dev/CI only).

## Readiness checks

After install:

```bash
kubectl get pods -n <namespace>
kubectl rollout status deployment/<release>-pangolin -n <namespace> --timeout=10m
```

Controller mode:

```bash
kubectl rollout status deployment/<release>-pangolin-controller -n <namespace> --timeout=10m
```

If Gerbil is enabled:

```bash
kubectl rollout status deployment/<release>-pangolin-gerbil -n <namespace> --timeout=10m
```

CloudNativePG cluster path:

```bash
kubectl wait --for=condition=Ready cluster.postgresql.cnpg.io/pangolin-db -n <namespace> --timeout=15m
```

## Uninstall

```bash
helm uninstall <release> -n <namespace>
```

If the namespace was chart-managed and is no longer needed:

```bash
kubectl delete namespace <namespace>
```

## Gerbil LoadBalancer annotations

Use `gerbil.service.annotations` to pass provider-specific Service annotations.

### Hetzner Cloud example

```yaml
gerbil:
  service:
    type: LoadBalancer
    annotations:
      load-balancer.hetzner.cloud/name: pangolin-gerbil
      load-balancer.hetzner.cloud/location: fsn1
      load-balancer.hetzner.cloud/uses-proxyprotocol: "false"
```

### AWS example

```yaml
gerbil:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

### MetalLB example

```yaml
gerbil:
  service:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/address-pool: public
```

Always verify annotation keys/values against your cloud/controller documentation.
