CHART_DIR := charts/newt
VALUES_DEV := $(CHART_DIR)/values.dev.yaml
EXAMPLE_VALUES := $(wildcard $(CHART_DIR)/examples/values/*.yaml)
EXAMPLE_TEMPLATES_DIR := $(CHART_DIR)/examples/renderd-manifests

.PHONY: sync schema schema-only schema-dev examples examples-templates docs all lint unittest unittest-examples pre-commit helm-test test test-matrix

# Sync values.yaml from dev + protected
sync:
	./scripts/values.sh sync -c $(CHART_DIR)

schema: sync
	helm schema -f $(CHART_DIR)/values.yaml -o $(CHART_DIR)/values.schema.json --config $(CHART_DIR)/.schema.yaml

# Generate schema directly from values.yaml without running sync
schema-only:
	helm schema -f $(CHART_DIR)/values.yaml -o $(CHART_DIR)/values.schema.json --config $(CHART_DIR)/.schema.yaml

schema-dev:
	helm schema -f $(CHART_DIR)/values.dev.yaml -o $(CHART_DIR)/values.schema.dev.json --config $(CHART_DIR)/.schema.yaml

examples: schema
	./scripts/render.sh --generate -c $(CHART_DIR)

# Render Helm templates for each example values file
examples-templates: 
	./scripts/render.sh --examples -c $(CHART_DIR)

docs: schema
	helm-docs

all: sync schema examples examples-templates docs

# Lint the chart with default and dev values
lint:
	helm lint $(CHART_DIR) -f $(VALUES_DEV)

# Run unit tests using helm-unittest plugin
unittest:
	helm unittest $(CHART_DIR) -v $(VALUES_DEV)

# Run unit tests using example values files (smoke tests)
unittest-examples:
	@for v in $(EXAMPLE_VALUES); do \
		printf "\n==> Running example tests with $$v\n"; \
		case "$${v##*/}" in \
			minimalistic*.yaml) pattern="examples/tests/examples_defaultsecret_test.yaml" ;; \
			*) pattern="examples/tests/examples_smoke_test.yaml" ;; \
		esac; \
		helm unittest $(CHART_DIR) -f $$pattern -v $$v || exit 1; \
	done

# Run all pre-commit hooks across the repo
pre-commit:
	pre-commit run --all-files

# Run Helm tests against an installed release in a cluster
# Usage: make helm-test RELEASE=<release-name> [NAMESPACE=<ns>]
helm-test:
	@test -n "$(RELEASE)" || (echo "RELEASE is required: make helm-test RELEASE=<release-name> [NAMESPACE=<ns>]" && exit 1)
	helm test $(RELEASE) $(if $(NAMESPACE),--namespace $(NAMESPACE))

# Aggregate target to run chart checks
test: yamllint lint unittest test-matrix pre-commit

# Run yamllint
yamllint:
	yamllint -c .yamllint $(CHART_DIR)

# Run comprehensive test suite (lint + unittest + matrix render + kubeconform)
test-matrix:
	./scripts/test.sh --with-kubeconform -c $(CHART_DIR)
