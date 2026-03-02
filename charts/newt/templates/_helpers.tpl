{{- define "newt.chart" -}}
{{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "newt.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "newt.fullname" -}}
{{- if .Values.global.fullnameOverride }}{{ .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" }}{{ else }}{{ printf "%s-%s" .Release.Name (include "newt.name" .) | trunc 63 | trimSuffix "-" }}{{ end -}}
{{- end }}

{{- define "newt.namespace" -}}
{{- default .Release.Namespace .Values.global.namespaceOverride -}}
{{- end }}

{{- define "newt.serviceAccountName" -}}
{{- /* Prefer explicit name when provided; guard against missing .Values.serviceAccount */ -}}
{{- $hasSA := hasKey .Values "serviceAccount" -}}
{{- if and $hasSA .Values.serviceAccount.name -}}
  {{- print .Values.serviceAccount.name -}}
{{- else -}}
  {{- /* If the chart is not creating a ServiceAccount, fall back to 'default' */ -}}
  {{- if not $hasSA -}}
    {{- print "default" -}}
  {{- else if eq (index .Values.serviceAccount "create") false -}}
    {{- print "default" -}}
  {{- else -}}
    {{- /* Build fullname + -sa and truncate to 63 chars; strip trailing '-' to satisfy DNS label limits */ -}}
    {{- printf "%s-sa" (include "newt.fullname" .) | trunc 63 | trimSuffix "-" -}}
  {{- end -}}
{{- end -}}{{- end }}

{{- define "newt.labels" -}}
app.kubernetes.io/name: {{ include "newt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "newt.chart" . }}
{{- range $k,$v := .Values.global.additionalLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}

{{- define "newt.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: newt
{{- end }}

{{- define "newt.instance.selectorLabels" -}}
app.kubernetes.io/instance: {{ $.Release.Name }}
app.kubernetes.io/component: newt
newt.instance: {{ .name }}
{{- end }}

{{- define "newt.instance.fullname" -}}
{{ printf "%s-%s" (include "newt.fullname" .root) .inst.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- /* Resolve image using global.image with fallback to .Values.image */}}
{{- define "newt.image" -}}
{{- $g := .Values.global.image -}}
{{- $l := .Values.image -}}
{{- $registry := default "" $g.registry -}}
{{- $baseRepo := default (default "" $l.repository) $g.repository -}}
{{- /* If a registry is specified but no repository is provided, fail fast to avoid invalid image like ":v1.0.0" */ -}}
{{- if and $registry (eq (trim $baseRepo) "") -}}
{{- fail "newt.image: global.image.registry is set but neither .Values.image.repository nor .Values.global.image.repository is specified" -}}
{{- end -}}
{{- $repo := $baseRepo -}}
{{- $digest := default (default "" $l.digest) $g.digest -}}
{{- $tag := default (default .Chart.AppVersion $l.tag) $g.tag -}}
{{- if and $registry $repo }}{{- $repo = printf "%s/%s" $registry $repo -}}{{- end -}}
{{- if $digest -}}
{{- if $repo }}{{ printf "%s@%s" $repo $digest }}{{ end }}
{{- else -}}
{{- if $repo }}{{ printf "%s:%s" $repo $tag }}{{ end }}
{{- end -}}
{{- end }}

{{- /* Resolve imagePullPolicy from global.image.imagePullPolicy with fallback */}}
{{- define "newt.imagePullPolicy" -}}
{{- default (default "IfNotPresent" .Values.image.pullPolicy) .Values.global.image.imagePullPolicy -}}
{{- end }}

{{- /* Resolve imagePullSecrets: prefer global.image.imagePullSecrets, then top-level .Values.imagePullSecrets, then .Values.global.imagePullSecrets */}}
{{- define "newt.imagePullSecrets" -}}
{{- /* Avoid direct deref of possibly-missing keys to keep linters/Intellisense happy */ -}}
{{- $vals := .Values | default dict -}}
{{- $global := $vals.global | default dict -}}
{{- $gImage := $global.image | default dict -}}
{{- $secrets := coalesce $gImage.imagePullSecrets $vals.imagePullSecrets $global.imagePullSecrets -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $s := $secrets }}
  - name: {{ $s.name | default $s | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- define "newt.instance.env" -}}
{{- $root := .root -}}
{{- $inst := .inst -}}
{{- $healthFile := default $root.Values.global.health.path $inst.healthFile -}}
{{- $canOverride := (default false $inst.allowGlobalOverride) -}}
{{- $svcAccept := ternary "true" "false" (default false $inst.acceptClients) -}}
{{- $nativeEnabled := and $inst.useNativeInterface $root.Values.global.nativeMode.enabled -}}
{{- $auth := default (dict) $inst.auth -}}
{{- $keys := (default dict (get $auth "keys")) -}}
{{- $endpointKey := (default "PANGOLIN_ENDPOINT" $keys.endpointKey) -}}
{{- $idKey := (default "NEWT_ID" $keys.idKey) -}}
{{- $secretKey := (default "NEWT_SECRET" $keys.secretKey) -}}
{{- $existing := get $auth "existingSecretName" -}}
{{- if $existing }}
- name: PANGOLIN_ENDPOINT
  valueFrom:
    secretKeyRef:
      name: {{ $existing }}
      key: {{ $endpointKey }}
- name: NEWT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $existing }}
      key: {{ $idKey }}
- name: NEWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $existing }}
      key: {{ $secretKey }}
{{- else }}
- name: PANGOLIN_ENDPOINT
  value: {{ $inst.pangolinEndpoint | quote }}
- name: NEWT_ID
  value: {{ $inst.id | quote }}
{{- if $inst.secret }}
- name: NEWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "newt.instance.fullname" (dict "root" $root "inst" $inst) }}
      key: NEWT_SECRET
{{- end }}
{{- end }}
{{- if and $canOverride $inst.logLevel }}
- name: LOG_LEVEL
  value: {{ $inst.logLevel | quote }}
{{- else if $root.Values.global.logLevel }}
- name: LOG_LEVEL
  value: {{ $root.Values.global.logLevel | quote }}
{{- end }}
{{- if and $inst.mtu (ne (int $inst.mtu) 1280) }}
- name: MTU
  value: {{ printf "%v" $inst.mtu | quote }}
{{- end }}
{{- if $inst.dns }}
- name: DNS
  value: {{ $inst.dns | quote }}
{{- end }}
{{- if $inst.pingInterval }}
- name: PING_INTERVAL
  value: {{ $inst.pingInterval | quote }}
{{- end }}
{{- if $inst.pingTimeout }}
- name: PING_TIMEOUT
  value: {{ $inst.pingTimeout | quote }}
{{- end }}
{{- /* Add ACCEPT_CLIENTS env var only when enabled */ -}}
{{- if (default false $inst.acceptClients) }}
- name: ACCEPT_CLIENTS
  value: "true"
{{- end }}
{{- if $nativeEnabled }}
- name: USE_NATIVE_INTERFACE
  value: "true"
{{- end }}
{{- if and $inst.interface (ne $inst.interface "newt") }}
- name: INTERFACE
  value: {{ $inst.interface | quote }}
{{- end }}
{{- if $inst.keepInterface }}
- name: KEEP_INTERFACE
  value: "true"
{{- end }}
{{- if $root.Values.global.health.enabled }}
- name: HEALTH_FILE
  value: {{ $healthFile | quote }}
{{- end }}
{{- if and (kindIs "map" $inst.dockerSocket) $inst.dockerSocket.enabled }}
- name: DOCKER_SOCKET
  value: {{ $inst.dockerSocket.path | quote }}
- name: DOCKER_ENFORCE_NETWORK_VALIDATION
  value: {{ ternary "true" "false" (default false $inst.dockerSocket.enforceNetworkValidation) | quote }}
{{- end }}
{{- if and (kindIs "map" $inst.updown) $inst.updown.enabled }}
- name: UPDOWN_SCRIPT
  value: {{ printf "%s/%s" (default "/opt/newt/updown" $inst.updown.mountPath) (default "updown.sh" $inst.updown.fileName) | quote }}
{{ end }}
{{- if $inst.configFile }}
- name: CONFIG_FILE
  value: {{ $inst.configFile | quote }}
{{- end }}
{{- if $inst.generateAndSaveKeyTo }}
- name: GENERATE_AND_SAVE_KEY_TO
  value: {{ $inst.generateAndSaveKeyTo | quote }}
{{- end }}
{{- if $inst.port }}
- name: PORT
  value: {{ $inst.port | quote }}
{{- end }}
{{- if $inst.noCloud }}
- name: NO_CLOUD
  value: "true"
{{- end }}
{{- if $inst.disableClients }}
- name: DISABLE_CLIENTS
  value: "true"
{{- end }}
{{- if $inst.blueprintFile }}
- name: BLUEPRINT_FILE
  value: {{ $inst.blueprintFile | quote }}
{{- end }}
{{- if $inst.enforceHcCert }}
- name: ENFORCE_HC_CERT
  value: "true"
{{- end }}
{{- /* Metrics and OTEL env vars */ -}}
{{- $gm := (default (dict) $root.Values.global.metrics) -}}
{{- if $gm.enabled }}
{{- if and $gm.adminAddr (ne $gm.adminAddr "127.0.0.1:2112") }}
- name: NEWT_ADMIN_ADDR
  value: {{ $gm.adminAddr | quote }}
{{- end }}
{{- if $gm.asyncBytes }}
- name: NEWT_METRICS_ASYNC_BYTES
  value: "true"
{{- end }}
{{- if $gm.region }}
- name: NEWT_REGION
  value: {{ $gm.region | quote }}
{{- end }}
{{- if $gm.otlpEnabled }}
- name: NEWT_METRICS_OTLP_ENABLED
  value: "true"
{{- end }}
{{- $otel := (default (dict) $gm.otel) -}}
{{- if $otel.exporterOtlpEndpoint }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $otel.exporterOtlpEndpoint | quote }}
{{- end }}
{{- if $otel.exporterOtlpProtocol }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ $otel.exporterOtlpProtocol | quote }}
{{- end }}
{{- if $otel.exporterOtlpHeaders }}
- name: OTEL_EXPORTER_OTLP_HEADERS
  value: {{ $otel.exporterOtlpHeaders | quote }}
{{- end }}
{{- if $otel.serviceName }}
- name: OTEL_SERVICE_NAME
  value: {{ $otel.serviceName | quote }}
{{- end }}
{{- end }}
{{- /* mTLS split PEM env vars */ -}}
{{- $mtls := (default (dict) $inst.mtls) -}}
{{- if and $mtls.enabled (eq (default "pkcs12" $mtls.mode) "pem") -}}
{{- $pem := (default (dict) $mtls.pem) -}}
{{- if $pem.clientCertPath }}
- name: TLS_CLIENT_CERT
  value: {{ $pem.clientCertPath | quote }}
{{- end }}
{{- if $pem.clientKeyPath }}
- name: TLS_CLIENT_KEY
  value: {{ $pem.clientKeyPath | quote }}
{{- end }}
{{- if $pem.caPath }}
- name: TLS_CLIENT_CAS
  value: {{ $pem.caPath | quote }}
{{- end }}
{{- else if and $mtls.enabled (eq (default "pkcs12" $mtls.mode) "pkcs12") -}}
{{- $cp := ternary $mtls.certPath "/certs/client.p12" (and (kindIs "map" $mtls) (kindIs "string" $mtls.certPath) (ne $mtls.certPath "")) -}}
- name: TLS_CLIENT_CERT
  value: {{ $cp | quote }}
{{- end }}
{{- include "newt.instance.extraEnv" (dict "root" $root "inst" $inst) }}
{{- end }}

{{- define "newt.instance.commandArgs" -}}
{{- $inst := .inst -}}
{{- $root := .root -}}
{{- $args := list }}
{{- $canOverride := (default false $inst.allowGlobalOverride) -}}
{{- $auth := default (dict) $inst.auth -}}
{{- $existing := get $auth "existingSecretName" -}}
{{- if not $existing }}
  {{- $args = append $args (printf "--endpoint=%s" $inst.pangolinEndpoint) }}
  {{- if $inst.id }}{{- $args = append $args (printf "--id=%s" $inst.id) }}{{- end }}
{{- end }}
{{- if or $inst.secret $existing }}{{- $args = append $args (printf "--secret-env=NEWT_SECRET") }}{{- end }}
{{- if and $inst.mtu (ne (int $inst.mtu) 1280) }}{{- $args = append $args (printf "--mtu=%v" $inst.mtu) }}{{- end }}
{{- if $inst.dns }}{{- $args = append $args (printf "--dns=%s" $inst.dns) }}{{- end }}
{{- if $inst.pingInterval }}{{- $args = append $args (printf "--ping-interval=%s" $inst.pingInterval) }}{{- end }}
{{- if $inst.pingTimeout }}{{- $args = append $args (printf "--ping-timeout=%s" $inst.pingTimeout) }}{{- end }}
{{- if and $canOverride $inst.logLevel }}{{- $args = append $args (printf "--log-level=%s" $inst.logLevel) }}{{- else if $root.Values.global.logLevel }}{{- $args = append $args (printf "--log-level=%s" $root.Values.global.logLevel) }}{{- end }}
{{- /* Append --accept-clients only when enabled */ -}}
{{- if (default false $inst.acceptClients) }}{{- $args = append $args "--accept-clients" }}{{- end }}
{{- if and $inst.useNativeInterface $root.Values.global.nativeMode.enabled }}{{- $args = append $args "--native" }}{{- end }}
{{- if and $inst.interface (ne $inst.interface "newt") }}{{- $args = append $args (printf "--interface=%s" $inst.interface) }}{{- end }}
{{- if $inst.keepInterface }}{{- $args = append $args "--keep-interface" }}{{- end }}
{{- if $root.Values.global.health.enabled }}{{- $args = append $args (printf "--health-file=%s" (default $root.Values.global.health.path $inst.healthFile)) }}{{- end }}
{{- if $inst.dockerSocket.enabled }}{{- $args = append $args (printf "--docker-socket=%s" $inst.dockerSocket.path) }}{{- end }}
{{- if and $inst.dockerSocket.enabled $inst.dockerSocket.enforceNetworkValidation }}{{- $args = append $args "--docker-enforce-network-validation" }}{{- end }}
{{- if $inst.updown.enabled }}{{- $args = append $args (printf "--updown=%s/%s" (default "/opt/newt/updown" $inst.updown.mountPath) (default "updown.sh" $inst.updown.fileName)) }}{{- end }}
{{- if $inst.mtls.enabled }}{{- $args = append $args (printf "--tls-client-cert=%s" $inst.mtls.certPath) }}{{- end }}
{{- if $inst.generateAndSaveKeyTo }}{{- $args = append $args (printf "--generateAndSaveKeyTo=%s" $inst.generateAndSaveKeyTo) }}{{- end }}
{{- if $inst.port }}{{- $args = append $args (printf "--port=%s" $inst.port) }}{{- end }}
{{- if $inst.noCloud }}{{- $args = append $args "--no-cloud" }}{{- end }}
{{- if $inst.disableClients }}{{- $args = append $args "--disable-clients" }}{{- end }}
{{- if $inst.blueprintFile }}{{- $args = append $args (printf "--blueprint-file=%s" $inst.blueprintFile) }}{{- end }}
{{- if $inst.enforceHcCert }}{{- $args = append $args "--enforce-hc-cert" }}{{- end }}
{{- /* Metrics CLI args */ -}}
{{- $gm := (default (dict) $root.Values.global.metrics) -}}
{{- if $gm.enabled }}
{{- if and $gm.adminAddr (ne $gm.adminAddr "127.0.0.1:2112") }}{{- $args = append $args (printf "--metrics-admin-addr=%s" $gm.adminAddr) }}{{- end }}
{{- if $gm.asyncBytes }}{{- $args = append $args "--metrics-async-bytes" }}{{- end }}
{{- if $gm.region }}{{- $args = append $args (printf "--region=%s" $gm.region) }}{{- end }}
{{- if $gm.otlpEnabled }}{{- $args = append $args "--otlp" }}{{- end }}
{{- $otel := (default (dict) $gm.otel) -}}
{{- if $otel.exporterOtlpEndpoint }}{{- $args = append $args (printf "--otel-exporter-otlp-endpoint=%s" $otel.exporterOtlpEndpoint) }}{{- end }}
{{- end }}
{{- /* mTLS: handle both pkcs12 and pem modes via CLI */ -}}
{{- $mtls := (default (dict) $inst.mtls) -}}
{{- if and $mtls.enabled (eq (default "pkcs12" $mtls.mode) "pem") -}}
{{- $pem := (default (dict) $mtls.pem) -}}
{{- if $pem.clientCertPath }}{{- $args = append $args (printf "--tls-client-cert-file=%s" $pem.clientCertPath) }}{{- end }}
{{- if $pem.clientKeyPath }}{{- $args = append $args (printf "--tls-client-key=%s" $pem.clientKeyPath) }}{{- end }}
{{- if $pem.caPath }}{{- $args = append $args (printf "--tls-client-ca=%s" $pem.caPath) }}{{- end }}
{{- else if and $mtls.enabled (eq (default "pkcs12" $mtls.mode) "pkcs12") -}}
{{- $cp := ternary $mtls.certPath "/certs/client.p12" (and (kindIs "map" $mtls) (kindIs "string" $mtls.certPath) (ne $mtls.certPath "")) -}}
{{- $args = append $args (printf "--tls-client-cert=%s" $cp) }}{{- end }}
command:
  - /newt
args:
{{- range $args }}
  - {{ . | quote }}
{{- end }}
{{- end }}

{{- /* Merged extra envs: instance overrides global; stable key order */ -}}
{{- define "newt.instance.extraEnv" -}}
{{- $root := .root -}}
{{- $inst := .inst -}}
{{- $g := (default (dict) $root.Values.global.extraEnv) -}}
{{- $i := (default (dict) $inst.extraEnv) -}}
{{- $merged := mergeOverwrite (deepCopy $g) $i -}}
{{- $keys := keys $merged | sortAlpha -}}
{{- range $k := $keys }}
- name: {{ $k }}
  value: {{ (index $merged $k) | quote }}
{{- end }}
{{- end }}

{{- /*
  Helper: newt.effectiveMetrics
  Usage: include "newt.effectiveMetrics" (list $inst $gm)
  Returns: JSON-encoded merged metrics (global merged with instance.metrics when allowGlobalOverride is true), parsed back to map via fromJson when used.
*/ -}}
{{- define "newt.effectiveMetrics" -}}
  {{- $inst := index . 0 -}}
  {{- $gm := index . 1 -}}
  {{- $allow := default false $inst.allowGlobalOverride -}}
  {{- if $allow -}}
    {{- $im := (default (dict) $inst.metrics) -}}
    {{- $res := mergeOverwrite (deepCopy $gm) $im -}}
    {{- printf "%s" (toJson $res) | fromJson -}}
  {{- else -}}
    {{- printf "%s" (toJson $gm) | fromJson -}}
  {{- end -}}
{{- end }}
