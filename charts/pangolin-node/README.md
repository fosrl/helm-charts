<!-- markdownlint-disable MD013 -->
<!-- markdownlint-disable MD034 -->
<!-- markdownlint-disable MD056 -->
<!-- markdownlint-disable MD060 -->

# Pangolin Node Helm Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.0](https://img.shields.io/badge/AppVersion-1.7.0-informational?style=flat-square)

Pangolin remote node (Pangolin Node, Gerbil and Traefik) connected to a managed Pangolin control plane

A remote node is a Pangolin exit node that you host while the control plane stays on
Pangolin Cloud (or another managed Pangolin). It has no controller and no database. It is
the same three containers as the `docker-compose` install, run in one Pod:

| Container | Role |
| --- | --- |
| `pangolin-node` | Connects to the control plane with the node ID and secret, writes the Traefik router config to `/var/dynamic` and TLS certificates to `/var/certificates`, and answers Badger and Gerbil on `127.0.0.1:3001`. |
| `gerbil` | WireGuard for sites (51820/udp) and clients (21820/udp), plus the SNI proxy on 8443 that receives public 443 and hands local hostnames to Traefik with PROXY protocol. |
| `traefik` | Reads `/var/dynamic` and `/var/certificates` read-only and routes requests over Gerbil's WireGuard interface, with the Badger plugin for authentication. |

### Why one Pod

- `pangolin-node` and `traefik` share `/var/dynamic` and `/var/certificates`. In one Pod
  these are emptyDirs, so the chart needs no ReadWriteMany storage. `pangolin-node`
  refills both on startup.
- Traefik must sit in Gerbil's network namespace to reach tunnel backends (the compose
  `network_mode: service:gerbil`).
- `pangolin-node` runs as a native sidecar (an init container with
  `restartPolicy: Always`). Gerbil and Traefik start only after its startup probe
  passes, which replaces the compose `depends_on: condition: service_healthy`.

### Differences from the full Pangolin chart

- No database, controller, dashboard or integration API.
- `config.yml` holds only `app`, `server`, `managed`, `traefik` and `gerbil`
  (see `server/lib/readConfigFile.ts` in pangolin-node). The chart sets
  `server.internal_hostname` and `gerbil.reachable_at` to `127.0.0.1` for the
  single-Pod layout.
- Traefik uses the file provider on `/var/dynamic` instead of Pangolin's HTTP provider,
  and certificates come from the control plane instead of ACME.

## Prerequisites

- Kubernetes >= 1.30.14 (native sidecars)
- Helm 3.x
- A remote node ID and secret from the Pangolin dashboard
- A namespace that allows `NET_ADMIN`:

  ```console
  kubectl label ns pangolin pod-security.kubernetes.io/enforce=privileged --overwrite
  ```

- Public reachability for 80/tcp, 443/tcp, 51820/udp and 21820/udp, through a
  LoadBalancer that supports mixed TCP/UDP Services or through `hostPorts`
- Egress to the control plane endpoint and to github.com (Traefik downloads Badger on startup)

## Install

```console
helm repo add fossorial https://charts.fossorial.io
helm repo update fossorial

helm install pangolin-node fossorial/pangolin-node \
  --namespace pangolin --create-namespace \
  --set config.managed.id=<node id> \
  --set config.managed.secret=<node secret> \
  --set config.gerbil.base_endpoint=node.example.com
```

To keep the credentials out of Helm values, create a Secret and point
`config.managed.existingSecret` at it; an init container merges it into `config.yml`:

```console
kubectl -n pangolin create secret generic pangolin-node-credentials \
  --from-literal=id=<node id> --from-literal=secret=<node secret>

helm install pangolin-node fossorial/pangolin-node -n pangolin \
  --set config.managed.existingSecret=pangolin-node-credentials \
  --set config.gerbil.base_endpoint=node.example.com
```

Then point `base_endpoint` and your resource domains at the Service's external address
(or the node IP with `hostPorts.enabled=true`).

## Examples

| File | Use |
| --- | --- |
| [values-loadbalancer.yaml](examples/values-loadbalancer.yaml) | Cloud LoadBalancer with mixed TCP/UDP |
| [values-hostports.yaml](examples/values-hostports.yaml) | Single machine or bare metal, ports bound on the node |
| [values-existing-secret.yaml](examples/values-existing-secret.yaml) | Node ID and secret from an existing Secret |
| [values-full-config-secret.yaml](examples/values-full-config-secret.yaml) | Bring your own `config.yml` |

## Notes

- The Deployment always runs one replica with the `Recreate` strategy. Run another
  release for another node.
