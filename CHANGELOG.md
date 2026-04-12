<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this repository are documented in this file.

This changelog is chart-scoped to support multiple charts over time.

---

## Newt Chart (`charts/newt`)

### Unreleased

- No changes yet.

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
