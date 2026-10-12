{{/*
Expand the name of the chart.
*/}}
{{- define "varnish-drupal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec). If the release name contains the chart name it will be
used as a full name.
*/}}
{{- define "varnish-drupal.fullname" -}}
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
Main service name — override via values.service.name, falls back to fullname.
*/}}
{{- define "varnish-drupal.serviceName" -}}
{{- if .Values.service.name }}
{{- .Values.service.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "varnish-drupal.fullname" . }}
{{- end }}
{{- end }}

{{/*
Main route name — override via values.route.name, falls back to fullname.
*/}}
{{- define "varnish-drupal.routeName" -}}
{{- if .Values.route.name }}
{{- .Values.route.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "varnish-drupal.fullname" . }}
{{- end }}
{{- end }}

{{/*
Create chart label.
*/}}
{{- define "varnish-drupal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "varnish-drupal.labels" -}}
helm.sh/chart: {{ include "varnish-drupal.chart" . }}
{{ include "varnish-drupal.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "varnish-drupal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "varnish-drupal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Headless service name — used in both service.yaml and statefulset.yaml args.
*/}}
{{- define "varnish-drupal.headlessServiceName" -}}
{{- if .Values.service.headlessName }}
{{- .Values.service.headlessName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-headless" (include "varnish-drupal.serviceName" .) }}
{{- end }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "varnish-drupal.configMapName" -}}
{{- printf "%s-config" (include "varnish-drupal.fullname" .) }}
{{- end }}

{{- define "varnish-drupal.serviceAccountName" -}}
{{- .Values.serviceAccountName | default "kube-httpcache-sa" }}
{{- end }}

{{/*
Backend watch — automatically true when director.mode is "multi".
*/}}
{{- define "varnish-drupal.backendWatch" -}}
{{- if eq .Values.vcl.director.mode "multi" }}true{{- else }}false{{- end }}
{{- end }}

{{/*
Validate incompatible vcl flag combination.
*/}}
{{- define "varnish-drupal.validateVcl" -}}
{{- if and .Values.vcl.rootRedirect.enabled (not .Values.vcl.rootRedirect.target) }}
{{- fail "vcl.rootRedirect.target must be set when vcl.rootRedirect.enabled is true" }}
{{- end }}
{{- end }}

{{/*
Varnish image reference. No registry hostnames are hard-coded here.
  image.registry   -> optional, falls back to global.imageRegistry
  image.repository -> required. Legacy values that still include the registry host
                      (e.g. "container-registry.platta-net.hel.fi/devops-toolchain/x") are
                      detected and used as-is, so global.imageRegistry is not prepended twice.
  image.digest     -> optional, wins over tag
*/}}
{{- define "varnish-drupal.image" -}}
{{- $img := .Values.image -}}
{{- $global := .Values.global | default dict -}}
{{- $repo := required "image.repository is required" $img.repository -}}
{{- $registry := $img.registry | default $global.imageRegistry | default "" | trimSuffix "/" -}}
{{- /* Backwards compatibility: repository already starts with a registry host (contains "." or ":" before first "/") */ -}}
{{- $first := first (splitList "/" $repo) -}}
{{- if and (not $img.registry) (or (contains "." $first) (contains ":" $first)) (gt (len (splitList "/" $repo)) 1) -}}
{{- $registry = "" -}}
{{- end -}}
{{- $ref := ternary (printf "%s/%s" $registry $repo) $repo (ne $registry "") -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $ref $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (toString (required "image.tag is required" $img.tag)) -}}
{{- end -}}
{{- end -}}

{{/*
imagePullSecrets = global.imagePullSecrets + imagePullSecrets (deduplicated)
*/}}
{{- define "varnish-drupal.imagePullSecrets" -}}
{{- $out := list -}}
{{- range (concat ((.Values.global).imagePullSecrets | default list) (.Values.imagePullSecrets | default list)) -}}
{{- $out = append $out (ternary (dict "name" .) . (kindIs "string" .)) -}}
{{- end -}}
{{- $out = uniq $out -}}
{{- if $out -}}
imagePullSecrets:
{{ toYaml $out | indent 2 }}
{{- end -}}
{{- end -}}

{{/*
Pod scheduling - the same contract in every coh chart:
  nodeSelector  map of node labels        (default {} = any node)
  tolerations   list of tolerations       (default [])
  affinity      Kubernetes affinity map   (default {})
Empty chart values fall back to global.nodeSelector / global.tolerations / global.affinity,
so a platform pipeline can set a default per region or cluster.
varnish-drupal extra: with no affinity set, a soft pod anti-affinity spreads the replicas
over nodes (podAntiAffinity.enabled, default true).
Legacy: nodeSelector may also be a plain string (old West Europe form), rendered as
<nodeSelectorKey>: <value> (key default "env").
*/}}
{{- define "varnish-drupal.scheduling" -}}
{{- $v := .Values -}}
{{- $g := $v.global | default dict -}}
{{- $ns := $v.nodeSelector -}}
{{- if and $ns (not (kindIs "map" $ns)) -}}
{{- $ns = dict ($v.nodeSelectorKey | default "env") ($ns | toString) -}}
{{- end -}}
{{- $ns = $ns | default $g.nodeSelector -}}
{{- $tol := $v.tolerations | default $g.tolerations -}}
{{- $aff := $v.affinity | default $g.affinity -}}
{{- /* built-in soft anti-affinity: spread the Varnish replicas over nodes */ -}}
{{- $pa := $v.podAntiAffinity | default dict -}}
{{- if and (not $aff) (or (not (hasKey $pa "enabled")) $pa.enabled) -}}
{{- $sel := include "varnish-drupal.selectorLabels" . | fromYaml -}}
{{- $aff = dict "podAntiAffinity" (dict "preferredDuringSchedulingIgnoredDuringExecution" (list (dict "weight" 100 "podAffinityTerm" (dict "topologyKey" "kubernetes.io/hostname" "labelSelector" (dict "matchLabels" $sel))))) -}}
{{- end -}}
{{- with $ns }}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $tol }}
tolerations:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with $aff }}
affinity:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end -}}
