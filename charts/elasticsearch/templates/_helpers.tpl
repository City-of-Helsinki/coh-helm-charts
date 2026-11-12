{{/*
Expand the name of the chart.
*/}}
{{- define "elasticsearch.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of the Elasticsearch resource. ECK derives the object names from it
(<name>-es-http, <name>-es-default-0, ...) and allows at most 36 characters.
*/}}
{{- define "elasticsearch.fullname" -}}
{{- $name := .Chart.Name }}
{{- $full := ternary .Release.Name (printf "%s-%s" .Release.Name $name) (contains $name .Release.Name) }}
{{- if gt (len $full) 36 }}
{{- fail (printf "Elasticsearch name %q is longer than 36 characters (ECK limit): use a shorter release name" $full) }}
{{- end }}
{{- $full }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "elasticsearch.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels. app.kubernetes.io/version is the Elasticsearch version actually deployed.
*/}}
{{- define "elasticsearch.labels" -}}
helm.sh/chart: {{ include "elasticsearch.chart" . }}
{{ include "elasticsearch.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "elasticsearch.selectorLabels" -}}
app.kubernetes.io/name: {{ include "elasticsearch.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service ECK creates for the HTTP API (port 9200).
*/}}
{{- define "elasticsearch.httpServiceName" -}}
{{- include "elasticsearch.fullname" . }}-es-http
{{- end }}

{{/*
Platta managed Service TLS: the OpenShift service CA creates this Secret for the
<name>-es-http Service (serving-cert annotation) and ECK serves HTTP with it.
Single source for both places, so they can never differ.
*/}}
{{- define "elasticsearch.httpTlsSecretName" -}}
platta-{{ include "elasticsearch.fullname" . }}-es-http-tls
{{- end }}

{{/*
Image: <registry>/<repository>:<version>, resolved like nginx-standard.imageRef:
  - image.registry  -> optional; falls back to global.imageRegistry
  - image.repository -> required
The tag is always .Values.version (no image.tag / image.digest). values.schema.json only
allows the official Elastic image (Platta mirror or docker.elastic.co), never a custom image.
*/}}
{{- define "elasticsearch.image" -}}
{{- $img := .Values.image -}}
{{- $global := .Values.global | default dict -}}
{{- $registry := $img.registry | default $global.imageRegistry | default "" | trimSuffix "/" -}}
{{- $repo := required "image.repository is required" $img.repository -}}
{{- $ref := ternary (printf "%s/%s" $registry $repo) $repo (ne $registry "") -}}
{{- printf "%s:%s" $ref .Values.version -}}
{{- end }}

{{/*
imagePullSecrets from global.imagePullSecrets (deduplicated), same as the other coh charts.
Accepts entries as {name: x} maps or plain strings.
*/}}
{{- define "elasticsearch.imagePullSecrets" -}}
{{- $out := list -}}
{{- range ((.Values.global).imagePullSecrets | default list) -}}
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
Empty chart values fall back to global.nodeSelector / global.tolerations / global.affinity.
No affinity rendered = ECK's default soft pod anti-affinity applies.
*/}}
{{- define "elasticsearch.scheduling" -}}
{{- $v := .Values -}}
{{- $g := $v.global | default dict -}}
{{- with ($v.nodeSelector | default $g.nodeSelector) }}
nodeSelector:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with ($v.tolerations | default $g.tolerations) }}
tolerations:
{{ toYaml . | indent 2 }}
{{- end }}
{{- with ($v.affinity | default $g.affinity) }}
affinity:
{{ toYaml . | indent 2 }}
{{- end }}
{{- end -}}

{{/*
Application users (ECK file realm).
*/}}

{{/*
Secret (and Password / ExternalSecret) name of a user. Argument: the user's name.
*/}}
{{- define "elasticsearch.userSecretName" -}}
elasticsearch-user-{{ . }}
{{- end }}

{{/*
Elasticsearch role of a user: <name>-<role>. Argument: the user entry.
*/}}
{{- define "elasticsearch.userRoleName" -}}
{{- printf "%s-%s" .name .role }}
{{- end }}

{{/*
Labels of the Password and ExternalSecret objects and of the generated Secrets.
Stable on purpose (no chart version, no Elasticsearch version): External Secrets re-syncs an
ExternalSecret whenever its labels, annotations or spec change, and with a generator every
re-sync is a new password. Version labels here would rotate every password on each upgrade.
*/}}
{{- define "elasticsearch.userLabels" -}}
{{ include "elasticsearch.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: user
{{- end }}

{{/*
Validated users list: fails on duplicate names (the schema cannot check uniqueness of a field).
*/}}
{{- define "elasticsearch.users" -}}
{{- $seen := dict -}}
{{- range .Values.users -}}
{{- if hasKey $seen .name -}}
{{- fail (printf "users: name %q is listed more than once" .name) -}}
{{- end -}}
{{- $_ := set $seen .name true -}}
{{- end -}}
{{- toJson (.Values.users | default list) -}}
{{- end }}
