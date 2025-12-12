{{/*
Expand the name of the chart.
*/}}
{{- define "nginx-standard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nginx-standard.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nginx-standard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "nginx-standard.labels" -}}
helm.sh/chart: {{ include "nginx-standard.chart" . }}
{{ include "nginx-standard.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.nginx.useCase }}
app.kubernetes.io/use-case: {{ .Values.nginx.useCase }}
{{- end }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "nginx-standard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx-standard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Generate namespace
*/}}
{{- define "nginx-standard.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}

{{/*
Check if file sharing is enabled
*/}}
{{- define "nginx-standard.fileSharingEnabled" -}}
{{- if and (eq .Values.nginx.useCase "file-sharing") .Values.fileSharing.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if elastic proxy is enabled
*/}}
{{- define "nginx-standard.elasticProxyEnabled" -}}
{{- if and (eq .Values.nginx.useCase "elastic-proxy") .Values.elasticProxy.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if front proxy is enabled
*/}}
{{- define "nginx-standard.frontProxyEnabled" -}}
{{- if and (eq .Values.nginx.useCase "front-proxy") .Values.frontProxy.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if cache proxy is enabled
*/}}
{{- define "nginx-standard.cacheEnabled" -}}
{{- if and (eq .Values.nginx.useCase "cache") .Values.cache.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Generate PVC name
*/}}
{{- define "nginx-standard.pvcName" -}}
{{- if .Values.fileSharing.storage.pvc.volumeName -}}
{{- .Values.fileSharing.storage.pvc.volumeName -}}
{{- else -}}
{{- include "nginx-standard.fullname" . }}-azure-file-pvc
{{- end -}}
{{- end -}}

{{/*
Generate PV name
*/}}
{{- define "nginx-standard.pvName" -}}
{{- if .Values.fileSharing.storage.pvc.azureFile.volumeName -}}
{{- .Values.fileSharing.storage.pvc.azureFile.volumeName -}}
{{- else if .Values.fileSharing.storage.pvc.volumeName -}}
{{- .Values.fileSharing.storage.pvc.volumeName -}}
{{- else -}}
{{- include "nginx-standard.fullname" . }}-pv
{{- end -}}
{{- end -}}

{{/*
Generate secret name for external secrets
*/}}
{{- define "nginx-standard.secretName" -}}
{{- if .Values.fileSharing.storage.pvc.azureFile.secretName -}}
{{- .Values.fileSharing.storage.pvc.azureFile.secretName -}}
{{- else -}}
{{- include "nginx-standard.fullname" . }}-secret
{{- end -}}
{{- end -}}

{{/*
Generate secret store name
*/}}
{{- define "nginx-standard.secretStoreName" -}}
{{- include "nginx-standard.fullname" . }}-azure-keyvault-secret-store
{{- end -}}

{{/*
Generate external secret name
*/}}
{{- define "nginx-standard.externalSecretName" -}}
{{- include "nginx-standard.fullname" . }}-azure-keyvault-external-secret
{{- end -}}

{{/*
Generate configmap name
*/}}
{{- define "nginx-standard.configmapName" -}}
{{- include "nginx-standard.fullname" . }}-config-map
{{- end -}}

{{/*
Define the NGINX image for the Deployment.
*/}}
{{- define "nginx-standard.image" -}}
{{- default "registry.redhat.io/ubi9/nginx-120@sha256:99d8a1d13835606114bb7785056793903c8739b7e1213b549f82ef30e0d51e5d" .Values.nginx.image.full -}}
{{- end -}}

{{/*
Check if Azure File storage is enabled
*/}}
{{- define "nginx-standard.azureFileEnabled" -}}
{{- if and (eq .Values.nginx.useCase "file-sharing") .Values.fileSharing.enabled .Values.fileSharing.storage.pvc.enabled .Values.fileSharing.storage.pvc.azureFile.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if external secrets are enabled
*/}}
{{- define "nginx-standard.externalSecretsEnabled" -}}
{{- if and (eq .Values.nginx.useCase "file-sharing") .Values.fileSharing.enabled .Values.externalSecrets.enabled .Values.externalSecrets.azureKeyVault.vaultName -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Get the Azure Key Vault URL
*/}}
{{- define "nginx-standard.vaultUrl" -}}
{{- if .Values.externalSecrets.azureKeyVault.vaultName -}}
https://{{ .Values.externalSecrets.azureKeyVault.vaultName }}.vault.azure.net
{{- else -}}
{{- fail "externalSecrets.azureKeyVault.vaultName is required when externalSecrets.enabled is true" -}}
{{- end -}}
{{- end -}}

{{/*
Get health check configuration
*/}}
{{- define "nginx-standard.healthChecksEnabled" -}}
{{- .Values.nginx.healthChecks.enabled | default true -}}
{{- end -}}

{{/*
Generate readiness probe path
*/}}
{{- define "nginx-standard.readinessPath" -}}
{{- .Values.nginx.healthChecks.readinessPath | default "/readiness" -}}
{{- end -}}

{{/*
Generate liveness probe path
*/}}
{{- define "nginx-standard.livenessPath" -}}
{{- .Values.nginx.healthChecks.livenessPath | default "/healthz" -}}
{{- end -}}

{{/*
Generate route annotations
*/}}
{{- define "nginx-standard.routeAnnotations" -}}
{{- with .Values.route.annotations -}}
{{ toYaml . }}
{{- else -}}
haproxy.router.openshift.io/hsts_header: max-age=31536000;includeSubDomains;preload
haproxy.router.openshift.io/disable_cookies: "true"
{{- end -}}
{{- end -}}

{{/*
Generate Azure File share name
*/}}
{{- define "nginx-standard.azureFileShareName" -}}
{{- .Values.fileSharing.storage.pvc.azureFile.shareName | default "fileshare" -}}
{{- end -}}

{{/*
Generate PV capacity
*/}}
{{- define "nginx-standard.pvCapacity" -}}
{{- .Values.fileSharing.storage.pvc.azureFile.capacity | default .Values.fileSharing.storage.pvc.size -}}
{{- end -}}

{{/*
Check if route is enabled
*/}}
{{- define "nginx-standard.routeEnabled" -}}
{{- .Values.route.enabled | default false -}}
{{- end -}}

{{/*
Get route host
*/}}
{{- define "nginx-standard.routeHost" -}}
{{- .Values.route.host | required "route.host is required when route.enabled is true" -}}
{{- end -}}

{{/*
Get route TLS termination
*/}}
{{- define "nginx-standard.routeTLSTermination" -}}
{{- .Values.route.tls.termination | default "edge" -}}
{{- end -}}

{{/*
Get route insecure edge termination policy
*/}}
{{- define "nginx-standard.routeInsecureEdgeTerminationPolicy" -}}
{{- .Values.route.tls.insecureEdgeTerminationPolicy | default "Redirect" -}}
{{- end -}}

{{/*
Get service port 
*/}}
{{- define "nginx-standard.servicePort" -}}
{{- default 8080 .Values.nginx.service.port -}}
{{- end -}}

{{/*
Get service name
*/}}
{{- define "nginx-standard.serviceName" -}}
{{- default "http" .Values.nginx.service.name -}}
{{- end -}}

{{/*
Get replica count
*/}}
{{- define "nginx-standard.replicaCount" -}}
{{- .Values.nginx.replicaCount | default 1 -}}
{{- end -}}

{{/*
Generate service account name if enabled
*/}}
{{- define "nginx-standard.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "nginx-standard.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
NGINX Security Headers Helper
*/}}
{{- define "nginx-standard.securityHeaders" -}}
{{- if .Values.nginx.security.headers.enabled -}}
add_header Content-Security-Policy "{{ .Values.nginx.security.headers.csp }}" always;
add_header Strict-Transport-Security "{{ .Values.nginx.security.headers.sts }}" always;
add_header X-Frame-Options "{{ .Values.nginx.security.headers.frameOptions }}" always;
add_header X-Content-Type-Options "{{ .Values.nginx.security.headers.contentTypeOptions }}" always;
add_header X-XSS-Protection "{{ .Values.nginx.security.headers.xssProtection }}" always;
{{- if .Values.nginx.security.headers.referrerPolicy }}
add_header Referrer-Policy "{{ .Values.nginx.security.headers.referrerPolicy }}" always;
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Validate cache configuration
*/}}
{{- define "nginx-standard.validateCache" -}}
{{- if eq .Values.nginx.useCase "cache" -}}
  {{- if not .Values.cache.enabled -}}
    {{- fail "cache.enabled must be true when nginx.useCase is 'cache'" -}}
  {{- end -}}
  {{- if .Values.cache.zones -}}
    {{- if not .Values.cache.locations -}}
      {{- fail "cache.locations is required when using cache.zones" -}}
    {{- end -}}
  {{- else -}}
    {{- if not .Values.cache.backendUrl -}}
      {{- fail "cache.backendUrl is required when not using cache.zones" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate elastic proxy configuration
*/}}
{{- define "nginx-standard.validateElasticProxy" -}}
{{- if eq .Values.nginx.useCase "elastic-proxy" -}}
  {{- if not .Values.elasticProxy.enabled -}}
    {{- fail "elasticProxy.enabled must be true when nginx.useCase is 'elastic-proxy'" -}}
  {{- end -}}
  {{- if not .Values.elasticProxy.upstream.url -}}
    {{- fail "elasticProxy.upstream.url is required" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
=============================================================================
CACHE CONFIGURATION HELPERS - NEW FLEXIBLE APPROACH
=============================================================================
*/}}

{{/*
Generate cache proxy_cache_path directives from zones configuration
*/}}
{{- define "nginx-standard.cacheZones" -}}
{{- if .Values.cache.zones }}
{{- range .Values.cache.zones }}
proxy_cache_path {{ .path }} levels={{ .levels }} keys_zone={{ .keysZone }} max_size={{ .maxSize }} inactive={{ .inactive }} use_temp_path={{ .useTempPath }};
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate location block with cache configuration
*/}}
{{- define "nginx-standard.cacheLocation" -}}
{{- $location := .location }}
{{- $root := .root }}
location {{ $location.path }} {
  {{- if $location.cache.enabled }}
  # Cache configuration
  proxy_cache {{ $location.cache.zone }};
  proxy_cache_key {{ $location.cache.key | default "$scheme$proxy_host$request_uri" }};
  
  {{- if $location.cache.validTime }}
  {{- if $location.cache.validTime.default }}
  proxy_cache_valid 200 301 302 {{ $location.cache.validTime.default }};
  {{- end }}
  {{- if $location.cache.validTime.notFound }}
  proxy_cache_valid 404 {{ $location.cache.validTime.notFound }};
  {{- end }}
  {{- if $location.cache.validTime.any }}
  proxy_cache_valid any {{ $location.cache.validTime.any }};
  {{- end }}
  {{- end }}
  
  {{- if $location.cache.backgroundUpdate }}
  proxy_cache_background_update {{ $location.cache.backgroundUpdate }};
  {{- end }}
  {{- if $location.cache.useStale }}
  proxy_cache_use_stale {{ $location.cache.useStale }};
  {{- end }}
  {{- if $location.cache.lock }}
  proxy_cache_lock {{ $location.cache.lock }};
  {{- end }}
  {{- if $location.cache.lockTimeout }}
  proxy_cache_lock_timeout {{ $location.cache.lockTimeout }};
  {{- end }}
  {{- if $location.cache.revalidate }}
  proxy_cache_revalidate {{ $location.cache.revalidate }};
  {{- end }}
  {{- if $location.cache.minUses }}
  proxy_cache_min_uses {{ $location.cache.minUses }};
  {{- end }}
  
  {{- if $location.cache.bypass }}
  proxy_cache_bypass {{ join " " $location.cache.bypass }};
  {{- end }}
  {{- if $location.cache.noCache }}
  proxy_no_cache {{ join " " $location.cache.noCache }};
  {{- end }}
  
  {{- if $location.cache.addHeader }}
  add_header {{ $location.cache.headerName | default "X-Cache-Status" }} $upstream_cache_status;
  {{- end }}
  {{- end }}
  
  {{- if or $location.backendUrl $root.Values.cache.defaultBackendUrl }}
  # Proxy configuration
  proxy_pass {{ $location.backendUrl | default $root.Values.cache.defaultBackendUrl }};
  
  {{- $proxy := $location.proxy | default $root.Values.cache.proxy }}
  {{- if $proxy.buffersNumber }}
  proxy_buffers {{ $proxy.buffersNumber }} {{ $proxy.bufferSize | default "4k" }};
  proxy_buffer_size {{ $proxy.bufferSize | default "4k" }};
  {{- end }}
  {{- if $proxy.sendTimeout }}
  proxy_send_timeout {{ $proxy.sendTimeout }};
  {{- end }}
  {{- if $proxy.readTimeout }}
  proxy_read_timeout {{ $proxy.readTimeout }};
  {{- end }}
  {{- if $proxy.connectTimeout }}
  proxy_connect_timeout {{ $proxy.connectTimeout }};
  {{- end }}
  
  {{- if $proxy.setHeaders }}
  {{- range $proxy.setHeaders }}
  proxy_set_header {{ . }};
  {{- end }}
  {{- end }}
  {{- end }}
  
  {{- if $location.additionalConfig }}
  # Additional configuration
  {{ $location.additionalConfig | nindent 2 }}
  {{- end }}
}
{{- end }}

{{/*
Generate NGINX http block with cache zones (NEW APPROACH)
*/}}
{{- define "nginx-standard.cacheHttpBlock" -}}
{{- if eq .Values.nginx.useCase "cache" }}
# Cache zones configuration
{{ include "nginx-standard.cacheZones" . }}

# Upstream cache status variable
map $upstream_cache_status $cache_header {
  "MISS" "MISS";
  "HIT" "HIT";
  "EXPIRED" "EXPIRED";
  "STALE" "STALE";
  "UPDATING" "UPDATING";
  "REVALIDATED" "REVALIDATED";
  "BYPASS" "BYPASS";
  default "UNKNOWN";
}
{{- end }}
{{- end }}

{{/*
OLD CACHE HTTP CONF - KEPT FOR BACKWARD COMPATIBILITY
This is your original hardcoded cache configuration
*/}}
{{- define "nginx-standard.cacheHttpConf" -}}
{{- $cfg := .Values.cache.config | default dict -}}
{{- $volumeName := .Values.cache.volumeName | default "nginx-cache" -}}
{{- $path := printf "/srv/cache/%s" $volumeName -}}
{{- printf "proxy_cache_path %s levels=%s keys_zone=%s max_size=%s inactive=%s use_temp_path=%s;" $path (default "1:2" $cfg.levels) (default "my_cache:10m" $cfg.keysZone) (default "1g" $cfg.maxSize) (default "60m" $cfg.inactive) (default "off" $cfg.useTempPath) }}
proxy_no_cache $cookie_nocache $arg_nocache $http_authorization $http_apikey;
proxy_cache_bypass $cookie_nocache $arg_nocache $http_authorization $http_apikey;
proxy_cache_background_update {{ default "on" $cfg.backgroundUpdate }};
proxy_cache_use_stale {{ default "error timeout" $cfg.useStale }};
proxy_cache_key $uri$args;
proxy_cache_valid 200 302 {{ default "10m" $cfg.validTime.default }};
proxy_cache_valid 404 {{ default "1m" $cfg.validTime.notFound }};
proxy_cache_lock on;
proxy_cache_lock_age 5s;
add_header X-Cache-Status $upstream_cache_status;
add_header X-Cache-Uri $uri$args;
{{- end -}}

{{/*
=============================================================================
NGINX MAIN CONFIGURATION
=============================================================================
*/}}

{{/*
Conditional NGINX main configuration
*/}}
{{- define "nginx-standard.nginxConf" -}}
{{- if eq .Values.nginx.useCase "elastic-proxy" -}}
worker_processes auto;
error_log /dev/stderr {{ .Values.nginx.logging.errorLevel | default "notice" }};
pid /var/run/nginx.pid;

env ELASTICSEARCH_URL;
env ELASTIC_PASSWORD;
env ELASTIC_USER;

load_module modules/ngx_http_perl_module.so;
events {
    worker_connections 1024;
}

http {
    proxy_temp_path /tmp/proxy_temp;
    client_body_temp_path /tmp/client_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    perl_set $elasticsearch_url '
      sub {
        return $ENV{"ELASTICSEARCH_URL"} || "";
      }
    ';
    
    # Perl script to set authorization header
    perl_set $elastic_authorization '
      sub {
        use MIME::Base64;
        if (exists($ENV{"ELASTIC_USER"}) && exists($ENV{"ELASTIC_PASSWORD"})) {
          return encode_base64($ENV{"ELASTIC_USER"} . ":" . $ENV{"ELASTIC_PASSWORD"}, "");
        }
        return "";
      }
    ';
    # Log in JSON Format 
    log_format nginxlog_json escape=json '{ "time": "$time_iso8601", '
      '"level": "info", '
      '"source": "nginx", '
      '"remote_addr": "$remote_addr", '
      '"method": "$request_method", '
      '"uri": "$request_uri", '
      '"status": $status, '
      '"response_time": $request_time, '
      '"bytes_sent": $body_bytes_sent, '
      '"referer": "$http_referer", '
      '"user_agent": "$http_user_agent", '
      '"x_forwarded_for": "$http_x_forwarded_for", '
      '"request_id": "$request_id" }';
    access_log /dev/stdout nginxlog_json;

    sendfile on;
    keepalive_timeout 65;

    # Include custom server block (server.conf)
    include /opt/app-root/etc/nginx.default.d/*.conf;
}
{{- else if eq .Values.nginx.useCase "cache" -}}
worker_processes auto;
error_log /dev/stderr {{ .Values.nginx.logging.errorLevel | default "notice" }};
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    {{- if .Values.cache.zones }}
    # NEW: Cache settings from zones configuration
    {{ include "nginx-standard.cacheHttpBlock" . | nindent 4 }}
    {{- else }}
    # OLD: Legacy cache settings (backward compatibility)
    {{ include "nginx-standard.cacheHttpConf" . | nindent 4 }}
    {{- end }}

    # JSON log format
    log_format json_log escape=json '{"time":"$time_iso8601","level":"info","source":"nginx","remote_addr":"$remote_addr","method":"$request_method","uri":"$request_uri","status":$status,"response_time":$request_time,"bytes_sent":$body_bytes_sent,"referer":"$http_referer","user_agent":"$http_user_agent","x_forwarded_for":"$http_x_forwarded_for","request_id":"$request_id"}';
    access_log {{ .Values.nginx.logging.accessLog | default "/dev/stdout" }} json_log;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Include custom server block (server.conf)
    include /opt/app-root/etc/nginx.default.d/*.conf;
}
{{- end -}}
{{- end -}}

{{/*
=============================================================================
SERVER CONFIGURATION
=============================================================================
*/}}

