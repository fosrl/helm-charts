<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this repository are documented in this file.

This changelog is chart-scoped to support multiple charts over time.

---

## Pangolin Chart (`charts/pangolin`)

### Unreleased

- No changes yet.

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

- No changes yet.

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
