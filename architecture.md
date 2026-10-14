# Architecture: OpenSOC Data Fabric (OSDF)

- Status: Draft v0.1
- Date: 2026-10-14
- Requirements: [`requirements.md`](requirements.md) (IDs such as `FR-PIP-01` are referenced below)

---

## 1. Architectural principles

0. **Cost is the primary design driver** (requirements G0). Every component
   choice and default is judged by cost per GB moved, stored and searched,
   and by engineer hours saved. Savings must be metered, not estimated
   (§5.7). The runtime transformation path is deterministic and CPU-bound;
   **LLMs are never called per event** (NFR-COST-03).
1. **Assemble, don't reinvent.** Use proven open source engines for the
   heavy parts (stream transport, transforms, storage, query, workflow).
   OSDF's own code is the **control plane, the content model, the
   detection compiler glue, and the agents**. Commercial vendors differentiate
   in these areas too.
2. **Control plane and data plane are separate** (the Cribl leader/worker model).
   The data plane runs on its last known good config when the control plane is down.
3. **Git is the source of truth** for all content: pipelines, routes, parsers,
   OCSF mappings, detections, packs and blueprints. The UI, CLI and agents all
   write *proposals* (branches/PRs). A deploy happens only from a merged commit.
4. **Open formats at rest.** OCSF events in Iceberg/Parquet on object storage.
   Any engine can read the lake, and there is no lock-in.
5. **Storage-agnostic detections** (the Anvilogic model). Sigma is the source,
   compiled per backend. OSDF can run detections itself or push them to a SIEM.
6. **Agents propose, deterministic checks verify, humans approve.** LLM output
   never reaches production without passing compilers, schema validators
   and tests.
7. **Log data is untrusted input.** Anything derived from events and given to
   an LLM is treated as possible prompt injection (see §8.4).
8. **Agentic-native by design** (secondary use case, requirements GA). Every
   capability is exposed as **MCP tools** designed for agents, and SOC
   procedures ship as **Agent Skills**. External agents are first-class
   consumers alongside OSDF's own agents, and they share the same identity,
   policy, budget and audit controls. The OSDF UI and CLI use the same API
   underneath, so agents and humans see one platform (§8.6–§8.11).

---

## 2. System context

```mermaid
flowchart LR
  subgraph Sources
    S1[Syslog / Firewalls]
    S2[Endpoints - edge agent]
    S3[Cloud & SaaS APIs]
    S4[Kafka / OTLP / HTTP]
  end

  subgraph OSDF
    CP[Control Plane]
    DP[Data Plane - collectors + pipeline workers]
    LK[(Lake - Iceberg on S3)]
    HOT[(Hot store - ClickHouse)]
    DET[Detection Engine]
    AG[Agent Runtime]
    MCP[MCP Gateway]
  end

  subgraph External
    SIEM[Splunk / Sentinel / Elastic]
    DL[Snowflake / Databricks]
    SOAR[SOAR / Case mgmt]
    TI[MISP / OpenCTI]
    LLM[LLMs - local or API]
    GIT[Git - Gitea/GitHub/GitLab]
  end

  Sources --> DP
  DP --> LK & HOT
  DP --> SIEM
  DET --> HOT & LK
  DET -. deploy compiled rules .-> SIEM
  DET --> SOAR
  AG <--> MCP
  MCP <--> CP & HOT & LK & DET
  AG --> LLM
  AG -. federated search .-> SIEM & DL
  CP <--> GIT
  CP --> DP
  TI --> DP & DET
```

---

## 3. Logical architecture (planes and modules)

```mermaid
flowchart TB
  subgraph ControlPlane[Control Plane]
    API[osdf-api - REST/gRPC, RBAC, audit]
    CFG[Config service - Git sync, render, validate]
    FLEET[Fleet manager - OpAMP server]
    REG[Schema registry + Source catalog]
    CNT[Content service - packs, armory]
    SCHED[Workflow engine - Temporal]
    GRAPH[(Postgres + AGE graph + pgvector)]
  end

  subgraph DataPlane[Data Plane]
    EDGE[Edge agents - Vector / OTel Collector]
    COL[Collector tier - Vector sources]
    BUS[(Kafka)]
    WRK[Pipeline workers - Vector transforms VRL]
    LW[Lake writer - Iceberg Kafka Connect sink]
    SIDE[osdf-sidecar - OpAMP client, config pull, health]
  end

  subgraph Storage
    OBJ[(S3-compatible object store)]
    ICE[(Iceberg REST catalog - Lakekeeper)]
    CH[(ClickHouse)]
  end

  subgraph Analytics
    TRINO[Trino - federated SQL]
    DETX[Detection runner]
    CORR[Correlator]
    HEALTH[Health & drift monitor]
  end

  subgraph AI[Agent Layer]
    ORCH[Agent runtime - LangGraph in Temporal activities]
    MCPS[MCP gateway + domain MCP servers]
    SKL[Skills registry - SKILL.md in Git]
    GW[LLM gateway - LiteLLM]
    EVAL[Eval harness + Langfuse tracing]
    VAL[Validator sandbox]
  end

  EDGE --> COL --> BUS --> WRK --> BUS
  BUS --> LW --> OBJ
  WRK --> CH
  COL -- raw archive --> OBJ
  LW --- ICE
  TRINO --> ICE & CH
  DETX --> CH & TRINO
  DETX --> BUS
  CORR --> CH
  HEALTH --> CH & REG
  SIDE --- WRK & COL & EDGE
  FLEET <--> SIDE
  CFG --> FLEET
  ORCH <--> MCPS --> API
  ORCH --> SKL
  EXTA[External agents - Claude, Copilot, customer agents] <--> MCPS
  ORCH --> GW
  ORCH --> VAL
  SCHED --> ORCH & DETX & HEALTH
```

### 3.1 Module responsibilities

