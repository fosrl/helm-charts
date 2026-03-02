#!/usr/bin/env bash
# Consolidated values management script
# Merges: sync-values.sh, sync-values-default.sh, enforce-release-constraints.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Usage: $0 <command> [OPTIONS]

Commands:
  sync        Sync values.yaml from dev + protected files (default)
  enforce     Enforce release constraints on a values file
  help        Show this help

Options for sync:
  -c, --chart PATH   Chart path (default: charts/newt)

Options for enforce:
  FILE                Path to values file to enforce constraints on

Examples:
  $0 sync                           # Sync charts/newt/values.yaml
  $0 sync -c charts/my-chart       # Sync specific chart
  $0 enforce charts/newt/values.yaml  # Enforce constraints
EOF
  exit 1
}

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  sync) ;;
  enforce) ;;
  help|--help|-h) usage ;;
  "") usage ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac

CHART_DIR="charts/newt"

if [ "$COMMAND" = "sync" ]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c|--chart) CHART_DIR="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done
  
  CHART_DIR="$(cd "$ROOT_DIR/$CHART_DIR" && pwd)"
  
  DEV="${CHART_DIR}/values.dev.yaml"
  PROTECTED="${CHART_DIR}/values.protected.yaml"
  OUT="${CHART_DIR}/values.yaml"
  
  command -v yq >/dev/null 2>&1 || { echo "ERROR: yq (mikefarah v4) required" >&2; exit 1; }
  test -f "$DEV" || { echo "ERROR: Missing $DEV" >&2; exit 1; }
  test -f "$PROTECTED" || { echo "ERROR: Missing $PROTECTED" >&2; exit 1; }
  
  RELEASE_SCHEMA_LINE='## yaml-language-server: $schema=./values.schema.json'
  
  TMP_DEV="$(mktemp)"
  TMP_MERGED="$(mktemp)"
  trap 'rm -f "$TMP_DEV" "$TMP_MERGED"' EXIT
  
  grep -Ev '^[[:space:]]*#{1,2}[[:space:]]*yaml-language-server:[[:space:]]*\$schema=' \
    "$DEV" > "$TMP_DEV"
  
  yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' \
    "$TMP_DEV" "$PROTECTED" > "$TMP_MERGED"
  
  awk -v schema="$RELEASE_SCHEMA_LINE" '
    BEGIN { found=0 }
    {
      if ($0 == schema) {
        if (found==0) { print $0; found=1 }
        next
      }
      print $0
    }
    END {
      if (found==0) {
        print ""
        print schema
      }
    }
  ' "$TMP_MERGED" > "$OUT"
  
  echo "Synced $OUT from $DEV with protected overrides from $PROTECTED"
  exit 0
fi

if [ "$COMMAND" = "enforce" ]; then
  FILE="${1:-}"
  [ -z "$FILE" ] && { echo "ERROR: FILE required for enforce command"; usage; }
  
  test -f "$FILE" || { echo "ERROR: File not found: $FILE" >&2; exit 1; }
  
  SCHEMA_LINE='## yaml-language-server: $schema=./values.schema.json'
  
  if ! grep -Fqx "$SCHEMA_LINE" "$FILE"; then
    awk -v schema="$SCHEMA_LINE" '
      BEGIN { inserted=0 }
      NR==1 { }
      {
        if (inserted==0) {
          if ($0 !~ /^[[:space:]]*($|#)/) {
            print schema
            print ""
            inserted=1
          }
        }
        print $0
      }
      END {
        if (inserted==0) {
          print schema
        }
      }
    ' "$FILE" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
  fi
  
  set_key_empty() {
    local key="$1"
    if grep -Eq "^[[:space:]]*${key}:[[:space:]]*" "$FILE"; then
      sed -E -i \
        "s|^([[:space:]]*${key}:[[:space:]]*).*$|\1\"\"|g" \
        "$FILE"
    else
      {
        echo ""
        echo "${key}: \"\""
      } >> "$FILE"
    fi
  }
  
  set_key_empty "pangolinEndpoint"
  set_key_empty "newtId"
  
  echo "Enforced release constraints in: $FILE"
  exit 0
fi
