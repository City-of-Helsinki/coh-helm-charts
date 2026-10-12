#!/usr/bin/env bash
# Prepare the CI namespace: verify access and apply test fixtures.
# Usage: ci-prepare-namespace.sh <namespace>
#
# The namespace (devops-toolchain) is shared with real workloads, so a fixture is only
# (re)applied if no object of that name exists yet, or the existing one carries the
# fixture label. Anything else is left alone and the job fails loudly.
set -euo pipefail
NS="${1:?namespace required}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$DIR/ci/fixtures.yaml"
LABEL_KEY="app.kubernetes.io/part-of"
LABEL_VAL="helm-ci-fixtures"

if ! oc get namespace "$NS" >/dev/null 2>&1 && ! oc get pods -n "$NS" >/dev/null 2>&1; then
  echo "::error::Namespace '$NS' does not exist or the CI service account cannot access it."
  echo "::error::A cluster admin must run: oc apply -f .github/ci/bootstrap-namespace.yaml"
  exit 1
fi

oc project "$NS" >/dev/null
echo "Using namespace: $NS on $(oc whoami --show-server)"

# kind/name of every fixture, e.g. "secret/ci-fixture-varnish-secret"
for obj in $(oc create --dry-run=client -o name -f "$FIXTURES"); do
  label=$(oc get "$obj" -n "$NS" -o "jsonpath={.metadata.labels.app\.kubernetes\.io/part-of}" 2>/dev/null || true)
  if oc get "$obj" -n "$NS" >/dev/null 2>&1 && [ "$label" != "$LABEL_VAL" ]; then
    echo "::error::$obj already exists in $NS without label $LABEL_KEY=$LABEL_VAL - refusing to overwrite it"
    exit 1
  fi
done
oc apply -n "$NS" -f "$FIXTURES"