| Module | Responsibility | Built on | Reqs |
|---|---|---|---|
| `osdf-api` | Public API, RBAC, tenancy, audit log, proposal lifecycle | Python FastAPI + Postgres, Keycloak (OIDC), OPA (policy) | FR-API-01, NFR-SEC-* |
| `config-service` | Pulls Git, renders OSDF YAML into engine configs (Vector TOML/YAML, ClickHouse DDL, compiled rules), validates, versions and stages rollouts | Python, Jinja/pydantic, `vector validate` | FR-PIP-01/02/13, NFR-OPS-04 |
| `fleet-manager` | Agent and worker enrollment, grouping, config distribution, health, version rollout | Go, `opamp-go` server | FR-COL-04 |
| `osdf-sidecar` | Runs next to every Vector process (OTel Collectors use their native OpAMP supervisor instead). OpAMP client: pulls config, validates locally, hot reloads, rolls back on failure, reports health | Go, `opamp-go` client | FR-COL-04, NFR-REL-02 |
| Collector tier | Network listeners and API pullers. Writes raw to Kafka plus the raw archive | Vector (sources), OTel Collector (OTLP), declarative REST connector runner | FR-COL-* |
| Kafka | Durable bus and persistent queue. Decouples ingest from processing and destinations | Apache Kafka (KRaft) | FR-PIP-06, NFR-REL-03 |
| Pipeline workers | Parse, normalize to OCSF, enrich, mask, reduce, route, fan out | Vector + VRL, Presidio-derived rule packs for the guard | FR-PIP-*, FR-SCH-* |
| Lake writer | Kafka → Iceberg tables (bronze/silver/gold), exactly-once commits | Apache Iceberg Kafka Connect sink (or a pyiceberg micro-batch writer for the MVP) | FR-LAK-01/02 |
| Hot store | Fast scheduled detections, search, dashboards, signals/alerts tables | ClickHouse | FR-LAK-04, FR-SRC-01 |
| Lake | System of record, replay source, long-term hunting | Iceberg + Lakekeeper REST catalog + object storage | FR-LAK-* |
| Trino | One SQL endpoint over Iceberg + ClickHouse (+ PostgreSQL, OpenSearch connectors) | Trino | FR-SRC-01 |
| Federated adapters | Query external SIEMs/lakes in their native language and normalize results | Python adapters (Splunk REST, Azure Monitor Query, Elastic, Snowflake, Databricks SQL) | FR-SRC-02 |
| Detection compiler | Sigma + `x-osdf` → backend queries. Custom ClickHouse and VRL backends | pySigma + backends | FR-DET-01/02 |
| Detection runner | Scheduled windowed execution, dedup, signal/alert emission, SIEM deployers | Python worker, Temporal schedules | FR-DET-03 |
| Correlator | Signals → alerts (sequence/threshold/risk) | ClickHouse SQL (MVP), Apache Flink (P2, for streaming state) | FR-DET-06 |
| Health & drift | Silence, volume, schema drift, data-quality score | Python + ClickHouse aggregates, Prometheus metrics | FR-HLT-* |
| Graph | Source↔field↔detection↔ATT&CK↔CTI, plus embeddings for retrieval | PostgreSQL + Apache AGE + pgvector | FR-GRF-* |
| Agent runtime | Agent graphs, tools, memory, human-in-the-loop | LangGraph (Python), run inside Temporal workflows | FR-AGT-* |
| MCP servers | Domain-split servers (`osdf-data`, `-pipeline`, `-detect`, `-alerts`, `-cost`, `-admin`) expose tools, resources and prompts to OSDF agents *and* external clients | Python MCP SDK (stateless HTTP) | FR-API-02, FR-AGN-01..07 |
| MCP gateway | One governed entry point: OAuth, OPA per-tool policy, budgets, audit, tool pinning, third-party server allowlist | LiteLLM MCP gateway or a thin custom gateway (evaluate open source gateways) + OPA | FR-AGN-12/13 |
| Skills registry | Versioned, signed `SKILL.md` skills from `osdf-content` packs; served to OSDF agents and exportable to other clients | Git + OCI artifact + MCP resources | FR-AGN-08/09 |
| A2A endpoint (P2) | Publishes OSDF agents with signed agent cards; delegates blueprint steps to external agents | A2A SDK | FR-AGN-14 |
| LLM gateway | Model routing, fallback, budgets, PII redaction before egress | LiteLLM proxy; vLLM or Ollama for local models | FR-AGT-12, NFR-AI-02 |
| Validator sandbox | Runs untrusted generated artifacts (VRL tests, SQL dry runs, Sigma compile) in isolated, network-less containers | gVisor/Kata or plain rootless containers with no network; `vector test`, ClickHouse `EXPLAIN` | NFR-AI-01/04 |
| Observability | Self-telemetry, dashboards, LLM tracing | OpenTelemetry, Prometheus, Grafana, Langfuse | NFR-OPS-02, NFR-AI-03 |
| Integrations | TI, cases, SOAR | OpenCTI/MISP, DFIR-IRIS, Shuffle (webhooks) | FR-PIP-10, FR-API-05 |

---

## 4. Recommended open source stack

> Verify the license and maintenance status of each component at adoption
> time (NFR-LIC-01). Alternatives are listed where the first choice has a risk.

