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
Conditional NGINX main configuration
*/}}
{{- define "nginx-standard.nginxConf" -}}
{{- if eq .Values.nginx.useCase "elastic-proxy" -}}
worker_processes auto;
error_log /dev/stderr {{ .Values.nginx.logging.errorLevel | default "notice" }};
pid /tmp/nginx.pid;

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

    # Log in JSON Format (using simplified structure aligned with the default, but required for elastic)
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
      '"request_id": "$nginx_req_id" }';
      
    access_log /dev/stdout nginxlog_json;

    sendfile on;
    keepalive_timeout 65;

    # Include custom server block (server.conf)
    include /opt/app-root/etc/nginx.default.d/*.conf; 
}
{{- end -}}
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
{{- .Values.nginx.service.port | default 8080 -}}
{{- end -}}

{{/*
Get service name
*/}}
{{- define "nginx-standard.serviceName" -}}
{{- .Values.nginx.service.name | default "http" -}}
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
{{- end -}}
{{- end -}}


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
    client_max_body_size {{ .Values.elasticProxy.clientMaxBodySize | default "50m" }};

{{- range .Values.elasticProxy.routes }}
    location {{ .path }} {
        {{- $methods := join " " .methods }}
        {{- if $methods }}
        limit_except {{ $methods }} {
          deny all;
        }
        {{- end }}
        
        # NGINX Proxy Settings (from values.yaml)
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

        # Elastic Authentication Header (via Perl module)
        proxy_set_header Authorization "Basic $elastic_authorization";

        # Proxy Pass to Elasticsearch URL
        proxy_pass ${ELASTICSEARCH_URL};
        proxy_ssl_verify off;
        proxy_redirect off;
        proxy_pass_header Authorization;
        
        # CORS Headers for search endpoints (check if path contains search/msearch)
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

    # Standard health check endpoints for the dedicated server block (Always needed)
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
{{- else -}}
# Default configuration
location / {
  return 404;
}
{{- end -}}
{{- end -}}