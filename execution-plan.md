# Execution Plan: from concept to a running OSDF

- Status: Draft v0.1
- Date: 2026-10-14
- Inputs: [`requirements.md`](requirements.md), [`architecture.md`](architecture.md)

This plan gets you from an empty repository to a **running MVP on one machine**
(see requirements §8), and then to a **production pilot**. It follows a
**walking skeleton** approach: first get one event flowing end to end through
the real components, then widen each stage. Agents come *after* the
deterministic foundations they depend on (tests, compilers, validators). An
agent is only as good as the checks that verify its output.

---

## 0. Recommended approach in one page

1. **Week 1: decide and bootstrap.** Answer the open questions in requirements §10,
   create the monorepo, CI and the Compose stack skeleton.
2. **Weeks 1–3: data-plane skeleton.** Syslog → Vector → Kafka → Vector worker →
   ClickHouse + Iceberg, queryable through Trino. No UI. No AI.
3. **Weeks 3–5: content model and CLI.** OSDF YAML → rendered Vector config,
   `osdf validate|test|deploy`, 3 source packs to OCSF, DLQ, and Grafana health.
4. **Weeks 5–7: detections.** Sigma → ClickHouse SQL, scheduled runner, alerts
   table + webhook, detection CI with test fixtures, and 10+ rules.
5. **Weeks 7–10: agents.** LLM gateway, MCP server, eval harness, then
   search → onboarding → detection → triage agents (in that order), all
   producing PRs or annotations.
6. **Weeks 10–14: control plane and fleet.** API + RBAC, OpAMP fleet/sidecar,
   minimal UI (alert queue, sources, proposals), replay, and drift detection.
7. **Weeks 14–20: pilot hardening.** Helm/Kubernetes, load testing, security
   review, federated search, correlation, and packs. Then run a real pilot
   alongside an existing SIEM.

**Team assumption:** 3–5 engineers (one data/infra, one or two backend/Python,
one detection engineer, one ML/agent engineer, plus a part-time frontend
engineer). With 1–2 people, roughly double the timeline and drop the UI.

**Build in the open:** use Apache-2.0, with public issues, ADRs in
`docs/adr/`, and a content repo that is separate from the code repo.

---

## 1. Phase 0: Decisions and bootstrap (week 1)

### 1.1 Decisions to lock (record each as an ADR)
| Decision | Recommended default |
|---|---|
| Single- or multi-tenant in v1 | Put `tenant_id` everywhere from day one; implement one tenant |
| LLM policy | Develop with any API model; keep local models (vLLM/Ollama) working through LiteLLM; PII masking on egress |
| First SIEM deploy target | Whatever the pilot SOC runs (Splunk or Sentinel) |
| Object store | SeaweedFS for local; cloud S3 in pilot |
| Git host for content PRs | Gitea in Compose; GitHub/GitLab in pilot |

### 1.2 Repositories

```
osdf/                           # code (Apache-2.0)
  cmd/fleet-manager/            # Go – OpAMP server
  cmd/osdf-sidecar/             # Go – OpAMP client + Vector supervisor
  osdf/                         # Python package (uv-managed)
    api/                        # FastAPI control plane
    cli/                        # `osdf` CLI (Typer)
    content/                    # pydantic models for OSDF YAML (Pipeline, Route, Pack, Detection, Blueprint)
    render/vector/              # OSDF YAML → Vector config renderer
    ocsf/                       # schema loader, validator, mapping DSL → VRL
    detect/                     # pySigma glue, custom backends, runner, correlator
    search/                     # engine router, federated adapters
    health/                     # silence/volume/drift monitors
    lake/                       # Iceberg writer (MVP), table mgmt, compaction jobs
    agents/                     # onboarding, detection, triage, search, tuning, drift
    mcp_server/                 # MCP tools
    workflows/                  # Temporal workflows/activities (blueprints, replay)
  ui/                           # React + TS (Phase 5)
  deploy/compose/               # docker-compose.yml + configs
  deploy/helm/                  # Phase 6
  evals/                        # golden datasets + scorers
  testdata/                     # sample logs (OTRF Security-Datasets, synthetic)
  docs/adr/

osdf-content/                   # content (GitOps source of truth)
  packs/<pack>/{pack.yaml, routes/, pipelines/, vrl/, mappings/, tests/, detections/}
  detections/<domain>/*.yml
  blueprints/*.yaml
  environments/{dev,prod}/{worker-groups.yaml, destinations.yaml, variables.yaml}
```