{{/*
Conditional NGINX server configuration
*/}}
{{- define "nginx-standard.serverConfig" -}}
{{- if eq .Values.nginx.useCase "file-sharing" -}}
{{- range .Values.fileSharing.locations -}}
location {{ .path }} {
{{- if .root }}
  root {{ .root }};
{{- end }}
{{- if .alias }}
  alias {{ .alias }};
{{- end }}
{{- if .index }}
  index {{ .index }};
{{- end }}
{{- if hasKey . "autoindex" }}
  autoindex {{ if .autoindex }}on{{ else }}off{{ end }};
{{- end }}
{{- if .additionalConfig }}
{{ .additionalConfig | nindent 2 }}
{{- end }}
}
{{ end -}}

{{- else if eq .Values.nginx.useCase "elastic-proxy" -}}
server {
    listen {{ include "nginx-standard.servicePort" . }} default_server;
    server_name _;
    # Hardcoded DNS resolver for Kubernetes/OpenShift
    # Tries multiple common DNS services for maximum compatibility
    resolver dns-default.openshift-dns.svc.cluster.local 
             valid=10s 
             ipv6=off;
    resolver_timeout 5s;
    client_max_body_size {{ .Values.elasticProxy.clientMaxBodySize | default "50m" }};
{{- range .Values.elasticProxy.routes }}
    location {{ .path }} {
        {{- $methods := join " " .methods }}
        {{- if $methods }}
        limit_except {{ $methods }} {
          deny all;
        }
        {{- end }}
        
        # NGINX Proxy Settings
        proxy_connect_timeout {{ $.Values.elasticProxy.proxy.connectTimeout | default "60s" }};
        proxy_send_timeout {{ $.Values.elasticProxy.proxy.sendTimeout | default "60s" }};
        proxy_read_timeout {{ $.Values.elasticProxy.proxy.readTimeout | default "60s" }};
        proxy_buffer_size {{ $.Values.elasticProxy.proxy.bufferSize | default "8k" }};
        proxy_buffers {{ $.Values.elasticProxy.proxy.buffersNumber | default 4 }} {{ $.Values.elasticProxy.proxy.bufferSize | default "8k" }};
        
        # Standard Proxy Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Elastic Authentication Header
        proxy_set_header Authorization "Basic $elastic_authorization";
        add_header X-Debug-Auth "Basic $elastic_authorization" always;
        
        # Proxy Pass to Elasticsearch
        proxy_pass $elasticsearch_url;
        proxy_ssl_verify off;
        proxy_redirect off;
        proxy_pass_header Authorization;
        
        # CORS Headers for search endpoints
        {{- if or (contains "_search" .path) (contains "_msearch" .path) }}
        if ($request_method = 'OPTIONS') {
          return 204;
        }
        proxy_pass_header Access-Control-Allow-Origin;
        proxy_pass_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        {{- end }}

        {{- if .additionalConfig }}
{{ .additionalConfig | nindent 8 }}
        {{- end }}
    }
{{- end }}
    # Health check endpoints
    location {{ include "nginx-standard.readinessPath" . }} {
      access_log off;
      add_header Content-Type text/plain;
      return 200 'OK';
    }
    
    location {{ include "nginx-standard.livenessPath" . }} {
      access_log off;
      add_header Content-Type text/plain;
      return 200 'OK';
    }
}

