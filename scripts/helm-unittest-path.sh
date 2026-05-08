#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <chart-path> [extra-helm-unittest-args...]" >&2
  exit 2
fi

chart_path="$1"
shift

# Normalize Windows separators so path handling is consistent across shells.
chart_path="${chart_path//\\//}"

exec helm unittest --debug --strict "$chart_path" "$@"
