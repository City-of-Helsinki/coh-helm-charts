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
Base `nginx.conf` with worker config, geo block, health probes. Never changes per environment. Only updated when base nginx behaviour changes globally.

### `configmap-server`
The server block with all location rules and Varnish backend hostnames. Changes per environment (different Varnish hostnames, different `serverName`). Updated when routing rules change or new Drupal sections are added.

### `configmap-redirections`
Env-jump convenience redirects — `www.hel.fi/fi/test-asuminen` → `https://www.test.hel.ninja/fi/asuminen` etc. Only enabled in prod (`redirections.enabled: true` in `values-prod.yaml`). These are developer shortcuts so teams can jump from `www.hel.fi` to test or staging environments without remembering the `.hel.ninja` hostnames.

Test and staging environments do not need these — they ARE the target environment.

This separation means:
- Routing rule changes → touch `configmap-server` only
- Adding a new env-jump redirect → touch `configmap-redirections` only
- No image rebuild needed for any config change

---

## Prerequisites

- Helm 3.x
- OpenShift CLI (`oc`) or `kubectl`
- Image `container-registry.platta-net.hel.fi/hki-kanslia-helfi-etusivu/helfi-proxy-nginx` built and pushed
- `quay-secret-new` pull secret present in target namespace

---

## Values reference

### Common values

| Key | Description | Default |
|---|---|---|
| `type` | Role: `receiver` or `dispatcher` | `receiver` |
| `replicaCount` | Number of pod replicas | `2` |
| `image.registry` | Container registry | `container-registry.platta-net.hel.fi` |
| `image.repository` | Image repository | `hki-kanslia-helfi-etusivu/helfi-proxy-nginx` |
| `image.tag` | Image tag | `latest` |
| `nodeSelector` | OpenShift node selector value (`devtest` / `stg` / `prod`) | `devtest` |
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
| `matchType` | **Optional.** Nginx modifier. Defaults to `~ ^/` (regex). Use ` ` (space) for prefix. |
| `proxyPath` | **Optional.** Path appended to backend. Use `/` to strip incoming prefixes. |

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

---

## Environment comparison

| | test | staging | prod |
|---|---|---|---|
| Hostname | `www.test.hel.ninja` | `www.stage.hel.ninja` | `www.hel.fi` |
| Cluster | devtest | stageprod | stageprod |
| OpenShift IP | `10.235.227.132` | `10.235.230.132` | `10.235.230.132` |
| X-Forwarded-Host | `$host` | `$host` | `$xfh` (geo block) |
| Node selector | `devtest` | `stg` | `prod` |
| Namespace | `hki-kanslia-helfi-etusivu-test` | `hki-kanslia-helfi-etusivu-staging` | `hki-kanslia-helfi-etusivu-prod` |
| Redirections enabled | `false` | `false` | `true` |

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