### 1.3 Tooling
- Python 3.12+, `uv`, `ruff`, `mypy`, `pytest`. Go 1.23+. Node 22 LTS for the UI.
- `pre-commit`, GitHub/Gitea Actions CI: lint → unit tests → `osdf validate/test`
  on the content repo → build images → Trivy scan → cosign sign.
- `Makefile` targets: `make up`, `make down`, `make seed`, `make test`,
  `make e2e`, `make eval`.

**Exit criteria:** both repos exist, CI is green on an empty skeleton, the ADRs are merged,
and `make up` starts an empty Compose stack.

---

## 2. Phase 1: Data-plane walking skeleton (weeks 1–3)

**Goal:** one syslog line sent with `logger` shows up as an OCSF row in ClickHouse
and in an Iceberg table that Trino can query.

### 2.1 Compose stack (starting point)

> Template only: pin image tags to current releases and verify each service's
> env/config against its docs. This file has not been run as-is.

```yaml
# deploy/compose/docker-compose.yml
name: osdf
services:
  kafka:
    image: apache/kafka:3.9.1            # KRaft single-node
    ports: ["9092:9092"]
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  seaweedfs:                              # S3-compatible object store
    image: chrislusf/seaweedfs:latest     # pin
    command: server -s3 -dir=/data
    ports: ["8333:8333"]
    volumes: [seaweed:/data]

  postgres:
    image: postgres:17
    environment: { POSTGRES_PASSWORD: osdf, POSTGRES_USER: osdf, POSTGRES_DB: osdf }
    volumes: [pg:/var/lib/postgresql/data]

  lakekeeper:                             # Iceberg REST catalog
    image: quay.io/lakekeeper/catalog:latest   # pin
    command: ["serve"]
    environment:
      LAKEKEEPER__PG_DATABASE_URL_READ: postgresql://osdf:osdf@postgres:5432/osdf
      LAKEKEEPER__PG_DATABASE_URL_WRITE: postgresql://osdf:osdf@postgres:5432/osdf
      LAKEKEEPER__PG_ENCRYPTION_KEY: change-me
    ports: ["8181:8181"]
    depends_on: [postgres]                # run its `migrate` once first (see Makefile)

  clickhouse:
    image: clickhouse/clickhouse-server:25.8   # pin
    ports: ["8123:8123", "9000:9000"]
    volumes: [ch:/var/lib/clickhouse, ./clickhouse/init:/docker-entrypoint-initdb.d]

  trino:
    image: trinodb/trino:latest           # pin
    ports: ["8080:8080"]
    volumes: [./trino/catalog:/etc/trino/catalog]   # iceberg.properties, clickhouse.properties

  vector-collector:
    image: timberio/vector:latest-debian  # pin
    volumes: [./vector/collector.yaml:/etc/vector/vector.yaml:ro]
    ports: ["5514:5514/udp", "5514:5514/tcp", "8088:8088"]
    depends_on: [kafka]

  vector-worker:
    image: timberio/vector:latest-debian  # pin
    volumes: [./vector/worker:/etc/vector:ro]
    command: ["--config-dir", "/etc/vector", "--watch-config"]
    depends_on: [kafka, clickhouse]

  lake-writer:                            # MVP: python + pyiceberg micro-batch
    build: ../../                         # osdf image
    command: ["osdf", "lake", "write", "--topics", "ocsf\\..*", "--batch-seconds", "60"]
    depends_on: [kafka, lakekeeper, seaweedfs]

  grafana:
    image: grafana/grafana:latest         # pin
    ports: ["3000:3000"]
    volumes: [./grafana/provisioning:/etc/grafana/provisioning]

volumes: { seaweed: {}, pg: {}, ch: {} }
```

Added in later phases: `temporal` (+ UI), `litellm`, `ollama` (optional),
`langfuse`, `gitea`, `keycloak`, `osdf-api`, `osdf-agents`, `osdf-mcp`,
`fleet-manager`, `prometheus`.

### 2.2 Hand-written Vector configs (these get generated in Phase 2)