{{- else if eq .Values.nginx.useCase "front-proxy" -}}
# Primary Servers (Simple redirect and default proxy)
{{- range .Values.frontProxy.primaryServers }}
server {
    listen {{ include "nginx-standard.servicePort" $ }};
    server_name {{ .serverName }};

    # Global server directives
    {{- with $.Values.frontProxy.globalConfig.serverDirectives }}
    {{- range . }}
    {{ . }};
    {{- end }}
    {{- end }}

    # Root redirect
    location = / {
        return 301 https://{{ .serverName }}{{ .redirectPath }};
    }

    # Default proxy
    location / {
        proxy_pass {{ $.Values.frontProxy.env.HOST_PROXY }}/; 
    }
}
{{- end }}

# Custom Servers (Complex logic/API proxies)
{{- range .Values.frontProxy.customServers }}
server {
    listen {{ include "nginx-standard.servicePort" $ }};
    server_name {{ .serverName }};

    # Global server directives
    {{- with $.Values.frontProxy.globalConfig.serverDirectives }}
    {{- range . }}
    {{ . }};
    {{- end }}
    {{- end }}
    
    {{- range .locations }}
    location {{ .path }} {
        {{- if .additionalConfig }}
{{ .additionalConfig | nindent 8 }}
        {{- end }}

        {{- if .proxyPass }}
        proxy_pass {{ .proxyPass }}/;
        {{- end }}
    }
    {{- end }}
}
{{- end }}

