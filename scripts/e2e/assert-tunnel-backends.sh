#!/usr/bin/env bash
#
# Assert the tunnel-backend invariant behind fosrl/helm-charts#20.
#
# Pangolin advertises Newt-site backends as raw WireGuard peer addresses out of
# `pangolin.config.gerbil.subnet_group`. Gerbil creates that interface inside
# its own Pod network namespace, so those addresses are reachable from the
# Gerbil Pod and nowhere else. The pangolin-kube-controller faithfully turns
# them into a headless Service plus an EndpointSlice, and an external Traefik
# then dials an address that does not exist for it - a deterministic 502 while
# every dashboard still reports the router as healthy.
#
# The invariant: an EndpointSlice address inside the tunnel CIDR is only useful
# when the release actually has a data path to it. This script checks that, and
# the E2E workflow runs it in every mode so the check proves itself rather than
# being taken on trust.
#
#   --mode none          no data path configured. Tunnel addresses must NOT be
#                        published. This is the #20 detector; with chart
#                        defaults it is expected to FAIL, and the workflow
#                        asserts that failure.
#   --mode host-gateway  gerbil.hostGateway.enabled=true. wg0 lives in the node
#                        netns, so tunnel addresses are reachable from Pods on
#                        that node and are the correct thing to publish. At
#                        least one must be present, otherwise the fixture never
#                        exercised the path and a green run means nothing.
#   --mode bridge        gerbil.bridge.enabled=true. The controller rewrites
#                        tunnel addresses to Gerbil's Pod IP, so NO tunnel
#                        address may remain and at least one endpoint must
#                        point at the bridge.
#
# Usage:
#   assert-tunnel-backends.sh --namespace NS --mode none|host-gateway|bridge
#                             [--release NAME] [--cidr CIDR]
#                             [--bridge-address IP] [--bridge-port-range A-B]
#                             [--managed-label KEY=VALUE]
#
# Requires: kubectl, python3 (stdlib only).

set -euo pipefail

NAMESPACE=""
MODE=""
CIDR=""
RELEASE="demo"
BRIDGE_ADDRESS=""
BRIDGE_PORT_RANGE=""
# Written by the controller in ensureManagedEndpointSliceMeta; the defaults come
# from MANAGED_LABEL_KEY / MANAGED_LABEL_VALUE.
MANAGED_LABEL="app.kubernetes.io/managed-by=pangolin-kube-controller"

usage() {
  sed -n '/^# Usage:/,/^# Requires:/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --namespace)         NAMESPACE="$2"; shift 2 ;;
    --mode)              MODE="$2"; shift 2 ;;
    --cidr)              CIDR="$2"; shift 2 ;;
    --release)           RELEASE="$2"; shift 2 ;;
    --bridge-address)    BRIDGE_ADDRESS="$2"; shift 2 ;;
    --bridge-port-range) BRIDGE_PORT_RANGE="$2"; shift 2 ;;
    --managed-label)     MANAGED_LABEL="$2"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "${NAMESPACE}" ]; then
  echo "ERROR: --namespace is required" >&2
  exit 2
fi

case "${MODE}" in
  none|host-gateway|bridge) ;;
  "") echo "ERROR: --mode is required" >&2; exit 2 ;;
  *)  echo "ERROR: unknown --mode: ${MODE}" >&2; exit 2 ;;
esac

if [ "${MODE}" = "bridge" ] && { [ -z "${BRIDGE_ADDRESS}" ] || [ -z "${BRIDGE_PORT_RANGE}" ]; }; then
  echo "ERROR: --mode bridge requires --bridge-address and --bridge-port-range" >&2
  exit 2
fi

