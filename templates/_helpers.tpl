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

{{/*
Name of the Secret that holds the agent API key.
Precedence: existingSecret → generated "<fullname>-agent-creds" (when apiKey is set).
Returns an empty string when neither is configured — caller must guard with {{- if ... }}.
*/}}
{{- define "graphon.agent.secretName" -}}
{{- if .Values.agent.existingSecret -}}
  {{- .Values.agent.existingSecret -}}
{{- else if .Values.agent.apiKey -}}
  {{- printf "%s-agent-creds" (include "graphon.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* ── Service Account ─────────────────────────────────────────────────── */}}

{{- define "graphon.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "graphon.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* ── PostgreSQL ───────────────────────────────────────────────────────── */}}

{{/*
PostgreSQL host.
Embedded: bitnami creates a Service named "<Release.Name>-postgresql".
External:  use externalPostgresql.host.
*/}}
{{- define "graphon.postgresHost" -}}
{{- if .Values.postgresql.enabled -}}
  {{- printf "%s-postgresql" .Release.Name -}}
{{- else -}}
  {{- required "externalPostgresql.host is required when postgresql.enabled=false" .Values.externalPostgresql.host -}}
{{- end -}}
{{- end }}

{{- define "graphon.postgresPort" -}}
{{- if .Values.postgresql.enabled -}}
  5432
{{- else -}}
  {{- .Values.externalPostgresql.port | default 5432 -}}
{{- end -}}
{{- end }}

{{- define "graphon.postgresDB" -}}
{{- if .Values.postgresql.enabled -}}
  {{- .Values.postgresql.auth.database | default "graphon" -}}
{{- else -}}
  {{- .Values.externalPostgresql.database | default "graphon" -}}
{{- end -}}
{{- end }}

{{- define "graphon.postgresUser" -}}
{{- if .Values.postgresql.enabled -}}
  {{- .Values.postgresql.auth.username | default "graphon" -}}
{{- else -}}
  {{- .Values.externalPostgresql.username | default "graphon" -}}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding POSTGRES_PASSWORD.
Embedded: bitnami generates "<Release.Name>-postgresql" with key "password".
Note: we use .Release.Name (not graphon.fullname) because the bitnami subchart
names its own secret from the parent release name, not from our fullname helper.
External:  either existingSecret or the one we create as "<fullname>-external-pg".
*/}}
{{- define "graphon.postgresSecretName" -}}
{{- if .Values.postgresql.enabled -}}
  {{- if .Values.postgresql.auth.existingSecret -}}
    {{- .Values.postgresql.auth.existingSecret -}}
  {{- else -}}
    {{- printf "%s-postgresql" .Release.Name -}}
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
Key inside the postgres secret that contains the password.
Bitnami uses "password" for the application user (auth.username).
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

{{/* ── Neo4j ─────────────────────────────────────────────────────────────── */}}

{{/*
Neo4j bolt URI.
Embedded: the neo4j/neo4j subchart creates a Service named after neo4j.neo4j.name
          (not the parent chart fullname). Default name is "graphon".
External:  use externalNeo4j.boltUrl.
*/}}
{{- define "graphon.neo4jURI" -}}
{{- if .Values.neo4j.enabled -}}
  {{- $svcName := .Values.neo4j.neo4j.name | default "graphon" -}}
  {{- printf "bolt://%s:7687" $svcName -}}
{{- else -}}
  {{- required "externalNeo4j.boltUrl is required when neo4j.enabled=false" .Values.externalNeo4j.boltUrl -}}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding NEO4J_PASSWORD.
Embedded: we create our own "<fullname>-neo4j-creds" secret (see backend/secret.yaml).
          We do NOT reference the neo4j subchart's secret because that chart stores
          the password as "NEO4J_AUTH" (format: "neo4j/<password>"), not as a raw
          password string that the backend can use directly.
External:  either existingSecret or the one we create as "<fullname>-external-neo4j".
*/}}
{{- define "graphon.neo4jSecretName" -}}
{{- if .Values.neo4j.enabled -}}
  {{- printf "%s-neo4j-creds" (include "graphon.fullname" .) -}}
{{- else -}}
  {{- if .Values.externalNeo4j.existingSecret -}}
    {{- .Values.externalNeo4j.existingSecret -}}
  {{- else -}}
    {{- printf "%s-external-neo4j" (include "graphon.fullname" .) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Key inside the neo4j secret.
Our own secrets always use "password" as the key.
*/}}
{{- define "graphon.neo4jSecretKey" -}}
{{- if .Values.neo4j.enabled -}}
  password
{{- else -}}
  {{- .Values.externalNeo4j.existingSecretKey | default "password" -}}
{{- end -}}
{{- end }}
