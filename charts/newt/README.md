<!-- markdownlint-disable MD013 -->
<!-- markdownlint-disable MD034 -->
<!-- markdownlint-disable MD056 -->
<!-- markdownlint-disable MD060 -->

# Newt Helm Chart

![Version: 1.3.0](https://img.shields.io/badge/Version-1.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.11.0](https://img.shields.io/badge/AppVersion-1.11.0-informational?style=flat-square)

Helm chart to deploy Newt (fosrl/newt) client instance

## ✨ Features

- Env var or CLI flag configuration
- Newt 1.11+ provisioning support (key-based bootstrap)
- First-class writable config persistence for CONFIG_FILE (emptyDir or existing PVC)
- Provisioning blueprint support (single-use)
- Optional mTLS (PKCS12) secret mount
- Optional up/down script injection
- Native WireGuard (privileged) mode (opt-in)
- Health file based probes & helm test Jobs
- RBAC Role/ClusterRole (opt-in)
- NetworkPolicy (opt-in)
- Prometheus metrics, PodMonitor, ServiceMonitor, PrometheusRule (opt-in)
- Optional pprof endpoint enablement (opt-in)
- Multi-instance (array-driven) deployments with per-instance overrides

## Prerequisites

- Kubernetes >= 1.30.14
- Helm 3.x
- kubectl >= v1.30.14
- Newt Credentials from Pangolin

## Quick Start

See [QUICKSTART-NEWT.md](../QUICKSTART-NEWT.md) for detailed instructions.

## Newt 1.11.0 notes (Chart version 1.3.0+)

- This chart targets Newt 1.11.0 by default.
- Upstream ping defaults changed in Newt 1.11.0. If you rely on the older 1.10.1 behavior, set `newtInstances[x].pingInterval` and `newtInstances[x].pingTimeout` explicitly.
- Legacy installs using ID/secret (including `auth.existingSecretName`) still work unchanged.

## Provisioning examples

### Provisioning (emptyDir) + writable config persistence

```yaml
newtInstances:
  - name: main-tunnel
    enabled: true
    pangolinEndpoint: https://pangolin.example.com
    provisioningKey: "YOUR_PROVISIONING_KEY"
    newtName: "my-site"

    # Required for provisioning-based installs so Newt can write credentials
    configPersistence:
      enabled: true
      type: emptyDir
      mountPath: /var/lib/newt
      fileName: config.json
```

### Provisioning (existing PVC) + writable config persistence

```yaml
newtInstances:
  - name: main-tunnel
    enabled: true
    pangolinEndpoint: https://pangolin.example.com
    provisioningKey: "YOUR_PROVISIONING_KEY"
    newtName: "my-site"

    configPersistence:
      enabled: true
      type: persistentVolumeClaim
      existingClaim: my-newt-config
      mountPath: /var/lib/newt
      fileName: config.json
```

### Provisioning blueprint (single-use)

```yaml
newtInstances:
  - name: main-tunnel
    enabled: true
    pangolinEndpoint: https://pangolin.example.com
    provisioningKey: "YOUR_PROVISIONING_KEY"
    newtName: "my-site"

    configPersistence:
      enabled: true
      type: emptyDir

    provisioningBlueprintFile: /etc/newt/provisioning-blueprint.yaml
    provisioningBlueprintData: |
      version: 1
      routes: []
```

### pprof enablement

```yaml
global:
  metrics:
    pprofEnabled: true
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.additionalAnnotations | object | `{}` | Additional annotations applied to all rendered resources. |
| global.additionalLabels | object | `{}` | Additional labels applied to all rendered resources. |
| global.additionalServiceAnnotations | object | `{}` | Additional annotations applied to external Service resources. |
| global.additionalServiceLabels | object | `{}` | Additional labels applied to external Service resources. |
| global.affinity | object | `{"nodeAffinity":{},"podAffinity":{},"podAntiAffinity":{}}` | Pod affinity and anti-affinity |
| global.affinity.nodeAffinity | object | `{}` | Node affinity rules |
| global.affinity.podAffinity | object | `{}` | Pod affinity rules |
| global.affinity.podAntiAffinity | object | `{}` | Pod anti-affinity rules |
| global.deploymentAnnotations | object | `{}` | Additional annotations applied to Deployment resources. |
| global.deploymentLabels | object | `{}` | Additional labels applied to Deployment resources. |
| global.extraEnv | object | `{}` | Extra environment variables injected into all containers (global scope). Map format: KEY: "value" |
| global.fullnameOverride | string | `""` | Fully override the computed fullname. |
| global.health | object | `{"enabled":false,"path":"/tmp/healthy","readinessFailureThreshold":3}` | --------------------------------------------------------------------------- |
| global.health.path | string | `"/tmp/healthy"` | Health file path checked by probes |
| global.health.readinessFailureThreshold | int | `3` | Readiness probe failure threshold |
| global.image | object | `{"digest":"","imagePullPolicy":"IfNotPresent","imagePullSecrets":[],"registry":"docker.io","repository":"fosrl/newt","tag":""}` | Global container image configuration used by all chart components. |
| global.image.digest | string | `""` | Image digest (overrides tag when set). Format: sha256:<64-hex>. |
| global.image.imagePullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| global.image.imagePullSecrets | list | `[]` | Image pull secrets (list of Kubernetes Secret references). Each entry should be an object like: { name: "my-secret" } |
| global.image.registry | string | `"docker.io"` | Container image registry (e.g., docker.io, ghcr.io, registry.example.com). |
| global.image.repository | string | `"fosrl/newt"` | Container image repository (e.g., fosrl/newt). |
| global.image.tag | string | `""` | Image tag (defaults to Chart.appVersion if empty). |
| global.logLevel | string | `"INFO"` | Global log level |
| global.metrics | object | `{"adminAddr":"127.0.0.1:2112","annotations":{},"asyncBytes":false,"enabled":false,"otel":{"exporterOtlpEndpoint":"","exporterOtlpHeaders":"","exporterOtlpProtocol":"","serviceName":""},"otlpEnabled":false,"path":"/metrics","podMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"metrics","relabelings":[],"scheme":"http","scrapeTimeout":"10s"},"port":9090,"portName":"metrics","pprofEnabled":false,"prometheusRule":{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"labels":{},"namespace":"","rules":[]},"region":"","service":{"annotations":{},"enabled":false,"port":9090,"portName":"metrics","type":"ClusterIP"},"serviceMonitor":{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","jobLabel":"","labels":{},"metricRelabelings":[],"namespace":"","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","targetLabels":[]},"targetPortName":""}` | --------------------------------------------------------------------------- @section Global Metrics |
| global.metrics.adminAddr | string | `"127.0.0.1:2112"` | Metrics admin server address (NEWT_ADMIN_ADDR). Used for health checks and metrics endpoint. |
| global.metrics.annotations | object | `{}` | Extra annotations added to metrics-related objects (e.g., Pods/Service depending on chart logic) |
| global.metrics.asyncBytes | bool | `false` | Enable async bytes metrics (NEWT_METRICS_ASYNC_BYTES) |
| global.metrics.enabled | bool | `false` | Enable Prometheus-compatible metrics exposure |
| global.metrics.otel | object | `{"exporterOtlpEndpoint":"","exporterOtlpHeaders":"","exporterOtlpProtocol":"","serviceName":""}` | OTEL exporter configuration (used when otlpEnabled=true) These are passed as environment variables to the container |
| global.metrics.otel.exporterOtlpEndpoint | string | `""` | OTLP endpoint (OTEL_EXPORTER_OTLP_ENDPOINT) |
| global.metrics.otel.exporterOtlpHeaders | string | `""` | OTLP headers (OTEL_EXPORTER_OTLP_HEADERS) - comma-separated key=value pairs |
| global.metrics.otel.exporterOtlpProtocol | string | `""` | OTLP exporter protocol (OTEL_EXPORTER_OTLP_PROTOCOL) - grpc or http/proto |
| global.metrics.otel.serviceName | string | `""` | Service name for OTLP (OTEL_SERVICE_NAME) |
| global.metrics.otlpEnabled | bool | `false` | Enable OTLP exporter (NEWT_METRICS_OTLP_ENABLED) |
| global.metrics.path | string | `"/metrics"` | Metrics HTTP path |
| global.metrics.podMonitor | object | `{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"metrics","relabelings":[],"scheme":"http","scrapeTimeout":"10s"}` | --------------------------------------------------------------------------- |
| global.metrics.podMonitor.annotations | object | `{}` | Extra annotations applied to the PodMonitor |
| global.metrics.podMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | PodMonitor API version (Prometheus Operator) |
| global.metrics.podMonitor.enabled | bool | `false` | Create a PodMonitor resource |
| global.metrics.podMonitor.honorLabels | bool | `true` | Whether to honor labels from the scraped target |
| global.metrics.podMonitor.interval | string | `"30s"` | Scrape interval (Prometheus duration, e.g., 30s, 1m) |
| global.metrics.podMonitor.labels | object | `{}` | Extra labels applied to the PodMonitor |
| global.metrics.podMonitor.metricRelabelings | list | `[]` | Metric relabeling rules (Prometheus Operator schema; treated as opaque objects) |
| global.metrics.podMonitor.namespace | string | `""` | Namespace override for PodMonitor (empty = release namespace) |
| global.metrics.podMonitor.path | string | `"/metrics"` | Metrics path |
| global.metrics.podMonitor.portName | string | `"metrics"` | Scrape port name (must match a named port on the Pod/Service endpoints) |
| global.metrics.podMonitor.relabelings | list | `[]` | Relabeling rules (Prometheus Operator schema; treated as opaque objects) |
| global.metrics.podMonitor.scheme | string | `"http"` | HTTP scheme for scraping |
| global.metrics.podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout (must be <= interval) |
| global.metrics.port | int | `9090` | Metrics endpoint port exposed by the workload container |
| global.metrics.portName | string | `"metrics"` | Optional Service port name (used when creating a Service) |
| global.metrics.pprofEnabled | bool | `false` | Enable pprof endpoints (NEWT_PPROF_ENABLED). Disabled by default. |
| global.metrics.prometheusRule | object | `{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"labels":{},"namespace":"","rules":[]}` | --------------------------------------------------------------------------- |
| global.metrics.prometheusRule.apiVersion | string | `"monitoring.coreos.com/v1"` | PrometheusRule API version (Prometheus Operator) |
| global.metrics.prometheusRule.enabled | bool | `false` | Create a PrometheusRule resource |
| global.metrics.prometheusRule.labels | object | `{}` | Extra labels applied to the PrometheusRule |
| global.metrics.prometheusRule.namespace | string | `""` | Namespace override for PrometheusRule (empty = release namespace) |
| global.metrics.prometheusRule.rules | list | `[]` | Rule groups/rules (templated). Structure is PrometheusRule-compatible; treated as opaque objects. |
| global.metrics.region | string | `""` | Region for metrics/telemetry (NEWT_REGION) |
| global.metrics.service | object | `{"annotations":{},"enabled":false,"port":9090,"portName":"metrics","type":"ClusterIP"}` | --------------------------------------------------------------------------- |
| global.metrics.service.annotations | object | `{}` | Additional Service annotations |
| global.metrics.service.enabled | bool | `false` | Create a dedicated Service for metrics scraping |
| global.metrics.service.port | int | `9090` | Service port exposed for scraping |
| global.metrics.service.portName | string | `"metrics"` | Service port name |
| global.metrics.service.type | string | `"ClusterIP"` | Kubernetes Service type |
| global.metrics.serviceMonitor | object | `{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","jobLabel":"","labels":{},"metricRelabelings":[],"namespace":"","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","targetLabels":[]}` | --------------------------------------------------------------------------- |
| global.metrics.serviceMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | ServiceMonitor API version (Prometheus Operator) |
| global.metrics.serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor resource |
| global.metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval (Prometheus duration, e.g., 30s, 1m) |
| global.metrics.serviceMonitor.jobLabel | string | `""` | Job label override (if your Prometheus setup uses a custom jobLabel) |
| global.metrics.serviceMonitor.labels | object | `{}` | Extra labels applied to the ServiceMonitor |
| global.metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabeling rules (Prometheus Operator schema; treated as opaque objects) |
| global.metrics.serviceMonitor.namespace | string | `""` | Namespace override for ServiceMonitor (empty = release namespace) |
| global.metrics.serviceMonitor.relabelings | list | `[]` | Relabeling rules (Prometheus Operator schema; treated as opaque objects) |
| global.metrics.serviceMonitor.sampleLimit | int | `0` | Sample limit (0 = unlimited) |
| global.metrics.serviceMonitor.scheme | string | `"http"` | HTTP scheme for scraping |
| global.metrics.serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout (Prometheus duration) |
| global.metrics.serviceMonitor.targetLabels | list | `[]` | Labels to transfer from the target Service onto metrics |
| global.metrics.targetPortName | string | `""` | Optional container port name to target instead of numeric port |
| global.nameOverride | string | `""` | Override chart name (replaces .Chart.Name). |
| global.namespaceOverride | string | `""` | Override the namespace for rendered resources (defaults to .Release.Namespace). |
| global.nativeMode.enabled | bool | `false` | Enable native WireGuard interface (requires privileged container) |
| global.networkPolicy | object | `{"components":{"custom":{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]},"defaultApp":{"egress":[],"enabled":true,"ingress":[],"policyTypes":["Ingress","Egress"]},"dns":{"egress":[{"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}],"to":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}]}],"enabled":false},"kubeApi":{"egress":[{"ports":[{"port":6443,"protocol":"TCP"}],"to":[{"ipBlock":{"cidr":"0.0.0.0/0"}},{"ipBlock":{"cidr":"::/0"}}]}],"enabled":false}},"defaultMode":"merge","enabled":false,"ruleSets":{}}` | Instance-level networkPolicy can inherit, merge, or replace these settings. |
| global.networkPolicy.components | object | `{"custom":{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]},"defaultApp":{"egress":[],"enabled":true,"ingress":[],"policyTypes":["Ingress","Egress"]},"dns":{"egress":[{"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}],"to":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}]}],"enabled":false},"kubeApi":{"egress":[{"ports":[{"port":6443,"protocol":"TCP"}],"to":[{"ipBlock":{"cidr":"0.0.0.0/0"}},{"ipBlock":{"cidr":"::/0"}}]}],"enabled":false}}` | --------------------------------------------------------------------------- |
| global.networkPolicy.components.custom | object | `{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]}` | ----------------------------------------------------------------------- |
| global.networkPolicy.components.custom.egress | list | `[]` | Custom egress rules (raw NetworkPolicySpec.egress objects) |
| global.networkPolicy.components.custom.ingress | list | `[]` | Custom ingress rules (raw NetworkPolicySpec.ingress objects) |
| global.networkPolicy.components.defaultApp | object | `{"egress":[],"enabled":true,"ingress":[],"policyTypes":["Ingress","Egress"]}` | ----------------------------------------------------------------------- |
| global.networkPolicy.components.defaultApp.egress | list | `[]` | Raw Kubernetes NetworkPolicySpec.egress rules |
| global.networkPolicy.components.defaultApp.ingress | list | `[]` | Raw Kubernetes NetworkPolicySpec.ingress rules |
| global.networkPolicy.components.defaultApp.policyTypes | list | `["Ingress","Egress"]` | NetworkPolicy policyTypes |
| global.networkPolicy.components.dns | object | `{"egress":[{"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}],"to":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}]}],"enabled":false}` | ----------------------------------------------------------------------- |
| global.networkPolicy.components.dns.egress | list | `[{"ports":[{"port":53,"protocol":"UDP"},{"port":53,"protocol":"TCP"}],"to":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"kube-system"}},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}]}]` | DNS egress rules (raw NetworkPolicySpec.egress objects) |
| global.networkPolicy.components.kubeApi | object | `{"egress":[{"ports":[{"port":6443,"protocol":"TCP"}],"to":[{"ipBlock":{"cidr":"0.0.0.0/0"}},{"ipBlock":{"cidr":"::/0"}}]}],"enabled":false}` | ----------------------------------------------------------------------- |
| global.networkPolicy.components.kubeApi.egress | list | `[{"ports":[{"port":6443,"protocol":"TCP"}],"to":[{"ipBlock":{"cidr":"0.0.0.0/0"}},{"ipBlock":{"cidr":"::/0"}}]}]` | Kubernetes API egress rules |
| global.networkPolicy.defaultMode | string | `"merge"` | newtInstances[].networkPolicy.mode |
| global.networkPolicy.enabled | bool | `false` | newtInstances[].networkPolicy.enabled: true |
| global.networkPolicy.ruleSets | object | `{}` | Optional named rule sets referenced via newtInstances[].networkPolicy.includeRuleSets   Each ruleSet must resemble a NetworkPolicySpec fragment:    policyTypes: ["Ingress","Egress"]    ingress: [...]    egress: [...]   Example:  ruleSets:    allow-internet:      policyTypes: ["Egress"]      egress:        - to:            - ipBlock: { cidr: 0.0.0.0/0 }          ports:            - { port: 80, protocol: TCP }            - { port: 443, protocol: TCP } |
| global.nodeSelector | object | `{}` | Node selector constraints applied to all Pods. |
| global.notes.defaultTraefikTarget | string | `"traefik.kube-system.svc.cluster.local:80"` | Default internal Traefik service target for NOTES output |
| global.podAnnotations | object | `{}` | Additional annotations applied to Pod resources. |
| global.podDisruptionBudget | object | `{"annotations":{},"enabled":false,"labels":{},"maxUnavailable":"","minAvailable":1}` | --------------------------------------------------------------------------- |
| global.podDisruptionBudget.annotations | object | `{}` | Additional annotations |
| global.podDisruptionBudget.labels | object | `{}` | Additional labels |
| global.podDisruptionBudget.maxUnavailable | string | `""` | Maximum unavailable pods (mutually exclusive with minAvailable) |
| global.podDisruptionBudget.minAvailable | int | `1` | Minimum available pods (mutually exclusive with maxUnavailable) |
| global.podLabels | object | `{}` | Additional labels applied to Pod resources. |
| global.podSecurityContext | object | `{}` | Pod-level securityContext override |
| global.priorityClassName | string | `""` | PriorityClass applied to all Pods. |
| global.resources | object | `{"limits":{"cpu":"200m","ephemeral-storage":"256Mi","memory":"256Mi"},"requests":{"cpu":"100m","ephemeral-storage":"128Mi","memory":"128Mi"}}` | --------------------------------------------------------------------------- |
| global.revisionHistoryLimit | int | `3` | Number of old ReplicaSets/ControllerRevisions to retain. |
| global.securityContext | object | `{}` | Container-level securityContext override SECURITY NOTE: By default (when nativeMode is disabled), Newt runs as non-root:   runAsUser: 65534   runAsNonRoot: true   allowPrivilegeEscalation: false   readOnlyRootFilesystem: true   capabilities.drop: ["ALL"]  When nativeMode.enabled=true OR useNativeInterface=true:   runAsUser: 0 (root)   allowPrivilegeEscalation: true   privileged: true   capabilities.add: [NET_ADMIN, SYS_MODULE]  IMPORTANT: Do NOT set capabilities.drop when running as root - this is invalid. |
| global.statefulsetAnnotations | object | `{}` | Additional annotations applied to StatefulSet resources. |
| global.tests | object | `{"enabled":false,"image":{"pullPolicy":"IfNotPresent","repository":"registry.k8s.io/kubectl","tag":"1.30.14"},"resources":{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}}` | --------------------------------------------------------------------------- |
| global.tests.image.repository | string | `"registry.k8s.io/kubectl"` | Container image repository for Helm test jobs. |
| global.tolerations | list | `[]` | Tolerations applied to all Pods. Each item must be a Kubernetes Toleration object: key, operator (Exists|Equal), value, effect (NoSchedule|PreferNoSchedule|NoExecute), tolerationSeconds |
| global.topologySpreadConstraints | list | `[]` | Pod topology spread constraints (applied to all Pods) |
| global.updownScripts | object | `{}` | Map of filename -> script content (mounted when updown.enabled=true) |
| image.digest | string | `""` | Image digest (sha256:...) |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (fallback when global.image.imagePullPolicy not set) |
| image.repository | string | `""` | Container image repository (fallback; prefer global.image) |
| image.tag | string | `""` | Image tag (ignored if digest is set) |
| newtInstances | list | `[{"acceptClients":false,"affinity":{"nodeAffinity":{},"podAffinity":{},"podAntiAffinity":{}},"allowGlobalOverride":false,"auth":{"existingSecretName":"","keys":{"endpointKey":"PANGOLIN_ENDPOINT","idKey":"NEWT_ID","secretKey":"NEWT_SECRET"}},"blueprintData":"","blueprintFile":"","configFile":"","configPersistence":{"enabled":false,"existingClaim":"","fileName":"config.json","mountPath":"/var/lib/newt","type":"emptyDir"},"disableClients":false,"dns":"","dockerSocket":{"enabled":false,"enforceNetworkValidation":false,"path":"/var/run/docker.sock"},"enabled":true,"enforceHcCert":false,"extraContainers":[],"extraEnv":{},"extraVolumeMounts":[],"extraVolumes":[],"generateAndSaveKeyTo":"","healthFile":"/tmp/healthy","hostNetwork":false,"hostPID":false,"id":"","initContainers":[],"interface":"newt","keepInterface":false,"lifecycle":{},"logLevel":"INFO","metrics":{"annotations":{},"enabled":false,"path":"/metrics","podMonitor":{"annotations":{},"apiVersion":"monitoring.coreos.com/v1","enabled":false,"honorLabels":true,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","path":"/metrics","portName":"metrics","relabelings":[],"scheme":"http","scrapeTimeout":"10s"},"port":9090,"portName":"metrics","prometheusRule":{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"labels":{},"namespace":"","rules":[]},"service":{"annotations":{},"enabled":false,"port":9090,"portName":"metrics","type":"ClusterIP"},"serviceMonitor":{"apiVersion":"monitoring.coreos.com/v1","enabled":false,"interval":"30s","jobLabel":"","labels":{},"metricRelabelings":[],"namespace":"","relabelings":[],"sampleLimit":0,"scheme":"http","scrapeTimeout":"10s","targetLabels":[]},"targetPortName":""},"mtls":{"certPath":"/certs/client.p12","enabled":false,"mode":"pkcs12","p12Base64":"","pem":{"caPath":"/certs/ca.crt","clientCertPath":"/certs/client.crt","clientKeyPath":"/certs/client.key","secretName":""},"secretName":""},"mtu":1280,"name":"main-tunnel","networkPolicy":{"components":{"custom":{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]},"defaultApp":{"egress":[],"enabled":false,"ingress":[],"policyTypes":[]},"dns":{"egress":[],"enabled":false},"kubeApi":{"egress":[],"enabled":false}},"enabled":null,"includeRuleSets":[],"mode":"merge","useGlobalComponents":{"custom":true,"defaultApp":true,"dns":false,"kubeApi":false}},"newtName":"","noCloud":false,"nodeSelector":{},"pangolinEndpoint":"","pingInterval":"","pingTimeout":"","podDisruptionBudget":{},"podSecurityContext":{},"port":"","provisioningBlueprintData":"","provisioningBlueprintFile":"","provisioningKey":"","replicas":1,"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","ephemeral-storage":"128Mi","memory":"128Mi"}},"secret":"","securityContext":{},"service":{"annotations":{},"enabled":true,"enabledWhenAcceptClients":true,"externalTrafficPolicy":"","labels":{},"loadBalancerClass":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"nodePorts":{"tester":"","wg":""},"port":51820,"testerPort":51821,"type":"ClusterIP"},"tolerations":[],"topologySpreadConstraints":[],"updown":{"enabled":false,"fileName":"updown.sh","mountPath":"/opt/newt/updown","script":""},"useCommandArgs":false,"useNativeInterface":false}]` | List of Newt instances to deploy. Each instance can optionally override |
| newtInstances[0].acceptClients | bool | `false` | Accept client connections for runtime only (ACCEPT_CLIENTS env). Does NOT create any Service; Service is controlled by newtInstances[x].service.enabled |
| newtInstances[0].affinity | object | `{"nodeAffinity":{},"podAffinity":{},"podAntiAffinity":{}}` | Pod affinity and anti-affinity |
| newtInstances[0].affinity.nodeAffinity | object | `{}` | Node affinity rules |
| newtInstances[0].affinity.podAffinity | object | `{}` | Pod affinity rules |
| newtInstances[0].affinity.podAntiAffinity | object | `{}` | Pod anti-affinity rules |
| newtInstances[0].allowGlobalOverride | bool | `false` | Allow this instance to override global settings (image, logLevel, etc). |
| newtInstances[0].auth.existingSecretName | string | `""` | Name of the existing Secret with endpoint/id/secret keys |
| newtInstances[0].auth.keys | object | `{"endpointKey":"PANGOLIN_ENDPOINT","idKey":"NEWT_ID","secretKey":"NEWT_SECRET"}` | Key mappings used inside the existing Secret |
| newtInstances[0].auth.keys.endpointKey | string | `"PANGOLIN_ENDPOINT"` | Key name for the Pangolin endpoint (default: PANGOLIN_ENDPOINT) |
| newtInstances[0].auth.keys.idKey | string | `"NEWT_ID"` | Key name for the Newt ID (default: NEWT_ID) |
| newtInstances[0].auth.keys.secretKey | string | `"NEWT_SECRET"` | Key name for the Newt secret (default: NEWT_SECRET) |
| newtInstances[0].blueprintData | string | `""` | Blueprint file content (inline). When provided, creates a ConfigMap with this content. Use this for simple inline blueprints, or leave empty to reference an existing ConfigMap. |
| newtInstances[0].blueprintFile | string | `""` | Blueprint file path (BLUEPRINT_FILE env). Path to a Newt blueprint configuration file. |
| newtInstances[0].configFile | string | `""` | Optional config file path for Newt (CONFIG_FILE env) |
| newtInstances[0].configPersistence | object | `{"enabled":false,"existingClaim":"","fileName":"config.json","mountPath":"/var/lib/newt","type":"emptyDir"}` | Writable config persistence (recommended for provisioning-based installs). When enabled, the chart mounts writable storage at mountPath and auto-sets CONFIG_FILE to mountPath/fileName. This does not remove support for the legacy `configFile` value. |
| newtInstances[0].configPersistence.enabled | bool | `false` | Enable writable config persistence. |
| newtInstances[0].configPersistence.existingClaim | string | `""` | Existing PVC name when type=persistentVolumeClaim. |
| newtInstances[0].configPersistence.fileName | string | `"config.json"` | File name inside mountPath for the persisted config. |
| newtInstances[0].configPersistence.mountPath | string | `"/var/lib/newt"` | Directory mount path for config persistence. |
| newtInstances[0].configPersistence.type | string | `"emptyDir"` | Storage type. Use emptyDir for ephemeral persistence or persistentVolumeClaim for durable persistence. |
| newtInstances[0].disableClients | bool | `false` | Disable client connections (DISABLE_CLIENTS env). When enabled, Newt does not accept incoming client connections. |
| newtInstances[0].dns | string | `""` | Optional DNS server address pushed to the client (leave empty to omit) |
| newtInstances[0].dockerSocket.enabled | bool | `false` | Mount the host's Docker socket into the pod |
| newtInstances[0].dockerSocket.enforceNetworkValidation | bool | `false` | Enforce Docker network validation when enabled |
| newtInstances[0].dockerSocket.path | string | `"/var/run/docker.sock"` | Docker socket mount path |
| newtInstances[0].enforceHcCert | bool | `false` | Enforce health check certificate validation (ENFORCE_HC_CERT env). When enabled, health checks must verify TLS certificates. |
| newtInstances[0].extraContainers | list | `[]` | Additional sidecar containers to add to the pod |
| newtInstances[0].extraEnv | object | `{}` | Extra environment variables to inject into the container |
| newtInstances[0].extraVolumeMounts | list | `[]` | Extra volume mounts to add (must be valid Kubernetes VolumeMount objects) |
| newtInstances[0].extraVolumes | list | `[]` | Extra pod volumes to add (must be valid Kubernetes Volume objects) |
| newtInstances[0].generateAndSaveKeyTo | string | `""` | Optional path to save generated private key (GENERATE_AND_SAVE_KEY_TO env) |
| newtInstances[0].healthFile | string | `"/tmp/healthy"` | Health file path used by liveness/readiness probes |
| newtInstances[0].hostNetwork | bool | `false` | Enable host networking (useful with native mode) |
| newtInstances[0].hostPID | bool | `false` | Enable sharing host PID namespace (rarely needed) |
| newtInstances[0].id | string | `""` | Instance ID issued by Pangolin |
| newtInstances[0].initContainers | list | `[]` | Additional init containers to add to the pod |
| newtInstances[0].interface | string | `"newt"` | WireGuard interface name in the pod |
| newtInstances[0].keepInterface | bool | `false` | Keep the interface on shutdown (native mode) |
| newtInstances[0].lifecycle | object | `{}` | Container lifecycle hooks (e.g., preStop for graceful WireGuard shutdown) |
| newtInstances[0].logLevel | string | `"INFO"` | Per-instance log level (falls back to global.logLevel when empty) |
| newtInstances[0].metrics.annotations | object | `{}` | Override or add custom metrics annotations |
| newtInstances[0].metrics.enabled | bool | `false` | Enable Prometheus metrics |
| newtInstances[0].metrics.path | string | `"/metrics"` | Metrics path |
| newtInstances[0].metrics.podMonitor.annotations | object | `{}` | Extra annotations |
| newtInstances[0].metrics.podMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for PodMonitor |
| newtInstances[0].metrics.podMonitor.enabled | bool | `false` | Create PodMonitor (Prometheus Operator) |
| newtInstances[0].metrics.podMonitor.honorLabels | bool | `true` | Honor labels from target |
| newtInstances[0].metrics.podMonitor.interval | string | `"30s"` | Scrape interval |
| newtInstances[0].metrics.podMonitor.labels | object | `{}` | Extra labels |
| newtInstances[0].metrics.podMonitor.metricRelabelings | list | `[]` | Metric relabelings |
| newtInstances[0].metrics.podMonitor.namespace | string | `""` | Optional namespace override |
| newtInstances[0].metrics.podMonitor.path | string | `"/metrics"` | HTTP path |
| newtInstances[0].metrics.podMonitor.portName | string | `"metrics"` | PodMonitor scrape port name |
| newtInstances[0].metrics.podMonitor.relabelings | list | `[]` | Relabelings |
| newtInstances[0].metrics.podMonitor.scheme | string | `"http"` | HTTP scheme |
| newtInstances[0].metrics.podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| newtInstances[0].metrics.port | int | `9090` | Metrics port |
| newtInstances[0].metrics.portName | string | `"metrics"` | Optional Service port name |
| newtInstances[0].metrics.prometheusRule.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for PrometheusRule |
| newtInstances[0].metrics.prometheusRule.enabled | bool | `false` | Create PrometheusRule (Prometheus Operator) |
| newtInstances[0].metrics.prometheusRule.labels | object | `{}` | Extra labels on PrometheusRule |
| newtInstances[0].metrics.prometheusRule.namespace | string | `""` | Optional namespace override |
| newtInstances[0].metrics.prometheusRule.rules | list | `[]` | Array of rule groups/rules (processed as templates) |
| newtInstances[0].metrics.service.annotations | object | `{}` | Service annotations |
| newtInstances[0].metrics.service.enabled | bool | `false` | Create metrics Service for scraping |
| newtInstances[0].metrics.service.port | int | `9090` | Service port |
| newtInstances[0].metrics.service.portName | string | `"metrics"` | Service port name |
| newtInstances[0].metrics.service.type | string | `"ClusterIP"` | Service type |
| newtInstances[0].metrics.serviceMonitor.apiVersion | string | `"monitoring.coreos.com/v1"` | API version for ServiceMonitor |
| newtInstances[0].metrics.serviceMonitor.enabled | bool | `false` | Create ServiceMonitor (Prometheus Operator) |
| newtInstances[0].metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval |
| newtInstances[0].metrics.serviceMonitor.jobLabel | string | `""` | Job label override |
| newtInstances[0].metrics.serviceMonitor.labels | object | `{}` | Extra labels on ServiceMonitor |
| newtInstances[0].metrics.serviceMonitor.metricRelabelings | list | `[]` | Metric relabelings |
| newtInstances[0].metrics.serviceMonitor.namespace | string | `""` | Optional namespace override |
| newtInstances[0].metrics.serviceMonitor.relabelings | list | `[]` | Relabelings |
| newtInstances[0].metrics.serviceMonitor.sampleLimit | int | `0` | Sample limit |
| newtInstances[0].metrics.serviceMonitor.scheme | string | `"http"` | HTTP scheme |
| newtInstances[0].metrics.serviceMonitor.scrapeTimeout | string | `"10s"` | Optional scrape timeout |
| newtInstances[0].metrics.serviceMonitor.targetLabels | list | `[]` | Target labels |
| newtInstances[0].metrics.targetPortName | string | `""` | Optional container port name to target instead of number |
| newtInstances[0].mtls.certPath | string | `"/certs/client.p12"` | In-container path to mount the PKCS12 file |
| newtInstances[0].mtls.enabled | bool | `false` | Enable mTLS client cert mounting |
| newtInstances[0].mtls.mode | string | `"pkcs12"` | mTLS mode: "pkcs12" (legacy) or "pem" (split PEM certificates) |
| newtInstances[0].mtls.p12Base64 | string | `""` | Inline base64 content for client.p12 (not recommended for production) |
| newtInstances[0].mtls.pem | object | `{"caPath":"/certs/ca.crt","clientCertPath":"/certs/client.crt","clientKeyPath":"/certs/client.key","secretName":""}` | Split PEM certificate configuration (used when mode=pem) |
| newtInstances[0].mtls.pem.caPath | string | `"/certs/ca.crt"` | In-container path to mount CA certificate(s) (ca.crt) - comma-separated list |
| newtInstances[0].mtls.pem.clientCertPath | string | `"/certs/client.crt"` | In-container path to mount client certificate (client.crt) |
| newtInstances[0].mtls.pem.clientKeyPath | string | `"/certs/client.key"` | In-container path to mount client key (client.key) |
| newtInstances[0].mtls.pem.secretName | string | `""` | Secret name containing client.crt, client.key, and optionally ca.crt |
| newtInstances[0].mtls.secretName | string | `""` | Secret name containing client.p12 (if empty and p12Base64 provided, a Secret is generated) |
| newtInstances[0].mtu | int | `1280` | WireGuard interface MTU (typical cloud path MTU ~1380). Leave at 1280 unless tuning |
| newtInstances[0].networkPolicy | object | `{"components":{"custom":{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]},"defaultApp":{"egress":[],"enabled":false,"ingress":[],"policyTypes":[]},"dns":{"egress":[],"enabled":false},"kubeApi":{"egress":[],"enabled":false}},"enabled":null,"includeRuleSets":[],"mode":"merge","useGlobalComponents":{"custom":true,"defaultApp":true,"dns":false,"kubeApi":false}}` | NetworkPolicy behavior (inherit/merge/replace) and enable/disable components. |
| newtInstances[0].networkPolicy.components | object | `{"custom":{"egress":[],"enabled":false,"ingress":[],"policyTypes":["Ingress","Egress"]},"defaultApp":{"egress":[],"enabled":false,"ingress":[],"policyTypes":[]},"dns":{"egress":[],"enabled":false},"kubeApi":{"egress":[],"enabled":false}}` | Instance-local components that can be merged in (mode=merge) or used exclusively (mode=replace). |
| newtInstances[0].networkPolicy.enabled | string | `nil` | - true/false: explicitly enable/disable NetworkPolicies for this instance |
| newtInstances[0].networkPolicy.includeRuleSets | list | `[]` | referencing ruleSets even in replace-mode. |
| newtInstances[0].networkPolicy.mode | string | `"merge"` | - replace: use instance components/ruleSets only (global ignored)   Typical examples:  - "merge": global defaultApp + (instance enables dns) + (instance adds custom)  - "replace": instance defines a fully custom policy set, independent of global |
| newtInstances[0].networkPolicy.useGlobalComponents | object | `{"custom":true,"defaultApp":true,"dns":false,"kubeApi":false}` | This allows per-instance toggling of global building blocks. |
| newtInstances[0].networkPolicy.useGlobalComponents.custom | bool | `true` | Include global custom component (if enabled globally). |
| newtInstances[0].networkPolicy.useGlobalComponents.defaultApp | bool | `true` | Include global defaultApp component (if enabled globally). |
| newtInstances[0].networkPolicy.useGlobalComponents.dns | bool | `false` | Include global dns component (if enabled globally). |
| newtInstances[0].networkPolicy.useGlobalComponents.kubeApi | bool | `false` | Include global kubeApi component (if enabled globally). |
| newtInstances[0].newtName | string | `""` | Provisioning site name (NEWT_NAME env). Use newtName to avoid colliding with newtInstances[].name (instance identifier). |
| newtInstances[0].noCloud | bool | `false` | Disable cloud connectivity (NO_CLOUD env). When enabled, Newt operates without connecting to Pangolin cloud. |
| newtInstances[0].nodeSelector | object | `{}` | Node selection constraints |
| newtInstances[0].pangolinEndpoint | string | `""` | Pangolin control-plane endpoint URL (e.g., https://pangolin.example.com) |
| newtInstances[0].pingInterval | string | `""` | Optional ping interval (e.g., "3s"). Leave empty to use default NOTE: Newt 1.11.0 changed upstream default ping timings. If you rely on the legacy 1.10.1 behavior, set pingInterval/pingTimeout explicitly. |
| newtInstances[0].pingTimeout | string | `""` | Optional ping timeout (e.g., "5s"). Leave empty to use default |
| newtInstances[0].podDisruptionBudget | object | `{}` | Pod Disruption Budget override for this instance |
| newtInstances[0].podSecurityContext | object | `{}` | Pod-level securityContext override |
| newtInstances[0].port | string | `""` | WireGuard UDP port (PORT env). Default is 51820. |
| newtInstances[0].provisioningBlueprintData | string | `""` | Provisioning blueprint file content (inline). Required when provisioningBlueprintFile is set. |
| newtInstances[0].provisioningBlueprintFile | string | `""` | Provisioning blueprint file path (PROVISIONING_BLUEPRINT_FILE env). Newt 1.11.0 applies this blueprint once during provisioning. |
| newtInstances[0].provisioningKey | string | `""` | Provisioning key (NEWT_PROVISIONING_KEY env). When set, Newt can bootstrap credentials and persist them to CONFIG_FILE. |
| newtInstances[0].replicas | int | `1` | Number of replicas for this instance (default: 1) |
| newtInstances[0].resources.limits.cpu | string | `"500m"` | CPU limit |
| newtInstances[0].resources.limits.memory | string | `"256Mi"` | Memory limit |
| newtInstances[0].resources.requests.cpu | string | `"100m"` | CPU request |
| newtInstances[0].resources.requests.ephemeral-storage | string | `"128Mi"` | Ephemeral storage request |
| newtInstances[0].resources.requests.memory | string | `"128Mi"` | Memory request |
| newtInstances[0].secret | string | `""` | Instance secret issued by Pangolin (WARNING: Use existingSecretName for production) |
| newtInstances[0].securityContext | object | `{}` | Container-level securityContext override SECURITY NOTE: By default (when nativeMode is disabled), Newt runs as non-root. When nativeMode.enabled=true OR useNativeInterface=true, Newt runs as root with privileges. IMPORTANT: Do NOT set capabilities.drop when running as root - this is invalid. |
| newtInstances[0].service.annotations | object | `{}` | Service annotations |
| newtInstances[0].service.enabled | bool | `true` | Create a Service for this instance |
| newtInstances[0].service.enabledWhenAcceptClients | bool | `true` | Create Service when acceptClients is true (alternative to service.enabled) |
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
| newtInstances[0].service.type | string | `"ClusterIP"` | Service type for this instance |
| newtInstances[0].tolerations | list | `[]` | Pod tolerations |
| newtInstances[0].topologySpreadConstraints | list | `[]` | Pod topology spread constraints |
| newtInstances[0].updown.enabled | bool | `false` | Mount and execute a shared up/down script |
| newtInstances[0].updown.fileName | string | `"updown.sh"` | filename for the single up/down script |
| newtInstances[0].updown.mountPath | string | `"/opt/newt/updown"` | Container mount path for up/down script files |
| newtInstances[0].updown.script | string | `""` | inline script content (prefer updownScripts map) |
| newtInstances[0].useCommandArgs | bool | `false` | Use command/args instead of environment-variable configuration |
| newtInstances[0].useNativeInterface | bool | `false` | Use native WireGuard kernel interface (requires nativeMode.enabled=true and privileged) |
| rbac | object | `{"annotations":{},"clusterRole":false,"create":true,"labels":{}}` | --------------------------------------------------------------------------- |
| rbac.annotations | object | `{}` | Additional annotations applied to RBAC resources. |
| rbac.clusterRole | bool | `false` | Create ClusterRole/ClusterRoleBinding instead of namespaced Role/RoleBinding. |
| rbac.create | bool | `true` | Create RBAC resources (Role/RoleBinding or ClusterRole/ClusterRoleBinding). |
| rbac.labels | object | `{}` | Additional labels applied to RBAC resources. |
| serviceAccount | object | `{"annotations":{},"automountServiceAccountToken":false,"create":true,"name":""}` | --------------------------------------------------------------------------- |
| serviceAccount.annotations | object | `{}` | Additional annotations applied to the ServiceAccount. |
| serviceAccount.automountServiceAccountToken | bool | `false` | Control automounting of the ServiceAccount token on Pods. |
| serviceAccount.create | bool | `true` | Create a dedicated ServiceAccount for this release. |
| serviceAccount.name | string | `""` | ServiceAccount name. If empty and create=true, the chart generates a name. If create=false and empty, the "default" ServiceAccount is used. |

## Service exposure vs. acceptClients

- Service resources are controlled by `newtInstances[x].service.enabled`.
- `acceptClients` only influences runtime behavior (sets `ACCEPT_CLIENTS=true` env or `--accept-clients` flag) and does not create or remove any Service.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| marcschaeferger | <info@marcschaeferger.de> | <https://github.com/marcschaeferger> |
