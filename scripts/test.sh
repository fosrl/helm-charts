#!/usr/bin/env bash
# Consolidated test runner for Newt Helm chart
# Merges: test-chart.sh, test-render-matrix.sh, test-newt-matrix.sh, metrics-override-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -c, --chart PATH         Chart path (default: charts/newt)
  -a, --all-charts         Test all charts under ./charts
  -m, --with-metrics       Run metrics override tests
  -k, --with-kubeconform   Run kubeconform validation (requires kubeconform installed)
      --k8s-versions V...  Kubernetes versions for kubeconform (default: 1.30 1.31 1.32 1.33 1.34 1.35)
  -o, --output-dir DIR     Output directory for rendered templates
  -d, --debug             Enable debug output
      --skip-unittest     Skip helm-unittest (useful if unittest plugin crashes)
  -t, --test-file FILE    Run only specific test file (can be specified multiple times)
  -p, --parallel          Run matrix tests in parallel
  -h, --help              Show this help

Examples:
  $0                              # Test default chart (newt)
  $0 --all-charts                 # Test all charts
  $0 --with-metrics               # Include metrics override tests
  $0 --with-kubeconform           # Include K8s validation
  $0 --chart                      # Test specific chart charts/my-chart     
  $0 --skip-unittest              # Skip unit tests (bypass crashes)
  $0 --test-file deployment_test  # Run only deployment tests
  $0 --parallel                   # Run matrix tests in parallel
EOF
  exit 1
}

CHART_DIR="charts/newt"
ALL_CHARTS=false
RUN_METRICS=false
RUN_KUBECONFORM=false
K8S_VERSIONS=("1.30.0" "1.31.0" "1.32.0" "1.33.0" "1.34.0" "1.35.0")
OUTPUT_DIR=""
DEBUG=false
SKIP_UNITTEST=false
TEST_FILES=()
PARALLEL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chart) CHART_DIR="$2"; shift 2 ;;
    -a|--all-charts) ALL_CHARTS=true; shift ;;
    -m|--with-metrics) RUN_METRICS=true; shift ;;
    -k|--with-kubeconform) RUN_KUBECONFORM=true; shift ;;
    --k8s-versions) shift; K8S_VERSIONS=("$@"); shift $# ;;
    -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -d|--debug) DEBUG=true; shift ;;
    --skip-unittest) SKIP_UNITTEST=true; shift ;;
    -t|--test-file)
      TEST_FILES+=("$2")
      shift 2
      ;;
    -p|--parallel) PARALLEL=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

CHART_DIR="$(cd "$ROOT_DIR/$CHART_DIR" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
debug() { if [ "$DEBUG" = "true" ]; then echo -e "${BLUE}[DEBUG]${NC} $*"; fi; }

if [ -n "$OUTPUT_DIR" ]; then
  mkdir -p "$OUTPUT_DIR"
  TEMP_DIR="$OUTPUT_DIR"
else
  TEMP_DIR=$(mktemp -d)
fi

trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${CYAN}===================================================================${NC}"
echo -e "${CYAN}          Newt Helm Chart - Test Suite${NC}"
echo -e "${CYAN}===================================================================${NC}"
echo ""
echo "Chart: ${CHART_DIR}"
echo ""

FAILED=0
PASSED=0
LINT_PASSED=0
LINT_FAILED=0
UNITTEST_PASSED=0
UNITTEST_FAILED=0
UNITTEST_CRASHED=0
RENDER_PASSED=0
RENDER_FAILED=0
YAML_PASSED=0
YAML_FAILED=0
MATRIX_PASSED=0
MATRIX_FAILED=0
KUBECONFORM_PASSED=0
KUBECONFORM_FAILED=0

