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
