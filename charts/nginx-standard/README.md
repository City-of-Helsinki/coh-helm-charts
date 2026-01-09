# NGINX Standard Helm Chart

A flexible, production-ready Helm chart for deploying NGINX on OpenShift with multiple use cases: 

- File sharing, 
- Elastic proxy, 
- Cache proxy, and 
- Front proxy.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Use Cases](#use-cases)
  - [File Sharing](#file-sharing)
  - [Elastic Proxy](#elastic-proxy)
  - [Cache Proxy](#cache-proxy)
  - [Front Proxy](#front-proxy)
- [Configuration](#configuration)
  - [Global Settings](#global-settings)
  - [NGINX Base Configuration](#nginx-base-configuration)
  - [Observability](#observability)
  - [Security](#security)
  - [Networking](#networking)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

This Helm chart provides a standardized NGINX deployment for OpenShift with four distinct use cases:

1. **File Sharing** - Serve static files from Azure File Storage with directory browsing
2. **Elastic Proxy** - Secure proxy for Elasticsearch with authentication and route filtering
3. **Cache Proxy** - Advanced caching proxy with flexible zone configuration
4. **Front Proxy** - Complex routing proxy with environment-based configuration

## Prerequisites

- OpenShift 4.8+
- Helm 3.0+
- PVC provisioner support (for file sharing with persistent storage)
- External Secrets Operator (optional, for Azure Key Vault integration)

## Installation

### Basic Installation

```bash
# Add the repository (if applicable)
helm repo add nginx-standard https://github.com/City-of-Helsinki/coh-helm-charts
helm repo update

# Install with custom values file
helm install my-nginx nginx-standard/nginx-standard -f my-values.yaml
```

### Uninstall

```bash
helm uninstall my-nginx
```

## Use Cases

### File Sharing

Serve static files with Azure File Storage integration and directory browsing. Supports both **dynamic** (auto-provisioned) and **static** (existing share) storage modes.

**Key Features:**
- Two storage provisioning modes: dynamic and static
- Dynamic: Cluster automatically creates Azure File shares
- Static: Mount pre-existing Azure File shares with External Secrets
- Directory auto-indexing with customizable layouts
- Multiple location blocks with custom configurations
- Support for download headers and custom NGINX directives

---

#### Storage Modes Comparison

| Feature | Dynamic Mode | Static Mode |
|---------|--------------|-------------|
| **Setup** | Automatic | Manual |
| **External Secrets** | Not required | Required |
| **Key Vault** | Not required | Required |
| **Use Existing Share** | No | Yes |
| **Best For** | New deployments | Legacy/existing shares |

---

#### Dynamic Provisioning Example

The cluster automatically creates the file share using Azure File CSI driver.

```yaml
nginx:
  useCase: "file-sharing"

fileSharing:
  enabled: true
  storage:
    # Dynamic mode: cluster creates share automatically
    mode: "dynamic"
    mountPath: "/opt/app-root/src"
    pvc:
      enabled: true
      size: "50Gi"
      # Use cluster's dynamic provisioner
      storageClassName: "azure-file"
      accessMode: "ReadWriteMany"
      # Leave empty for dynamic provisioning
      volumeName: ""
      # Disable static Azure File configuration
      azureFile:
        enabled: false
  # Configure file serving locations
  locations:
    - path: "/"
      root: "/opt/app-root/src"
      autoindex: true
      additionalConfig: |
        autoindex_exact_size off;
        autoindex_localtime on;
    # Downloads with attachment headers
    - path: "/downloads"
      alias: "/opt/app-root/src/downloads/"
      autoindex: true
      additionalConfig: |
        add_header Content-Disposition "attachment";
# External Secrets not needed for dynamic mode
externalSecrets:
  enabled: false
routes:
  enabled: true
  items:
    - nameSuffix: ""
      host: "files.example.com"
      tls:
        termination: "edge"
```
**What happens:**
1. Helm creates PVC with `storageClassName: azurefile-csi`
2. Azure File CSI provisioner detects the PVC
3. Cluster automatically:
   - Creates or selects a storage account
   - Creates a file share (named `pvc-xxxxx`)
   - Creates a PV and binds it to the PVC
   - Generates and stores credentials
---

#### Static Provisioning Example

Mount a pre-existing Azure File share with credentials from Azure Key Vault.

```yaml
nginx:
  useCase: "file-sharing"
fileSharing:
  enabled: true
  storage:
    # Static mode: use existing file share
    mode: "static"
    mountPath: "/opt/app-root/src"
    pvc:
      enabled: true
      size: "50Gi"
      storageClassName: "azurefile"
      accessMode: "ReadWriteMany"
      # Optional: bind to specific PV
      volumeName: "my-fileshare-pv"
      # Azure File configuration for existing share
      azureFile:
        enabled: true
        # REQUIRED: name of your existing Azure File share
        shareName: "company-fileshare"
        secretName: "" #provide secret name only if secret object already exist, else it will be generated from external secrets objects 
        # Optional: override PV capacity
        capacity: ""
  # Configure file serving locations
  locations:
    - path: "/"
      root: "/opt/app-root/src"
      index: "index.html index.htm"
      autoindex: true
      additionalConfig: |
        autoindex_exact_size off;
        autoindex_localtime on;
    # Restricted admin area
    - path: "/admin"
      alias: "/opt/app-root/src/admin/"
      autoindex: false
      additionalConfig: |
        # Disable directory listing for admin
        auth_basic "Restricted Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
# External Secrets REQUIRED for static mode
externalSecrets:
  enabled: true
  refreshInterval: "1h"
  azureKeyVault:
    # REQUIRED: Your Azure Key Vault name
    vaultName: "company-keyvault"
    # REQUIRED: Azure AD tenant ID
    tenantId: "3feb6bc1-d722-4726-966c-5b58b64df752"
    # Key names in Azure Key Vault
    storageAccountNameKey: "AZURE-STORAGE-ACCOUNT-NAME"
    storageAccountKeyKey: "AZURE-STORAGE-ACCOUNT-KEY"
  # Service Principal credentials (must exist in cluster)
  servicePrincipal:
    secretName: "azure-service-principal"
routes:
  enabled: true
  items:
    - nameSuffix: ""
      host: "files.example.com"
      tls:
        termination: "edge"
```

**Prerequisites for Static Mode:**

1. **Create Azure Resources:**
- Create file share (if not exists)
- Get storage account key
- Store credentials in Key Vault
2. **Create Service Principal Secret with clientid and clientsecret**
3. **Deploy Helm Chart:**

**What happens:**
1. Helm creates SecretStore pointing to your Key Vault
2. ExternalSecret fetches credentials from Key Vault
3. Kubernetes Secret is auto-created with storage account credentials
4. PV is created pointing to your existing file share
5. PVC binds to the PV
---

#### Configuration Reference

**Storage Mode Configuration:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `fileSharing.enabled` | Enable file sharing mode | `false` |
| `fileSharing.storage.mode` | Provisioning mode: `dynamic` or `static` | `dynamic` |
| `fileSharing.storage.mountPath` | Mount path for files | `/opt/app-root/src` |

**PVC Configuration:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `fileSharing.storage.pvc.enabled` | Create PVC | `true` |
| `fileSharing.storage.pvc.size` | PVC size | `10Gi` |
| `fileSharing.storage.pvc.storageClassName` | Storage class name | `azurefile-csi` |
| `fileSharing.storage.pvc.accessMode` | Access mode | `ReadWriteMany` |
| `fileSharing.storage.pvc.volumeName` | Bind to specific PV (static mode only) | `""` |

**Azure File Configuration (Static Mode Only):**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `fileSharing.storage.pvc.azureFile.enabled` | Enable Azure File static provisioning | `false` |
| `fileSharing.storage.pvc.azureFile.shareName` | Existing Azure File share name | `fileshare` |
| `fileSharing.storage.pvc.azureFile.secretName` | Secret name with credentials | Auto-generated |
| `fileSharing.storage.pvc.azureFile.capacity` | PV capacity override | Uses `pvc.size` |

**Location Configuration:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `fileSharing.locations` | List of NGINX location blocks | See values.yaml |
| `fileSharing.locations[].path` | Location path | - |
| `fileSharing.locations[].root` | Document root directory | - |
| `fileSharing.locations[].alias` | Alias directive (alternative to root) | - |
| `fileSharing.locations[].index` | Index files | - |
| `fileSharing.locations[].autoindex` | Enable directory listing | `false` |
| `fileSharing.locations[].additionalConfig` | Custom NGINX directives | `""` |

**External Secrets Configuration (Static Mode Only):**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalSecrets.enabled` | Enable External Secrets integration | `false` |
| `externalSecrets.refreshInterval` | Sync interval from Key Vault | `1h` |
| `externalSecrets.azureKeyVault.vaultName` | Azure Key Vault name | Required |
| `externalSecrets.azureKeyVault.tenantId` | Azure AD tenant ID | Required |
| `externalSecrets.servicePrincipal.secretName` | K8s secret with SP credentials | `azure-service-principal` |
---
### Elastic Proxy

Secure proxy for Elasticsearch with built-in authentication and route filtering.

**Key Features:**
- Basic authentication with environment variables
- Route-based method restrictions
- CORS support for search endpoints
- Health check endpoints

**Example Values:**

```yaml
nginx:
  useCase: "elastic-proxy"

elasticProxy:
  enabled: true
  authSecretName: "elastic-credentials"
  upstream:
    url: "https://elasticsearch.cluster.svc:9200"
  
  clientMaxBodySize: "50m"
  
  routes:
    - path: "~ ^/([a-z][a-z_,-]*)/(_search|_msearch)$"
      methods: ["POST", "GET"]
      additionalConfig: |
        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;
        proxy_hide_header Access-Control-Max-Age;
        
        if ($request_method = 'OPTIONS') {
          add_header 'Access-Control-Allow-Origin' '*' always;
          add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
          add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
          add_header 'Access-Control-Max-Age' 1728000 always;
          add_header 'Content-Type' 'text/plain; charset=utf-8' always;
          add_header 'Content-Length' 0 always;
          return 204;
        }
        
        # Actual request - pass through with CORS headers
        proxy_pass $elasticsearch_url;
        proxy_ssl_verify off;
        proxy_redirect off;
        proxy_pass_header Authorization;
        
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;

routes:
  enabled: true
  items:
    - nameSuffix: ""
      host: "elastic-proxy.example.com"
      tls:
        termination: "edge"
```

**Configuration Reference:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `elasticProxy.enabled` | Enable elastic proxy mode | `false` |
| `elasticProxy.authSecretName` | Secret containing `user` and `password` keys | Chart name |
| `elasticProxy.upstream.url` | Elasticsearch URL | Required |
| `elasticProxy.clientMaxBodySize` | Max request body size | `50m` |
| `elasticProxy.routes` | List of route configurations | See values.yaml |

**Required Secret Format in openshift**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: elastic-credentials
type: Opaque
data:
  user: <base64-encoded-username>
  password: <base64-encoded-password>
```

### Cache Proxy

Advanced caching proxy with flexible zone configuration and per-location cache policies.

**Key Features:**
- Multiple cache zones with independent configurations
- Per-location cache policies
- Cache bypass and invalidation rules
- Background cache updates
- Stale content serving

**Example Values:**

```yaml
nginx:
  useCase: "cache"

cache:
  enabled: true
  defaultBackendUrl: "https://backend-api.svc:8000"
  clientMaxBodySize: "50m"
  volumeSize: "5Gi"
  
  proxy:
    buffersNumber: 1024
    bufferSize: "4k"
    sendTimeout: "300s"
    readTimeout: "300s"
    connectTimeout: "300s"
  
  # Define cache zones
  zones:
    - name: "hot_cache"
      path: "/srv/cache/hot"
      levels: "1:2"
      keysZone: "hot_cache:20m"
      maxSize: "2g"
      inactive: "30m"
      useTempPath: "off"
    
    - name: "static_cache"
      path: "/srv/cache/static"
      levels: "1:2"
      keysZone: "static_cache:50m"
      maxSize: "10g"
      inactive: "7d"
      useTempPath: "off"
  
  # Configure locations with different caching strategies
  locations:
    # Dynamic content with short cache
    - path: "/"
      cache:
        enabled: true
        zone: "hot_cache"
        backgroundUpdate: "on"
        useStale: "error timeout updating"
        lock: "on"
        lockTimeout: "5s"
        revalidate: "on"
        minUses: 1
        key: "$scheme$proxy_host$request_uri"
        validTime:
          default: "10m"
          notFound: "1m"
        bypass:
          - "$http_pragma"
          - "$http_authorization"
          - "$cookie_nocache"
        noCache:
          - "$http_pragma"
          - "$http_authorization"
        addHeader: true
        headerName: "X-Cache-Status"
      proxy:
        setHeaders:
          - "Host $host"
          - "X-Real-IP $remote_addr"
          - "X-Forwarded-For $proxy_add_x_forwarded_for"
    
    # Static assets with long cache
    - path: "~ \\.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf)$"
      backendUrl: "https://cdn-backend.svc:8000"
      cache:
        enabled: true
        zone: "static_cache"
        validTime:
          default: "7d"
          notFound: "10m"
        minUses: 1
        addHeader: true
      additionalConfig: |
        expires 7d;
        add_header Cache-Control "public, immutable";

observability:
  metrics:
    enabled: true
    type: "stub_status"
    stubStatus:
      path: "/nginx_status"
      allowedIPs:
        - "10.0.0.0/8"
```

**Configuration Reference:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cache.enabled` | Enable cache mode | `false` |
| `cache.defaultBackendUrl` | Default backend URL | Required |
| `cache.clientMaxBodySize` | Max request body size | `50m` |
| `cache.volumeSize` | Cache volume size | `2Gi` |
| `cache.zones` | List of cache zones | See values.yaml |
| `cache.zones[].name` | Zone identifier | - |
| `cache.zones[].path` | Cache storage path | - |
| `cache.zones[].levels` | Cache directory levels | `1:2` |
| `cache.zones[].keysZone` | Shared memory zone size | - |
| `cache.zones[].maxSize` | Maximum cache size | - |
| `cache.zones[].inactive` | Inactive cache time | - |
| `cache.zones[].useTempPath` | Use temp path | `off` |
| `cache.locations` | List of location configurations | See values.yaml |
| `cache.locations[].path` | Location path/pattern | - |
| `cache.locations[].backendUrl` | Override backend URL | Uses default |
| `cache.locations[].cache.enabled` | Enable caching for location | `true` |
| `cache.locations[].cache.zone` | Cache zone to use | - |
| `cache.locations[].cache.key` | Cache key definition | `$scheme$proxy_host$request_uri` |
| `cache.locations[].cache.validTime` | Cache validity times | - |
| `cache.locations[].cache.backgroundUpdate` | Background update | - |
| `cache.locations[].cache.useStale` | Stale cache policy | - |
| `cache.locations[].cache.bypass` | Cache bypass conditions | - |
| `cache.locations[].cache.noCache` | No-cache conditions | - |

### Front Proxy

Complex routing proxy with environment-based configuration and advanced features.

**Key Features:**
- Environment variable support (plain and secret-based)
- GEO IP filtering with whitelists
- Multiple server blocks with custom logic
- Primary servers (simple redirect/proxy)
- Custom servers (complex routing)

**Example Values:**

```yaml
nginx:
  useCase: "front-proxy"

frontProxy:
  enabled: true
  
  # Plain environment variables
  env:
    HOST_PROXY: "https://backend-api.svc.cluster.local:443"
    HOST_EN: "en.example.com"
    HOST_SV: "sv.example.com"
    PROXY_DEFAULT: "0"
    
    # IP whitelist (generates proxy_ips.conf)
    PROXY_IP: |
      137.163.145.226/32 1;
      129.0.0.0/8 1;
      10.128.0.0/14 1;
  
  # Secret-based environment variables
  secretEnv:
    DIGITRANSIT_API_KEY:
      secretName: "my-proxy-secrets"
      secretKey: "digitransit-key"
    
    CUSTOM_AUTH_TOKEN:
      secretName: "auth-secrets"
      secretKey: "auth-token-value"
  
  # Global NGINX configuration
  globalConfig:
    # HTTP block directives (e.g., GEO block)
    httpDirectives: |
      geo $remote_addr $allowed {
        default $PROXY_DEFAULT;
        include /opt/app-root/etc/proxy_ips.conf;
      }
    
    # Server block directives (applied to all servers)
    serverDirectives:
      - "real_ip_header X-Forwarded-For;"
      - "set_real_ip_from 10.128.0.0/14;"
      - "client_max_body_size 100m;"
      - "proxy_buffers 1024 4k;"
  
  # Simple redirect/proxy servers
  primaryServers:
    - serverName: "$HOST_EN"
      redirectPath: "/en"
  
  # Complex routing servers
  customServers:
    # API proxy with secret header
    - serverName: "digitransit-proxy.api.hel.fi"
      locations:
        - path: "/"
          proxyPass: "https://api.digitransit.fi/"
          additionalConfig: |
            proxy_set_header digitransit-subscription-key $DIGITRANSIT_API_KEY;
    
    # GEO-restricted admin
    - serverName: "admin.example.com"
      locations:
        - path: "= /admin"
          additionalConfig: |
            if ($allowed = 0) {
              return 403 "blocked $remote_addr";
            }
          proxyPass: "https://admin-backend.svc:8000/admin"
    
    # Simple redirect
    - serverName: "old.example.com"
      locations:
        - path: "/"
          additionalConfig: |
            return 301 https://new.example.com$uri;
```

**Configuration Reference:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontProxy.enabled` | Enable front proxy mode | `false` |
| `frontProxy.env` | Plain environment variables | `{}` |
| `frontProxy.secretEnv` | Secret-based environment variables | `{}` |
| `frontProxy.globalConfig.httpDirectives` | HTTP block directives | - |
| `frontProxy.globalConfig.serverDirectives` | Server block directives | `[]` |
| `frontProxy.primaryServers` | Simple server configurations | `[]` |
| `frontProxy.primaryServers[].serverName` | Server name | - |
| `frontProxy.primaryServers[].redirectPath` | Root redirect path | - |
| `frontProxy.customServers` | Complex server configurations | `[]` |
| `frontProxy.customServers[].serverName` | Server name | - |
| `frontProxy.customServers[].locations` | Location blocks | `[]` |
| `frontProxy.customServers[].locations[].path` | Location path | - |
| `frontProxy.customServers[].locations[].proxyPass` | Proxy target | - |
| `frontProxy.customServers[].locations[].additionalConfig` | Custom NGINX config | - |

## Configuration

### Global Settings

```yaml
global:
  namespace: ""  # Override release namespace

nameOverride: ""  # Override chart name
fullnameOverride: ""  # Override full resource names
```

### NGINX Base Configuration

```yaml
nginx:
  useCase: "file-sharing"  # file-sharing | elastic-proxy | cache | front-proxy
  replicaCount: 2
  
  image:
    full: 'registry.redhat.io/rhel8/nginx-120:latest'
    pullPolicy: "IfNotPresent"
    pullSecrets:
      - name: "quay-secret-new"
  
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "500m"
  
  service:
    port: 8080
    targetPort: 8080
    name: "http"
    type: "ClusterIP"
  
  healthChecks:
    enabled: true
    readinessPath: "/readiness"
    livenessPath: "/healthz"
    readiness:
      initialDelaySeconds: 5
      timeoutSeconds: 1
      periodSeconds: 10
      successThreshold: 1
      failureThreshold: 3
    liveness:
      initialDelaySeconds: 30
      timeoutSeconds: 1
      periodSeconds: 10
      successThreshold: 1
      failureThreshold: 3
  
  logging:
    accessLog: "/dev/stdout"
    errorLog: "/dev/stderr"
    errorLevel: "warn"
    format: "json"
  
  security:
    headers:
      enabled: true
      csp: "default-src 'self'"
      sts: "max-age=31536000; includeSubDomains; preload"
      frameOptions: "SAMEORIGIN"
      contentTypeOptions: "nosniff"
      xssProtection: "1; mode=block"
      referrerPolicy: "strict-origin-when-cross-origin"
  
  errorPages:
    enabled: false
    pages:
      404: "/custom_404.html"
      500: "/custom_50x.html"
    root: "/usr/share/nginx/html"
  
  nodeSelector: {}
  tolerations: []
  affinity: {}
```

### Observability

```yaml
observability:
  metrics:
    enabled: false
    type: "stub_status"  # stub_status | prometheus_exporter
    
    # NGINX stub_status module
    stubStatus:
      path: "/nginx_status"
      allowedIPs:
        - "10.0.0.0/8"
        - "172.16.0.0/12"
    
    # Prometheus exporter sidecar
    prometheusExporter:
      enabled: false
      image: "nginx/nginx-prometheus-exporter:0.11.0"
      port: 9113
      resources:
        requests:
          memory: "32Mi"
          cpu: "50m"
        limits:
          memory: "64Mi"
          cpu: "100m"
  
  # Prometheus ServiceMonitor
  serviceMonitor:
    enabled: false
    interval: "30s"
    scrapeTimeout: "10s"
    labels: {}
```

### Security

#### Network Policies

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              network.openshift.io/policy-group: ingress
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: openshift-dns
      ports:
        - protocol: UDP
          port: 53
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 443
```

#### External Secrets (Azure Key Vault)

```yaml
externalSecrets:
  enabled: false
  refreshInterval: "1h"
  azureKeyVault:
    vaultName: "my-keyvault"
    tenantId: "your-tenant-id"
    storageAccountNameKey: "AZURE-STORAGE-ACCOUNT-NAME"
    storageAccountKeyKey: "AZURE-STORAGE-ACCOUNT-KEY"
  servicePrincipal:
    secretName: "azure-service-principal"
```

**Required Service Principal Secret in openshift**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: azure-service-principal
type: Opaque
data:
  clientId: <base64-encoded-client-id>
  clientSecret: <base64-encoded-client-secret>
```

### Networking

#### OpenShift Routes

```yaml
routes:
  enabled: false
  annotations:
    haproxy.router.openshift.io/hsts_header: "max-age=31536000;includeSubDomains;preload"
  items:
    - nameSuffix: ""
      host: "hostname.example.com"
      path: ""
      tls:
        termination: "edge"
        insecureEdgeTerminationPolicy: "Redirect"
    
    - nameSuffix: "-internal"
      host: "internal.example.com"
      path: "/internal"
      tls:
        termination: "edge"
```

#### Service Account

```yaml
serviceAccount:
  create: false
  annotations: {}
  name: ""
```

## Examples

### Example 1: Simple File Sharing

```yaml
nginx:
  useCase: "file-sharing"
  replicaCount: 1

fileSharing:
  enabled: true
  storage:
    pvc:
      enabled: false  # Use emptyDir
  locations:
    - path: "/"
      root: "/opt/app-root/src"
      autoindex: true

routes:
  enabled: true
  items:
    - nameSuffix: ""
      host: "files.example.com"
      tls:
        termination: "edge"
```

### Example 2: Elasticsearch Proxy with Health Checks

```yaml
nginx:
  useCase: "elastic-proxy"

elasticProxy:
  enabled: true
  upstream:
    url: "https://elasticsearch:9200"
  routes:
    - path: "~ ^/([a-z][a-z_,-]*)/(_search)$"
      methods: ["POST"]
    - path: "/_cluster/health"
      methods: ["GET"]

routes:
  enabled: true
  items:
    - nameSuffix: ""
      host: "search.example.com"
      tls:
        termination: "edge"
```

### Example 3: Multi-Zone Cache

```yaml
nginx:
  useCase: "cache"

cache:
  enabled: true
  defaultBackendUrl: "http://backend:8080"
  volumeSize: "10Gi"
  
  zones:
    - name: "api_cache"
      path: "/srv/cache/api"
      levels: "1:2"
      keysZone: "api_cache:10m"
      maxSize: "1g"
      inactive: "1h"
      useTempPath: "off"
    
    - name: "static_cache"
      path: "/srv/cache/static"
      levels: "1:2"
      keysZone: "static_cache:50m"
      maxSize: "5g"
      inactive: "30d"
      useTempPath: "off"
  
  locations:
    - path: "/api"
      cache:
        enabled: true
        zone: "api_cache"
        validTime:
          default: "5m"
    
    - path: "~ \\.(css|js|jpg|png)$"
      cache:
        enabled: true
        zone: "static_cache"
        validTime:
          default: "30d"
      additionalConfig: |
        expires 30d;
```

### Example 4: Complex Front Proxy

```yaml
nginx:
  useCase: "front-proxy"

frontProxy:
  enabled: true
  env:
    HOST_APP: "www.example.com"
    HOST_PROXY: "http://backend:8080"
  
  globalConfig:
    serverDirectives:
      - "client_max_body_size 50m;"
  
  primaryServers:
    - serverName: "$HOST_APP"
      redirectPath: "/home"
  
  customServers:
    - serverName: "api.example.com"
      locations:
        - path: "/v1"
          proxyPass: "http://api-v1:8080"
        - path: "/v2"
          proxyPass: "http://api-v2:8080"
```
## Troubleshooting
### Debug Mode

Enable debug logging:

```yaml
nginx:
  logging:
    errorLevel: "debug"
```

### Validation

Validate NGINX configuration:

```bash
# Exec into pod
oc exec -it <pod-name> -- /bin/bash

# Test config
nginx -t

# View actual config
cat /etc/nginx/nginx.conf
cat /opt/app-root/etc/nginx.default.d/server.conf
```

### Health Checks

Test health endpoints:

```bash
# Readiness
curl http://<service-ip>:8080/readiness

# Liveness
curl http://<service-ip>:8080/healthz

# Metrics (if enabled)
curl http://<service-ip>:8080/nginx_status
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Test all changes with `helm lint` and `helm template`
2. Update documentation for new features
3. Follow existing code style and conventions
4. Add examples for new use cases

## Support

For issues and questions:
- Create an issue in the repository
- Contact the platform team
- Check existing documentation

## Version History

| Version | Changes |
|---------|---------|
| 1.0.0 | Initial release with four use cases |

---