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
Get the Redis image
*/}}
{{- define "redis-sentinel.redis.image" -}}
{{- if .Values.redis.image -}}
{{- .Values.redis.image -}}
{{- else -}}
registry.redhat.io/rhel9/redis-7@sha256:3d31c0cfaf4219f5bd1c52882b603215d1cb4aaef5b8d1a128d0174e090f96f3
{{- end -}}
{{- end }}

{{/*
Get the Sentinel image
*/}}
{{- define "redis-sentinel.sentinel.image" -}}
{{- if .Values.sentinel.image -}}
{{- .Values.sentinel.image -}}
{{- else -}}
registry.redhat.io/rhel9/redis-7@sha256:3d31c0cfaf4219f5bd1c52882b603215d1cb4aaef5b8d1a128d0174e090f96f3
{{- end -}}
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
Generate Redis configuration with auto-merge (extraConfig wins)
*/}}
{{- define "redis-sentinel.redis.config" -}}
{{- $baseConfig := dict 
  "bind" (.Values.redis.config.bind | default "0.0.0.0")
  "protected-mode" (.Values.redis.config.protectedMode | default "yes")
  "port" (.Values.redis.config.port | default "6379")
  "timeout" (.Values.redis.config.timeout | default "500")
  "tcp-keepalive" (.Values.redis.config.tcpKeepalive | default "300")
  "tcp-backlog" (.Values.redis.config.tcpBacklog | default "511")
  
  "requirepass" (.Values.redis.config.requirepass | default "")
  
  "daemonize" (.Values.redis.config.daemonize | default "no")
  "supervised" (.Values.redis.config.supervised | default "no")
  "pidfile" (.Values.redis.config.pidfile | default "/var/run/redis_6379.pid")
  
  "loglevel" (.Values.redis.config.loglevel | default "notice")
  "logfile" (.Values.redis.config.logfile | default "")
  
  "databases" (.Values.redis.config.databases | default "16")
  
  "maxmemory" (.Values.redis.config.maxmemory | default "900mb")
  "maxmemory-policy" (.Values.redis.config.maxmemoryPolicy | default "allkeys-lru")
  
  "save" (.Values.redis.config.save | default "")
  "appendonly" (.Values.redis.config.appendonly | default "no")
  "stop-writes-on-bgsave-error" (.Values.redis.config.stopWritesOnBgsaveError | default "no")
  "rdbcompression" (.Values.redis.config.rdbcompression | default "yes")
  "rdbchecksum" (.Values.redis.config.rdbchecksum | default "yes")
  "rdb-del-sync-files" (.Values.redis.config.rdbDelSyncFiles | default "no")
  
  "replica-serve-stale-data" (.Values.redis.config.replicaServeStaleData | default "yes")
  "replica-read-only" (.Values.redis.config.replicaReadOnly | default "yes")
  "repl-diskless-sync" (.Values.redis.config.replDisklessSync | default "no")
  "repl-diskless-sync-delay" (.Values.redis.config.replDisklessSyncDelay | default "5")
  "repl-diskless-load" (.Values.redis.config.replDisklessLoad | default "disabled")
  "repl-disable-tcp-nodelay" (.Values.redis.config.replDisableTcpNodelay | default "no")
  "replica-priority" (.Values.redis.config.replicaPriority | default "100")
  
  "acllog-max-len" (.Values.redis.config.acllogMaxLen | default "128")
  
  "always-show-logo" (.Values.redis.config.alwaysShowLogo | default "yes")
  "dir" (.Values.redis.config.dir | default "/data")
-}}

{{- $finalConfig := $baseConfig -}}

{{- if .Values.redis.extraConfig }}
  {{- range $key, $value := .Values.redis.extraConfig }}
    {{- if not (empty $value) }}
      {{- $finalConfig = set $finalConfig $key $value }}
    {{- end }}
  {{- end }}
{{- end }}

{{- range $key, $value := $finalConfig }}
{{- if not (empty $value) }}
{{ $key }} {{ $value }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate Sentinel configuration with auto-merge (extraConfig wins)
*/}}
{{- define "redis-sentinel.sentinel.config" -}}
{{- $masterName := .Values.sentinel.config.masterName | default "mymaster" -}}
{{- $redisMaster := (include "redis-sentinel.fullname" .) -}}
{{- $redisPort := .Values.redis.config.port | default 6379 | int -}}
{{- $redisMasterWithPort := printf "%s-0.%s-headless %d" $redisMaster $redisMaster $redisPort -}}
{{- $quorum := .Values.sentinel.config.quorum | default 2 | int -}}
{{- $downAfterMs := .Values.sentinel.config.downAfterMilliseconds | default 5000 | int -}}
{{- $failoverTimeout := .Values.sentinel.config.failoverTimeout | default 10000 | int -}}
{{- $parallelSyncs := .Values.sentinel.config.parallelSyncs | default 1 | int -}}

{{- $baseConfig := dict 
  "port" (.Values.sentinel.config.port | default 26379 | int)
  "sentinel resolve-hostnames" (.Values.sentinel.config.resolveHostnames | default "yes")
  "sentinel announce-hostnames" (.Values.sentinel.config.announceHostnames | default "yes")
-}}

{{- $baseConfig = set $baseConfig "sentinel monitor" (printf "%s %s %d" $masterName $redisMasterWithPort $quorum) -}}
{{- $baseConfig = set $baseConfig "sentinel down-after-milliseconds" (printf "%s %d" $masterName $downAfterMs) -}}
{{- $baseConfig = set $baseConfig "sentinel failover-timeout" (printf "%s %d" $masterName $failoverTimeout) -}}
{{- $baseConfig = set $baseConfig "sentinel parallel-syncs" (printf "%s %d" $masterName $parallelSyncs) -}}

{{- $finalConfig := $baseConfig -}}

{{- if .Values.sentinel.extraConfig }}
  {{- range $key, $value := .Values.sentinel.extraConfig }}
    {{- if not (empty $value) }}
      {{- $finalConfig = set $finalConfig $key $value }}
    {{- end }}
  {{- end }}
{{- end }}

{{- range $key, $value := $finalConfig }}
{{- if not (empty $value) }}
{{ $key }} {{ $value }}
{{- end }}
{{- end }}
{{- end }}