```yaml
# vector/collector.yaml
sources:
  syslog_in: { type: syslog, address: "0.0.0.0:5514", mode: udp }
  http_in:   { type: http_server, address: "0.0.0.0:8088", decoding: { codec: json } }
transforms:
  envelope:
    type: remap
    inputs: [syslog_in, http_in]
    source: |
      .osdf.tenant_id = "default"
      .osdf.source_id = if exists(.appname) { "linux-" + string!(.appname) } else { "http" }
      .osdf.received_at = now()
sinks:
  raw_kafka:
    type: kafka
    inputs: [envelope]
    bootstrap_servers: kafka:9092
    topic: "raw.default.{{ osdf.source_id }}"
    encoding: { codec: json }
  raw_archive:
    type: aws_s3
    inputs: [envelope]
    endpoint: http://seaweedfs:8333
    bucket: osdf-lake
    key_prefix: "bronze/default/{{ osdf.source_id }}/%Y/%m/%d/%H/"
    compression: gzip
    encoding: { codec: json }
    framing: { method: newline_delimited }
```

```yaml
# vector/worker/sshd.yaml
sources:
  raw: { type: kafka, bootstrap_servers: kafka:9092, group_id: wg-default,
         topics: ["^raw\\.default\\..*"], decoding: { codec: json } }
transforms:
  sshd_ocsf:
    type: remap
    inputs: [raw]
    drop_on_error: true
    reroute_dropped: true          # → sshd_ocsf.dropped → DLQ
    source: |
      m = parse_regex!(.message, r'^(?P<result>Accepted|Failed) (?P<method>\S+) for (invalid user )?(?P<user>\S+) from (?P<ip>\S+) port (?P<port>\d+)')
      . = {
        "class_uid": 3002, "category_uid": 3, "activity_id": 1,
        "time": to_unix_timestamp(timestamp!(.timestamp), unit: "milliseconds"),
        "status_id": if m.result == "Accepted" { 1 } else { 2 },
        "user": { "name": m.user },
        "src_endpoint": { "ip": m.ip, "port": to_int!(m.port) },
        "auth_protocol": m.method,
        "metadata": { "product": { "name": "sshd", "vendor_name": "OpenBSD" }, "version": "1.3.0" },
        "osdf": .osdf, "raw_data": .message
      }
sinks:
  hot:
    type: clickhouse
    inputs: [sshd_ocsf]
    endpoint: http://clickhouse:8123
    database: osdf
    table: ocsf_authentication
    skip_unknown_fields: true
  gold_kafka:
    type: kafka
    inputs: [sshd_ocsf]
    bootstrap_servers: kafka:9092
    topic: ocsf.default.authentication
    encoding: { codec: json }
  dlq:
    type: kafka
    inputs: [sshd_ocsf.dropped]
    bootstrap_servers: kafka:9092
    topic: dlq.default
    encoding: { codec: json }
```

### 2.3 Tasks
1. Write the Compose stack, a `make up`, and init scripts (Kafka topics, ClickHouse DDL,
   the Lakekeeper warehouse, the S3 bucket, Trino catalogs).
2. Write ClickHouse DDL for `ocsf_authentication`, `ocsf_process_activity`, `ocsf_api_activity`
   (store the full event as a JSON column, and promote hot fields to typed columns),
   plus `dlq`, `source_stats`, `signals` and `alerts`.
3. Build the MVP lake writer (`osdf lake write`): consume `ocsf.*`, micro-batch to
   Arrow, write with pyiceberg to `gold.ocsf_<class>`. Plan to replace it with the
   Iceberg Kafka Connect sink in Phase 6.
4. Add a test-data loader, `make seed`. It replays OTRF Security-Datasets and
   synthetic sshd/CloudTrail/Windows events at a configurable EPS.
5. Write an E2E test (`make e2e`): send N events, then assert N rows in ClickHouse,
   and N rows in Iceberg via Trino within 2 minutes.

**Exit criteria:** `make up && make seed && make e2e` passes. Trino runs
`SELECT count(*) FROM iceberg.gold.ocsf_authentication` successfully. You can show
a DLQ entry for a malformed line.

---

## 3. Phase 2: Content model, renderer, CLI and health (weeks 3–5)

**Goal:** stop hand-writing Vector config. Content lives in Git, and the CLI
tests and deploys it.

### Tasks
1. **Pydantic models** for `Pipeline`, `Route`, `Source`, `Destination`, `Pack`
   (architecture §5.3). Generate JSON Schema from them, for editor support and
   for agent output validation.
