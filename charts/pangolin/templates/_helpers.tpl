{{- define "pangolin.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pangolin.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "pangolin.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.controller.fullname" -}}
{{- printf "%s-controller" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pangolin.namespace" -}}
{{- default .Release.Namespace .Values.global.namespaceOverride -}}
{{- end -}}

{{- define "pangolin.serviceAccountName" -}}
{{- if .Values.serviceAccount.pangolin.name -}}
{{- .Values.serviceAccount.pangolin.name -}}
{{- else -}}
{{- printf "%s-sa" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.serviceAccountName.gerbil" -}}
{{- if .Values.serviceAccount.gerbil.name -}}
{{- .Values.serviceAccount.gerbil.name -}}
{{- else -}}
{{- printf "%s-gerbil-sa" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.serviceAccountName.controller" -}}
{{- if .Values.serviceAccount.controller.name -}}
{{- .Values.serviceAccount.controller.name -}}
{{- else -}}
{{- printf "%s-controller-sa" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.serviceAccountName.single" -}}
{{- if and (eq .Values.deployment.type "controller") .Values.controller.enabled -}}
{{- include "pangolin.serviceAccountName.controller" . -}}
{{- else -}}
{{- include "pangolin.serviceAccountName" . -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.gerbil.startupMode" -}}
{{- default "normal" .Values.gerbil.startupMode -}}
{{- end -}}

{{- /* include() returns strings, so callers compare this helper output to "true". */ -}}
{{- define "pangolin.gerbil.resourcesEnabled" -}}
{{- if and .Values.gerbil.enabled (ne (include "pangolin.gerbil.startupMode" .) "disabledUntilSetup") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "pangolin.db.mode" -}}
{{- default "cloudnativepg" ((.Values.database).mode) -}}
{{- end -}}

{{- define "pangolin.db.cnpgClusterName" -}}
{{- $db := default (dict) .Values.database -}}
{{- $cnpg := default (dict) (get $db "cloudnativepg") -}}
{{- $cnpgCluster := default (dict) (get $cnpg "cluster") -}}
{{- $cnpgName := default "" (get $cnpgCluster "name") -}}
{{- $cnpgSubchart := default (dict) (index .Values "cnpg-cluster") -}}
{{- $subchartEnabled := default false (get $cnpgSubchart "enabled") -}}
{{- $subchartCnpgName := default "" (get $cnpgSubchart "fullnameOverride") -}}
{{- if and (eq (include "pangolin.db.mode" .) "cloudnativepg") $subchartEnabled $subchartCnpgName -}}
{{- $subchartCnpgName -}}
{{- else if $cnpgName -}}
{{- $cnpgName -}}
{{- else -}}
pangolin-db
{{- end -}}
{{- end -}}

{{- define "pangolin.db.connectionSecretName" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- $db := default (dict) .Values.database -}}
{{- $conn := default (dict) (get $db "connection") -}}
{{- $external := default (dict) (get $db "external") -}}
{{- $cnpg := default (dict) (get $db "cloudnativepg") -}}
{{- $cnpgConn := default (dict) (get $cnpg "connection") -}}
{{- $cnpgGenerated := default (dict) (get $cnpgConn "generatedSecret") -}}
{{- if (get $conn "existingSecretName") -}}
{{- get $conn "existingSecretName" -}}
{{- else if and (eq $mode "external") (get $external "existingSecretName") -}}
{{- get $external "existingSecretName" -}}
{{- else if and (eq $mode "cloudnativepg") (get $cnpgConn "existingSecretName") -}}
{{- get $cnpgConn "existingSecretName" -}}
{{- else if and (eq $mode "cloudnativepg") ((get $cnpgGenerated "create") | default false) -}}
{{- /* Chart builds CNPG connection string – use generatedSecret name */ -}}
{{- default (printf "%s-db-connection" (include "pangolin.fullname" .)) (get $cnpgGenerated "name") -}}
{{- else if eq $mode "cloudnativepg" -}}
{{- /* Auto-derive the CNPG-generated app Secret: <cluster-name>-app */ -}}
{{- printf "%s-app" (include "pangolin.db.cnpgClusterName" .) -}}
{{- else if eq $mode "external" -}}
{{- $extGen := default (dict) (get $external "generatedSecret") -}}
{{- default (printf "%s-db-connection" (include "pangolin.fullname" .)) (get $extGen "name") -}}
{{- else -}}
{{- default (printf "%s-db-connection" (include "pangolin.fullname" .)) (get (default (dict) (get $conn "generatedSecret")) "name") -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.db.connectionSecretKey" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- $db := default (dict) .Values.database -}}
{{- $conn := default (dict) (get $db "connection") -}}
{{- $external := default (dict) (get $db "external") -}}
{{- $cnpg := default (dict) (get $db "cloudnativepg") -}}
{{- $cnpgConn := default (dict) (get $cnpg "connection") -}}
{{- $cnpgGenerated := default (dict) (get $cnpgConn "generatedSecret") -}}
{{- if (get $conn "existingSecretName") -}}
{{- default "connectionString" (get $conn "existingSecretKey") -}}
{{- else if and (eq $mode "external") (get $external "existingSecretName") -}}
{{- default "connectionString" (get $external "existingSecretKey") -}}
{{- else if and (eq $mode "cloudnativepg") (get $cnpgConn "existingSecretName") -}}
{{- default "connectionString" (get $cnpgConn "existingSecretKey") -}}
{{- else if and (eq $mode "cloudnativepg") ((get $cnpgGenerated "create") | default false) -}}
{{- /* Chart builds CNPG connection string – use generatedSecret key */ -}}
{{- default "connectionString" (get $cnpgGenerated "key") -}}
{{- else if eq $mode "cloudnativepg" -}}
{{- /* Auto-derived CNPG app Secret always uses the "uri" key */ -}}
uri
{{- else -}}
{{- default "connectionString" (get (default (dict) (get $conn "generatedSecret")) "key") -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.db.shouldRenderConnectionSecret" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- $db := default (dict) .Values.database -}}
{{- $conn := default (dict) (get $db "connection") -}}
{{- $external := default (dict) (get $db "external") -}}
{{- $cnpg := default (dict) (get $db "cloudnativepg") -}}
{{- $cnpgConn := default (dict) (get $cnpg "connection") -}}
{{- $generated := default (dict) (get $conn "generatedSecret") -}}
{{- if or (eq $mode "sqlite") (eq $mode "cloudnativepg") -}}
false
{{- else if or (get $conn "existingSecretName") (and (eq $mode "external") (get $external "existingSecretName")) -}}
false
{{- else if eq $mode "external" -}}
{{- /* For external mode, the create flag lives under database.external.generatedSecret */ -}}
{{- $extGenerated := default (dict) (get $external "generatedSecret") -}}
{{- ternary "true" "false" ((get $extGenerated "create") | default false) -}}
{{- else -}}
{{- ternary "true" "false" ((get $generated "create") | default false) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.db.connectionString" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- $ssl := default "disable" .Values.database.connection.generatedSecret.sslMode -}}
{{- if eq $mode "external" -}}
{{- $extGen := default (dict) .Values.database.external.generatedSecret -}}
{{- $connStr := default "" (get $extGen "connectionString") -}}
{{- if $connStr -}}
{{- $connStr -}}
{{- else -}}
{{- /* Build connection string from individual parameters */ -}}
{{- $host := required "database.external.generatedSecret.host (or .connectionString) is required when database.mode=external and database.external.generatedSecret.create=true" (get $extGen "host") -}}
{{- $port := default 5432 (get $extGen "port") -}}
{{- $dbName := default (default "pangolin" .Values.database.name) (get $extGen "database") -}}
{{- $user := default (default "pangolin" .Values.database.username) (get $extGen "username") -}}
{{- $pass := required "database.external.generatedSecret.password is required when building a connection string from individual parameters" (get $extGen "password") -}}
{{- $sslMode := default "disable" (get $extGen "sslMode") -}}
{{- printf "postgresql://%s:%s@%s:%v/%s?sslmode=%s" ($user | urlquery) ($pass | urlquery) $host $port $dbName $sslMode -}}
{{- end -}}
{{- else if eq $mode "embedded" -}}
{{- $user := required "database.username is required" .Values.database.username -}}
{{- $db := required "database.name is required" .Values.database.name -}}
{{- if not .Values.database.embedded.auth.generatedSecret.create -}}
{{- fail "database.embedded.auth.generatedSecret.create must be true (or set database.connection.existingSecretName) to generate a connection string for embedded mode" -}}
{{- end -}}
{{- $pw := required "database.embedded.auth.generatedSecret.password is required when generating embedded connection secret" .Values.database.embedded.auth.generatedSecret.password -}}
{{- $host := printf "%s-embedded-postgres" (include "pangolin.fullname" .) -}}
{{- $port := default 5432 .Values.database.embedded.service.port -}}
{{- printf "postgresql://%s:%s@%s:%v/%s?sslmode=%s" $user $pw $host $port $db $ssl -}}
{{- else if eq $mode "cloudnativepg" -}}
{{- $user := default .Values.database.username .Values.database.cloudnativepg.connection.username -}}
{{- $db := default .Values.database.name .Values.database.cloudnativepg.connection.database -}}
{{- $sslCnpg := default "disable" .Values.database.cloudnativepg.connection.sslMode -}}
{{- $host := .Values.database.cloudnativepg.connection.host -}}
{{- if not $host -}}
  {{- $rwSvc := .Values.database.cloudnativepg.cluster.rwServiceName -}}
  {{- if not $rwSvc -}}
    {{- $rwSvc = printf "%s-rw" (include "pangolin.db.cnpgClusterName" .) -}}
  {{- end -}}
  {{- $host = $rwSvc -}}
{{- end -}}
{{- $port := default 5432 .Values.database.cloudnativepg.connection.port -}}
{{- $cnpgAuth := default (dict) .Values.database.cloudnativepg.auth -}}
{{- $cnpgAuthGenerated := default (dict) (get $cnpgAuth "generatedSecret") -}}
{{- $cnpgAuthExisting := default "" (get $cnpgAuth "existingSecretName") -}}
{{- $pw := "" -}}
{{- if and ((get $cnpgAuthGenerated "create") | default false) (get $cnpgAuthGenerated "password") -}}
{{- $pw = get $cnpgAuthGenerated "password" -}}
{{- else if $cnpgAuthExisting -}}
{{- $pwKey := default "password" (get $cnpgAuth "passwordKey") -}}
{{- $authSecret := lookup "v1" "Secret" (include "pangolin.namespace" .) $cnpgAuthExisting -}}
{{- if and $authSecret $authSecret.data (hasKey $authSecret.data $pwKey) -}}
{{- $pw = index $authSecret.data $pwKey | b64dec -}}
{{- else -}}
{{- fail (printf "PANGOLIN-CNPG: Could not retrieve password from existing Secret '%s' (key: %s). Verify the Secret exists in the correct namespace and contains the specified key." $cnpgAuthExisting $pwKey) -}}
{{- end -}}
{{- else -}}
{{- fail "PANGOLIN-CNPG: Cannot generate a PostgreSQL connection string for CloudNativePG without a password. Set database.cloudnativepg.auth.generatedSecret.password, set database.cloudnativepg.auth.existingSecretName, or use database.connection.existingSecretName to reference the CNPG-generated app Secret." -}}
{{- end -}}
{{- printf "postgresql://%s:%s@%s:%v/%s?sslmode=%s" $user $pw $host $port $db $sslCnpg -}}
{{- else -}}
{{- fail (printf "unsupported database.mode: %s" $mode) -}}
{{- end -}}
{{- end -}}

{{- /*
pangolin.db.waitHost returns the hostname to poll for TCP readiness before
Pangolin starts. Returns an empty string for sqlite (no wait needed).
*/ -}}
{{- define "pangolin.db.waitHost" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- if eq $mode "cloudnativepg" -}}
  {{- $cnpg := default (dict) .Values.database.cloudnativepg -}}
  {{- $conn := default (dict) (get $cnpg "connection") -}}
  {{- $host := default "" (get $conn "host") -}}
  {{- if $host -}}
    {{- $host -}}
  {{- else -}}
    {{- $cluster := default (dict) (get $cnpg "cluster") -}}
    {{- $rwSvc := default "" (get $cluster "rwServiceName") -}}
    {{- if not $rwSvc -}}
      {{- $rwSvc = printf "%s-rw" (include "pangolin.db.cnpgClusterName" .) -}}
    {{- end -}}
    {{- $rwSvc -}}
  {{- end -}}
{{- else if eq $mode "embedded" -}}
  {{- printf "%s-embedded-postgres" (include "pangolin.fullname" .) -}}
{{- else if eq $mode "external" -}}
  {{- $extGen := default (dict) .Values.database.external.generatedSecret -}}
  {{- default "" (get $extGen "host") -}}
{{- end -}}
{{- end -}}

{{- /*
pangolin.db.waitPort returns the TCP port to poll for database readiness.
Returns an empty string for sqlite.
*/ -}}
{{- define "pangolin.db.waitPort" -}}
{{- $mode := include "pangolin.db.mode" . -}}
{{- if eq $mode "cloudnativepg" -}}
  {{- $cnpg := default (dict) .Values.database.cloudnativepg -}}
  {{- $conn := default (dict) (get $cnpg "connection") -}}
  {{- default 5432 (get $conn "port") -}}
{{- else if eq $mode "embedded" -}}
  {{- default 5432 .Values.database.embedded.service.port -}}
{{- else if eq $mode "external" -}}
  {{- $extGen := default (dict) .Values.database.external.generatedSecret -}}
  {{- default 5432 (get $extGen "port") -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pangolin.labels" -}}
{{- include "pangolin.renderNonSelectorLabels" (dict "labels" (mergeOverwrite (dict) (.Values.global.additionalLabels | default dict) (.Values.global.commonLabels | default dict))) }}
helm.sh/chart: {{ include "pangolin.chart" . }}
app.kubernetes.io/name: {{ include "pangolin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "pangolin.component.commonLabels" -}}
{{- $componentValues := get .root.Values .component | default dict -}}
{{- include "pangolin.renderNonSelectorLabels" (dict "labels" (get $componentValues "commonLabels" | default dict)) }}
{{- end -}}

{{- define "pangolin.component.commonAnnotations" -}}
{{- $componentValues := get .root.Values .component | default dict -}}
{{- toYaml (get $componentValues "commonAnnotations" | default dict) -}}
{{- end -}}

{{- define "pangolin.global.commonAnnotations" -}}
{{- toYaml (mergeOverwrite (dict) (.Values.global.additionalAnnotations | default dict) (.Values.global.commonAnnotations | default dict)) -}}
{{- end -}}

{{- define "pangolin.renderNonSelectorLabels" -}}
{{- $labels := .labels | default dict -}}
{{- range $k, $v := $labels }}
{{- if and (ne $k "app.kubernetes.io/name") (ne $k "app.kubernetes.io/instance") (ne $k "app.kubernetes.io/component") }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- define "pangolin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pangolin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "pangolin.pangolin.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: pangolin
{{- end -}}

{{- define "pangolin.controller.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: controller
{{- end -}}

{{- define "pangolin.embeddedPostgres.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: embedded-postgres
{{- end -}}

{{- define "pangolin.gerbil.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: gerbil
{{- end -}}

{{- define "pangolin.traefik.standalone.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: traefik-standalone
{{- end -}}

{{- define "pangolin.single.selectorLabels" -}}
{{ include "pangolin.selectorLabels" . }}
app.kubernetes.io/component: single
{{- end -}}

{{- define "pangolin.imagePullSecrets" -}}
{{- with .Values.global.image.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end -}}
{{- end -}}

{{- define "pangolin._resolveImage" -}}
{{- $img := .img -}}
{{- $root := .root -}}
{{- $tagPrefix := .tagPrefix | default "" -}}
{{- $registry := $img.registry | default ($root.Values.global.image.registry | default "docker.io") -}}
{{- $repo := $img.repository -}}
{{- $digest := $img.digest | default "" -}}
{{- $pullPolicy := $img.pullPolicy | default ($root.Values.global.image.pullPolicy | default "IfNotPresent") -}}
{{- if $digest -}}
{{- printf "%s/%s@%s" $registry $repo $digest -}}
{{- else -}}
{{- $fallbackTag := .fallbackTag | default (printf "%s%s" $tagPrefix $root.Chart.AppVersion) -}}
{{- $tag := $img.tag | default $fallbackTag -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.image" -}}
{{- $root := . -}}
{{- $dbMode := include "pangolin.db.mode" $root -}}
{{- $img := $root.Values.images.pangolin -}}
{{- if or $img.tag $img.digest -}}
{{- /* User explicitly set tag or digest: honour their pangolin image config as-is */ -}}
{{- include "pangolin._resolveImage" (dict "img" $img "root" $root) -}}
{{- else if ne $dbMode "sqlite" -}}
{{- /* PostgreSQL-backed mode: use the postgresql-capable image (tag defaults to postgresql-<AppVersion>) */ -}}
{{- include "pangolin._resolveImage" (dict "img" $root.Values.images.pangolinPostgresql "root" $root "tagPrefix" "postgresql-") -}}
{{- else -}}
{{- /* SQLite mode: use the standard pangolin image */ -}}
{{- include "pangolin._resolveImage" (dict "img" $img "root" $root) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.imagePullPolicy" -}}
{{- .Values.images.pangolin.pullPolicy | default .Values.global.image.imagePullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "pangolin.controller.image" -}}
{{- include "pangolin._resolveImage" (dict "img" .Values.images.controller "root" . "fallbackTag" "0.1.0-alpha.1") -}}
{{- end -}}

{{- define "pangolin.controller.imagePullPolicy" -}}
{{- .Values.images.controller.pullPolicy | default .Values.global.image.imagePullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{- define "pangolin.postgres.image" -}}
{{- include "pangolin._resolveImage" (dict "img" .Values.images.postgres "root" .) -}}
{{- end -}}

{{- define "pangolin.gerbil.image" -}}
{{- include "pangolin._resolveImage" (dict "img" .Values.images.gerbil "root" .) -}}
{{- end -}}

{{- define "pangolin.traefik.image" -}}
{{- include "pangolin._resolveImage" (dict "img" .Values.images.traefik "root" .) -}}
{{- end -}}

{{- define "pangolin.controller.configMapName" -}}
{{- include "pangolin.controller.fullname" . -}}
{{- end -}}

{{- define "pangolin.controller.configEndpoint" -}}
{{- $pangolinSvc := include "pangolin.pangolin.serviceFQDN" . -}}
{{- $pangolinPort := (.Values.pangolin.service.ports.internalApi | default 3001) -}}
{{- $defaultEndpoint := printf "http://%s:%v/api/v1/traefik-config" $pangolinSvc $pangolinPort -}}
{{- .Values.controller.config.configEndpoint | default $defaultEndpoint -}}
{{- end -}}

{{- define "pangolin.controller.configAllowInsecureHttp" -}}
{{- $allowInsecureHttp := .Values.controller.config.allowInsecureHttp -}}
{{- if eq $allowInsecureHttp nil -}}
{{- hasPrefix "http://" (lower (include "pangolin.controller.configEndpoint" .)) -}}
{{- else -}}
{{- $allowInsecureHttp -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.wait.config" -}}
{{- $root := .root -}}
{{- $override := default (dict) .override -}}
{{- $runtime := default (dict) $root.Values.runtime -}}
{{- $runtimeDependencyWait := default (dict) (get $runtime "dependencyWait") -}}
{{- $runtimeImage := default (dict) (get $runtimeDependencyWait "image") -}}
{{- $overrideImage := default (dict) (get $override "image") -}}
{{- $default := dict "intervalSeconds" 5 "timeoutSeconds" 300 "stableSeconds" 30 -}}
{{- $_ := set $default "image" (dict "registry" "docker.io" "repository" "busybox" "tag" "1.36" "pullPolicy" "IfNotPresent") -}}
{{- $merged := mergeOverwrite (dict) $default $runtimeDependencyWait $override -}}
{{- $_ = set $merged "image" (mergeOverwrite (dict) (get $default "image") $runtimeImage $overrideImage) -}}
{{- toYaml $merged -}}
{{- end -}}

{{- define "pangolin.wait.image" -}}
{{- $img := default (dict) . -}}
{{- $registry := default "docker.io" (get $img "registry") -}}
{{- $repository := default "busybox" (get $img "repository") -}}
{{- $tag := default "1.36" (get $img "tag") -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.controller.tlsSecretName" -}}
{{- $tls := .Values.controller.tls | default dict -}}
{{- if (get $tls "existingSecretName") -}}
{{- get $tls "existingSecretName" -}}
{{- else -}}
{{- printf "%s-controller-tls" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.app.secretName" -}}
{{- if .Values.pangolin.secret.existingSecretName -}}
{{- .Values.pangolin.secret.existingSecretName -}}
{{- else if and .Values.pangolin.secret.generated .Values.pangolin.secret.generated.name -}}
{{- .Values.pangolin.secret.generated.name -}}
{{- else -}}
{{- printf "%s-app" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.app.secretValue" -}}
{{- $len := (.Values.pangolin.secret.generated.length | default 64 | int) -}}
{{- $key := .Values.pangolin.secret.generated.key | default "SERVER_SECRET" -}}
{{- $existing := lookup "v1" "Secret" (include "pangolin.namespace" .) (include "pangolin.app.secretName" .) -}}
{{- if and $existing $existing.data (hasKey $existing.data $key) -}}
{{- index $existing.data $key | b64dec -}}
{{- else -}}
{{- randAlphaNum $len -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.privateConfig.secretName" -}}
{{- $pc := .Values.pangolin.privateConfig | default dict -}}
{{- if (get $pc "existingSecretName") -}}
{{- get $pc "existingSecretName" -}}
{{- else -}}
{{- $gen := (get $pc "generatedSecret") | default dict -}}
{{- if (get $gen "name") -}}
{{- get $gen "name" -}}
{{- else -}}
{{- printf "%s-private-config" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.blueprints.configMapName" -}}
{{- $bp := .Values.pangolin.blueprints | default dict -}}
{{- if (get $bp "existingConfigMap") -}}
{{- get $bp "existingConfigMap" -}}
{{- else -}}
{{- $cm := (get $bp "configMap") | default dict -}}
{{- if (get $cm "name") -}}
{{- get $cm "name" -}}
{{- else -}}
{{- printf "%s-blueprints" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.blueprints.envSecretName" -}}
{{- $bp := .Values.pangolin.blueprints | default dict -}}
{{- if (get $bp "existingEnvironmentSecret") -}}
{{- get $bp "existingEnvironmentSecret" -}}
{{- else -}}
{{- $es := (get $bp "environmentSecret") | default dict -}}
{{- if (get $es "name") -}}
{{- get $es "name" -}}
{{- else -}}
{{- printf "%s-blueprints-env" (include "pangolin.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.database.connectionSecretName" -}}
{{- include "pangolin.db.connectionSecretName" . -}}
{{- end -}}

{{- define "pangolin.database.authSecretName" -}}
{{- $db := default (dict) .Values.database -}}
{{- $embedded := default (dict) (get $db "embedded") -}}
{{- $auth := default (dict) (get $embedded "auth") -}}
{{- if (get $auth "existingSecretName") -}}
{{- get $auth "existingSecretName" -}}
{{- else -}}
{{- $generated := default (dict) (get $auth "generatedSecret") -}}
{{- default (printf "%s-embedded-postgres-auth" (include "pangolin.fullname" .)) (get $generated "name") -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.gerbilEnv" -}}
{{- $gerbil := .Values.gerbil -}}
{{- range $k, $v := ($gerbil.extraEnv | default dict) }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end -}}
{{- end -}}

{{- define "pangolin.traefikEnv" -}}
{{- $root := . -}}
{{- $cf := default (dict) .Values.traefik.cloudflare -}}
{{- $cfKeys := default (dict) (get $cf "keys") -}}
{{- $cfGenerated := default (dict) (get $cf "generatedSecret") -}}
{{- $cfSecret := (get $cf "existingSecretName") | default "" -}}
{{- if $cfSecret }}
- name: CF_API_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ $cfSecret }}
      key: {{ (get $cfKeys "email") | default "email" }}
- name: CF_DNS_API_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $cfSecret }}
      key: {{ (get $cfKeys "dnsApiToken") | default "dnsApiToken" }}
{{- else if ((get $cfGenerated "create") | default false) }}
{{- $genName := (get $cfGenerated "name") | default (printf "%s-traefik-cloudflare" (include "pangolin.fullname" $root | trunc 44 | trimSuffix "-")) -}}
- name: CF_API_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ $genName }}
      key: email
- name: CF_DNS_API_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $genName }}
      key: dnsApiToken
{{- end -}}
{{- end -}}

{{- /*
pangolin.renderResources renders a resources block applying the global resourcesPolicy:
  - ephemeral-storage keys are omitted unless resourcesPolicy.ephemeralStorage.enabled=true
  - CPU limits are omitted when resourcesPolicy.cpuLimits.enabled=false (default: true)
Usage: {{- include "pangolin.renderResources" (dict "resources" $component.resources "root" .) | nindent N }}
*/ -}}
{{- define "pangolin.renderResources" -}}
{{- $res := .resources | default dict -}}
{{- $root := .root -}}
{{- $policy := ($root.Values.resourcesPolicy | default dict) -}}
{{- /* Resolve cpuLimits.enabled (default true) */ -}}
{{- $cpuLimitsSection := ($policy.cpuLimits | default dict) -}}
{{- $cpuLimitsEnabled := true -}}
{{- if hasKey $cpuLimitsSection "enabled" -}}
  {{- $cpuLimitsEnabled = get $cpuLimitsSection "enabled" -}}
{{- end -}}
{{- /* Resolve ephemeralStorage.enabled (default false) */ -}}
{{- $ephemeralSection := ($policy.ephemeralStorage | default dict) -}}
{{- $ephemeralEnabled := false -}}
{{- if hasKey $ephemeralSection "enabled" -}}
  {{- $ephemeralEnabled = get $ephemeralSection "enabled" -}}
{{- end -}}
{{- /* Build filtered requests map */ -}}
{{- $req := dict -}}
{{- range $k, $v := ($res.requests | default dict) -}}
  {{- if and (eq $k "ephemeral-storage") (not $ephemeralEnabled) -}}
  {{- else -}}
    {{- $_ := set $req $k $v -}}
  {{- end -}}
{{- end -}}
{{- /* Build filtered limits map */ -}}
{{- $lim := dict -}}
{{- range $k, $v := ($res.limits | default dict) -}}
  {{- if and (eq $k "ephemeral-storage") (not $ephemeralEnabled) -}}
  {{- else if and (eq $k "cpu") (not $cpuLimitsEnabled) -}}
  {{- else -}}
    {{- $_ := set $lim $k $v -}}
  {{- end -}}
{{- end -}}
{{- if not (empty $req) }}
requests:
{{- toYaml $req | nindent 2 }}
{{- end -}}
{{- if not (empty $lim) }}
limits:
{{- toYaml $lim | nindent 2 }}
{{- end -}}
{{- end -}}

{{- define "pangolin.dashboardHostFromURL" -}}
{{- $dashboardURL := trim (default "" .Values.pangolin.config.app.dashboard_url) -}}
{{- if $dashboardURL -}}
{{- $withoutScheme := regexReplaceAll "^[a-zA-Z][a-zA-Z0-9+.-]*://" $dashboardURL "" -}}
{{- $authority := regexFind "^[^/?#]+" $withoutScheme -}}
{{- if $authority -}}
{{- $host := regexReplaceAll "^[^@]*@" $authority "" -}}
{{- $host = regexReplaceAll ":[0-9]+$" $host "" -}}
{{- $host -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.ingressRoute.dashboard.host" -}}
{{- $dashboardIngress := default (dict) .Values.pangolin.ingressRoute.dashboard -}}
{{- $configuredHost := trim (default "" (get $dashboardIngress "host")) -}}
{{- if $configuredHost -}}
{{- $configuredHost -}}
{{- else -}}
{{- include "pangolin.dashboardHostFromURL" . -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.ingressRoute.dashboard.serviceName" -}}
{{- $route := default (dict) .route -}}
{{- $service := default (dict) (get $route "service") -}}
{{- default (include "pangolin.fullname" .root) (get $service "name") -}}
{{- end -}}

{{- define "pangolin.ingressRoute.dashboard.serviceNamespace" -}}
{{- $route := default (dict) .route -}}
{{- $service := default (dict) (get $route "service") -}}
{{- default (include "pangolin.namespace" .root) (get $service "namespace") -}}
{{- end -}}

{{- define "pangolin.ingressRoute.dashboard.servicePort" -}}
{{- $route := default (dict) .route -}}
{{- $service := default (dict) (get $route "service") -}}
{{- default .defaultPort (get $service "port") -}}
{{- end -}}

{{- /*
SQLite persistence helpers. `database.mode` is the single source of truth for
whether SQLite is in use; the old `database.sqlite.enabled` toggle was never read
by any template and is gone.
*/ -}}
{{- /*
In-cluster addressing. Badger runs inside the Traefik Pod and resolves the address
Pangolin advertises for its internal API, so a bare Service name only works when
Traefik happens to share the namespace. deployment.traefikNamespace explicitly supports
the opposite, and there the bare name does not resolve at all: Badger then answers
404 page not found for every request while the Traefik dashboard still reports the
router as healthy. server.internal_hostname also drives the Pangolin UI URL and the AI
gateway URL in the same generated configuration, so resolving it once fixes all three.
*/ -}}
{{- define "pangolin.gerbil.hostGateway.enabled" -}}
{{- if (((.Values.gerbil).hostGateway) | default dict).enabled -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pangolin.gerbil.hostGateway.dnsPolicy" -}}
{{- (((.Values.gerbil).hostGateway) | default dict).dnsPolicy | default "ClusterFirstWithHostNet" -}}
{{- end -}}

{{- /*
A required podAffinity against a workload that never schedules leaves the dependent
Pods Pending forever, so co-location is suppressed unless a separate Gerbil Pod really
does run: single mode puts Gerbil in the shared Pod, and a non-normal startupMode keeps
the Deployment at zero replicas.
*/ -}}
{{- define "pangolin.gerbil.colocationSupported" -}}
{{- if and (eq (include "pangolin.gerbil.resourcesEnabled" .) "true") (eq .Values.deployment.mode "multi") (eq (include "pangolin.gerbil.startupMode" .) "normal") -}}
true{{- else -}}false{{- end -}}
{{- end -}}

{{- /* Whether this chart renders a Traefik workload at all. deployment-traefik.yaml is
       gated on exactly these conditions, and NOTES.txt needs the same answer. */ -}}
{{- define "pangolin.traefik.chartManaged" -}}
{{- if and (.Values.traefik).enabled (eq .Values.deployment.type "standalone") (eq .Values.deployment.mode "multi") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pangolin.traefik.colocateWithGerbil" -}}
{{- $mode := (.Values.traefik).colocateWithGerbil | default "auto" -}}
{{- $chartManagedTraefik := eq (include "pangolin.traefik.chartManaged" .) "true" -}}
{{- if not $chartManagedTraefik -}}
false
{{- else if eq (include "pangolin.gerbil.colocationSupported" .) "false" -}}
false
{{- else if eq $mode "required" -}}
true
{{- else if eq $mode "disabled" -}}
false
{{- else -}}
{{- include "pangolin.gerbil.hostGateway.enabled" . -}}
{{- end -}}
{{- end -}}

{{- /*
Deliberately required..., not preferred...: a preferred term lets the scheduler place
Traefik on a node without the tunnel route, which surfaces as a silent 502 rather than a
visible Pending. `namespaces` is explicit because Traefik is frequently deployed to
deployment.traefikNamespace while Gerbil stays in the release namespace, and podAffinity
otherwise defaults to the Pod's own namespace.
*/ -}}
{{- define "pangolin.gerbil.colocationTerm" -}}
labelSelector:
  matchLabels:
    {{- include "pangolin.gerbil.selectorLabels" . | nindent 4 }}
namespaces:
  - {{ include "pangolin.namespace" . }}
topologyKey: kubernetes.io/hostname
{{- end -}}

{{- /* Merged into global.affinity rather than replacing it. */ -}}
{{- define "pangolin.traefik.affinity" -}}
{{- $affinity := deepCopy (.Values.global.affinity | default dict) -}}
{{- if eq (include "pangolin.traefik.colocateWithGerbil" .) "true" -}}
{{- $podAffinity := deepCopy (get $affinity "podAffinity" | default dict) -}}
{{- $required := concat (get $podAffinity "requiredDuringSchedulingIgnoredDuringExecution" | default list) (list (include "pangolin.gerbil.colocationTerm" . | fromYaml)) -}}
{{- $_ := set $podAffinity "requiredDuringSchedulingIgnoredDuringExecution" $required -}}
{{- $_ := set $affinity "podAffinity" $podAffinity -}}
{{- end -}}
{{- if gt (len $affinity) 0 -}}
{{- toYaml $affinity -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.clusterDomain" -}}
{{- .Values.global.clusterDomain | default "cluster.local" -}}
{{- end -}}

{{- define "pangolin.pangolin.serviceFQDN" -}}
{{- printf "%s.%s.svc.%s" (include "pangolin.fullname" .) (include "pangolin.namespace" .) (include "pangolin.clusterDomain" .) -}}
{{- end -}}

{{- define "pangolin.gerbil.serviceFQDN" -}}
{{- printf "%s-gerbil.%s.svc.%s" (include "pangolin.fullname" .) (include "pangolin.namespace" .) (include "pangolin.clusterDomain" .) -}}
{{- end -}}

{{- define "pangolin.server.internalHostname" -}}
{{- $server := (.Values.pangolin.config).server | default dict -}}
{{- $explicit := trim (default "" (get $server "internal_hostname")) -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- include "pangolin.pangolin.serviceFQDN" . -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.sqlite.claimName" -}}
{{- $persistence := ((.Values.database).sqlite | default dict).persistence | default dict -}}
{{- $persistence.existingClaim | default (printf "%s-sqlite" (include "pangolin.fullname" .)) -}}
{{- end -}}

{{- define "pangolin.sqlite.persistenceEnabled" -}}
{{- $persistence := ((.Values.database).sqlite | default dict).persistence | default dict -}}
{{- if and (eq (include "pangolin.db.mode" .) "sqlite") ($persistence.enabled | default false) -}}
true{{- else -}}false{{- end -}}
{{- end -}}

{{- /*
Mount the DIRECTORY holding the database file, not the file itself: SQLite writes
-wal, -shm and journal siblings next to it, and a subPath file mount would leave
those on the container filesystem.
*/ -}}
{{- define "pangolin.sqlite.mountPath" -}}
{{- $path := ((.Values.database).sqlite | default dict).path | default "/app/data/pangolin.db" -}}
{{- $dir := dir $path -}}
{{- if or (not (hasPrefix "/" $path)) (eq $dir ".") (eq $dir "/") (hasSuffix "/" $path) -}}
{{- fail (printf "PANGOLIN-068: database.sqlite.path must be an absolute file path inside a directory that can be mounted, got %q. A relative path yields a relative mountPath, which the API server rejects." $path) -}}
{{- end -}}
{{- $dir -}}
{{- end -}}

{{- /*
Rollout strategy for one workload.

`runtime.updateStrategy` is the chart-wide default and `<component>.deployment.updateStrategy`
overrides it. A workload that cannot have two Pods alive at once is forced to Recreate instead:
that is the case when it holds a PVC which is not ReadWriteMany, because the surged Pod cannot
attach the volume the running one still holds. Surging such a workload under the chart default
(maxSurge 1 / maxUnavailable 0) deadlocks the rollout permanently - the new Pod never becomes
Ready and the old Pod is never allowed to terminate.

StatefulSets take a different schema: maxSurge is not a field there at all and maxUnavailable: 0
is rejected by the API server, so the Deployment shape is translated rather than reused. A
StatefulSet already replaces Pods one at a time without surging, so no Recreate equivalent is needed.
*/ -}}
{{- define "pangolin.persistence.blocksSurge" -}}
{{- $persistence := .persistence | default dict -}}
{{- if $persistence.enabled -}}
{{- $modes := $persistence.accessModes | default (list "ReadWriteOnce") -}}
{{- if not (has "ReadWriteMany" $modes) -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.sqlite.blocksSurge" -}}
{{- $persistence := ((.Values.database).sqlite | default dict).persistence | default dict -}}
{{- if eq (include "pangolin.sqlite.persistenceEnabled" .) "true" -}}
{{- include "pangolin.persistence.blocksSurge" (dict "persistence" (merge (dict "enabled" true) $persistence)) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.gerbil.blocksSurge" -}}
{{- /* In host gateway mode Gerbil binds its ports in the node network namespace, so a
       surged Pod cannot bind them and the rollout would never converge. */ -}}
{{- if eq (include "pangolin.gerbil.hostGateway.enabled" .) "true" -}}true
{{- else -}}
{{- include "pangolin.persistence.blocksSurge" (dict "persistence" ((.Values.gerbil).persistence | default dict)) -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.traefik.blocksSurge" -}}
{{- include "pangolin.persistence.blocksSurge" (dict "persistence" ((.Values.traefik).persistence | default dict)) -}}
{{- end -}}

{{- define "pangolin.updateStrategy" -}}
{{- $root := .root -}}
{{- $workloadType := .workloadType | default "Deployment" -}}
{{- $override := .override | default dict -}}
{{- $blockSurge := .blockSurge | default false -}}
{{- $strategy := dict -}}
{{- if gt (len $override) 0 -}}
{{- $strategy = $override -}}
{{- else if $blockSurge -}}
{{- $strategy = dict "type" "Recreate" -}}
{{- else -}}
{{- $strategy = ($root.Values.runtime.updateStrategy | default dict) -}}
{{- end -}}
{{- if gt (len $strategy) 0 -}}
{{- $type := $strategy.type | default "RollingUpdate" -}}
{{- if eq $workloadType "StatefulSet" -}}
{{- $rollingUpdate := $strategy.rollingUpdate | default dict -}}
updateStrategy:
  type: {{ ternary "OnDelete" "RollingUpdate" (eq $type "OnDelete") }}
{{- if and (ne $type "OnDelete") (hasKey $rollingUpdate "partition") }}
  rollingUpdate:
    partition: {{ $rollingUpdate.partition | int }}
{{- end }}
{{- else -}}
{{- $out := deepCopy $strategy -}}
{{- if eq $type "Recreate" -}}
{{- $_ := unset $out "rollingUpdate" -}}
{{- end -}}
strategy:
  {{- toYaml $out | nindent 2 }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /*
Static Traefik configuration the chart-managed Traefik needs to serve Pangolin.

Pangolin generates routers, services and middlewares and serves them as JSON from
GET /api/v1/traefik-config on its internal API port. A Traefik that only runs the
Kubernetes providers never reads that document, so it starts healthy and 404s every
resource Pangolin created. Every generated router also puts a middleware named `badger`
first; the middleware body is in the generated config, but the plugin behind it has to be
declared statically or Traefik fails the route with `unknown plugin type: badger`.
*/ -}}
{{- /* True whenever this chart renders a Traefik container at all, in either mode.
       deployment-traefik.yaml covers standalone+multi and deployment-single.yaml runs
       Traefik inside the single-mode Pod. */ -}}
{{- define "pangolin.traefik.chartManagedAnyMode" -}}
{{- if and (.Values.traefik).enabled (eq .Values.deployment.type "standalone") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pangolin.traefik.configEndpoint" -}}
{{- $root := . -}}
{{- $tf := $root.Values.traefik | default dict -}}
{{- $explicit := ((($tf.config).httpProvider) | default dict).endpoint | default "" -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- $port := ((($root.Values.pangolin).service).ports).internalApi | default 3001 -}}
{{- printf "http://%s:%v/api/v1/traefik-config" (include "pangolin.pangolin.serviceFQDN" $root) $port -}}
{{- end -}}
{{- end -}}

{{- define "pangolin.traefik.httpProviderEnabled" -}}
{{- $hp := (((.Values.traefik).config).httpProvider) | default dict -}}
{{- $enabled := true -}}
{{- if kindIs "bool" $hp.enabled -}}{{- $enabled = $hp.enabled -}}{{- end -}}
{{- if $enabled -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{- define "pangolin.traefik.staticArgs" -}}
{{- $root := . -}}
{{- $tf := $root.Values.traefik | default dict -}}
{{- $badger := $tf.badger | default dict -}}
{{- if eq (include "pangolin.traefik.httpProviderEnabled" $root) "true" }}
- --providers.http.endpoint={{ include "pangolin.traefik.configEndpoint" $root }}
- --providers.http.pollinterval={{ (($tf.config).httpProvider | default dict).pollInterval | default "5s" }}
{{- end }}
{{- if $badger.enabled }}
- --experimental.plugins.badger.modulename={{ $badger.moduleName | default "github.com/fosrl/badger" }}
- --experimental.plugins.badger.version={{ $badger.version | required "traefik.badger.version is required when traefik.badger.enabled=true" }}
{{- end }}
{{- end -}}

{{- define "pangolin.validate" -}}
{{- $root := . -}}

{{- if and (eq $root.Values.deployment.mode "single") (eq $root.Values.deployment.type "controller") (not $root.Values.controller.enabled) -}}
{{- fail "PANGOLIN-016: deployment.mode=single with deployment.type=controller requires controller.enabled=true." -}}
{{- end -}}

{{- $db := default (dict) $root.Values.database -}}
{{- $gerbil := default (dict) $root.Values.gerbil -}}
{{- $gerbilStartupMode := default "normal" (get $gerbil "startupMode") -}}
{{- if not (has $gerbilStartupMode (list "normal" "delayed" "disabledUntilSetup")) -}}
{{- fail (printf "PANGOLIN-062: gerbil.startupMode must be one of [normal, delayed, disabledUntilSetup], got %q" $gerbilStartupMode) -}}
{{- end -}}

{{- $cnpg := default (dict) (get $db "cloudnativepg") -}}
{{- $cnpgCluster := default (dict) (get $cnpg "cluster") -}}
{{- $cnpgName := default "" (get $cnpgCluster "name") -}}
{{- $cnpgSubchart := default (dict) (index $root.Values "cnpg-cluster") -}}
{{- $subchartCnpgName := default "" (get $cnpgSubchart "fullnameOverride") -}}
{{- if and (eq $root.Values.database.mode "cloudnativepg") (default false (get $cnpgSubchart "enabled")) $cnpgName $subchartCnpgName (ne $cnpgName $subchartCnpgName) (ne $cnpgName "pangolin-db") -}}
{{- fail "PANGOLIN-CNPG: cnpg-cluster.fullnameOverride and database.cloudnativepg.cluster.name must match when cnpg-cluster.enabled=true" -}}
{{- end -}}

{{- $traefik := default (dict) $root.Values.traefik -}}
{{- $traefikConfig := default (dict) (get $traefik "config") -}}
{{- if and (default false (get $traefik "enabled")) (not (default "" (get $traefikConfig "letsencryptEmail"))) -}}
{{- fail "PANGOLIN-014: traefik.config.letsencryptEmail must be set when traefik.enabled=true" -}}
{{- end -}}

{{- $dynamicRouters := default (dict) (get $traefikConfig "dynamicRouters") -}}
{{- $routerHost := default "" (get $dynamicRouters "host") -}}
{{- if and (default false (get $traefik "enabled")) (or (eq $routerHost "") (eq $routerHost "example.com")) -}}
{{- fail "PANGOLIN-043: traefik.config.dynamicRouters.host must be set to a real hostname (must not be empty or example.com) when traefik.enabled=true" -}}
{{- end -}}

{{- $traefikPersistence := default (dict) (get $traefik "persistence") -}}
{{- if and (default false (get $traefik "enabled")) (default false (get $traefikConfig "dashboard")) (not (default false (get $traefikPersistence "enabled"))) -}}
{{- fail "PANGOLIN-015: traefik.persistence.enabled must be true when traefik.config.dashboard=true (ACME state should persist to avoid rate limits on restarts)" -}}
{{- end -}}

{{- if and $root.Values.deployment.installTraefikController (ne $root.Values.deployment.type "controller") -}}
{{- fail "PANGOLIN-012: deployment.installTraefikController=true requires deployment.type=controller" -}}
{{- end -}}

{{- $traefikController := default (dict) $root.Values.traefikController -}}
{{- $tcDeployment := default (dict) (get $traefikController "deployment") -}}
{{- $tcProviders := default (dict) (get $traefikController "providers") -}}
{{- $tcProviderK8sCrd := default (dict) (get $tcProviders "kubernetesCRD") -}}
{{- $tcDeploymentEnabled := true -}}
{{- if hasKey $tcDeployment "enabled" -}}
{{- $tcDeploymentEnabled = (index $tcDeployment "enabled") -}}
{{- end -}}
{{- $tcK8sCrdEnabled := true -}}
{{- if hasKey $tcProviderK8sCrd "enabled" -}}
{{- $tcK8sCrdEnabled = (index $tcProviderK8sCrd "enabled") -}}
{{- end -}}
{{- if and (eq $root.Values.deployment.type "controller") $root.Values.deployment.installTraefikController (eq $tcDeploymentEnabled false) -}}
{{- fail "PANGOLIN-080: traefikController.deployment.enabled=false conflicts with deployment.installTraefikController=true" -}}
{{- end -}}

{{- if and (eq $root.Values.deployment.type "controller") $root.Values.deployment.installTraefikController (eq $tcK8sCrdEnabled false) -}}
{{- fail "PANGOLIN-081: traefikController.providers.kubernetesCRD.enabled=false is not supported (required by controller mode)" -}}
{{- end -}}

{{- $pangolin := default (dict) $root.Values.pangolin -}}
{{- $pangolinCfg := default (dict) (get $pangolin "config") -}}
{{- $pangolinApp := default (dict) (get $pangolinCfg "app") -}}
{{- $pangolinDomains := default (dict) (get $pangolinCfg "domains") -}}
{{- $pangolinGerbil := default (dict) (get $pangolinCfg "gerbil") -}}
{{- $pangolinTraefik := default (dict) (get $pangolinCfg "traefik") -}}
{{- $dashboardURL := default "" (get $pangolinApp "dashboard_url") -}}
{{- $baseEndpoint := default "" (get $pangolinGerbil "base_endpoint") -}}
{{- $devTestMode := eq (default "" $root.Values.database.mode) "sqlite" -}}

{{- if and (not $devTestMode) (not $dashboardURL) -}}
{{- fail "PANGOLIN-055: pangolin.config.app.dashboard_url must be set (non-empty). For development/testing only, set database.mode=sqlite to bypass this validation." -}}
{{- end -}}

{{- if and (not $devTestMode) (eq (len $pangolinDomains) 0) -}}
{{- fail "PANGOLIN-056: pangolin.config.domains must contain at least one domain entry with base_domain and cert_resolver. For development/testing only, set database.mode=sqlite to bypass this validation." -}}
{{- end -}}

{{- if not $devTestMode -}}
{{- range $domainName, $domainCfgRaw := $pangolinDomains -}}
  {{- if not (kindIs "map" $domainCfgRaw) -}}
    {{- fail (printf "PANGOLIN-057: pangolin.config.domains.%s must be a map containing base_domain and cert_resolver." $domainName) -}}
  {{- end -}}
  {{- $domainCfg := default (dict) $domainCfgRaw -}}
  {{- if not (default "" (get $domainCfg "base_domain")) -}}
    {{- fail (printf "PANGOLIN-058: pangolin.config.domains.%s.base_domain must be set (non-empty)." $domainName) -}}
  {{- end -}}
  {{- if not (default "" (get $domainCfg "cert_resolver")) -}}
    {{- fail (printf "PANGOLIN-059: pangolin.config.domains.%s.cert_resolver must be set (non-empty)." $domainName) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- if and (not $devTestMode) (not $baseEndpoint) -}}
{{- fail "PANGOLIN-060: pangolin.config.gerbil.base_endpoint must be set (non-empty). For development/testing only, set database.mode=sqlite to bypass this validation." -}}
{{- end -}}

{{- $ingressRoute := default (dict) (get $pangolin "ingressRoute") -}}
{{- $dashboardIngress := default (dict) (get $ingressRoute "dashboard") -}}
{{- $dashboardIngressEnabled := true -}}
{{- if hasKey $dashboardIngress "enabled" -}}
{{- $dashboardIngressEnabled = (get $dashboardIngress "enabled") -}}
{{- end -}}
{{- if and (eq $root.Values.deployment.type "controller") $dashboardIngressEnabled -}}
{{- $dashboardHost := trim (include "pangolin.ingressRoute.dashboard.host" $root) -}}
{{- if not $dashboardHost -}}
{{- fail "PANGOLIN-063: pangolin.ingressRoute.dashboard.enabled=true requires a host. Set pangolin.ingressRoute.dashboard.host or provide a parseable pangolin.config.app.dashboard_url." -}}
{{- end -}}

{{- $routes := default (dict) (get $dashboardIngress "routes") -}}
{{- $apiRoute := default (dict) (get $routes "api") -}}
{{- $dashboardRoute := default (dict) (get $routes "dashboard") -}}
{{- $apiEnabled := true -}}
{{- if hasKey $apiRoute "enabled" -}}
{{- $apiEnabled = (get $apiRoute "enabled") -}}
{{- end -}}
{{- $dashboardEnabled := true -}}
{{- if hasKey $dashboardRoute "enabled" -}}
{{- $dashboardEnabled = (get $dashboardRoute "enabled") -}}
{{- end -}}
{{- if and (not $apiEnabled) (not $dashboardEnabled) -}}
{{- fail "PANGOLIN-064: pangolin.ingressRoute.dashboard.routes.api.enabled and routes.dashboard.enabled cannot both be false." -}}
{{- end -}}

{{- $allowCrossNamespaceServices := default false (get $dashboardIngress "allowCrossNamespaceServices") -}}
{{- if not $allowCrossNamespaceServices -}}
{{- $releaseNamespace := include "pangolin.namespace" $root -}}
{{- if $apiEnabled -}}
{{- $apiServiceNamespace := include "pangolin.ingressRoute.dashboard.serviceNamespace" (dict "root" $root "route" $apiRoute) -}}
{{- if ne $apiServiceNamespace $releaseNamespace -}}
{{- fail (printf "PANGOLIN-066: cross-namespace Traefik service references are disabled. Set pangolin.ingressRoute.dashboard.allowCrossNamespaceServices=true to allow routes.api.service.namespace=%q (Traefik kubernetesCRD provider must also allow cross-namespace references)." $apiServiceNamespace) -}}
{{- end -}}
{{- end -}}
{{- if $dashboardEnabled -}}
{{- $dashboardServiceNamespace := include "pangolin.ingressRoute.dashboard.serviceNamespace" (dict "root" $root "route" $dashboardRoute) -}}
{{- if ne $dashboardServiceNamespace $releaseNamespace -}}
{{- fail (printf "PANGOLIN-066: cross-namespace Traefik service references are disabled. Set pangolin.ingressRoute.dashboard.allowCrossNamespaceServices=true to allow routes.dashboard.service.namespace=%q (Traefik kubernetesCRD provider must also allow cross-namespace references)." $dashboardServiceNamespace) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- $tls := default (dict) (get $dashboardIngress "tls") -}}
{{- $tlsEnabled := true -}}
{{- if hasKey $tls "enabled" -}}
{{- $tlsEnabled = (get $tls "enabled") -}}
{{- end -}}
{{- if $tlsEnabled -}}
{{- $tlsSecretName := trim (default "" (get $tls "secretName")) -}}
{{- $tlsCertResolver := trim (default "" (get $tls "certResolver")) -}}
{{- if and (not $tlsCertResolver) (not $tlsSecretName) -}}
{{- $tlsCertResolver = trim (default "" (get $pangolinTraefik "cert_resolver")) -}}
{{- end -}}
{{- if and $tlsCertResolver $tlsSecretName -}}
{{- fail "PANGOLIN-065: pangolin.ingressRoute.dashboard.tls.certResolver and tls.secretName are mutually exclusive. Set exactly one TLS mode." -}}
{{- end -}}
{{- if and (not $tlsCertResolver) (not $tlsSecretName) -}}
{{- fail "PANGOLIN-065: pangolin.ingressRoute.dashboard.tls.enabled=true requires exactly one TLS mode. Set tls.certResolver or tls.secretName." -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- $bp := default (dict) (get (default (dict) $root.Values.pangolin) "blueprints") -}}
{{- $bpEnabled := default false (get $bp "enabled") -}}
{{- $bpCm := default (dict) (get $bp "configMap") -}}
{{- $bpCmCreate := default false (get $bpCm "create") -}}
{{- $bpExistingCm := default "" (get $bp "existingConfigMap") -}}
{{- $bpFiles := default (dict) (get $bp "files") -}}
{{- $bpEs := default (dict) (get $bp "environmentSecret") -}}
{{- $bpEsCreate := default false (get $bpEs "create") -}}
{{- $bpExistingEs := default "" (get $bp "existingEnvironmentSecret") -}}
{{- $bpEnv := default (dict) (get $bp "environment") -}}

{{- if and $bpEnabled (not $bpCmCreate) (not $bpExistingCm) -}}
{{- /* blueprints.enabled=true but no blueprint source is configured — warn via a clear error */ -}}
{{- fail "PANGOLIN-050: pangolin.blueprints.enabled=true but no blueprint source is configured. Set configMap.create=true (with files) or existingConfigMap to provide blueprint YAML definitions." -}}
{{- end -}}

{{- if and $bpCmCreate $bpExistingCm -}}
{{- fail "PANGOLIN-051: pangolin.blueprints.configMap.create=true and pangolin.blueprints.existingConfigMap are mutually exclusive. Use one or the other." -}}
{{- end -}}

{{- if and $bpCmCreate (not $bpFiles) -}}
{{- fail "PANGOLIN-052: pangolin.blueprints.configMap.create=true but pangolin.blueprints.files is empty. Provide at least one blueprint file." -}}
{{- end -}}

{{- if and $bpEsCreate $bpExistingEs -}}
{{- fail "PANGOLIN-053: pangolin.blueprints.environmentSecret.create=true and pangolin.blueprints.existingEnvironmentSecret are mutually exclusive. Use one or the other." -}}
{{- end -}}

{{- if and $bpEsCreate (not $bpEnv) -}}
{{- fail "PANGOLIN-054: pangolin.blueprints.environmentSecret.create=true but pangolin.blueprints.environment is empty. Provide at least one environment variable." -}}
{{- end -}}

{{- /* PANGOLIN-061: external mode requires a database Secret source */ -}}
{{- if eq (include "pangolin.db.mode" $root) "external" -}}
{{- $extConn := default (dict) (get $db "connection") -}}
{{- $ext := default (dict) (get $db "external") -}}
{{- $extGen := default (dict) (get $ext "generatedSecret") -}}
{{- $hasExisting := or (get $extConn "existingSecretName") (get $ext "existingSecretName") -}}
{{- $hasCreated := (get $extGen "create") | default false -}}
{{- if and (not $hasExisting) (not $hasCreated) -}}
{{- fail "PANGOLIN-061: database.mode=external requires a database connection Secret. Either set database.connection.existingSecretName (user-managed Secret) or set database.external.generatedSecret.create=true with database.external.generatedSecret.connectionString or host/username/password/port/database values (chart-managed Secret)." -}}
{{- end -}}
{{- end -}}

{{- /* PANGOLIN-067: the controller cannot reconcile Traefik CRDs without egress to the
       Kubernetes API. Only the contradictory state fails - asking for the rule while
       leaving it no destination - because that is the one case the chart cannot resolve
       and the one that used to surface as a controller crash-loop instead. */ -}}
{{- $np := default (dict) $root.Values.networkPolicy -}}
{{- $npEnabled := true -}}
{{- if hasKey $np "enabled" -}}
{{- $npEnabled = get $np "enabled" -}}
{{- end -}}
{{- if and $npEnabled (eq $root.Values.deployment.type "controller") (default false (get (default (dict) $root.Values.controller) "enabled")) -}}
{{- $npControllerEgress := default (dict) (get (default (dict) (get $np "controller")) "egress") -}}
{{- $npKubeApi := default (dict) (get $npControllerEgress "kubernetesApi") -}}
{{- $npControllerEgressEnabled := true -}}
{{- if hasKey $npControllerEgress "enabled" -}}
{{- $npControllerEgressEnabled = get $npControllerEgress "enabled" -}}
{{- end -}}
{{- $npKubeApiEnabled := true -}}
{{- if hasKey $npKubeApi "enabled" -}}
{{- $npKubeApiEnabled = get $npKubeApi "enabled" -}}
{{- end -}}
{{- if and $npControllerEgressEnabled $npKubeApiEnabled -}}
{{- $hasLegacyKubeApi := or (ne (default "" (get $npKubeApi "cidr")) "") (gt (len (default list (get $np "kubernetesApiCIDRs"))) 0) -}}
{{- $hasKubeApiEndpoints := false -}}
{{- range $i, $endpoint := (default list (get $npKubeApi "endpoints")) -}}
{{- $cidrs := default list (get $endpoint "cidrs") -}}
{{- if eq (len $cidrs) 0 -}}
{{- fail (printf "PANGOLIN-067: networkPolicy.controller.egress.kubernetesApi.endpoints[%d] has no cidrs. An entry without cidrs is not a destination and was previously skipped in silence, so a misspelled key narrowed the policy without any error. Every entry needs cidrs: [ ... ]." $i) -}}
{{- end -}}
{{- range $cidr := $cidrs -}}
{{- if not (regexMatch "^[0-9A-Fa-f:.]+/[0-9]{1,3}$" (printf "%v" $cidr)) -}}
{{- fail (printf "PANGOLIN-067: networkPolicy.controller.egress.kubernetesApi.endpoints[%d] contains %q, which is not an address/prefix. Kubernetes rejects an ipBlock without a prefix length, so write for example 10.43.0.1/32 rather than a bare address." $i $cidr) -}}
{{- end -}}
{{- end -}}
{{- if and (gt (len (default list (get $endpoint "except"))) 0) (gt (len $cidrs) 1) -}}
{{- fail (printf "PANGOLIN-067: networkPolicy.controller.egress.kubernetesApi.endpoints[%d] combines except with %d cidrs. Kubernetes requires every except range to sit inside the cidr it belongs to, and the chart would copy this except onto all of them. Split the entry so each cidr carries its own except." $i (len $cidrs)) -}}
{{- end -}}
{{- range $port := (default list (get $endpoint "ports")) -}}
{{- if or (lt (int $port) 1) (gt (int $port) 65535) -}}
{{- fail (printf "PANGOLIN-067: networkPolicy.controller.egress.kubernetesApi.endpoints[%d] declares port %v, which is outside 1-65535." $i $port) -}}
{{- end -}}
{{- end -}}
{{- $hasKubeApiEndpoints = true -}}
{{- end -}}
{{- if not (or $hasLegacyKubeApi $hasKubeApiEndpoints) -}}
{{- fail "PANGOLIN-067: networkPolicy.controller.egress.kubernetesApi.enabled=true but no destination is configured, which would leave the controller unable to reach the Kubernetes API. Populate networkPolicy.controller.egress.kubernetesApi.endpoints[].cidrs (the chart default covers RFC1918/CGNAT/link-local on TCP 443 and 6443), or set kubernetesApi.enabled=false and supply the rule yourself via networkPolicy.controller.extraEgress." -}}
{{- end -}}
{{- end -}}
{{- /* PANGOLIN-069: SQLite is a single-writer file database. Two Pangolin Pods writing the
       same file corrupts it, and the chart cannot prevent that once the volume is shared. */ -}}
{{- if eq (include "pangolin.sqlite.persistenceEnabled" $root) "true" -}}
{{- $sqliteReplicas := int ((($root.Values.pangolin).replicaCount) | default 1) -}}
{{- if gt $sqliteReplicas 1 -}}
{{- fail (printf "PANGOLIN-069: pangolin.replicaCount is %d while database.mode=sqlite with persistence enabled. SQLite has a single writer, so a shared volume across replicas corrupts the database. Keep replicaCount at 1, or move to database.mode=cloudnativepg or external for a replicated deployment." $sqliteReplicas) -}}
{{- end -}}
{{- /* PANGOLIN-070: the chart's own SQLite volume and an identically named extraVolume would
       render two entries with the same name, which the API server rejects. */ -}}
{{- $sqliteMountPath := include "pangolin.sqlite.mountPath" $root -}}
{{- range $volume := (($root.Values.pangolin).extraVolumes | default list) -}}
{{- if eq ($volume.name | default "") "pangolin-sqlite" -}}
{{- fail "PANGOLIN-070: pangolin.extraVolumes contains a volume named pangolin-sqlite, which is the name the chart uses for the SQLite volume. Rename your volume: two volumes with one name make the Pod spec invalid." -}}
{{- end -}}
{{- end -}}
{{- range $mount := (($root.Values.pangolin).extraVolumeMounts | default list) -}}
{{- if eq ($mount.mountPath | default "") $sqliteMountPath -}}
{{- fail (printf "PANGOLIN-070: pangolin.extraVolumeMounts already mounts %q, which is where the chart mounts the SQLite directory derived from database.sqlite.path. Two mounts on one path make the Pod spec invalid; choose a different path or a different database.sqlite.path." $sqliteMountPath) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- /* Host gateway mode: fail on the combinations that cannot work rather than letting
       them surface as a Pending Pod or a silent 502. */ -}}
{{- if eq (include "pangolin.gerbil.hostGateway.enabled" $root) "true" -}}
{{- $hgGerbil := default (dict) $root.Values.gerbil -}}
{{- if ne $root.Values.deployment.mode "multi" -}}
{{- fail "PANGOLIN-071: gerbil.hostGateway.enabled=true requires deployment.mode=multi. In single mode Gerbil shares a Pod with Pangolin, so hostNetwork would bind every component's ports on the node." -}}
{{- end -}}
{{- if not (default false (get $hgGerbil "enabled")) -}}
{{- fail "PANGOLIN-072: gerbil.hostGateway.enabled=true requires gerbil.enabled=true." -}}
{{- end -}}
{{- if gt (int (default 1 (get $hgGerbil "replicaCount"))) 1 -}}
{{- fail "PANGOLIN-073: gerbil.hostGateway.enabled=true requires gerbil.replicaCount=1. Gerbil binds its WireGuard and internal API ports on the node, so a second replica cannot start alongside it." -}}
{{- end -}}
{{- $hgNamespace := default (dict) $root.Values.namespace -}}
{{- $hgPodSecurity := default (dict) (get $hgNamespace "podSecurity") -}}
{{- if and (default false (get $hgNamespace "create")) (ne (default "" (get $hgPodSecurity "enforce")) "privileged") -}}
{{- fail "PANGOLIN-074: gerbil.hostGateway.enabled=true requires namespace.podSecurity.enforce=privileged when the chart creates the namespace. Pod Security Admission level baseline forbids hostNetwork." -}}
{{- end -}}
{{- /* PANGOLIN-075: a hostNetwork Pod sources from the node IP, so the Gerbil -> Pangolin
       internal-API rule becomes an ipBlock. The chart cannot discover node addresses at
       template time and any guess would admit far more than the node. */ -}}
{{- $hgNp := default (dict) $root.Values.networkPolicy -}}
{{- $hgNpEnabled := true -}}
{{- if hasKey $hgNp "enabled" -}}
{{- $hgNpEnabled = get $hgNp "enabled" -}}
{{- end -}}
{{- if $hgNpEnabled -}}
{{- $hgNpGerbil := default (dict) (get $hgNp "gerbil") -}}
{{- $hgNodeCidrs := default list (get (default (dict) (get $hgNpGerbil "hostGateway")) "nodeCIDRs") -}}
{{- if eq (len $hgNodeCidrs) 0 -}}
{{- fail "PANGOLIN-075: gerbil.hostGateway.enabled=true with networkPolicy.enabled=true requires networkPolicy.gerbil.hostGateway.nodeCIDRs. Gerbil runs with hostNetwork, so its traffic sources from the node IP and no podSelector matches it; without node address blocks this chart's own policy blackholes Gerbil's --remoteConfig polling. Set your node addresses, e.g. kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}'. Do not use the private ranges wholesale - they contain every mainstream Pod CIDR." -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
