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
{{- if .Values.global.project }}
app.kubernetes.io/project: {{ .Values.global.project }}
{{- end }}
{{- if .Values.global.environment }}
app.kubernetes.io/environment: {{ .Values.global.environment }}
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
{{ .additionalConfig | indent 2 }}
{{- end -}}
}
{{ end -}}
{{- else if eq .Values.nginx.useCase "elastic-proxy" -}}
{{- range .Values.elasticProxy.routes -}}
location {{ .path }} {
{{- $methods := join " " .methods }}
{{- if $methods }}
  limit_except {{ $methods }} {
    deny all;
  }
{{- end }}
  proxy_pass {{ $.Values.elasticProxy.upstream.protocol }}://{{ $.Values.elasticProxy.upstream.service }}:{{ $.Values.elasticProxy.upstream.port }};
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
{{- if .additionalConfig }}
{{ .additionalConfig | indent 2 }}
{{- end }}
}

{{- end -}}
{{- else -}}
# Default configuration
location / {
  return 404;
}
{{- end -}}
{{- end -}}