2. **OCSF module.** Load the OCSF schema (pin a version), and validate events with
   `osdf ocsf validate`. Build a **mapping DSL** (YAML `target: source-expr`) that
   compiles to VRL, so LLMs write mappings rather than raw VRL.
3. **Vector renderer:** content → one Vector config per worker group, including
   `[[tests]]` blocks generated from pack fixtures.
4. **CLI:**
   - `osdf validate`: schema + references + VRL compile (`vector validate`)
   - `osdf test`: `vector test` + OCSF validation of outputs + golden diffs
   - `osdf preview <pipeline> --sample file`: before/after diff and size reduction
   - `osdf deploy --env dev`: render, write to the worker config dir, and let Vector `--watch-config` reload. OpAMP comes in Phase 5
5. **Three packs:** `linux-sshd`, `windows-security` (4624/4625/4688/4720…),
   and `aws-cloudtrail`, each with ≥ 10 fixtures and expected OCSF output.
6. **Health v1:** a Vector `internal_metrics` → Prometheus → Grafana
   dashboard (events in/out per source, drop %, DLQ rate). A ClickHouse
   `source_stats` table fed by a scheduled job. A **silent-source** alert.
7. **Reduction demo:** a `windows-security` route that sends full data to the
   lake and a reduced version to the `splunk` destination (a stub HTTP sink in
   dev). Show the % reduction in Grafana.

**Exit criteria:** changing a mapping in `osdf-content`, then running `osdf test`,
`osdf deploy` and re-seeding, changes the output, with no hand edits. A broken
mapping fails CI. Grafana shows volume and reduction.

---

## 4. Phase 3: Detections (weeks 5–7)

**Goal:** detection-as-code that runs on the hot store, with CI.

### Tasks
1. **pySigma integration.** Add OCSF field-mapping pipelines (Sigma taxonomy →
   OCSF fields) for the three packs. Evaluate any existing community ClickHouse
   backend. If it is missing or weak, write `osdf.detect.backends.clickhouse`,
   starting with selection/condition/modifiers (`contains`, `startswith`,
   `endswith`, `re`, `cidr`, `all`) and failing loudly on anything else.
2. **`x-osdf` extension** model + validation (architecture §6.1).
3. **Rule CI:** `osdf detect test` loads positive/negative fixtures into an
   ephemeral ClickHouse (testcontainers), runs the compiled SQL, and asserts
   hits and misses. This runs in content-repo CI.
4. **Runner:** a scheduled loop (APScheduler for now; it moves to Temporal in
   Phase 4) with watermarks, lateness overlap and dedup keys. It writes to
   `signals` / `alerts`, and posts alerts to a webhook (DFIR-IRIS or a generic one).
5. **Content:** import 10–20 SigmaHQ rules that match the three packs, plus
   Atomic Red Team–style fixtures. Write 2 correlation rules (brute force then
   success; console login from a new country then IAM change).
6. **Backtest:** `osdf detect backtest <rule> --days 7` via Trino on Iceberg.
7. **Coverage v0:** `osdf detect coverage` outputs an ATT&CK Navigator layer
   JSON from the rule tags. Load it in the ATT&CK Navigator.

**Exit criteria:** 10+ rules pass CI and run every 5 minutes. Seeded attack data
produces the expected alerts, and benign data produces none. The webhook receives
alerts. A backtest works.

---

## 5. Phase 4: Agent foundation and first agents (weeks 7–10)

**Goal:** the four P0 agents work end to end, with evals and safety checks.

### 5.1 Foundation (week 7)
1. Add **LiteLLM** to Compose with ≥ 2 models configured (one API model, one local
   model through Ollama/vLLM). Turn on budget limits and a PII-masking egress hook.
2. **Langfuse** for tracing. Wrap every agent run in a trace ID that is stored
   with its proposal or annotation.
3. **OSDF MCP server** (Python MCP SDK) with read tools first: `get_schema`,
   `list_sources`, `source_health`, `search` (read-only ClickHouse/Trino,
   time-range required, row/byte limits), `get_alert`, `similar_alerts`,
   `coverage_for_technique`, `ocsf_class_lookup`. Then validation tools:
   `test_pipeline`, `validate_ocsf`, `compile_rule`, `test_rule`, `backtest_rule`.
   Then one write tool: `propose_change(files, title, body)`, which creates a
   branch and PR in Gitea/GitHub.
