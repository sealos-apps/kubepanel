{{/* Expand the name of the chart. */}}
{{- define "kubepanel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "kubepanel.fullname" -}}
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

{{- define "kubepanel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "kubepanel.labels" -}}
helm.sh/chart: {{ include "kubepanel.chart" . }}
{{ include "kubepanel.selectorLabels" . }}
{{ include "kubepanel.recommendedLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "kubepanel.selectorLabels" -}}
app: {{ include "kubepanel.fullname" . }}
{{- end }}

{{- define "kubepanel.recommendedLabels" -}}
app.kubernetes.io/name: {{ include "kubepanel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "kubepanel.scheme" -}}
{{- if eq (toString .Values.kubepanelConfig.disableHttps) "true" -}}http{{- else -}}https{{- end -}}
{{- end }}

{{- define "kubepanel.port" -}}
{{- $scheme := include "kubepanel.scheme" . -}}
{{- $port := toString .Values.kubepanelConfig.cloudPort -}}
{{- if eq $scheme "http" -}}
{{- $port = toString .Values.kubepanelConfig.httpPort -}}
{{- end -}}
{{- if or (and (eq $scheme "https") (or (eq $port "") (eq $port "443"))) (and (eq $scheme "http") (or (eq $port "") (eq $port "80"))) -}}
{{- "" -}}
{{- else -}}
{{- $port -}}
{{- end }}
{{- end }}

{{- define "kubepanel.portSuffix" -}}
{{- $port := include "kubepanel.port" . -}}
{{- if $port -}}:{{ $port }}{{- end -}}
{{- end }}

{{- define "kubepanel.portEnv" -}}
{{- $port := include "kubepanel.port" . -}}
{{- if $port -}}:{{ $port }}{{- end -}}
{{- end }}

{{- define "kubepanel.cloudOrigin" -}}
{{- include "kubepanel.scheme" . -}}://{{ .Values.kubepanelConfig.cloudDomain }}{{ include "kubepanel.portSuffix" . }}
{{- end }}

{{- define "kubepanel.wildcardCloudOrigin" -}}
{{- include "kubepanel.scheme" . -}}://*.{{ .Values.kubepanelConfig.cloudDomain }}{{ include "kubepanel.portSuffix" . }}
{{- end }}

{{- define "kubepanel.host" -}}
{{- default (printf "kubepanel.%s" .Values.kubepanelConfig.cloudDomain) .Values.ingress.host -}}
{{- end }}

{{- define "kubepanel.appUrl" -}}
{{- include "kubepanel.scheme" . -}}://{{ include "kubepanel.host" . }}{{ include "kubepanel.portSuffix" . }}
{{- end }}
