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
{{- if .Values.labels }}
{{- if .Values.labels.common }}
{{- range $key, $value := .Values.labels.common }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
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
{{- if .Values.labels }}
{{- if .Values.labels.redis }}
{{- range $key, $value := .Values.labels.redis }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
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
{{- if .Values.labels }}
{{- if .Values.labels.sentinel }}
{{- range $key, $value := .Values.labels.sentinel }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}
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
Get the Redis image
*/}}
{{- define "redis-sentinel.redis.image" -}}
registry.redhat.io/rhel9/redis-7@sha256:3d31c0cfaf4219f5bd1c52882b603215d1cb4aaef5b8d1a128d0174e090f96f3
{{- end }}

{{/*
Get the Sentinel image
*/}}
{{- define "redis-sentinel.sentinel.image" -}}
registry.redhat.io/rhel9/redis-7@sha256:3d31c0cfaf4219f5bd1c52882b603215d1cb4aaef5b8d1a128d0174e090f96f3
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
{{- $bind := "0.0.0.0" }}
{{- $protectedMode := "yes" }}
{{- $port := 6379 }}
{{- $timeout := 0 }}
{{- $tcpKeepalive := 300 }}
{{- $loglevel := "notice" }}
{{- $databases := 16 }}
{{- $maxmemoryPolicy := "allkeys-lru" }}
{{- if .Values.redis }}
{{- if .Values.redis.config }}
{{- $bind = .Values.redis.config.bind | default $bind }}
{{- $protectedMode = .Values.redis.config.protectedMode | default $protectedMode }}
{{- $port = .Values.redis.config.port | default $port }}
{{- $timeout = .Values.redis.config.timeout | default $timeout }}
{{- $tcpKeepalive = .Values.redis.config.tcpKeepalive | default $tcpKeepalive }}
{{- $loglevel = .Values.redis.config.loglevel | default $loglevel }}
{{- $databases = .Values.redis.config.databases | default $databases }}
{{- $maxmemoryPolicy = .Values.redis.config.maxmemoryPolicy | default $maxmemoryPolicy }}
{{- end -}}
{{- end -}}
bind {{ $bind }}
protected-mode {{ $protectedMode }}
port {{ $port }}
tcp-backlog 511
timeout {{ $timeout }}
tcp-keepalive {{ $tcpKeepalive }}
daemonize no
supervised no
pidfile "/var/run/redis_6379.pid"
loglevel {{ $loglevel }}
logfile ""
databases {{ $databases }}
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
maxmemory-policy {{ $maxmemoryPolicy }}
{{- if .Values.redis }}
{{- if .Values.redis.config }}
{{- if .Values.redis.config.extraConfig }}
{{- range $key, $value := .Values.redis.config.extraConfig }}
{{ $key }} {{ $value }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate sentinel configuration
*/}}
{{- define "redis-sentinel.sentinel.config" -}}
{{- $port := 5000 }}
{{- $masterName := "mymaster" }}
{{- $quorum := 2 }}
{{- $downAfterMilliseconds := 1000 }}
{{- $failoverTimeout := 10000 }}
{{- $parallelSyncs := 1 }}
{{- if .Values.sentinel }}
{{- if .Values.sentinel.config }}
{{- $port = .Values.sentinel.config.port | default $port }}
{{- $masterName = .Values.sentinel.config.masterName | default $masterName }}
{{- $quorum = .Values.sentinel.config.quorum | default $quorum }}
{{- $downAfterMilliseconds = .Values.sentinel.config.downAfterMilliseconds | default $downAfterMilliseconds }}
{{- $failoverTimeout = .Values.sentinel.config.failoverTimeout | default $failoverTimeout }}
{{- $parallelSyncs = .Values.sentinel.config.parallelSyncs | default $parallelSyncs }}
{{- end -}}
{{- end -}}
port {{ $port }}
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor {{ $masterName }} {{ include "redis-sentinel.fullname" . }}-0.{{ include "redis-sentinel.fullname" . }}-headless 6379 {{ $quorum }}
sentinel down-after-milliseconds {{ $masterName }} {{ $downAfterMilliseconds }}
sentinel failover-timeout {{ $masterName }} {{ $failoverTimeout }}
sentinel parallel-syncs {{ $masterName }} {{ $parallelSyncs }}
{{- if .Values.sentinel }}
{{- if .Values.sentinel.config }}
{{- if .Values.sentinel.config.extraConfig }}
{{- range $key, $value := .Values.sentinel.config.extraConfig }}
{{ $key }} {{ $value }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}