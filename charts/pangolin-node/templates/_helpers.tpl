{{- define "pangolin-node.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pangolin-node.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin-node.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pangolin-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pangolin-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "pangolin-node.labels" -}}
helm.sh/chart: {{ include "pangolin-node.chart" . }}
{{ include "pangolin-node.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: pangolin
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "pangolin-node.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end -}}

{{- define "pangolin-node.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "pangolin-node.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- /* Usage: include "pangolin-node.image" (dict "image" .Values.images.gerbil "default" "") */ -}}
{{- define "pangolin-node.image" -}}
{{- $img := .image -}}
{{- $ref := printf "%s/%s" $img.registry $img.repository | trimPrefix "/" -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $ref $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (default .default $img.tag) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin-node.configSecretName" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecret -}}
{{- else -}}
{{- printf "%s-config" (include "pangolin-node.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin-node.configSecretKey" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecretKey | default "config.yml" -}}
{{- else -}}
config.yml
{{- end -}}
{{- end -}}

{{- /* Whether an init container merges managed.existingSecret into config.yml. */ -}}
{{- define "pangolin-node.mergeManagedSecret" -}}
{{- if and (not .Values.config.existingSecret) .Values.config.managed.existingSecret -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pangolin-node.gerbilClaimName" -}}
{{- .Values.gerbil.persistence.existingClaim | default (printf "%s-gerbil" (include "pangolin-node.fullname" .)) -}}
{{- end -}}

{{- /*
config.yml for pangolin-node (server/lib/readConfigFile.ts).

Everything runs in one Pod, so the addresses the node hands out point at loopback:
- server.internal_hostname goes into the Badger middleware config, and Badger runs inside
  Traefik in this Pod.
- gerbil.reachable_at is where pangolin-node calls Gerbil's HTTP API.
The traefik.* paths must match the shared volume mounts and the Traefik file provider.
*/ -}}
{{- define "pangolin-node.config" -}}
{{- $c := .Values.config -}}
{{- $managed := dict "endpoint" $c.managed.endpoint -}}
{{- if not $c.managed.existingSecret -}}
{{- $_ := set $managed "id" $c.managed.id -}}
{{- $_ := set $managed "secret" $c.managed.secret -}}
{{- end -}}
{{- with $c.managed.name }}{{ $_ := set $managed "name" . }}{{ end -}}
{{- with $c.managed.redirect_endpoint }}{{ $_ := set $managed "redirect_endpoint" . }}{{ end -}}
{{- $dyn := .Values.sharedVolumes.dynamic.mountPath | trimSuffix "/" -}}
{{- $cfg := dict
  "app" (dict
    "log_level" $c.app.log_level
    "log_failed_attempts" $c.app.log_failed_attempts
    "audit_logging_enabled" $c.app.audit_logging_enabled)
  "server" (dict
    "internal_port" (int .Values.pangolinNode.internalPort)
    "internal_hostname" "127.0.0.1")
  "managed" $managed
  "traefik" (dict
    "certificates_path" (.Values.sharedVolumes.certificates.mountPath | trimSuffix "/")
    "dynamic_cert_config_path" (printf "%s/cert_config.yml" $dyn)
    "dynamic_router_config_path" (printf "%s/router_config.yml" $dyn))
  "gerbil" (dict
    "base_endpoint" $c.gerbil.base_endpoint
    "start_port" (int $c.gerbil.start_port)
    "reachable_at" (printf "http://127.0.0.1:%d" (int .Values.gerbil.ports.internalApi)))
-}}
{{- toYaml (mergeOverwrite $cfg (deepCopy ($c.extra | default dict))) -}}
{{- end -}}

{{- /* Traefik static configuration (the compose config/traefik/traefik_config.yml). */ -}}
{{- define "pangolin-node.traefikConfig" -}}
{{- $t := .Values.traefik -}}
{{- $websecure := dict "address" (printf ":%d" (int $t.ports.websecure)) "transport" (dict "respondingTimeouts" (dict "readTimeout" "30m")) -}}
{{- with $t.proxyProtocolTrustedIPs }}
{{- $_ := set $websecure "proxyProtocol" (dict "trustedIPs" .) -}}
{{- end -}}
{{- $cfg := dict
  "api" (dict "insecure" $t.dashboard "dashboard" $t.dashboard)
  "ping" (dict "entryPoint" "traefik")
  "providers" (dict "file" (dict "directory" (.Values.sharedVolumes.dynamic.mountPath | trimSuffix "/") "watch" true))
  "experimental" (dict "plugins" (dict "badger" (dict "moduleName" $t.badger.moduleName "version" $t.badger.version)))
  "log" (dict "level" $t.logLevel "format" "common")
  "entryPoints" (dict
    "traefik" (dict "address" (printf ":%d" (int $t.ports.admin)))
    "web" (dict "address" (printf ":%d" (int $t.ports.web)))
    "websecure" $websecure)
  "serversTransport" (dict "insecureSkipVerify" true)
-}}
{{- if $t.accessLog }}
{{- $_ := set $cfg "accessLog" (dict) -}}
{{- end -}}
{{- toYaml (mergeOverwrite $cfg (deepCopy ($t.extraStaticConfig | default dict))) -}}
{{- end -}}

{{- define "pangolin-node.validate" -}}
{{- $c := .Values.config -}}
{{- if not $c.existingSecret -}}
{{- if not $c.gerbil.base_endpoint -}}
{{- fail "config.gerbil.base_endpoint is required: the public hostname or IP sites use to reach this node" -}}
{{- end -}}
{{- if and (not $c.managed.existingSecret) (or (not $c.managed.id) (not $c.managed.secret)) -}}
{{- fail "set config.managed.id and config.managed.secret, or config.managed.existingSecret, or config.existingSecret" -}}
{{- end -}}
{{- if ne (int $c.gerbil.start_port) (int .Values.gerbil.ports.wg1) -}}
{{- fail (printf "config.gerbil.start_port (%v) must equal gerbil.ports.wg1 (%v)" $c.gerbil.start_port .Values.gerbil.ports.wg1) -}}
{{- end -}}
{{- /* Sites dial base_endpoint:start_port, so the public port has to be the same number. */ -}}
{{- if and .Values.service.enabled (eq .Values.service.type "LoadBalancer") (ne (int .Values.service.ports.wg1) (int $c.gerbil.start_port)) -}}
{{- fail (printf "service.ports.wg1 (%v) must equal config.gerbil.start_port (%v): sites connect to base_endpoint:start_port" .Values.service.ports.wg1 $c.gerbil.start_port) -}}
{{- end -}}
{{- if and .Values.hostPorts.enabled (ne (int .Values.hostPorts.wg1) (int $c.gerbil.start_port)) -}}
{{- fail (printf "hostPorts.wg1 (%v) must equal config.gerbil.start_port (%v): sites connect to base_endpoint:start_port" .Values.hostPorts.wg1 $c.gerbil.start_port) -}}
{{- end -}}
{{- end -}}
{{- if eq (int .Values.traefik.ports.websecure) (int .Values.gerbil.ports.sni) -}}
{{- fail "traefik.ports.websecure and gerbil.ports.sni share the Pod network namespace and must differ" -}}
{{- end -}}
{{- end -}}