{{- else if eq .Values.nginx.useCase "cache" -}}
{{- if .Values.cache.locations }}
# NEW: Per-location cache configuration
server {
    listen {{ include "nginx-standard.servicePort" . }} default_server;
    server_name _;
    
    {{- if .Values.cache.clientMaxBodySize }}
    client_max_body_size {{ .Values.cache.clientMaxBodySize }};
    {{- end }}
    large_client_header_buffers 4 32k;
    
    {{- range .Values.cache.locations }}
    {{ include "nginx-standard.cacheLocation" (dict "root" $ "location" .) }}
    {{- end }}
}
{{- else }}
# OLD: Legacy single location cache (backward compatibility)
server {
    listen {{ include "nginx-standard.servicePort" . }} default_server;
    server_name _;
    client_max_body_size {{ .Values.cache.clientMaxBodySize | default "100m" }};
    large_client_header_buffers 4 32k;
    
    location / {
        proxy_buffers {{ .Values.cache.proxy.buffersNumber | default 1024 }} {{ .Values.cache.proxy.bufferSize | default "4k" }};
        proxy_buffer_size {{ .Values.cache.proxy.bufferSize | default "16k" }};
        proxy_send_timeout {{ .Values.cache.proxy.sendTimeout | default "600s" }};
        proxy_read_timeout {{ .Values.cache.proxy.readTimeout | default "600s" }};
        proxy_connect_timeout {{ .Values.cache.proxy.connectTimeout | default "600s" }};

        # Cache directives
        proxy_cache my_cache;
        proxy_cache_valid 200 302 {{ .Values.cache.config.validTime.default | default "10m" }};
        proxy_cache_valid 404 {{ .Values.cache.config.validTime.notFound | default "1m" }};
        
        # Standard headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_pass {{ .Values.cache.backendUrl | required "cache.backendUrl is required" }};
    }
}
{{- end }}

