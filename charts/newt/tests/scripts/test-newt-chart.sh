#!/usr/bin/env bash
# Comprehensive test suite for Newt Helm chart
# Mirrors the Pangolin chart test suite and adds CRD-specific checks

set -euo pipefail

# Configuration
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${CHART_DIR}/tests"
VALUES_DIR="${TEST_DIR}/values"
OUTPUT_DIR="${TEST_DIR}/output"
SCRIPTS_DIR="${TEST_DIR}/scripts"
: "${HELM_KUBE_VERSION:=1.28.15}"
: "${TEST_FAST:=0}"
: "${KUBECONFORM_SCHEMA_LOCATIONS:=}"
: "${KUBECONFORM_STRICT_CRD:=0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Test statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0
START_TIME=$(date +%s)

# Arrays for results
declare -a FAILED_TESTS=()
declare -a WARNED_TESTS=()
declare -a TEST_RESULTS=()

# Print helpers
print_header() { echo -e "\n${CYAN}$(printf '=%.0s' {1..80})${NC}\n${CYAN} $1${NC}\n${CYAN}$(printf '=%.0s' {1..80})${NC}"; }
print_step() { echo -e "${YELLOW}>> $1${NC}"; }
print_success() { echo -e "${GREEN}[+] $1${NC}"; }
print_error() { echo -e "${RED}[-] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_info() { echo -e "${CYAN}[i] $1${NC}"; }

# Tool presence
check_tool() {
  local tool=$1
  local required=${2:-false}
  if command -v "$tool" >/dev/null 2>&1; then
    print_info "$tool is available"
    return 0
  else
    if [ "$required" = true ]; then
      print_error "$tool is required but not found"
      exit 1
    else
      print_warning "$tool is not available - skipping related tests"
      return 1
    fi
  fi
}

# Whitespace/cleanliness validator (ignore ConfigMap data blocks)
validate_template_cleanliness() {
  local file=$1
  local in_configmap=false
  local in_configmap_data=false
  local line_num=0
  local inappropriate_empty_lines=()
  local trailing_ws_lines=()
  local tab_char_lines=()
  local double_space_after_colon_lines=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_num++))

    if [[ $line =~ ^---$ ]]; then
      in_configmap=false
      in_configmap_data=false
    elif [[ $line =~ ^apiVersion: ]]; then
      in_configmap=false
      in_configmap_data=false
    elif [[ $line =~ ^kind:[[:space:]]*ConfigMap$ ]]; then
      in_configmap=true
      in_configmap_data=false
    elif [[ $line =~ ^[[:space:]]*data:[[:space:]]*$ ]] && [[ $in_configmap == true ]]; then
      in_configmap_data=true
    elif [[ $line =~ ^kind: ]] && [[ $line != *"ConfigMap"* ]]; then
      in_configmap=false
      in_configmap_data=false
    fi

    # Skip checks inside ConfigMap data
    if [[ $in_configmap_data == true ]]; then
      continue
    fi

    # Empty line not allowed outside ConfigMap data
    if [[ $line =~ ^[[:space:]]*$ ]]; then
      inappropriate_empty_lines+=("$line_num")
      continue
    fi

    # Trailing whitespace
    if [[ $line =~ [[:blank:]]+$ ]]; then
      trailing_ws_lines+=("$line_num")
    fi

    # Tab characters
    if [[ $line == *$'\t'* ]]; then
      tab_char_lines+=("$line_num")
    fi

    # Double spaces after colon (e.g., 'key:  value')
    if [[ $line =~ ^[[:space:]]*[^#[:space:]][^:]*:[[:space:]]{2,}[^[:space:]] ]]; then
      double_space_after_colon_lines+=("$line_num")
    fi
  done < "$file"

  local issues=()
  [[ ${#inappropriate_empty_lines[@]} -gt 0 ]] && issues+=("Empty lines at: ${inappropriate_empty_lines[*]}")
  [[ ${#trailing_ws_lines[@]} -gt 0 ]] && issues+=("Trailing whitespace at: ${trailing_ws_lines[*]}")
  [[ ${#tab_char_lines[@]} -gt 0 ]] && issues+=("Tab characters at: ${tab_char_lines[*]}")
  [[ ${#double_space_after_colon_lines[@]} -gt 0 ]] && issues+=("Double spaces after ':' at: ${double_space_after_colon_lines[*]}")

  if [[ ${#issues[@]} -eq 0 ]]; then
    return 0
  else
    print_error "Whitespace policy violations detected:"
    for i in "${issues[@]}"; do echo "  - $i"; done
    return 1
  fi
}

check_prerequisites() {
  print_header "Checking Prerequisites"

  # Required tools (helm is required, others are recommended but optional)
  check_tool helm true
  check_tool yq || true
  check_tool jq || true
  # kubeconform is recommended for Kubernetes schema validation
  check_tool kubeconform || true
  check_tool kube-score || true
  check_tool kubescape || true
  check_tool kube-linter || true

  # Include vendored CRD schemas for kubeconform if present
  # This complements any user-provided KUBECONFORM_SCHEMA_LOCATIONS
  local vendor_dir="${TEST_DIR}/schemas"
  if [ -d "$vendor_dir" ]; then
    local vendor_url="file://${vendor_dir}"
    if [ -n "${KUBECONFORM_SCHEMA_LOCATIONS}" ]; then
      KUBECONFORM_SCHEMA_LOCATIONS="${KUBECONFORM_SCHEMA_LOCATIONS},${vendor_url}"
    else
      KUBECONFORM_SCHEMA_LOCATIONS="default,${vendor_url}"
    fi
  fi

  # Ensure output directory exists
  mkdir -p "$OUTPUT_DIR"
  print_success "Prerequisites check completed"
}

# Record results
record_test_result() {
  local test_name=$1 description=$2 result=$3 details=${4:-}
  TESTS_RUN=$((TESTS_RUN+1))
  case "$result" in
    PASS) TESTS_PASSED=$((TESTS_PASSED+1)); print_success "$description: OK" ;;
    WARN) TESTS_WARNED=$((TESTS_WARNED+1)); print_warning "$description: WARNING"; WARNED_TESTS+=("$test_name - $description: $details") ;;
    SKIP) print_warning "$description: SKIPPED" ;;
    *)    TESTS_FAILED=$((TESTS_FAILED+1)); print_error "$description: FAILED"; FAILED_TESTS+=("$test_name - $description: $details") ;;
  esac
  TEST_RESULTS+=("$test_name|$description|$result|$details")
}

# Test config mapping: values|expected_counts|expected_labels
get_test_config() {
  case "$1" in
    minimal)
      echo "tests/values/minimal.yaml|1,0,0,0,0,0|app.kubernetes.io/name: newt" ;;
    metrics)
      echo "tests/values/metrics.yaml|1,0,0,0,0,1|app.kubernetes.io/name: newt" ;;
    full)
      echo "tests/values/full.yaml|1,2,0,0,0,2|app.kubernetes.io/name: newt" ;;
    *) return 1 ;;
  esac
}

get_test_description() {
  case "$1" in
    minimal) echo "Minimal configuration testing defaults" ;;
    metrics) echo "Metrics enabled with Service + ServiceMonitor + PrometheusRule" ;;
    full)    echo "Full configuration exercising overrides and features" ;;
    *)       echo "Unknown test" ;;
  esac
}

# Helm lint
test_helm_lint() {
  local test_name=$1
  print_step "Running helm lint"
  if output=$(helm lint "$CHART_DIR" 2>&1); then
    if echo "$output" | grep -q "0 chart(s) failed"; then
      record_test_result "$test_name" "Helm lint validation" "PASS" "Chart linting passed"
      return 0
    fi
  fi
  record_test_result "$test_name" "Helm lint validation" "FAIL" "Chart linting failed: $output"
  return 1
}

# Values parsing
test_values_parsing() {
  local test_name=$1 values_file=$2
  print_step "Validating values file parsing"
  if ! [ -f "$values_file" ]; then
    record_test_result "$test_name" "Values file parsing" "FAIL" "Values file not found: $values_file"
    return 1
  fi
  if output=$(env -u KUBECONFIG helm template "$test_name" "$CHART_DIR" -f "$values_file" --kube-version "$HELM_KUBE_VERSION" --dry-run 2>&1); then
    record_test_result "$test_name" "Values file parsing" "PASS" "Values file parsed successfully"
    return 0
  else
    record_test_result "$test_name" "Values file parsing" "FAIL" "Values parsing failed: $output"
    return 1
  fi
}

# Render and validate resource counts + labels + cleanliness
test_template_rendering() {
  local test_name=$1 values_file=$2 expected_counts=$3 expected_labels=$4
  print_step "Testing template rendering for $test_name"
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"
  if ! output=$(env -u KUBECONFIG helm template "$test_name" "$CHART_DIR" -f "$values_file" --kube-version "$HELM_KUBE_VERSION" 2>&1); then
    record_test_result "$test_name" "Template rendering" "FAIL" "Helm template failed: $output"
    return 1
  fi
  echo "$output" > "$output_file"

  if validate_template_cleanliness "$output_file"; then
    record_test_result "$test_name" "Template cleanliness" "PASS" "No whitespace policy violations"
  else
    record_test_result "$test_name" "Template cleanliness" "FAIL" "Whitespace policy violations present"
    return 1
  fi

  IFS=',' read -ra COUNTS <<< "$expected_counts"
  local resource_types=("Deployment" "ConfigMap" "ServiceAccount" "Role" "RoleBinding" "Service")
  for i in "${!resource_types[@]}"; do
    local resource_type="${resource_types[$i]}"
    local expected_count="${COUNTS[$i]}"
    local actual_count
    # grep -c prints 0 even when it returns exit status 1 (no matches). Avoid appending another 0.
    actual_count=$(grep -c "^kind: $resource_type$" "$output_file" 2>/dev/null || true)
    # Normalize CRLF and ensure a numeric value
    actual_count="${actual_count//$'\r'/}"
    if ! [[ "$actual_count" =~ ^[0-9]+$ ]]; then actual_count=0; fi
    if [ "$actual_count" -ne "$expected_count" ]; then
      record_test_result "$test_name" "Template rendering" "FAIL" "Found $actual_count $resource_type resources, expected $expected_count"
      return 1
    fi
  done

  if [ -n "$expected_labels" ]; then
    IFS=',' read -ra LABELS <<< "$expected_labels"
    for label in "${LABELS[@]}"; do
      if ! grep -q "$label" "$output_file"; then
        record_test_result "$test_name" "Template rendering" "FAIL" "Missing expected label: $label"
        return 1
      fi
    done
  fi

  record_test_result "$test_name" "Template rendering" "PASS" "All expected resources and labels present"
  return 0
}

# kubeconform (default: ignore missing schemas)
test_kubernetes_validation() {
  local test_name=$1
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"
  print_step "Validating Kubernetes resources with kubeconform"
  if ! check_tool kubeconform; then
    record_test_result "$test_name" "Kubernetes validation" "SKIP" "kubeconform not available"
    return 0
  fi
  local args=("-summary")
  if [ "${KUBECONFORM_STRICT_CRD}" != "1" ]; then
    args+=("-ignore-missing-schemas")
  fi
  if [ -n "${KUBECONFORM_SCHEMA_LOCATIONS}" ]; then
    IFS=',' read -ra LOCS <<< "${KUBECONFORM_SCHEMA_LOCATIONS}"
    for loc in "${LOCS[@]}"; do args+=("-schema-location" "$loc"); done
  else
    args+=("-schema-location" "default")
  fi
  if output=$(kubeconform "${args[@]}" "$output_file" 2>&1); then
    record_test_result "$test_name" "Kubernetes validation" "PASS" "All resources are valid"
  else
    record_test_result "$test_name" "Kubernetes validation" "FAIL" "Invalid Kubernetes resources: $output"
    return 1
  fi
}

# kube-score security analysis
test_security_kube_score() {
  local test_name=$1
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"
  print_step "Running security analysis with kube-score"
  if ! check_tool kube-score; then
    record_test_result "$test_name" "Security (kube-score)" "SKIP" "kube-score not available"
    return 0
  fi

  local raw
  raw=$(kube-score score "$output_file" --output-format json 2>&1 || true)
  echo "$raw" > "${OUTPUT_DIR}/${test_name}-kube-score.json"

  local disallowed_count
  disallowed_count=$(echo "$raw" | jq -r '
    def allowed: ["container-security-context-readonlyrootfilesystem","container-security-context-user-group-id","pod-probes-identical","deployment-has-poddisruptionbudget","deployment-has-host-podantiaffinity","container-image-pull-policy","pod-networkpolicy"];
    def ignored: ["deployment-replicas"];
    [ .[] | .checks[]
      | select((.comments != null) and (.grade != 10) and (.skipped | not))
      | select(.check.id as $id | any(ignored[]; . == $id) | not)
      | select((.check.id as $id | ( [allowed[] | select(. == $id)] | length) == 0))
    ] | length' 2>/dev/null || echo "0")

  local allowed_warn allowed_list
  allowed_warn=$(echo "$raw" | jq -r '
    def allowed: ["container-security-context-readonlyrootfilesystem","container-security-context-user-group-id","pod-probes-identical","deployment-has-poddisruptionbudget","deployment-has-host-podantiaffinity","container-image-pull-policy","pod-networkpolicy"];
    def ignored: ["deployment-replicas"];
    [ .[] | .checks[]
      | select((.comments != null) and (.grade != 10) and (.skipped | not))
      | select(.check.id as $id | any(ignored[]; . == $id) | not)
      | select(.check.id as $id | any(allowed[]; . == $id))
    ] | length' 2>/dev/null || echo "0")
  allowed_list=$(echo "$raw" | jq -r '
    def allowed: ["container-security-context-readonlyrootfilesystem","container-security-context-user-group-id","pod-probes-identical","deployment-has-poddisruptionbudget","deployment-has-host-podantiaffinity","container-image-pull-policy","pod-networkpolicy"];
    def ignored: ["deployment-replicas"];
    [ .[] | .checks[]
      | select((.comments != null) and (.grade != 10) and (.skipped | not))
      | select(.check.id as $id | any(ignored[]; . == $id) | not)
      | select(.check.id as $id | any(allowed[]; . == $id))
      | .check.id
    ] | unique | join(", ")' 2>/dev/null || echo "")

  print_info "kube-score: disallowed=$disallowed_count, allowed-warn=$allowed_warn"
  if [ "$disallowed_count" -gt 0 ]; then
    record_test_result "$test_name" "Security (kube-score)" "FAIL" "$disallowed_count disallowed issues (see ${OUTPUT_DIR}/${test_name}-kube-score.json)"
    return 1
  elif [ "$allowed_warn" -gt 0 ]; then
    record_test_result "$test_name" "Security (kube-score)" "WARN" "$allowed_warn known exceptions: ${allowed_list}"
  else
    record_test_result "$test_name" "Security (kube-score)" "PASS" "No issues"
  fi
}

# kubescape security
test_security_kubescape() {
  local test_name=$1
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"
  print_step "Running security analysis with kubescape"
  if ! check_tool kubescape; then
    record_test_result "$test_name" "Security (kubescape)" "SKIP" "kubescape not available"
    return 0
  fi
  local results_file="${OUTPUT_DIR}/${test_name}-kubescape.json"
  if kubescape scan "$output_file" --format json --output "$results_file" >/dev/null 2>&1; then
    local score
    score=$(jq -r '.summaryDetails.complianceScore' "$results_file" 2>/dev/null || echo "0")
    print_info "kubescape: complianceScore=${score}"
    if awk "BEGIN {exit !($score >= 70)}"; then
      record_test_result "$test_name" "Security (kubescape)" "PASS" "Compliance score: ${score} (>= 70)"
    else
      record_test_result "$test_name" "Security (kubescape)" "FAIL" "Compliance score: ${score} (< 70)"
      return 1
    fi
  else
    record_test_result "$test_name" "Security (kubescape)" "FAIL" "kubescape analysis failed"
    return 1
  fi
}

# kube-linter security
test_security_kube_linter() {
  local test_name=$1
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"
  print_step "Running security analysis with kube-linter"
  if ! check_tool kube-linter; then
    record_test_result "$test_name" "Security (kube-linter)" "SKIP" "kube-linter not available"
    return 0
  fi
  if output=$(kube-linter lint "$output_file" 2>&1); then
    record_test_result "$test_name" "Security (kube-linter)" "PASS" "No security issues found"
  else
    local error_count=$(echo "$output" | grep -c "Error:" || echo "0")
    if [ "$error_count" -gt 0 ]; then
      record_test_result "$test_name" "Security (kube-linter)" "WARN" "$error_count issues (warn-only)"
    else
      record_test_result "$test_name" "Security (kube-linter)" "PASS" "Only warnings found"
    fi
  fi
}

# Additional CRD invariants for the metrics test only
test_metrics_crd_invariants() {
  local test_name=$1 values_file=$2
  local output_file="${OUTPUT_DIR}/${test_name}-output.yaml"

  print_step "Asserting CRD invariants for metrics scenario"

  local sm_count pm_count pr_count
  sm_count=$(grep -c "^kind: ServiceMonitor$" "$output_file" || true)
  pm_count=$(grep -c "^kind: PodMonitor$" "$output_file" || true)
  pr_count=$(grep -c "^kind: PrometheusRule$" "$output_file" || true)

  if [ "$sm_count" -ne 1 ]; then
    record_test_result "$test_name" "CRD invariants" "FAIL" "Expected 1 ServiceMonitor, got $sm_count"
    return 1
  fi
  if [ "$pm_count" -ne 0 ]; then
    record_test_result "$test_name" "CRD invariants" "FAIL" "Expected 0 PodMonitor, got $pm_count"
    return 1
  fi
  if [ "$pr_count" -ne 1 ]; then
    record_test_result "$test_name" "CRD invariants" "FAIL" "Expected 1 PrometheusRule, got $pr_count"
    return 1
  fi
  record_test_result "$test_name" "CRD invariants" "PASS" "ServiceMonitor=1, PodMonitor=0, PrometheusRule=1"

  # Negative case A: enabling both PodMonitor and ServiceMonitor must fail
  print_step "Negative: Enabling both PodMonitor and ServiceMonitor should fail"
  local neg_output
  if neg_output=$(env -u KUBECONFIG helm template neg-a "$CHART_DIR" -f "$values_file" \
      --set metrics.podMonitor.enabled=true --kube-version "$HELM_KUBE_VERSION" 2>&1); then
    record_test_result "$test_name" "CRD negative (both enabled)" "FAIL" "Expected Helm fail, but succeeded"
    return 1
  else
    if echo "$neg_output" | grep -q "Either metrics.podMonitor.enabled or metrics.serviceMonitor.enabled"; then
      record_test_result "$test_name" "CRD negative (both enabled)" "PASS" "Got expected Helm fail() message"
    else
      record_test_result "$test_name" "CRD negative (both enabled)" "FAIL" "Unexpected error: $neg_output"
      return 1
    fi
  fi

  # Negative case B: ServiceMonitor requires metrics.service.enabled
  print_step "Negative: ServiceMonitor without metrics.service.enabled should fail"
  if neg_output=$(env -u KUBECONFIG helm template neg-b "$CHART_DIR" -f "$values_file" \
      --set metrics.service.enabled=false --kube-version "$HELM_KUBE_VERSION" 2>&1); then
    record_test_result "$test_name" "CRD negative (ServiceMonitor requires Service)" "FAIL" "Expected Helm fail, but succeeded"
    return 1
  else
    if echo "$neg_output" | grep -q "metrics.service.enabled must be true when metrics.serviceMonitor.enabled is true"; then
      record_test_result "$test_name" "CRD negative (ServiceMonitor requires Service)" "PASS" "Got expected Helm fail() message"
    else
      record_test_result "$test_name" "CRD negative (ServiceMonitor requires Service)" "FAIL" "Unexpected error: $neg_output"
      return 1
    fi
  fi

  # Strict kubeconform CRD validation for metrics case
  print_step "Strict kubeconform validation with CRD schemas"
  if ! check_tool kubeconform; then
    record_test_result "$test_name" "CRD kubeconform strict" "SKIP" "kubeconform not available"
    return 0
  fi
  local args=("-summary")
  # Strict: do NOT ignore missing schemas
  # Include default + Prometheus Operator jsonschema unless user provided custom locations
  if [ -n "${KUBECONFORM_SCHEMA_LOCATIONS}" ]; then
    IFS=',' read -ra LOCS <<< "${KUBECONFORM_SCHEMA_LOCATIONS}"
    for loc in "${LOCS[@]}"; do args+=("-schema-location" "$loc"); done
  else
    args+=("-schema-location" "default")
    args+=("-schema-location" "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/jsonschema")
  fi
  if output=$(kubeconform "${args[@]}" "$output_file" 2>&1); then
    record_test_result "$test_name" "CRD kubeconform strict" "PASS" "All resources valid with CRD schemas"
  else
    if echo "$output" | grep -qi "could not find schema"; then
      record_test_result "$test_name" "CRD kubeconform strict" "WARN" "Schemas missing (using vendored stubs or default): $output"
    else
      record_test_result "$test_name" "CRD kubeconform strict" "FAIL" "CRD schema validation failed: $output"
      return 1
    fi
  fi
}

# Run one test case
run_test_case() {
  local test_name=$1
  local config
  if ! config=$(get_test_config "$test_name"); then
    print_error "Unknown test: $test_name"; return 1
  fi
  IFS='|' read -r values_file expected_counts expected_labels <<< "$config"
  values_file="${CHART_DIR}/${values_file}"

  print_header "$test_name - $(get_test_description "$test_name")"

  test_values_parsing "$test_name" "$values_file" || return 1
  test_template_rendering "$test_name" "$values_file" "$expected_counts" "$expected_labels" || return 1
  if [ "${TEST_FAST}" = "1" ]; then print_info "Skipping validators (TEST_FAST=1)"; else test_kubernetes_validation "$test_name"; fi
  if [ "${TEST_FAST}" = "1" ]; then :; else test_security_kube_score "$test_name"; fi
  if [ "${TEST_FAST}" = "1" ]; then :; else test_security_kubescape "$test_name"; fi
  if [ "${TEST_FAST}" = "1" ]; then :; else test_security_kube_linter "$test_name"; fi

  if [ "$test_name" = "metrics" ]; then
    test_metrics_crd_invariants "$test_name" "$values_file" || return 1
  fi

  return 0
}

# Usage
usage() {
  cat << EOF
Usage: $0 [OPTIONS] [TEST_NAME]

Test the Newt Helm chart with comprehensive validation.

OPTIONS:
  -h, --help          Show this help message
  -v, --verbose       Enable verbose output
  -f, --fail-fast     Stop on first failure
  -o, --output DIR    Output directory (default: tests/output)

TEST_NAME:
  If specified, run only this test. Available tests:
  - minimal
  - metrics
  - full

Examples:
  $0                      # Run all tests
  $0 minimal              # Run minimal test only
  $0 -f                   # Run all tests, stop on first failure
  $0 -o ./my-results full # Custom output directory
EOF
}

# Summary
print_summary() {
  local end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local success_rate=0
  if [ $TESTS_RUN -gt 0 ]; then
    success_rate=$(( (TESTS_PASSED * 100) / TESTS_RUN ))
  fi

  print_header "Test Summary"
  echo -e "${WHITE}Total Tests Run: $TESTS_RUN${NC}"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${YELLOW}Warnings: $TESTS_WARNED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo -e "${WHITE}Duration: ${duration}s${NC}"
  echo -e "${WHITE}Success Rate: ${success_rate}%${NC}"

  if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${RED}Failed Tests:${NC}"
    for failed in "${FAILED_TESTS[@]}"; do echo -e "${RED}  • $failed${NC}"; done
  fi
  if [ ${#WARNED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Warnings:${NC}"
    for warn in "${WARNED_TESTS[@]}"; do echo -e "${YELLOW}  • $warn${NC}"; done
  fi

  local results_file="${OUTPUT_DIR}/test-results.json"
  echo "[" > "$results_file"
  for i in "${!TEST_RESULTS[@]}"; do
    IFS='|' read -r name desc result details <<< "${TEST_RESULTS[$i]}"
    cat >> "$results_file" << JSON
  {
    "testName": "$name",
    "description": "$desc",
    "result": "$result",
    "details": "$details",
    "timestamp": "$(date -Iseconds)"
  }$([ $i -lt $((${#TEST_RESULTS[@]} - 1)) ] && echo "," || echo "")
JSON
  done
  echo "]" >> "$results_file"
  print_info "Detailed results saved to: $results_file"
  [ $TESTS_FAILED -eq 0 ]
}

# Main
main() {
  local test_name="" verbose=false fail_fast=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      -v|--verbose) verbose=true; shift ;;
      -f|--fail-fast) fail_fast=true; shift ;;
      -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
      -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
      *) test_name="$1"; shift ;;
    esac
  done

  print_header "Newt Helm Chart Test Suite"
  check_prerequisites

  print_step "Running initial Helm lint check"
  if ! test_helm_lint "helm-lint"; then
    if [ "$fail_fast" = true ]; then
      print_error "Helm lint failed - stopping execution"
      print_summary
      exit 1
    fi
  fi

  local test_cases=("minimal" "metrics" "full")
  if [ -n "$test_name" ]; then
    if get_test_config "$test_name" >/dev/null; then
      test_cases=("$test_name")
    else
      print_error "Unknown test: $test_name"
      echo "Available tests: ${test_cases[*]}"
      exit 1
    fi
  fi

  for t in "${test_cases[@]}"; do
    if ! run_test_case "$t"; then
      if [ "$fail_fast" = true ]; then
        print_error "Test failed - stopping execution"
        break
      fi
    fi
    echo
  done

  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

