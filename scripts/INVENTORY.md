# Scripts inventory

This repository includes helper scripts under `scripts/`.

## Consolidated Scripts (2026-03)

The following 3 scripts provide all the functionality previously spread across 11 scripts:

---

## `scripts/test.sh`

- **Area:** CI / Developer test runner
- **Short:** Comprehensive test runner for Helm charts
- **Details:**
  - Runs `helm lint` with values.dev.yaml
  - Runs `helm unittest` with all test files
  - Renders templates for all example values files
  - Runs `yamllint` on Chart.yaml, values.yaml, and examples
  - Tests all matrix scenarios in `tests/values-matrix/`
  - Supports `--with-metrics` flag for metrics override tests
  - Supports `--with-kubeconform` flag for K8s API validation
  - Supports `--all-charts` flag to test all charts under `./charts`
- **Requires:** `helm`, `helm-unittest`, optional `yamllint`, optional `kubeconform`

**Usage:**

```bash
./scripts/test.sh                      # Test default chart (newt)
./scripts/test.sh --all-charts         # Test all charts
./scripts/test.sh --with-metrics       # Include metrics override tests
./scripts/test.sh --with-kubeconform   # Include K8s validation
./scripts/test.sh -c charts/my-chart    # Test specific chart
```

---

## `scripts/render.sh`

- **Area:** Rendered artifacts generation
- **Short:** Generates rendered manifests for human review/diffing
- **Details:**
  - Renders `examples/values/*.yaml` files to `tmp/renders/examples/<chart>/`
  - Renders `tests/values-matrix/*.yaml` files to `tmp/renders/matrix/<chart>/`
  - Supports `--generate` flag to generate example values from overlays
  - Can render examples and/or matrix scenarios via flags
- **Requires:** `helm`, optional `yq` and `jq` for `--generate`

**Usage:**

```bash
./scripts/render.sh                    # Render examples and matrix (default)
./scripts/render.sh --examples         # Render only examples
./scripts/render.sh --matrix           # Render only matrix
./scripts/render.sh --generate         # Generate example values from overlays
./scripts/render.sh -c charts/newt     # Render specific chart
```

---

## `scripts/values.sh`

- **Area:** Values management / Release constraints
- **Short:** Syncs and enforces values file constraints
- **Details:**
  - `sync` command: Merges values.dev.yaml + values.protected.yaml into values.yaml
  - `enforce` command: Ensures schema header and forces protected keys to empty strings
- **Requires:** `yq` (mikefarah v4)

**Usage:**

```bash
./scripts/values.sh sync                      # Sync default chart (newt)
./scripts/values.sh sync -c charts/my-chart   # Sync specific chart
./scripts/values.sh enforce values.yaml       # Enforce constraints on a values file
```

---

## `scripts/helm-docs.sh`

- **Area:** Documentation
- **Short:** Auto-generate chart documentation using helm-docs
- **Details:**
  - Runs `helm-docs` to generate or update README.md files for charts under `charts/`.
  - Intended to be idempotent and safe to run in CI before committing documentation updates.
  - Can be run for a single chart by passing a chart path via `-c`/`--chart`.
- **Requires:** `helm-docs` (see the helm-docs project on GitHub)

**Usage:**

```bash
./scripts/helm-docs.sh                 # Generate docs for all charts
./scripts/helm-docs.sh -c charts/newt  # Generate docs for a specific chart
```

---

## `scripts/setup-tools.sh`

- **Area:** Developer environment setup
- **Short:** Installs and verifies local tooling required to work with the repository
- **Details:**
  - Installs or verifies presence of required CLI tools (for example: `helm`, `helm-unittest`, `helm-docs`, `yq`, `kubeconform`).
  - Optionally installs tools into the user's PATH or prints installation instructions when not run with elevated permissions.
  - Provides a `--check` mode to only verify versions without performing installs.
  - Includes helpful notes about recommended versions and links to upstream installation docs.
- **Requires:** `curl`/`wget`, optional package managers (brew/apt/choco) depending on OS

**Usage:**

```bash
./scripts/setup-tools.sh         # Attempt to install or verify tools interactively
./scripts/setup-tools.sh --check # Only verify tooling and print versions
```

## Migration Guide

| Old Script                       | New Script(s)                   |
| -------------------------------- | ------------------------------- |
| `test-chart.sh`                  | `test.sh`                       |
| `test-render-matrix.sh`          | `test.sh`                       |
| `test-newt-matrix.sh`            | `test.sh`                       |
| `metrics-override-tests.sh`      | `test.sh --with-metrics`        |
| `ci-helm-examples.sh`            | `render.sh --examples`          |
| `render-examples-templates.sh`   | `render.sh --examples`          |
| `gen-rendered-scenarios.sh`      | `render.sh --examples --matrix` |
| `gen-examples.sh`                | `render.sh --generate`          |
| `sync-values.sh`                 | `values.sh sync`                |
| `sync-values-default.sh`         | `values.sh sync` (prefer sync)  |
| `enforce-release-constraints.sh` | `values.sh enforce`             |

---

## Functionality Parity Notes

- **helm lint**: Covered by `test.sh`
- **helm unittest**: Covered by `test.sh`
- **yamllint**: Covered by `test.sh`
- **matrix rendering**: Covered by `test.sh` and `render.sh`
- **kubeconform validation**: Covered by `test.sh --with-kubeconform`
- **metrics override tests**: Covered by `test.sh --with-metrics`
- **example rendering**: Covered by `render.sh`
- **values syncing**: Covered by `values.sh sync`
- **release constraints**: Covered by `values.sh enforce`
