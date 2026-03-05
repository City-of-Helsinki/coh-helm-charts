{{/*
Expand the name of the chart.
*/}}
{{- define "nginx-standard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nginx-standard.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nginx-standard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

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
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nginx-standard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nginx-standard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nginx-standard.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nginx-standard.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "nginx-standard.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "nginx-standard.configmapName" -}}
{{- include "nginx-standard.fullname" . }}-config
{{- end }}

{{/*
Service port
*/}}
{{- define "nginx-standard.servicePort" -}}
{{- .Values.nginx.service.port | default 8080 }}
{{- end }}

{{/*
Service name
*/}}
{{- define "nginx-standard.serviceName" -}}
{{- .Values.nginx.service.name | default "http" }}
{{- end }}

{{/*
Replica count (respects autoscaling)
*/}}
{{- define "nginx-standard.replicaCount" -}}
{{- if .Values.autoscaling.enabled }}
{{- .Values.autoscaling.minReplicas }}
{{- else }}
{{- .Values.nginx.replicaCount | default 1 }}
{{- end }}
{{- end }}

{{/*
Image reference - Selects image based on use case
*/}}
{{- define "nginx-standard.image" -}}
{{- $useCase := default "file-sharing" .Values.nginx.useCase -}}

{{/* Check if there's a custom image specified in values */}}
{{- if .Values.nginx.image.full -}}
{{- .Values.nginx.image.full -}}
{{- else -}}
  {{/* Default images for each use case */}}
  {{- if eq $useCase "file-sharing" -}}
registry.redhat.io/rhel9/nginx-124:latest
  {{- else if eq $useCase "elastic-proxy" -}}
container-registry.platta-net.hel.fi/devops/nginxinc/nginx-unprivileged:alpine-perl
  {{- else if eq $useCase "cache" -}}
registry.redhat.io/rhel9/nginx-124:latest
  {{- else if eq $useCase "front-proxy" -}}
container-registry.platta-net.hel.fi/devops/nginxinc/nginx-unprivileged:alpine-perl
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Health check paths
*/}}
{{- define "nginx-standard.readinessPath" -}}
{{- .Values.nginx.healthChecks.readinessPath | default "/readiness" }}
{{- end }}

{{- define "nginx-standard.livenessPath" -}}
{{- .Values.nginx.healthChecks.livenessPath | default "/healthz" }}
{{- end }}