| Layer | Choice | License | Alternatives / notes |
|---|---|---|---|
| Edge/collector/transform engine | **Vector** | MPL-2.0 | Fluent Bit (Apache-2.0) for very small footprints; OTel Collector (Apache-2.0) for OTLP-native and OpAMP-native fleets; Tenzir (executor BSD-3, but check which parts are closed) |
| Transform language | **VRL** (Vector Remap Language) | MPL-2.0 | Chosen because it is typed, sandboxed, fast, has built-in unit tests (`vector test`), and is easy for LLMs to generate and for compilers to verify |
| Edge runtime (OTel-native fleets) | **OpenTelemetry Collector** (contrib or a custom OCB build) + OTTL | Apache-2.0 | The model BindPlane uses with its BDOT distribution. OSDF renders edge pipelines to OTel config when a group's runtime is `otelcol` (FR-COL-08) |
| Fleet protocol | **OpAMP** (`opamp-go`) | Apache-2.0 | Proven at very large scale by BindPlane. The OTel Collector has a native OpAMP extension/supervisor, and Vector uses the `osdf-sidecar` |
| Message bus | **Apache Kafka** (KRaft) | Apache-2.0 | Redpanda is BSL (avoid on the default path). NATS JetStream (Apache-2.0) for small deployments |
| Object storage | **SeaweedFS** or **Ceph RGW** (prod), any S3 in cloud | Apache-2.0 / LGPL | Garage (AGPL). MinIO community edition is AGPL and moved to source-only maintenance in 2025, so avoid it as the default |
| Table format | **Apache Iceberg** | Apache-2.0 | Delta Lake (Apache-2.0) if the Databricks ecosystem is the priority |
| Iceberg catalog | **Lakekeeper** (REST catalog) | Apache-2.0 | Apache Polaris (Apache-2.0), Nessie |
| Lake writer | **Iceberg Kafka Connect sink** | Apache-2.0 | pyiceberg micro-batch (MVP), Flink Iceberg sink (scale) |
| Hot analytics store | **ClickHouse** | Apache-2.0 | OpenSearch (Apache-2.0) if full-text search is the main need |
| Federated SQL | **Trino** | Apache-2.0 | DuckDB (MIT) for single-node/embedded |
| Streaming state (P2) | **Apache Flink** | Apache-2.0 | Arroyo (Apache-2.0/MIT) |
| Workflow/durable execution | **Temporal** | MIT | Apache Airflow for batch-only; Hatchet (MIT) |
| Agent framework | **LangGraph** | MIT | PydanticAI (MIT), Claude Agent SDK (via the gateway); keep agents framework-agnostic behind an interface |
| Agent tool protocol | **MCP** (official Python SDK; TypeScript SDK for UI/MCP Apps) | MIT | Pin the spec revision (2026-07-28 at the time of writing) |
| Agent procedures | **Agent Skills** (`SKILL.md`, agentskills.io format) | Open spec | Skills are plain folders, so any skills-compatible client can load them |
| Agent-to-agent | **A2A** protocol SDKs (Linux Foundation) | Apache-2.0 | P2. Use only for delegation across products or organizations |
| Agent telemetry | **OpenTelemetry GenAI semantic conventions** → Langfuse/Grafana | Apache-2.0 | — |
| LLM gateway | **LiteLLM** proxy | MIT (core) | Direct SDKs |
| Local model serving | **vLLM** / **Ollama** | Apache-2.0 / MIT | Use open-weight models with good tool use; benchmark them with the eval harness |
| LLM tracing/evals | **Langfuse** | MIT (core) | Arize Phoenix (ELv2, not OSI, avoid), OpenLLMetry (Apache-2.0) |
| Detection format/compiler | **Sigma** + **pySigma** | DRL (rules) / LGPL-2.1 | Write a custom ClickHouse backend if the community one is not good enough, and a VRL backend for streaming |
| Schema | **OCSF** schema + `ocsf-lib`/`ocsf-schema` tools | Apache-2.0 | — |
| PII detection | **Microsoft Presidio** patterns + custom VRL rule pack | MIT | Run Presidio NER as an optional enrichment service |
| Control-plane DB | **PostgreSQL** + **Apache AGE** + **pgvector** | PostgreSQL / Apache-2.0 | Neo4j Community (GPLv3) if graph needs grow |
| Cache/shared state | **Valkey** | BSD-3 | (Redis 8 is AGPL, also acceptable) |
| Identity | **Keycloak** | Apache-2.0 | Authentik, Zitadel |
| Policy | **Open Policy Agent** | Apache-2.0 | — |
| Secrets | **OpenBao** | MPL-2.0 | Kubernetes Secrets + SOPS |
| Git server (self-hosted) | **Gitea** / **Forgejo** | MIT / GPLv3 | GitHub/GitLab if allowed |
| Dashboards/metrics | **Grafana**, **Prometheus** | AGPL-3.0 / Apache-2.0 | Perses (Apache-2.0) |
| Threat intel | **OpenCTI** / **MISP** | Apache-2.0 / AGPL-3.0 | — |
| Case mgmt / SOAR | **DFIR-IRIS**, **Shuffle** | LGPL-3.0 / AGPL-3.0 | Integrate through webhooks only |
| UI | React + TypeScript, React Flow (pipeline canvas), Monaco (code) | MIT | — |
| Deploy | Docker Compose (dev), **Helm** on Kubernetes, Strimzi (Kafka operator), Altinity ClickHouse operator | Apache-2.0 | — |
| Supply chain | cosign, Syft, Trivy | Apache-2.0 | — |

**Language choices.** Use Python for the control plane API, agents, the
detection compiler, health and the CLI. They share pydantic models and the
pySigma/MCP/LangGraph ecosystems. Use Go for the fleet manager and sidecar,
because `opamp-go` is in Go and a static binary suits edge hosts. Use
TypeScript for the UI. VRL and SQL are generated content.

---

## 5. Data plane design

### 5.1 Event flow

```mermaid
sequenceDiagram
  participant Src as Source
  participant Col as Collector (Vector)
  participant Arc as Raw archive (S3)
  participant K as Kafka
  participant W as Worker (Vector/VRL)
  participant CH as ClickHouse
  participant LW as Lake writer
  participant Ice as Iceberg

  Src->>Col: syslog/HTTP/API/file
  Col->>Col: tag tenant/source/receipt time
  Col->>Arc: raw gzip NDJSON (bronze archive)
  Col->>K: topic raw.<tenant>.<source>
  K->>W: consume (consumer group per worker group)
  W->>W: route → parse → OCSF map → enrich → mask → reduce
  W->>K: ocsf.<class> / siem.<dest> / dlq
  W->>CH: gold OCSF (hot window)
  K->>LW: ocsf.* and raw.*
  LW->>Ice: commit bronze / gold tables
```

### 5.2 Kafka topic conventions

| Topic | Content | Retention |
|---|---|---|
| `raw.<tenant>.<source_id>` | Unparsed events with an ingest envelope | 24–72 h |
| `ocsf.<tenant>.<class_name>` | Normalized OCSF events (JSON for MVP; Avro/Protobuf with a schema registry in P1) | 24–72 h |
| `dest.<destination_id>` | Destination-specific reduced streams (for example, SIEM-bound) | 24 h |
| `dlq.<tenant>` | Parse or validation failures with reason, raw and pipeline version | 7 d |
| `signals`, `alerts` | Detection outputs | 7 d |
| `osdf.audit`, `osdf.health` | Internal | 30 d |

### 5.3 OSDF content model (rendered to Vector)

Users and agents write **OSDF YAML**. The config service compiles it into
Vector config, so the engine can be swapped later and the YAML is easier for
LLMs to work with.

```yaml
# packs/linux-sshd/pipelines/sshd_to_ocsf.yaml
apiVersion: osdf/v1
kind: Pipeline
metadata: { name: linux-sshd-ocsf, pack: linux-sshd, version: 1.2.0 }
spec:
  input: { route: linux-auth }
  steps:
    - id: parse
      type: vrl
      source: file://vrl/parse_sshd.vrl
    - id: to_ocsf
      type: ocsf_map            # rendered to VRL; validated against OCSF schema
      class: authentication     # class_uid 3002
      mapping: file://mappings/sshd_auth.yaml
    - id: drop_noise
      type: filter
      drop_if: '.activity_id == 2 && .status_id == 1 && .user.name == "nagios"'
    - id: mask
      type: guard
      rulesets: [credentials, pii-basic]
  outputs:
    - destination: clickhouse-hot
    - destination: lake-gold
    - destination: splunk-prod
      reduce: { keep_fields: [time, user, src_endpoint, status_id, activity_id, metadata] }
  tests:
    - fixture: tests/sshd_failed_password.log
      expect: tests/sshd_failed_password.ocsf.json
```

Rendering rules:
- Each `Pipeline` becomes a chain of Vector `remap`/`filter`/`route` transforms.
  `tests` become Vector `[[tests]]` blocks plus an OCSF JSON-schema validation step.
- `Route` objects become a Vector `route` transform on `raw.*` consumers.
- Each worker group gets one Vector config bundle with a content hash. The
  sidecar applies it atomically and rolls back if health checks fail.

### 5.4 Stateful functions