resolve_chart() {
  local path="$1"
  if [[ "$path" = /* || "$path" =~ ^[A-Za-z]: ]]; then
    echo "$path"
  else
    echo "$ROOT_DIR/$path"
  fi
}

collect_charts() {
  local charts=()
  if [ "$ALL_CHARTS" = "true" ]; then
    for d in "$ROOT_DIR"/charts/*/; do
      [ -d "$d" ] || continue
      [ -f "${d}Chart.yaml" ] || continue
      charts+=("$(resolve_chart "$d")")
    done
  else
    charts+=("$(resolve_chart "$CHART_DIR")")
  fi
  printf '%s\n' "${charts[@]}"
}

run_helm_lint() {
  local chart="$1"
  log_info "Running helm lint on: $chart"
  if helm lint "$chart" -f "$chart/values.dev.yaml" >/dev/null 2>&1; then
    log_pass "helm lint passed"
    LINT_PASSED=$((LINT_PASSED + 1))
    return 0
  else
    log_fail "helm lint failed"
    LINT_FAILED=$((LINT_FAILED + 1))
    return 1
  fi
}

run_helm_unittest() {
  local chart="$1"
  
  if [ "$SKIP_UNITTEST" = "true" ]; then
    log_warn "Skipping helm unittest (--skip-unittest enabled)"
    return 0
  fi
  
  log_info "Running helm unittest on: $chart"
  
  local test_files=()
  
  if [ ${#TEST_FILES[@]} -gt 0 ]; then
    for tf in "${TEST_FILES[@]}"; do
      for f in "$chart/tests/${tf}"*.yaml; do
        [ -f "$f" ] && test_files+=("$f")
      done
      for f in "$chart/tests/${tf}"*_test.yaml; do
        [ -f "$f" ] && test_files+=("$f")
      done
    done
    if [ ${#test_files[@]} -eq 0 ]; then
      log_warn "No test files matching '${TEST_FILES[*]}' found, skipping unittest"
      return 0
    fi
  else
    for f in "$chart/tests/"*_test.yaml; do
      [ -f "$f" ] && test_files+=("$f")
    done
  fi
  
  if [ ${#test_files[@]} -eq 0 ]; then
    log_warn "No test files found, skipping unittest"
    return 0
  fi
  
  local file_count=${#test_files[@]}
  local it_count=0
  for f in "${test_files[@]}"; do
    local count
    count=$(grep -hE '^[[:space:]]*-[[:space:]]*it:' "$f" 2>/dev/null | wc -l | tr -d ' ')
    it_count=$((it_count + count))
  done
  
  local args=()
  for f in "${test_files[@]}"; do
    args+=("-f" "$f")
  done
  
  local output
  local exit_code=0
  
  output=$(helm unittest "$chart" -v "$chart/values.dev.yaml" "${args[@]}" 2>&1) || exit_code=$?
  
  if echo "$output" | grep -qE "panic:|nil pointer dereference|runtime error"; then
    log_warn "helm unittest CRASHED (files=$file_count, cases=$it_count)"
    debug "Crash details: $(echo "$output" | tail -20)"
    log_warn "Consider using --skip-unittest to bypass this crash"
    UNITTEST_CRASHED=$((UNITTEST_CRASHED + 1))
    UNITTEST_FAILED=$((UNITTEST_FAILED + 1))
    return 1
  fi
  
  if [ $exit_code -eq 0 ]; then
    log_pass "helm unittest passed (files=$file_count, cases=$it_count)"
    UNITTEST_PASSED=$((UNITTEST_PASSED + 1))
    return 0
  fi
  
  log_fail "helm unittest failed (files=$file_count, cases=$it_count)"
  echo "$output"
  UNITTEST_FAILED=$((UNITTEST_FAILED + 1))
  return 1
}

render_chart_templates() {
  local chart="$1"
  local name
  name=$(basename "$chart")
  
  log_info "Rendering templates for: $name"
  
  local values_file=""
  if [ -f "$chart/values.dev.yaml" ]; then
    values_file="$chart/values.dev.yaml"
  elif [ -f "$chart/values.yaml" ]; then
    values_file="$chart/values.yaml"
  fi
  
  local helm_args=()
  [ -n "$values_file" ] && helm_args+=("-f" "$values_file")
  
  local vals_dir=""
  if [ -d "$chart/examples/values" ]; then
    vals_dir="$chart/examples/values"
  elif [ -d "$chart/examples" ]; then
    vals_dir="$chart/examples"
  fi

  local rendered_count=0
  local failed_count=0

  for vf in "$vals_dir"/*.yaml; do
    [ -e "$vf" ] || continue
    local base
    base=$(basename "$vf" .yaml)
    local out="$TEMP_DIR/${name}-rendered-${base}.yaml"
    if helm template "$name" "$chart" -f "$vf" "${helm_args[@]}" > "$out" 2> "$TEMP_DIR/${name}-${base}.err"; then
      debug "Rendered $vf -> $out"
      rendered_count=$((rendered_count + 1))
    else
      log_warn "helm template failed for $name with $vf"
      failed_count=$((failed_count + 1))
    fi
  done
  
  debug "Rendered: $rendered_count files, failed: $failed_count"
  
  if [ $failed_count -eq 0 ] && [ $rendered_count -gt 0 ]; then
    RENDER_PASSED=$((RENDER_PASSED + 1))
    return 0
  elif [ $rendered_count -eq 0 ]; then
    return 0
  else
    RENDER_FAILED=$((RENDER_FAILED + 1))
    return 1
  fi
}

run_yamllint() {
  local chart="$1"
  if ! command -v yamllint >/dev/null 2>&1; then
    log_warn "yamllint not installed, skipping"
    return 0
  fi
  
  log_info "Running yamllint on: $chart"
  local files=("$chart/Chart.yaml" "$chart/values.yaml")
  [ -d "$chart/examples/values" ] && files+=("$chart/examples/values")
  [ -d "$chart/examples" ] && [ ! -d "$chart/examples/values" ] && files+=("$chart/examples")
  
  if yamllint "${files[@]}" >/dev/null 2>&1; then
    log_pass "yamllint passed"
    YAML_PASSED=$((YAML_PASSED + 1))
  else
    log_warn "yamllint reported issues (non-critical)"
    YAML_FAILED=$((YAML_FAILED + 1))
  fi
}

run_matrix_render() {
  local chart="$1"
  local matrix_dir="$chart/tests/values-matrix"
  
  if [ ! -d "$matrix_dir" ]; then
    debug "No matrix directory found, skipping matrix tests"
    return 0
  fi
  
  log_info "Testing values matrix scenarios"
  
  if [ "$PARALLEL" = "true" ]; then
    run_matrix_render_parallel "$chart" "$matrix_dir"
  else
    run_matrix_render_sequential "$chart" "$matrix_dir"
  fi
}

run_matrix_render_sequential() {
  local chart="$1"
  local matrix_dir="$2"
  
  for f in "$matrix_dir"/*.yaml; do
    [ -e "$f" ] || continue
    local name
    name=$(basename "$f" .yaml)
    local output_file="$TEMP_DIR/${name}.yaml"
    
    local is_negative=false
    if [[ "$name" == invalid-* ]]; then
      is_negative=true
    fi
    
    echo -n "  [${name}] "
    
    if helm template "test-release" "$chart" -f "$f" --namespace default \
        > "$output_file" 2>&1; then
      if [ "$is_negative" = "true" ]; then
        log_fail "FAILED (negative test should have failed)"
        FAILED=$((FAILED + 1))
        MATRIX_FAILED=$((MATRIX_FAILED + 1))
      else
        log_pass "OK"
        PASSED=$((PASSED + 1))
        MATRIX_PASSED=$((MATRIX_PASSED + 1))
      fi
    else
      if [ "$is_negative" = "true" ]; then
        log_pass "OK (expected failure)"
        PASSED=$((PASSED + 1))
        MATRIX_PASSED=$((MATRIX_PASSED + 1))
      else
        log_fail "FAILED"
        FAILED=$((FAILED + 1))
        MATRIX_FAILED=$((MATRIX_FAILED + 1))
      fi
    fi
  done
}

run_matrix_render_parallel() {
  local chart="$1"
  local matrix_dir="$2"
  
  local pids=()
  local names=()
  local temp_files=()
  local result_files=()
  
  for f in "$matrix_dir"/*.yaml; do
    [ -e "$f" ] || continue
    local name
    name=$(basename "$f" .yaml)
    local output_file="$TEMP_DIR/${name}.yaml"
    local result_file="$TEMP_DIR/${name}.result"
    
    (
      if helm template "test-release" "$chart" -f "$f" --namespace default \
          > "$output_file" 2>/dev/null; then
        echo "PASS" > "$result_file"
      else
        echo "FAIL" > "$result_file"
      fi
    ) &
    
    pids+=($!)
    names+=("$name")
    temp_files+=("$output_file")
    result_files+=("$result_file")
  done
  
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"
    local name="${names[$i]}"
    local result_file="${result_files[$i]}"
    local is_negative=false
    
    if [[ "$name" == invalid-* ]]; then
      is_negative=true
    fi
    
    echo -n "  [${name}] "
    
    if [ -f "$result_file" ]; then
      local result
      result=$(cat "$result_file")
      if [ "$result" = "PASS" ]; then
        if [ "$is_negative" = "true" ]; then
          log_fail "FAILED (negative test should have failed)"
          FAILED=$((FAILED + 1))
          MATRIX_FAILED=$((MATRIX_FAILED + 1))
        else
          log_pass "OK"
          PASSED=$((PASSED + 1))
          MATRIX_PASSED=$((MATRIX_PASSED + 1))
        fi
      else
        if [ "$is_negative" = "true" ]; then
          log_pass "OK (expected failure)"
          PASSED=$((PASSED + 1))
          MATRIX_PASSED=$((MATRIX_PASSED + 1))
        else
          log_fail "FAILED"
          FAILED=$((FAILED + 1))
          MATRIX_FAILED=$((MATRIX_FAILED + 1))
        fi
      fi
    else
      if [ "$is_negative" = "true" ]; then
        log_pass "OK (expected failure)"
        PASSED=$((PASSED + 1))
        MATRIX_PASSED=$((MATRIX_PASSED + 1))
      else
        log_fail "FAILED"
        FAILED=$((FAILED + 1))
        MATRIX_FAILED=$((MATRIX_FAILED + 1))
      fi
    fi
  done
}

run_metrics_override_tests() {
  local chart="$1"
  log_info "Running metrics override tests"
  
  local metrics_tmp="$TEMP_DIR/metrics-tests"
  mkdir -p "$metrics_tmp"
  
  cat > "$metrics_tmp/a-values.yaml" <<'EOF'
global:
  metrics:
    enabled: false
EOF
  helm template test-a "$chart" -f "$metrics_tmp/a-values.yaml" > "$metrics_tmp/a.yaml" 2>/dev/null || true
  if grep -q "Kind: PrometheusRule\|kind: PrometheusRule" "$metrics_tmp/a.yaml"; then
    log_fail "PrometheusRule rendered when global.metrics.enabled=false"
    FAILED=$((FAILED + 1))
  else
    log_pass "No PrometheusRule when global.metrics.enabled=false"
  fi
  
  cat > "$metrics_tmp/b-values.yaml" <<'EOF'
global:
  metrics:
    enabled: true
    prometheusRule:
      enabled: true
EOF
  helm template test-b "$chart" -f "$metrics_tmp/b-values.yaml" > "$metrics_tmp/b.yaml" 2>/dev/null || true
  if grep -q "Kind: PrometheusRule\|kind: PrometheusRule" "$metrics_tmp/b.yaml"; then
    log_pass "PrometheusRule present when global.prometheusRule.enabled=true"
  else
    log_fail "PrometheusRule missing when global.prometheusRule.enabled=true"
    FAILED=$((FAILED + 1))
  fi
  
  if [ -f "$chart/examples/values/minimalistic-metrics.yaml" ]; then
    helm template test-c "$chart" -f "$chart/examples/values/minimalistic-metrics.yaml" > "$metrics_tmp/c.yaml" 2>/dev/null || true
    if grep -q "Kind: PrometheusRule\|kind: PrometheusRule" "$metrics_tmp/c.yaml"; then
      log_pass "PrometheusRule present with allowGlobalOverride"
    else
      log_fail "PrometheusRule missing with allowGlobalOverride"
      FAILED=$((FAILED + 1))
    fi
    fi
    
    PASSED=$((PASSED + 1))
}

run_kubeconform() {
  local chart="$1"
  
  if [ "$RUN_KUBECONFORM" = "false" ]; then
    return 0
  fi
  
  if ! command -v kubeconform >/dev/null 2>&1; then
    log_warn "kubeconform not installed, skipping K8s validation"
    RUN_KUBECONFORM=false
    return 0
  fi
  
  log_info "Running kubeconform validation on: $chart"
  
  local name
  name=$(basename "$chart")
  
  local values_file=""
  if [ -f "$chart/values.dev.yaml" ]; then
    values_file="$chart/values.dev.yaml"
  elif [ -f "$chart/values.yaml" ]; then
    values_file="$chart/values.yaml"
  fi
  
  local rendered_file="$TEMP_DIR/${name}-kubeconform.yaml"
  local helm_args=("-f" "$values_file")
  
  if ! helm template "$name" "$chart" "${helm_args[@]}" > "$rendered_file" 2>&1; then
    log_fail "Failed to render templates for kubeconform"
    FAILED=$((FAILED + 1))
    return 1
  fi
  
  local kubeconform_args=("-strict" "-cache" "$TEMP_DIR/kubeconform-cache")
  local version_failed=0
  
  for version in "${K8S_VERSIONS[@]}"; do
    echo -n "  [kubeconform-$version] "
    if kubeconform "${kubeconform_args[@]}" -kubernetes-version "$version" "$rendered_file" >/dev/null 2>&1; then
      log_pass "OK"
      PASSED=$((PASSED + 1))
      KUBECONFORM_PASSED=$((KUBECONFORM_PASSED + 1))
    else
      log_fail "FAILED"
      FAILED=$((FAILED + 1))
      KUBECONFORM_FAILED=$((KUBECONFORM_FAILED + 1))
      version_failed=1
    fi
  done
  
  return $version_failed
}

main() {
  local charts
  mapfile -t charts < <(collect_charts)
  
  if [ ${#charts[@]} -eq 0 ]; then
    log_fail "No charts found to test"
    exit 1
  fi
  
  for chart in "${charts[@]}"; do
    echo ""
    echo -e "${CYAN}=== Testing: $(basename "$chart") ===${NC}"
    echo ""
    
    run_helm_lint "$chart" || FAILED=$((FAILED + 1))
    run_helm_unittest "$chart" || FAILED=$((FAILED + 1))
    render_chart_templates "$chart"
    run_yamllint "$chart"
    run_matrix_render "$chart"
    
    if [ "$RUN_METRICS" = "true" ] && [ "$(basename "$chart")" = "newt" ]; then
      run_metrics_override_tests "$chart"
    fi
    
    run_kubeconform "$chart"
  done
  
  echo ""
  echo -e "${CYAN}===================================================================${NC}"
  echo -e "${CYAN}                         SUMMARY${NC}"
  echo -e "${CYAN}===================================================================${NC}"
  echo ""
  echo -e "${GREEN}Passed:${NC} $PASSED"
  echo -e "${RED}Failed:${NC} $FAILED"
  echo ""
  echo "Breakdown by test type:"
  echo "  helm lint:        ${GREEN}$LINT_PASSED passed${NC} / ${RED}$LINT_FAILED failed${NC}"
  if [ $UNITTEST_CRASHED -gt 0 ]; then
    echo "  helm unittest:   ${GREEN}$UNITTEST_PASSED passed${NC} / ${RED}$UNITTEST_FAILED failed${NC} / ${YELLOW}$UNITTEST_CRASHED crashed${NC}"
  else
    echo "  helm unittest:   ${GREEN}$UNITTEST_PASSED passed${NC} / ${RED}$UNITTEST_FAILED failed${NC}"
  fi
  echo "  template render: ${GREEN}$RENDER_PASSED passed${NC} / ${RED}$RENDER_FAILED failed${NC}"
  echo "  yamllint:        ${GREEN}$YAML_PASSED passed${NC} / ${RED}$YAML_FAILED failed${NC}"
  echo "  matrix tests:    ${GREEN}$MATRIX_PASSED passed${NC} / ${RED}$MATRIX_FAILED failed${NC}"
  if [ "$RUN_KUBECONFORM" = "true" ]; then
    echo "  kubeconform:      ${GREEN}$KUBECONFORM_PASSED passed${NC} / ${RED}$KUBECONFORM_FAILED failed${NC}"
  fi
  echo ""
  echo "Output: $TEMP_DIR"
  
  if [ $FAILED -gt 0 ]; then
    log_fail "SOME TESTS FAILED"
    exit 1
  else
    log_pass "ALL TESTS PASSED"
    exit 0
  fi
}

main
