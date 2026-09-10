<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this repository are documented in this file.

This changelog is chart-scoped to support multiple charts over time.

---

## Pangolin Chart (`charts/pangolin`)

### Unreleased

#### Fixed

- `pangolin.extraVolumes` / `pangolin.extraVolumeMounts` no longer abort `helm template`.
  The `- {{- toYaml . | nindent N }}` pattern let the whitespace strip eat the list dash
  ([#25](https://github.com/fosrl/helm-charts/issues/25)).
- `networkPolicy.controller.egress.kubernetesApi` now renders a rule by default, so
  `deployment.type=controller` no longer ships with the controller unable to reach the
  Kubernetes API ([#22](https://github.com/fosrl/helm-charts/issues/22)).
- The dashboard `next` port (3002) is now allowed whenever the chart-managed dashboard
  IngressRoute targets it, instead of being blocked by a default that could drift
  ([#22](https://github.com/fosrl/helm-charts/issues/22)).
- `gerbil.startupMode=disabledUntilSetup` is accepted again. A duplicate PANGOLIN-062
  check rejected the value its own schema enum advertised.
- Explicit `false` and `0` now stick for `pangolin.config.app.telemetry.anonymous_usage`,
  `pangolin.config.app.notifications.*`, `pangolin.config.server.trust_proxy` and
  `pangolin.config.email.smtp_tls_reject_unauthorized`. `| default` collapsed them back
  onto the default, so telemetry could not be turned off.

#### Added

- `database.sqlite.persistence.*` is implemented: it renders a PVC and mounts the
  directory holding `database.sqlite.path` in both `multi` and `single` mode. The values
  existed and were documented but no template read them
  ([#25](https://github.com/fosrl/helm-charts/issues/25)).
- `networkPolicy.controller.egress.kubernetesApi.endpoints` accepts CIDR groups with
  their own port lists, covering both pre-DNAT (Service ClusterIP:443) and post-DNAT
  (node IP:6443) CNI behaviour.
- `PANGOLIN-067` fails the render when Kubernetes API egress is enabled with no
  destination configured.
- The Pangolin 1.22 configuration surface: `server.{ai_gateway_port, ai_gateway_override,
  badger_override, remote_headers.*, enable_ai_gateway_client_ip_header, maxmind_db_path,
  maxmind_asn_path}`, `flags.{disable_virtual_api_keys_ui, enable_acme_cert_sync,
  disable_private_http_placeholder}` and `traefik.{site_types, static_domains,
  rate_limit}`. Optional keys are emitted only when set so Pangolin's defaults apply.
- `pangolin.service.ports.aiGateway` (3005), exposed on the Service and the workload, with
  an opt-in `networkPolicy.pangolin.externalIngress.aiGateway` rule. The rendered
  `server.*_port` values now derive from these ports so they cannot drift.

#### Changed

- Bumped Pangolin appVersion to `1.22.2`, the Gerbil image to `1.5.1` and the chart to
  `0.1.0-alpha.2`. The chart remains a prerelease.
- **BREAKING:** `pangolin.config.gerbil.use_subdomain` is removed - Pangolin dropped it
  from its config schema, so the chart was emitting a key upstream no longer knows.
- **BREAKING:** the top-level `monitoring.*` tree and `runtime.hostNetwork` are removed.
  No template ever read either of them. The two removals fail differently on upgrade
  because the schema is strict at the root only: a leftover `monitoring:` block aborts
  `helm upgrade` with `at '': additional properties 'monitoring' not allowed`, while a
  leftover `runtime.hostNetwork` is accepted and does nothing. Delete both from your
  values file. If you need host networking for Gerbil, use `gerbil.hostGateway.*`.
- **BREAKING:** `database.sqlite.enabled` is removed. It was never read by any template;
  `database.mode=sqlite` is and remains the only switch.
- `networkPolicy.controller.egress.kubernetesApi.cidr` and
  `networkPolicy.kubernetesApiCIDRs` are deprecated in favour of `endpoints`. Both are
  still honoured and take precedence over `endpoints`, so an existing scoped allow-list
  is never widened by an upgrade.
- `networkPolicy.pangolin.externalIngress.next` defaults to `null` (derive from the
  dashboard route). An explicit boolean still wins.
- `networkPolicy.pangolin.externalIngress.aiGateway` defaults to `true`. Traefik reaches
  the AI gateway by connecting to port 3005 on the Pangolin Pod, so the previous `false`
  blocked every AI gateway route while the port was published on the Service.

---

### 0.1.0-alpha.1 - 2026-05-11

#### Changed

- Bumped Pangolin chart version to `0.1.0-alpha.1` and app version to `1.18.3`.
- Updated Artifact Hub image references to Pangolin `1.18.3` (including PostgreSQL variant) for both Docker Hub and GHCR.

---

### 0.1.0-alpha.0 - 2026-05-08

#### Added

- Initial alpha release of the Pangolin Helm chart (`charts/pangolin`).

---

## Newt Chart (`charts/newt`)

### Unreleased

#### Fixed

- Enabling metrics now actually exposes them. The chart never emitted
  `NEWT_METRICS_PROMETHEUS_ENABLED`, the Service published 2112 while targeting 9090, and
  `newt.effectiveMetrics` returned Go's map-print form instead of JSON so the metrics
  container port was never declared and per-instance metrics overrides were inert
  ([#16](https://github.com/fosrl/helm-charts/issues/16)).
- `newtInstances[].resources` is honoured again. It was gated behind
  `allowGlobalOverride` while `global.resources` shipped non-empty, so the documented
  per-instance key was a no-op on every default install
  ([#23](https://github.com/fosrl/helm-charts/issues/23)).
- `newtInstances[].extraVolumes` / `extraVolumeMounts` no longer render stray bare list
  dashes ([#25](https://github.com/fosrl/helm-charts/issues/25)).

#### Added

- Per-instance `disableSSH`, `useNativeMainInterface` / `interfaceMain`, `preferEndpoint`,
  `udpProxyIdleTimeout` and `authDaemon.*`, covering the options Newt gained through
  1.16. `authDaemon.keySecretName`/`keySecretKey` reference the pre-shared key from a
  Secret; it is never inlined into the manifest.

#### Changed

- `global.resources` and `newtInstances[].resources` default to `{}`. The chart no longer
  imposes CPU or memory requests/limits, and the `resources` key is omitted entirely when
  both are empty so LimitRange and namespace defaults apply. Commented examples are
  provided in `values.yaml` ([#23](https://github.com/fosrl/helm-charts/issues/23)).
- The resources schema accepts an empty map, `null`, requests-only, limits-only,
  fractional CPU and extended resources. It previously typed every field as a bare string
  with a `^[0-9]+m?$` pattern, which rejected `null`.
- `global.metrics.adminAddr` is authoritative for the metrics port; the container port,
  Service `targetPort` and scrape annotation all derive from it. `global.metrics.port` is
  deprecated but still honoured as the listen port so existing values files are unchanged.
- Bumped Newt appVersion to `1.16.0` and the chart to `1.6.0`.
- Stopped emitting `ACCEPT_CLIENTS`, `KEEP_INTERFACE` and `GENERATE_AND_SAVE_KEY_TO` and
  their CLI flags. None exist in any Newt release this chart can select - `ACCEPT_CLIENTS`
  was replaced by `DISABLE_CLIENTS` in Newt 1.7.0 - so the binary already ignored them and
  removing them changes no behaviour. The values keys are kept: `acceptClients` still
  gates the client Service and NetworkPolicy rule, and the other two are documented as
  inert.

---

### 1.5.0 - 2026-05-11

#### Changed

- Bumped Newt chart version to `1.5.0` and app version to `1.12.5`.
- Updated Artifact Hub image references to Newt `1.12.5` for both Docker Hub and GHCR.

---

### 1.4.0 - 2026-05-08

#### Added

- Added support for namespace creation and Pod Security Admission labels, including per-instance namespace overrides.
- Added per-instance ServiceAccount override support (create/name/automount) when global override is enabled.
- Added `tests.enabled` controls (global and per-instance) to manage tester UDP port exposure.
- Added helper logic for effective namespace, namespace labels, PSA labels, tests enablement, and metrics admin port resolution.
- Added `auth.createSecret` and `auth.envVarsDirect` authentication modes for inline/development workflows.
- Added runtime NOTES warnings for insecure inline credential patterns.
- Added explicit namespace rendering for generated ConfigMaps, Services, Secrets, and ServiceAccounts in multi-namespace deployments.
- Added GHCR OCI publish step in release automation for packaged chart artifacts.

#### Changed

- Bumped Newt chart version to `1.4.0` and app version to `1.12.3`.
- Changed default RBAC behavior to least-privilege by setting `rbac.create=false`.
- Changed tester port behavior to disabled by default unless enabled via tests settings or legacy tester port config.
- Refactored Role/RoleBinding rendering to create one pair per unique effective namespace when `clusterRole=false`.
- Updated metrics defaults and behavior around `adminAddr` (default `:2112`), including metrics Service default port alignment.
- Increased default `revisionHistoryLimit` from `3` to `10`.
- Hardened release workflow for tag-driven releases, expanded permissions, and improved signing/publishing flow.

#### Fixed

- Fixed metrics env var rendering to avoid YAML block sequence errors.
- Fixed OTLP protocol enum usage to `http/protobuf`.
- Fixed container ports and Prometheus annotations to follow `adminAddr`-driven metrics exposure.
- Fixed NetworkPolicy tester ingress generation to avoid opening tester UDP rules when tester exposure is disabled.
- Fixed secret generation in create-secret mode to include endpoint/id/secret credentials consistently.
- Fixed auth validation for partial inline credentials and conflicting auth mode combinations.

#### Removed

- Removed implicit default RBAC creation; RBAC is now opt-in.
- Removed the broad all-env deployment test from active execution and retained it as a disabled fixture.

---

### 1.3.0 - 2026-04-12

#### Added

- Added support for Newt 1.11 provisioning via `NEWT_PROVISIONING_KEY` and `NEWT_NAME` (backward compatible with existing ID/secret installs).
- Added provisioning blueprint support via `PROVISIONING_BLUEPRINT_FILE`.
- Automatically generates ConfigMaps for provisioning blueprints.
- Added deployment-level validation for provisioning blueprint configuration.
- Added writable config persistence support using either `emptyDir` or an existing PVC.
- Automatically wires `CONFIG_FILE` for persistent configuration setups.
- Added optional pprof enablement via `NEWT_PPROF_ENABLED`.
- Added helm-unittest coverage for provisioning blueprint ConfigMap rendering.

#### Changed

- Updated documentation and examples for Newt 1.11.0, including upstream behavior notes.
- Updated helm-unittest assertions to current syntax (`exists` / `notExists`).
- Improved chart validation and cross-platform compatibility in CI workflows.

---

### 1.2.0 - 2026-03-03

#### Added

- Added development values file support for CI workflows.
- Added new configuration options:
  - `port`
  - `noCloud`
  - `disableClients`
  - `blueprintFile`
  - `enforceHcCert`
- Added enhanced metrics configuration options:
  - `adminAddr`
  - `asyncBytes`
  - `region`
  - `otlpEnabled`
- Added OpenTelemetry (OTEL) configuration support.
- Added split PEM mTLS support (`mode: pem`) with:
  - `TLS_CLIENT_CERT`
  - `TLS_CLIENT_KEY`
  - `TLS_CLIENT_CAS`
- Added Artifact Hub metadata annotations (support, documentation, links).
- Added Helm chart provenance signing support.
- Added resource requests and limits for test workloads.

#### Changed

- Reworked NetworkPolicy templates to consistently honor both:
  - `global.networkPolicy.*`
  - chart-local `networkPolicy.*`
- Reworked PodDisruptionBudget templates to consistently honor both:
  - `global.podDisruptionBudget.*`
  - chart-local `podDisruptionBudget.*`
- Improved test scripts for connection and readiness checks with better error handling.
- Updated documentation and examples for Newt 1.10.1.

#### Fixed

- Fixed JSON Schema generation failures caused by malformed `# @schema` annotations in `values.yaml`.
- Fixed Helm template parsing/runtime errors caused by corrupted helper templates (PR #12).
- Fixed versioning inconsistencies introduced by a previously merged change set (PR #12).
- Fixed metrics Service rendering when `global.metrics.service.enabled=true` by preserving root context across `range`.
- Fixed Helm test `ImagePullBackOff` by:
  - Updating default kubectl test image to `registry.k8s.io/kubectl`
  - Honoring `global.tests.image.*`
  - Resolving shell compatibility issues

---

### 1.1.0 - 2025-09-19

#### Changed

- Updated Kubernetes compatibility to `>=1.28.15-0`.
- Added and improved Artifact Hub metadata:
  - `source`
  - `homepage`
  - `documentation`
  - screenshot annotations

---

### 1.0.0 - 2025-09-13

#### Added

- Initial stable release of the Newt Helm chart (`charts/newt`).
