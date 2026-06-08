# mailpit-openshift

A Helm wrapper chart that deploys [jouve/mailpit](https://github.com/jouve/charts/tree/main/charts/mailpit) with OpenShift-specific extras: an OpenShift Route, NetworkPolicy, and optional ExternalSecret for per-namespace SMTP test sinks in Platta OpenShift environments.

| Field | Value |
|---|---|
| Chart version | 0.1.0 |
| App version | 1.30.0 |
| Upstream chart | `jouve/mailpit` 0.34.1 |
| Chart type | application |

---

## Overview

`mailpit-openshift` provides a lightweight, disposable SMTP sink per namespace. It wraps the upstream `jouve/mailpit` subchart and adds:

- An **OpenShift Route** with edge TLS termination
- **NetworkPolicies** with a default deny-all posture, allow rules for SMTP and HTTP ingress, OpenShift router ingress, and `devops-toolchain` pipeline access
- An optional **ExternalSecret** to pull the UI htpasswd file from a `ClusterSecretStore`
- OpenShift-compatible security context defaults (no hardcoded UIDs)

---

## Prerequisites

- Helm 3.x
- OpenShift 4.x (Platta platform)
- [External Secrets Operator](https://external-secrets.io/) installed in the cluster (only required if `externalSecret.enabled: true`)

---

## Installing the Chart

```bash
# Add the upstream dependency repository (needed for helm dependency build)
helm repo add jouve https://jouve.github.io/charts/
helm repo update

# Fetch subchart dependencies
helm dependency build charts/mailpit-openshift

# Install with defaults (uses existingSecret for htpasswd)
helm upgrade --install mailpit charts/mailpit-openshift \
  --namespace <your-namespace> \
  --set route.host="mailpit.apps.your-cluster.example.com" \
  --set existingSecret="mailpit-ui-auth"
```

---

## Uninstalling the Chart

```bash
helm uninstall mailpit --namespace <your-namespace>
```

---

## Configuration

### Subchart values (`mailpit.*`)

These are passed through to the upstream `jouve/mailpit` chart. Key defaults set by this wrapper:

| Parameter | Description | Default |
|---|---|---|
| `mailpit.image.registry` | Image registry | `docker.io` |
| `mailpit.image.repository` | Image repository | `axllent/mailpit` |
| `mailpit.image.tag` | Image tag | `v1.30.0` |
| `mailpit.image.pullPolicy` | Pull policy | `IfNotPresent` |
| `mailpit.resources.requests.cpu` | CPU request | `10m` |
| `mailpit.resources.requests.memory` | Memory request | `32Mi` |
| `mailpit.resources.limits.cpu` | CPU limit | `100m` |
| `mailpit.resources.limits.memory` | Memory limit | `128Mi` |
| `mailpit.service.smtp.port` | SMTP service port | `1025` |
| `mailpit.service.http.port` | HTTP/UI service port | `8025` |
| `mailpit.ingress.enabled` | Upstream ingress (disabled; use Route instead) | `false` |
| `mailpit.networkPolicy.enabled` | Upstream networkPolicy (disabled; use wrapper instead) | `false` |

#### Environment variables

| Variable | Description | Default |
|---|---|---|
| `MP_UI_AUTH_FILE` | Path to htpasswd file for UI auth | `/etc/mailpit-auth/htpasswd` |
| `MP_SMTP_AUTH_ACCEPT_ANY` | Accept any SMTP credentials | `true` |
| `MP_SMTP_AUTH_ALLOW_INSECURE` | Allow insecure SMTP auth | `true` |
| `MP_MAX_MESSAGES` | Maximum stored messages | `500` |
| `MP_MAX_AGE` | Maximum message retention age | `48h` |
| `MP_SMTP_BIND_ADDR` | SMTP bind address | `0.0.0.0:1025` |
| `MP_UI_BIND_ADDR` | UI bind address | `0.0.0.0:8025` |

#### Security context

All UID/GID fields are deliberately set to `null` so OpenShift assigns them automatically from the namespace range. The pod and container both run as non-root with all capabilities dropped.

---

### OpenShift Route (`route.*`)

| Parameter | Description | Default |
|---|---|---|
| `route.enabled` | Deploy an OpenShift Route | `true` |
| `route.host` | Hostname for the Route. Leave empty to let OpenShift assign one. | `""` |
| `route.tls.termination` | TLS termination strategy | `edge` |
| `route.tls.insecureEdgeTerminationPolicy` | HTTP traffic handling | `Redirect` |
| `route.annotations` | Extra annotations to add to the Route | `{}` |

---

### NetworkPolicy (`networkPolicy.*`)

The wrapper deploys four NetworkPolicy objects:

| Policy | Purpose |
|---|---|
| `…-deny-all` | Default deny all ingress and egress |
| `…-deny-egress` | Explicit egress deny (belt-and-suspenders) |
| `…-allow-smtp` | Allow ingress on SMTP port from matching pods |
| `…-allow-http` | Allow ingress on HTTP port from matching pods |
| `…-allow-router` | Allow ingress from `openshift-ingress` namespace |
| `…-allow-devops-pipeline` | Allow ingress from `devops-toolchain` namespace on both ports |

| Parameter | Description | Default |
|---|---|---|
| `networkPolicy.enabled` | Deploy NetworkPolicy resources | `true` |
| `networkPolicy.smtp.enabled` | Enable SMTP allow policy | `true` |
| `networkPolicy.smtp.port` | SMTP port | `1025` |
| `networkPolicy.http.enabled` | Enable HTTP allow policy | `true` |
| `networkPolicy.http.port` | HTTP port | `8025` |
| `networkPolicy.http.podSelector.matchLabels` | Labels to select pods allowed to reach the UI | `{}` (all pods in namespace) |

---

### Authentication secret

The UI htpasswd file is mounted from a secret at `/etc/mailpit-auth/htpasswd`. Supply it in one of two ways:

#### Option A — Pre-existing secret (default)

Create the secret manually before installing, then reference it:

```bash
oc create secret generic mailpit-ui-auth \
  --from-file=htpasswd=./htpasswd \
  -n <your-namespace>
```

```yaml
existingSecret: "mailpit-ui-auth"
```

| Parameter | Description | Default |
|---|---|---|
| `existingSecret` | Name of a pre-existing secret containing the htpasswd file | `""` |

#### Option B — ExternalSecret

Pull the htpasswd value from a `ClusterSecretStore`:

```yaml
externalSecret:
  enabled: true
  secretStoreName: "cluster-secret-store"
  secretStoreKind: "ClusterSecretStore"
  refreshInterval: "1h"
  remoteRef:
    key: "platta/mailpit/{{ .Release.Namespace }}"
    property: "htpasswd"
  targetSecretName: "mailpit-ui-auth"
```

| Parameter | Description | Default |
|---|---|---|
| `externalSecret.enabled` | Deploy an ExternalSecret resource | `false` |
| `externalSecret.secretStoreName` | Name of the SecretStore/ClusterSecretStore | `cluster-secret-store` |
| `externalSecret.secretStoreKind` | Kind of secret store | `ClusterSecretStore` |
| `externalSecret.refreshInterval` | How often to sync the secret | `1h` |
| `externalSecret.remoteRef.key` | Key path in the secret store (supports templating) | `platta/mailpit/{{ .Release.Namespace }}` |
| `externalSecret.remoteRef.property` | Property within the key | `htpasswd` |
| `externalSecret.targetSecretName` | Name of the openshift secret to create | `mailpit-ui-auth` |

When `externalSecret.enabled` is `true`, the mounted secret name is taken from `externalSecret.targetSecretName`. When `false`, it falls back to `existingSecret`. If neither is set, the chart defaults to the name `mailpit-ui-auth`.

---

## Example values overrides

### Minimal — existing secret, auto-assigned hostname

```yaml
existingSecret: "mailpit-ui-auth"
```

### With explicit route hostname

```yaml
route:
  host: "mailpit.apps.ocp-dev.hel.ninja"

existingSecret: "mailpit-ui-auth"
```

### With ExternalSecret

```yaml
externalSecret:
  enabled: true
  secretStoreName: "cluster-secret-store"
  remoteRef:
    key: "platta/mailpit/my-namespace"
    property: "htpasswd"

route:
  host: "mailpit.apps.ocp-dev.hel.ninja"
```

### Restrict HTTP UI access to specific pods

```yaml
networkPolicy:
  http:
    podSelector:
      matchLabels:
        app.openshift.io/name: my-app
```

---

## CI / Release workflow

The chart ships with a GitHub Actions workflow (`release-mailpit.yml`) with three jobs:

| Job | Trigger | Description |
|---|---|---|
| `test` | PR to `main` touching `charts/mailpit-openshift/**` | Lints the chart, runs helm-unittest if tests exist, validates manifests with kubeconform (skipping `Route` and `ExternalSecret` CRDs) |
| `integration-test` | After `test` passes | Deploys to `hki-kanslia-helfi-hakuvahti-dev` on the dev cluster, verifies the `/readyz` endpoint returns HTTP 200, then cleans up |
| `release` | `workflow_dispatch` with `chart_version` input | Bumps `Chart.yaml`, packages, publishes to `coh-helm-repo` (`gh-pages` branch), and creates a GitHub Release with auto-generated changelog |

Required secrets: `OPENSHIFT_API_URL`, `OPENSHIFT_TOKEN`, `GH_TOKEN`.

Git tags follow the pattern `mailpit-openshift-v<version>`.

---

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| 1025 | TCP | SMTP |
| 8025 | TCP | Web UI / HTTP API |

---