Vector's `dedupe`, `aggregate`, `sample` and `throttle` work per process
(Cribl has the same shared-nothing caveat). For cross-worker semantics,
partition Kafka by entity key (for example, `src_ip`) so that related events
land on the same worker. For global state, use Valkey (FR-PIP-11, P2).

### 5.5 Replay (FR-PIP-05)

`osdf replay --source X --from T1 --to T2 --pipeline P --dest D` starts a
Temporal workflow. It lists the archive objects by prefix
(`tenant/source/yyyy/mm/dd/hh`), streams them into the topic
`replay.<job_id>`, and starts a temporary Vector worker with pipeline P and
destination D. Progress and counts are reported, and the job can be cancelled.

### 5.6 Lake layout

```
s3://osdf-lake/
  bronze/   (raw archive, gzip NDJSON, written by collectors; Iceberg table over it in P1)
  warehouse/                      (Iceberg, Lakekeeper catalog)
    silver.<source_type>          (parsed, source-native)
    gold.ocsf_<class_name>        (partition: tenant_id, day(time); sort: time)
    detect.signals / detect.alerts
```

ClickHouse holds `gold` tables for the hot window (TTL, for example 30 days),
using `MergeTree` ordered by `(tenant_id, class_uid, time)`. It also holds the
`signals`, `alerts`, `source_stats` and `field_usage` tables. Field usage, which
records which fields each detection and saved search reads, drives the
optimization agent.

### 5.7 Cost architecture (primary use case)

**Where the money goes and which OSDF lever removes it:**

| Cost driver | Lever in OSDF | Component | Typical effect (to verify in pilot) |
|---|---|---|---|
| SIEM ingest/license | Tiered routing: only detect-critical events and fields go to the SIEM | Route policies + reduction functions on Vector workers | 30–60% fewer GB/day to the SIEM |
| SIEM ingest/license | Field reduction: drop raw duplicate fields after parsing, nulls/defaults, verbose blobs | `reduce` steps, `keep_fields` per destination | 20–40% smaller events |
| SIEM ingest/license | Dedup, suppression, log-to-metric aggregation for chatty sources (firewall allow, DNS, flow, health checks) | Vector `dedupe`/`reduce`/`log_to_metric`, Kafka keyed partitioning | 50–90% fewer events for those sources |
| SIEM retention | Keep a short window in the SIEM; long retention in the Iceberg lake; search in place | Lake + Trino; selective replay | Retention cost moves from SIEM pricing to object-storage pricing |
| SIEM workload/compute | Run detections and hunts on ClickHouse or the lake instead of in the SIEM | Detection runner, compiled Sigma | Lower SIEM search load |
| Storage | Parquet + ZSTD, sort by `(tenant, class, time)`, compaction, TTL tiers | Lake writer, compaction jobs, ClickHouse TTL | 10–20× compression vs raw text |
| Transformation compute | Efficient Rust engine (Vector), one parse per event (fan out after parsing), no per-event LLM, autoscaling on Kafka lag | Workers + KEDA | Linear CPU cost per EPS |
| Pipeline tool licenses | Open source replaces Cribl/BindPlane/Databahn licenses | Whole platform | License line removed; offset by OSDF infra + ops (shown in the net figure) |
| Engineering labor | Onboarding, drift, optimization and detection agents produce tested PRs | Agent layer | Fewer hours per source and per rule |

**Metering flow:**

```mermaid
flowchart LR
  V[Vector internal_metrics<br/>bytes/events per component] --> P[Prometheus]
  V --> CL[(ClickHouse cost_ledger<br/>5-min buckets)]
  SH[Baseline shadow meter<br/>raw bytes per source/destination] --> CL
  RC[Rate card<br/>Git: environments/*/rates.yaml] --> CV[Cost views]
  CL --> CV
  INF[Platform infra cost<br/>node-hours, storage GB, tokens] --> CV
  CV --> G[Grafana savings dashboard]
  CV --> OPT[Cost optimization agent]
  FU[(field_usage<br/>from detections, searches, dashboards)] --> OPT
  OPT --> PR[Reduction PR<br/>what-if + safety check]
```

- **Cost ledger schema** (ClickHouse): `ts, tenant_id, source_id, route_id,
  pipeline_version, destination_id, tier, events_in, bytes_in, events_out,
  bytes_out, baseline_bytes`. Cost views join it with the rate card, so
  changing a price recomputes history without re-metering.
- **Baseline** is the raw size at the collector (before any reduction) priced
  at the current SIEM rate. It is what you would pay without OSDF.
- **Net savings** = baseline cost − (SIEM cost after reduction + lake storage
  + OSDF infrastructure + LLM tokens). This net figure is the headline number.
- **What-if simulation** runs the proposed pipeline in the validator sandbox
  against a 24 h sample read from Iceberg, and writes projected rows to
  `cost_ledger_sim`.
- **Detection-safety check**: the set of fields and classes removed by a
  change is intersected with `field_usage` and with every production rule's
  `requires`. A non-empty intersection blocks the change.

```yaml
# osdf-content/environments/prod/rates.yaml
currency: USD
destinations:
  splunk-prod:   { model: ingest, usd_per_gb: 4.00 }   # example value; use your contract
  sentinel-prod: { model: ingest, usd_per_gb: 2.50 }
  lake-warm:     { model: storage, usd_per_gb_month: 0.023 }
  archive:       { model: storage, usd_per_gb_month: 0.004 }
compute:         { usd_per_vcpu_hour: 0.04 }
llm:             { default_usd_per_mtok_in: 3.0, default_usd_per_mtok_out: 15.0 }
```

---

## 6. Detection architecture

```mermaid
flowchart LR
  R[Sigma rule + x-osdf<br/>in Git] --> C[Compiler<br/>pySigma]
  C --> Q1[ClickHouse SQL]
  C --> Q2[Trino SQL]
  C --> Q3[VRL condition - streaming]
  C --> Q4[SPL / KQL / ES QL]
  Q1 --> RUN[Scheduled runner]
  Q3 --> WRK[Pipeline workers]
  Q4 --> DEP[SIEM deployers]
  RUN --> SIG[(signals)]
  WRK --> SIG
  SIG --> COR[Correlator]
  COR --> AL[(alerts)]
  AL --> TRI[Triage agent]
  TRI --> OUT[Webhook / SOAR / case]
  TRI -- verdicts --> FB[(feedback)]
  FB --> TUNE[Tuning agent]
```

### 6.1 Rule format

```yaml
title: Successful SSH login after multiple failures
id: 6f0c...-uuid
status: test
logsource: { product: linux, service: sshd }
detection:
  selection: { class_uid: 3002, status_id: 1 }
  condition: selection
tags: [attack.credential_access, attack.t1110]
level: medium
x-osdf:
  kind: signal                 # signal | alert
  entity: [user.name, src_endpoint.ip]
  risk_score: 30
  requires: { classes: [3002], fields: [user.name, src_endpoint.ip, status_id] }
  schedule: { every: 5m, lookback: 10m }
  tests:
    positive: [tests/brute_then_success.ndjson]
    negative: [tests/normal_login.ndjson]
  exceptions: file://exceptions/ssh_bastion.yaml
```