- The Gerbil WireGuard key lives on a small PVC (`gerbil.persistence`) that is kept on
  uninstall. Without it Gerbil generates a new key on every restart.
- `config.gerbil.start_port`, `gerbil.ports.wg1` and the public WireGuard port
  (`service.ports.wg1` or `hostPorts.wg1`) must match. The chart refuses to render otherwise.
- Changing `config.managed.existingSecret` contents does not restart the Pod; run
  `kubectl rollout restart` afterwards.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Fossorial Inc | <contact@pangolin.net> |  |

## Source Code

* <https://github.com/fosrl/helm-charts>
* <https://github.com/fosrl/pangolin-node>
* <https://github.com/fosrl/gerbil>

## Requirements

Kubernetes: `>=1.30.14-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonAnnotations | object | `{}` | Annotations added to every resource. |
| commonLabels | object | `{}` | Labels added to every resource. |
| config.app.audit_logging_enabled | bool | `true` | Send request audit logs to the control plane. |
| config.app.log_failed_attempts | bool | `false` | Log failed authentication attempts. |
| config.app.log_level | string | `"info"` | Log level: debug, info, warn or error. |
| config.existingSecret | string | `""` | Use an existing Secret holding a complete config.yml instead of rendering one from the values below. The Secret must contain the key set in `existingSecretKey`. When set, everything under `config.app`, `config.managed`, `config.gerbil` and `config.extra` is ignored. |
| config.existingSecretKey | string | `"config.yml"` | Key inside `existingSecret` holding config.yml. |
| config.extra | object | `{}` | Extra keys deep-merged into the rendered config.yml, for settings this chart does not model. `server.internal_hostname`, `server.internal_port` and `gerbil.reachable_at` are set by the chart for the single-Pod layout. |
| config.gerbil.base_endpoint | string | `""` | Public hostname or IP that sites and clients use to reach this node's WireGuard listener (the address of the Service / node). Required. |
| config.gerbil.start_port | int | `51820` | WireGuard listen port announced to the control plane. Keep it equal to `gerbil.ports.wg1` and the Service port. |
| config.managed.endpoint | string | `"https://app.pangolin.net"` | Control plane URL. |
| config.managed.existingSecret | string | `""` | Read `id` and `secret` from an existing Secret instead. An init container merges them into config.yml at startup, so they never appear in Helm values. |
| config.managed.existingSecretIdKey | string | `"id"` | Key in `managed.existingSecret` holding the node ID. |
| config.managed.existingSecretSecretKey | string | `"secret"` | Key in `managed.existingSecret` holding the node secret. |
| config.managed.id | string | `""` | Remote node ID from the Pangolin dashboard. Required unless `managed.existingSecret` or `config.existingSecret` is set. |
| config.managed.name | string | `""` | Optional display name for the node. |
| config.managed.redirect_endpoint | string | `""` | Optional redirect endpoint. |
| config.managed.secret | string | `""` | Remote node secret from the Pangolin dashboard. Required unless `managed.existingSecret` or `config.existingSecret` is set. |
| extraVolumes | list | `[]` | Extra Pod volumes, referenced from the `extraVolumeMounts` lists above. |
| fullnameOverride | string | `""` | Override the full resource name. |
| gerbil.args | list | `[]` | Replace the default args entirely. |
| gerbil.extraEnv | object | `{}` | Extra environment variables (see gerbil's main.go for the full list). |
| gerbil.extraVolumeMounts | list | `[]` |  |
| gerbil.logLevel | string | `"INFO"` | Gerbil log level. |
| gerbil.persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| gerbil.persistence.annotations | object | `{}` |  |
| gerbil.persistence.enabled | bool | `true` | Persist the WireGuard private key (/var/config/key). Without it Gerbil generates a new key on every restart and re-registers with the control plane. |
| gerbil.persistence.existingClaim | string | `""` |  |
| gerbil.persistence.size | string | `"64Mi"` |  |
| gerbil.persistence.storageClass | string | `""` |  |
| gerbil.ports.internalApi | int | `3003` | Gerbil HTTP API (gerbil.reachable_at). Only reached from inside the Pod. |
| gerbil.ports.sni | int | `8443` | SNI proxy port. Public 443 lands here; Gerbil forwards local SNI matches to Traefik's websecure entrypoint with PROXY protocol. |
| gerbil.ports.wg1 | int | `51820` | WireGuard port for sites. |
| gerbil.ports.wg2 | int | `21820` | WireGuard port for clients. |
| gerbil.resources.limits.memory | string | `"512Mi"` |  |
| gerbil.resources.requests.cpu | string | `"50m"` |  |
| gerbil.resources.requests.memory | string | `"64Mi"` |  |
| gerbil.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"add":["NET_ADMIN"],"drop":["ALL"]}}` | Gerbil needs NET_ADMIN for the WireGuard interface and iptables. Add SYS_MODULE if the node must load the wireguard kernel module itself. |
| hostPorts | object | `{"enabled":false,"http":80,"https":443,"wg1":51820,"wg2":21820}` | Expose the public ports on the node with hostPort, the equivalent of the compose `ports:` block (80, 443, 51820/udp, 21820/udp). Use this on bare-metal or single-node clusters without a LoadBalancer. |
| imagePullSecrets | list | `[]` | Image pull secrets for the Pod. |
| images.configInit | object | `{"digest":"","pullPolicy":"IfNotPresent","registry":"docker.io","repository":"mikefarah/yq","tag":"4.45.4"}` | Image for the init container that merges `managed.existingSecret` into config.yml. Only used when `config.managed.existingSecret` is set. |
| images.gerbil.digest | string | `""` |  |
| images.gerbil.pullPolicy | string | `"IfNotPresent"` |  |
| images.gerbil.registry | string | `"docker.io"` |  |
| images.gerbil.repository | string | `"fosrl/gerbil"` |  |
| images.gerbil.tag | string | `"1.6.0"` |  |
| images.pangolinNode.digest | string | `""` | Overrides `tag` when set. |
| images.pangolinNode.pullPolicy | string | `"IfNotPresent"` |  |
| images.pangolinNode.registry | string | `"docker.io"` |  |
| images.pangolinNode.repository | string | `"fosrl/pangolin-node"` |  |
| images.pangolinNode.tag | string | `""` | Defaults to `.Chart.AppVersion`. |
| images.traefik.digest | string | `""` |  |
| images.traefik.pullPolicy | string | `"IfNotPresent"` |  |
| images.traefik.registry | string | `"docker.io"` |  |
| images.traefik.repository | string | `"traefik"` |  |
| images.traefik.tag | string | `"v3.7.19"` |  |
| nameOverride | string | `""` | Override the chart name. |
| pangolinNode.extraEnv | object | `{}` | Extra environment variables. |
| pangolinNode.extraVolumeMounts | list | `[]` |  |
| pangolinNode.internalPort | int | `3001` | Internal API port (server.internal_port). Badger and Gerbil call it on 127.0.0.1. |
| pangolinNode.livenessProbe.failureThreshold | int | `6` |  |
| pangolinNode.livenessProbe.httpGet.path | string | `"/api/v1/"` |  |
| pangolinNode.livenessProbe.httpGet.port | string | `"internal-api"` |  |
| pangolinNode.livenessProbe.periodSeconds | int | `10` |  |
| pangolinNode.livenessProbe.timeoutSeconds | int | `10` |  |
| pangolinNode.readinessProbe.failureThreshold | int | `3` |  |
| pangolinNode.readinessProbe.httpGet.path | string | `"/api/v1/"` |  |
| pangolinNode.readinessProbe.httpGet.port | string | `"internal-api"` |  |
| pangolinNode.readinessProbe.periodSeconds | int | `10` |  |
| pangolinNode.readinessProbe.timeoutSeconds | int | `10` |  |
| pangolinNode.resources.limits.memory | string | `"512Mi"` |  |
| pangolinNode.resources.requests.cpu | string | `"50m"` |  |
| pangolinNode.resources.requests.memory | string | `"128Mi"` |  |
| pangolinNode.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| pangolinNode.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| pangolinNode.startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/api/v1/","port":"internal-api"},"periodSeconds":5,"timeoutSeconds":5}` | Startup probe. Gerbil and Traefik start only after it passes (the compose `depends_on: condition: service_healthy`). |
| pangolinNode.timezone | string | `""` | Timezone for log timestamps. |
| pod.affinity | object | `{}` |  |
| pod.annotations | object | `{}` | Extra Pod annotations. |
| pod.dnsPolicy | string | `""` | DNS policy. Defaults to ClusterFirstWithHostNet when hostNetwork is true. |
| pod.hostNetwork | bool | `false` | Run the Pod in the host network namespace. Gerbil's SNI proxy then binds 8443 and Traefik binds 8000/9443/8080 directly on the node, so prefer `hostPorts` or a LoadBalancer Service unless you need the node's own IP stack. |
| pod.labels | object | `{}` | Extra Pod labels. |
| pod.nodeSelector | object | `{}` |  |
| pod.priorityClassName | string | `""` |  |
| pod.securityContext | object | `{"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. |
| pod.terminationGracePeriodSeconds | int | `30` |  |
| pod.tolerations | list | `[]` |  |
| pod.topologySpreadConstraints | list | `[]` |  |
| revisionHistoryLimit | int | `10` | Deployment revision history. |
| service.annotations | object | `{}` |  |
| service.enabled | bool | `true` | Create the Service for the public ports. |
| service.externalTrafficPolicy | string | `"Local"` | Use Local to keep client source IPs (Gerbil and Traefik log real IPs). |
| service.labels | object | `{}` |  |
| service.loadBalancerClass | string | `""` |  |
| service.loadBalancerIP | string | `""` |  |
| service.loadBalancerSourceRanges | list | `[]` |  |
| service.nodePorts | object | `{"http":"","https":"","wg1":"","wg2":""}` | Fixed nodePorts when `type` is NodePort or LoadBalancer. Empty lets Kubernetes pick. |
| service.ports.http | int | `80` |  |
| service.ports.https | int | `443` |  |
| service.ports.wg1 | int | `51820` |  |
| service.ports.wg2 | int | `21820` |  |
| service.type | string | `"LoadBalancer"` | ClusterIP, NodePort or LoadBalancer. LoadBalancer needs a provider that supports mixed TCP/UDP ports on one Service; otherwise use `hostPorts`. |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` | Create a ServiceAccount. None of the containers call the Kubernetes API. |
| serviceAccount.name | string | `""` |  |
| sharedVolumes.certificates.mountPath | string | `"/var/certificates"` | Mount path. Must match `traefik.certificates_path` in config.yml. |
| sharedVolumes.certificates.sizeLimit | string | `"128Mi"` | emptyDir size limit. |
| sharedVolumes.dynamic.mountPath | string | `"/var/dynamic"` | Mount path. Must match `traefik.dynamic_*_config_path` in config.yml (defaults to /var/dynamic) and the Traefik file provider directory. |
| sharedVolumes.dynamic.sizeLimit | string | `"64Mi"` | emptyDir size limit. |
| traefik.accessLog | bool | `false` | Enable the access log on stdout. |
| traefik.badger.moduleName | string | `"github.com/fosrl/badger"` | Go module path of the Badger plugin. |
| traefik.badger.version | string | `"v1.8.0"` | Badger version. Traefik downloads it from GitHub at startup. |
| traefik.dashboard | bool | `false` | Serve the Traefik dashboard on the admin port (not exposed by the Service). |
| traefik.extraArgs | list | `[]` |  |
| traefik.extraEnv | object | `{}` |  |
| traefik.extraStaticConfig | object | `{}` | Extra static configuration deep-merged over the generated traefik_config.yml. |
| traefik.extraVolumeMounts | list | `[]` |  |
| traefik.livenessProbe.failureThreshold | int | `3` |  |
| traefik.livenessProbe.httpGet.path | string | `"/ping"` |  |
| traefik.livenessProbe.httpGet.port | string | `"admin"` |  |
| traefik.livenessProbe.periodSeconds | int | `10` |  |
| traefik.livenessProbe.timeoutSeconds | int | `5` |  |
| traefik.logLevel | string | `"INFO"` | Traefik log level. |
| traefik.ports.admin | int | `8080` | Ping/API entrypoint used by the probes. |
| traefik.ports.web | int | `8000` | HTTP entrypoint (`web`). Public 80 lands here. |
| traefik.ports.websecure | int | `9443` | HTTPS entrypoint (`websecure`). Fed by Gerbil's SNI proxy, not exposed directly. Not 8443, which Gerbil binds in the same network namespace. |
| traefik.proxyProtocolTrustedIPs | list | `["127.0.0.1/32","::1/128"]` | Sources trusted to send PROXY protocol to `websecure`. Gerbil connects from inside the Pod; widen this only with hostNetwork. |
| traefik.readinessProbe.failureThreshold | int | `3` |  |
| traefik.readinessProbe.httpGet.path | string | `"/ping"` |  |
| traefik.readinessProbe.httpGet.port | string | `"admin"` |  |
| traefik.readinessProbe.periodSeconds | int | `10` |  |
| traefik.readinessProbe.timeoutSeconds | int | `5` |  |
| traefik.resources.limits.memory | string | `"512Mi"` |  |
| traefik.resources.requests.cpu | string | `"50m"` |  |
| traefik.resources.requests.memory | string | `"64Mi"` |  |
| traefik.securityContext.allowPrivilegeEscalation | bool | `false` |  |
| traefik.securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| traefik.startupProbe.failureThreshold | int | `60` |  |
| traefik.startupProbe.httpGet.path | string | `"/ping"` |  |
| traefik.startupProbe.httpGet.port | string | `"admin"` |  |
| traefik.startupProbe.periodSeconds | int | `5` |  |
| traefik.startupProbe.timeoutSeconds | int | `5` |  |
