#!/usr/bin/env bash
# ==============================================================================
# Remove everything a CI run created in the shared namespace.
#
# Usage: ci-cleanup.sh <namespace> <release-regex>
#   <release-regex> is an extended regex matched against Helm release names and
#   object names, e.g. '^ci-redis-'  or  '^ci-helfi-pr-12$'  or  '^ci-nginx-pr-12-'
#
# Removes, for every matching release:
#   1. the Helm release (including failed/pending ones), waiting for deletion
#   2. any object still labelled app.kubernetes.io/instance=<release>
#      (catches leftovers when the Helm record is already gone)
#   3. StatefulSet PVCs (data-<release>-*), which Helm never deletes
# and, independently of releases:
#   4. Secrets / ConfigMaps whose NAME matches the regex (created by the workflow
#      itself with `oc create secret`, e.g. ci-redis-secret)
#
# Shared fixtures from .github/ci/fixtures.yaml are NOT touched - other charts'
# runs may be using them concurrently.
# Never fails the job: cleanup problems are reported as warnings.
# ==============================================================================
set -uo pipefail
NS="${1:?namespace required}"
PAT="${2:?release regex required}"

KINDS="deployment statefulset daemonset job cronjob pod service route ingress configmap secret
persistentvolumeclaim horizontalpodautoscaler poddisruptionbudget networkpolicy
serviceaccount role rolebinding externalsecret secretstore servicemonitor elasticsearch"

# releases from Helm (all states) + instance labels still present on objects
RELEASES=$( {
  helm list -n "$NS" -a -q 2>/dev/null
  oc get all,configmap,secret,pvc -n "$NS" \
    -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/instance}{"\n"}{end}' 2>/dev/null
  # ECK Elasticsearch clusters created by the nginx-standard CI (CRD may be absent)
  oc get elasticsearch -n "$NS" \
    -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/instance}{"\n"}{end}' 2>/dev/null
} | grep -E "$PAT" | sort -u )

if [ -z "$RELEASES" ]; then
  echo "No releases matching '$PAT' in $NS"
fi

for r in $RELEASES; do
  echo "::group::Cleaning release $r"
  if helm status "$r" -n "$NS" >/dev/null 2>&1; then
    helm uninstall "$r" -n "$NS" --wait --timeout 5m \
      || helm uninstall "$r" -n "$NS" --no-hooks --wait --timeout 5m \
      || echo "::warning::helm uninstall $r failed"
  fi
  for k in $KINDS; do
    oc delete "$k" -n "$NS" -l "app.kubernetes.io/instance=$r" \
      --ignore-not-found --wait=true --timeout=120s 2>/dev/null || true
  done
  oc get pvc -n "$NS" -o name 2>/dev/null | grep -E "^persistentvolumeclaim/[a-z0-9-]+-${r}-" \
    | xargs -r oc delete -n "$NS" --wait=true --timeout=120s || true
  echo "::endgroup::"
done

# workflow-created secrets/configmaps (by name); never Helm's own release records
oc get secret,configmap -n "$NS" -o name 2>/dev/null \
  | grep -E "^(secret|configmap)/" | grep -v "/sh\.helm\.release\." \
  | awk -F/ -v pat="$PAT" '$2 ~ pat' \
  | xargs -r oc delete -n "$NS" --ignore-not-found || true

# report anything left behind
LEFT=$(oc get all,configmap,secret,pvc,networkpolicy,rolebinding -n "$NS" \
  -o jsonpath='{range .items[*]}{.kind}/{.metadata.name} {.metadata.labels.app\.kubernetes\.io/instance}{"\n"}{end}' 2>/dev/null \
  | awk -v pat="$PAT" '{ split($1,a,"/"); if (a[2] ~ pat || $2 ~ pat) print $1 }')
if [ -n "$LEFT" ]; then
  echo "::warning::Objects still present after cleanup (may be terminating):"
  echo "$LEFT" | sed 's/^/  /'
else
  echo "Namespace $NS is clean for '$PAT'"
fi
exit 0