4. **Validator sandbox:** a container with `vector`, `osdf`, and no network. Tools
   that run generated artifacts call it.
5. **Temporal:** move the detection runner and replay jobs to it, and add the
   generic blueprint workflow.
6. **Eval harness:** the `evals/` layout, scorers, and `make eval` with a
   summary table per agent per model. Gate on regressions in CI.

### 5.2 Agents, in build order
| Order | Agent | Why this order | Done when |
|---|---|---|---|
| 1 | **Search agent** | Simplest. It exercises MCP, schema retrieval and guardrails | ≥ 70% execution accuracy on 50 NL→SQL eval pairs |
| 2 | **Onboarding agent** | Highest value (Databahn Cruz / Anvilogic onboard). It depends on Phase 2 validators | For 5 held-out log types it opens PRs whose tests pass on the first try ≥ 60% of the time |
| 3 | **Detection engineering agent** | Depends on the Phase 3 compiler and tests | Given 10 ATT&CK techniques/CTI snippets, ≥ 70% of PRs compile, pass tests and have a sane backtest volume |
| 4 | **Triage agent** | Needs alerts, search tools and context | On a labeled set of ≥ 200 alerts: precision on "benign" ≥ 90%, malicious recall ≥ 95%. Every verdict cites event IDs |

Agent design pattern (all agents):
`plan → gather (tools) → draft → verify (deterministic tools) → repair loop (≤ N) → package (artifacts + evidence + confidence) → propose`.
If verification fails after N repairs, the agent opens a **draft** PR labeled
`needs-human` with the failure report. It never fails silently.

### 5.3 Minimal analyst loop
- A small page (or Grafana panel + webhook) that lists alerts with the triage
  verdict, a summary, evidence links, and **agree/disagree** buttons that write
  to a `feedback` table. Feedback becomes both eval data and tuning-agent input.

**Exit criteria:** MVP items 4–8 from requirements §8 are demonstrated live.
`make eval` publishes a scorecard. An external MCP client (for example, Claude
Code or Claude Desktop) can connect to the OSDF MCP server and run a search.

---

## 6. Phase 5: Control plane, fleet, UI, replay and drift (weeks 10–14)

### Tasks
1. **osdf-api** (FastAPI): sources, destinations, worker groups, deployments,
   proposals, alerts, agent runs, audit log. Keycloak OIDC, plus OPA for RBAC and
   agent autonomy policies.
2. **Fleet:** a Go `fleet-manager` (OpAMP server) and `osdf-sidecar` (OpAMP client,
   wrapping Vector). The sidecar downloads the signed config bundle, runs
   `vector validate`, does an atomic swap with health-check rollback, and
   reports heartbeat/version. Rollout is canary first, then the whole group.
3. **Edge agent packaging:** sidecar + Vector for Linux (deb/rpm) and Windows
   (MSI), enrolled with a token, buffering to disk.
4. **UI v1** (React): source inventory + health, alert queue + triage view,
   proposals (diff, checks, approve → merges the PR), detection catalog +
   ATT&CK heatmap, and copilot chat (MCP-backed).
5. **Replay** (architecture §5.5) as a Temporal workflow + CLI + UI button.
6. **Schema registry and drift:** a job that profiles samples per source (field
   set, types, parse rate, unmapped ratio) hourly, stores versions, and
   triggers the **drift remediation agent** blueprint when thresholds are crossed.
7. **Pipeline optimization agent** using a `field_usage` table, which is
   populated by parsing compiled detection SQL and saved searches for
   referenced fields.

**Exit criteria:** a fresh Linux VM enrolls as an edge node and receives config
from the UI. Approving an agent PR in the UI deploys it to the workers with no CLI.
A deliberate format change in seeded data triggers a drift PR.

---

## 7. Phase 6: Pilot hardening (weeks 14–20)

### Tasks
1. **Helm umbrella chart:** Strimzi, the ClickHouse operator, CloudNativePG,
   Temporal, Trino, Lakekeeper, OSDF services, and HPA on Kafka consumer lag
   (KEDA).
2. **Swap the MVP lake writer** for the Iceberg Kafka Connect sink. Add
   compaction and snapshot-expiry jobs.
3. **Performance testing:** use k6 or a custom generator to find EPS per vCPU
   for each pack, and ClickHouse query p95 at 100 GB/day and 1 TB/day. Publish a
   sizing guide. Check against NFR-PERF.
