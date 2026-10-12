#!/usr/bin/env bash
# ==============================================================================
# Namespace-scoped ECK operator for the nginx-standard CI, living in the CI
# namespace itself (devops-toolchain) and watching ONLY that namespace.
#
# Usage:
#   ci-eck.sh ensure  <namespace>   install/upgrade the operator if it is not running
#   ci-eck.sh release <namespace>   uninstall it again once no Elasticsearch is left
#
# Several nginx-standard runs (PRs + release) can be active at once and share one
# operator. `release` therefore only removes it when no Elasticsearch resource is
# left in the namespace, and ci-elasticsearch.sh re-runs `ensure` while it waits,
# so a run never ends up without an operator.
#
# Restricted install (no cluster-scoped objects): the CI service account cannot create
# CRDs, ClusterRoles or webhooks. The ECK CRDs already exist on the Sweden Central
# cluster - installed by OLM with the OperatorHub ECK operators (3.1.0 in Aug 2026) -
# and are NOT touched here. Keep ECK_VERSION equal to the CRD version:
#   oc get crd elasticsearches.elasticsearch.k8s.elastic.co -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}'
#
# Env (optional):
#   ECK_VERSION               eck-operator chart/operator version, default 3.1.0 (= the CRDs on the cluster)
#   ECK_OPERATOR_REPOSITORY   operator image without tag (e.g. a mirror in
#                             image-registry.int.platta.hel.fi); default docker.elastic.co/eck/eck-operator
# ==============================================================================
set -euo pipefail
CMD="${1:?usage: ci-eck.sh ensure|release <namespace>}"
NS="${2:?namespace required}"
ECK_VERSION="${ECK_VERSION:-3.1.0}"
RELEASE="ci-eck-operator"           # also the name of every object the chart creates
CHART_REPO="https://helm.elastic.co"

running() {
  [ "$(oc get statefulset "$RELEASE" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)" = "1" ]
}

ensure() {
  if ! oc api-resources --api-group=elasticsearch.k8s.elastic.co -o name 2>/dev/null | grep -q '^elasticsearches'; then
    echo "::error::ECK CRDs are not installed on $(oc whoami --show-server)."
    echo "::error::They normally come with the OperatorHub ECK operator (OLM); ask a cluster admin."
    exit 1
  fi
  local crd_version
  crd_version=$(oc get crd elasticsearches.elasticsearch.k8s.elastic.co -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || true)
  if [ -n "$crd_version" ] && [ "$crd_version" != "$ECK_VERSION" ]; then
    echo "::warning::ECK CRDs on the cluster are ${crd_version}, CI operator is ${ECK_VERSION} - set CI_ECK_VERSION=${crd_version}"
  fi
  if running && [ "$(helm get metadata "$RELEASE" -n "$NS" -o json 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')" = "$ECK_VERSION" ]; then
    echo "ECK operator ${ECK_VERSION} already running in ${NS}"
    return 0
  fi

  local image_args=()
  [ -n "${ECK_OPERATOR_REPOSITORY:-}" ] && image_args=(--set "image.repository=${ECK_OPERATOR_REPOSITORY}")

  echo "Installing ECK operator ${ECK_VERSION} in ${NS} (watching ${NS} only)"
  local attempt
  for attempt in 1 2 3; do
    if helm upgrade --install "$RELEASE" eck-operator --repo "$CHART_REPO" --version "$ECK_VERSION" \
         -n "$NS" \
         --set fullnameOverride="$RELEASE" \
         --set installCRDs=false \
         --set createClusterScopedResources=false \
         --set "managedNamespaces={${NS}}" \
         --set webhook.enabled=false \
         --set config.validateStorageClass=false \
         --set serviceMonitor.enabled=false \
         --set telemetry.disabled=true \
         --set "podLabels.app\.kubernetes\.io/part-of=helm-ci" \
         "${image_args[@]}" \
         --wait --timeout 5m; then
      echo "ECK operator ready: statefulset/${RELEASE}"
      return 0
    fi
    # another run may be installing/removing the same release right now
    echo "::warning::helm install of ${RELEASE} failed (attempt ${attempt}), retrying"
    sleep $(( attempt * 15 ))
    running && { echo "ECK operator is running now"; return 0; }
  done
  echo "::error::Could not install the ECK operator in ${NS}"
  oc get pods -n "$NS" -l "app.kubernetes.io/instance=${RELEASE}" -o wide || true
  oc describe statefulset "$RELEASE" -n "$NS" | tail -20 || true
  exit 1
}

release() {
  local left
  if ! left=$(oc get elasticsearch -n "$NS" -o name 2>/dev/null); then
    echo "::warning::Could not list Elasticsearch in ${NS} - keeping the ECK operator"
    return 0
  fi
  if [ -n "$left" ]; then
    echo "Keeping the ECK operator: Elasticsearch still in use by other runs:"
    echo "$left" | sed 's/^/  /'
    return 0
  fi
  if helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
    echo "No Elasticsearch left in ${NS} - removing the ECK operator"
    helm uninstall "$RELEASE" -n "$NS" --wait --timeout 3m \
      || echo "::warning::helm uninstall ${RELEASE} failed"
  fi
  # objects the operator creates at runtime (not part of the Helm release)
  oc delete lease elastic-operator-leader -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  oc delete configmap elastic-licensing -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
  oc delete all,configmap,secret,role,rolebinding,serviceaccount -n "$NS" \
    -l "app.kubernetes.io/instance=${RELEASE}" --ignore-not-found >/dev/null 2>&1 || true
  echo "ECK operator removed from ${NS}"
}

case "$CMD" in
  ensure)  ensure ;;
  release) release ;;
  *) echo "usage: ci-eck.sh ensure|release <namespace>"; exit 2 ;;
esac
