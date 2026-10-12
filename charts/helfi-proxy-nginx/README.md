# helfi-proxy-nginx Helm Chart

Nginx proxy chart for hel.fi services. Handles two roles via `type` value:

- `receiver` — helfi-nginx, owns Drupal compositing for a specific domain (www.test.hel.ninja, www.hel.fi etc.)
- `dispatcher` — thin router, owns the public OpenShift route and fans traffic out to multiple receiver services internally via ClusterIP

---

## Background

OpenShift enforces that a hostname can only be claimed by one route in one namespace at a time. This chart solves that by:

- In simple environments (test, staging): `receiver` owns the route directly
- In prod with multiple receivers: `dispatcher` owns `www.hel.fi` route and routes internally to `receiver` services via ClusterIP — no public routes needed on receivers

---

## Chart structure

```
helfi-proxy-nginx/
  Chart.yaml
  values.yaml                   ← shared defaults
  values-test.yaml              ← www.test.hel.ninja overrides
  values-staging.yaml           ← www.stage.hel.ninja overrides
  values-prod.yaml              ← www.hel.fi overrides
  templates/
    _helpers.tpl                ← shared template helpers
    configmap-base-nginx.yaml   ← nginx.conf (same for all envs, never changes)
    configmap-server.yaml       ← server block (rendered from values, differs per env)
    configmap-redirections.yaml ← env-jump redirects (only rendered in prod)
    deployment.yaml
    service.yaml
    route.yaml
```

---

## Three ConfigMaps — why

The nginx config is split into three ConfigMaps deliberately:

### `configmap-base-nginx`
Base `nginx.conf` with worker config, geo block, health probes, and `limit_req_zone` rate-limiting zone definitions (see [Rate Limiting](#rate-limiting) below — these must live in the `http{}` context, which only this ConfigMap owns). Never changes per environment beyond which rate-limiting zones are enabled. Only updated when base nginx behaviour changes globally.

### `configmap-server`
The server block with all location rules, Varnish backend hostnames, and the `location` blocks that enforce rate limiting for configured zones. Changes per environment (different Varnish hostnames, different `serverName`, different `rateLimiting` config). Updated when routing rules change, new Drupal sections are added, or rate limiting is enabled/adjusted.

### `configmap-redirections`
Env-jump convenience redirects — `www.hel.fi/fi/test-asuminen` → `https://www.test.hel.ninja/fi/asuminen` etc. Only enabled in prod (`redirections.enabled: true` in `values-prod.yaml`). These are developer shortcuts so teams can jump from `www.hel.fi` to test or staging environments without remembering the `.hel.ninja` hostnames.

Test and staging environments do not need these — they ARE the target environment.

This separation means:
- Routing rule changes → touch `configmap-server` only
- Adding a new env-jump redirect → touch `configmap-redirections` only
- Adding/adjusting rate limiting → touch `rateLimiting` values only (no template changes needed for a new zone)
- No image rebuild needed for any config change

---

## Prerequisites

- Helm 3.x
- OpenShift CLI (`oc`) or `kubectl`
- Image built by the `devops-toolchain/helfi-proxy-nginx` repository (Dockerfile + error pages)
  and pushed to both registries:
  - Sweden Central: `image-registry.int.platta.hel.fi/hki-platta-components/helfi-proxy-nginx`
    (public repository, no pull secret needed) - the chart default
  - West Europe: `container-registry.platta-net.hel.fi/devops-toolchain/helfi-proxy-nginx`
    (pull secret `quay-secret-new`, set by pipeline-templates)

---

## Values reference

### Common values

| Key | Description | Default |
|---|---|---|
| `type` | Role: `receiver` or `dispatcher` | `receiver` |
| `replicaCount` | Number of pod replicas | `2` |
| `global.imageRegistry` | Registry used when `image.registry` is empty (set per region by the pipeline) | `image-registry.int.platta.hel.fi` |
| `global.imagePullSecrets` | Pull secrets added to the pod | `[]` |
| `image.registry` | Registry override (empty = `global.imageRegistry`) | `""` |
| `image.repository` | Image repository | `hki-platta-components/helfi-proxy-nginx` |
| `image.tag` | Image tag | `latest` |
| `image.digest` | Optional digest, wins over tag | `""` |
| `nodeSelector` | Node labels as a map (e.g. `{environment: test}`), or a legacy string value for `<nodeSelectorKey>` (e.g. `prod`). Empty = any node | `{}` |
| `nodeSelectorKey` | Label key for the string form only | `env` |
| `tolerations` | Pod tolerations; empty falls back to `global.tolerations` | `[]` |
| `affinity` | Kubernetes affinity; empty falls back to `global.affinity` | `{}` |
| `route.enabled` | Create OpenShift route | `true` |
| `route.host` | Public hostname for the route | `""` |
| `route.tls.enabled` | Enable TLS on route | `true` |

### Receiver-specific values

#### 1. General & Backends
Backends are defined as a map of keys to hostnames. These keys are referenced by the proxy routes.

| Key | Description |
|---|---|
| `receiver.serverName` | nginx `server_name` directive |
| `receiver.openshiftIP` | Internal OpenShift AGW IP used in `proxy_pass` |
| `receiver.xForwardedHost` | Value for `X-Forwarded-Host` header (`$host` or `$xfh`) |
| `receiver.backends.asuminen` | Varnish hostname for asuminen |
| `receiver.backends.etusivu` | Varnish hostname for etusivu |
| `receiver.backends.kasvatus` | Varnish hostname for kasvatus-koulutus |
| `receiver.backends.kuva` | Varnish hostname for kuva |
| `receiver.backends.liikenne` | Varnish hostname for liikenne |
| `receiver.backends.rekry` | Varnish hostname for rekry |
| `receiver.backends.sitemap` | Varnish hostname for sitemap/robots.txt |
| `receiver.backends.strategia` | Varnish hostname for strategia-talous |
| `receiver.backends.terveys` | Varnish hostname for terveys |
| `receiver.backends.tyo-yrittaminen` | Varnish hostname for tyo-yrittaminen |
| `receiver.backends.uutisapi` | Hostname for etusivu elastic proxy (news API) |

#### 2. Dynamic Proxy Routes (`receiver.proxiedRoutes`)
This list defines the Nginx `location` blocks.

| Key | Description |
|---|---|
| `name` | Descriptive name (used as a comment in config) |
| `paths` | The URI patterns or regex strings to match |
| `backendKey` | The key from `receiver.backends` to use for the Host header |
| `matchType` | **Optional.** Nginx modifier. Defaults to `~ ^/` (regex). Use `" "` (a literal single space) for a plain prefix-match location — an empty string `""` will NOT trigger prefix mode, since Helm's `default` treats an empty string as unset and silently falls back to `~ ^/`. |
| `proxyPath` | **Optional.** Path appended to backend. Use `/` to strip incoming prefixes. |

#### 3. Rate Limiting (`receiver.rateLimiting`) <a name="rate-limiting"></a>

Applies per-pod request rate limiting to specific paths, returning a configurable status code (typically `204`) instead of forwarding to the backend once the limit is exceeded. Used to protect Drupal/the database from traffic spikes on lightweight endpoints (e.g. CSP violation reporting) without needing every request to reach the backend.

| Key | Description | Default |
|---|---|---|
| `rateLimiting.enabled` | Master switch for rate limiting on this receiver | `false` |
| `rateLimiting.zones` | List of rate-limiting zones (see below) | `[]` |
| `zones[].name` | Zone name — must be unique per receiver; used as the nginx `limit_req_zone` name | — |
| `zones[].rate` | **Per-pod** rate, nginx format (e.g. `"1r/s"`, `"10r/m"`) | — |
| `zones[].key` | `"global"` for one shared counter across all clients (site-wide limit); any other value is used verbatim as the nginx rate-limit key (e.g. `"$binary_remote_addr"` for a per-client limit) | — |
| `zones[].size` | Shared memory zone size | `10m` |
| `zones[].burst` | Requests allowed to queue above the rate before being delayed/rejected. Only emitted in the rendered config when `> 0` — nginx does not accept `burst=0` as valid syntax, so `0` (or unset) means no burst clause at all, i.e. immediate rejection with no queueing | `0` |
| `zones[].nodelay` | When `burst > 0`, whether queued requests are rejected immediately instead of delayed. Ignored when `burst` is `0`/unset | `true` |
| `zones[].methods` | HTTP methods subject to rate limiting; any other method returns `405` | `["GET", "POST"]` |
| `zones[].paths` | List of fully-anchored regex paths this zone applies to (e.g. `"^/fi/log-report-uri/enforce$"`) | — |
| `zones[].backendKey` | Key from `receiver.backends` — where accepted (non-rate-limited) requests are proxied | — |
| `zones[].responseCode` | Status code returned for rate-limited requests | `204` |

**Important — per-pod, not global:** `limit_req_zone` counters are local to each nginx pod; there is no shared state across replicas. The real aggregate ceiling reaching the backend is approximately `rate × replicaCount`, not the configured `rate` alone. With `replicaCount: 2` and `rate: "1r/s"`, expect up to ~2 req/s in practice, occasionally higher in bursts spanning slightly more than one second (each pod's counter resets independently). This is an intentional trade-off — a true global limit would require shared state (e.g. Redis) which isn't implemented here, since this feature is meant as a coarse safeguard against traffic spikes rather than a precise rate guarantee.

**Ordering:** rate-limited `location` blocks are rendered *before* the etusivu catch-all and after `proxiedRoutes`, since nginx evaluates regex locations in file order and stops at the first match.

##### Example

```yaml
receiver:
  rateLimiting:
    enabled: true
    zones:
      - name: csp_report
        rate: "1r/s"
        key: "global"
        methods: ["GET", "POST"]
        paths:
          - "^/fi/log-report-uri/enforce$"
          - "^/sv/log-report-uri/enforce$"
          - "^/en/log-report-uri/enforce$"
        backendKey: "etusivu"
        responseCode: 204
```

---

## Example Dynamic Route Configuration

```yaml
receiver:
  backends:
    asuminen: "varnish-asuminen-test.apps.arodevtest.hel.fi"
    uutisapi: "etusivu-elastic-proxy-test.apps.arodevtest.hel.fi"

  proxiedRoutes:
    - name: "Asuminen"
      paths: "fi/asuminen|en/housing"
      backendKey: "asuminen"
    - name: "News API"
      matchType: " "
      paths: "/uutisapi/"
      proxyPath: "/"
      backendKey: "uutisapi"
```

### Redirections values

| Key | Description | Default |
|---|---|---|
| `redirections.enabled` | Enable env-jump redirect ConfigMap | `false` |
| `redirections.testHost` | Target hostname for `test-` prefix redirects | `www.test.hel.ninja` |
| `redirections.stagingHost` | Target hostname for `staging-` prefix redirects | `www.stage.hel.ninja` |

Only set `redirections.enabled: true` in `values-prod.yaml`. These redirects handle paths like:
- `www.hel.fi/fi/test-asuminen` → `302 https://www.test.hel.ninja/fi/asuminen`
- `www.hel.fi/fi/staging-etusivu` → `302 https://www.stage.hel.ninja/fi`

Covered sections: etusivu, asuminen, kasvatus-koulutus, kuva, liikenne, rekry, strategia-talous, terveys, tyo-yrittaminen.

### Dispatcher-specific values

| Key | Description |
|---|---|
| `dispatcher.openshiftIP` | Internal OpenShift IP for routing |
| `dispatcher.routes` | List of path-based routing rules to internal ClusterIP services |
| `dispatcher.routes[].path` | nginx location regex path |
| `dispatcher.routes[].backend` | Internal ClusterIP service name |
| `dispatcher.routes[].port` | Service port (typically 8080) |

> **Note:** the `dispatcher` role only fans out traffic in prod (`hki-kanslia-proxy-helfi-prod`), which owns the public `www.hel.fi` route. Test and staging have no dispatcher — the `receiver` owns its route directly, so any path reachable by the receiver (rate-limited or not) is reachable without needing a matching dispatcher rule. In prod, a path must be routed to the receiver by the dispatcher (via `dispatcher.routes`) before any `receiver`-side config — including `rateLimiting` — will ever see traffic for it.

---

## Environment comparison (West Europe)

| | test | staging | prod |
|---|---|---|---|
| Hostname | `www.test.hel.ninja` | `www.stage.hel.ninja` | `www.hel.fi` |
| Cluster | devtest | stageprod | stageprod |
| OpenShift IP | `10.235.227.132` | `10.235.230.132` | `10.235.230.132` |
| X-Forwarded-Host | `$host` | `$host` | `$xfh` (geo block) |
| Node selector (`env=`, West Europe only) | `devtest` | `stg` | `prod` |
| Namespace | `hki-kanslia-helfi-etusivu-test` | `hki-kanslia-helfi-etusivu-staging` | `hki-kanslia-helfi-etusivu-prod` |
| Redirections enabled | `false` | `false` | `true` |
| Rate limiting (`csp_report`) | `true` | `true` | `true` |

> Sweden Central nodes are labelled `environment=dev|test|...`, not `env=...`. Leave
> `nodeSelector` empty there (any worker) or use the map form, e.g. `{environment: test}`.

---

## Rollback

### Config change rollback (Helm)

```bash
helm rollback helfi-nginx <revision> -n <namespace>
```

Check revision history:

```bash
helm history helfi-nginx -n <namespace>
```

## Images per region

| Image | Sweden Central | West Europe |
|---|---|---|
| nginx (receiver / dispatcher) | `image-registry.int.platta.hel.fi/hki-platta-components/helfi-proxy-nginx:latest` | `container-registry.platta-net.hel.fi/devops-toolchain/helfi-proxy-nginx:latest` |
| Pull secret | none (public repository) | `quay-secret-new` |

Built from the `devops-toolchain/helfi-proxy-nginx` repository (Red Hat `ubi9/nginx-126` + error
pages) and pushed to both registries; every build is tagged `build-<BuildId>` and promoted to `latest`.
The West Europe path applies once `pipeline-templates/common/helm-values/images/we/helfi-proxy-nginx.yaml`
points at `devops-toolchain/helfi-proxy-nginx` (older West Europe deployments used
`hki-kanslia-helfi-etusivu/helfi-proxy-nginx`).

How the region is chosen: platform deployments (Azure DevOps, `pipeline-templates`) load
`common/helm-values/region-<se|we>.yaml` (sets `global.imageRegistry` / `global.imagePullSecrets`),
then `common/helm-values/images/<chart>.yaml` (repository + tag, single source of truth) and, for
West Europe only, `common/helm-values/images/we/<chart>.yaml` (legacy paths and pull secrets).
The region follows the service connection name: `*-se` = Sweden Central, anything else = West Europe.
Installing the chart directly (no pipeline) uses the chart defaults, i.e. the Sweden Central images.

---

## Changelog

### 1.1.0
* **Behaviour change:** the default `nodeSelector: devtest` is gone - pods may run on any
  worker unless a values file sets `nodeSelector`. A plain string (`nodeSelector: prod`)
  still renders `env: prod`; a map (`{environment: test}`) is used as-is.
* New `tolerations` and `affinity` values.
* Default image `hki-platta-components/helfi-proxy-nginx:latest` (source moved to the
  `devops-toolchain/helfi-proxy-nginx` repository).
* Images: no registry hostnames in the templates any more. `global.imageRegistry`
  (default `image-registry.int.platta.hel.fi`, set per region by pipeline-templates),
  `global.imagePullSecrets`, and per image `registry` / `repository` / `tag` / `digest`.
* Pod scheduling: the same `nodeSelector` / `tolerations` / `affinity` keys as every coh chart,
  empty by default (any worker node), falling back to `global.*`.
* CI runs on the Sweden Central cluster (namespace `devops-toolchain`).

