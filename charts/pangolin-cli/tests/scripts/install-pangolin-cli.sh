#!/usr/bin/env bash
# pangolin-cli Helm chart install/verify/uninstall helper
# - No secrets are created or modified by this script
# - Uses current kubeconfig and prints current context and cluster name
# - Applies Hetzner LB annotations for the site Service when accepting clients
# - On failure, collects logs/describe/status for quick troubleshooting

set -Eeuo pipefail
IFS=$'\n\t'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_RELEASE="pangolin-cli-validation"
DEFAULT_NAMESPACE="Chart-Validation-Site"
DEFAULT_TIMEOUT="5m"
DEFAULT_LOG_SINCE="15m"
DEFAULT_INSTANCE_NAME="main-tunnel"

# State (flags)
RELEASE="$DEFAULT_RELEASE"
NAMESPACE="$DEFAULT_NAMESPACE"
TIMEOUT="$DEFAULT_TIMEOUT"
LOG_SINCE="$DEFAULT_LOG_SINCE"
INSTANCE_NAME="$DEFAULT_INSTANCE_NAME"
SECRET_NAME=""
LB_LOCATION=""
LB_NAME=""
KUBE_CONTEXT=""
ASSUME_YES=false
RUN_HELM_TEST=false

# Arrays for repeatable args
VALUES_FILES=()
USER_SET_ARGS=()
EXTRA_LB_ANNOTATIONS=()

# Utilities
log() { echo -e "${CYAN}[i]${NC} $*"; }
ok() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[-]${NC} $*" 1>&2; }

fatal() { err "$*"; exit 1; }

require_bin() { command -v "$1" >/dev/null 2>&1 || fatal "Required binary not found: $1"; }

# Error trap to auto-collect debug on failure (only during install/verify)
CURRENT_ACTION=""
on_err() {
  local ec=$?
  if [[ -n "$CURRENT_ACTION" ]]; then
    warn "Action '$CURRENT_ACTION' failed with exit code $ec — collecting debug info"
    debug_collect || true
  fi
  exit "$ec"
}
trap on_err ERR

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install            Install or upgrade the release, then verify
  upgrade            Alias of install
  verify             Verify deployment and (if enabled) Service LoadBalancer
  status             Show Helm/K8s status summary
  debug              Collect detailed diagnostics into tests/output
  uninstall          Helm uninstall (never deletes your existing Secret)
  purge              Uninstall + delete release-labeled PVCs (never deletes your existing Secret)

Options:
  --release NAME           Release name (default: ${DEFAULT_RELEASE})
  --namespace NAME         Namespace (default: ${DEFAULT_NAMESPACE})
  --context NAME           kube-context to use (default: current)
  --timeout DUR            Wait timeout (default: ${DEFAULT_TIMEOUT})
  --since DUR              Log window for debug collection (default: ${DEFAULT_LOG_SINCE})
  --values FILE            Additional values file (repeatable)
  --set key=val            Additional Helm set (repeatable)

Site-specific (required for install/verify):
  --secret-name NAME       Name of existing Secret holding PANGOLIN_ENDPOINT, SITE_ID, SITE_SECRET
  --instance-name NAME     Instance name (default: ${DEFAULT_INSTANCE_NAME})

Hetzner LoadBalancer (required when accepting clients):
  --lb-location LOC        Hetzner location, e.g. fsn1/nbg1/hel1 (sets service.annotations.load-balancer.hetzner.cloud/location)
  --lb-name NAME           Optional LB name annotation (sets service.annotations.load-balancer.hetzner.cloud/name)
  --lb-annotation K=V      Extra LB annotation(s), repeatable. Example:
                           --lb-annotation load-balancer.hetzner.cloud/type=lb11

Misc:
  --yes                    Do not prompt for confirmation on destructive actions
  --run-helm-test          If Helm tests are defined, run 'helm test' after install (default: off)

Examples:
  # Install with existing secret and Hetzner LB location
  $(basename "$0") install --secret-name pangolin-site-credentials \
    --lb-location fsn1 --lb-name my-site-lb

  # Verify only
  $(basename "$0") verify --secret-name pangolin-site-credentials
EOF
}

# Parse args
if [[ $# -lt 1 ]]; then usage; exit 1; fi
CMD="$1"; shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --context) KUBE_CONTEXT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --since) LOG_SINCE="$2"; shift 2 ;;
    --values) VALUES_FILES+=("$2"); shift 2 ;;
    --set) USER_SET_ARGS+=("$2"); shift 2 ;;
    --secret-name) SECRET_NAME="$2"; shift 2 ;;
    --instance-name) INSTANCE_NAME="$2"; shift 2 ;;
    --lb-location) LB_LOCATION="$2"; shift 2 ;;
    --lb-name) LB_NAME="$2"; shift 2 ;;
    --lb-annotation) EXTRA_LB_ANNOTATIONS+=("$2"); shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    --run-helm-test) RUN_HELM_TEST=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) fatal "Unknown option: $1" ;;
    *) fatal "Unexpected argument: $1" ;;
  esac
done

