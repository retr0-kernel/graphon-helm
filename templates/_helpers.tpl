{{/*
Expand the name of the chart.
*/}}
{{- define "graphon.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "graphon.fullname" -}}
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
{{- define "graphon.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "graphon.labels" -}}
helm.sh/chart: {{ include "graphon.chart" . }}
{{ include "graphon.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "graphon.selectorLabels" -}}
app.kubernetes.io/name: {{ include "graphon.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ── Backend ─────────────────────────────────────────────────────────── */}}

{{- define "graphon.backend.fullname" -}}
{{- printf "%s-backend" (include "graphon.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "graphon.backend.labels" -}}
{{ include "graphon.labels" . }}
app.kubernetes.io/component: backend
{{- end }}

{{- define "graphon.backend.selectorLabels" -}}
{{ include "graphon.selectorLabels" . }}
app.kubernetes.io/component: backend
{{- end }}

{{- define "graphon.backend.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.backend.image.registry -}}
{{- printf "%s/%s:%s" $registry .Values.backend.image.repository .Values.backend.image.tag -}}
{{- end }}

{{/* ── UI ────────────────────────────────────────────────────────────── */}}

{{- define "graphon.ui.fullname" -}}
{{- printf "%s-ui" (include "graphon.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "graphon.ui.labels" -}}
{{ include "graphon.labels" . }}
app.kubernetes.io/component: ui
{{- end }}

{{- define "graphon.ui.selectorLabels" -}}
{{ include "graphon.selectorLabels" . }}
app.kubernetes.io/component: ui
{{- end }}

{{- define "graphon.ui.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.ui.image.registry -}}
{{- printf "%s/%s:%s" $registry .Values.ui.image.repository .Values.ui.image.tag -}}
{{- end }}

{{/* ── Agent ───────────────────────────────────────────────────────────── */}}

{{- define "graphon.agent.fullname" -}}
{{- printf "%s-agent" (include "graphon.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "graphon.agent.labels" -}}
{{ include "graphon.labels" . }}
app.kubernetes.io/component: agent
{{- end }}

{{- define "graphon.agent.selectorLabels" -}}
{{ include "graphon.selectorLabels" . }}
app.kubernetes.io/component: agent
{{- end }}

{{- define "graphon.agent.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.agent.image.registry -}}
{{- printf "%s/%s:%s" $registry .Values.agent.image.repository .Values.agent.image.tag -}}
{{- end }}

{{/* ── Service Account ─────────────────────────────────────────────────── */}}

{{- define "graphon.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "graphon.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* ── Database connection strings ──────────────────────────────────────── */}}

{{/*
PostgreSQL DSN — embedded or external.
*/}}
{{- define "graphon.postgresDSN" -}}
{{- if .Values.postgresql.enabled -}}
  {{- $host := printf "%s-postgresql" (include "graphon.fullname" .) -}}
  {{- $user := .Values.postgresql.auth.username | default "graphon" -}}
  {{- $db   := .Values.postgresql.auth.database | default "graphon" -}}
  {{- printf "postgres://%s:$(POSTGRES_PASSWORD)@%s:5432/%s?sslmode=disable" $user $host $db -}}
{{- else -}}
  {{- $host := .Values.externalPostgresql.host -}}
  {{- $port := .Values.externalPostgresql.port | default 5432 -}}
  {{- $user := .Values.externalPostgresql.username -}}
  {{- $db   := .Values.externalPostgresql.database -}}
  {{- $ssl  := .Values.externalPostgresql.sslMode | default "require" -}}
  {{- printf "postgres://%s:$(POSTGRES_PASSWORD)@%s:%d/%s?sslmode=%s" $user $host (int $port) $db $ssl -}}
{{- end -}}
{{- end }}

{{/*
Neo4j bolt URI — embedded or external.
*/}}
{{- define "graphon.neo4jURI" -}}
{{- if .Values.neo4j.enabled -}}
  {{- printf "bolt://%s:7687" (include "graphon.fullname" .) -}}
{{- else -}}
  {{- .Values.externalNeo4j.boltUrl -}}
{{- end -}}
{{- end }}

{{/*
Name of secret holding POSTGRES_PASSWORD.
*/}}
{{- define "graphon.postgresSecretName" -}}
{{- if .Values.postgresql.enabled -}}
  {{- if .Values.postgresql.auth.existingSecret -}}
    {{- .Values.postgresql.auth.existingSecret -}}
  {{- else -}}
    {{- printf "%s-postgresql" (include "graphon.fullname" .) -}}
  {{- end -}}
{{- else -}}
  {{- if .Values.externalPostgresql.existingSecret -}}
    {{- .Values.externalPostgresql.existingSecret -}}
  {{- else -}}
    {{- printf "%s-external-pg" (include "graphon.fullname" .) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Key for POSTGRES_PASSWORD inside the secret.
*/}}
{{- define "graphon.postgresSecretKey" -}}
{{- if .Values.postgresql.enabled -}}
  {{- if .Values.postgresql.auth.secretKeys -}}
    {{- .Values.postgresql.auth.secretKeys.userPasswordKey | default "password" -}}
  {{- else -}}
    password
  {{- end -}}
{{- else -}}
  {{- .Values.externalPostgresql.existingSecretKey | default "password" -}}
{{- end -}}
{{- end }}

{{/*
Name of secret holding NEO4J_PASSWORD.
*/}}
{{- define "graphon.neo4jSecretName" -}}
{{- if .Values.neo4j.enabled -}}
  {{- printf "%s-neo4j-passwords" (include "graphon.fullname" .) -}}
{{- else -}}
  {{- if .Values.externalNeo4j.existingSecret -}}
    {{- .Values.externalNeo4j.existingSecret -}}
  {{- else -}}
    {{- printf "%s-external-neo4j" (include "graphon.fullname" .) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Key for NEO4J_PASSWORD inside the secret.
*/}}
{{- define "graphon.neo4jSecretKey" -}}
{{- if .Values.neo4j.enabled -}}
  NEO4J_PASSWORD
{{- else -}}
  {{- .Values.externalNeo4j.existingSecretKey | default "password" -}}
{{- end -}}
{{- end }}