{{/*
Health checks enabled
*/}}
{{- define "nginx-standard.healthChecksEnabled" -}}
{{- if .Values.nginx.healthChecks.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{/*
==============================================================================
USE CASE FEATURE FLAGS
==============================================================================
*/}}

{{- define "nginx-standard.cacheEnabled" -}}
{{- if and (eq .Values.nginx.useCase "cache") .Values.cache.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{- define "nginx-standard.elasticProxyEnabled" -}}
{{- if and (eq .Values.nginx.useCase "elastic-proxy") .Values.elasticProxy.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{- define "nginx-standard.frontProxyEnabled" -}}
{{- if and (eq .Values.nginx.useCase "front-proxy") .Values.frontProxy.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{- define "nginx-standard.fileSharingEnabled" -}}
{{- if and (eq .Values.nginx.useCase "file-sharing") .Values.fileSharing.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{/*
==============================================================================
EXTERNAL SECRETS & STORAGE
==============================================================================
*/}}

{{- define "nginx-standard.externalSecretsEnabled" -}}
{{- if .Values.externalSecrets.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{- define "nginx-standard.azureFileEnabled" -}}
{{- if and (eq .Values.nginx.useCase "file-sharing") .Values.fileSharing.enabled .Values.fileSharing.storage.pvc.enabled (eq .Values.fileSharing.storage.mode "static") .Values.fileSharing.storage.pvc.azureFile.enabled }}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}

{{- define "nginx-standard.secretName" -}}
{{- include "nginx-standard.fullname" . }}-secret
{{- end }}

{{- define "nginx-standard.secretStoreName" -}}
{{- include "nginx-standard.fullname" . }}-secretstore
{{- end }}

{{- define "nginx-standard.externalSecretName" -}}
{{- include "nginx-standard.fullname" . }}-externalsecret
{{- end }}

{{- define "nginx-standard.vaultUrl" -}}
{{- printf "https://%s.vault.azure.net" .Values.externalSecrets.azureKeyVault.vaultName }}
{{- end }}

{{- define "nginx-standard.pvcName" -}}
{{- include "nginx-standard.fullname" . }}-pvc
{{- end }}

{{- define "nginx-standard.pvName" -}}
{{- include "nginx-standard.fullname" . }}-pv
{{- end }}

{{- define "nginx-standard.azureFileShareName" -}}
{{- .Values.fileSharing.storage.pvc.azureFile.shareName }}
{{- end }}

{{- define "nginx-standard.pvCapacity" -}}
{{- if .Values.fileSharing.storage.pvc.azureFile.capacity }}
{{- .Values.fileSharing.storage.pvc.azureFile.capacity }}
{{- else }}
{{- .Values.fileSharing.storage.pvc.size }}
{{- end }}
{{- end }}

{{/*
==============================================================================
VALIDATION HELPERS
==============================================================================
*/}}

{{- define "nginx-standard.validateCache" -}}
{{- if eq .Values.nginx.useCase "cache" }}
{{- if not .Values.cache.enabled }}
{{- fail "cache.enabled must be true when nginx.useCase is 'cache'" }}
{{- end }}
{{- if not .Values.cache.zones }}
{{- fail "cache.zones must be defined when nginx.useCase is 'cache'" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "nginx-standard.validateElasticProxy" -}}
{{- if eq .Values.nginx.useCase "elastic-proxy" }}
{{- if not .Values.elasticProxy.enabled }}
{{- fail "elasticProxy.enabled must be true when nginx.useCase is 'elastic-proxy'" }}
{{- end }}
{{- if not .Values.elasticProxy.upstream.url }}
{{- fail "elasticProxy.upstream.url must be defined when nginx.useCase is 'elastic-proxy'" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
SECURITY HEADERS
==============================================================================
*/}}

{{- define "nginx-standard.securityHeaders" -}}
{{- if .Values.nginx.security.headers.enabled -}}
add_header X-Content-Type-Options "{{ .Values.nginx.security.headers.contentTypeOptions }}" always;
add_header X-Frame-Options "{{ .Values.nginx.security.headers.frameOptions }}" always;
add_header X-XSS-Protection "{{ .Values.nginx.security.headers.xssProtection }}" always;
add_header Referrer-Policy "{{ .Values.nginx.security.headers.referrerPolicy }}" always;
{{- if .Values.nginx.security.headers.csp }}
add_header Content-Security-Policy "{{ .Values.nginx.security.headers.csp }}" always;
{{- end }}
{{- if .Values.nginx.security.headers.sts }}
add_header Strict-Transport-Security "{{ .Values.nginx.security.headers.sts }}" always;
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
NGINX MAIN CONFIGURATION (nginx.conf)
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf" -}}
{{- if eq .Values.nginx.useCase "cache" -}}
{{ include "nginx-standard.nginxMainConf.cache" . }}
{{- else if eq .Values.nginx.useCase "elastic-proxy" -}}
{{ include "nginx-standard.nginxMainConf.elasticProxy" . }}
{{- else if eq .Values.nginx.useCase "front-proxy" -}}
{{ include "nginx-standard.nginxMainConf.frontProxy" . }}
{{- else if eq .Values.nginx.useCase "file-sharing" -}}
{{ include "nginx-standard.nginxMainConf.fileSharing" . }}
{{- else -}}
{{ include "nginx-standard.nginxMainConf.default" . }}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
NGINX SERVER CONFIGURATION (server.conf)
==============================================================================
*/}}

{{- define "nginx-standard.nginxServerConf" -}}
{{- if eq .Values.nginx.useCase "cache" -}}
{{- include "nginx-standard.serverConf.cache" . }}
{{- else if eq .Values.nginx.useCase "elastic-proxy" -}}
{{- include "nginx-standard.serverConf.elasticProxy" . }}
{{- else if eq .Values.nginx.useCase "front-proxy" -}}
{{- include "nginx-standard.serverConf.frontProxy" . }}
{{- else if eq .Values.nginx.useCase "file-sharing" -}}
{{- include "nginx-standard.serverConf.fileSharing" . -}}
{{- else -}}
{{- include "nginx-standard.serverConf.default" . }}
{{- end -}}
{{- end -}}

{{/*
==============================================================================
COMMON BUILDING BLOCKS
==============================================================================
*/}}

{{/* Common worker and events configuration */}}
{{- define "nginx-standard.commonWorkerEvents" }}
worker_processes auto;
error_log {{ .Values.nginx.logging.errorLog | default "/dev/stderr" }} {{ .Values.nginx.logging.errorLevel | default "notice" }};
pid /var/run/nginx.pid;

events {
  worker_connections 1024;
}
{{ end }}

{{/* Common HTTP block start */}}
{{- define "nginx-standard.commonHttpBlockStart" }}
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
{{- end }}

{{/* Common JSON log format */}}
{{- define "nginx-standard.jsonLogFormat" -}}
{{- $requestIdVar := "$nginx_req_id" -}}
{{- $includeCache := false -}}
{{- if hasKey . "requestIdVar" -}}
{{- $requestIdVar = .requestIdVar -}}
{{- end -}}
{{- if hasKey . "includeCache" -}}
{{- $includeCache = .includeCache -}}
{{- end -}}
log_format json_log escape=json '{"time":"$time_iso8601","level":"info","source":"nginx","remote_addr":"$remote_addr","method":"$request_method","uri":"$request_uri","status":$status,"response_time":$request_time,"bytes_sent":$body_bytes_sent,{{- if $includeCache }}"cache_status":"$upstream_cache_status",{{- end }}"referer":"$http_referer","user_agent":"$http_user_agent","x_forwarded_for":"$http_x_forwarded_for","request_id":"{{ $requestIdVar }}"}';
access_log {{ .Values.nginx.logging.accessLog | default "/dev/stdout" }} json_log;
{{- end }}

{{/* Request ID generation */}}
{{- define "nginx-standard.requestIdGeneration" -}}
set $nginx_req_id $http_x_request_id;
if ($nginx_req_id = "") {
  set $nginx_req_id "nginx-$connection-$msec";
}
add_header X-Request-ID $nginx_req_id;
{{- end }}

{{/* Common server block start */}}
{{- define "nginx-standard.commonServerBlockStart" -}}
server {
  listen {{ include "nginx-standard.servicePort" . | default "8080" }} default_server;
  listen [::]:{{ include "nginx-standard.servicePort" . | default "8080" }} default_server;
  server_name _;
  
  {{- include "nginx-standard.requestIdGeneration" . | nindent 2 }}
{{- include "nginx-standard.securityHeaders" . | nindent 2 }}
{{- end }}

{{/* Metrics endpoint */}}
{{- define "nginx-standard.metricsLocation" -}}
{{- if .Values.observability.metrics.enabled -}}
{{- if eq .Values.observability.metrics.type "stub_status" -}}
location {{ .Values.observability.metrics.stubStatus.path }} {
  stub_status;
  access_log off;
  {{- if .Values.observability.metrics.stubStatus.allowedIPs }}
  {{- range .Values.observability.metrics.stubStatus.allowedIPs }}
  allow {{ . }};
  {{- end }}
  deny all;
  {{- end }}
}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Health check locations */}}
{{- define "nginx-standard.healthCheckLocations" -}}
location = {{ include "nginx-standard.readinessPath" . }} {
  access_log off;
  add_header Content-Type text/plain;
  return 200 'OK';
}
location = {{- include "nginx-standard.livenessPath" . }} {
  access_log off;
  add_header Content-Type text/plain;
  return 200 'OK';
}
{{- end }}

{{/*
==============================================================================
CACHE USE CASE
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf.cache" -}}
# NGINX Cache Proxy Mode
{{- include "nginx-standard.commonWorkerEvents" . }}
{{- include "nginx-standard.commonHttpBlockStart" . }}
  # Cache zones
{{- include "nginx-standard.cacheHttpBlock" . | nindent 2 }}
  # JSON log format with cache status
{{- $ctx := dict "Values" .Values "includeCache" true }}
{{- include "nginx-standard.jsonLogFormat" $ctx | nindent 2 }}
{{- if .Values.cache.httpDirectives }}
  # Global HTTP directives
{{ .Values.cache.httpDirectives | nindent 2 }}
{{- end }}
{{- include "nginx-standard.commonServerBlockStart" . | nindent 2 -}}
    # Include custom server configuration
    include /opt/app-root/etc/nginx.default.d/*.conf;
{{- if .Values.observability.metrics.enabled }}
{{- include "nginx-standard.metricsLocation" . | nindent 4 }}
{{- end }}
  }
}
{{- end }}

{{- define "nginx-standard.serverConf.cache" -}}
{{ include "nginx-standard.cacheServerConfig" . }}
{{- end -}}

{{/* Cache HTTP block configuration */}}
{{- define "nginx-standard.cacheHttpBlock" -}}
{{- range .Values.cache.zones }}
proxy_cache_path {{ .path }} levels={{ .levels }} keys_zone={{ .keysZone }} max_size={{ .maxSize }} inactive={{ .inactive }} use_temp_path={{ .useTempPath }};
{{- end }}
{{- end -}}

{{/* Cache server configuration */}}
{{- define "nginx-standard.cacheServerConfig" -}}
client_max_body_size {{ .Values.cache.clientMaxBodySize | default "50m" }};
{{- if .Values.cache.serverDirectives }}
{{- range .Values.cache.serverDirectives }}
{{ . }};
{{- end }}
{{- end }}

{{- range .Values.cache.locations }}
location {{ .path }} {
  {{- if not .noProxyPass }}
  {{- $backendUrl := .backendUrl | default $.Values.cache.defaultBackendUrl }}
  {{- if not $backendUrl }}
  {{- fail "backendUrl must be specified either globally (cache.defaultBackendUrl) or per location" }}
  {{- end }}
  proxy_pass {{ $backendUrl }};
  {{- end }}
  
  {{- if .cache.enabled }}
  # Cache configuration
  proxy_cache {{ .cache.zone }};
  proxy_cache_key {{ .cache.key | default "$scheme$proxy_host$request_uri" }};
  
  {{- if .cache.validTime }}
  proxy_cache_valid {{ .cache.validTime.default | default "10m" }};
  {{- if .cache.validTime.notFound }}
  proxy_cache_valid 404 {{ .cache.validTime.notFound }};
  {{- end }}
  {{- if .cache.validTime.any }}
  proxy_cache_valid any {{ .cache.validTime.any }};
  {{- end }}
  {{- end }}
  
  {{- if .cache.bypass }}
  proxy_cache_bypass {{ range $i, $cond := .cache.bypass }}{{ if $i }} {{ end }}{{ $cond }}{{ end }};
  {{- end }}
  
  {{- if .cache.noCache }}
  proxy_no_cache {{ range $i, $cond := .cache.noCache }}{{ if $i }} {{ end }}{{ $cond }}{{ end }};
  {{- end }}
  
  {{- if .cache.backgroundUpdate }}
  proxy_cache_background_update {{ .cache.backgroundUpdate }};
  {{- end }}
  
  {{- if .cache.useStale }}
  proxy_cache_use_stale {{ .cache.useStale }};
  {{- end }}
  
  {{- if .cache.lock }}
  proxy_cache_lock {{ .cache.lock }};
  {{- if .cache.lockTimeout }}
  proxy_cache_lock_timeout {{ .cache.lockTimeout }};
  {{- end }}
  {{- end }}
  
  {{- if .cache.revalidate }}
  proxy_cache_revalidate {{ .cache.revalidate }};
  {{- end }}
  
  {{- if .cache.minUses }}
  proxy_cache_min_uses {{ .cache.minUses }};
  {{- end }}
  
  {{- if .cache.addHeader }}
  add_header {{ .cache.headerName | default "X-Cache-Status" }} $upstream_cache_status;
  {{- end }}
  {{- end }}
  # Proxy settings
  {{- $proxySettings := .proxy | default $.Values.cache.proxy }}
  proxy_buffers {{ $proxySettings.buffersNumber | default 1024 }} {{ $proxySettings.bufferSize | default "4k" }};
  proxy_send_timeout {{ $proxySettings.sendTimeout | default "300s" }};
  proxy_read_timeout {{ $proxySettings.readTimeout | default "300s" }};
  proxy_connect_timeout {{ $proxySettings.connectTimeout | default "300s" }};
  
  {{- if .proxy }}
  {{- if .proxy.setHeaders }}
  {{- range .proxy.setHeaders }}
  proxy_set_header {{ . }};
  {{- end }}
  {{- end }}
  {{- end }}
  
  {{- if .additionalConfig -}}
{{ .additionalConfig | nindent 2 }}
  {{- end }}
}
{{- end }}
{{ include "nginx-standard.healthCheckLocations" . }}
{{- if .Values.cache.namedLocations }}
# Named locations
{{- range .Values.cache.namedLocations }}
location @{{ .name }} {
  {{- if .internal }}
  internal;
  {{- end }}
  {{- if .additionalConfig }}
{{ .additionalConfig | nindent 2 }}
  {{- end }}
}
{{- end }}
{{- end }}
{{- end -}}

{{/*
==============================================================================
ELASTIC PROXY USE CASE
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf.elasticProxy" -}}
{{- include "nginx-standard.nginxElasticConf" . }}
{{- end -}}

{{- define "nginx-standard.serverConf.elasticProxy" -}}
{{- include "nginx-standard.serverConfig" . }}
{{- end -}}
{{/* Perl script for Elastic auth */}}
{{- define "nginx-standard.elasticUrlPerlScript" }}
  sub {
    return $ENV{"ELASTICSEARCH_URL"} || "";
  }
{{- end }}
{{/* Perl script for Elastic auth */}}
{{- define "nginx-standard.elasticAuthPerlScript" }}
  sub {
    use MIME::Base64;
    if (exists($ENV{"ELASTIC_READER_USER"}) && exists($ENV{"ELASTIC_READER_PASSWORD"})) {
      return "Basic " . encode_base64($ENV{"ELASTIC_READER_USER"} . ":" . $ENV{"ELASTIC_READER_PASSWORD"}, "");
    }
    return "";
  }
{{- end }}

{{- define "nginx-standard.nginxElasticConf" -}}
env ELASTICSEARCH_URL;
env ELASTIC_READER_PASSWORD;
env ELASTIC_READER_USER;
# Load perl module
load_module modules/ngx_http_perl_module.so;

{{- include "nginx-standard.commonWorkerEvents" . }}

{{- include "nginx-standard.commonHttpBlockStart" . }}
  
  # Perl script to set authorization header
  perl_set $elasticsearch_url '{{ include "nginx-standard.elasticUrlPerlScript" . }}';
  perl_set $elastic_auth '{{ include "nginx-standard.elasticAuthPerlScript" . }}';

  # JSON log format
{{- include "nginx-standard.jsonLogFormat" . | nindent 2 }}
  
  # Upstream configuration
  upstream elasticsearch {
    server {{ .Values.elasticProxy.upstream.url | replace "https://" "" | replace "http://" "" }};
  }
  
{{- include "nginx-standard.commonServerBlockStart" . | nindent 2 }}
    # Include custom server configuration
    include /opt/app-root/etc/nginx.default.d/*.conf;
    
{{- if .Values.observability.metrics.enabled }}
{{- include "nginx-standard.metricsLocation" . | nindent 4 }}
{{- end }}
  }
}
{{- end }}

{{- define "nginx-standard.serverConfig" -}}
# Hardcoded DNS resolver for Kubernetes/OpenShift
resolver dns-default.openshift-dns.svc.cluster.local valid=10s ipv6=off;
client_max_body_size {{ .Values.elasticProxy.clientMaxBodySize | default "50m" }};
{{ include "nginx-standard.healthCheckLocations" . }}
{{- range .Values.elasticProxy.routes }}
location {{ .path }} {
  {{- if .methods }}
  limit_except {{ range .methods }}{{ . }} {{ end }}{
    deny all;
  }
  {{- end }}
  {{- if $.Values.elasticProxy.upstreamAuth.enabled }}
  proxy_set_header Authorization $elastic_auth;
  {{- end }}  
  {{- if .additionalConfig }}
{{ .additionalConfig | nindent 2 }}
  {{- end }}
}
{{- end }}
{{- end }}

{{/*
==============================================================================
FRONT PROXY USE CASE
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf.frontProxy" -}}
# NGINX Front Proxy Mode
# Load Perl module for environment variable access
load_module modules/ngx_http_perl_module.so;
{{- include "nginx-standard.commonWorkerEvents" . }}
{{- if eq (include "nginx-standard.frontProxyEnabled" .) "true" }}
{{- if .Values.frontProxy.env }}
{{- range $key, $val := .Values.frontProxy.env }}
env {{ $key }};
{{- end }}
{{- end }}
{{- if .Values.frontProxy.secretEnv }}
{{- range $key, $val := .Values.frontProxy.secretEnv }}
env {{ $key }};
{{- end }}
{{- end }}
{{- end }}
{{- include "nginx-standard.commonHttpBlockStart" . }}
  # JSON log format
{{- $ctx := dict "Values" .Values "requestIdVar" "$request_id" }}
{{- include "nginx-standard.jsonLogFormat" $ctx | nindent 2 }}
{{- if and .Values.frontProxy.enabled .Values.frontProxy.globalConfig.httpDirectives }}
  # Global HTTP directives
{{ .Values.frontProxy.globalConfig.httpDirectives | nindent 2 }}
{{- end }}
  # Perl set blocks for environment variables
{{- if and .Values.frontProxy.enabled .Values.frontProxy.secretEnv }}
{{- range $key, $val := .Values.frontProxy.secretEnv }}
  perl_set ${{ lower $key }} 'sub { return $ENV{"{{ $key }}"} || ""; }';
{{- end }}
{{- end }}
  {{- if and .Values.frontProxy.env (index .Values.frontProxy.env "HOST_PROXY") }}
  # Perl variable for HOST_PROXY
  perl_set $host_proxy_env 'sub { return $ENV{"HOST_PROXY"} || ""; }';
  {{- end }}
  # Include custom server configuration
  include /opt/app-root/etc/nginx.default.d/*.conf;
}
{{- end }}

{{- define "nginx-standard.serverConf.frontProxy" -}}
{{- if and .Values.frontProxy .Values.frontProxy.enabled }}
# Default server for health checks and catch-all
server {
  listen {{ include "nginx-standard.servicePort" . }} default_server;
  server_name _;
{{- include "nginx-standard.healthCheckLocations" . | nindent 2 }}
{{- if .Values.observability.metrics.enabled }}
{{- include "nginx-standard.metricsLocation" . | nindent 2 }}
{{- end }}
  # Default catch-all
  location / {
    return 404 'Not Found';
  }
}
{{- if .Values.frontProxy.primaryServers }}
# Primary Servers
{{- range .Values.frontProxy.primaryServers }}
server {
  listen {{ include "nginx-standard.servicePort" $ }};
  server_name {{ .serverName }};
  resolver dns-default.openshift-dns.svc.cluster.local valid=30s ipv6=off;
{{- with $.Values.frontProxy.globalConfig.serverDirectives }}
{{- range . }}
  {{ . }};
{{- end }}
{{- end }}
{{- include "nginx-standard.healthCheckLocations" $ | nindent 2 }}
  # Root redirect
  location = / {
    return 301 https://{{ .serverName }}{{ .redirectPath }};
  }
  # Default proxy
  location / {
    proxy_pass $host_proxy_env/;
  }
}
{{- end }}
{{- end }}
{{- if .Values.frontProxy.customServers }}
# Custom Servers
{{- range .Values.frontProxy.customServers }}
server {
  listen {{ include "nginx-standard.servicePort" $ }};
  server_name {{ .serverName }};
{{- with $.Values.frontProxy.globalConfig.serverDirectives }}
{{- range . }}
  {{ . }};
{{- end }}
{{- end }}
{{- include "nginx-standard.healthCheckLocations" $ | nindent 2 }}
{{- range .locations }}
  location {{ .path }} {
{{- if .additionalConfig }}
{{ .additionalConfig | nindent 4 }}
{{- end }}
{{- if .proxyPass }}
    proxy_pass {{ .proxyPass }};
{{- end }}
  }
{{- end }}
}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
==============================================================================
FILE SHARING USE CASE
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf.fileSharing" -}}
{{ include "nginx-standard.nginxMainConf.default" . }}
{{- end -}}

{{- define "nginx-standard.serverConf.fileSharing" -}}
{{- if and .Values.fileSharing .Values.fileSharing.enabled -}}
{{- if .Values.fileSharing.locations -}}
{{- range .Values.fileSharing.locations }}
location {{ .path }} {
{{- if .root }}
  root {{ .root }};
{{- end -}}
{{- if .alias }}
  alias {{ .alias }};
{{- end -}}
{{- if .index }}
  index {{ .index }};
{{- end -}}
{{- if hasKey . "autoindex" }}
  autoindex {{ if .autoindex }}on{{ else }}off{{ end }};
{{- end -}}
{{- if .additionalConfig -}}
{{- .additionalConfig | nindent 2 -}}
{{- end -}}
}
{{- end -}}
{{- else }}
# Default file sharing configuration
location / {
  root /opt/app-root/src;
  autoindex on;
  autoindex_exact_size off;
  autoindex_localtime on;
  index index.html index.htm;
}
{{- end }}
{{ include "nginx-standard.healthCheckLocations" . }}
{{- else }}
# Fallback
location / {
  root /opt/app-root/src;
  autoindex on;
  autoindex_exact_size off;
  autoindex_localtime on;
  index index.html index.htm;
}
{{ include "nginx-standard.healthCheckLocations" . }}
{{- end -}}
{{- end }}

{{/*
==============================================================================
DEFAULT USE CASE
==============================================================================
*/}}

{{- define "nginx-standard.nginxMainConf.default" -}}
# NGINX Default Configuration
{{- include "nginx-standard.commonWorkerEvents" . }}
{{- include "nginx-standard.commonHttpBlockStart" . }}
  # JSON log format
{{- include "nginx-standard.jsonLogFormat" . | nindent 2 }}
{{- include "nginx-standard.commonServerBlockStart" . | nindent 2 }}
    # Include custom server configuration
    include /opt/app-root/etc/nginx.default.d/*.conf;
{{- if .Values.observability.metrics.enabled }}
{{- include "nginx-standard.metricsLocation" . | nindent 4 }}
{{- end }}
  }
}
{{- end }}

{{- define "nginx-standard.serverConf.default" -}}
location / {
  root /usr/share/nginx/html;
  index index.html index.htm;
}
{{- include "nginx-standard.healthCheckLocations" . }}
{{- end }}