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
{{- printf "%s-headless" (include "varnish-drupal.fullname" .) }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "varnish-drupal.configMapName" -}}
{{- printf "%s-config" (include "varnish-drupal.fullname" .) }}
{{- end }}

{{/*
Validate incompatible vcl flag combination.
*/}}
{{- define "varnish-drupal.validateVcl" -}}
{{- if and (eq .Values.vcl.director.mode "multi") .Values.vcl.healthEndpoint.enabled }}
{{- fail "vcl.healthEndpoint.enabled must be false when vcl.director.mode is \"multi\" (health synth is handled by the multi-director VCL path)" }}
{{- end }}
{{- if and .Values.vcl.rootRedirect.enabled (not .Values.vcl.rootRedirect.target) }}
{{- fail "vcl.rootRedirect.target must be set when vcl.rootRedirect.enabled is true" }}
{{- end }}
{{- end }}