# Read the tunnel CIDR from the live ConfigMap rather than hardcoding it, so the
# check follows whatever the release was actually installed with. The `gerbil:`
# block is scoped explicitly because `subnet_group` also appears under `orgs:`.
if [ -z "${CIDR}" ]; then
  CIDR="$(kubectl -n "${NAMESPACE}" get configmap "${RELEASE}-pangolin-config" \
    -o jsonpath='{.data.config\.yml}' | awk '
      /^gerbil:[[:space:]]*$/ { in_gerbil = 1; next }
      /^[^ ]/                 { in_gerbil = 0 }
      in_gerbil && $1 == "subnet_group:" { gsub(/"/, "", $2); print $2; exit }
    ')"
fi

if [ -z "${CIDR}" ]; then
  echo "ERROR: could not determine the tunnel CIDR; pass --cidr explicitly" >&2
  exit 2
fi

echo "namespace:   ${NAMESPACE}"
echo "mode:        ${MODE}"
echo "tunnel CIDR: ${CIDR}"

slices_json="$(mktemp)"
trap 'rm -f "${slices_json}"' EXIT
kubectl -n "${NAMESPACE}" get endpointslices -l "${MANAGED_LABEL}" -o json > "${slices_json}"

python3 - "${slices_json}" "${CIDR}" "${MODE}" "${BRIDGE_ADDRESS}" "${BRIDGE_PORT_RANGE}" <<'PY'
import ipaddress
import json
import sys

path, cidr, mode, bridge_address, bridge_port_range = sys.argv[1:6]

# strict=False is load-bearing, not defensive. The chart ships
# subnet_group: "100.89.137.0/20", which is not in canonical form - it masks to
# 100.89.128.0/20. Any comparison that skips the masking step rejects the very
# addresses Pangolin hands out.
network = ipaddress.ip_network(cidr, strict=False)
if str(network) != cidr:
    print("tunnel CIDR {} masks to {}".format(cidr, network))

bridge_lo = bridge_hi = None
if bridge_port_range:
    lo, _, hi = bridge_port_range.partition("-")
    bridge_lo, bridge_hi = int(lo), int(hi)

with open(path, encoding="utf-8") as fh:
    slices = json.load(fh).get("items", [])

endpoints = []
for sl in slices:
    name = sl["metadata"]["name"]
    ports = [p.get("port") for p in sl.get("ports") or []]
    for ep in sl.get("endpoints") or []:
        for addr in ep.get("addresses") or []:
            for port in ports or [None]:
                endpoints.append((name, addr, port))

if not endpoints:
    print("\nno controller-managed EndpointSlices found")
else:
    print("\ncontroller-managed endpoints:")
    for name, addr, port in endpoints:
        print("  {:<40} {}:{}".format(name, addr, port))


def in_tunnel(addr):
    try:
        return ipaddress.ip_address(addr) in network
    except ValueError:
        return False


tunnel = [e for e in endpoints if in_tunnel(e[1])]
failures = []

if mode == "none":
    if tunnel:
        failures.append(
            "{} endpoint(s) inside the tunnel CIDR {} are published with no data "
            "path to reach them.\n"
            "Traefik will dial an address that exists only inside the Gerbil Pod "
            "network namespace and return 502.\n"
            "Enable gerbil.hostGateway.enabled (and co-locate Traefik) or "
            "gerbil.bridge.enabled.".format(len(tunnel), network)
        )
elif mode == "host-gateway":
    if not tunnel:
        failures.append(
            "expected at least one endpoint inside the tunnel CIDR {}, found none. "
            "The fixture never produced a tunnel backend, so this run proves "
            "nothing about the data path.".format(network)
        )
elif mode == "bridge":
    if tunnel:
        failures.append(
            "{} endpoint(s) still carry a raw tunnel address inside {}; the "
            "controller should have rewritten them to the Gerbil bridge.".format(
                len(tunnel), network
            )
        )
    bridged = [
        e for e in endpoints
        if e[1] == bridge_address and e[2] is not None and bridge_lo <= e[2] <= bridge_hi
    ]
    if not bridged:
        failures.append(
            "expected at least one endpoint at {}:{}-{} (the Gerbil bridge), "
            "found none.".format(bridge_address, bridge_lo, bridge_hi)
        )

if failures:
    print("\nFAIL: tunnel-backend invariant violated (mode={})".format(mode))
    for f in failures:
        print("\n  - " + f.replace("\n", "\n    "))
    sys.exit(1)

print("\nOK: tunnel-backend invariant holds (mode={})".format(mode))
PY
