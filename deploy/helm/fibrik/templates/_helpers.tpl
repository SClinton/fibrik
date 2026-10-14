{{/* Common names and labels. */}}

{{- define "fibrik.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Name of one component, e.g. "fibrik-postgres". Call with (list $ "postgres"). */}}
{{- define "fibrik.component" -}}
{{- $root := index . 0 -}}
{{- printf "%s-%s" (include "fibrik.fullname" $root) (index . 1) -}}
{{- end -}}

{{- define "fibrik.labels" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: {{ index . 1 }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/part-of: fibrik
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $root.Chart.Name $root.Chart.Version }}
{{- end -}}

{{- define "fibrik.selectorLabels" -}}
{{- $root := index . 0 -}}
app.kubernetes.io/name: {{ index . 1 }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
{{- end -}}

{{- define "fibrik.image" -}}
{{- printf "%s:%s" .repository .tag -}}
{{- end -}}

{{- define "fibrik.credentialsSecret" -}}
{{- default (include "fibrik.component" (list . "credentials")) .Values.credentials.existingSecret -}}
{{- end -}}

{{/*
Credential values, generated once per release. Existing values are read back
from the cluster so upgrades keep them. The result is cached on .Values so
every template in one render sees the same values.
*/}}
{{- define "fibrik.credentials" -}}
{{- if not (hasKey .Values "_credentials") -}}
{{- $keys := list "postgres-password" "lakekeeper-db-password" "lakekeeper-encryption-key" "dex-db-password" "dex-client-secret" "clickhouse-password" "s3-access-key-id" "s3-secret-access-key" -}}
{{- $existing := (lookup "v1" "Secret" .Release.Namespace (include "fibrik.credentialsSecret" .)).data | default dict -}}
{{- $out := dict -}}
{{- range $keys -}}
{{- if hasKey $existing . -}}
{{- $_ := set $out . (index $existing . | b64dec) -}}
{{- else -}}
{{- $_ := set $out . (randAlphaNum 32) -}}
{{- end -}}
{{- end -}}
{{- $_ := set .Values "_credentials" $out -}}
{{- end -}}
{{- toYaml .Values._credentials -}}
{{- end -}}

{{/* An env var read from the credentials Secret. Call with (list $ "ENV_NAME" "secret-key"). */}}
{{- define "fibrik.secretEnv" -}}
{{- $root := index . 0 -}}
- name: {{ index . 1 }}
  valueFrom:
    secretKeyRef:
      name: {{ include "fibrik.credentialsSecret" $root }}
      key: {{ index . 2 }}
{{- end -}}

{{/* Init container that waits until Postgres accepts connections. */}}
{{- define "fibrik.waitForPostgres" -}}
- name: wait-for-postgres
  image: {{ include "fibrik.image" .Values.postgres.image }}
  command: ["sh", "-c", "until pg_isready -h {{ include "fibrik.component" (list . "postgres") }} -p 5432; do echo waiting for postgres; sleep 2; done"]
  resources:
    requests: { cpu: 10m, memory: 16Mi }
    limits: { memory: 64Mi }
{{- end -}}

{{- define "fibrik.pvc" -}}
{{- $root := index . 0 -}}
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    {{- with $root.Values.global.storageClass }}
    storageClassName: {{ . }}
    {{- end }}
    resources:
      requests:
        storage: {{ index . 1 }}
{{- end -}}

{{- define "fibrik.lakekeeperEnv" -}}
{{- $pg := include "fibrik.component" (list . "postgres") -}}
{{ include "fibrik.secretEnv" (list . "LAKEKEEPER_DB_PASSWORD" "lakekeeper-db-password") }}
{{ include "fibrik.secretEnv" (list . "LAKEKEEPER__PG_ENCRYPTION_KEY" "lakekeeper-encryption-key") }}
- name: LAKEKEEPER__PG_DATABASE_URL_READ
  value: postgresql://lakekeeper:$(LAKEKEEPER_DB_PASSWORD)@{{ $pg }}:5432/lakekeeper
- name: LAKEKEEPER__PG_DATABASE_URL_WRITE
  value: postgresql://lakekeeper:$(LAKEKEEPER_DB_PASSWORD)@{{ $pg }}:5432/lakekeeper
- name: LAKEKEEPER__BASE_URI
  value: http://{{ include "fibrik.component" (list . "lakekeeper") }}:8181
{{- end -}}

{{/* Image of a Fibrik-built component, e.g. (list $ "fibrik-api"). */}}
{{- define "fibrik.ownImage" -}}
{{- $root := index . 0 -}}
{{- printf "%s/%s:%s" $root.Values.images.registry (index . 1) (default $root.Chart.AppVersion $root.Values.images.tag) -}}
{{- end -}}

{{/* S3 endpoint from the storage profile. */}}
{{- define "fibrik.storageEndpoint" -}}
{{- if .Values.storage.endpoint -}}
{{- .Values.storage.endpoint -}}
{{- else if .Values.seaweedfs.enabled -}}
{{- printf "http://%s:8333" (include "fibrik.component" (list . "seaweedfs")) -}}
{{- end -}}
{{- end -}}

{{/* Env vars holding the S3 credentials, under the given names. Call with (list $ "ID_VAR" "SECRET_VAR"). */}}
{{- define "fibrik.storageCredentialEnv" -}}
{{- $root := index . 0 -}}
{{- if $root.Values.seaweedfs.enabled -}}
{{ include "fibrik.secretEnv" (list $root (index . 1) "s3-access-key-id") }}
{{ include "fibrik.secretEnv" (list $root (index . 2) "s3-secret-access-key") }}
{{- else -}}
- name: {{ index . 1 }}
  valueFrom:
    secretKeyRef:
      name: {{ required "storage.existingSecret is required when seaweedfs is disabled" $root.Values.storage.existingSecret }}
      key: access-key-id
- name: {{ index . 2 }}
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.storage.existingSecret }}
      key: secret-access-key
{{- end -}}
{{- end -}}

{{/* Settings for fibrik-api and its migrate job (fibrik/settings.py). */}}
{{- define "fibrik.apiEnv" -}}
{{- $lk := include "fibrik.component" (list . "lakekeeper") -}}
- name: FIBRIK_CLICKHOUSE_URL
  value: http://{{ include "fibrik.component" (list . "clickhouse") }}:8123
- name: FIBRIK_CLICKHOUSE_USER
  value: {{ .Values.clickhouse.user | quote }}
- name: FIBRIK_CLICKHOUSE_DATABASE
  value: {{ .Values.clickhouse.database | quote }}
- name: FIBRIK_HOT_TTL_DAYS
  value: {{ .Values.clickhouse.hotTtlDays | quote }}
{{ include "fibrik.secretEnv" (list . "FIBRIK_CLICKHOUSE_PASSWORD" "clickhouse-password") }}
- name: FIBRIK_CATALOG_URI
  value: http://{{ $lk }}:8181/catalog
- name: FIBRIK_CATALOG_MANAGEMENT_URI
  value: http://{{ $lk }}:8181/management
- name: FIBRIK_AUTH_ENABLED
  value: {{ .Values.dex.enabled | quote }}
- name: FIBRIK_OIDC_ISSUER
  value: {{ printf "%s/dex" .Values.global.publicUrl | quote }}
- name: FIBRIK_OIDC_AUDIENCE
  value: {{ .Values.dex.clientId | quote }}
- name: FIBRIK_OIDC_JWKS_URL
  value: http://{{ include "fibrik.component" (list . "dex") }}:5556/dex/keys
- name: FIBRIK_LAKE_WRITER_INTERVAL_SECONDS
  value: {{ .Values.api.lakeWriterIntervalSeconds | quote }}
- name: FIBRIK_STORAGE_TYPE
  value: {{ .Values.storage.type | quote }}
- name: FIBRIK_STORAGE_BUCKET
  value: {{ .Values.storage.bucket | quote }}
- name: FIBRIK_STORAGE_ENDPOINT
  value: {{ include "fibrik.storageEndpoint" . | quote }}
- name: FIBRIK_STORAGE_REGION
  value: {{ .Values.storage.region | quote }}
- name: FIBRIK_STORAGE_PATH_STYLE
  value: {{ .Values.storage.pathStyle | quote }}
{{ include "fibrik.storageCredentialEnv" (list . "FIBRIK_STORAGE_ACCESS_KEY_ID" "FIBRIK_STORAGE_SECRET_ACCESS_KEY") }}
{{- end -}}
