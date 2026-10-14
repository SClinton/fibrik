#!/usr/bin/env bash
# End-to-end check for the week-1 data path (initial-stack.md §9, day 3):
# syslog -> fibrik-otelcol -> Vector -> ClickHouse (hot) + Iceberg (lake).
# Sends N RFC 5424 lines from a pod, then polls fibrik-api until both stores
# hold at least N more rows than before.
set -euo pipefail

KUBECTL=${KUBECTL:-kubectl}
NAMESPACE=${NAMESPACE:-fibrik}
RELEASE=${RELEASE:-fibrik}
LINES=${LINES:-5}
TIMEOUT=${TIMEOUT:-180}
CURL_IMAGE=${CURL_IMAGE:-curlimages/curl:8.23.0}
NC_IMAGE=${NC_IMAGE:-busybox:1.38.0}

k() { "$KUBECTL" -n "$NAMESPACE" "$@"; }
api="http://$RELEASE-api:8001/v1/pipeline/stats"
otel="$RELEASE-otelcol"

run_pod() {  # run_pod NAME IMAGE SCRIPT
  k delete pod "$1" --ignore-not-found --wait=true >/dev/null
  k run "$1" --restart=Never --image="$2" --command -- sh -c "$3" >/dev/null
  k wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$1" --timeout=120s >/dev/null
  k logs "$1"
  k delete pod "$1" --wait=false >/dev/null
}

stats() { run_pod e2e-stats "$CURL_IMAGE" "curl -fsS $api"; }
field() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['$1']['raw_logs'])" "$2"; }

before=$(stats)
echo "before: $before"
ch0=$(field clickhouse "$before"); lake0=$(field lake "$before")

lines=""
for i in $(seq 1 "$LINES"); do
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  lines+="<38>1 $ts e2e-host sshd $i E2E - e2e test line $i\n"
done
run_pod e2e-send "$NC_IMAGE" "printf '$lines' | nc -w 3 $otel 5140; echo sent $LINES lines"

deadline=$((SECONDS + TIMEOUT))
while :; do
  now=$(stats)
  ch=$(field clickhouse "$now"); lake=$(field lake "$now")
  echo "clickhouse=$ch (+$((ch - ch0))) lake=$lake (+$((lake - lake0)))"
  if (( ch - ch0 >= LINES && lake - lake0 >= LINES )); then
    echo "e2e passed: $LINES events reached ClickHouse and Iceberg"
    exit 0
  fi
  if (( SECONDS > deadline )); then
    echo "e2e failed: events did not arrive within ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 5
done
