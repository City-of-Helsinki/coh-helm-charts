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

Every `pr-<chart>.yaml` can also be started by hand (Actions → *PR: <chart>* → **Run workflow**)
to test a chart on `main` or any branch without opening a PR (run names `ci-<chart>-manual-<n>`).

> Branch protection: status check names changed, e.g. `ci / lint` and
> `ci / integration (OpenShift)`. Update required checks if you use them.

### Integration tests

All integration tests run on the **Sweden Central** OpenShift cluster, in the existing
`devops-toolchain` namespace. Each run uses its own names
(`ci-<chart>-pr-<n>` for PRs, `ci-<chart>-rel` for releases), so PRs can run in parallel.

`devops-toolchain` is shared with the image builds (BuildConfigs, Quay push secrets,
`registry-ca`), so CI only creates and deletes objects whose names start with `ci-`:
`ci-cleanup.sh` refuses any pattern that is not `^ci-<chart>-…`, and fixtures are named
`ci-fixture-*` and never overwrite an object they did not create.

#### GitHub settings (Settings → Secrets and variables → Actions)

| Name | Kind | Value |
|---|---|---|
| `OPENSHIFT_SE_SERVER` | variable | API URL of the Sweden Central cluster, e.g. `https://api.<cluster>:6443` |
| `OPENSHIFT_SE_TOKEN` | **secret** | Token of the `github-actions-ci` service account (see below) |
| `GH_TOKEN` | **secret** | Push access to `coh-helm-repo` (release only, unchanged) |
| `CI_NAMESPACE` | variable (optional) | Default `devops-toolchain` |
| `CI_ROUTE_DOMAIN` | variable (optional) | Default `test-se.hel.ninja` (or `dev-se.hel.ninja`) |
| `CI_NODE_ENV` | variable (optional) | `environment=` node label for helfi-proxy-nginx tests (`dev` or `test` on Sweden Central); unset = no nodeSelector |
| `CI_ES_VERSION` | variable (optional) | Elasticsearch version for nginx-standard tests, default `8.15.3` |
| `CI_ES_IMAGE` | variable (optional) | Elasticsearch image override (e.g. a mirror); default is ECK's |
| `CI_ECK_VERSION` | variable (optional) | ECK operator version for nginx-standard tests, default `3.1.0` (must match the ECK CRDs on the cluster) |
| `CI_ECK_OPERATOR_REPOSITORY` | variable (optional) | Operator image without tag (e.g. a mirror); default `docker.elastic.co/eck/eck-operator` |

The old secrets/variables `OPENSHIFT_API_URL`, `OPENSHIFT_SERVER` and `OPENSHIFT_TOKEN` are no
longer used and can be deleted.

#### One-time cluster setup (cluster admin)

```bash
oc login <sweden-central-api>                      # as admin
oc apply -f .github/ci/bootstrap-namespace.yaml    # service account + permissions + token (namespace already exists)
oc get secret github-actions-ci-token -n devops-toolchain \
  -o jsonpath='{.data.token}' | base64 -d          # -> OPENSHIFT_SE_TOKEN
oc whoami --show-server                            # -> OPENSHIFT_SE_SERVER
```

The service account is `admin` of `devops-toolchain` only (no `oc new-project`, no access
elsewhere), plus the rights to run a namespace-scoped ECK operator there.

> **Token scope.** Being admin of `devops-toolchain` means the token can also read the other
> secrets in that namespace, e.g. the Quay push secrets used by the image builds. Store it only
> as this repository's secret (not an organisation secret), and remember that anyone who can
> push a branch here can run a workflow that uses it. Fork PRs never get it.

#### ECK operator (nginx-standard only)

There is no cluster-wide ECK operator. `.github/scripts/ci-eck.sh` installs the `eck-operator`
Helm chart as release `ci-eck-operator` **in `devops-toolchain`, watching only
`devops-toolchain`** (restricted mode: no CRDs, ClusterRoles or webhooks). It is started
by the first nginx-standard run that needs it and removed again by the last one: the final
step `ci-eck.sh release` uninstalls it once no Elasticsearch resource is left, so parallel
runs share one operator and nothing stays behind.

The ECK CRDs are not installed by CI or by the bootstrap: they already exist on the cluster,
managed by OLM for the OperatorHub ECK operators in other namespaces (3.1.0). Keep
`CI_ECK_VERSION` equal to that version (the job warns if they differ); never install the CRDs
again with Helm, OLM owns them.

#### nginx-standard: real Elasticsearch

Each nginx-standard integration run starts its own single-node Elasticsearch through ECK
(`.github/scripts/ci-elasticsearch.sh`, ephemeral storage), seeds a `ci-test` index, deploys
all four use cases against it and runs an end-to-end test of the elastic-proxy
(`.github/scripts/ci-nginx-e2e.sh`): health and search are proxied with the
injected reader credentials, a client cannot override them, CORS preflight works, write
methods and non-whitelisted APIs are rejected, and the public route answers.

#### Test fixtures

`.github/ci/fixtures.yaml` holds dummy secrets the other tests need
(`ci-fixture-varnish-secret`, `ci-fixture-mailpit-ui-auth`). Every integration run applies
it via `ci-prepare-namespace.sh`, which stops if an object with the same name exists that
is not labelled `app.kubernetes.io/part-of=helm-ci-fixtures`.

#### Cleanup

Every integration job runs `.github/scripts/ci-cleanup.sh` twice: at the start (sweeps
leftovers of crashed or cancelled runs) and at the end with `if: always()`. For its own run
name it removes the Helm releases (including failed ones, waiting for deletion), every
object still labelled `app.kubernetes.io/instance=<run>…` (including the Elasticsearch),
StatefulSet PVCs (which Helm never deletes) and secrets the workflow created, then warns
about anything left over. Shared fixtures are kept on purpose.
