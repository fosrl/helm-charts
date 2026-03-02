#!/usr/bin/env bash
# Consolidated render script for generating rendered artifacts
# Merges: ci-helm-examples.sh, render-examples-templates.sh, gen-rendered-scenarios.sh, gen-examples.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -c, --chart PATH         Chart path (default: charts/newt)
  -e, --examples           Render example values files
  -m, --matrix             Render matrix/test scenarios
  -g, --generate          Generate example values files from overlays (gen-examples)
  -o, --out DIR            Output directory (default: tmp/renders)
  -d, --debug              Enable debug output
  -h, --help               Show this help

Examples:
  $0 --examples --matrix               # Render both examples and matrix
  $0 --examples                        # Render only examples
  $0 --generate                        # Generate example values from overlays
  $0 --chart charts/newt --examples    # Render examples for specific chart
EOF
  exit 1
}

CHART_DIR="charts/newt"
RENDER_EXAMPLES=false
RENDER_MATRIX=false
GENERATE_EXAMPLES=false
OUTPUT_DIR="tmp/renders"
DEBUG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chart) CHART_DIR="$2"; shift 2 ;;
    -e|--examples) RENDER_EXAMPLES=true; shift ;;
    -m|--matrix) RENDER_MATRIX=true; shift ;;
    -g|--generate) GENERATE_EXAMPLES=true; shift ;;
    -o|--out) OUTPUT_DIR="$2"; shift 2 ;;
    -d|--debug) DEBUG=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if [ "$RENDER_EXAMPLES" = "false" ] && [ "$RENDER_MATRIX" = "false" ] && [ "$GENERATE_EXAMPLES" = "false" ]; then
  RENDER_EXAMPLES=true
  RENDER_MATRIX=true
fi

CHART_DIR="$(cd "$ROOT_DIR/$CHART_DIR" && pwd)"
OUTPUT_DIR="$(cd "$ROOT_DIR/$OUTPUT_DIR" && pwd)"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
debug() { if [ "$DEBUG" = "true" ]; then echo -e "${BLUE}[DEBUG]${NC} $*"; fi; }

command -v helm >/dev/null 2>&1 || { echo "ERROR: helm required" >&2; exit 1; }

echo "==================================================================="
echo "          Newt Chart - Render Artifacts Generator"
echo "==================================================================="
echo ""
echo "Chart: $CHART_DIR"
echo "Output: $OUTPUT_DIR"
echo ""

render_example_values() {
  local chart="$1"
  local examples_dir="$chart/examples/values"
  
  if [ ! -d "$examples_dir" ]; then
    log_warn "No examples/values directory found in $chart"
    return 0
  fi
  
  log_info "Rendering example values from: $examples_dir"
  
  local out_dir="$OUTPUT_DIR/examples/$(basename "$chart")"
  mkdir -p "$out_dir"
  
  shopt -s nullglob
  for vf in "$examples_dir"/*.yaml; do
    [ -e "$vf" ] || continue
    local name
    name=$(basename "$vf" .yaml)
    local out_file="$out_dir/${name}.yaml"
    
    log_info "Rendering $name -> $out_file"
    if helm template "$name" "$chart" -f "$vf" > "$out_file"; then
      log_pass "Rendered $name"
    else
      log_warn "Failed to render $name"
    fi
  done
  shopt -u nullglob
  
  echo ""
}

render_matrix_values() {
  local chart="$1"
  local matrix_dir="$chart/tests/values-matrix"
  
  if [ ! -d "$matrix_dir" ]; then
    log_warn "No tests/values-matrix directory found in $chart"
    return 0
  fi
  
  log_info "Rendering matrix scenarios from: $matrix_dir"
  
  local out_dir="$OUTPUT_DIR/matrix/$(basename "$chart")"
  mkdir -p "$out_dir"
  
  shopt -s nullglob
  for vf in "$matrix_dir"/*.yaml; do
    [ -e "$vf" ] || continue
    local name
    name=$(basename "$vf" .yaml)
    local out_file="$out_dir/${name}.yaml"
    
    log_info "Rendering matrix $name -> $out_file"
    if helm template "matrix-$name" "$chart" -f "$vf" --namespace default > "$out_file"; then
      log_pass "Rendered $name"
    else
      log_warn "Failed to render $name"
    fi
  done
  shopt -u nullglob
  
  echo ""
}

render_all_charts_examples() {
  log_info "Rendering examples for all charts under: $ROOT_DIR/charts"
  
  for d in "$ROOT_DIR"/charts/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}Chart.yaml" ] || continue
    
    local chart_name
    chart_name=$(basename "$d")
    log_info "Processing chart: $chart_name"
    
    if [ "$RENDER_EXAMPLES" = "true" ]; then
      render_example_values "$d"
    fi
    
    if [ "$RENDER_MATRIX" = "true" ]; then
      render_matrix_values "$d"
    fi
  done
}

generate_example_values() {
  local chart="$1"
  
  command -v yq >/dev/null 2>&1 || { echo "ERROR: yq required for --generate" >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for --generate" >&2; exit 1; }
  
  local schema="$chart/values.schema.json"
  local base="$chart/values.yaml"
  local overlays_dir="$chart/examples/overlays"
  local out_dir="$chart/examples"
  
  if [ ! -d "$overlays_dir" ]; then
    log_warn "No overlays directory found: $overlays_dir"
    return 0
  fi
  
  log_info "Generating example values from overlays"
  
  gen_one() {
    local name="$1"
    local overlay="$overlays_dir/${name}.yaml"
    local out="$out_dir/values-${name}.yaml"
    
    if [ ! -f "$overlay" ]; then
      log_warn "Overlay not found: $overlay"
      return 1
    fi
    
    yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' \
      "$base" "$overlay" > "$out"
    
    if [ -f "$schema" ]; then
      for key in $(jq -r '.required[]? // empty' "$schema"); do
        local val
        val="$(yq eval ".${key} // \"__MISSING__\"" "$out")"
        if [ "$val" = "__MISSING__" ] || [ "$val" = "\"\"" ]; then
          log_warn "Example ${out} missing required key: ${key}"
          return 1
        fi
      done
    fi
    
    log_pass "Generated $out"
  }
  
  if [ "$(basename "$chart")" = "newt" ]; then
    gen_one bare-minimum
    gen_one minimalistic
    gen_one minimalistic-metrics
    gen_one full
    gen_one existing-secret
    gen_one docker-socket
  fi
  
  echo ""
}

main() {
  mkdir -p "$OUTPUT_DIR"
  
  if [ "$GENERATE_EXAMPLES" = "true" ]; then
    generate_example_values "$CHART_DIR"
  fi
  
  if [ "$RENDER_EXAMPLES" = "true" ] || [ "$RENDER_MATRIX" = "true" ]; then
    render_all_charts_examples
  fi
  
  echo "==================================================================="
  log_pass "Rendered artifacts written to: $OUTPUT_DIR"
  echo "==================================================================="
}

main