kctx_args=()
hctx_args=()
if [[ -n "$KUBE_CONTEXT" ]]; then kctx_args+=("--context" "$KUBE_CONTEXT"); hctx_args+=("--kube-context" "$KUBE_CONTEXT"); fi

show_context() {
  local ctx; ctx=$(kubectl "${kctx_args[@]}" config current-context 2>/dev/null || true)
  local cluster
  if [[ -n "$ctx" ]]; then
    cluster=$(kubectl "${kctx_args[@]}" config view --minify -o jsonpath='{.contexts[?(@.name=="'"$ctx"'")].context.cluster}' 2>/dev/null || true)
  else
    cluster=""
  fi
  log "Kube context: ${ctx:-unknown}  |  Cluster: ${cluster:-unknown}"
}

confirm() {
  $ASSUME_YES && return 0
  read -r -p "${1:-Are you sure?} [y/N] " ans || true
  case "$ans" in [yY][eE][sS]|[yY]) return 0 ;; *) return 1 ;; esac
}

# Build Helm args common to install/upgrade
build_helm_args() {
  local -n _out=$1
  _out=(upgrade --install "$RELEASE" "$CHART_DIR" -n "$NAMESPACE" --create-namespace --wait --timeout "$TIMEOUT")
  local vf
  for vf in "${VALUES_FILES[@]:-}"; do _out+=( -f "$vf" ); done
  local s
  for s in "${USER_SET_ARGS[@]:-}"; do _out+=( --set "$s" ); done

  # Enable first instance, require existing secret (never created/modified here)
  _out+=( --set "siteInstances[0].enabled=true" )
  if [[ -z "$SECRET_NAME" ]]; then fatal "--secret-name is required"; fi
  _out+=( --set-string "siteInstances[0].auth.existingSecretName=$SECRET_NAME" )
  _out+=( --set "siteInstances[0].acceptClients=true" )
  _out+=( --set "siteInstances[0].service.enabled=true" )
  _out+=( --set "siteInstances[0].service.type=LoadBalancer" )

  # Hetzner LB annotations
  if [[ -z "$LB_LOCATION" ]]; then
    warn "--lb-location not provided. On your cluster, a Hetzner location annotation may be required for LB provisioning."
  else
    _out+=( --set "siteInstances[0].service.annotations.load-balancer\\.hetzner\\.cloud/location=$LB_LOCATION" )
  fi
  if [[ -n "$LB_NAME" ]]; then
    _out+=( --set "siteInstances[0].service.annotations.load-balancer\\.hetzner\\.cloud/name=$LB_NAME" )
  fi
  local kv
  for kv in "${EXTRA_LB_ANNOTATIONS[@]:-}"; do
    _out+=( --set "siteInstances[0].service.annotations.${kv//./\\.}" )
  done

  # Kube context
  if [[ ${#hctx_args[@]} -gt 0 ]]; then _out+=("${hctx_args[@]}"); fi
}

verify_ready() {
  show_context
  log "Verifying deployments in namespace '$NAMESPACE' for release '$RELEASE'"
  # Wait for deployments with the release label
  local sel="app.kubernetes.io/instance=${RELEASE}"
  local have
  have=$(kubectl -n "$NAMESPACE" "${kctx_args[@]}" get deploy -l "$sel" -o name 2>/dev/null | wc -l | awk '{print $1}') || have=0
  if [[ "${have}" -gt 0 ]]; then
    kubectl -n "$NAMESPACE" "${kctx_args[@]}" wait --for=condition=available deploy -l "$sel" --timeout="$TIMEOUT"
    ok "Deployments are Available"
  else
    warn "No Deployments found with selector: $sel"
  fi

  # Wait for Service LoadBalancer if accepting clients
  local svc_names
  svc_names=$(kubectl -n "$NAMESPACE" "${kctx_args[@]}" get svc -l "${sel},pangolin-cli.instance=${INSTANCE_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' || true)
  if [[ -n "$svc_names" ]]; then
    local name
    for name in $svc_names; do
      wait_for_lb "$name"
    done
  else
    warn "No Service found for instance ${INSTANCE_NAME}; ensure acceptClients=true and instance name matches"
  fi
}

wait_for_lb() {
  local svc="$1"
  log "Waiting for LoadBalancer on Service/${svc} (timeout ${TIMEOUT})"
  local start_ts now_ts elapsed
  start_ts=$(date +%s)
  while true; do
    local ip host
    ip=$(kubectl -n "$NAMESPACE" "${kctx_args[@]}" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    host=$(kubectl -n "$NAMESPACE" "${kctx_args[@]}" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "$ip" || -n "$host" ]]; then
      ok "Service/${svc} LoadBalancer ready: ${ip:-$host}"
      break
    fi
    now_ts=$(date +%s); elapsed=$(( now_ts - start_ts ))
    # Convert TIMEOUT (e.g., 5m, 90s) to seconds roughly; default to 300s if not parseable
    local max=300
    if [[ "$TIMEOUT" =~ ^([0-9]+)s$ ]]; then max="${BASH_REMATCH[1]}"; fi
    if [[ "$TIMEOUT" =~ ^([0-9]+)m$ ]]; then max=$(( ${BASH_REMATCH[1]} * 60 )); fi
    if (( elapsed > max )); then
      fatal "Timeout waiting for LoadBalancer on Service/${svc}"
    fi
    sleep 3
  done
}

status_summary() {
  show_context
  echo
  helm status "$RELEASE" -n "$NAMESPACE" "${hctx_args[@]}" || true
  echo
  kubectl -n "$NAMESPACE" "${kctx_args[@]}" get deploy,po,svc -l app.kubernetes.io/instance="$RELEASE" -o wide || true
  echo
  kubectl -n "$NAMESPACE" "${kctx_args[@]}" get events --sort-by=.metadata.creationTimestamp | tail -n 50 || true
}

_debug_dir="${CHART_DIR}/tests/output/pangolin-cli-${RELEASE}-$(date +%Y%m%d-%H%M%S)"

debug_collect() {
  mkdir -p "${_debug_dir}/logs"
  log "Collecting debug artifacts into ${_debug_dir}"
  (
    set +e
    helm status "$RELEASE" -n "$NAMESPACE" "${hctx_args[@]}" > "${_debug_dir}/helm-status.txt" 2>&1
    helm get values "$RELEASE" -n "$NAMESPACE" -a "${hctx_args[@]}" > "${_debug_dir}/helm-values.txt" 2>&1
    helm get manifest "$RELEASE" -n "$NAMESPACE" "${hctx_args[@]}" > "${_debug_dir}/helm-manifest.yaml" 2>&1
    kubectl -n "$NAMESPACE" "${kctx_args[@]}" get all -l app.kubernetes.io/instance="$RELEASE" -o wide > "${_debug_dir}/get-all.txt" 2>&1
    kubectl -n "$NAMESPACE" "${kctx_args[@]}" describe pods -l app.kubernetes.io/instance="$RELEASE" > "${_debug_dir}/describe-pods.txt" 2>&1
    kubectl -n "$NAMESPACE" "${kctx_args[@]}" get events --sort-by=.metadata.creationTimestamp > "${_debug_dir}/events.txt" 2>&1
    # Pod logs
    mapfile -t pods < <(kubectl -n "$NAMESPACE" "${kctx_args[@]}" get pods -l app.kubernetes.io/instance="$RELEASE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    for p in "${pods[@]:-}"; do
      kubectl -n "$NAMESPACE" "${kctx_args[@]}" logs "$p" --all-containers --timestamps --since "$LOG_SINCE" > "${_debug_dir}/logs/${p}.log" 2>&1 || true
      kubectl -n "$NAMESPACE" "${kctx_args[@]}" logs "$p" --all-containers --timestamps --since "$LOG_SINCE" --previous > "${_debug_dir}/logs/${p}-previous.log" 2>&1 || true
    done
  )
  ok "Debug artifacts written to ${_debug_dir}"
}

install_or_upgrade() {
  require_bin helm; require_bin kubectl
  show_context

  # Prechecks
  if ! kubectl "${kctx_args[@]}" get ns "$NAMESPACE" >/dev/null 2>&1; then
    log "Namespace '$NAMESPACE' will be created by Helm (--create-namespace)"
  fi
  if ! kubectl -n "$NAMESPACE" "${kctx_args[@]}" get secret "$SECRET_NAME" >/dev/null 2>&1; then
    fatal "Required Secret '$SECRET_NAME' not found in namespace '$NAMESPACE' (script never creates or modifies it)"
  fi

  local args=(); build_helm_args args
  CURRENT_ACTION="helm upgrade --install"
  log "helm ${args[*]}"
  helm "${args[@]}"

  CURRENT_ACTION="verify"
  verify_ready

  if $RUN_HELM_TEST; then
    CURRENT_ACTION="helm test"
    log "Running 'helm test' if hooks are defined"
    helm test "$RELEASE" -n "$NAMESPACE" "${hctx_args[@]}" || warn "helm test failed or no tests defined"
  fi

  CURRENT_ACTION=""
  ok "Install/upgrade successful"
}

uninstall_release() {
  require_bin helm; require_bin kubectl
  show_context
  if ! confirm "Uninstall release '$RELEASE' from namespace '$NAMESPACE'?"; then
    warn "Aborted by user"
    return 0
  fi
  CURRENT_ACTION="helm uninstall"
  helm uninstall "$RELEASE" -n "$NAMESPACE" "${hctx_args[@]}" || true
  CURRENT_ACTION=""
  ok "Uninstall completed (existing secrets were not touched)"
}

purge_release() {
  uninstall_release || true
  # Delete PVCs with release label, but never delete arbitrary secrets
  log "Deleting PVCs labeled with app.kubernetes.io/instance=$RELEASE"
  kubectl -n "$NAMESPACE" "${kctx_args[@]}" delete pvc -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found || true
  ok "Purge completed (namespace preserved; secrets untouched)"
}

case "$CMD" in
  install|upgrade) install_or_upgrade ;;
  verify) require_bin kubectl; verify_ready ;;
  status) status_summary ;;
  debug) debug_collect ;;
  uninstall) uninstall_release ;;
  purge) purge_release ;;
  *) usage; exit 1 ;;
esac

