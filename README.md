# coh-helm-charts
Helm charts for city of helsinki

## Versioning

Chart versions are plain [SemVer 2.0](https://semver.org) – `1.2.3`, never `v1.2.3`.
Release workflows accept `1.2.3` (a leading `v` in the input is stripped), validate the
format and refuse to re-release an existing version. Git tags keep the
`<chart>-v<version>` form (e.g. `nginx-standard-v1.2.3`) so tag history stays continuous.

## Images

Templates contain no registry hostnames. Every chart (except mailpit-openshift, which wraps
the upstream mailpit chart) supports:

| Value | Purpose |
|---|---|
| `global.imageRegistry` | Registry prepended to images that do not set their own `registry` (default `image-registry.int.platta.hel.fi`) |
| `global.imagePullSecrets` | Pull secrets added to every pod, merged with the chart's own list |
| `<image>.registry` / `.repository` / `.tag` / `.digest` | Per-image settings; `digest` wins over `tag` |

Platform deployments get registry and tags from
`pipeline-templates/common/helm-values/` (one file per chart, one file per region), so a
component upgrade is a one-line change there.

Backwards compatible: `nginx.image.full`, a string `redis.image`, and a varnish
`image.repository` that still contains a registry host all keep working.

## CI

Every chart has the same three workflows:

| File | Name in GitHub | Runs on | Does |
|---|---|---|---|
| `ci-<chart>.yaml` | `CI: <chart>` | called by the two below | **lint** (helm lint, unit tests, kubeconform, chart-specific checks, gixy) + **integration** on OpenShift |
| `pr-<chart>.yaml` | `PR: <chart>` | pull requests touching `charts/<chart>/**` | runs `ci-<chart>` |
| `release-<chart>.yaml` | `Release: <chart>` | manual run with a version, or tag `<chart>-v1.2.3` | runs `ci-<chart>`, then `release-chart.yaml` |

`release-chart.yaml` (`Release: chart (reusable)`) holds the release steps shared by all charts:
SemVer check, changelog (commits under `charts/<chart>/` since the previous tag), package,
publish to `coh-helm-repo` and GitHub release. A release only happens after the same tests
a PR runs have passed.

Charts: `helfi-proxy-nginx`, `mailpit-openshift`, `nginx-standard`, `redis-cluster`, `varnish-drupal`.

Shared pieces: `.github/actions/setup-ci-tools` (pinned Helm v3.19.2, kubeconform, yq,
helm-unittest, gixy, oc) and `.github/actions/openshift-login`.

> Branch protection: status check names changed, e.g. `ci / lint` and
> `ci / integration (OpenShift)`. Update required checks if you use them.

### Integration tests

All integration tests run on the **Sweden Central** OpenShift cluster, in one shared
namespace: `platta-components-helm-ci`. Each run uses its own names
(`ci-<chart>-pr-<n>` for PRs, `ci-<chart>-rel` for releases), so PRs can run in parallel.

#### GitHub settings (Settings → Secrets and variables → Actions)

| Name | Kind | Value |
|---|---|---|
| `OPENSHIFT_SERVER` | variable | API URL of the Sweden Central cluster, e.g. `https://api.<cluster>:6443` |
| `OPENSHIFT_TOKEN` | **secret** | Token of the `github-actions-ci` service account (see below) |
| `GH_TOKEN` | **secret** | Push access to `coh-helm-repo` (release only, unchanged) |
| `CI_NAMESPACE` | variable (optional) | Default `platta-components-helm-ci` |
| `CI_ROUTE_DOMAIN` | variable (optional) | Default `test-se.hel.ninja` (or `dev-se.hel.ninja`) |
| `CI_NODE_ENV` | variable (optional) | `env=` node label for helfi-proxy-nginx tests, default `devtest`; empty = no nodeSelector |
| `CI_ES_VERSION` | variable (optional) | Elasticsearch version for nginx-standard tests, default `8.15.3` |
| `CI_ES_IMAGE` | variable (optional) | Elasticsearch image override (e.g. a mirror); default is ECK's |

The old secret `OPENSHIFT_API_URL` is no longer used and can be deleted.

#### One-time cluster setup (cluster admin)

```bash
oc login <sweden-central-api>                      # as admin
oc apply -f .github/ci/bootstrap-namespace.yaml    # namespace + service account + RoleBinding + token
oc get secret github-actions-ci-token -n platta-components-helm-ci \
  -o jsonpath='{.data.token}' | base64 -d          # -> OPENSHIFT_TOKEN
```

The service account is `admin` of that namespace only (no `oc new-project`, no access
elsewhere). The **ECK operator** must be installed on the cluster for the nginx-standard tests.

#### nginx-standard: real Elasticsearch

Each nginx-standard integration run starts its own single-node Elasticsearch through ECK
(`.github/scripts/ci-elasticsearch.sh`, ephemeral storage), seeds a `ci-test` index, deploys
all four use cases against it and runs an end-to-end test of the elastic-proxy
(`.github/scripts/ci-nginx-e2e.sh`): health and search are proxied with the
injected reader credentials, a client cannot override them, CORS preflight works, write
methods and non-whitelisted APIs are rejected, and the public route answers.

#### Test fixtures

`.github/ci/fixtures.yaml` holds dummy secrets the other tests need (`varnish-secret`,
`mailpit-ui-auth`). Every integration run applies it via `ci-prepare-namespace.sh`.

#### Cleanup

Every integration job runs `.github/scripts/ci-cleanup.sh` twice: at the start (sweeps
leftovers of crashed or cancelled runs) and at the end with `if: always()`. For its own run
name it removes the Helm releases (including failed ones, waiting for deletion), every
object still labelled `app.kubernetes.io/instance=<run>…` (including the Elasticsearch),
StatefulSet PVCs (which Helm never deletes) and secrets the workflow created, then warns
about anything left over. Shared fixtures are kept on purpose.
