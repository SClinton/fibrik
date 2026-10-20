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
{{- $keys := list "postgres-password" "lakekeeper-db-password" "lakekeeper-encryption-key" "dex-db-password" "dex-client-secret" "clickhouse-password" "objectstore-access-key" "objectstore-secret-key" -}}
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

{{/*
Standard AWS-style env vars for the in-cluster S3-compatible object store,
reused by anything that writes/reads it (the Lakekeeper warehouse bootstrap
job, Vector's aws_s3 sink, the lake writer).
*/}}
{{- define "fibrik.objectstoreEnv" -}}
{{ include "fibrik.secretEnv" (list . "AWS_ACCESS_KEY_ID" "objectstore-access-key") }}
{{ include "fibrik.secretEnv" (list . "AWS_SECRET_ACCESS_KEY" "objectstore-secret-key") }}
- name: AWS_REGION
  value: us-east-1
- name: FIBRIK_OBJECTSTORE_ENDPOINT
  value: http://{{ include "fibrik.component" (list . "objectstore") }}:8333
- name: FIBRIK_LAKE_BUCKET
  value: {{ .Values.objectstore.lakeBucket | quote }}
{{- end -}}
