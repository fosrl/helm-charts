# Newt Helm Chart

![Version: 1.1.1](https://img.shields.io/badge/Version-1.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.5.0](https://img.shields.io/badge/AppVersion-1.5.0-informational?style=flat-square)

Helm chart to deploy Newt (fosrl/newt) client instance

## ✨ Features

- Env var or CLI flag configuration
- Optional mTLS (PKCS12) secret mount
- Optional up/down script injection
- Native WireGuard (privileged) mode (opt-in)
- Health file based probes & helm test Jobs
- RBAC Role/ClusterRole (opt-in)
- NetworkPolicy (opt-in)
- Prometheus metrics, PodMonitor, ServiceMonitor, PrometheusRule (opt-in)
- Multi-instance (array-driven) deployments with per-instance overrides

## Prerequisites

- Kubernetes >= 1.28.15
- Helm 3.x
- kubectl >= v1.28.15
- Newt Credentials from Pangolin

## Quick Start

See [QUICKSTART-NEWT.md](../QUICKSTART-NEWT.md) for detailed instructions.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.additionalAnnotations | object | `{}` | Additional annotations to be added to all resources |
| global.additionalLabels | object | `{}` | Additional labels to be added to all resources |
| global.additionalServiceAnnotations | object | `{}` | Additional annotations to add to all external Service resources |
| global.additionalServiceLabels | object | `{}` | Additional labels to add to all external Service resources |
| global.affinity | object | `{}` | affinity rules for all components |
| global.deploymentAnnotations | object | `{}` | Annotations to add to all Deployment resources |
| global.deploymentLabels | object | `{}` | Labels to add to all Deployment resources |
| global.extraEnv | object | `{}` | Extra environment variables to add to all containers (global scope) |
| global.fullnameOverride | string | `""` | String to fully override "RELEASE-NAME.fullname" |
| global.health.enabled | bool | `true` | Enable liveness/readiness probes (file existence) |
| global.health.path | string | `"/tmp/healthy"` | Default health file path (instances can override with healthFile) |
| global.health.readinessFailureThreshold | int | `3` | Readiness probe failure threshold |
| global.image | object | `{"digest":"","imagePullPolicy":"IfNotPresent","imagePullSecrets":[],"registry":"docker.io","repository":"fosrl/newt","tag":""}` | Global Docker image settings for all components in the Helm chart   |
| global.image.digest | string | `""` | Optional image digest (overrides tag) |
| global.image.imagePullPolicy | string | `"IfNotPresent"` | Global Docker image pull policy |
| global.image.imagePullSecrets | list | `[]` | Global Docker registry secret |
| global.image.registry | string | `"docker.io"` | Global Docker image registry |
| global.image.repository | string | `"fosrl/newt"` | Global Docker image repository |
| global.image.tag | string | `""` | Global Docker image tag (defaults to chart appVersion if not set) |
| global.logLevel | string | `"INFO"` | Global log level setting |
| global.metrics.annotations | object | `{}` | Override or add custom metrics annotations |
| global.metrics.enabled | bool | `false` | Enable Prometheus metrics |
| global.metrics.path | string | `"/metrics"` | Metrics path |
| global.metrics.podMonitor.annotations | object | `{}` | Extra annotations |
| global.metrics.podMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for PodMonitor |
| global.metrics.podMonitor.enabled | bool | `false` | Create PodMonitor (Prometheus Operator) |
| global.metrics.podMonitor.honorLabels | bool | `true` | Honor labels from target |
| global.metrics.podMonitor.interval | string | `"30s"` | Scrape interval |
| global.metrics.podMonitor.labels | object | `{}` | Extra labels |
| global.metrics.podMonitor.metricRelabelings | list | `[]` | Metric relabelings |
| global.metrics.podMonitor.namespace | string | `""` | Optional namespace override |
| global.metrics.podMonitor.path | string | `"/metrics"` | HTTP path |
| global.metrics.podMonitor.portName | string | `"metrics"` | PodMonitor scrape port name |
| global.metrics.podMonitor.relabelings | list | `[]` | Relabelings |
| global.metrics.podMonitor.scheme | string | `"http"` | HTTP scheme |
| global.metrics.podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| global.metrics.port | int | `9090` | Metrics port |
| global.metrics.portName | string | `"metrics"` | Optional Service port name |
| global.metrics.prometheusRule.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for PrometheusRule |
| global.metrics.prometheusRule.enabled | bool | `false` | Create PrometheusRule (Prometheus Operator) |
| global.metrics.prometheusRule.labels | object | `{}` | Extra labels on PrometheusRule |
| global.metrics.prometheusRule.namespace | string | `""` | Optional namespace override |
| global.metrics.prometheusRule.rules | list | `[]` | Array of rule groups/rules (processed as templates) |
| global.metrics.service.annotations | object | `{}` | Service annotations |
| global.metrics.service.enabled | bool | `false` | Create metrics Service for scraping |
| global.metrics.service.port | int | `9090` | Service port |
| global.metrics.service.portName | string | `"metrics"` | Service port name |
| global.metrics.service.type | string | `"ClusterIP"` | Service type |
| global.metrics.serviceMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for ServiceMonitor |
| global.metrics.serviceMonitor.enabled | bool | `false` | Create ServiceMonitor (Prometheus Operator) |
| global.metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval |
| global.metrics.serviceMonitor.jobLabel | string | `""` | Job label override |
| global.metrics.serviceMonitor.labels | object | `{}` | Extra labels on ServiceMonitor |
| global.metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabelings |
| global.metrics.serviceMonitor.namespace | string | `""` | Optional namespace override |
| global.metrics.serviceMonitor.relabelings | list | `[]` | Relabelings |
| global.metrics.serviceMonitor.sampleLimit | int | `0` | Sample limit |
| global.metrics.serviceMonitor.scheme | string | `"http"` | HTTP scheme |
| global.metrics.serviceMonitor.scrapeTimeout | string | `"10s"` | Optional scrape timeout |
| global.metrics.serviceMonitor.targetLabels | list | `[]` | Target labels |
| global.metrics.targetPortName | string | `""` | Optional container port name to target instead of number |
| global.nameOverride | string | `""` | Override the name of the chart (replaces `.Chart.Name`) |
| global.namespaceOverride | string | `""` | Override the namespace of resources. Defaults to `.Release.Namespace` |
| global.nativeMode.enabled | bool | `false` | Master switch to allow native WireGuard interface usage (privileged) |
| global.networkPolicy | object | `{"create":true,"defaultDenyIngress":false}` | Global NetworkPolicy settings applied by this chart. |
| global.networkPolicy.create | bool | `true` | Enable creation of NetworkPolicy resources for all components |
| global.networkPolicy.defaultDenyIngress | bool | `false` | Default deny all ingress traffic when network policies are enabled |
| global.nodeSelector | object | `{}` | Node selector applied to all pods |
| global.notes.defaultTraefikTarget | string | `"traefik.kube-system.svc.cluster.local:80"` | Default internal Traefik target used in NOTES output |
| global.podAnnotations | object | `{}` | Annotations to add to all Pod resources |
| global.podDisruptionBudget | object | `{"annotations":{},"enabled":false,"labels":{},"maxUnavailable":"","minAvailable":1}` | PodDisruptionBudget for production deployments (optional, disabled by default) |
| global.podDisruptionBudget.annotations | object | `{}` | Additional annotations for PodDisruptionBudget |
| global.podDisruptionBudget.labels | object | `{}` | Additional labels for PodDisruptionBudget |
| global.podDisruptionBudget.maxUnavailable | string | `""` | Maximum unavailable pods during disruptions (cannot be used with minAvailable) |
| global.podDisruptionBudget.minAvailable | int | `1` | Minimum available pods during disruptions (cannot be used with maxUnavailable) |
| global.podLabels | object | `{}` | Labels to add to all Pod resources |
| global.podSecurityContext | object | `{}` | Pod-level securityContext override |
| global.priorityClassName | string | `""` | Priority class name applied to all pods |
| global.resources.limits.cpu | string | `"200m"` | CPU limit |
| global.resources.limits.ephemeral-storage | string | `"256Mi"` | Ephemeral storage limit |
| global.resources.limits.memory | string | `"256Mi"` | Memory limit |
| global.resources.requests.cpu | string | `"100m"` | CPU request |
| global.resources.requests.ephemeral-storage | string | `"128Mi"` | Ephemeral storage request |
| global.resources.requests.memory | string | `"128Mi"` | Memory request |
| global.revisionHistoryLimit | int | `3` | Revision history limit for deployments/statefulsets |
| global.securityContext | object | `{}` | Container-level securityContext override |
| global.statefulsetAnnotations | object | `{}` | Annotations to add to all StatefulSet resources |
| global.tests.enabled | bool | `false` | Helm test pod configuration |
| global.tests.image.pullPolicy | string | `"IfNotPresent"` | Test image pull policy |
| global.tests.image.repository | string | `"bitnami/kubectl"` | Test image repository |
| global.tests.image.tag | string | `"1.28.15"` | Test image tag |
| global.tolerations | list | `[]` | Tolerations applied to all pods |
| global.updownScripts | object | `{}` | Map of script filename to content for up/down scripts mounted when updown.enabled=true |
| image.digest | string | `""` | Image digest (sha256:...) |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (fallback when global.image.imagePullPolicy not set) |
| image.repository | string | `""` | Container image repository (fallback; prefer global.image) |
| image.tag | string | `""` | Image tag (ignored if digest is set) |
| newtInstances[0].acceptClients | bool | `false` | Accept client connections for runtime only (ACCEPT_CLIENTS env). Does NOT create any Service; Service is controlled by newtInstances[x].service.enabled |
| newtInstances[0].affinity | object | `{}` | Pod affinity and anti-affinity |
| newtInstances[0].allowGlobalOverride | bool | `false` | Allow this instance to override global settings (image, logLevel, etc) |
| newtInstances[0].auth.existingSecretName | string | `""` | Name of the existing Secret with endpoint/id/secret keys |
| newtInstances[0].auth.keys | object | `{"endpointKey":"PANGOLIN_ENDPOINT","idKey":"NEWT_ID","secretKey":"NEWT_SECRET"}` | Key mappings used inside the existing Secret |
| newtInstances[0].auth.keys.endpointKey | string | `"PANGOLIN_ENDPOINT"` | Key name for the Pangolin endpoint (default: PANGOLIN_ENDPOINT) |
| newtInstances[0].auth.keys.idKey | string | `"NEWT_ID"` | Key name for the Newt ID (default: NEWT_ID) |
| newtInstances[0].auth.keys.secretKey | string | `"NEWT_SECRET"` | Key name for the Newt secret (default: NEWT_SECRET) |
| newtInstances[0].configFile | string | `""` | Optional config file path for Newt (CONFIG_FILE env) |
| newtInstances[0].dns | string | `""` | Optional DNS server address pushed to the client (leave empty to omit) |
| newtInstances[0].dockerSocket.enabled | bool | `false` | Mount the host's Docker socket into the pod |
| newtInstances[0].dockerSocket.enforceNetworkValidation | bool | `false` | Enforce Docker network validation when enabled |
| newtInstances[0].dockerSocket.path | string | `"/var/run/docker.sock"` | Docker socket mount path |
| newtInstances[0].extraContainers | list | `[]` | Additional sidecar containers to add to the pod |
| newtInstances[0].extraEnv | object | `{}` | Extra environment variables to inject into the container |
| newtInstances[0].extraVolumeMounts | list | `[]` | Extra volume mounts to add to the container |
| newtInstances[0].extraVolumes | list | `[]` | Extra pod volumes to add |
| newtInstances[0].generateAndSaveKeyTo | string | `""` | Optional path to save generated private key (GENERATE_AND_SAVE_KEY_TO env) |
| newtInstances[0].healthFile | string | `"/tmp/healthy"` | Health file path used by liveness/readiness probes |
| newtInstances[0].hostNetwork | bool | `false` | Enable host networking (useful with native mode) |
| newtInstances[0].hostPID | bool | `false` | Enable sharing host PID namespace (rarely needed) |
| newtInstances[0].id | string | `""` | Instance ID issued by Pangolin |
| newtInstances[0].initContainers | list | `[]` | Additional init containers to add to the pod |
| newtInstances[0].interface | string | `"newt"` | WireGuard interface name in the pod |
| newtInstances[0].keepInterface | bool | `false` | Keep the interface on shutdown (native mode) |
| newtInstances[0].logLevel | string | `"INFO"` | Per-instance log level (falls back to global.logLevel when empty) |
| newtInstances[0].mtls.certPath | string | `"/certs/client.p12"` | In-container path to mount the PKCS12 file |
| newtInstances[0].mtls.enabled | bool | `false` | Enable mTLS client cert mounting (PKCS12) |
| newtInstances[0].mtls.p12Base64 | string | `""` | Inline base64 content for client.p12 (not recommended for production) |
| newtInstances[0].mtls.secretName | string | `""` | Secret name containing client.p12 (if empty and p12Base64 provided, a Secret is generated) |
| newtInstances[0].mtu | int | `1280` | WireGuard interface MTU (typical cloud path MTU ~1380). Leave at 1280 unless tuning |
| newtInstances[0].name | string | `"main-tunnel"` |  |
| newtInstances[0].nodeSelector | object | `{}` | Node selection constraints |
| newtInstances[0].pangolinEndpoint | string | `"https://pangolin.example.com"` | Pangolin control-plane endpoint URL (e.g., <https://pangolin.example.com>) |
| newtInstances[0].pingInterval | string | `""` | Optional ping interval (e.g., "3s"). Leave empty to use default |
| newtInstances[0].pingTimeout | string | `""` | Optional ping timeout (e.g., "5s"). Leave empty to use default |
| newtInstances[0].podSecurityContext | object | `{}` | Pod-level securityContext override |
| newtInstances[0].resources.limits.cpu | string | `"500m"` | CPU limit |
| newtInstances[0].resources.limits.memory | string | `"256Mi"` | Memory limit |
| newtInstances[0].resources.requests.cpu | string | `"100m"` | CPU request |
| newtInstances[0].resources.requests.ephemeral-storage | string | `"128Mi"` | Ephemeral storage request |
| newtInstances[0].resources.requests.memory | string | `"128Mi"` | Memory request |
| newtInstances[0].secret | string | `""` | Instance secret issued by Pangolin |
| newtInstances[0].securityContext | object | `{}` | Container-level securityContext override |
| newtInstances[0].service.annotations | object | `{}` | Service annotations |
| newtInstances[0].service.enabled | bool | `true` | Create a Service for this instance |
| newtInstances[0].service.externalTrafficPolicy | string | `""` | External traffic policy (Cluster or Local). Empty = omit field |
| newtInstances[0].service.labels | object | `{}` | Additional service labels |
| newtInstances[0].service.loadBalancerClass | string | `""` | loadBalancerClass (when type=LoadBalancer). Empty = omit field |
| newtInstances[0].service.loadBalancerIP | string | `""` | Static loadBalancerIP (when type=LoadBalancer). Empty = omit field |
| newtInstances[0].service.loadBalancerSourceRanges | list | `[]` | Source ranges to allow (when type=LoadBalancer). Empty = omit field |
| newtInstances[0].service.nodePorts | object | `{"tester":"","wg":""}` | NodePorts for NodePort type (optional, set only to fix ports) |
| newtInstances[0].service.nodePorts.tester | string | `""` | NodePort to expose tester UDP (leave empty to let K8s assign one) |
| newtInstances[0].service.nodePorts.wg | string | `""` | NodePort to expose WireGuard UDP (leave empty to let K8s assign one) |
| newtInstances[0].service.port | int | `51820` | WireGuard UDP service port |
| newtInstances[0].service.testerPort | int | `51821` | Tester/diagnostic UDP service port |
| newtInstances[0].service.type | string | `"LoadBalancer"` | Service type for this instance |
| newtInstances[0].tolerations | list | `[]` | Pod tolerations |
| newtInstances[0].updown.enabled | bool | `false` | Mount and execute a shared up/down script |
| newtInstances[0].updown.fileName | Deprecated | `"updown.sh"` | filename for the single up/down script |
| newtInstances[0].updown.mountPath | string | `"/opt/newt/updown"` | Container mount path for up/down script files |
| newtInstances[0].updown.script | Deprecated | `""` | inline script content (prefer updownScripts map) |
| newtInstances[0].useCommandArgs | bool | `false` | Use command/args instead of environment-variable configuration |
| newtInstances[0].useNativeInterface | bool | `false` | Use native WireGuard kernel interface (requires nativeMode.enabled=true and privileged) |
| rbac.annotations | object | `{}` | RBAC resource annotations |
| rbac.clusterRole | bool | `false` | Create ClusterRole/Binding instead of namespaced Role/Binding |
| rbac.create | bool | `false` | Create RBAC resources (Role/RoleBinding or ClusterRole/ClusterRoleBinding) |
| rbac.labels | object | `{}` | RBAC resource labels |
| serviceAccount | object | `{"annotations":{},"automountServiceAccountToken":false,"create":false,"name":""}` | ServiceAccount settings |
| serviceAccount.annotations | object | `{}` | Additional annotations for the ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Control automounting of the ServiceAccount token on pods |
| serviceAccount.create | bool | `false` | Create a dedicated ServiceAccount |
| serviceAccount.name | string | `""` | ServiceAccount name (empty = auto-generated when create=true, else default) |

## Service exposure vs. acceptClients

- Service resources are controlled by `newtInstances[x].service.enabled`.
- `acceptClients` only influences runtime behavior (sets `ACCEPT_CLIENTS=true` env or `--accept-clients` flag) and does not create or remove any Service.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcschaeferger | <info@marcschaeferger.de> | <https://github.com/marcschaeferger> |
