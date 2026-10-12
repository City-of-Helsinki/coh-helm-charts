#!/usr/bin/env bash
# ==============================================================================
# Throw-away single-node Elasticsearch (ECK) for the nginx-standard CI.
#
# Usage:
#   ci-elasticsearch.sh create <namespace> <name>
#       Applies the Elasticsearch resource and returns as soon as ECK has created
#       the service and the elastic-user secret (seconds). That is all the cache and
#       front-proxy use cases need to start, so they deploy while ES warms up.
#   ci-elasticsearch.sh wait <namespace> <name>
#       Waits until Elasticsearch is ready and seeds the index "ci-test".
#
#   <name> = Elasticsearch resource name, max 36 chars. ECK then creates
#            service  <name>-es-http          (port 9200, self-signed TLS)
#            secret   <name>-es-elastic-user  (key: elastic)
#
# Env (optional):
#   ES_VERSION  Elasticsearch version, default 8.15.3 (must be supported by the cluster's ECK)
#   ES_IMAGE    Full image override, e.g. a mirror in image-registry.int.platta.hel.fi
#   ES_TIMEOUT  Seconds to wait for readiness, default 600
#
#   ECK_VERSION / ECK_OPERATOR_REPOSITORY  passed on to ci-eck.sh
#
# The ECK operator runs in the CI namespace itself (ci-eck.sh, namespace-scoped, installed
# on demand and removed by `ci-eck.sh release` when no Elasticsearch is left). The ECK CRDs
# are installed once by a cluster admin. The resource and its pods carry
# app.kubernetes.io/instance=<name>, so ci-cleanup.sh removes them; deleting the resource
# garbage-collects everything ECK created.
# ==============================================================================
set -euo pipefail
CMD="${1:?usage: ci-elasticsearch.sh create|wait <namespace> <name>}"
NS="${2:?namespace required}"
NAME="${3:?elasticsearch name required}"
ES_VERSION="${ES_VERSION:-8.15.3}"
ES_TIMEOUT="${ES_TIMEOUT:-600}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
[ "${#NAME}" -le 36 ] || { echo "::error::Elasticsearch name '$NAME' is longer than 36 characters"; exit 1; }

create() {
  if ! oc api-resources --api-group=elasticsearch.k8s.elastic.co -o name 2>/dev/null | grep -q '^elasticsearches'; then
    echo "::error::ECK CRDs (elasticsearch.k8s.elastic.co) not found on $(oc whoami --show-server). They normally come with the OperatorHub ECK operator (OLM); ask a cluster admin."
    exit 1
  fi
  local image_line=""
  [ -n "${ES_IMAGE:-}" ] && image_line="  image: ${ES_IMAGE}"

  echo "Creating Elasticsearch ${NAME} (${ES_VERSION}) in ${NS}"
  oc apply -n "$NS" -f - <<YAML
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: ${NAME}
  labels:
    app.kubernetes.io/instance: ${NAME}
    app.kubernetes.io/part-of: helm-ci
spec:
  version: ${ES_VERSION}
${image_line}
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false          # no vm.max_map_count sysctl needed on OpenShift
        xpack.ml.enabled: false
      podTemplate:
        metadata:
          labels:
            app.kubernetes.io/instance: ${NAME}
        spec:
          containers:
            - name: elasticsearch
              env:
                - name: ES_JAVA_OPTS
                  value: "-Xms512m -Xmx512m"
              resources:
                requests: {cpu: 250m, memory: 1Gi}
                limits:   {memory: 1Gi}
          volumes:
            - name: elasticsearch-data        # ephemeral: no PVC to clean up
              emptyDir: {}
YAML

  # Resource first, operator second: another run's `ci-eck.sh release` then sees this
  # Elasticsearch and keeps the shared operator.
  bash "$SCRIPTS/ci-eck.sh" ensure "$NS"

  # ECK creates these right away; the cache and front-proxy pods only need them to exist
  for _ in $(seq 1 60); do
    if oc get service "${NAME}-es-http" -n "$NS" >/dev/null 2>&1 \
       && oc get secret "${NAME}-es-elastic-user" -n "$NS" >/dev/null 2>&1; then
      echo "Service ${NAME}-es-http and secret ${NAME}-es-elastic-user exist"
      return 0
    fi
    sleep 2
  done
  echo "::error::ECK did not create ${NAME}-es-http / ${NAME}-es-elastic-user within 120s (is the operator running?)"
  oc get elasticsearch "$NAME" -n "$NS" -o yaml | tail -20 || true
  exit 1
}

wait_ready() {
  echo "Waiting up to ${ES_TIMEOUT}s for ${NAME} to become ready..."
  local deadline phase health
  deadline=$(( $(date +%s) + ES_TIMEOUT ))
  while :; do
    # a parallel run may have removed the shared operator just before this run created its ES
    oc get statefulset ci-eck-operator -n "$NS" >/dev/null 2>&1 || bash "$SCRIPTS/ci-eck.sh" ensure "$NS"
    phase=$(oc get elasticsearch "$NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    health=$(oc get elasticsearch "$NAME" -n "$NS" -o jsonpath='{.status.health}' 2>/dev/null || true)
    echo "  phase=${phase:-?} health=${health:-?}"
    if [ "$phase" = "Ready" ] && { [ "$health" = "green" ] || [ "$health" = "yellow" ]; }; then break; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "::error::Elasticsearch ${NAME} not ready after ${ES_TIMEOUT}s"
      oc get elasticsearch,pods -n "$NS" -l "app.kubernetes.io/instance=${NAME}" -o wide || true
      oc describe pods -n "$NS" -l "app.kubernetes.io/instance=${NAME}" | tail -40 || true
      exit 1
    fi
    sleep 10
  done

  local pod="${NAME}-es-default-0" pw count
  pw=$(oc get secret "${NAME}-es-elastic-user" -n "$NS" -o jsonpath='{.data.elastic}' | base64 -d)
  es() { oc exec -n "$NS" "$pod" -c elasticsearch -- curl -sk -u "elastic:${pw}" -H 'Content-Type: application/json' "$@"; }

  echo "Seeding index ci-test"
  es -X PUT  "https://localhost:9200/ci-test" -d '{"settings":{"number_of_replicas":0}}' >/dev/null
  es -X POST "https://localhost:9200/ci-test/_doc/1?refresh=true" -d '{"title":"helm-ci","source":"coh-helm-charts"}' >/dev/null
  count=$(es "https://localhost:9200/ci-test/_count" | sed -E 's/.*"count":([0-9]+).*/\1/')
  [ "${count:-0}" -ge 1 ] || { echo "::error::Seeding ci-test failed (count=${count:-?})"; exit 1; }
  echo "Elasticsearch ${NAME} ready: service ${NAME}-es-http, secret ${NAME}-es-elastic-user, ci-test docs=${count}"
}

case "$CMD" in
  create) create ;;
  wait)   wait_ready ;;
  *) echo "usage: ci-elasticsearch.sh create|wait <namespace> <name>"; exit 2 ;;
esac
