{{- define "notes-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notes-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "notes-stack.name" . -}}
{{- end -}}
{{- end -}}

{{- define "notes-stack.labels" -}}
app.kubernetes.io/name: {{ include "notes-stack.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "notes-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notes-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
