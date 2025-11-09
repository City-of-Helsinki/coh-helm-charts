{{/*
Expand the name of the chart.
*/}}
{{- define "redis-sentinel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redis-sentinel.fullname" -}}
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
{{- define "redis-sentinel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis-sentinel.labels" -}}
helm.sh/chart: {{ include "redis-sentinel.chart" . }}
{{ include "redis-sentinel.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis-sentinel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis-sentinel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Redis labels
*/}}
{{- define "redis-sentinel.redis.labels" -}}
{{ include "redis-sentinel.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis selector labels
*/}}
{{- define "redis-sentinel.redis.selectorLabels" -}}
{{ include "redis-sentinel.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Sentinel labels
*/}}
{{- define "redis-sentinel.sentinel.labels" -}}
{{ include "redis-sentinel.labels" . }}
app.kubernetes.io/component: sentinel
{{- end }}

{{/*
Sentinel selector labels
*/}}
{{- define "redis-sentinel.sentinel.selectorLabels" -}}
{{ include "redis-sentinel.selectorLabels" . }}
app.kubernetes.io/component: sentinel
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis-sentinel.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis-sentinel.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the redis password secret
*/}}
{{- define "redis-sentinel.redis.passwordSecret" -}}
{{- if .Values.redis.password.existingSecret }}
{{- .Values.redis.password.existingSecret }}
{{- else }}
{{- include "redis-sentinel.fullname" . }}-secret
{{- end }}
{{- end }}

{{/*
Get the redis password key
*/}}
{{- define "redis-sentinel.redis.passwordKey" -}}
{{- if .Values.redis.password.existingSecret }}
{{- .Values.redis.password.secretKey }}
{{- else }}
{{- "redis-password" }}
{{- end }}
{{- end }}

{{/*
Generate redis configuration
*/}}
{{- define "redis-sentinel.redis.config" -}}
bind {{ .Values.redis.config.bind }}
protected-mode {{ .Values.redis.config.protectedMode }}
port {{ .Values.redis.config.port }}
tcp-backlog 511
timeout {{ .Values.redis.config.timeout }}
tcp-keepalive {{ .Values.redis.config.tcpKeepalive }}
daemonize no
supervised no
pidfile "/var/run/redis_6379.pid"
loglevel {{ .Values.redis.config.loglevel }}
logfile ""
databases {{ .Values.redis.config.databases }}
always-show-logo yes
save ""
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
rdb-del-sync-files no
dir "/data"
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-diskless-load disabled
repl-disable-tcp-nodelay no
replica-priority 100
acllog-max-len 128
maxmemory-policy {{ .Values.redis.config.maxmemoryPolicy }}
{{- range $key, $value := .Values.redis.config.extraConfig }}
{{ $key }} {{ $value }}
{{- end }}
{{- end }}

{{/*
Generate sentinel configuration
*/}}
{{- define "redis-sentinel.sentinel.config" -}}
port {{ .Values.sentinel.config.port }}
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor {{ .Values.sentinel.config.masterName }} {{ include "redis-sentinel.fullname" . }}-0.{{ include "redis-sentinel.fullname" . }}-headless 6379 {{ .Values.sentinel.config.quorum }}
sentinel down-after-milliseconds {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.downAfterMilliseconds }}
sentinel failover-timeout {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.failoverTimeout }}
sentinel parallel-syncs {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.parallelSyncs }}
{{- range $key, $value := .Values.sentinel.config.extraConfig }}
{{ $key }} {{ $value }}
{{- end }}
{{- end }}