{{- else -}}
# Default configuration
location / {
    root /usr/share/nginx/html;
    index index.html index.htm;
}
{{- end -}}
{{- end -}}

{{/*
Generate cache server configuration specifically (called from configmap.yaml)
This is a separate helper because configmap.yaml specifically calls it
*/}}
{{- define "nginx-standard.cacheServerConfig" -}}
{{- if .Values.cache.locations }}
# Per-location cache configuration
{{- if .Values.cache.clientMaxBodySize }}
client_max_body_size {{ .Values.cache.clientMaxBodySize }};
{{- end }}

{{- range .Values.cache.locations }}
{{ include "nginx-standard.cacheLocation" (dict "root" $ "location" .) }}
{{- end }}
{{- else }}
# Legacy single location cache
client_max_body_size {{ .Values.cache.clientMaxBodySize | default "100m" }};
large_client_header_buffers 4 32k;

location / {
    proxy_buffers {{ .Values.cache.proxy.buffersNumber | default 1024 }} {{ .Values.cache.proxy.bufferSize | default "4k" }};
    proxy_buffer_size {{ .Values.cache.proxy.bufferSize | default "16k" }};
    proxy_send_timeout {{ .Values.cache.proxy.sendTimeout | default "600s" }};
    proxy_read_timeout {{ .Values.cache.proxy.readTimeout | default "600s" }};
    proxy_connect_timeout {{ .Values.cache.proxy.connectTimeout | default "600s" }};

    # Cache directives
    proxy_cache my_cache;
    proxy_cache_valid 200 302 {{ .Values.cache.config.validTime.default | default "10m" }};
    proxy_cache_valid 404 {{ .Values.cache.config.validTime.notFound | default "1m" }};
    
    # Standard headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_pass {{ .Values.cache.backendUrl | required "cache.backendUrl is required" }};
}
{{- end }}
{{- end -}}