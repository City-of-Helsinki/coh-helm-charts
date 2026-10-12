{{/*
Expand the name of the chart.
*/}}
{{- define "helfi-proxy-nginx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "helfi-proxy-nginx.fullname" -}}
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
Common labels
*/}}
{{- define "helfi-proxy-nginx.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "helfi-proxy-nginx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: {{ .Values.type }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "helfi-proxy-nginx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "helfi-proxy-nginx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full image reference
*/}}
{{- define "helfi-proxy-nginx.image" -}}
{{- $img := .Values.image -}}
{{- $global := .Values.global | default dict -}}
{{- $registry := $img.registry | default $global.imageRegistry | default "" | trimSuffix "/" -}}
{{- $repo := required "image.repository is required" $img.repository -}}
{{- $ref := ternary (printf "%s/%s" $registry $repo) $repo (ne $registry "") -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $ref $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (toString (required "image.tag is required" $img.tag)) -}}
{{- end -}}
{{- end }}

{{/*
imagePullSecrets = global.imagePullSecrets + imagePullSecrets (deduplicated)
*/}}
{{- define "helfi-proxy-nginx.imagePullSecrets" -}}
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
nodeSelector: map -> used as-is; non-empty string -> { <nodeSelectorKey>: <value> }; empty -> none
*/}}
{{- define "helfi-proxy-nginx.nodeSelector" -}}
{{- $ns := .Values.nodeSelector -}}
{{- if and (kindIs "map" $ns) $ns -}}
nodeSelector:
{{ toYaml $ns | indent 2 }}
{{- else if and (not (kindIs "map" $ns)) $ns -}}
nodeSelector:
  {{ .Values.nodeSelectorKey | default "env" }}: {{ $ns | toString | quote }}
{{- end -}}
{{- end -}}
