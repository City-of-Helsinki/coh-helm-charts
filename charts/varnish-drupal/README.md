# varnish-drupal

A Helm chart that deploys [kube-httpcache](https://github.com/mittwald/kube-httpcache) as a Varnish HTTP cache in front of a Drupal backend on OpenShift.

## Architecture

```
OpenShift Route → Service (varnish) → StatefulSet pods
                                                      │
                                    ┌─────────────────┴─────────────────┐
                                    │  Pod                               │
                                    │  ┌─────────────┐  ┌────────────┐  │
                                    │  │   varnish   │  │   logger   │  │
                                    │  │  (8080/8090)│  │  (varnish  │  │
                                    │  └──────┬──────┘  │   ncsa)    │  │
                                    │         │         └────────────┘  │
                                    └─────────┼─────────────────────────┘
                                              │
                                    Service (drupal:8080)
```

Each pod runs two containers:
- **varnish** — kube-httpcache managing Varnish + peer discovery via the headless Service
- **logger** — sidecar running `varnishncsa` and streaming access logs to stdout

## Prerequisites

- OpenShift 4.x (or Kubernetes with the Route CRD available)
- A `ServiceAccount` named `kube-httpcache` in the target namespace with permission to list/watch Endpoints
- A `Secret` containing `VARNISH_SECRET` and `VARNISH_PURGE_KEY` (referenced via `externalSecretName`)
- Helm 3.x

## Installing

```bash
helm install my-varnish ./varnish-drupal \
  --namespace my-app \
  --set route.host=varnish-myapp.apps.example.com \
  --set externalSecretName=my-varnish-secret
```

Multiple independent instances can be deployed in the same namespace:

```bash
helm install varnish-fi ./varnish-drupal --namespace my-app --set route.host=fi.example.com ...
helm install varnish-en ./varnish-drupal --namespace my-app --set route.host=en.example.com ...
```

## Upgrading

```bash
helm upgrade my-varnish ./varnish-drupal --namespace my-app -f my-values.yaml
```

## Uninstalling

```bash
helm uninstall my-varnish --namespace my-app
```

## Values

### Core

| Key                    | Default | Description                                                                    |
| ---------------------- | ------- | ------------------------------------------------------------------------------ |
| `nameOverride`         | `""`    | Override the chart name component of resource names                            |
| `fullnameOverride`     | `""`    | Override the full resource name entirely                                       |
| `replicaCount`         | `2`     | Number of Varnish pods                                                         |
| `revisionHistoryLimit` | `3`     | StatefulSet revision history to retain                                         |
| `nodeSelector`         | `""`    | Value for the `env` node label (e.g. `prod`, `staging`)                        |
| `externalSecretName`   | `""`    | **Required.** Name of the Secret with `VARNISH_SECRET` and `VARNISH_PURGE_KEY` |

### Routing

| Key             | Default  | Description                                    |
| --------------- | -------- | ---------------------------------------------- |
| `route.host`    | `""`     | **Required.** Hostname for the OpenShift Route |
| `route.path`    | `""`     | Optional sub-path (e.g. `/fi`)                 |
| `route.timeout` | `"300s"` | HAProxy router timeout                         |

### Service Names

By default both service names are derived from the Helm release name. Override them independently without affecting any other chart resources (ConfigMap, StatefulSet, etc.).

| Key                    | Default | Description                                                                             |
| ---------------------- | ------- | --------------------------------------------------------------------------------------- |
| `service.name`         | `""`    | Overrides the main ClusterIP service name. Falls back to `fullname` if not set.         |
| `service.headlessName` | `""`    | Overrides the headless service name. Falls back to `<serviceName>-headless` if not set. |

**Example:**

```yaml
service:
  name: my-varnish
  headlessName: my-varnish-headless
```

### Image

| Key                | Default                                                                     | Description                                           |
| ------------------ | --------------------------------------------------------------------------- | ----------------------------------------------------- |
| `image.repository` | `container-registry.platta-net.hel.fi/devops-toolchain/kube-httpcache-fork` | Image repository                                      |
| `image.tag`        | `stable-3.0`                                                                | Image tag                                             |
| `image.pullPolicy` | `Always`                                                                    | Pull policy                                           |
| `imagePullSecrets` | `[]`                                                                        | List of pull secret names, e.g. `[{name: my-secret}]` |

### Backend

| Key            | Default    | Description         |
| -------------- | ---------- | ------------------- |
| `backend.host` | `"drupal"` | Drupal Service name |
| `backend.port` | `"8080"`   | Drupal Service port |

### Resources

| Key                                 | Default | Description                                 |
| ----------------------------------- | ------- | ------------------------------------------- |
| `resources.varnish.requests.cpu`    | `200m`  |                                             |
| `resources.varnish.requests.memory` | `1Gi`   |                                             |
| `resources.varnish.limits.cpu`      | `""`    | Leave empty to omit (avoids CPU throttling) |
| `resources.varnish.limits.memory`   | `1Gi`   |                                             |
| `resources.logger.requests.cpu`     | `50m`   |                                             |
| `resources.logger.requests.memory`  | `50Mi`  |                                             |
| `resources.logger.limits.cpu`       | `""`    | Leave empty to omit                         |
| `resources.logger.limits.memory`    | `50Mi`  |                                             |

### Varnish storage

| Key                       | Default       | Description               |
| ------------------------- | ------------- | ------------------------- |
| `varnishStorage`          | `malloc,128M` | Primary Varnish storage   |
| `varnishTransientStorage` | `malloc,128M` | Transient Varnish storage |

### VCL feature flags

| Key                          | Default      | Description                                                                                                                                                         |
| ---------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `vcl.director.mode`          | `single`     | `single` — one `be-drupal` backend with `directors.hash` for peer discovery. `multi` — separate `directors.shard` (frontends) + `directors.round_robin` (backends). |
| `vcl.healthEndpoint.enabled` | `true`       | Serve `200 OK` on `/varnishstatus`. Must be `false` when `director.mode=multi`.                                                                                     |
| `vcl.healthProbe.enabled`    | `true`       | Attach a backend health probe.                                                                                                                                      |
| `vcl.healthProbe.endpoint`   | `/healthz`   | Health probe request path                                                                                                                                           |
| `vcl.healthProbe.host`       | `www.hel.fi` | `Host` header sent with health probe requests                                                                                                                       |
| `vcl.healthProbe.timeout`    | `5s`         |                                                                                                                                                                     |
| `vcl.healthProbe.interval`   | `5s`         |                                                                                                                                                                     |
| `vcl.healthProbe.window`     | `5`          |                                                                                                                                                                     |
| `vcl.healthProbe.threshold`  | `3`          |                                                                                                                                                                     |
| `vcl.rootRedirect.enabled`   | `false`      | Return `302` for requests to `/`                                                                                                                                    |
| `vcl.rootRedirect.target`    | `""`         | Redirect target URL. Required when `rootRedirect.enabled=true`.                                                                                                     |
| `vcl.overrides.backendError` | `""`         | Replace the entire `vcl_backend_error` block. Paste a full `sub vcl_backend_error { ... }` string.                                                                  |
| `vcl.basicAuth.enabled`      | `false`      | Enable basicAuth                                                                                                                                                    |
| `vcl.basicAuth.credentials`  | `""`         | Base64 encoded string for basic auth                                                                                                                                |

## Examples

### Minimal production deployment

```yaml
# my-values.yaml
route:
  host: varnish-myapp.apps.platta.hel.fi

externalSecretName: myapp-varnish-secret

replicaCount: 2
nodeSelector: prod

resources:
  varnish:
    requests:
      cpu: "500m"
      memory: "2Gi"
    limits:
      memory: "2Gi"

varnishStorage: "malloc,512M"
varnishTransientStorage: "malloc,128M"
```

### Root redirect

```yaml
vcl:
  rootRedirect:
    enabled: true
    target: "https://myapp.hel.fi/fi"
```

### Multilingual backend error page

```yaml
vcl:
  overrides:
    backendError: |
      sub vcl_backend_error {
        set beresp.http.Content-Type = "text/html; charset=utf-8";
        if (bereq.url ~ "^/fi/") {
          synthetic ({"<html><body>Sivu ei ole saatavilla.</body></html>"});
        } else if (bereq.url ~ "^/en/") {
          synthetic ({"<html><body>Page temporarily unavailable.</body></html>"});
        } else {
          synthetic ({"<html><body>Service unavailable.</body></html>"});
        }
        return (deliver);
      }
```

### Multi-backend mode (e.g. palvelukeskus)

```yaml
vcl:
  director:
    mode: multi
  healthEndpoint:
    enabled: false   # required when mode=multi
  healthProbe:
    enabled: false
```

## Cache purging

The chart supports two purge methods, both authenticated with `VARNISH_PURGE_KEY`:

**Tag-based ban** (recommended for Drupal):
```bash
curl -X BAN https://your-route.example.com/ \
  -H "X-VC-Purge-Key: <VARNISH_PURGE_KEY>" \
  -H "Cache-Tags: node:123"
```

**URL purge:**
```bash
curl -X PURGE https://your-route.example.com/path/to/page \
  -H "X-VC-Purge-Key: <VARNISH_PURGE_KEY>"
```

The purge method (regex / exact / page) is auto-detected from the URL or can be forced with the `X-VC-Purge-Method` header.

## Troubleshooting

**Pods stuck in `Pending`**
- Check that the `kube-httpcache` ServiceAccount exists in the namespace.
- Check that `externalSecretName` points to an existing Secret.

**Pods not becoming Ready**
- `vcl.healthEndpoint.enabled` must be `true` (default) unless you are handling `/varnishstatus` yourself in a custom VCL.
- Check `kubectl logs <pod> -c varnish` for VCL compilation errors.

**Cache not purging**
- Confirm `VARNISH_PURGE_KEY` in your Secret matches what you send in `X-VC-Purge-Key`.
- Check the response body — a `405` means the key did not match.

**`helm template` fails with "must be false when director.mode is multi"**
- Set `vcl.healthEndpoint.enabled: false` in your values when using `director.mode: multi`.
