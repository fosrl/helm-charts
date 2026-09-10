#!/usr/bin/env bash
# Fail when the controller publishes tunnel-subnet addresses that nothing can route to.
#
# Pangolin advertises Newt-site backends as WireGuard peer addresses. The controller
# materialises them into EndpointSlices verbatim, so an address inside the tunnel CIDR is
# only reachable if a data path exists - today that means Gerbil running in host gateway
# mode with Traefik co-located on the same node. Publishing such an address without one
# is the exact failure in fosrl/helm-charts#20: Traefik reports the router healthy and
# every request 502s.
#
# Usage:
#   assert-tunnel-backends.sh --namespace <ns> --tunnel-cidr <cidr> [--expect-data-path]
#   assert-tunnel-backends.sh --file <endpointslices.json> --tunnel-cidr <cidr> ...
#
# --expect-data-path  a data path is configured; tunnel addresses are allowed and the
#                     script additionally verifies Gerbil and Traefik share a node.
# Without it, any tunnel-CIDR address is a failure.
#
# --file lets the address logic be exercised against a fixture without a cluster.

set -euo pipefail

NAMESPACE=""
TRAEFIK_NAMESPACE=""
TUNNEL_CIDR=""
INPUT_FILE=""
EXPECT_DATA_PATH="false"

die() { echo "ERROR: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    --traefik-namespace) TRAEFIK_NAMESPACE="$2"; shift 2 ;;
    -c|--tunnel-cidr) TUNNEL_CIDR="$2"; shift 2 ;;
    -f|--file) INPUT_FILE="$2"; shift 2 ;;
    --expect-data-path) EXPECT_DATA_PATH="true"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TUNNEL_CIDR" ] || die "--tunnel-cidr is required"
[ -n "$INPUT_FILE" ] || [ -n "$NAMESPACE" ] || die "--namespace or --file is required"

if [ -n "$INPUT_FILE" ]; then
  [ -f "$INPUT_FILE" ] || die "no such file: $INPUT_FILE"
  slices_json="$(cat "$INPUT_FILE")"
else
  slices_json="$(kubectl -n "$NAMESPACE" get endpointslices -o json)"
fi

# Collect every published address together with the slice that carries it.
mapfile -t entries < <(
  printf '%s' "$slices_json" |
    python3 -c '
import json, sys
doc = json.load(sys.stdin)
for item in doc.get("items", []):
    name = item.get("metadata", {}).get("name", "<unnamed>")
    for endpoint in item.get("endpoints", []) or []:
        for address in endpoint.get("addresses", []) or []:
            print("%s\t%s" % (name, address))
'
)

in_cidr() {
  # Values are stripped: a CR survives here when the JSON was produced on a platform
  # that writes CRLF, and ip_address() rejects it.
  python3 -c '
import ipaddress, sys
try:
    address = ipaddress.ip_address(sys.argv[1].strip())
    network = ipaddress.ip_network(sys.argv[2].strip(), strict=False)
    sys.stdout.write("yes" if address in network else "no")
except ValueError:
    sys.stdout.write("no")
' "$1" "$2"
}

tunnel_hits=()
for entry in "${entries[@]:-}"; do
  [ -n "$entry" ] || continue
  slice="${entry%%$'\t'*}"
  address="${entry##*$'\t'}"
  if [ "$(in_cidr "$address" "$TUNNEL_CIDR")" = "yes" ]; then
    tunnel_hits+=("$slice=$address")
  fi
done

echo "Published endpoint addresses: ${#entries[@]}"
echo "Inside the tunnel CIDR ($TUNNEL_CIDR): ${#tunnel_hits[@]}"
for hit in "${tunnel_hits[@]:-}"; do
  [ -n "$hit" ] && echo "  $hit"
done

if [ "$EXPECT_DATA_PATH" != "true" ]; then
  if [ "${#tunnel_hits[@]}" -gt 0 ]; then
    cat >&2 <<'EOF'

FAIL: the controller published addresses inside the tunnel subnet while no data path is
configured. Traefik will report these routers healthy and return 502 for every request.
Enable gerbil.hostGateway and co-locate Traefik, or use a local site whose target is a
Kubernetes Service FQDN.
EOF
    exit 1
  fi
  echo "OK: no unroutable tunnel addresses published."
  exit 0
fi

# A data path is claimed - verify the part of it the cluster can actually confirm.
[ -n "$NAMESPACE" ] || die "--expect-data-path requires --namespace"

gerbil_node="$(kubectl -n "$NAMESPACE" get pods \
  -l app.kubernetes.io/component=gerbil \
  -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)"
[ -n "$gerbil_node" ] || die "no Gerbil Pod found in namespace $NAMESPACE"

host_network="$(kubectl -n "$NAMESPACE" get pods \
  -l app.kubernetes.io/component=gerbil \
  -o jsonpath='{.items[0].spec.hostNetwork}' 2>/dev/null || true)"
[ "$host_network" = "true" ] || die "Gerbil is not running with hostNetwork; the tunnel route stays in its Pod namespace"

echo "Gerbil runs on node $gerbil_node with hostNetwork=true"

if [ -n "$TRAEFIK_NAMESPACE" ]; then
  mapfile -t traefik_nodes < <(
    kubectl -n "$TRAEFIK_NAMESPACE" get pods -l app.kubernetes.io/name=traefik \
      -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u
  )
  [ "${#traefik_nodes[@]}" -gt 0 ] || die "no Traefik Pods found in namespace $TRAEFIK_NAMESPACE"
  for node in "${traefik_nodes[@]}"; do
    [ "$node" = "$gerbil_node" ] || die "Traefik runs on $node but Gerbil is on $gerbil_node; tunnel backends are unreachable from there"
  done
  echo "All Traefik Pods share the Gerbil node"
fi

echo "OK: tunnel addresses are published and a data path is in place."
