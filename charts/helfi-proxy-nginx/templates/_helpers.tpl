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
Pod scheduling - the same contract in every coh chart:
  nodeSelector  map of node labels        (default {} = any node)
  tolerations   list of tolerations       (default [])
  affinity      Kubernetes affinity map   (default {})
Empty chart values fall back to global.nodeSelector / global.tolerations / global.affinity,
so a platform pipeline can set a default per region or cluster.
Legacy: nodeSelector may also be a plain string (old West Europe form), rendered as
<nodeSelectorKey>: <value> (key default "env").
*/}}
{{- define "helfi-proxy-nginx.scheduling" -}}
{{- $v := .Values -}}
{{- $g := $v.global | default dict -}}
{{- $ns := $v.nodeSelector -}}
{{- if and $ns (not (kindIs "map" $ns)) -}}
{{- $ns = dict ($v.nodeSelectorKey | default "env") ($ns | toString) -}}
{{- end -}}
{{- $ns = $ns | default $g.nodeSelector -}}
{{- $tol := $v.tolerations | default $g.tolerations -}}
{{- $aff := $v.affinity | default $g.affinity -}}
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
