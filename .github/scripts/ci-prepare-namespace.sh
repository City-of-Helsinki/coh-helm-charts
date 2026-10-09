#!/usr/bin/env bash
# Prepare the shared CI namespace: verify access and apply test fixtures.
# Usage: ci-prepare-namespace.sh <namespace>
set -euo pipefail
NS="${1:?namespace required}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! oc get namespace "$NS" >/dev/null 2>&1 && ! oc get pods -n "$NS" >/dev/null 2>&1; then
  echo "::error::Namespace '$NS' does not exist or the CI service account cannot access it."
  echo "::error::A cluster admin must run: oc apply -f .github/ci/bootstrap-namespace.yaml"
  exit 1
fi

oc project "$NS" >/dev/null
echo "Using namespace: $NS on $(oc whoami --show-server)"
oc apply -n "$NS" -f "$DIR/ci/fixtures.yaml"