Sigma correlation rules (`type: event_count | value_count | temporal`)
group signals into alerts. An OSDF `risk` correlation type sums
`risk_score` per entity over a window and fires when it passes a threshold.
This is Anvilogic-style "warning → threat scenario" correlation.

### 6.2 Execution semantics
- **Windowing:** each run queries `[last_watermark - lateness, now - delay]`.
  Results are deduplicated by `(rule_id, rule_version, hash(entity, event_ids))`,
  so overlapping windows never produce duplicate signals.
- **Shadow mode:** in `staging`, rules write to `signals_shadow`. Their volume
  and overlap are reported but nothing is alerted.
- **Backtest:** run the compiled Trino SQL against Iceberg gold for N days,
  and return hit counts by day, top entities and sample events.
- **Data dependency check:** before deploy and on every health tick, join
  `requires` against the source catalog and field stats. A rule is blind
  if its data is missing.

### 6.3 Coverage
The ATT&CK STIX bundle is loaded into the graph. Coverage per technique is
computed from rules in production, whether their data is healthy, and the
average signal-to-alert precision. A technique counts as "covered" only when
the rule is deployed **and** its data dependencies are healthy. This is the
data↔detection mapping that Anvilogic calls its security graph.

---

## 7. Search architecture

- **Native:** Trino catalogs `iceberg` (warm) and `clickhouse` (hot). The
  search service chooses the engine from the time range: the hot window goes to
  ClickHouse directly, and longer ranges go through Trino with a UNION over both.
- **Federated (FR-SRC-02):** an adapter interface:

  ```python
  class SearchAdapter(Protocol):
      dialect: Literal["spl", "kql", "esql", "snowflake_sql", "databricks_sql", "trino_sql"]
      async def estimate(self, q: str, tr: TimeRange) -> Cost: ...
      async def run(self, q: str, tr: TimeRange, limit: int) -> AsyncIterator[OCSFRow]: ...
  ```

  The search agent writes the per-dialect query. When the intent maps to a
  Sigma-like selection, it uses the Sigma compiler; otherwise the LLM writes
  the query and it is checked with dry run or EXPLAIN. Results are mapped to
  OCSF field names, so they can be merged and displayed together.
- **Guardrails:** a mandatory time range, a scanned-bytes estimate (Trino
  `EXPLAIN (TYPE IO)`, ClickHouse `EXPLAIN ESTIMATE`), per-user quotas, and a
  read-only service account.

---

## 8. Agent architecture

### 8.1 Runtime

```mermaid
flowchart LR
  T[Trigger<br/>UI / chat / schedule / event] --> WF[Temporal workflow<br/>Blueprint]
  WF --> A[Agent activity<br/>LangGraph graph]
  A <--> TOOLS[MCP client]
  A --> SK[Skills<br/>loaded on demand]
  TOOLS <--> MGW[MCP gateway<br/>authN, OPA, budgets, audit]
  MGW <--> MCP[OSDF domain MCP servers]
  MGW <--> EXT[Allowlisted external MCP servers]
  A <--> GW[LLM gateway]
  A --> VAL[Validator sandbox]
  A --> PROP[Change proposal<br/>Git branch + PR]
  PROP --> HUMAN{Human approval}
  HUMAN -- merge --> CICD[CI: compile + tests] --> DEPLOY[config-service deploy]
  A --> TRACE[Langfuse traces + audit log]
```

- **Blueprints** (FR-AGT-09) are Temporal workflows defined in YAML and
  compiled to a generic workflow. Each step is an agent call, a deterministic
  tool call, a wait-for-signal (human approval), or a condition. Temporal
  provides retries, timeouts, durable state and resume after crashes.
- **Agents** are LangGraph graphs behind a common interface
  (`run(input, context) -> AgentResult{artifacts, evidence, confidence, trace_id}`).
  This keeps the framework replaceable.
- **Memory and retrieval:** pgvector indexes the OCSF schema docs, the
  pack/parser library, the Sigma rule corpus, ATT&CK and internal runbooks.
  The graph (AGE) answers structural questions.

### 8.2 Agent catalog

| Agent | Inputs | Tools used | Deterministic verification | Output |
|---|---|---|---|---|
| Onboarding | Sample logs / source endpoint | `sample_source`, `similar_parsers`, `ocsf_class_lookup`, `test_pipeline`, `validate_ocsf` | `vector test` passes, OCSF schema validation, ≥ X% fields mapped, no `unmapped` required fields | PR with VRL, mapping, route, fixtures, report |
| Drift remediation | Drift event (diff of samples) | `get_schema_history`, `get_dlq_samples`, `test_pipeline` | Old fixtures still pass and new samples parse | PR with patch |
| **Cost optimization** (built first) | Top-cost sources from `cost_ledger`, or a source ID | `cost_ledger`, `field_usage`, `volume_stats`, `detections_requiring`, `simulate_pipeline` | What-if on 24 h sample; detection-safety check passes (no field or class needed by a production rule, search or dashboard is removed) | PR with reduction steps, projected GB/day and $/month saved |
| Detection engineering | CTI text/URL/STIX, technique ID | `coverage_for_technique`, `search_rules_corpus`, `compile_rule`, `backtest_rule`, `data_available` | Compiles for all targets, positive/negative tests pass, backtest volume under threshold | PR with Sigma rule, tests, backtest report |
| Tuning | Rule ID | `rule_health`, `triage_outcomes`, `backtest_rule` | Backtest shows FP reduction with no loss on labeled TPs | PR with exception/logic patch |
| Search | NL question | `get_schema`, `search` (read-only), federated adapters | Query parses, EXPLAIN passes, cost under budget | Answer + query + results |
| Triage | Alert ID | `get_alert`, `search`, `entity_history`, `asset_lookup`, `identity_lookup`, `ti_lookup`, `similar_alerts` | Every claim cites an event ID or tool result; verdict schema-valid | Verdict, confidence, severity, evidence, next steps (written to the alert) |
| Investigation (P2) | Alert or hypothesis | All read tools | — | Timeline, entity graph, report |
| Copilot | Chat | All tools allowed by the user's RBAC | — | Answers / proposals |

### 8.3 Human-in-the-loop and autonomy levels
Each agent and action has a configured autonomy level. **L0** suggests only.
**L1** opens a PR. **L2** auto-merges when all checks pass and the change is
low risk (for example, adding a test fixture). **L3** acts automatically
(for example, auto-closing a benign alert above a confidence threshold, with
sampled human review). The default is L1 for config and L0/L1 for triage. OPA
policies enforce the levels.

