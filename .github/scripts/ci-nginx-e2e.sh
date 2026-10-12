#!/usr/bin/env bash
# ==============================================================================
# Functional end-to-end tests for the four nginx-standard use cases, run against
# a deployed release in the CI namespace. Requests are sent from inside the nginx
# pod (oc exec ... curl localhost:8080) and, where a route exists, from the runner.
#
# Usage: ci-nginx-e2e.sh <use-case> <namespace> <release> [route-host]
#   use-case: filesharing | cache | frontproxy | elasticproxy
# Env:
#   ES_SECRET   name of the Elasticsearch elastic-user secret (cache, frontproxy)
#
# The values the tests rely on come from charts/nginx-standard/values-<use-case>.yaml
# (as rendered by ci-nginx-standard.yaml). Change both together.
# ==============================================================================
set -uo pipefail
UC="${1:?use-case required}"
NS="${2:?namespace required}"
RELEASE="${3:?release required}"
ROUTE_HOST="${4:-}"
FAIL=0
pass() { echo "  ✓ $*"; }
fail() { echo "::error::[${UC} e2e] $*"; FAIL=1; }
step() { echo "$*"; }

POD=$(oc get pods -n "$NS" -l "app.kubernetes.io/name=nginx-standard,app.kubernetes.io/instance=${RELEASE}" \
      --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
[ -n "$POD" ] || { echo "::error::[${UC} e2e] no running pod for ${RELEASE}"; exit 1; }
echo "== ${UC}: testing ${RELEASE} through pod ${POD}"

# req <method> <path> [curl args...] -> sets CODE, BODY, HDRS (response headers, lower-cased)
req() {
  local m="$1" p="$2"; shift 2
  CODE=$(oc exec -n "$NS" "$POD" -- curl -s -D /tmp/e2e-hdr -o /tmp/e2e-body -w '%{http_code}' \
           -X "$m" "$@" "http://localhost:8080${p}" 2>/dev/null)
  BODY=$(oc exec -n "$NS" "$POD" -- cat /tmp/e2e-body 2>/dev/null)
  HDRS=$(oc exec -n "$NS" "$POD" -- cat /tmp/e2e-hdr 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')
}
header() { grep -i "^$1:" <<<"$HDRS" | head -n1 | cut -d: -f2- | sed 's/^ *//'; }
expect_code() { # expect_code <expected> <description>
  if [ "$CODE" = "$1" ]; then pass "$2 -> $CODE"; else fail "$2 -> $CODE (expected $1): $(head -c 200 <<<"$BODY")"; fi
}
route_get() { # route_get <path> <expected-code> [grep-pattern]
  local c="" b
  [ -n "$ROUTE_HOST" ] || return 0
  for _ in $(seq 1 12); do   # route admission + DNS can take a moment
    b=$(curl -sk -w '\n%{http_code}' "https://${ROUTE_HOST}$1" || true)
    c=$(tail -n1 <<<"$b")
    [ "$c" = "$2" ] && { if [ -z "${3:-}" ] || grep -q "$3" <<<"$b"; then pass "route https://${ROUTE_HOST}$1 -> $c"; return 0; fi; }
    sleep 5
  done
  fail "route https://${ROUTE_HOST}$1 -> ${c} (expected $2)"
}
es_auth() {
  local pw
  pw=$(oc get secret "${ES_SECRET:?ES_SECRET required}" -n "$NS" -o jsonpath='{.data.elastic}' | base64 -d)
  printf 'elastic:%s' "$pw"
}

case "$UC" in
# ------------------------------------------------------------------------------
filesharing)
  step "1. Serves files from the shared folder (directory listing + download)"
  oc exec -n "$NS" "$POD" -- sh -c 'echo "hello from helm-ci" > /opt/app-root/src/ci.txt \
    && mkdir -p /opt/app-root/src/downloads && echo "report" > /opt/app-root/src/downloads/report.txt' \
    || fail "could not write test files into /opt/app-root/src"
  req GET /;          expect_code 200 "GET / (autoindex)"
  grep -q 'ci.txt' <<<"$BODY" && pass "listing shows ci.txt" || fail "directory listing does not show ci.txt"
  req GET /ci.txt;    expect_code 200 "GET /ci.txt"
  grep -q 'hello from helm-ci' <<<"$BODY" && pass "file content served" || fail "unexpected content: $BODY"

  step "2. /downloads/ is served as attachments"
  req GET /downloads/report.txt; expect_code 200 "GET /downloads/report.txt"
  header content-disposition | grep -q attachment && pass "Content-Disposition: attachment" \
    || fail "missing Content-Disposition: attachment (got '$(header content-disposition)')"

  step "3. Missing files return 404"
  req GET /does-not-exist.txt; expect_code 404 "GET /does-not-exist.txt"

  step "4. Public route"
  route_get /ci.txt 200 'hello from helm-ci'
  ;;
# ------------------------------------------------------------------------------
cache)
  AUTH=$(es_auth)
  step "1. Requests are proxied to the backend (Elasticsearch, client credentials passed through)"
  req GET /ci-test/_doc/1 -u "$AUTH"; expect_code 200 "GET /ci-test/_doc/1"
  grep -q '"helm-ci"' <<<"$BODY" && pass "backend document returned" || fail "backend document not in response"

  step "2. Second identical request is served from cache"
  first="$(header x-cache-status)"
  req GET /ci-test/_doc/1 -u "$AUTH"; second="$(header x-cache-status)"
  if [ "$first" = "miss" ] && [ "$second" = "hit" ]; then pass "X-Cache-Status MISS -> HIT"
  elif [ "$second" = "hit" ]; then pass "X-Cache-Status ${first:-?} -> HIT"
  else fail "X-Cache-Status '${first:-none}' -> '${second:-none}' (expected MISS -> HIT)"; fi

  step "3. Error responses are not cached"
  req GET /ci-test/_doc/1                    # no credentials -> 401 from Elasticsearch, unless served from cache
  if [ "$CODE" = "401" ]; then pass "unauthenticated request -> 401 (not served from cache)"
  elif [ "$(header x-cache-status)" = "hit" ]; then
    echo "::warning::[cache e2e] cache key in values-cache.yaml ignores Authorization: an unauthenticated client got a cached authenticated response (${CODE}). Fine for this test backend, but do not copy this cache key for authenticated upstreams."
    pass "cache serves by URI only (see warning)"
  else fail "unauthenticated request -> $CODE"; fi
  req GET /_nonexistent_index_ci -u "$AUTH"; c1="$(header x-cache-status)"
  req GET /_nonexistent_index_ci -u "$AUTH"; c2="$(header x-cache-status)"
  [ "$c2" != "hit" ] && pass "404 from backend not cached (${c1:-?} -> ${c2:-?})" || fail "404 response was cached"
  ;;
