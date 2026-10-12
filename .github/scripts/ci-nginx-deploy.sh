#!/usr/bin/env bash
# ==============================================================================
# Install nginx-standard use cases in parallel and smoke-test each one
# (rollout + /readiness + /healthz from inside the pod).
#
# Usage: ci-nginx-deploy.sh <namespace> <run-name> <use-case>...
#   Expects rendered values in ci-values/<use-case>.yaml; release = <run-name>-<use-case>.
# ==============================================================================
set -uo pipefail
NS="${1:?namespace required}"; RUN="${2:?run name required}"; shift 2
CHART="${CHART:-charts/nginx-standard}"
[ $# -gt 0 ] || { echo "usage: ci-nginx-deploy.sh <namespace> <run-name> <use-case>..."; exit 2; }

extra_args() {
  case "$1" in
    # values-filesharing.yaml uses a static Azure File PV (cluster-scoped, not creatable by
    # the namespace-admin CI account) and a Key Vault ExternalSecret. Both are schema-checked
    # in the lint job; here the share is replaced by an emptyDir.
    filesharing) echo "--set fileSharing.storage.pvc.enabled=false --set externalSecrets.enabled=false" ;;
    *) echo "" ;;
  esac
}

deploy_and_verify() {
  local uc="$1" release="${RUN}-$1" pod
  echo "== [$uc] installing $release"
  # shellcheck disable=SC2046
  helm upgrade --install "$release" "$CHART" -n "$NS" -f "ci-values/${uc}.yaml" $(extra_args "$uc") \
      --wait --timeout 5m || return 1
  pod=$(oc get pods -n "$NS" -l "app.kubernetes.io/name=nginx-standard,app.kubernetes.io/instance=${release}" \
          --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}') || return 1
  oc exec -n "$NS" "$pod" -- curl -sf http://localhost:8080/readiness >/dev/null || { echo "/readiness failed"; return 1; }
  oc exec -n "$NS" "$pod" -- curl -sf http://localhost:8080/healthz   >/dev/null || { echo "/healthz failed"; return 1; }
  echo "== [$uc] deployed and healthy"
}

for uc in "$@"; do
  ( deploy_and_verify "$uc" > "/tmp/deploy-${uc}.log" 2>&1; echo $? > "/tmp/deploy-${uc}.rc" ) &
done
wait

FAIL=0
for uc in "$@"; do
  echo "::group::deploy $uc"; cat "/tmp/deploy-${uc}.log"; echo "::endgroup::"
  if [ "$(cat "/tmp/deploy-${uc}.rc")" != "0" ]; then
    echo "::error::[$uc] deployment/smoke test failed"
    oc get pods -n "$NS" -l "app.kubernetes.io/instance=${RUN}-${uc}" -o wide || true
    FAIL=1
  fi
done
exit $FAIL