### 8.4 Agent security (prompt injection and misuse)
- Log content, CTI text and alert fields are wrapped as *data* and never
  concatenated into instructions. Tool results are labeled untrusted.
- Agents have **no shell and no general network access**. Every side effect
  goes through typed MCP tools with OPA authorization, using a per-agent
  service account scoped to a tenant.
- Write tools only create proposals. The only path to production is
  merge + CI + deploy.
- An egress policy in the LLM gateway masks PII/secrets before data leaves for
  external model providers, or blocks external providers entirely.
- Output validators check that triage verdicts cite real event IDs, so
  hallucinated evidence is rejected.
- Agent runs are fully traced (Langfuse) and audit-logged (`osdf.audit`).
- Alignment: OWASP Top 10 for LLM Applications and OWASP Top 10 for Agentic
  Applications. Use them as a threat-model checklist in design reviews.

### 8.5 Evaluation harness (FR-AGT-11)
- `evals/<agent>/` holds golden datasets: log samples with expected OCSF,
  CTI with expected technique/rule behavior, labeled alerts (from Splunk
  BOTS-style datasets, Mordor/OTRF Security-Datasets, Atomic Red Team runs,
  and the user's own historical alert outcomes), and NL→SQL pairs.
- Scorers are deterministic where possible: tests pass, schema valid, SQL
  result-set equality, verdict match. An LLM-as-judge scores only summaries.
- Evals run in CI on every prompt, model or agent change. The results go to
  Langfuse datasets, with a regression gate.

### 8.6 Agentic-native platform overview (secondary use case)

OSDF treats agents as a primary interface, not an add-on. The platform's
"agent surface" has four parts:

```mermaid
flowchart TB
  subgraph Clients[Agent clients]
    OA[OSDF agents<br/>LangGraph + Temporal]
    XA[External assistants<br/>Claude, Copilot, Gemini, Codex]
    CA[Customer agent frameworks]
    VA[Vendor agents<br/>via A2A]
  end
  subgraph Surface[OSDF agent surface]
    GW[MCP gateway<br/>OAuth • OPA • budgets • audit • tool pinning]
    A2A[A2A endpoint<br/>signed agent cards]
    subgraph Servers[Domain MCP servers]
      D[osdf-data]
      P[osdf-pipeline]
      DT[osdf-detect]
      AL[osdf-alerts]
      C[osdf-cost]
      AD[osdf-admin]
    end
    SK[Skills registry<br/>SKILL.md packs]
    SDK[Code-execution sandbox<br/>typed osdf SDK]
  end
  subgraph Core[OSDF core]
    API[osdf-api] --- CH[(ClickHouse)] --- ICE[(Iceberg)]
    API --- GIT[(Content Git)]
    API --- TMP[Temporal]
  end
  OA & XA & CA --> GW
  VA <--> A2A --> OA
  GW --> Servers
  OA & XA & CA -. load .-> SK
  OA --> SDK --> GW
  Servers --> API
  EXT3[Third-party MCP servers<br/>SIEM, EDR, ticketing, TI] <--> GW
```

| Part | What it is | Why it matters |
|---|---|---|
| **MCP servers** | Domain-split servers with tools, resources and prompts | A small, focused tool surface per task; independent scaling, permissions and versioning |
| **Skills** | Portable SOC procedures (`SKILL.md` + scripts + references) | Teaches *how* to do SOC work with the tools. Loaded by progressive disclosure, so context stays small |
| **Tools** | Task-shaped operations with structured I/O, designed for agents | Higher task success, fewer tokens, safer writes |
| **Gateway + identity** | One governed path for every agent call | Consistent policy, budgets and audit for internal and external agents |

### 8.7 MCP server topology

| Server | Tools (examples) | Resources | Prompts | Default scope |
|---|---|---|---|---|
| `osdf-data` | `search_sql`, `search_federated`, `get_result_page`, `summarize_result`, `explain_query`, `list_tables` | `schema://ocsf/<class>` schema cards, `catalog://sources/<id>` | `/hunt` | read |
| `osdf-pipeline` | `list_sources`, `sample_source`, `test_pipeline`, `simulate_pipeline`, `validate_ocsf`, `propose_change` | `pack://<name>`, `pipeline://<id>` | `/onboard` | read + propose |
| `osdf-detect` | `search_rules`, `compile_rule`, `test_rule`, `backtest_rule` (task), `coverage_for_technique`, `rule_health` | `rule://<id>`, `attack://<technique>` | `/write-detection` | read + propose |
| `osdf-alerts` | `list_alerts`, `get_alert_context`, `entity_history`, `similar_alerts`, `annotate_alert`, `record_verdict` | `alert://<id>` (subscribable) | `/triage` | read + annotate |
| `osdf-cost` | `cost_report`, `top_cost_sources`, `field_usage`, `cost_check`, `savings_since` | `rates://<env>` | `/reduce-cost` | read |
| `osdf-admin` | `deployments`, `fleet_status`, `rollback` (approval required) | — | — | admin only, never granted to agents by default |

Implementation notes:
- **Spec revision.** Build on the current MCP revision (2026-07-28 at the time
  of writing), which has a stateless protocol core. Servers run as ordinary
  stateless HTTP services behind the gateway and scale horizontally. Any state
  lives in OSDF (result handles in ClickHouse, jobs in Temporal), not in MCP
  sessions. Verify the exact features against the final spec text before
  implementation.
- **Long-running operations** such as `backtest_rule`, `replay` and
  `simulate_pipeline` on large samples start a Temporal workflow and return a
  task/job handle that the client polls or awaits. They use MCP's
  asynchronous task mechanism where the client supports it.
- **Human approval** for consequential tools uses MCP elicitation, so the
  human answers inside their own agent client, or returns
  `approval_required` + proposal URL. Either way, the approval is recorded in
  the audit log against the agent identity.
- **Same backend for UI and agents.** Tools are thin adapters over `osdf-api`,
  so there is one implementation of business logic and RBAC.

### 8.8 Tool design principles (agent-first)

1. **Task-shaped, not CRUD-shaped.** `get_alert_context(alert_id)` returns the
   alert plus related events, entities, asset/identity facts and similar past
   verdicts in one call, instead of making the agent chain eight REST calls.
2. **Descriptions are prompts.** Each tool states its purpose, when to use it,
   when *not* to use it, its cost (for example, "scans up to N GB"), and an
   example call. Descriptions are versioned and evaluated like code.
3. **Structured output.** Every tool declares an output schema. Results include
   `ids` the agent can cite (event IDs, rule IDs), which triage evidence
   validation requires (§8.4).
4. **Token-bounded by default.** Responses stay within a default budget (NFR-AI-06).
   Large results are stored server-side and returned as a **result handle**
   with a summary, row count, schema and the first page. The agent then calls
   `get_result_page`, `summarize_result`, or works on the handle in the
   code-execution sandbox.
5. **Safe writes.** Writes are proposals by default, with `dry_run=true` as the
   default, idempotency keys, and a diff in the response.
6. **Actionable errors.** Errors say what was wrong and how to fix it (for
   example, "field `src_ip` is not in OCSF class 3002; did you mean
   `src_endpoint.ip`?"). This removes whole retry loops.
7. **Small tool sets.** ≤ 15–20 tools per server. Agents see only the servers
   their task needs, and clients with tool search or deferred loading load
   schemas on demand.
8. **Cost-aware.** Every call records tokens returned, bytes scanned and
   compute used in the `cost_ledger` with the agent identity (primary use case).

### 8.9 Skills

**What a skill is.** A folder with `SKILL.md` (YAML front matter `name` +
`description`, then instructions), plus optional `scripts/`, `templates/`
and `reference/`. Agents load only the name and description up front, then the
body when relevant, then the files on demand (progressive disclosure). OSDF
uses the open Agent Skills format, so the same skill works in OSDF agents and
in any skills-compatible client.

**How skills relate to tools:** tools are *capabilities* (what can be done),
and skills are *procedures* (how a SOC does it well, in order, with checks).
A skill names the MCP tools it uses and the checks it must pass.

```
osdf-content/packs/core-skills/skills/
  onboard-log-source/
    SKILL.md                 # steps: sample → identify → map OCSF → test → simulate cost → propose
    reference/ocsf-mapping-guide.md
    templates/pipeline.yaml.j2
    scripts/profile_sample.py   # runs in the sandbox
  reduce-siem-cost/
    SKILL.md                 # top_cost_sources → field_usage → simulate → cost_check → propose
  write-sigma-detection/
  triage-identity-alert/
  triage-endpoint-alert/
  hunt-credential-access/
  write-incident-summary/
```

```markdown
---
name: reduce-siem-cost
description: Find and propose safe volume reductions for the most expensive
  security data sources. Use when asked to cut SIEM/ingest cost or review a
  source's volume. Never removes fields used by production detections.
---
1. Call `osdf-cost.top_cost_sources(days=7, limit=10)`.
2. For each source, call `osdf-cost.field_usage(source_id)` and
   `osdf-pipeline.sample_source(source_id, n=500)`.
3. Choose reductions from reference/reduction-catalog.md, in order of
   savings ÷ risk. Prefer tiering and dropping redundant raw fields first.
4. Call `osdf-pipeline.simulate_pipeline(...)`, then `osdf-cost.cost_check(...)`.
   Stop if the check fails.
5. Call `osdf-pipeline.propose_change(...)` with projected $/month and the safety report.
```

**Skill lifecycle (same as other content):** author (a human, or an agent
proposing a new skill from a successful run) → PR → CI (front-matter lint,
references resolve to existing tools, scripts run in the sandbox, **skill
evals** show a better task success rate than with no skill) → signed
release in a pack → distributed to OSDF agents and exported as a bundle
for external clients. Treat third-party skills like code dependencies:
review them, pin them and scan them. A skill can carry instructions and
scripts, so it is a supply-chain and prompt-injection vector.

### 8.10 Code-execution mode and tool discovery

Two problems show up as tool counts grow: tool definitions take up context,
and large intermediate results flow through the model. Two patterns solve
them:
- **Tool search / deferred loading.** Keep servers small and descriptions
  precise, and publish a tool catalog, so clients that load tool schemas on
  demand work well.
- **Code execution.** A typed `osdf` Python SDK, generated from the tool
  schemas, is available inside the network-less validator sandbox. The agent
  writes a short script, for example: query, join with `field_usage`, compute
  savings, and return the top 10. Only the final result enters the context.
  The sandbox has CPU, memory and time limits. It can reach only the MCP
  gateway, with the agent's own token, so policy still applies to every call.
  Public reports claim large token savings from this pattern. Measure it
  with OSDF's own evals before relying on it.

### 8.11 Agent identity, gateway and A2A

- **Identity.** Each agent (OSDF built-in, customer, or third-party) is
  registered as an OAuth client in Keycloak (or uses workload identity). It
  receives short-lived, **audience-bound** tokens per MCP server, carrying tenant,
  allowed tools and autonomy level as claims. It never reuses a human
  session. A human who uses an external assistant gets delegated tokens
  scoped to their own RBAC.
- **Gateway policy (OPA)** is evaluated per call on agent, tool, arguments,
  tenant and autonomy level. Examples: `search_sql` limited to 50 GB scanned;
  `record_verdict(auto_close=true)` only at L3 and above the measured
  precision threshold; `osdf-admin` denied to all agents by default.
- **Tool pinning.** The gateway records a hash of each server's tool
  definitions. A change in a third-party server's tool descriptions blocks
  that server until a human re-approves it (defends against tool poisoning
  and silent changes).
- **Output screening.** Tool outputs that contain event data are tagged
  untrusted. Known injection patterns are flagged, and secrets/PII are masked
  according to the egress policy.
- **Audit.** Every call records agent identity, on-behalf-of user, tool,
  argument hash, result size, cost, decision and trace ID, written to `osdf.audit`.
- **Third-party MCP servers** (for example, a SIEM vendor's MCP server for
  Sentinel or Splunk data, EDR, ticketing, TI) are registered in the
  gateway allowlist with their own scopes. That makes OSDF the single governed
  point where SOC agents reach *all* security tools. OSDF does not replace
  those servers.
- **A2A (P2).** OSDF's triage, onboarding, detection and cost agents are
  published with signed agent cards (`/.well-known/agent-card.json`), so an
  external orchestrator can delegate whole tasks. Blueprints can delegate a step
  to an allowlisted external agent. The rule of thumb: MCP for agent→tool,
  A2A for agent→agent across product or organization boundaries.
- **Guidance.** Use the NSA MCP security design guidance (May 2026) and the OWASP
  Top 10 for Agentic Applications as the review checklist for every new
  server, tool, skill and external integration.

---

## 9. Control plane design

### 9.1 Core entities (Postgres)
`tenant`, `user`, `role_binding`, `worker_group`, `node` (agent/worker),
`source`, `destination`, `route`, `pipeline`, `pack`, `pack_version`,
`detection`, `detection_version`, `deployment` (git sha → group, status),
`proposal` (origin human|agent, PR url, checks, approvals), `agent_run`,
`blueprint`, `alert` (mirror/index of the ClickHouse alerts table),
`triage_verdict`, `feedback`, `audit_event`.

### 9.2 GitOps deployment flow
1. A change is merged to `main` in the content repo.
2. CI runs `osdf validate && osdf test && osdf compile` and publishes a
   content bundle (an OCI artifact signed with cosign).
3. The config service resolves the bundle for each worker group (variables,
   secrets references) and records a `deployment`.
4. The fleet manager sends the new config hash over OpAMP. The sidecars
   download it, run `vector validate`, swap atomically and report health.
   Rollout is staged (canary node first, then the whole group).
5. Health regressions (error rate, drop rate, DLQ spike) roll back automatically.

### 9.3 Multi-tenancy
Every record and Kafka topic carries a tenant prefix. Iceberg tables are
partitioned by `tenant_id`, and dedicated namespaces are available for hard
isolation. ClickHouse row policies filter by tenant. OPA policies are
tenant-scoped, and agents run with tenant-scoped credentials.

---

## 10. Deployment topologies

| Topology | Use | Components |
|---|---|---|
| **Dev / laptop** | Development, demo, MVP | Docker Compose: 1× each of Kafka, Vector collector, Vector worker, ClickHouse, SeaweedFS, Lakekeeper, Trino, Postgres, Temporal, LiteLLM, Ollama (optional), Grafana, osdf-api, osdf-agents, Gitea |
| **Single node appliance** | Small sites (≤ 50 GB/day) | Same as dev, hardened, with systemd or k3s |
| **Kubernetes HA** | Production | Helm umbrella chart. Strimzi Kafka (3+ brokers), ClickHouse via operator (2 replicas × N shards), Vector as Deployments per worker group with HPA on consumer lag, Lakekeeper ×2, Trino coordinator + workers, Temporal HA, Postgres HA (CloudNativePG), object storage from the cloud or Ceph |
| **Hybrid** | Distributed enterprise / MSSP | Central control plane. Worker groups in each site/VPC connect outbound to the control plane (OpAMP over mTLS) and to the regional Kafka |

**Sizing rule of thumb (to validate in Phase 7 performance testing):** about 1 vCPU per 5–10k EPS
for parse + map in Vector. Kafka should handle 2–3× peak ingest throughput, with
replication factor 3. ClickHouse compresses OCSF JSON 8–15×. Iceberg/Parquet
compresses 10–20× versus raw text.

---

## 11. Key architecture decisions (ADR summary)

| # | Decision | Rationale | Trade-off |
|---|---|---|---|
| ADR-01 | Use Vector as the data-plane engine, behind an OSDF YAML abstraction | Mature, fast, many sources/sinks, VRL is safe and testable, hot reload | Its per-process state and lack of a native Iceberg sink are covered by Kafka partitioning and the Kafka Connect sink. The abstraction allows a Fluent Bit or Tenzir backend later |
| ADR-02 | Kafka as the backbone between collect, process and deliver | Persistent queue, replay, decoupled scaling, ecosystem (Connect, Flink) | Operational weight; NATS is an option for small installs |
| ADR-03 | OCSF as the canonical schema | Vendor-neutral, broad adoption (AWS Security Lake, many vendors), good for LLM mapping | Some sources map imperfectly, so keep `unmapped` and the silver tier |
| ADR-04 | Iceberg + ClickHouse dual storage | Open lake for cost and portability, ClickHouse for speed | Two stores to keep consistent. The hot store is a TTL cache of gold |
| ADR-05 | Sigma as the detection source format | The largest open rule corpus, pySigma backends, correlation spec | Its expressiveness is limited, so `x-osdf` extensions and raw-SQL rules serve as an escape hatch |
| ADR-06 | Temporal for blueprints and long-running jobs | Durable, human-in-the-loop waits, retries, visibility | Another stateful service |
| ADR-07 | Agents write PRs, never config | Auditability, reversibility, reuses CI | Slower than direct writes. L2 auto-merge for low-risk changes reduces the friction |
| ADR-08 | MCP as the only tool interface for agents | One tool surface for internal agents and external assistants, with policy enforced once | MCP spec is still changing, so pin the version |
| ADR-09 | Python control plane, Go edge components | Speed of development plus the AI ecosystem; static binaries at the edge | Two toolchains |
| ADR-10 | Two edge runtimes (Vector and the OTel Collector) behind one OSDF YAML and one OpAMP fleet manager | BindPlane shows that OTel + OpAMP is becoming the standard for agent fleets. Supporting it avoids rip-and-replace for OTel shops | Renderer and test matrix for two engines. Edge-side OTel pipelines support a subset of functions (filter, mask, route, enrich); OCSF mapping stays on Vector workers |
| ADR-11 | Cost metering is built into the data plane from Phase 1, with a Git-versioned rate card | Cost reduction is the primary use case, and savings that can't be measured can't be defended to finance | Extra metrics cardinality. Mitigated by 5-minute buckets and by attributing per route, not per event |
| ADR-19 | OpenTelemetry Collector for ingestion (OpAMP-managed), Vector for processing (see `mvp-scope.md`) | Widest open connector ecosystem, native fleet management, matches what customers run; VRL stays best for generated, testable parsing | Two engines; strict split between receive (OTel) and transform (Vector) |
| ADR-20 | Declarative connector packages and generic engines (`object_storage`, `http_pull`, …) built as OTel receivers in the OSDF distribution (see `connectors-framework.md`) | Community can add sources without code; one fleet and health model | Core team owns the engines; L2/L3 code paths need sandboxing and review |
| ADR-21 | LLMs (Gemini first-class, provider-agnostic) act as pipeline compilers and batch analysts, not per-event processors; template-level caching for long-tail logs (see `ai-data-optimization.md`) | Keeps transformation cost CPU-bound and deterministic while still letting AI design flows and remove unneeded storage | Runtime AI (mode D) is a budgeted exception only |
| ADR-22 | $0 MVP on OCI Always Free ARM64 with a lean profile (no Kafka/Trino/Temporal/Keycloak) (see `zero-cost-mvp.md`) | Zero upfront cost; same chart as production via profiles | Small capacity (~5–20 GB/day); free-tier terms may change |
| ADR-23 | Portability first: one Helm chart + multi-arch images on any conformant Kubernetes; only open interfaces between components; vendor services only as ingestion sources or optional add-ons (see `initial-stack.md`) | Moves between laptop, free VM and any cloud without code changes; avoids lock-in from day one | Gives up some free edge conveniences (Cloudflare Tunnel/Access) in the core |
| ADR-12 | Split MCP servers by domain behind one gateway | Smaller tool sets per task (accuracy, tokens), independent scaling and permissions, one place for policy and audit | More deployables. The gateway and shared SDK keep them consistent |
| ADR-13 | SOC procedures ship as Agent Skills (open `SKILL.md` format) inside packs | Know-how becomes versioned, testable, portable content that works in OSDF agents and external clients; progressive disclosure saves tokens | Skills are a new supply-chain/injection vector, so they get signing, review, sandboxed scripts and evals |
| ADR-14 | External agents are first-class: same tools, identity model and policy as internal agents; A2A for delegation | This is the secondary use case. It avoids lock-in to OSDF's own agents, and customers can bring their own | A larger attack surface. Mitigated by gateway policy, tool pinning, scoped tokens and audit |