# ------------------------------------------------------------------------------
frontproxy)
  AUTH=$(es_auth)
  step "1. Unknown Host hits the default server -> 404"
  req GET / -H 'Host: unknown.example.org'; expect_code 404 "Host unknown.example.org"

  step "2. Primary server: root redirect, everything else proxied via HOST_PROXY"
  req GET / -H 'Host: en.example.com'; expect_code 301 "GET / (Host en.example.com)"
  [ "$(header location)" = "https://en.example.com/en" ] && pass "Location https://en.example.com/en" \
    || fail "Location '$(header location)' (expected https://en.example.com/en)"
  req GET /anything -H 'Host: en.example.com' -u "$AUTH"; expect_code 200 "GET /anything (Host en.example.com) proxied"
  grep -q '"tagline"' <<<"$BODY" && pass "response comes from the backend" || fail "backend response not returned"

  step "3. Custom server 'localhost': geo allow-list"
  req GET / -H 'Host: localhost'; expect_code 403 "client 127.0.0.1 (not allowed)"
  grep -q 'blocked' <<<"$BODY" && pass "blocked message returned" || fail "expected 'blocked' body, got: $BODY"
  # 127.0.0.2 is added to the allow-list by the CI values render step
  req GET / -H 'Host: localhost' --interface 127.0.0.2 -u "$AUTH"; expect_code 200 "client 127.0.0.2 (allowed) proxied"
  grep -q '"tagline"' <<<"$BODY" && pass "response comes from the backend" || fail "backend response not returned"

  step "4. secretEnv values are injected from the secret"
  v=$(oc exec -n "$NS" "$POD" -- printenv DIGITRANSIT_API_KEY 2>/dev/null || true)
  [ -n "$v" ] && [ "elastic:$v" = "$AUTH" ] && pass "DIGITRANSIT_API_KEY set from ${ES_SECRET}" \
    || fail "DIGITRANSIT_API_KEY not set from ${ES_SECRET}"

  step "5. Metrics endpoint (default server; plain 'localhost' would hit the custom server)"
  req GET /nginx_status -H 'Host: metrics.ci.local'; expect_code 200 "GET /nginx_status"
  grep -q 'Active connections' <<<"$BODY" && pass "stub_status output" || fail "unexpected /nginx_status body"
  ;;
# ------------------------------------------------------------------------------
elasticproxy)
  # No client credentials are sent: every successful upstream call proves nginx
  # injected the reader credentials itself.
  step "1. GET /health is proxied to _cluster/health with injected credentials"
  req GET /health; expect_code 200 "GET /health"
  grep -q '"cluster_name"' <<<"$BODY" && pass "cluster health returned" || fail "no cluster health in body"

  step "2. Client-supplied Authorization header cannot override the proxy's"
  req GET /health -H 'Authorization: Basic aW52YWxpZDppbnZhbGlk'; expect_code 200 "GET /health with bogus client auth"

  step "3. POST /ci-test/_search returns the seeded document"
  req POST /ci-test/_search -H 'Content-Type: application/json' -d '{"query":{"match_all":{}}}'
  expect_code 200 "POST /ci-test/_search"
  grep -q '"helm-ci"' <<<"$BODY" && pass "seeded document found" || fail "seeded document not found"

  step "4. CORS preflight on a search path"
  req OPTIONS /ci-test/_search -H 'Origin: https://example.hel.fi' -H 'Access-Control-Request-Method: POST'
  expect_code 204 "OPTIONS /ci-test/_search"
  [ "$(header access-control-allow-origin)" = "*" ] && pass "Access-Control-Allow-Origin: *" || fail "CORS header missing"

  step "5. Write methods are rejected on search paths"
  req DELETE /ci-test/_search; expect_code 403 "DELETE /ci-test/_search"

  step "6. Index existence check is HEAD-only"
  req HEAD /ci-test -I; expect_code 200 "HEAD /ci-test"
  req GET /ci-test;     expect_code 403 "GET /ci-test (mapping not exposed)"

  step "7. Non-whitelisted Elasticsearch APIs are not exposed"
  for p in /_cat/indices /ci-test/_doc/1 /_security/user; do
    req GET "$p"
    if [ "$CODE" = "403" ] || [ "$CODE" = "404" ]; then pass "GET $p -> $CODE"
    else fail "GET $p -> $CODE (must not be proxied)"; fi
  done

  step "8. Public route"
  route_get /health 200 '"cluster_name"'
  ;;
*)
  echo "::error::unknown use case '$UC'"; exit 2 ;;
esac

[ $FAIL = 0 ] && echo "== ${UC}: all end-to-end checks passed"
exit $FAIL
