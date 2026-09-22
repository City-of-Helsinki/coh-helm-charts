#!/usr/bin/env bash
# test-nginx-standard-usecase.sh <use-case>
# Runs the same per-use-case checks that release-workflow-nginx-standard.yaml's
# matrix `test` job runs for one use-case, against charts/nginx-standard.

set -uo pipefail  # not -e: we want every check below to run and report, not stop at the first failure

UC="${1:?usage: test-nginx-standard-usecase.sh <use-case>}"
CHART=charts/nginx-standard
VALUES="$CHART/values-$UC.yaml"
FAIL=0

step() { echo "-- [$UC] $*"; }
err()  { echo "::error::[$UC] $*"; FAIL=1; }

[[ -f "$VALUES" ]] || { err "no such values file: $VALUES"; exit 1; }

step "template rendering"
helm template "test-$UC" "$CHART" -f "$VALUES" --debug >/dev/null || err "helm template failed"

step "OpenShift manifest validation"
helm template "test-$UC" "$CHART" -f "$VALUES" --skip-tests \
  | yq eval 'select(.kind != null)' - \
  | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.27.0 - \
  || err "kubeconform failed on base render"

step "custom overrides (autoscaling / metrics / netpol / route)"
helm template "test-$UC-hpa" "$CHART" -f "$VALUES" \
    --set autoscaling.enabled=true --set autoscaling.minReplicas=2 --set autoscaling.maxReplicas=10 \
    --skip-tests \
  | yq eval 'select(.kind != null)' - | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.27.0 - \
  || err "kubeconform failed with autoscaling.enabled=true"

helm template "test-$UC-metrics" "$CHART" -f "$VALUES" \
    --set observability.metrics.enabled=true --set observability.serviceMonitor.enabled=true \
    --skip-tests \
  | yq eval 'select(.kind != null)' - | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.27.0 - \
  || err "kubeconform failed with metrics/serviceMonitor enabled"

helm template "test-$UC-netpol" "$CHART" -f "$VALUES" \
    --set networkPolicy.enabled=true \
    --skip-tests \
  | yq eval 'select(.kind != null)' - | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.27.0 - \
  || err "kubeconform failed with networkPolicy.enabled=true"

helm template "test-$UC-route" "$CHART" -f "$VALUES" \
    --set routes.enabled=true --set "routes.items[0].host=test-$UC.apps.example.com" \
    --skip-tests \
  | yq eval 'select(.kind != null)' - | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.27.0 - \
  || err "kubeconform failed with routes.enabled=true"

step "NGINX configuration syntax"
helm template "test-$UC" "$CHART" -f "$VALUES" \
  | yq eval 'select(.kind == "ConfigMap") | .data."nginx.conf"' - > /tmp/nginx-$UC.conf
helm template "test-$UC" "$CHART" -f "$VALUES" \
  | yq eval 'select(.kind == "ConfigMap") | .data."server.conf"' - > /tmp/server-$UC.conf

grep -q "events {" /tmp/nginx-$UC.conf || err "missing events block in nginx.conf"
grep -q "http {"   /tmp/nginx-$UC.conf || err "missing http block in nginx.conf"
OPEN=$(grep -o "{" /tmp/nginx-$UC.conf | wc -l)
CLOSE=$(grep -o "}" /tmp/nginx-$UC.conf | wc -l)
[[ "$OPEN" -eq "$CLOSE" ]] || err "unbalanced braces in nginx.conf (open: $OPEN, close: $CLOSE)"

step "gixy security scan"
.github/scripts/gixy-helm.sh \
    --chart "$CHART" \
    --name "test-$UC" \
    -f "$VALUES" \
    --map nginx.conf=/etc/nginx/nginx.conf \
    --map server.conf=/opt/app-root/etc/nginx.default.d/server.conf \
    --fail-on high \
  || err "gixy found high-severity issues"

step "use-case specific validations"
case "$UC" in
  filesharing)
    helm template "test-$UC" "$CHART" -f "$VALUES" | yq eval 'select(.kind == "PersistentVolumeClaim")' - > /tmp/pvc-$UC.yaml
    [[ -s /tmp/pvc-$UC.yaml ]] || err "PVC not generated for filesharing mode"
    MODE=$(yq eval '.fileSharing.storage.mode' "$VALUES")
    if [[ "$MODE" == "static" ]]; then
      helm template "test-$UC" "$CHART" -f "$VALUES" | yq eval 'select(.kind == "ExternalSecret")' - > /tmp/es-$UC.yaml
      [[ -s /tmp/es-$UC.yaml ]] || err "ExternalSecret not generated for static filesharing mode"
    fi
    ;;
  elasticproxy)
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "ELASTICSEARCH_URL")' - > /tmp/es-env-$UC.yaml
    [[ -s /tmp/es-env-$UC.yaml ]] || err "ELASTICSEARCH_URL not set for elasticproxy"
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "ConfigMap") | .data."nginx.conf"' - | grep -q "ngx_http_perl_module" \
      || err "perl module not loaded for elasticproxy"
    ;;
  cache)
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "Deployment") | .spec.template.spec.volumes[] | select(.name == "cache-volume")' - > /tmp/cache-vol-$UC.yaml
    [[ -s /tmp/cache-vol-$UC.yaml ]] || err "cache volume not created"
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "ConfigMap") | .data."nginx.conf"' - | grep -q "proxy_cache_path" \
      || err "proxy_cache_path not configured"
    ;;
  frontproxy)
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "HOST_PROXY")' - > /tmp/host-proxy-env-$UC.yaml
    [[ -s /tmp/host-proxy-env-$UC.yaml ]] || err "HOST_PROXY not set for frontproxy"
    helm template "test-$UC" "$CHART" -f "$VALUES" \
      | yq eval 'select(.kind == "ConfigMap") | .data."nginx.conf"' - | grep -q "ngx_http_perl_module" \
      || err "perl module not loaded for frontproxy"
    ;;
  *)
    err "no use-case-specific validation defined for '$UC' — add one or confirm none is needed"
    ;;
esac

if [[ $FAIL -eq 0 ]]; then
  echo "-- [$UC] all checks passed"
else
  echo "-- [$UC] one or more checks FAILED (see ::error:: lines above)"
fi
exit $FAIL
