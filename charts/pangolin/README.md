# Pangolin Helm Chart

![Version: 0.1.0-alpha.0](https://img.shields.io/badge/Version-0.1.0--alpha.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.18.2](https://img.shields.io/badge/AppVersion-1.18.2-informational?style=flat-square)

Pangolin Helm Chart

## Features

- All-in-one (single) or multi-deployment composition
- Standalone Traefik integration (in-pod) or Kube Controller mode
- Embedded PostgreSQL or external/CloudNativePG database support
- Let's Encrypt ACME certificate management via Traefik
- Gerbil WireGuard tunnel management
- Prometheus monitoring (ServiceMonitor, PodMonitor, PrometheusRule)
- Kubernetes RBAC for controller mode (supports targeting a separate Traefik namespace)
- NetworkPolicy support
- Optional Blueprint support (store blueprint YAML as chart-managed ConfigMaps/Secrets)

## Prerequisites

- Kubernetes >= 1.30.14
- Helm 3.x

## Architecture overview

This chart can deploy a Pangolin control-plane plus optional components:

- **Pangolin app**: the main API/UI workloads and Services.
- **pangolin-kube-controller** (controller mode): reconciles Traefik CRDs and reads Pangolin config from the Pangolin API endpoint.
- **Traefik**:
	- **Controller mode**: you run a Traefik Ingress Controller (optionally installed via the bundled dependency, aliased as `traefikController`).
	- **Standalone mode**: the chart runs an in-cluster Traefik Deployment managed directly by this chart.
- **Database**: one of `cloudnativepg`, `external`, `embedded`, or `sqlite` (see below).

## Deployment modes

- `deployment.type=controller` (recommended)
	- Runs Pangolin + `pangolin-kube-controller`.
	- Requires Traefik CRDs and a Traefik controller (either installed separately or via `deployment.installTraefikController=true`).
- `deployment.type=standalone`
	- Runs Pangolin plus an internal Traefik workload managed by this chart.
	- Best for labs/dev; for production, controller mode is recommended unless you specifically need a self-contained deployment.

`deployment.mode` controls how workloads are split:

- `multi`: separate workloads for Pangolin / Gerbil / Traefik.
- `single`: one shared Pod. In `deployment.type=controller`, it runs Pangolin + optional Gerbil + controller. In `deployment.type=standalone`, it runs Pangolin + optional Gerbil + optional standalone Traefik. `deployment.mode=multi` remains the recommended production topology.

## Example install profiles

Scenario-based example values files are in [`charts/pangolin/examples/`](./examples/).
Use the examples guide for profile selection, prerequisites, and install/cleanup commands:
[`charts/pangolin/examples/README.md`](./examples/README.md).

## Database mode selection

The default `database.mode` is **`cloudnativepg`** — the recommended production path. Pangolin automatically uses the PostgreSQL-capable image (`fosrl/pangolin:postgresql-<appVersion>`) for any non-SQLite mode.

| Mode | Use case | Pangolin image |
|------|----------|---------------|
| `cloudnativepg` | **Recommended production** – CloudNativePG operator manages PostgreSQL | `fosrl/pangolin:postgresql-<appVersion>` |
| `external` | Production with externally managed PostgreSQL (RDS, Cloud SQL, etc.) | `fosrl/pangolin:postgresql-<appVersion>` |
| `embedded` | Labs/test – chart-managed PostgreSQL StatefulSet | `fosrl/pangolin:postgresql-<appVersion>` |
| `sqlite` | **Dev/CI only – NOT for production** | `fosrl/pangolin:<appVersion>` |

## CloudNativePG setup (recommended production database)

CloudNativePG (CNPG) is the preferred production database backend. The chart uses the official
[cloudnative-pg operator chart](https://cloudnative-pg.github.io/charts) and the official
[cluster chart](https://cloudnative-pg.github.io/charts) from the same repository.

The operator and cluster are controlled only by top-level subchart values and support four modes:

1. **External operator + external cluster**: `cnpg-operator.enabled=false`, `cnpg-cluster.enabled=false`
2. **Chart installs operator only**: `cnpg-operator.enabled=true`, `cnpg-cluster.enabled=false`
3. **Chart installs cluster only**: `cnpg-operator.enabled=false`, `cnpg-cluster.enabled=true`
4. **Chart installs both operator and cluster**: `cnpg-operator.enabled=true`, `cnpg-cluster.enabled=true`

When `database.mode=cloudnativepg` and `cnpg-cluster.enabled=true`, Pangolin resolves the cluster
name in this order:

1. `cnpg-cluster.fullnameOverride` (when non-empty)
2. `database.cloudnativepg.cluster.name`

If both are set to different values, chart rendering fails with:
`PANGOLIN-CNPG: cnpg-cluster.fullnameOverride and database.cloudnativepg.cluster.name must match when cnpg-cluster.enabled=true`.

### Connecting Pangolin to a CNPG cluster

CloudNativePG automatically creates an application Secret when a cluster boots.
For a cluster named `pangolin-db` (the default `cnpg-cluster.fullnameOverride`),
the Secret is named **`pangolin-db-app`** and contains the key **`uri`** with the full PostgreSQL
connection string (format: `postgresql://user:password@host:port/dbname?sslmode=...`).

**Default behavior — auto-derived CNPG app Secret (no extra configuration needed):**

The chart automatically references the CNPG-generated app Secret (`<cluster-name>-app`, key `uri`)
when no explicit `database.connection.existingSecretName` is set. With the default cluster name
`pangolin-db`, the Deployment uses:

```
secretName: pangolin-db-app
key:        uri
```

This means a basic CNPG setup requires **no `database.connection` overrides at all**.

**Optional: explicitly reference the CNPG-generated app Secret:**

```yaml
database:
  mode: cloudnativepg
  # cloudnativepg.cluster.name is optional when cnpg-cluster.fullnameOverride is set
  connection:
    existingSecretName: pangolin-db-app   # created automatically by CNPG
    existingSecretKey: uri

cnpg-cluster:
  enabled: true
  fullnameOverride: pangolin-db
```

**Alternative — let the chart build a connection string from a password Secret:**

```yaml
database:
  mode: cloudnativepg
  cloudnativepg:
    auth:
      existingSecretName: my-db-password-secret   # Secret with the password
      passwordKey: password
    connection:
      generatedSecret:
        create: true
```

> **Note:** The chart never silently generates a passwordless PostgreSQL connection string. If you
> enable `database.cloudnativepg.connection.generatedSecret.create=true` without providing a
> password source, the chart will fail at render time with a clear error message.

See `examples/values-controller-cnpg.yaml` for a complete working example.

## External PostgreSQL database

For production deployments using an externally managed PostgreSQL server (RDS, Cloud SQL,
self-managed, etc.), set `database.mode=external` and configure one of these options:

### Option A — User-managed Secret (recommended for production)

Create the Secret yourself and reference it. The chart will fail with a clear error (PANGOLIN-061)
if no Secret source is configured.

```bash
kubectl create secret generic pangolin-ext-db \
  --from-literal=connectionString="postgresql://pangolin:s3cr3t@db.example.com:5432/pangolin?sslmode=require"
```

```yaml
database:
  mode: external
  connection:
    existingSecretName: pangolin-ext-db    # pre-existing Secret
    existingSecretKey: connectionString
```

### Option B — Chart-managed Secret from a full connection string

```yaml
database:
  mode: external
  external:
    generatedSecret:
      create: true
      connectionString: "postgresql://pangolin:s3cr3t@db.example.com:5432/pangolin?sslmode=require"
```

### Option C — Chart-managed Secret from individual connection parameters

```yaml
database:
  mode: external
  external:
    generatedSecret:
      create: true
      host: db.example.com
      port: 5432
      database: pangolin
      username: pangolin
      password: s3cr3t
      sslMode: require
```

> **Note:** Setting `database.mode=external` without any Secret source configuration will cause Helm
> to fail at render time with a clear `PANGOLIN-061` error. This prevents Pangolin from starting with
> a missing database Secret.

See `examples/values-controller-external-db.yaml` for a complete working example.

## Ingress and Traefik guidance

- In controller mode you typically expose Pangolin via Traefik CRDs/IngressRoute resources.
- `pangolin.config.traefik` configures the Traefik output Pangolin generates in `config.yml`; it does **not** install Traefik.
- The chart renders `pangolin.config.traefik` by default so entrypoint and cert resolver names are explicit. Review `pangolin.config.traefik.http_entrypoint`, `https_entrypoint`, and `cert_resolver` so they match your real Traefik deployment.
- If you enable the bundled Traefik dependency, put Traefik chart overrides under the **`traefikController:`** key (the dependency is aliased).
- In standalone mode, Traefik dashboard is **disabled by default** and the Service does **not** expose the admin port.

### Chart-managed dashboard IngressRoute (controller mode)

By default (`pangolin.ingressRoute.dashboard.enabled=true`) the chart renders a Traefik `IngressRoute`
for the Pangolin dashboard/API when `deployment.type=controller`.

- Host defaults to `pangolin.config.app.dashboard_url` (hostname extracted from URL), or set `pangolin.ingressRoute.dashboard.host`.
- API route: `Host(<host>) && PathPrefix(/api/v1)` -> `pangolin.service.ports.external` (default `3000`), priority `100`.
- Dashboard route: `Host(<host>)` -> `pangolin.service.ports.next` (default `3002`), priority `10`.
- `tls.certResolver` and `tls.secretName` are mutually exclusive when TLS is enabled.
- `tls.secretName` references a Secret in the same namespace as the `IngressRoute` (Traefik CRD cross-namespace Secret usage is provider-dependent and not configured by this chart).
- To target one Traefik instance in multi-controller setups, add `pangolin.ingressRoute.dashboard.traefikSelectorLabels` (metadata labels matched by the provider `labelSelector`).
- `ingressClassName` is mapped to `metadata.annotations["kubernetes.io/ingress.class"]` for CRD-provider ingress-class filtering.

#### Example: certResolver mode

```yaml
pangolin:
  config:
    app:
      dashboard_url: "https://pangolin-e2e.example.com"
  ingressRoute:
    dashboard:
      enabled: true
      tls:
        certResolver: letsencrypt
```

#### Example: existing TLS Secret mode

```yaml
pangolin:
  ingressRoute:
    dashboard:
      enabled: true
      tls:
        certResolver: ""
        secretName: pangolin-dashboard-tls
```

#### Example: multi-Traefik labelSelector mode

```yaml
pangolin:
  ingressRoute:
    dashboard:
      enabled: true
      traefikSelectorLabels:
        traefik-instance: public
```

## Security and permissions

- **Gerbil/WireGuard:** Gerbil typically needs to run as root and requires Linux capabilities like `NET_ADMIN`/`SYS_MODULE` for WireGuard tunnel management. Do not “blindly harden” Gerbil without validating WireGuard functionality in your environment.
- **NetworkPolicy:** By default, the chart does **not** allow broad HTTPS egress to the internet. If your deployment needs outbound TCP/443, explicitly enable it (or, preferably, add a scoped allow-list via `networkPolicy.extraEgress`).
- **ServiceAccount token automount (least-privilege):**
  - **Controller** (`serviceAccount.controller.automountServiceAccountToken=true`, default): the pangolin-kube-controller must call the Kubernetes API to reconcile Traefik CRDs, manage EndpointSlices, and (optionally) perform leader election. It therefore requires a mounted ServiceAccount token. The matching RBAC Role/ClusterRole is only bound to the controller ServiceAccount.
  - **Pangolin** (`serviceAccount.pangolin.automountServiceAccountToken=false`, default): the main Pangolin application server does not require Kubernetes API access. Keeping automount disabled follows the least-privilege principle and prevents accidental in-cluster API calls.
  - **Gerbil** (`serviceAccount.gerbil.automountServiceAccountToken=false`, default): Gerbil manages WireGuard tunnels and does not require Kubernetes API access. Token automount is disabled by default.
  - All three settings are configurable via `serviceAccount.<component>.automountServiceAccountToken`.
- **Single mode ServiceAccount trade-off:** Kubernetes ServiceAccount selection is Pod-level. In `deployment.mode=single` + `deployment.type=controller`, the shared Pod uses the controller ServiceAccount/token so Pangolin and Gerbil share that Pod-level token behavior.
- **hostNetwork:** `runtime.hostNetwork=true` reduces network isolation. Enable it only when you understand why it’s required (some WireGuard / UDP exposure setups may need it).
- **Container security context:** `global.containerSecurityContext` is intentionally empty by default so you can choose a baseline that matches your cluster policy. Workloads merge this with their own `*.securityContext`.

## Production checklist

- Use `deployment.type=controller` unless you have a reason not to.
- Use `cloudnativepg` or `external` for the database; avoid `sqlite` in production.
- For CloudNativePG (recommended):
	- The chart **automatically** references the CNPG-generated app Secret (`<cluster-name>-app`, key `uri`).
	  No extra `database.connection` configuration is needed for the default setup.
	- Or explicitly reference it via `database.connection.existingSecretName: <cluster-name>-app` / `existingSecretKey: uri`
	- Or provide a password and set `database.cloudnativepg.connection.generatedSecret.create=true`
- Provide externally managed Secrets where appropriate:
	- `pangolin.secret.existingSecretName` (Pangolin app server secret)
	- database connection Secret (`database.connection.existingSecretName`)
- Review `pangolin.config.traefik.*` so Pangolin emits routes for the same Traefik entrypoints and certificate resolver names your cluster actually uses.
- For external PostgreSQL:
	- User-managed Secret: set `database.connection.existingSecretName` — Helm fails with PANGOLIN-061 if omitted
	- Chart-managed Secret: set `database.external.generatedSecret.create=true` with a `connectionString` or individual params
- If you use standalone Traefik + ACME:
	- set `traefik.config.letsencryptEmail`
	- enable persistence when dashboard/ACME state must survive restarts
- Review NetworkPolicy egress needs and avoid broad 0.0.0.0/0 allows when possible.
- Validate Gerbil/WireGuard requirements against your cluster security policies.

## Release smoke-test and readiness checklist

Use this checklist before tagging alpha/RC/stable releases. This runtime validation is intentionally separate from the automated E2E workflow.

### Before alpha

- [ ] `helm dependency build charts/pangolin`
- [ ] `helm lint charts/pangolin`
- [ ] Render templates:
  - [ ] `helm template demo charts/pangolin --namespace pangolin > /tmp/pangolin-default.yaml`
  - [ ] `for values in charts/pangolin/examples/*.yaml; do helm template demo charts/pangolin --namespace pangolin -f "$values" > "/tmp/pangolin-$(basename "$values" .yaml).yaml"; done`
- [ ] `helm unittest charts/pangolin`
- [ ] `yamllint -d '{extends: relaxed, rules: {line-length: {max: 200}, indentation: {spaces: consistent, indent-sequences: whatever}, trailing-spaces: disable}}' /tmp/pangolin-*.yaml`
- [ ] `for f in /tmp/pangolin-*.yaml; do kubeconform -strict -summary -ignore-missing-schemas "$f"; done`
- [ ] Validate image/app versions and ArtifactHub image annotations in `charts/pangolin/Chart.yaml` and `charts/pangolin/values.yaml` are consistent.
- [ ] Bump chart version from `0.1.0-alpha.0` to the next alpha in `charts/pangolin/Chart.yaml`.
- [ ] Do **not** change `kubeVersion`; current value is intentional.

### Before RC

- [ ] Install in a real cluster (or Talos GitHub Actions cluster) and wait for readiness:
  - [ ] `kubectl wait --for=condition=Available deploy/<release>-pangolin -n <ns> --timeout=10m`
  - [ ] `kubectl wait --for=condition=Available deploy/<release>-pangolin-kube-controller -n <ns> --timeout=10m`
- [ ] Default controller + CloudNativePG path reaches readiness (`deployment.type=controller`, `database.mode=cloudnativepg`).
- [ ] Pangolin is running with PostgreSQL image:
  - [ ] `kubectl get deploy/<release>-pangolin -n <ns> -o jsonpath='{.spec.template.spec.containers[0].image}'` contains `:postgresql-`.
- [ ] Gerbil registration + persistence works:
  - [ ] Confirm startup logs show registration success.
  - [ ] Confirm `/var/config/key` persists across restart (`kubectl exec ... -- ls -l /var/config/key`, then restart and re-check).
- [ ] Controller probes and API access work:
  - [ ] `kubectl port-forward -n <ns> svc/<release>-pangolin-kube-controller 9090:9090` then `curl -fsS http://127.0.0.1:9090/livez` and `curl -fsS http://127.0.0.1:9090/readyz`.
  - [ ] Controller logs confirm Kubernetes API connectivity (no repeated in-cluster auth/permission errors).
- [ ] Traefik CRDs are present and reconciled where applicable (`IngressRoute`, `Middleware`, `TLSOption`).
- [ ] Default NetworkPolicy does not block startup (Pangolin, Gerbil, controller, and DB all become ready).

### Before stable

- [ ] Runtime test matrix:
  - [ ] Controller / multi mode (`deployment.type=controller`, `deployment.mode=multi`) — required.
  - [ ] Controller / single mode after single mode is implemented.
  - [ ] Standalone / multi mode.
  - [ ] Standalone / single mode if implemented.
  - [ ] External DB mode.
  - [ ] Strict NetworkPolicy mode (`examples/values-networkpolicy-strict.yaml`).
- [ ] Production guidance is still accurate:
  - [ ] `deployment.mode=multi` remains recommended for production.
  - [ ] Standalone Traefik remains less recommended than controller mode unless self-contained deployment is required.
- [ ] Renovate dry-run confirms image/action/dependency update detection.
- [ ] ArtifactHub metadata verified (links, maintainers, image annotations).
- [ ] Blueprint + Newt workflow tested/documented:
  - [ ] Blueprint files are stored by this chart (ConfigMap/Secret).
  - [ ] Blueprints are applied via Newt (`--blueprint-file` / `--provisioning-blueprint-file`), not by Pangolin server directly.

## Troubleshooting basics

- Check rendered resources: `helm template <release> charts/pangolin -n <ns> | less`
- Check pods: `kubectl get pods -n <ns> -l app.kubernetes.io/instance=<release>`
- Check events: `kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -n 50`
- Controller logs: `kubectl logs -n <ns> deploy/<release>-pangolin --since=10m` (adjust name if overridden)

## Gerbil networking model

- Gerbil always opens UDP ports on the Pod.
- `gerbil.service.enabled=false` means the chart does not create a Service for those UDP ports (useful for hostNetwork/hostPort patterns or when you publish UDP another way).
- If you need Kubernetes Service-based exposure for Gerbil UDP, set `gerbil.service.enabled=true` and pick an appropriate Service `type`.

## Gerbil first-run bootstrap behavior

- Upstream Pangolin returns `404 {"message":"Exit node not found"}` from `/gerbil/get-all-relays` until an exit node exists.
- Upstream Gerbil exits on startup when that endpoint returns non-200 (`Failed to fetch initial mappings`), so waiting for Gerbil readiness can fail on fresh installs before UI/bootstrap is completed.
- Use `gerbil.startupMode=delayed` for first installs or smoke tests. This keeps Gerbil resources rendered but starts the Deployment with `replicas: 0` so `helm install --wait` can succeed while you complete initial Pangolin setup.
- After setup, switch to normal startup with:

```bash
helm upgrade <release> <chart> -n <namespace> --reuse-values --set gerbil.startupMode=normal
```

## Secrets

- **Pangolin app secret:** If you do not provide `pangolin.secret.existingSecretName`, the chart generates a strong random secret and reuses it across upgrades.
- **Controller TLS:** In controller mode, the chart can generate a self-signed `kubernetes.io/tls` Secret (or you can provide an existing one via `controller.tls.existingSecretName`).

## Standalone Traefik notes

- `pangolin.config.traefik` configures Pangolin's generated Traefik output only; Traefik installation is controlled separately by top-level `traefik.enabled`.
- `traefik.enabled=true` requires `traefik.config.letsencryptEmail` to be set.
- If you enable the Traefik dashboard (`traefik.config.dashboard=true`), enable `traefik.persistence.enabled` so ACME state survives restarts.

## Storage

- If your cluster has no default StorageClass, explicitly set `global.storageClass` and/or per-PVC `*.persistence.storageClass` values.

## Upgrades and rollbacks

- Secrets generated by the chart (like the Pangolin app secret) are designed to be stable across upgrades.
- For embedded database mode, data lives on a PVC; rolling back a chart does not revert database data.
- Use standard Helm workflows: `helm upgrade` to update, `helm rollback` to revert.

## Blueprints

Pangolin [Blueprints](https://docs.pangolin.net/manage/blueprints) let you define resources (public-resources, private-resources, sites) as YAML and apply them to Pangolin via Newt agents using `--blueprint-file` or `--provisioning-blueprint-file`. The Pangolin server does **not** read blueprint files directly — Newt pushes blueprints through the Pangolin API.

This chart provides optional storage of blueprint YAML files as Kubernetes ConfigMaps and Secrets so they can be managed declaratively alongside your Pangolin release.

### Enabling blueprints

```yaml
pangolin:
  blueprints:
    enabled: true
    configMap:
      create: true
    files:
      site-blueprint.yaml: |
        sites:
          my-site:
            name: My Site
            docker-socket-enabled: true
        public-resources:
          web-app:
            name: Web Application
            protocol: http
            full-domain: "app.example.com"
            targets:
              - site: my-site
                hostname: app
                port: 8080
                method: http
```

### Environment templating

Blueprint YAML supports `{{env.VARIABLE_NAME}}` placeholders. At apply time, Newt resolves them from its process environment. Store sensitive per-site or per-device values (serial numbers, customer slugs) in a Secret:

```yaml
pangolin:
  blueprints:
    enabled: true
    existingConfigMap: my-blueprint-configmap    # ConfigMap you manage externally
    environmentSecret:
      create: true
    environment:
      BASE_DOMAIN: "example.com"
      # Sensitive values should come from an existingEnvironmentSecret instead:
      # SERIAL_NUMBER: "device-001"
```

> **Security note:** Do **not** put sensitive provisioning values (API tokens, passwords, device serials) into the chart-managed blueprint `environment` map. Pass them to the chart via `existingEnvironmentSecret` pointing at a Secret you manage outside this chart, or inject them directly into your Newt process environment.

### Using existing resources

```yaml
pangolin:
  blueprints:
    enabled: true
    existingConfigMap: my-blueprint-configmap         # pre-existing ConfigMap
    existingEnvironmentSecret: my-blueprint-env       # pre-existing Secret
```

See `examples/values-blueprints.yaml` for a complete working example.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cnpg-cluster | object | `{"cluster":{"instances":1,"monitoring":{"enabled":false},"postgresql":{"parameters":{}},"storage":{"size":"8Gi","storageClass":""}},"enabled":false,"fullnameOverride":"pangolin-db","managed":{"backup":{},"monitoring":{"enabled":false},"roles":[],"services":{"disabledDefaultServices":[]}},"mode":"standalone","namespace":"","type":"postgresql"}` | --------------------------------------------------------------------------- # @section CloudNativePG Cluster subchart |
| cnpg-cluster.cluster.instances | int | `1` | Number of PostgreSQL instances in the CNPG cluster. |
| cnpg-cluster.cluster.monitoring | object | `{"enabled":false}` | Optional monitoring configuration for the CNPG cluster. |
| cnpg-cluster.cluster.postgresql | object | `{"parameters":{}}` | Optional PostgreSQL parameters and bootstrap configuration. |
| cnpg-cluster.cluster.storage | object | `{"size":"8Gi","storageClass":""}` | Storage configuration for the CNPG cluster. |
| cnpg-cluster.cluster.storage.storageClass | string | `""` | StorageClass for CNPG PVCs. When empty, the cluster uses the Kubernetes default StorageClass. If your cluster has no default StorageClass, set this explicitly. |
| cnpg-cluster.enabled | bool | `false` | Enable the official CloudNativePG `cluster` Helm chart as a dependency/subchart. |
| cnpg-cluster.fullnameOverride | string | `"pangolin-db"` | Override the CNPG cluster resource name to keep it stable and RFC1123-safe. Set this to match `database.cloudnativepg.cluster.name`. |
| cnpg-cluster.managed | object | `{"backup":{},"monitoring":{"enabled":false},"roles":[],"services":{"disabledDefaultServices":[]}}` | Managed application database/user bootstrap configuration for the CNPG cluster. |
| cnpg-cluster.mode | string | `"standalone"` | CNPG deployment mode passed to the official `cluster` chart. |
| cnpg-cluster.namespace | string | `""` | Target namespace for the CNPG cluster release / cluster CR. Leave empty to use the Pangolin release namespace unless your chart logic/templates override it. |
| cnpg-cluster.type | string | `"postgresql"` | CNPG workload type passed to the official `cluster` chart. |
| cnpg-operator | object | `{"additionalLabels":{},"config":{"data":{}},"crds":{"create":true},"enabled":false,"monitoring":{"grafanaDashboard":{"create":false},"podMonitorEnabled":false},"namespace":"","replicaCount":1}` | --------------------------------------------------------------------------- # @section CloudNativePG Operator subchart |
| cnpg-operator.additionalLabels | object | `{}` | Additional labels applied by the CloudNativePG operator chart where supported. |
| cnpg-operator.config.data | object | `{}` | Operator configuration values passed to the upstream chart when needed. |
| cnpg-operator.crds.create | bool | `true` | Create/upgrade CloudNativePG CRDs through the operator chart. |
| cnpg-operator.enabled | bool | `false` | Enable the official CloudNativePG operator Helm chart as a dependency/subchart. |
| cnpg-operator.monitoring.podMonitorEnabled | bool | `false` | Create ServiceMonitor resources for the operator if supported by the upstream chart. |
| cnpg-operator.namespace | string | `""` | Target namespace for the CloudNativePG operator release. Leave empty to let the Helm release/subchart behavior decide the namespace. |
| cnpg-operator.replicaCount | int | `1` | Number of CloudNativePG operator replicas. |
| controller | object | `{"commonAnnotations":{},"commonLabels":{},"config":{"allowInsecureHttp":null,"configEndpoint":"","configTlsSkipVerify":false,"enableLeaderElection":false,"leaseLockNamespace":"","logTraefikConfig":false,"metricsAddr":":9090","readOnly":false,"targetNamespace":""},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"enabled":true,"extraEnv":{},"monitoring":{"podMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"metrics","relabelings":[],"scheme":"http","scrapeTimeout":"10s"},"prometheusRule":{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"labels":{},"namespace":"","rules":[]},"serviceMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","targetLabels":[]}},"probes":{"liveness":{"failureThreshold":3,"httpGet":{"path":"/livez","port":"metrics"},"initialDelaySeconds":10,"periodSeconds":10,"timeoutSeconds":5},"readiness":{"failureThreshold":3,"httpGet":{"path":"/readyz","port":"metrics"},"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":5},"startup":{"failureThreshold":24,"httpGet":{"path":"/livez","port":"metrics"},"initialDelaySeconds":5,"periodSeconds":5,"timeoutSeconds":3}},"rbac":{"annotations":{},"labels":{}},"replicaCount":1,"resources":{"limits":{"cpu":"500m","ephemeral-storage":"128Mi","memory":"512Mi"},"requests":{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":false},"service":{"annotations":{},"enabled":true,"labels":{},"port":9090,"portName":"metrics","type":"ClusterIP"},"serviceAccount":{"annotations":{},"labels":{}},"tls":{"enabled":false,"existingSecretName":""},"waitForPangolin":{"enabled":true,"image":{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"curlimages/curl","tag":"8.8.0"},"intervalSeconds":5,"stableSeconds":30,"timeoutSeconds":600},"workloadType":"Deployment"}` | --------------------------------------------------------------------------- # @section Pangolin kube controller |
| controller.commonAnnotations | object | `{}` | Annotations added to all controller resources rendered by this chart. |
| controller.commonLabels | object | `{}` | Labels added to all controller resources rendered by this chart. |
| controller.config.allowInsecureHttp | string | `nil` | Allow plaintext HTTP for the controller config endpoint. Set to `null` (default) to auto-derive from `configEndpoint` (`http://` => true, `https://` => false). INSECURE: plaintext HTTP is only acceptable for same-namespace in-cluster traffic protected by NetworkPolicy. For production, prefer HTTPS/mTLS (set an HTTPS configEndpoint and enable controller.tls). |
| controller.config.configEndpoint | string | `""` | Pangolin config API endpoint consumed by the controller. Defaults to in-cluster HTTP (`http://<pangolin-service>:3001/...`). Set an HTTPS endpoint when using TLS/mTLS for controller->Pangolin traffic. |
| controller.config.configTlsSkipVerify | bool | `false` | Skip TLS verification when fetching Pangolin config. |
| controller.config.enableLeaderElection | bool | `false` | Enable lease-based leader election. |
| controller.config.leaseLockNamespace | string | `""` | Namespace used for the leader election Lease. Defaults to targetNamespace when empty. |
| controller.config.logTraefikConfig | bool | `false` | DEBUG ONLY. Log full rendered Traefik configuration. |
| controller.config.metricsAddr | string | `":9090"` | Metrics / health listen address. |
| controller.config.readOnly | bool | `false` | Run controller in read-only mode and disable mutating operations. |
| controller.config.targetNamespace | string | `""` | Namespace where Traefik CRDs/resources live. Defaults to `deployment.traefikNamespace` or release namespace when empty. |
| controller.enabled | bool | `true` | Enable Pangolin kube controller. Default should be true because the preferred chart mode is controller + multi. |
| controller.monitoring.podMonitor | object | `{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"metrics","relabelings":[],"scheme":"http","scrapeTimeout":"10s"}` | Enable PodMonitor for Prometheus Operator. |
| controller.monitoring.prometheusRule | object | `{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"labels":{},"namespace":"","rules":[]}` | Create PrometheusRule resources for the controller. |
| controller.monitoring.serviceMonitor | object | `{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","targetLabels":[]}` | Enable ServiceMonitor for Prometheus Operator. |
| controller.replicaCount | int | `1` | Number of controller replicas. |
| controller.service.enabled | bool | `true` | Create a metrics / health Service for the controller. |
| controller.tls.enabled | bool | `false` | Mount a TLS Secret at /etc/pangolin/tls for the controller. Keep disabled for the default same-namespace HTTP setup. Enable only when controller.config.configEndpoint uses HTTPS and the controller needs client TLS material. When enabled and no existing Secret is provided, the chart generates a self-signed certificate. |
| controller.tls.existingSecretName | string | `""` | Existing Secret name to use for controller TLS material. When set, the chart does not generate a Secret. |
| controller.waitForPangolin.enabled | bool | `true` | Wait for Pangolin CONFIG_ENDPOINT before starting controller. |
| controller.workloadType | string | `"Deployment"` | Controller workload type. |
| database | object | `{"cloudnativepg":{"auth":{"existingSecretName":"","generatedSecret":{"create":false,"name":"","password":"","passwordKey":"password"},"passwordKey":"password"},"cluster":{"name":"pangolin-db","port":5432,"rwServiceName":""},"connection":{"database":"pangolin","existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"create":false,"key":"connectionString","name":""},"host":"","port":5432,"sslMode":"disable","username":"pangolin"}},"connection":{"existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"create":true,"key":"connectionString","name":"","sslMode":"disable"}},"embedded":{"auth":{"databaseKey":"database","existingSecretName":"","generatedSecret":{"create":true,"databaseKey":"database","name":"","password":"","passwordKey":"password","usernameKey":"username"},"passwordKey":"password","usernameKey":"username"},"commonAnnotations":{},"commonLabels":{},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"enabled":false,"extraEnv":{},"persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"existingClaim":"","size":"8Gi","storageClass":""},"podSecurityContext":{"fsGroup":null},"resources":{"limits":{"cpu":"300m","ephemeral-storage":"128Mi","memory":"256Mi"},"requests":{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}},"service":{"annotations":{},"enabled":true,"labels":{},"port":5432,"type":"ClusterIP"},"workloadType":{"kind":"StatefulSet","replicaCount":1}},"external":{"enabled":false,"existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"connectionString":"","create":false,"database":"","host":"","key":"connectionString","name":"","password":"","port":5432,"sslMode":"disable","username":""}},"mode":"cloudnativepg","name":"pangolin","sqlite":{"enabled":false,"path":"/app/data/pangolin.db","persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"existingClaim":"","size":"1Gi","storageClass":""}},"username":"pangolin"}` | --------------------------------------------------------------------------- # @section Database |
| database.cloudnativepg | object | `{"auth":{"existingSecretName":"","generatedSecret":{"create":false,"name":"","password":"","passwordKey":"password"},"passwordKey":"password"},"cluster":{"name":"pangolin-db","port":5432,"rwServiceName":""},"connection":{"database":"pangolin","existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"create":false,"key":"connectionString","name":""},"host":"","port":5432,"sslMode":"disable","username":"pangolin"}}` | CloudNativePG-backed database configuration. This is the recommended production backend model for Pangolin on Kubernetes. |
| database.cloudnativepg.auth.existingSecretName | string | `""` | Existing Secret name containing the application user password for Pangolin. This password is used to generate the final application-facing connection string. |
| database.cloudnativepg.auth.generatedSecret.create | bool | `false` | Create a Secret containing the Pangolin database password for use with CNPG connection generation. |
| database.cloudnativepg.auth.generatedSecret.name | string | `""` | Name of the generated CNPG auth Secret. Defaults to "<fullname>-cnpg-app-auth" when empty. |
| database.cloudnativepg.auth.generatedSecret.password | string | `""` | Pangolin database password. |
| database.cloudnativepg.auth.generatedSecret.passwordKey | string | `"password"` | Key inside the generated CNPG auth Secret containing the password. |
| database.cloudnativepg.auth.passwordKey | string | `"password"` | Key in the existing Secret containing the Pangolin database password. |
| database.cloudnativepg.cluster.name | string | `"pangolin-db"` | CloudNativePG cluster name used for Pangolin. When `cnpg-cluster.enabled=true` and `cnpg-cluster.fullnameOverride` is set, templates prefer `cnpg-cluster.fullnameOverride` for CNPG Secret/service derivation. If both are set to different values, chart validation fails. |
| database.cloudnativepg.cluster.port | int | `5432` | PostgreSQL port exposed by the CNPG cluster service. |
| database.cloudnativepg.cluster.rwServiceName | string | `""` | Read-write service hostname override for Pangolin connection generation. When empty, templates can derive it from the CNPG cluster naming convention. |
| database.cloudnativepg.connection.database | string | `"pangolin"` | Database name used in the generated Pangolin connection string. |
| database.cloudnativepg.connection.existingSecretKey | string | `"connectionString"` | Key inside the existing Secret containing the final Pangolin CNPG connection string. |
| database.cloudnativepg.connection.existingSecretName | string | `""` | Existing Secret containing a fully assembled Pangolin connection string for CNPG. If set, this takes precedence over chart-generated CNPG connection strings. |
| database.cloudnativepg.connection.generatedSecret.create | bool | `false` | Create a chart-managed Secret containing the final Pangolin CNPG connection string. Requires a password to be available via database.cloudnativepg.auth.generatedSecret.password or database.cloudnativepg.auth.existingSecretName (the chart looks up the Secret at render time). If you are using the CloudNativePG-generated app Secret (typically <cluster>-app with key `uri`), leave create=false and reference it via database.connection.existingSecretName instead. |
| database.cloudnativepg.connection.generatedSecret.key | string | `"connectionString"` | Key used in the generated CNPG connection Secret. |
| database.cloudnativepg.connection.generatedSecret.name | string | `""` | Name of the generated CNPG connection Secret. Defaults to "<fullname>-cnpg-db-connection" when empty. |
| database.cloudnativepg.connection.host | string | `""` | Override the hostname used when generating the final Pangolin connection string. Usually left empty so templates derive it from the CNPG cluster/service. |
| database.cloudnativepg.connection.port | int | `5432` | Override the port used when generating the final Pangolin connection string. |
| database.cloudnativepg.connection.sslMode | string | `"disable"` | SSL mode used in the generated Pangolin connection string. Default `disable` is intended for chart-managed in-cluster CNPG connectivity unless TLS/CA is explicitly configured. |
| database.cloudnativepg.connection.username | string | `"pangolin"` | Username used in the generated Pangolin connection string. |
| database.connection | object | `{"existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"create":true,"key":"connectionString","name":"","sslMode":"disable"}}` | Unified application-facing database connection secret configuration. Pangolin should always consume one consistent Secret/key pair regardless of the selected backend mode. |
| database.connection.existingSecretKey | string | `"connectionString"` | Key inside the existing Secret containing the final Pangolin PostgreSQL connection string. |
| database.connection.existingSecretName | string | `""` | Existing Secret name containing the final Pangolin PostgreSQL connection string. If set, this takes precedence over chart-generated connection secrets. |
| database.connection.generatedSecret.create | bool | `true` | Create a chart-managed Secret containing the Pangolin PostgreSQL connection string. Used for `embedded` mode (chart-builds the connection string from embedded PostgreSQL credentials). For `cloudnativepg` mode, the chart auto-derives the CNPG-generated app Secret (`<cluster-name>-app`) and this flag has no effect. For `external` mode, use `database.external.generatedSecret.create` instead. |
| database.connection.generatedSecret.key | string | `"connectionString"` | Key used inside the generated Secret for the final connection string. |
| database.connection.generatedSecret.name | string | `""` | Name of the generated connection Secret. Defaults to "<fullname>-db-connection" when empty. |
| database.connection.generatedSecret.sslMode | string | `"disable"` | SSL mode appended to generated PostgreSQL connection strings where applicable. Default `disable` is intended for simple in-cluster chart-managed database paths. For external/production PostgreSQL, prefer `require`, `verify-ca`, or `verify-full` with proper CA handling. |
| database.embedded | object | `{"auth":{"databaseKey":"database","existingSecretName":"","generatedSecret":{"create":true,"databaseKey":"database","name":"","password":"","passwordKey":"password","usernameKey":"username"},"passwordKey":"password","usernameKey":"username"},"commonAnnotations":{},"commonLabels":{},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"enabled":false,"extraEnv":{},"persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"existingClaim":"","size":"8Gi","storageClass":""},"podSecurityContext":{"fsGroup":null},"resources":{"limits":{"cpu":"300m","ephemeral-storage":"128Mi","memory":"256Mi"},"requests":{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}},"service":{"annotations":{},"enabled":true,"labels":{},"port":5432,"type":"ClusterIP"},"workloadType":{"kind":"StatefulSet","replicaCount":1}}` | Simple embedded PostgreSQL configuration managed directly by this chart. This mode is mainly intended for lightweight/lab/test scenarios. |
| database.embedded.auth.databaseKey | string | `"database"` | Key in the existing Secret containing the database name. |
| database.embedded.auth.existingSecretName | string | `""` | Existing Secret name containing embedded PostgreSQL credentials. |
| database.embedded.auth.generatedSecret.create | bool | `true` | Create a Secret for embedded PostgreSQL credentials when no existing Secret is used. |
| database.embedded.auth.generatedSecret.databaseKey | string | `"database"` | Key used for the database name in the generated Secret. |
| database.embedded.auth.generatedSecret.name | string | `""` | Name of the generated auth Secret. Defaults to "<fullname>-embedded-postgres-auth" when empty. |
| database.embedded.auth.generatedSecret.password | string | `""` | Password value for embedded PostgreSQL. Leave empty to have the chart generate a strong random password (recommended). Prefer using an existing Secret in production. |
| database.embedded.auth.generatedSecret.passwordKey | string | `"password"` | Key used for the password in the generated Secret. |
| database.embedded.auth.generatedSecret.usernameKey | string | `"username"` | Key used for the username in the generated Secret. |
| database.embedded.auth.passwordKey | string | `"password"` | Key in the existing Secret containing the password. |
| database.embedded.auth.usernameKey | string | `"username"` | Key in the existing Secret containing the username. |
| database.embedded.commonAnnotations | object | `{}` | Annotations added to all embedded PostgreSQL resources rendered by this chart. |
| database.embedded.commonLabels | object | `{}` | Labels added to all embedded PostgreSQL resources rendered by this chart. |
| database.embedded.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the embedded PostgreSQL PVC. |
| database.embedded.persistence.annotations | object | `{}` | Additional annotations for the embedded PostgreSQL PVC. |
| database.embedded.persistence.enabled | bool | `false` | Persist embedded PostgreSQL data on a PersistentVolumeClaim. |
| database.embedded.persistence.existingClaim | string | `""` | Existing PVC name to use for embedded PostgreSQL data. |
| database.embedded.persistence.size | string | `"8Gi"` | PVC size for embedded PostgreSQL. |
| database.embedded.persistence.storageClass | string | `""` | StorageClass for the embedded PostgreSQL PVC. Falls back to `global.storageClass` when empty. |
| database.embedded.podSecurityContext.fsGroup | string | `nil` | Extra podSecurityContext merged into the embedded Postgres workload. Set fsGroup explicitly only if your Postgres image/storage permissions require it. |
| database.embedded.resources.requests | object | `{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}` | Resource requests/limits for the embedded PostgreSQL workload. |
| database.embedded.service.annotations | object | `{}` | Additional annotations for the embedded PostgreSQL Service. |
| database.embedded.service.enabled | bool | `true` | Create a Service for embedded PostgreSQL. |
| database.embedded.service.labels | object | `{}` | Additional labels for the embedded PostgreSQL Service. |
| database.embedded.service.port | int | `5432` | Service port for embedded PostgreSQL. |
| database.embedded.service.type | string | `"ClusterIP"` | Service type for embedded PostgreSQL. |
| database.embedded.workloadType.kind | string | `"StatefulSet"` | Workload type for the embedded PostgreSQL instance. |
| database.embedded.workloadType.replicaCount | int | `1` | Number of embedded PostgreSQL replicas. Keep this at 1 unless you explicitly know what you are doing. |
| database.external | object | `{"enabled":false,"existingSecretKey":"connectionString","existingSecretName":"","generatedSecret":{"connectionString":"","create":false,"database":"","host":"","key":"connectionString","name":"","password":"","port":5432,"sslMode":"disable","username":""}}` | Existing external PostgreSQL database configuration. |
| database.external.existingSecretKey | string | `"connectionString"` | Key in the external Secret containing the connection string. |
| database.external.existingSecretName | string | `""` | Existing Secret name containing a PostgreSQL connection string for Pangolin. External-mode compatibility key. Prefer using database.connection.existingSecretName when possible so Pangolin always consumes one consistent Secret/key regardless of database mode. |
| database.external.generatedSecret.connectionString | string | `""` | Full PostgreSQL connection string for Pangolin. When set, this value is used directly and the individual connection parameters below are ignored. |
| database.external.generatedSecret.create | bool | `false` | Create a chart-managed Secret containing the external PostgreSQL connection string. |
| database.external.generatedSecret.database | string | `""` | Database name. Defaults to database.name when empty. Used when connectionString is empty. |
| database.external.generatedSecret.host | string | `""` | PostgreSQL hostname. Used when connectionString is empty. |
| database.external.generatedSecret.key | string | `"connectionString"` | Key used inside the generated external connection Secret. |
| database.external.generatedSecret.name | string | `""` | Name of the generated external connection Secret. Defaults to "<fullname>-db-connection" when empty. |
| database.external.generatedSecret.password | string | `""` | Database password. Used when connectionString is empty. Special characters (e.g. @ : / ?) are automatically percent-encoded in the connection string. |
| database.external.generatedSecret.port | int | `5432` | PostgreSQL port. Used when connectionString is empty. |
| database.external.generatedSecret.sslMode | string | `"disable"` | SSL mode. Used when connectionString is empty. Default `disable` is intended for simple in-cluster usage. For external/production PostgreSQL, prefer `require`, `verify-ca`, or `verify-full` with proper CA handling. |
| database.external.generatedSecret.username | string | `""` | Database username. Defaults to database.username when empty. Used when connectionString is empty. |
| database.mode | string | `"cloudnativepg"` | Database backend mode used by Pangolin. `cloudnativepg` = preferred production mode using the CloudNativePG operator and cluster chart `external`      = use an already existing external PostgreSQL database `embedded`      = use a simple chart-managed PostgreSQL instance `sqlite`        = use SQLite (development / test only; NOT recommended for production) |
| database.name | string | `"pangolin"` | Logical database name used by Pangolin. |
| database.sqlite | object | `{"enabled":false,"path":"/app/data/pangolin.db","persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":false,"existingClaim":"","size":"1Gi","storageClass":""}}` | SQLite backend configuration. Recommended only for development or very small test deployments. |
| database.sqlite.path | string | `"/app/data/pangolin.db"` | SQLite database file path used by Pangolin. |
| database.sqlite.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the SQLite PVC. |
| database.sqlite.persistence.annotations | object | `{}` | Additional annotations for the SQLite PVC. |
| database.sqlite.persistence.enabled | bool | `false` | Persist the SQLite database file on a PersistentVolumeClaim. |
| database.sqlite.persistence.existingClaim | string | `""` | Existing PVC name to use for SQLite. |
| database.sqlite.persistence.size | string | `"1Gi"` | PVC size for SQLite data. |
| database.sqlite.persistence.storageClass | string | `""` | StorageClass for the SQLite PVC. Falls back to `global.storageClass` when empty. |
| database.username | string | `"pangolin"` | Database username used by Pangolin. |
| deployment | object | `{"installTraefikController":false,"mode":"multi","traefikNamespace":"","type":"controller"}` | --------------------------------------------------------------------------- # @section Deployment topology |
| deployment.installTraefikController | bool | `false` | Install bundled Traefik subchart when `deployment.type=controller`. |
| deployment.mode | string | `"multi"` | Pod topology for Pangolin application components. `single` runs one Pod containing Pangolin plus optional Gerbil and either pangolin-kube-controller (controller type) or standalone Traefik (standalone type). `multi` runs separate workloads (recommended for production). |
| deployment.traefikNamespace | string | `""` | Namespace where Traefik controller resources live in controller mode. Defaults to the release namespace. |
| deployment.type | string | `"controller"` | Pangolin deployment integration mode. `controller` uses pangolin-kube-controller and Traefik CRDs. `standalone` runs an internal Traefik Pod (not recommended for production). |
| gerbil | object | `{"args":[],"command":[],"commonAnnotations":{},"commonLabels":{},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"enabled":true,"extraEnv":{},"persistence":{"accessModes":["ReadWriteOnce"],"annotations":{},"enabled":true,"existingClaim":"","size":"1Gi","storageClass":""},"ports":{"internalApi":3004,"wg1":51820,"wg2":21820},"probes":{},"pvc":{"annotations":{},"labels":{}},"replicaCount":1,"resources":{"limits":{"cpu":"500m","ephemeral-storage":"128Mi","memory":"512Mi"},"requests":{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"add":["NET_ADMIN"],"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsNonRoot":false},"service":{"annotations":{},"enabled":true,"externalTrafficPolicy":"","labels":{},"loadBalancerIP":"","loadBalancerSourceRanges":[],"ports":[{"name":"wg1","port":51820,"protocol":"UDP","targetPort":"wg1"},{"name":"wg2","port":21820,"protocol":"UDP","targetPort":"wg2"},{"name":"internal-api","port":3004,"protocol":"TCP","targetPort":"internal-api"}],"type":"ClusterIP"},"serviceAccount":{"annotations":{},"labels":{}},"startupMode":"normal","waitForPangolin":{"enabled":true,"endpoint":"","image":{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"curlimages/curl","tag":"8.8.0"},"intervalSeconds":5,"stableSeconds":30,"timeoutSeconds":600}}` | --------------------------------------------------------------------------- # @section Gerbil |
| gerbil.args | list | `[]` | Override the Gerbil container args. When empty the chart computes the following default args:   --reachableAt=http://<gerbil-svc>:<internalApi-port>   --generateAndSaveKeyTo=/var/config/key   --remoteConfig=http://<pangolin-svc>:<internalApi-port>/api/v1/ Set this list explicitly to pass custom args to Gerbil. |
| gerbil.command | list | `[]` | Override the Gerbil container entrypoint (command). When empty the container image's default entrypoint is used. |
| gerbil.commonAnnotations | object | `{}` | Annotations added to all Gerbil resources rendered by this chart. |
| gerbil.commonLabels | object | `{}` | Labels added to all Gerbil resources rendered by this chart. |
| gerbil.enabled | bool | `true` | Enable Gerbil component. |
| gerbil.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the Gerbil PVC. |
| gerbil.persistence.annotations | object | `{}` | Additional annotations for the Gerbil PVC. |
| gerbil.persistence.enabled | bool | `true` | Persist Gerbil key/config data on a PVC. Enabled by default (production-recommended): Gerbil saves its WireGuard private key to /var/config/key. Without persistence the key regenerates on every restart, which forces all WireGuard peers to re-handshake and breaks connectivity until peers reconnect. Disable only for ephemeral dev/CI environments where key rotation is acceptable. |
| gerbil.persistence.existingClaim | string | `""` | Existing PVC name to use for Gerbil config/key data. When set, skips PVC creation and mounts the referenced claim directly. |
| gerbil.persistence.size | string | `"1Gi"` | PVC size for Gerbil config/key data. |
| gerbil.persistence.storageClass | string | `""` | StorageClass for the Gerbil PVC. Falls back to `global.storageClass` when empty. When both are empty, the cluster default StorageClass is used. |
| gerbil.ports.internalApi | int | `3004` | Internal Gerbil API/listener TCP port. |
| gerbil.ports.wg1 | int | `51820` | First WireGuard UDP port exposed by Gerbil. |
| gerbil.ports.wg2 | int | `21820` | Second WireGuard UDP port exposed by Gerbil. |
| gerbil.probes | object | `{}` | Gerbil health probes. Disabled by default because the previously shipped probe path was not mounted by the chart. Configure probes explicitly if your Gerbil image exposes a reliable health check. |
| gerbil.replicaCount | int | `1` | Number of Gerbil replicas in multi mode. |
| gerbil.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"add":["NET_ADMIN"],"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsNonRoot":false}` | Gerbil container security context. WARNING: NET_ADMIN is required for WireGuard interface management and MUST NOT be removed. Without NET_ADMIN, Gerbil cannot create or manage WireGuard network interfaces. If your cluster enforces Pod Security Admission (baseline/restricted), you must label the deployment namespace to allow this capability:   kubectl label ns <namespace> pod-security.kubernetes.io/enforce=privileged --overwrite Or set namespace.create=true and namespace.podSecurity.enforce=privileged in values. SYS_MODULE is NOT added by default; add it explicitly only if your node kernel requires module loading from inside the container (uncommon on managed clusters). |
| gerbil.service.enabled | bool | `true` | Create a Service for Gerbil UDP traffic. Enabled by default so a standard installation can receive WireGuard traffic without hostNetwork/hostPort overrides. |
| gerbil.service.loadBalancerIP | string | `""` | Fixed IP to request from the cloud provider when type=LoadBalancer. Leave empty to let the provider assign an IP automatically. |
| gerbil.startupMode | string | `"normal"` | Gerbil first-run startup behavior. `normal`: render and start Gerbil immediately. `delayed`: render Gerbil resources but keep the multi-mode Gerbil Deployment at replicas=0. `disabledUntilSetup`: do not render Gerbil resources until switched back to `normal` (or `delayed`). |
| gerbil.waitForPangolin.enabled | bool | `true` | Wait for Pangolin internal API before starting Gerbil. |
| gerbil.waitForPangolin.endpoint | string | `""` | Override endpoint checked by the wait initContainer. Defaults to http://<pangolin-service>:<internal-api-port>/api/v1/ |
| global | object | `{"additionalAnnotations":{},"additionalLabels":{},"additionalPodAnnotations":{},"additionalPodLabels":{},"additionalServiceAnnotations":{},"additionalServiceLabels":{},"affinity":{},"commonAnnotations":{},"commonLabels":{},"containerSecurityContext":{},"extraEnv":{},"fullnameOverride":"","image":{"imagePullPolicy":"IfNotPresent","imagePullSecrets":[],"registry":"docker.io"},"nameOverride":"","namespaceOverride":"","nodeSelector":{},"podSecurityContext":{"fsGroupChangePolicy":"OnRootMismatch","seccompProfile":{"type":"RuntimeDefault"}},"priorityClassName":"","revisionHistoryLimit":10,"storageClass":"","tolerations":[],"topologySpreadConstraints":[]}` | --------------------------------------------------------------------------- # @section Global settings |
| global.additionalAnnotations | object | `{}` | Common annotations applied to all resources rendered by this chart. |
| global.additionalLabels | object | `{}` | Common labels applied to all resources rendered by this chart. |
| global.additionalPodAnnotations | object | `{}` | Common annotations added to all Pods. |
| global.additionalPodLabels | object | `{}` | Common labels added to all Pods. |
| global.additionalServiceAnnotations | object | `{}` | Common annotations added to all Services. |
| global.additionalServiceLabels | object | `{}` | Common labels added to all Services. |
| global.affinity | object | `{}` | Affinity applied to all Pods. |
| global.commonAnnotations | object | `{}` | Common annotations applied to all resources rendered by this chart (preferred alias). |
| global.commonLabels | object | `{}` | Common labels applied to all resources rendered by this chart (preferred alias). |
| global.containerSecurityContext | object | `{}` | Default container security context. |
| global.extraEnv | object | `{}` | Common extra environment variables added to all containers. |
| global.fullnameOverride | string | `""` | Override the fully qualified app name. |
| global.image | object | `{"imagePullPolicy":"IfNotPresent","imagePullSecrets":[],"registry":"docker.io"}` | Global container image configuration used by all chart components. |
| global.image.imagePullSecrets | list | `[]` | Image pull secrets applied to all workloads by default. |
| global.image.registry | string | `"docker.io"` | Default image registry for all components. |
| global.nameOverride | string | `""` | Override the chart name. |
| global.namespaceOverride | string | `""` | Override namespace for rendered resources. |
| global.nodeSelector | object | `{}` | Node selector applied to all Pods. |
| global.podSecurityContext | object | `{"fsGroupChangePolicy":"OnRootMismatch","seccompProfile":{"type":"RuntimeDefault"}}` | Default pod security context. |
| global.priorityClassName | string | `""` | Default PriorityClass applied to all Pods. |
| global.revisionHistoryLimit | int | `10` | Revision history limit for Deployments and StatefulSets. |
| global.storageClass | string | `""` | Default StorageClass used by all PVCs when the local storageClass is empty. |
| global.tolerations | list | `[]` | Tolerations applied to all Pods. |
| global.topologySpreadConstraints | list | `[]` | Topology spread constraints applied to all Pods. |
| highAvailability | object | `{"podAntiAffinity":{"enabled":false,"labelSelector":{},"topologyKey":"kubernetes.io/hostname","type":"soft","weight":100},"podDisruptionBudget":{"annotations":{},"enabled":false,"labels":{},"maxUnavailable":null,"minAvailable":1}}` | --------------------------------------------------------------------------- # @section High availability |
| highAvailability.podAntiAffinity | object | `{"enabled":false,"labelSelector":{},"topologyKey":"kubernetes.io/hostname","type":"soft","weight":100}` | Optional anti-affinity helper for spreading replicas. |
| highAvailability.podDisruptionBudget | object | `{"annotations":{},"enabled":false,"labels":{},"maxUnavailable":null,"minAvailable":1}` | Enable a chart-managed PodDisruptionBudget for applicable workloads. |
| images | object | `{"controller":{"digest":"","pullPolicy":"IfNotPresent","registry":"ghcr.io","repository":"fosrl/pangolin-kube-controller","tag":"0.1.0-alpha.1"},"gerbil":{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"fosrl/gerbil","tag":"1.3.1"},"pangolin":{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"fosrl/pangolin","tag":""},"pangolinPostgresql":{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"fosrl/pangolin","tag":""},"postgres":{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"postgres","tag":"18.3-alpine"},"traefik":{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"traefik","tag":"v3.6.15"}}` | --------------------------------------------------------------------------- # @section Images |
| images.controller.digest | string | `""` | Pangolin kube controller image digest. Overrides tag when set. |
| images.controller.pullPolicy | string | `"IfNotPresent"` | Pangolin kube controller image pull policy. |
| images.controller.registry | string | `"ghcr.io"` | Pangolin kube controller image registry. |
| images.controller.repository | string | `"fosrl/pangolin-kube-controller"` | Pangolin kube controller image repository. |
| images.controller.tag | string | `"0.1.0-alpha.1"` | Pangolin kube controller image tag. Managed independently from `.Chart.AppVersion`. |
| images.gerbil.digest | string | `""` | Gerbil image digest. Overrides tag when set. |
| images.gerbil.pullPolicy | string | `"IfNotPresent"` | Gerbil image pull policy. |
| images.gerbil.registry | string | `"docker.io"` | Gerbil image registry. |
| images.gerbil.repository | string | `"fosrl/gerbil"` | Gerbil image repository. |
| images.gerbil.tag | string | `"1.3.1"` | Gerbil image tag. |
| images.pangolin.digest | string | `""` | Pangolin image digest. Overrides tag and automatic image selection when set. |
| images.pangolin.pullPolicy | string | `"IfNotPresent"` | Pangolin image pull policy. |
| images.pangolin.registry | string | `"docker.io"` | Pangolin image registry. The chart selects the correct image variant based on `database.mode` automatically. Set an explicit `tag` or `digest` to override automatic image selection. |
| images.pangolin.repository | string | `"fosrl/pangolin"` | Pangolin image repository. |
| images.pangolin.tag | string | `""` | Pangolin image tag. Defaults to .Chart.AppVersion when empty. Set this to override automatic database-mode-based image selection. |
| images.pangolinPostgresql.digest | string | `""` | PostgreSQL-capable Pangolin image digest. Overrides tag when set. |
| images.pangolinPostgresql.pullPolicy | string | `"IfNotPresent"` | PostgreSQL-capable Pangolin image pull policy. |
| images.pangolinPostgresql.registry | string | `"docker.io"` | PostgreSQL-capable Pangolin image registry. Used automatically when database.mode is not sqlite (unless images.pangolin.tag or images.pangolin.digest is set). |
| images.pangolinPostgresql.repository | string | `"fosrl/pangolin"` | PostgreSQL-capable Pangolin image repository. |
| images.pangolinPostgresql.tag | string | `""` | PostgreSQL-capable Pangolin image tag. Defaults to "postgresql-<AppVersion>" when empty. |
| images.postgres.digest | string | `""` | Embedded Postgres image digest. Overrides tag when set. |
| images.postgres.pullPolicy | string | `"IfNotPresent"` | Embedded Postgres image pull policy. |
| images.postgres.registry | string | `"docker.io"` | Embedded Postgres image registry. |
| images.postgres.repository | string | `"postgres"` | Embedded Postgres image repository. |
| images.postgres.tag | string | `"18.3-alpine"` | Embedded Postgres image tag. |
| images.traefik.digest | string | `""` | Traefik image digest. Overrides tag when set. |
| images.traefik.pullPolicy | string | `"IfNotPresent"` | Traefik image pull policy. |
| images.traefik.registry | string | `"docker.io"` | Traefik image registry used for standalone mode and/or bundled Traefik chart overrides. |
| images.traefik.repository | string | `"traefik"` | Traefik image repository. |
| images.traefik.tag | string | `"v3.6.15"` | Traefik image tag. |
| monitoring | object | `{"enabled":false,"metrics":{"addInternals":false,"customLabels":{"service":"pangolin"},"endpoints":{"application":"/app/metrics","health":"/health/metrics","performance":"/perf/metrics"},"path":"/metrics","targetPort":9090,"targetPortName":"metrics"},"podMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"internalApi","relabelings":[],"scheme":"http","scrapeTimeout":"10s"},"prometheusRule":{"additionalLabels":{},"enabled":false,"namespace":"","rules":[]},"service":{"annotations":{"prometheus.io/path":"/metrics","prometheus.io/port":"9090","prometheus.io/scrape":"true"},"enabled":false,"labels":{},"port":9090,"portName":"metrics","type":"ClusterIP"},"serviceMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","selector":{"matchLabels":{"app.kubernetes.io/name":"pangolin"}},"targetLabels":[]}}` | --------------------------------------------------------------------------- # @section Metrics and monitoring |
| monitoring.enabled | bool | `false` | Enable generic chart-level metrics Service / scrape integration for Pangolin app. |
| monitoring.metrics.addInternals | bool | `false` | Expose internal metrics where supported. |
| monitoring.metrics.path | string | `"/metrics"` | Default metrics path. |
| monitoring.metrics.targetPort | int | `9090` | Metrics endpoint numeric port. |
| monitoring.metrics.targetPortName | string | `"metrics"` | Metrics endpoint port name. |
| monitoring.service.enabled | bool | `false` | Create a metrics Service for Pangolin. |
| namespace | object | `{"create":false,"labels":{},"name":"","podSecurity":{"audit":"","enforce":"","warn":""}}` | Namespace configuration for resources created by this chart. When namespace.create=true the chart renders a Namespace resource and applies the Pod Security Admission labels required for Gerbil (NET_ADMIN / WireGuard). If you manage the namespace outside this chart, apply the label manually:   kubectl label ns <namespace> pod-security.kubernetes.io/enforce=privileged --overwrite |
| namespace.labels | object | `{}` | Additional labels applied to the created namespace. |
| namespace.name | string | `""` | Namespace name to create. When empty and create=true, the Helm release namespace (.Release.Namespace) is used. |
| namespace.podSecurity | object | `{"audit":"","enforce":"","warn":""}` | Pod Security Admission labels for the created namespace. Gerbil requires NET_ADMIN (WireGuard). Set enforce: privileged to allow this capability. audit/warn can be set to a stricter level (e.g. baseline) to flag other policy violations. |
| namespace.podSecurity.audit | string | `""` | PSA audit level applied to the namespace. |
| namespace.podSecurity.enforce | string | `""` | PSA enforce level applied to the namespace. Use "privileged" to allow Gerbil's NET_ADMIN capability. |
| namespace.podSecurity.warn | string | `""` | PSA warn level applied to the namespace. |
| networkPolicy | object | `{"allowExternalEgressHttps":false,"allowExternalIngress":true,"controller":{"egress":{"enabled":true,"kubernetesApi":{"cidr":"","enabled":true,"port":443}},"extraEgress":[],"extraIngress":[],"metrics":{"allowExternalIngress":false,"enabled":false,"from":[],"namespaceSelector":{},"podSelector":{}}},"database":{"cnpgPeers":[],"enabled":true,"externalCIDRs":[],"extraEgress":[],"extraIngress":[],"port":5432},"dns":{"enabled":true,"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}],"to":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}}}]},"enabled":true,"extraEgress":[],"extraIngress":[],"gerbil":{"allowWireguardUdpEgress":true,"extraEgress":[],"extraIngress":[],"wireguardUdpCIDRs":["0.0.0.0/0"]},"kubernetesApiCIDRs":[],"pangolin":{"externalIngress":{"external":true,"integration":false,"next":false,"requireIntegrationFlag":true},"extraEgress":[],"extraIngress":[],"ingress":{"dashboard":{"from":[]}}}}` | --------------------------------------------------------------------------- # @section NetworkPolicy |
| networkPolicy.allowExternalEgressHttps | bool | `false` | Allow HTTPS egress (TCP/443) to 0.0.0.0/0. Disabled by default; prefer using `networkPolicy.extraEgress` for a scoped allow-list. |
| networkPolicy.allowExternalIngress | bool | `true` | Allow ingress from everywhere to public entrypoints / services managed by this chart. Component-level controls below can further restrict which ports open externally. |
| networkPolicy.controller.egress.enabled | bool | `true` | Enable explicit controller egress NetworkPolicy. When disabled, no controller egress policy is rendered by this chart even if DNS/Pangolin/Kubernetes API egress rules are configured. |
| networkPolicy.controller.egress.kubernetesApi.cidr | string | `""` | Single CIDR for Kubernetes API server egress target (for example 10.96.0.1/32). Leave empty to skip this rule unless legacy `networkPolicy.kubernetesApiCIDRs` is set. For multiple CIDRs, use the legacy `networkPolicy.kubernetesApiCIDRs` list. |
| networkPolicy.controller.egress.kubernetesApi.enabled | bool | `true` | Enable egress rule to Kubernetes API server. |
| networkPolicy.controller.egress.kubernetesApi.port | int | `443` | Kubernetes API server egress port. |
| networkPolicy.controller.extraEgress | list | `[]` | Additional egress rules appended to the Controller NetworkPolicy only. Use this for controller-specific outbound rules such as metrics or API access. |
| networkPolicy.controller.extraIngress | list | `[]` | Additional ingress rules appended to the Controller NetworkPolicy only. |
| networkPolicy.controller.metrics.allowExternalIngress | bool | `false` | Allow controller metrics ingress from all Pods. |
| networkPolicy.controller.metrics.enabled | bool | `false` | Enable controller metrics ingress rule on controller service port. |
| networkPolicy.controller.metrics.from | list | `[]` | Allowed source peers for controller metrics ingress when enabled. Each item supports standard NetworkPolicyPeer fields (namespaceSelector, podSelector, ipBlock). If empty, legacy `namespaceSelector`/`podSelector` are used when set; otherwise ingress stays denied. |
| networkPolicy.controller.metrics.namespaceSelector | object | `{}` | Optional namespace selector for scoped metrics ingress. |
| networkPolicy.controller.metrics.podSelector | object | `{}` | Optional pod selector for scoped metrics ingress. |
| networkPolicy.database.cnpgPeers | list | `[]` | Optional explicit peers used for CNPG DB egress. If empty, same-namespace egress is used. |
| networkPolicy.database.enabled | bool | `true` | Add DB egress rules for Pangolin workload. |
| networkPolicy.database.externalCIDRs | list | `[]` | Optional CIDRs used for external DB egress. |
| networkPolicy.database.extraEgress | list | `[]` | Additional egress rules appended to the embedded-postgres NetworkPolicy only. |
| networkPolicy.database.extraIngress | list | `[]` | Additional ingress rules appended to the embedded-postgres NetworkPolicy only. |
| networkPolicy.database.port | int | `5432` | Default DB port used when rendering non-embedded DB egress rules. |
| networkPolicy.dns.enabled | bool | `true` | Enable DNS egress rule for all components. Disable only if you manage DNS egress rules yourself. |
| networkPolicy.dns.ports | list | `[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}]` | DNS egress ports. |
| networkPolicy.dns.to | list | `[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}}}]` | DNS egress destination peers. Defaults to the kube-system namespace for standard Kubernetes cluster DNS. Override this if your cluster DNS runs in a different namespace or pod selector. |
| networkPolicy.enabled | bool | `true` | Create NetworkPolicy resources. |
| networkPolicy.extraEgress | list | `[]` | Additional egress rules appended to all generated NetworkPolicies (global escape hatch). Prefer component-scoped `extraEgress` fields (e.g. `networkPolicy.pangolin.extraEgress`) for precision. |
| networkPolicy.extraIngress | list | `[]` | Additional ingress rules appended to all generated NetworkPolicies (global escape hatch). Prefer component-scoped `extraIngress` fields (e.g. `networkPolicy.pangolin.extraIngress`) for precision. |
| networkPolicy.gerbil.allowWireguardUdpEgress | bool | `true` | Allow UDP egress for WireGuard peer traffic. |
| networkPolicy.gerbil.extraEgress | list | `[]` | Additional egress rules appended to the Gerbil NetworkPolicy only. Use this for Gerbil-specific outbound rules. |
| networkPolicy.gerbil.extraIngress | list | `[]` | Additional ingress rules appended to the Gerbil NetworkPolicy only. |
| networkPolicy.gerbil.wireguardUdpCIDRs | list | `["0.0.0.0/0"]` | CIDRs allowed for Gerbil UDP egress when WireGuard egress is enabled. |
| networkPolicy.kubernetesApiCIDRs | list | `[]` | DEPRECATED: CIDRs allowed for controller egress to Kubernetes API on TCP/443. Prefer `networkPolicy.controller.egress.kubernetesApi.cidr`. Keep this scoped to cluster API ranges when known. |
| networkPolicy.pangolin.externalIngress.external | bool | `true` | Allow external ingress on Pangolin public port. |
| networkPolicy.pangolin.externalIngress.integration | bool | `false` | Allow external ingress on Pangolin integration API port. |
| networkPolicy.pangolin.externalIngress.next | bool | `false` | Allow external ingress on Pangolin next port. |
| networkPolicy.pangolin.externalIngress.requireIntegrationFlag | bool | `true` | Require `pangolin.config.flags.enable_integration_api=true` before opening integration ingress. |
| networkPolicy.pangolin.extraEgress | list | `[]` | Additional egress rules appended to the Pangolin NetworkPolicy only. Use this for Pangolin-specific outbound rules such as SMTP or OIDC provider egress. |
| networkPolicy.pangolin.extraIngress | list | `[]` | Additional ingress rules appended to the Pangolin NetworkPolicy only. |
| networkPolicy.pangolin.ingress.dashboard.from | list | `[]` | Optional source peers allowed to reach Pangolin public dashboard/API port. Each item supports standard NetworkPolicyPeer fields (namespaceSelector, podSelector, ipBlock). Applies only when `networkPolicy.pangolin.externalIngress.external=true`. |
| pangolin | object | `{"blueprints":{"configMap":{"create":false,"name":""},"enabled":false,"environment":{},"environmentSecret":{"create":false,"name":""},"existingConfigMap":"","existingEnvironmentSecret":"","files":{}},"commonAnnotations":{},"commonLabels":{},"config":{"app":{"dashboard_url":"https://pangolin.example.com","log_failed_attempts":true,"log_level":"info","notifications":{"new_releases":true,"product_updates":true},"save_logs":false,"telemetry":{"anonymous_usage":true}},"domains":{"domain1":{"base_domain":"example.com","cert_resolver":"letsencrypt"}},"email":{"enabled":false,"no_reply":"","smtp_host":"","smtp_port":587,"smtp_secure":false,"smtp_tls_reject_unauthorized":true,"smtp_user":""},"extraConfig":"","flags":{"allow_raw_resources":true,"disable_basic_wireguard_sites":false,"disable_config_managed_domains":false,"disable_enterprise_features":false,"disable_local_sites":false,"disable_product_help_banners":false,"disable_signup_without_invite":true,"disable_user_create_org":false,"enable_integration_api":false,"require_email_verification":false},"gerbil":{"base_endpoint":"pangolin.example.com","block_size":24,"clients_start_port":21820,"site_block_size":30,"start_port":51820,"subnet_group":"100.89.137.0/20","use_subdomain":false},"orgs":{"block_size":24,"enabled":false,"subnet_group":"100.90.128.0/20","utility_subnet_group":"100.96.128.0/20"},"postgres":{"enabled":false,"pool":{"connection_timeout_ms":5000,"idle_timeout_ms":30000,"max_connections":20,"max_replica_connections":10}},"rate_limits":{"auth":{"max_requests":10,"window_minutes":1},"enabled":true,"global":{"max_requests":500,"window_minutes":1}},"server":{"cors":{"allowed_headers":[],"credentials":false,"methods":[],"origins":[]},"dashboard_session_length_hours":720,"internal_hostname":"pangolin","resource_access_token_headers":{"id":"P-Access-Token-Id","token":"P-Access-Token"},"resource_access_token_param":"p_token","resource_session_length_hours":720,"resource_session_request_param":"p_session_request","session_cookie_name":"p_session_token","trust_proxy":1},"traefik":{"additional_middlewares":[],"cert_resolver":"letsencrypt","enabled":true,"http_entrypoint":"web","https_entrypoint":"websecure","prefer_wildcard_cert":false}},"configFile":{"enabled":true},"configMap":{"annotations":{},"labels":{}},"databaseWait":{"enabled":true,"image":{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"postgres","tag":"17"},"intervalSeconds":5,"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":65534},"stableSeconds":30,"timeoutSeconds":600},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"extraEnv":{},"extraVolumeMounts":[],"extraVolumes":[],"ingressRoute":{"dashboard":{"allowCrossNamespaceServices":false,"annotations":{},"enabled":true,"entryPoints":["websecure"],"host":"","ingressClassName":"","labels":{},"name":"","namespace":"","routes":{"api":{"enabled":true,"middlewares":[],"pathPrefix":"/api/v1","priority":100,"service":{"name":"","namespace":"","port":null}},"dashboard":{"enabled":true,"middlewares":[],"priority":10,"service":{"name":"","namespace":"","port":null}}},"tls":{"certResolver":"","domains":[],"enabled":true,"options":{"name":"","namespace":""},"secretName":"","store":{"name":"","namespace":""}},"traefikSelectorLabels":{}}},"privateConfig":{"enabled":false,"existingSecretKey":"privateConfig.yml","existingSecretName":"","generatedSecret":{"create":false,"data":"","key":"privateConfig.yml","name":""}},"probes":{"liveness":{"failureThreshold":3,"httpGet":{"path":"/api/v1/traefik-config","port":"internal-api"},"initialDelaySeconds":10,"periodSeconds":10,"timeoutSeconds":5},"readiness":{"failureThreshold":3,"httpGet":{"path":"/api/v1/traefik-config","port":"internal-api"},"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":5},"startup":{"failureThreshold":60,"httpGet":{"path":"/api/v1/traefik-config","port":"internal-api"},"initialDelaySeconds":10,"periodSeconds":10,"timeoutSeconds":5}},"replicaCount":1,"resources":{"limits":{"cpu":"1000m","ephemeral-storage":"256Mi","memory":"1Gi"},"requests":{"cpu":"200m","ephemeral-storage":"32Mi","memory":"256Mi"}},"secret":{"existingSecretKey":"SERVER_SECRET","existingSecretName":"","generated":{"create":true,"key":"SERVER_SECRET","length":64,"name":""}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsNonRoot":false},"service":{"annotations":{},"enabled":true,"labels":{},"ports":{"external":3000,"integration":3003,"internalApi":3001,"next":3002},"type":"ClusterIP"},"serviceAccount":{"annotations":{},"labels":{}},"workloadType":"Deployment"}` | --------------------------------------------------------------------------- # @section Pangolin core application |
| pangolin.blueprints | object | `{"configMap":{"create":false,"name":""},"enabled":false,"environment":{},"environmentSecret":{"create":false,"name":""},"existingConfigMap":"","existingEnvironmentSecret":"","files":{}}` | provisioning-blueprint-file. Blueprints are NOT consumed directly by the Pangolin server. Enabling this feature stores blueprint definitions as Kubernetes ConfigMaps/Secrets within this Helm release so they can be managed declaratively alongside the rest of the chart.  Blueprint YAML supports environment variable templating using {{env.VARIABLE_NAME}} syntax. Sensitive templating values (e.g. per-site serial numbers, customer IDs) must be stored in a Secret, not a ConfigMap.  See https://docs.pangolin.net/manage/blueprints for the blueprint schema. |
| pangolin.blueprints.configMap.create | bool | `false` | Create a chart-managed ConfigMap containing blueprint YAML file(s). Each key in `files` becomes a ConfigMap data entry. Mutually exclusive with `existingConfigMap`; setting both will cause validation to fail. |
| pangolin.blueprints.configMap.name | string | `""` | Name override for the generated ConfigMap. Defaults to "<fullname>-blueprints" when empty. |
| pangolin.blueprints.enabled | bool | `false` | Enable chart-managed blueprint resources. When false (default) no Blueprint ConfigMap or Secret is rendered. Set to true and configure configMap or existingConfigMap to manage blueprint YAML files as Kubernetes resources in this release namespace. |
| pangolin.blueprints.environment | object | `{}` | Environment templating key/value pairs rendered into the managed Secret. Keys correspond to {{env.KEY}} placeholders in blueprint YAML. Sensitive values should be supplied through `existingEnvironmentSecret` instead. |
| pangolin.blueprints.environmentSecret.create | bool | `false` | Create a chart-managed Secret for environment templating values. Values here map to {{env.VARIABLE_NAME}} placeholders in blueprint YAML. Sensitive per-site or per-device identifiers belong here, never in a ConfigMap. Mutually exclusive with `existingEnvironmentSecret`; setting both will cause validation to fail. |
| pangolin.blueprints.environmentSecret.name | string | `""` | Name override for the generated Secret. Defaults to "<fullname>-blueprints-env" when empty. |
| pangolin.blueprints.existingConfigMap | string | `""` | Reference an existing ConfigMap that already contains blueprint YAML files. When set, the chart does not create a managed ConfigMap. |
| pangolin.blueprints.existingEnvironmentSecret | string | `""` | Reference an existing Secret containing environment templating values. When set, the chart does not create a managed environmentSecret. |
| pangolin.blueprints.files | object | `{}` | Blueprint YAML file(s) keyed by filename (e.g. `site.yaml`). Each entry is rendered as a data key in the chart-managed ConfigMap. Non-sensitive blueprint definitions belong here. Example:   files:     site.yaml: |       sites:         my-site:           name: My Site           docker-socket-enabled: true |
| pangolin.commonAnnotations | object | `{}` | Annotations added to all Pangolin resources rendered by this chart. |
| pangolin.commonLabels | object | `{}` | Labels added to all Pangolin resources rendered by this chart. |
| pangolin.config | object | `{"app":{"dashboard_url":"https://pangolin.example.com","log_failed_attempts":true,"log_level":"info","notifications":{"new_releases":true,"product_updates":true},"save_logs":false,"telemetry":{"anonymous_usage":true}},"domains":{"domain1":{"base_domain":"example.com","cert_resolver":"letsencrypt"}},"email":{"enabled":false,"no_reply":"","smtp_host":"","smtp_port":587,"smtp_secure":false,"smtp_tls_reject_unauthorized":true,"smtp_user":""},"extraConfig":"","flags":{"allow_raw_resources":true,"disable_basic_wireguard_sites":false,"disable_config_managed_domains":false,"disable_enterprise_features":false,"disable_local_sites":false,"disable_product_help_banners":false,"disable_signup_without_invite":true,"disable_user_create_org":false,"enable_integration_api":false,"require_email_verification":false},"gerbil":{"base_endpoint":"pangolin.example.com","block_size":24,"clients_start_port":21820,"site_block_size":30,"start_port":51820,"subnet_group":"100.89.137.0/20","use_subdomain":false},"orgs":{"block_size":24,"enabled":false,"subnet_group":"100.90.128.0/20","utility_subnet_group":"100.96.128.0/20"},"postgres":{"enabled":false,"pool":{"connection_timeout_ms":5000,"idle_timeout_ms":30000,"max_connections":20,"max_replica_connections":10}},"rate_limits":{"auth":{"max_requests":10,"window_minutes":1},"enabled":true,"global":{"max_requests":500,"window_minutes":1}},"server":{"cors":{"allowed_headers":[],"credentials":false,"methods":[],"origins":[]},"dashboard_session_length_hours":720,"internal_hostname":"pangolin","resource_access_token_headers":{"id":"P-Access-Token-Id","token":"P-Access-Token"},"resource_access_token_param":"p_token","resource_session_length_hours":720,"resource_session_request_param":"p_session_request","session_cookie_name":"p_session_token","trust_proxy":1},"traefik":{"additional_middlewares":[],"cert_resolver":"letsencrypt","enabled":true,"http_entrypoint":"web","https_entrypoint":"websecure","prefer_wildcard_cert":false}}` | Pangolin application config rendered into /app/config/config.yml. Keys and structure follow the Pangolin 1.18.x configSchema (snake_case). |
| pangolin.config.app.dashboard_url | string | `"https://pangolin.example.com"` | Public dashboard URL exposed to end users (required by Pangolin at startup). Set this to your real public dashboard URL for production. |
| pangolin.config.app.log_failed_attempts | bool | `true` | Log failed authentication / access attempts. Enabled by default for audit and attack-detection purposes. Upstream OSS default is false; the chart overrides it to true for a security-hardened baseline. Disable if log volume or storage is a concern. |
| pangolin.config.app.log_level | string | `"info"` | Pangolin application log level. |
| pangolin.config.app.notifications.new_releases | bool | `true` | Receive new release notifications. |
| pangolin.config.app.notifications.product_updates | bool | `true` | Receive product update notifications. |
| pangolin.config.app.save_logs | bool | `false` | Persist application logs to disk. Enabling this writes logs to the container filesystem; ensure ephemeral-storage limits are sized accordingly or mount an external volume for log retention. |
| pangolin.config.app.telemetry.anonymous_usage | bool | `true` | Send anonymous usage telemetry to Fossorial. |
| pangolin.config.domains | object | `{"domain1":{"base_domain":"example.com","cert_resolver":"letsencrypt"}}` | Domain map for Pangolin. Each key is a logical domain name; the value defines the base domain and optional cert settings. The default `example.com` entry is a non-production placeholder and must be replaced with a real domain before deploying to real environments. Example:   my-domain:     base_domain: example.com     cert_resolver: letsencrypt   # optional; falls back to traefik.cert_resolver     prefer_wildcard_cert: false At least one domain is required for non-sqlite installs. |
| pangolin.config.email.enabled | bool | `false` | Include the email section in the rendered config.yml. |
| pangolin.config.email.no_reply | string | `""` | Sender address used for system emails. |
| pangolin.config.email.smtp_host | string | `""` | SMTP server hostname. |
| pangolin.config.email.smtp_port | int | `587` | SMTP server port. |
| pangolin.config.email.smtp_secure | bool | `false` | Use TLS for the SMTP connection. |
| pangolin.config.email.smtp_tls_reject_unauthorized | bool | `true` | Reject unauthorized TLS certificates. |
| pangolin.config.email.smtp_user | string | `""` | SMTP username (or set EMAIL_SMTP_USER env var). |
| pangolin.config.extraConfig | string | `""` | Extra raw YAML appended verbatim at the end of the generated config.yml. |
| pangolin.config.flags.allow_raw_resources | bool | `true` | Allow unmanaged (raw) resource types. Installer parity: the upstream quick installer enables this by default. |
| pangolin.config.flags.disable_basic_wireguard_sites | bool | `false` | Disable plain WireGuard sites (without Newt agent). |
| pangolin.config.flags.disable_config_managed_domains | bool | `false` | Disable config-file managed domains; domains are then managed only via the DB/UI. |
| pangolin.config.flags.disable_enterprise_features | bool | `false` | Disable Enterprise-licensed features even when a valid license is present. |
| pangolin.config.flags.disable_local_sites | bool | `false` | Disable local (same-host) site type. |
| pangolin.config.flags.disable_product_help_banners | bool | `false` | Disable product help banners in the Pangolin UI. |
| pangolin.config.flags.disable_signup_without_invite | bool | `true` | Disable sign-ups that were not invited. Set to true (the chart and upstream quick-install default) to lock down open registration in production. Set to false only during initial onboarding. |
| pangolin.config.flags.disable_user_create_org | bool | `false` | Prevent regular users from creating new organizations. Set to true in production to keep org management in admin hands. Upstream default is false; the chart keeps upstream default for onboarding flexibility. |
| pangolin.config.flags.enable_integration_api | bool | `false` | Enable the Pangolin integration / machine-to-machine API. |
| pangolin.config.flags.require_email_verification | bool | `false` | Require email verification for new sign-ups. Keep false unless you have configured the email section (smtp_host etc.); enabling it without a working SMTP setup will prevent new users from completing registration. |
| pangolin.config.gerbil.base_endpoint | string | `"pangolin.example.com"` | Public endpoint (hostname or IP) where Gerbil is reachable by sites. Set this to your real public endpoint for production. |
| pangolin.config.gerbil.block_size | int | `24` | CIDR prefix length per cluster / site group. |
| pangolin.config.gerbil.clients_start_port | int | `21820` | WireGuard client start port. Keep in sync with gerbil.ports.wg2. |
| pangolin.config.gerbil.site_block_size | int | `30` | CIDR prefix length per individual site. |
| pangolin.config.gerbil.start_port | int | `51820` | WireGuard site start port Gerbil listens on. Keep in sync with gerbil.ports.wg1. |
| pangolin.config.gerbil.subnet_group | string | `"100.89.137.0/20"` | Supernet for WireGuard address allocation. |
| pangolin.config.gerbil.use_subdomain | bool | `false` | Use subdomain-based resource endpoints. |
| pangolin.config.orgs.block_size | int | `24` | CIDR prefix length per organization. |
| pangolin.config.orgs.enabled | bool | `false` | Include the orgs section in the rendered config.yml. |
| pangolin.config.orgs.subnet_group | string | `"100.90.128.0/20"` | Supernet for organization WireGuard address allocation. |
| pangolin.config.orgs.utility_subnet_group | string | `"100.96.128.0/20"` | Supernet for organization utility address allocation. |
| pangolin.config.postgres.enabled | bool | `false` | Include postgres pool settings in the rendered config.yml. |
| pangolin.config.postgres.pool.connection_timeout_ms | int | `5000` | Connection establishment timeout in milliseconds. |
| pangolin.config.postgres.pool.idle_timeout_ms | int | `30000` | Idle connection timeout in milliseconds. |
| pangolin.config.postgres.pool.max_connections | int | `20` | Maximum number of primary PostgreSQL connections in the pool. |
| pangolin.config.postgres.pool.max_replica_connections | int | `10` | Maximum number of read-replica connections in the pool. |
| pangolin.config.rate_limits.auth.max_requests | int | `10` | Maximum auth requests per window per client. Set to 10 to mitigate brute-force login attacks. Upstream default is 500; the chart uses a stricter value for auth endpoints. Adjust upward only if legitimate automation requires more auth requests per window. |
| pangolin.config.rate_limits.auth.window_minutes | int | `1` | Window size in minutes for the authentication rate limit bucket. |
| pangolin.config.rate_limits.enabled | bool | `true` | Include the rate_limits section in the rendered config.yml. Enabled by default for a security-hardened baseline. Upstream does not enable rate limits by default; the chart enables them to protect against brute-force and denial-of-service attacks. |
| pangolin.config.rate_limits.global.max_requests | int | `500` | Maximum requests per window per client for the global bucket. 500 req/min is a permissive ceiling suitable for most API consumers; tighten if you observe abuse patterns. |
| pangolin.config.rate_limits.global.window_minutes | int | `1` | Window size in minutes for the global rate limit bucket. |
| pangolin.config.server.cors.allowed_headers | list | `[]` | Allowed CORS request headers. |
| pangolin.config.server.cors.credentials | bool | `false` | Allow credentials in CORS requests. |
| pangolin.config.server.cors.methods | list | `[]` | Allowed CORS methods. Empty list falls back to Pangolin defaults. |
| pangolin.config.server.cors.origins | list | `[]` | Allowed CORS origins. Empty list disables CORS origin restriction. |
| pangolin.config.server.dashboard_session_length_hours | int | `720` | Dashboard session lifetime in hours. Upstream default is 720 (30 days). For production environments with stricter security requirements, consider reducing to 168 (7 days) or 336 (14 days) to limit session exposure. |
| pangolin.config.server.internal_hostname | string | `"pangolin"` | Internal hostname used by Pangolin when communicating with Gerbil. |
| pangolin.config.server.resource_access_token_headers.id | string | `"P-Access-Token-Id"` | Header name for resource identifier. |
| pangolin.config.server.resource_access_token_headers.token | string | `"P-Access-Token"` | Header name for resource access token. |
| pangolin.config.server.resource_access_token_param | string | `"p_token"` | Request parameter name for resource access tokens. |
| pangolin.config.server.resource_session_length_hours | int | `720` | Resource session lifetime in hours. Upstream default is 720 (30 days). For production environments with stricter security requirements, consider reducing to 168 (7 days) or 336 (14 days) to limit session exposure. |
| pangolin.config.server.resource_session_request_param | string | `"p_session_request"` | Request parameter name for resource session handling. Pangolin docs and the upstream 1.0.0-beta.9 migration use `p_session_request`. |
| pangolin.config.server.session_cookie_name | string | `"p_session_token"` | Session cookie name. |
| pangolin.config.server.trust_proxy | int | `1` | Number of trusted reverse-proxy hops. Use 0 to disable trust-proxy. |
| pangolin.config.traefik.additional_middlewares | list | `[]` | Extra Traefik middleware names applied to all Pangolin routes. |
| pangolin.config.traefik.cert_resolver | string | `"letsencrypt"` | ACME cert resolver name. |
| pangolin.config.traefik.enabled | bool | `true` | Include Pangolin's traefik section in the rendered config.yml. This configures the Traefik output Pangolin generates; it does NOT install Traefik. Entrypoint and cert resolver names must match the real Traefik deployment (external controller, bundled dependency, or standalone Traefik workload). |
| pangolin.config.traefik.http_entrypoint | string | `"web"` | HTTP entrypoint name in Traefik. |
| pangolin.config.traefik.https_entrypoint | string | `"websecure"` | HTTPS entrypoint name in Traefik. |
| pangolin.config.traefik.prefer_wildcard_cert | bool | `false` | Request wildcard certificates instead of per-domain certificates. |
| pangolin.configFile.enabled | bool | `true` | Render and mount /app/config/config.yml for Pangolin. |
| pangolin.configMap.annotations | object | `{}` | Annotations applied to chart-managed Pangolin ConfigMap resources. |
| pangolin.configMap.labels | object | `{}` | Labels applied to chart-managed Pangolin ConfigMap resources. |
| pangolin.databaseWait | object | `{"enabled":true,"image":{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"postgres","tag":"17"},"intervalSeconds":5,"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":65534},"stableSeconds":30,"timeoutSeconds":600}` | Database readiness initContainer configuration. When enabled and database.mode is not sqlite, an initContainer waits for PostgreSQL readiness using the same POSTGRES_CONNECTION_STRING Secret/key as the main Pangolin container, and requires a stable success window. |
| pangolin.databaseWait.enabled | bool | `true` | Enable the database-wait initContainer. Automatically skipped when database.mode=sqlite. |
| pangolin.databaseWait.image | object | `{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"postgres","tag":"17"}` | Image used by the database-wait initContainer. Must provide `pg_isready`. |
| pangolin.databaseWait.intervalSeconds | int | `5` | Interval in seconds between readiness checks. |
| pangolin.databaseWait.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":65534}` | Security context for the database-wait initContainer. |
| pangolin.databaseWait.stableSeconds | int | `30` | Consecutive ready seconds required before Pangolin starts. |
| pangolin.databaseWait.timeoutSeconds | int | `600` | Total time in seconds to wait for the database before giving up. |
| pangolin.deployment.annotations | object | `{}` | Annotations applied to Pangolin Deployment/StatefulSet metadata. |
| pangolin.deployment.labels | object | `{}` | Labels applied to Pangolin Deployment/StatefulSet metadata. |
| pangolin.deployment.podAnnotations | object | `{}` | Annotations applied to Pangolin Pod template metadata. |
| pangolin.deployment.podLabels | object | `{}` | Labels applied to Pangolin Pod template metadata. |
| pangolin.ingressRoute.dashboard.allowCrossNamespaceServices | bool | `false` | Set true to permit cross-namespace Traefik service references in routes.service.namespace. Requires Traefik kubernetesCRD provider allowCrossNamespace settings. |
| pangolin.ingressRoute.dashboard.annotations | object | `{}` | Extra metadata annotations for the dashboard IngressRoute. |
| pangolin.ingressRoute.dashboard.enabled | bool | `true` | Enable chart-managed Traefik IngressRoute for Pangolin dashboard/API in controller mode. |
| pangolin.ingressRoute.dashboard.entryPoints | list | `["websecure"]` | Traefik entrypoints for this IngressRoute. Empty defaults to pangolin.config.traefik.https_entrypoint. |
| pangolin.ingressRoute.dashboard.host | string | `""` | Dashboard host override for Host(...) match. Empty derives host from pangolin.config.app.dashboard_url. |
| pangolin.ingressRoute.dashboard.ingressClassName | string | `""` | Optional ingress class value mapped to metadata annotation kubernetes.io/ingress.class. |
| pangolin.ingressRoute.dashboard.labels | object | `{}` | Extra metadata labels for the dashboard IngressRoute. |
| pangolin.ingressRoute.dashboard.name | string | `""` | Override IngressRoute name. Empty uses "<release>-pangolin-dashboard". |
| pangolin.ingressRoute.dashboard.namespace | string | `""` | Override IngressRoute namespace. Empty uses release namespace. |
| pangolin.ingressRoute.dashboard.routes.api.enabled | bool | `true` | Enable API route. |
| pangolin.ingressRoute.dashboard.routes.api.middlewares | list | `[]` | Optional middleware references for API route (name required, namespace optional). |
| pangolin.ingressRoute.dashboard.routes.api.pathPrefix | string | `"/api/v1"` | PathPrefix for Pangolin API route. |
| pangolin.ingressRoute.dashboard.routes.api.priority | int | `100` | Traefik route priority for API route. |
| pangolin.ingressRoute.dashboard.routes.api.service.name | string | `""` | Backend service name for API route. Empty uses chart fullname. |
| pangolin.ingressRoute.dashboard.routes.api.service.namespace | string | `""` | Backend service namespace for API route. Empty uses release namespace. |
| pangolin.ingressRoute.dashboard.routes.api.service.port | string | `nil` | Backend service port for API route. Empty uses pangolin.service.ports.external. |
| pangolin.ingressRoute.dashboard.routes.dashboard.enabled | bool | `true` | Enable dashboard/UI route. |
| pangolin.ingressRoute.dashboard.routes.dashboard.middlewares | list | `[]` | Optional middleware references for dashboard route (name required, namespace optional). |
| pangolin.ingressRoute.dashboard.routes.dashboard.priority | int | `10` | Traefik route priority for dashboard/UI route. |
| pangolin.ingressRoute.dashboard.routes.dashboard.service.name | string | `""` | Backend service name for dashboard route. Empty uses chart fullname. |
| pangolin.ingressRoute.dashboard.routes.dashboard.service.namespace | string | `""` | Backend service namespace for dashboard route. Empty uses release namespace. |
| pangolin.ingressRoute.dashboard.routes.dashboard.service.port | string | `nil` | Backend service port for dashboard route. Empty uses pangolin.service.ports.next. |
| pangolin.ingressRoute.dashboard.tls.certResolver | string | `""` | Traefik certResolver for ACME mode. Empty falls back to pangolin.config.traefik.cert_resolver. |
| pangolin.ingressRoute.dashboard.tls.domains | list | `[]` | Optional TLS domains list (Traefik IngressRoute tls.domains). |
| pangolin.ingressRoute.dashboard.tls.enabled | bool | `true` | Enable TLS on the dashboard IngressRoute. |
| pangolin.ingressRoute.dashboard.tls.options.name | string | `""` | Optional TLSOption reference name. |
| pangolin.ingressRoute.dashboard.tls.options.namespace | string | `""` | Optional TLSOption reference namespace. |
| pangolin.ingressRoute.dashboard.tls.secretName | string | `""` | Existing TLS Secret name. Mutually exclusive with tls.certResolver. |
| pangolin.ingressRoute.dashboard.tls.store.name | string | `""` | Optional TLSStore reference name. |
| pangolin.ingressRoute.dashboard.tls.store.namespace | string | `""` | Optional TLSStore reference namespace. |
| pangolin.ingressRoute.dashboard.traefikSelectorLabels | object | `{}` | Optional selector labels for multi-Traefik setups (matches provider labelSelector). |
| pangolin.privateConfig.enabled | bool | `false` | Enable mounting a privateConfig.yml for Pangolin Enterprise features. Disabled by default; OSS installations do not require this. |
| pangolin.privateConfig.existingSecretKey | string | `"privateConfig.yml"` | Key inside the existing Secret that holds the privateConfig.yml content. |
| pangolin.privateConfig.existingSecretName | string | `""` | Existing Secret name that contains the privateConfig.yml content. When set, the chart mounts this Secret without creating a new one. |
| pangolin.privateConfig.generatedSecret.create | bool | `false` | Create a chart-managed Secret containing the privateConfig.yml content. |
| pangolin.privateConfig.generatedSecret.data | string | `""` | Raw YAML content for the privateConfig.yml file. |
| pangolin.privateConfig.generatedSecret.key | string | `"privateConfig.yml"` | Key inside the generated Secret. |
| pangolin.privateConfig.generatedSecret.name | string | `""` | Name of the generated Secret. Defaults to "<fullname>-private-config" when empty. |
| pangolin.replicaCount | int | `1` | Number of Pangolin replicas in multi mode. |
| pangolin.secret.annotations | object | `{}` | Annotations applied to chart-managed Pangolin Secret resources. |
| pangolin.secret.existingSecretKey | string | `"SERVER_SECRET"` | Key name inside the existing Secret. |
| pangolin.secret.existingSecretName | string | `""` | Existing Secret containing the Pangolin application secret (SERVER_SECRET). |
| pangolin.secret.generated.create | bool | `true` | Create a chart-managed Secret when no existing Secret is supplied. |
| pangolin.secret.generated.key | string | `"SERVER_SECRET"` | Key name used inside the generated Secret. |
| pangolin.secret.generated.length | int | `64` | Random generated secret length in bytes. |
| pangolin.secret.generated.name | string | `""` | Name of the generated Secret. Defaults to "<fullname>-app" when empty. |
| pangolin.secret.labels | object | `{}` | Labels applied to chart-managed Pangolin Secret resources. |
| pangolin.service.annotations | object | `{}` | Additional Service annotations for Pangolin. |
| pangolin.service.enabled | bool | `true` | Create an internal Service for Pangolin. |
| pangolin.service.labels | object | `{}` | Additional Service labels for Pangolin. |
| pangolin.service.ports | object | `{"external":3000,"integration":3003,"internalApi":3001,"next":3002}` | Service port configuration. |
| pangolin.service.type | string | `"ClusterIP"` | Pangolin Service type. |
| pangolin.serviceAccount.annotations | object | `{}` | Annotations applied to chart-managed Pangolin ServiceAccount metadata. |
| pangolin.serviceAccount.labels | object | `{}` | Labels applied to chart-managed Pangolin ServiceAccount metadata. |
| pangolin.workloadType | string | `"Deployment"` | Workload kind for Pangolin in multi mode. |
| rbac.create | bool | `true` | Create RBAC resources for the pangolin-kube-controller. Only the controller receives Kubernetes API permissions; Pangolin and Gerbil Pods use their own ServiceAccounts without any RBAC bindings. |
| resourcesPolicy | object | `{"cpuLimits":{"enabled":true},"ephemeralStorage":{"enabled":false}}` | Global resource rendering policy controlling which optional resource fields are included. |
| resourcesPolicy.cpuLimits | object | `{"enabled":true}` | Enable CPU limits on all workloads. Set to `false` to omit CPU limits without affecting CPU requests or memory resources. Useful when running VPA or relying on burstable CPU scheduling. |
| resourcesPolicy.ephemeralStorage | object | `{"enabled":false}` | Enable ephemeral-storage requests and limits on all workloads. Disabled by default to avoid unexpected pod scheduling constraints and evictions. Enable only when your cluster enforces ephemeral-storage policies or you want to bound disk usage per container. |
| runtime | object | `{"dependencyWait":{"image":{"pullPolicy":"IfNotPresent","registry":"docker.io","repository":"busybox","tag":"1.36"},"intervalSeconds":5,"stableSeconds":30,"timeoutSeconds":300},"hostNetwork":false,"minReadySeconds":0,"terminationGracePeriodSeconds":30,"updateStrategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}}` | --------------------------------------------------------------------------- # @section Common runtime settings |
| runtime.dependencyWait.image.pullPolicy | string | `"IfNotPresent"` | Pull policy used by dependency wait initContainers unless overridden per component. |
| runtime.dependencyWait.image.registry | string | `"docker.io"` | Registry used by dependency wait initContainers unless overridden per component. |
| runtime.dependencyWait.image.repository | string | `"busybox"` | Repository used by dependency wait initContainers unless overridden per component. |
| runtime.dependencyWait.image.tag | string | `"1.36"` | Tag used by dependency wait initContainers unless overridden per component. |
| runtime.dependencyWait.intervalSeconds | int | `5` | Default interval between dependency wait probes. |
| runtime.dependencyWait.stableSeconds | int | `30` | Required consecutive successful seconds before a dependency is treated as stable. |
| runtime.dependencyWait.timeoutSeconds | int | `300` | Default timeout for dependency wait probes. |
| runtime.hostNetwork | bool | `false` | Enable hostNetwork on workloads that support it. |
| runtime.minReadySeconds | int | `0` | Min ready seconds for Deployments. |
| runtime.terminationGracePeriodSeconds | int | `30` | Grace period in seconds before Pod termination. |
| runtime.updateStrategy | object | `{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}` | Default update strategy for Deployments managed by this chart. |
| serviceAccount | object | `{"controller":{"annotations":{},"automountServiceAccountToken":true,"create":true,"labels":{},"name":""},"gerbil":{"annotations":{},"automountServiceAccountToken":false,"create":true,"labels":{},"name":""},"pangolin":{"annotations":{},"automountServiceAccountToken":false,"create":true,"labels":{},"name":""}}` | Per-component ServiceAccount configuration. In `deployment.mode=multi`, each component uses its own ServiceAccount so RBAC can be scoped precisely. In `deployment.mode=single` with `deployment.type=controller`, the shared Pod uses the controller ServiceAccount (and its token/RBAC), so Pangolin and Gerbil run in the same Pod security context. |
| serviceAccount.controller.annotations | object | `{}` | Extra annotations added to the controller ServiceAccount. |
| serviceAccount.controller.automountServiceAccountToken | bool | `true` | Automount Kubernetes API token into controller Pods. The controller needs in-cluster API access to manage Traefik CRDs; defaults to true. |
| serviceAccount.controller.create | bool | `true` | Create a ServiceAccount for the pangolin-kube-controller Pod. |
| serviceAccount.controller.labels | object | `{}` | Extra labels added to the controller ServiceAccount. |
| serviceAccount.controller.name | string | `""` | Existing ServiceAccount name. When empty and create=true, a name is generated. |
| serviceAccount.gerbil.annotations | object | `{}` | Extra annotations added to the Gerbil ServiceAccount. |
| serviceAccount.gerbil.automountServiceAccountToken | bool | `false` | Automount Kubernetes API token into Gerbil Pods. Gerbil does not need cluster API access; defaults to false. |
| serviceAccount.gerbil.create | bool | `true` | Create a ServiceAccount for Gerbil Pods. |
| serviceAccount.gerbil.labels | object | `{}` | Extra labels added to the Gerbil ServiceAccount. |
| serviceAccount.gerbil.name | string | `""` | Existing ServiceAccount name. When empty and create=true, a name is generated. |
| serviceAccount.pangolin.annotations | object | `{}` | Extra annotations added to the Pangolin ServiceAccount. |
| serviceAccount.pangolin.automountServiceAccountToken | bool | `false` | Automount Kubernetes API token into Pangolin Pods. Pangolin does not need cluster API access; defaults to false. |
| serviceAccount.pangolin.create | bool | `true` | Create a ServiceAccount for Pangolin Pods. |
| serviceAccount.pangolin.labels | object | `{}` | Extra labels added to the Pangolin ServiceAccount. |
| serviceAccount.pangolin.name | string | `""` | Existing ServiceAccount name. When empty and create=true, a name is generated. |
| traefik | object | `{"cloudflare":{"existingSecretName":"","generatedSecret":{"apiToken":"","create":false,"dnsApiToken":"","email":"","name":"","zoneApiToken":""},"keys":{"dnsApiToken":"dnsApiToken","email":"email","zoneApiToken":"zoneApiToken"}},"commonAnnotations":{},"commonLabels":{},"config":{"acmeCaServer":"https://acme-v02.api.letsencrypt.org/directory","acmeDelayBeforeCheck":0,"adminPort":8085,"certResolver":"letsencrypt","dashboard":false,"dashboardDeclareContainerPort":false,"dynamicRouters":{"host":"example.com"},"httpEntrypoint":"web","httpsEntrypoint":"websecure","insecureSkipVerify":false,"letsencryptEmail":"","logLevel":"INFO"},"deployment":{"annotations":{},"labels":{},"podAnnotations":{},"podLabels":{}},"enabled":false,"persistence":{"accessModes":["ReadWriteOnce"],"enabled":false,"existingClaim":"","size":"1Gi","storageClass":""},"probes":{"liveness":{"failureThreshold":3,"httpGet":{"path":"/ping","port":8085},"initialDelaySeconds":10,"periodSeconds":30,"timeoutSeconds":5},"readiness":{"failureThreshold":3,"httpGet":{"path":"/ping","port":8085},"initialDelaySeconds":5,"periodSeconds":10,"timeoutSeconds":3},"startup":{"failureThreshold":20,"httpGet":{"path":"/ping","port":8085},"initialDelaySeconds":5,"periodSeconds":5,"timeoutSeconds":3}},"replicaCount":1,"resources":{"limits":{"cpu":"500m","ephemeral-storage":"128Mi","memory":"512Mi"},"requests":{"cpu":"100m","ephemeral-storage":"16Mi","memory":"128Mi"}},"securityContext":{"allowPrivilegeEscalation":true,"readOnlyRootFilesystem":false,"runAsNonRoot":false},"service":{"annotations":{},"enabled":true,"externalTrafficPolicy":"","labels":{},"loadBalancerSourceRanges":[],"type":"LoadBalancer"}}` | --------------------------------------------------------------------------- # @section Standalone Traefik mode |
| traefik.cloudflare.existingSecretName | string | `""` | Existing Secret name with Cloudflare credentials. |
| traefik.cloudflare.generatedSecret.apiToken | string | `""` | One token reused for both DNS and zone scopes when the app supports it. |
| traefik.cloudflare.generatedSecret.create | bool | `false` | Create a chart-managed Cloudflare Secret. |
| traefik.cloudflare.generatedSecret.dnsApiToken | string | `""` | DNS token override. |
| traefik.cloudflare.generatedSecret.email | string | `""` | Cloudflare email to place into the generated Secret. |
| traefik.cloudflare.generatedSecret.name | string | `""` | Name of the generated Secret. Defaults to "<fullname>-traefik-cloudflare" when empty. |
| traefik.cloudflare.generatedSecret.zoneApiToken | string | `""` | Zone token override. |
| traefik.cloudflare.keys.dnsApiToken | string | `"dnsApiToken"` | Key inside the existing Secret containing DNS API token. |
| traefik.cloudflare.keys.email | string | `"email"` | Key inside the existing Secret containing Cloudflare email. |
| traefik.cloudflare.keys.zoneApiToken | string | `"zoneApiToken"` | Key inside the existing Secret containing zone API token. |
| traefik.commonAnnotations | object | `{}` | Annotations added to all standalone Traefik resources rendered by this chart. |
| traefik.commonLabels | object | `{}` | Labels added to all standalone Traefik resources rendered by this chart. |
| traefik.config.acmeCaServer | string | `"https://acme-v02.api.letsencrypt.org/directory"` | ACME CA directory URL. |
| traefik.config.acmeDelayBeforeCheck | int | `0` | Delay before ACME validation checks. |
| traefik.config.adminPort | int | `8085` | Admin/dashboard/ping port inside the Traefik Pod. |
| traefik.config.certResolver | string | `"letsencrypt"` | ACME resolver name. |
| traefik.config.dashboard | bool | `false` | Enable Traefik dashboard. |
| traefik.config.dashboardDeclareContainerPort | bool | `false` | Expose dashboard port as a declared container port in single mode. |
| traefik.config.dynamicRouters.host | string | `"example.com"` | Example/default host used by generated dynamic router config. |
| traefik.config.httpEntrypoint | string | `"web"` | HTTP entrypoint name. |
| traefik.config.httpsEntrypoint | string | `"websecure"` | HTTPS entrypoint name. |
| traefik.config.insecureSkipVerify | bool | `false` | Skip TLS verification for upstream serversTransport. |
| traefik.config.letsencryptEmail | string | `""` | ACME account email. Required when traefik.enabled=true (the chart fails fast if empty). |
| traefik.config.logLevel | string | `"INFO"` | Traefik log level. |
| traefik.enabled | bool | `false` | Enable built-in Traefik workload. Used mainly when `deployment.type=standalone`. |
| traefik.persistence.enabled | bool | `false` | Persist Traefik ACME state on a PVC. Strongly recommended when using ACME; required when enabling the dashboard (traefik.config.dashboard=true). |
| traefik.replicaCount | int | `1` | Number of standalone Traefik replicas in multi mode. |
| traefik.service.enabled | bool | `true` | Create the public Traefik Service. |
| traefikController | object | `{}` | Values passed to the Traefik dependency chart (only used when `deployment.installTraefikController=true`). |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcschaeferger | <info@marcschaeferger.de> | <https://github.com/marcschaeferger> |