4. **Federated search adapters:** Splunk and Sentinel first (or whichever the
   pilot runs), then Snowflake/Databricks.
5. **SIEM deployers:** push compiled SPL/KQL detections to the pilot SIEM, and
   reconcile their state.
6. **Correlation v2:** OSDF risk-based correlation. Use Flink only if
   streaming stateful correlation turns out to be necessary.
7. **Guard:** a PII/secret rule pack (Presidio-derived regex + checks) with
   tests, applied before SIEM and LLM egress.
8. **Security:** threat model (STRIDE + OWASP LLM/Agentic Top 10), pen test of
   the MCP server and agents (prompt injection through log fields, tool abuse,
   cross-tenant access), cosign/SBOM, secrets in OpenBao, and mTLS everywhere.
9. **Docs:** quickstart, pack authoring guide, detection authoring guide, agent
   autonomy guide, and runbooks.

### Pilot (run side by side, 4–6 weeks)
- Mirror 3–5 real sources (through Kafka tee or SIEM forwarding) into OSDF
  while the SIEM stays primary.
- Measure: volume reduction to the SIEM, detection parity, onboarding time with the
  agent, triage agreement rate versus analysts, and cost per GB.
- Go/no-go review against the success metrics in requirements §9.

---

## 8. Day-one checklist (the first commands)

```bash
# 1. repos
mkdir osdf && cd osdf && git init && uv init --package osdf
mkdir -p deploy/compose/{vector/worker,clickhouse/init,trino/catalog,grafana/provisioning} \
         osdf/{content,render/vector,ocsf,detect,lake,cli} testdata evals docs/adr

# 2. core deps
uv add typer pydantic pyyaml jinja2 confluent-kafka clickhouse-connect pyiceberg[pyarrow] \
       trino pysigma httpx
uv add --dev pytest ruff mypy testcontainers

# 3. bring up the skeleton (after writing compose + configs from §2)
make up                     # docker compose up -d + init jobs
logger -n 127.0.0.1 -P 5514 -d "Failed password for root from 203.0.113.7 port 51234 ssh2"
curl -s 'http://localhost:8123/?query=SELECT+count()+FROM+osdf.ocsf_authentication'
```

## 9. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| LLM-generated parsers and rules are wrong in subtle ways | Bad data / missed detections | Deterministic tests are mandatory. Fixtures come from real samples. Use shadow mode before production. Eval gates in CI |
| Prompt injection through log content | Agent misuse, data exfiltration | No shell or network for agents, typed tools only, PR-only writes, OPA, egress masking, red-team tests in Phase 6 |
| Sigma backend gaps for ClickHouse/Trino | Rules can't compile | Own the backend. Fail loudly. Allow raw-SQL rules as an escape hatch |
| License changes in dependencies | Forced migration | Abstractions (OSDF YAML over Vector, S3 API, Iceberg, MCP). License check in CI (`osv`/`scancode`) |
| Operational complexity (many services) | Slow adoption | Single-node appliance mode, a one-command Compose setup, and Helm with sane defaults. Keep Flink and Trino optional for small installs (DuckDB fallback) |
| Scope creep toward a full SIEM/SOAR | Never ship | Non-goals in requirements §2. Integrate with DFIR-IRIS/Shuffle/existing SIEM |
| Triage autonomy erodes analyst trust | Rejection | Start at L0/L1. Show evidence. Track the agreement rate publicly. Only allow auto-close above measured precision |
| Vendor feature claims we benchmark against are unverified | Wrong targets | Set targets from our own pilot measurements, not vendor marketing |

## 10. Milestone summary

| Milestone | Week | Demo |
|---|---|---|
| M0 Bootstrap | 1 | `make up` on empty stack, CI green |
| M1 Skeleton | 3 | syslog → OCSF in ClickHouse + Iceberg; Trino query |
| M2 Content | 5 | GitOps packs, `osdf test/deploy`, Grafana health, reduction % |
| M3 Detect | 7 | 10+ Sigma rules in CI, alerts to webhook, backtest, ATT&CK layer |
| **M4 MVP** | 10 | Search, onboarding, detection and triage agents + MCP + eval scorecard |
| M5 Platform | 14 | UI, fleet/OpAMP, replay, drift agent, optimization agent |
| M6 Pilot-ready | 20 | Helm, perf-tested, security reviewed, federated search, SIEM deploy |
