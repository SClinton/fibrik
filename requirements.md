# Requirements: OpenSOC Data Fabric (OSDF)

> An open source, agentic platform for collecting and managing security data
> and for building detections. It combines the pipeline and data management
> of Cribl, the OpenTelemetry-native fleet and pipeline management of
> BindPlane, the AI-assisted security data fabric of Databahn, and the agentic
> detection engineering and triage of Anvilogic. Every component is open source.

- Status: Draft v0.1
- Date: 2026-10-14
- Companion docs: [`architecture.md`](architecture.md), [`execution-plan.md`](execution-plan.md)

---

## 1. Problem statement

SOC teams pay to ingest, index and keep data in a SIEM, and most of that data
is never queried. Detection logic is locked into one vendor's query language.
Onboarding a new log source (parse, normalize, map to a schema, test) takes
days to weeks of specialist work, and a silent upstream format change breaks
parsers and detections. Analysts spend most of their time triaging
false positives.

Commercial tools solve parts of this problem:

- **Cribl** adds a control plane between sources and destinations, so teams can
  route, reduce, reshape and replay data.
- **BindPlane** manages large fleets of OpenTelemetry Collectors over OpAMP,
  with edge processing and routing. It is the default pipeline for Google SecOps.
- **Databahn** uses AI to automate the data engineering: parsers, schema drift,
  normalization and PII masking.
- **Anvilogic** separates detection logic from storage, compiles it to many
  query languages, and uses agents for onboarding, detection, search and triage.

No open source project combines all of this. OSDF fills that gap.

All four vendors sell mainly on **cost reduction**: send less data to the
SIEM, store the rest cheaply, and spend less engineering time. OSDF aims to
deliver those savings without adding a new commercial license, and to make
every saving **measurable and attributable** to a source, route and destination.

## 2. Goals and non-goals

### Primary objective
**G0: cut the total cost of managing and transforming security data.** This
is the main use case, and it decides priority wherever goals compete. The cost
covers:

- SIEM/analytics **ingest and license** costs (usually the largest line item)
- **storage** and retention costs across hot, warm and archive tiers
- **transformation compute**: parsing, normalization, enrichment and routing
- **engineering labor**: onboarding sources, maintaining parsers, fixing
  drift, writing and tuning detections
- **commercial pipeline-tool licenses** (Cribl, BindPlane, Databahn and similar),
  which OSDF replaces with open source

Target: **≥ 40% lower total cost** versus the measured baseline for the
pilot's data sources, with no loss of detection coverage (see §9). Every other
goal must either support this objective or at least not raise cost.

### Secondary objective
**GA: an agentic-native SOC data platform.** OSDF is designed for AI agents
to use as first-class consumers, alongside humans:

- OSDF's own agents
- the customer's own agents
- third-party assistants and agent platforms (Claude, Copilot/Security
  Copilot, Gemini, Codex and others)
- other vendors' agents (SIEM, EDR, SOAR)

Concretely, every capability is exposed as **MCP servers and tools** that are
designed for agents. SOC know-how is packaged as portable **Agent Skills**.
Agents get their own identity, authorization, budgets and audit trail, and
OSDF agents can work with external agents over **A2A**. OSDF's built-in agents
are reference implementations on this surface, not a closed feature. Where GA
conflicts with G0, G0 wins. In practice they reinforce each other: agent-first
tools, skills and result handles also cut token spend (NFR-COST-04).

### Supporting goals
1. **G1, Own the pipeline.** Any source to any destination, with filtering,
   reduction, enrichment, masking and normalization done before data reaches
   expensive storage.
2. **G2, Own the data.** A cheap, open-format (Iceberg/Parquet on object
   storage) security data lake that is the system of record, with replay
   to any tool.
3. **G3, Own the detections.** Detection-as-code in an open format (Sigma
   plus extensions), compiled to many backends, tested, versioned and
   mapped to MITRE ATT&CK.
4. **G4, Agents do the toil, humans approve.** AI agents onboard sources,
   write parsers, tune detections, search and triage. Every change they
   propose is reviewable, testable and reversible.
5. **G5, Fully open source.** Every runtime dependency uses an OSI-approved
   license. LLMs can be local open-weight models or any API (bring your own model).

### Non-goals (for v1)
- Building a full SIEM UI to replace Splunk or Sentinel. OSDF feeds and
  augments them.
- Building a full SOAR or case management system. Integrate with an existing
  one (DFIR-IRIS, Shuffle, or a ticketing system).
- Endpoint agents with EDR features. Collection only.
- Fully autonomous response actions with no human approval.

## 3. Personas

| Persona | Needs |
|---|---|
| **Security data engineer** | Onboard sources fast, keep parsers healthy, control volume and cost, route to many destinations |
| **Detection engineer** | Write, test and deploy detections once and run them anywhere; see ATT&CK coverage; tune noisy rules |
| **SOC analyst (L1/L2)** | Get fewer, better-enriched alerts with a triage verdict and evidence; ask questions in natural language |
| **Threat hunter** | Search hot and cold data across stores in one query; pivot quickly |
| **SOC manager / CISO** | Cost per GB, coverage versus threats, MTTD/MTTR, agent accuracy, audit trail |
| **AI agent (internal or external)** | A small, well-described, task-shaped tool surface; skills that teach the procedure; structured, paginated, token-bounded results; clear errors with fixes; scoped credentials; a way to ask a human for approval |
| **Agent builder (customer/partner)** | Connect their own agent framework to OSDF over MCP/A2A; reuse and publish skills; test against eval sets; observe their agents' cost and actions |
| **Platform admin** | Deploy, scale, upgrade, configure RBAC and secrets, and handle multi-tenancy (MSSP) |

---

## 4. Competitive capability analysis

### 4.1 Cribl

**Products:** Stream (pipeline engine), Edge (lightweight agent), Search
(search in place, now with lakehouse engines), Lake (managed object-storage
data lake), Cribl.Cloud (hosted leader), Copilot/AI, Guard (sensitive-data
detection and masking).

**Architecture:**
- A **Leader** (control plane) manages configuration for **Worker Groups**
  (data plane). Workers in a group share config and scale horizontally. Groups are
  split by workload (for example, high-volume agent traffic) and by compliance
  boundary (PCI/PHI). Hybrid deployments are common: a cloud leader with
  customer-managed workers.
- **Edge Nodes** are grouped into **Fleets**. They collect from files, APIs,
  and system state, and forward to Stream workers. This gives two queue layers:
  local queues on the node and persistent queues on the workers.
- Data model: **Sources → Routes (filter expressions) → Pipelines (ordered
  Functions) → Destinations**. Pre-processing pipelines attach to sources and
  post-processing pipelines attach to destinations.
- **Packs** bundle routes, pipelines, lookups, knowledge objects and sample
  data into a portable unit. Packs are like a fancy pipeline. Group variables
  allow per-environment values.
- **Functions** include Eval, Mask, Parser, Regex Extract, Lookup, Drop,
  Regex Filter, Sampling, Dynamic Sampling, Suppress (dedup), Aggregations,
  Rollup Metrics, Serialize, Flatten, GeoIP, DNS lookup, Code (JS) and others.
- **Stateful functions are per worker process** (a shared-nothing design).
  Aggregating or deduplicating across workers needs an external cache
  such as Redis. *(We keep the same design trade-off and add an optional
  shared state tier.)*
- **Persistent queues** protect against backpressure and outages. **Replay** reads
  stored data back from object storage through pipelines to any destination.
- **Search** queries data in place (S3, Lake, APIs, Edge nodes) with a KQL-like
  language. Since 4.17 (March 2026) it can also ingest into lakehouse engines
  and run AI-powered investigations (preview).
- **AI:** Copilot (natural-language help for pipelines and queries, and since
  4.18 aware of the live environment), external MCP server support, a
  standalone MCP server, Notebooks, BYO AI, and Guard (200+ rules for
  PII/PHI/credentials, plus agentic background detection).

**Capabilities we must match:** route, reduce, enrich, mask and normalize in
flight; agent fleet management; packs; persistent queues; replay; search in
place; an AI copilot exposed over MCP; sensitive-data detection.

### 4.2 Databahn

**Products:** Smart Edge, Highway, Cruz, Reef.

- **Smart Edge:** agentless and agent-based collection (syslog, APIs, cloud,
  databases) with edge analytics, contextual metadata tagging and smart routing.
  It claims 400 to 600+ connectors.
- **Highway:** orchestration and routing layer. AI-driven filtering,
  **schema drift detection and management**, cost optimization, and routing to
  SIEM, data lake and archive.
- **Cruz:** an agentic "data engineer in a box". It discovers logs, onboards
  sources, builds parsers, normalizes to **OCSF / ECS / CIM**, enriches or
  suppresses data in context, and monitors pipeline health and drift. It uses
  ML/RL and semantic parsing (vendor description).
- **Reef:** a contextual intelligence hub. It sends the high-value subset to
  customer-owned data lakes, does graph-based correlation, and offers
  AI-powered and natural-language search. It integrates with Cruz over **MCP**.
- **Also:** automated PII masking, compliance tracking, anomaly alerts on
  volume and silence, and claims of about 50% SIEM volume reduction (vendor claim).

**Capabilities we must match:** AI-generated parsers and schema mappings;
drift detection with auto-proposed fixes; source-health monitoring (silent
source, volume anomaly); multi-schema output; a security context graph that
AI can query over MCP.

### 4.3 Anvilogic

**Platform:** the "AgenticSecOps" platform, an AI layer on top of existing
SIEMs and data lakes (Splunk, Sentinel, Elastic, Snowflake, Databricks) and
cloud storage (S3, Azure Blob, GCS through "Anvilogic Compute").

- **Agents:**
  - **Onboard:** parses and normalizes any source. On Snowflake it creates
    Tasks/Streams and moves data from Silver to Gold tables (medallion), and
    generates normalization SQL with Copilot.
  - **Search:** one query across Splunk, Snowflake, Sentinel, S3 and others,
    without moving data (federated).
  - **Detect:** takes threat intel and produces deployed detection logic.
  - **Investigate/Triage:** automated triage, enrichment and severity
    scoring before an analyst opens the case. The vendor claims 98% triage accuracy.
- **Blueprints:** chain agents into end-to-end automated workflows.
- **Armory:** a curated library of detections and TTPs, with summaries of
  thousands of CTI reports.
- **Detection-as-code:** version-controlled logic decoupled from the SIEM, and
  generated for SPL, KQL and SQL.
- **Coverage:** MITRE ATT&CK mapping, detection-health benchmarking and
  maturity scoring.
- **Correlation:** low-fidelity "warning" signals that roll up to
  high-fidelity, multi-stage threat scenarios. This cuts alert volume.
- **Monte Copilot:** chat that auto-tunes noisy rules, fixes broken detections,
  converts natural language to SQL/KQL/SPL, and enriches alerts.
- **Enterprise security graph:** classifies data feeds and maps which data
  supports which detections. This underpins the agents.

**Capabilities we must match:** a portable detection format and
multi-backend compiler; a detection lifecycle (author, test, deploy, monitor,
tune, retire); ATT&CK coverage and data-to-detection mapping; signal-to-alert
correlation; federated search; triage and investigation agents; composable
agent workflows (blueprints).

### 4.4 BindPlane

**Company:** formerly observIQ. Dynatrace has announced a definitive agreement
to acquire it. The closing date and any effect on the roadmap or licensing
were not public at the time of this research.

**Products:** the BindPlane control plane (server and web UI, self-hosted or
cloud, with an Enterprise "Google Edition" bundled with Google SecOps) and the
**BDOT Collector**. The BDOT Collector is an open source distribution of the
OpenTelemetry Collector, built with the OpenTelemetry Collector Builder.

**Architecture:**
- A **control plane for OpenTelemetry Collectors**. It manages fleets that are
  claimed to reach up to about 1M collectors from one instance or cluster.
- **OpAMP** pushes configuration, manages collector versions and collects
  health, with no SSH access to hosts. The BDOT Collector is described as the
  first distribution to implement OpAMP.
- A pipeline model of **sources → processors → destinations**. It runs at the
  point of collection (on the edge collector) or on gateway collectors.
  Processing covers filtering, sampling, deduplication, log-to-metric
  extraction, masking/encryption of sensitive data, enrichment, and
  routing by data type, source or policy to many destinations.
- **Rollouts:** staged config rollouts across the fleet, with version history.
- **Blueprints:** reusable configuration bundles. Earlier blueprints covered
  processors only. Newer "Full-Pipeline Blueprints" cover source, processors
  and destination.
- **Google SecOps integration:** BindPlane is Google's recommended agent and
  pipeline for Chronicle/SecOps ingestion. It includes a forwarder migration tool
  and SecOps Data Processing pipelines (Preview, March 2026) that you can
  configure from the BindPlane console or the SecOps Data Pipeline API.
- **AI:** "Pipeline Intelligence" (November 2025) identifies log types, applies
  parsers and optimizes configs. It claims to automate 70–80% of pipeline work
  (vendor claim). "Global Intelligence" (around RSAC 2026) monitors pipelines
  and recommends optimizations. Its first feature, Threat Intel Enrichment,
  tags suspicious IPs in-stream. Both features are limited to select
  Enterprise customers and are rolling out gradually.
- **Licensing note:** the BDOT Collector is open source, while the BindPlane
  server's enterprise editions are commercial. Check the current terms,
  especially after the Dynatrace acquisition.

**What it is not:** BindPlane does not host a data lake, run search, run
detections or triage alerts. It is a pure pipeline and fleet product.

**Capabilities we must match:** an OpenTelemetry-native collector option;
**OpAMP-based fleet management at large scale** (enrollment, config
push, version upgrades, staged rollouts, health); processing at the edge;
full-pipeline blueprints; AI log-type identification and parser
assignment; in-stream threat-intel enrichment; and a migration path from
existing forwarders.

**Design implication for OSDF:** BindPlane proves that OpAMP + the OTel
Collector works as a vendor-neutral fleet model. OSDF should therefore treat the
**OTel Collector as a first-class edge runtime next to Vector** (FR-COL-08), so
that fleets already standardized on OpenTelemetry can adopt OSDF without
replacing agents.

### 4.5 Capability matrix → OSDF modules

| Capability | Cribl | Databahn | Anvilogic | BindPlane | OSDF module |
|---|:-:|:-:|:-:|:-:|---|
| Agent/edge collection + fleet management | ● | ● | ○ | ● | `collect` |
| Agentless/API/cloud connectors | ● | ● | ○ | ● | `collect` |
| Routing, filtering, reduction | ● | ● | ○ | ● | `pipeline` |
| Parsing + schema normalization (OCSF) | ◐ | ● | ● | ◐ | `pipeline` + `onboard-agent` |
| PII/sensitive data masking | ● | ● | – | ● | `pipeline` (`guard`) |
| Persistent queues + replay | ● | ◐ | – | ◐ | `pipeline` + `lake` |
| Schema drift detection/remediation | ◐ | ● | ◐ | ? | `health` + `drift-agent` |
| Source health/silence/volume anomaly | ◐ | ● | ◐ | ◐ | `health` |
| Open-format data lake | ● | ◐ | ◐ (uses customer lake) | ○ (routes to lakes) | `lake` |
| Federated search | ● | ◐ | ● | – | `search` |
| NL → query | ● | ● | ● | ? | `search-agent` |
| Detection-as-code, multi-backend | – | – | ● | – | `detect` |
| ATT&CK coverage + data↔detection graph | – | ◐ | ● | – | `graph` + `detect` |
| Signal correlation → alerts | – | ◐ | ● | – | `detect` (`correlate`) |
| Triage/investigation agents | ◐ | ◐ | ● | – | `triage-agent` |
| Agent workflow chaining (blueprints) | ◐ | ◐ | ● | ○ | `orchestrator` |
| MCP exposure of platform | ● | ● | ◐ | ? | `mcp-gateway` |
| Packs/content marketplace | ● | ◐ | ● (Armory) | ◐ (Blueprints) | `content` |

● strong, ◐ partial, ○ limited, – not a focus, ? not found in public material

---

## 5. Functional requirements

Priority: **P0** = MVP (walking skeleton plus first useful release), **P1** =
v1.0, **P2** = later. Each requirement has an ID, so the architecture and
the tests can trace back to it.

### 5.0 Cost management and reduction (`cost`) — primary use case

| ID | Requirement | Pri |
|---|---|---|
| FR-CST-01 | **Rate card**: configurable unit costs per destination and tier ($/GB ingested into each SIEM, or workload/compute-unit pricing; $/GB-month for hot, warm and archive storage; $/vCPU-hour for pipeline compute; $/1M tokens for LLMs) | P0 |
| FR-CST-02 | **Metering**: bytes and events in and out measured at every stage (source, route, each function, destination). Stored in a `cost_ledger`, attributed to tenant, source, route, pipeline version and destination | P0 |
| FR-CST-03 | **Baseline capture**: record what each source would cost if sent raw to the current SIEM (a pass-through shadow measurement) before any reduction is applied, so that savings are measured, not estimated | P0 |
| FR-CST-04 | **Savings report**: per source, route and destination: baseline cost vs actual cost, GB/day saved, $ saved per month, trend. Exportable (CSV/JSON) for finance | P0 |
| FR-CST-05 | **Reduction function library** with documented typical savings: drop null/empty/default fields, drop redundant raw fields after parsing, deduplicate repeated events, suppress chatty event IDs, aggregate to metrics (logs → counters), sample low-value events, truncate oversized fields, compact field names for the SIEM output, filter by allow/deny lists | P0 |
| FR-CST-06 | **Tiered routing policies**: classify each source/event type as *detect-critical* (SIEM + lake), *investigate* (lake only, searchable), *compliance* (archive only, compressed) or *drop*. Policies are declared per route and enforced in the pipeline | P0 |
| FR-CST-07 | **Detection-safety guard**: a reduction change is blocked if it removes an event type or field that a production detection, saved search or dashboard requires (uses `field_usage` + rule `requires`) | P0 |
| FR-CST-08 | **What-if simulation**: before deploy, run a proposed pipeline on a recent sample (for example, 24 h from the lake) and report projected GB/day, $/month and detection impact | P0 |
| FR-CST-09 | **Budgets and alerts**: per source/destination daily volume and cost budgets, with alerts on overrun and on sudden growth (a cost anomaly) | P1 |
| FR-CST-10 | **Chargeback/showback** per tenant, business unit or data owner | P2 |
| FR-CST-11 | **Search in the lake instead of rehydration**: investigations run on lake data in place (Trino), and selective replay sends only the matching slice to the SIEM, never whole time ranges | P1 |
| FR-CST-12 | **Platform cost visibility**: OSDF's own infrastructure cost (compute, Kafka, ClickHouse, object storage, LLM tokens) is shown next to the savings, so net savings are reported honestly | P1 |
| FR-CST-13 | **Labor-cost metrics**: time to onboard a source, time to fix drift, and detection authoring time, measured from proposal timestamps and compared against the pre-OSDF baseline | P1 |
| FR-CST-14 | **Cost-efficient storage formats**: Parquet with ZSTD, partition and sort settings tuned for compression, and automatic compaction. Ratios are reported per table | P0 |

### 5.1 Collection (`collect`)

| ID | Requirement | Pri |
|---|---|---|
| FR-COL-01 | Receive syslog (RFC3164/5424, UDP/TCP/TLS), HTTP/HEC-compatible, OTLP (logs), Kafka, and file tail | P0 |
| FR-COL-02 | Pull from cloud and SaaS APIs: AWS CloudTrail/S3 (SQS notification), Azure Event Hub, GCP Pub/Sub, Okta, M365/Entra, GitHub audit | P1 |
| FR-COL-03 | Lightweight edge agent for Linux/Windows/macOS: files, journald, Windows Event Log, host metrics | P1 |
| FR-COL-04 | Central **fleet management** of agents and workers: enroll, group, push config, health, version, rollout/rollback (OpAMP-compatible) | P1 |
| FR-COL-05 | **Extensible connectors framework**: a declarative connector package (manifest + mapping + presets + samples), generic engines (`otel_receiver`, `object_storage`, `http_pull`, `queue`, `webhook`), generated UI forms, a CLI and offline tests, a community registry with trust tiers. Detailed in [`connectors-framework.md`](connectors-framework.md) (FR-CON-01..16) | P0 (lite) |
| FR-COL-11 | **Cloud storage ingestion points**: AWS S3, Azure Blob/ADLS Gen2 and Google Cloud Storage via notifications (SQS / Event Grid / Pub/Sub) and backfill, with formats, checkpoints and cross-account identity (connectors-framework §5) | P0 |
| FR-COL-06 | Tag every event at ingest with `source_id`, `tenant_id`, `collector_id`, receipt time and raw size | P0 |
| FR-COL-07 | Buffer at the edge (disk) when downstream is unavailable | P1 |
| FR-COL-08 | Support the **OpenTelemetry Collector** (upstream contrib or a custom OCB build) as an edge/gateway runtime alongside Vector, managed through the same OpAMP fleet manager. OSDF pipeline YAML can render to OTel Collector config (receivers/processors/exporters + OTTL) for edge-side filtering, masking and routing | P1 |
| FR-COL-09 | **Staged rollouts** of fleet config and collector versions (canary → percentage → all), with automatic rollback on health regression and a full version history | P1 |
| FR-COL-10 | **Forwarder migration helpers**: import existing configs (for example, Splunk UF inputs.conf, Fluent Bit, Logstash/Beats) into OSDF sources/routes as a proposal | P2 |

### 5.2 Pipeline and routing (`pipeline`)

| ID | Requirement | Pri |
|---|---|---|
| FR-PIP-01 | Declarative **pipeline definitions** (YAML, versioned in Git) made of ordered functions: parse, extract, eval/remap, drop, filter, sample, dedup/suppress, aggregate, lookup/enrich, mask, serialize, route | P0 |
| FR-PIP-02 | **Routes**: ordered filter expressions that send events to pipelines, with "final" and clone (fan-out) semantics | P0 |
| FR-PIP-03 | Output to many destinations: object storage/lake (Iceberg/Parquet), ClickHouse, OpenSearch, Kafka, Splunk HEC, Sentinel/Log Analytics, Elastic, syslog, webhook | P0 for lake + ClickHouse + Kafka, P1 for others |
| FR-PIP-04 | **Full-fidelity archive**: raw events always go to cheap object storage before reduction (configurable per source) | P0 |
| FR-PIP-05 | **Replay**: select a time range and source from the archive and re-run it through any pipeline to any destination | P1 |
| FR-PIP-06 | **Persistent queues** at the worker tier (Kafka is the backbone), with at-least-once delivery | P0 |
| FR-PIP-07 | **Data preview / test mode**: run a pipeline on sample events in the UI or CLI and show a before/after diff and the volume change | P0 |
| FR-PIP-08 | **Packs**: a portable bundle (routes, pipelines, parsers, lookups, OCSF mappings, sample data, tests, detections) with semantic versioning, import/export, and a registry | P1 |
| FR-PIP-09 | **Sensitive data guard**: detect and mask, hash or tokenize PII, PHI, secrets and credentials with a rule library (regex + checksum + NER), applied per route | P1 |
| FR-PIP-10 | Enrichment: GeoIP (open DB), ASN, asset/identity lookups (CSV or DB), threat-intel IOC match (from MISP/OpenCTI) | P1 |
| FR-PIP-11 | Shared state tier for cross-worker dedup and aggregation (optional) | P2 |
| FR-PIP-12 | Per-route and per-function **metrics**: events/bytes in/out, drop rate, error rate, latency | P0 |
| FR-PIP-13 | Group variables and secrets references in pipeline definitions | P1 |
| FR-PIP-14 | **Full-pipeline blueprints**: one-click templates that create source + processing + destination together, parameterized and versioned (BindPlane-style; packaged as packs) | P1 |
| FR-PIP-15 | **In-stream threat-intel enrichment**: tag IPs, domains and hashes against IOC feeds at the edge or worker tier, with feeds refreshed on a schedule | P1 |

### 5.3 Schema and normalization

| ID | Requirement | Pri |
|---|---|---|
| FR-SCH-01 | **OCSF** is the canonical internal schema. Each normalized event carries `class_uid`, `category_uid`, `metadata.product`, `metadata.version` and `unmapped` | P0 |
| FR-SCH-02 | Optional output adapters to ECS and Splunk CIM field names | P2 |
| FR-SCH-03 | A **schema registry** of each source's observed field set, types and cardinality, versioned over time | P1 |
| FR-SCH-04 | Validation: events that fail OCSF validation go to a dead-letter stream with the reason. They are never silently dropped | P0 |
| FR-SCH-05 | Medallion layers in the lake: **bronze** (raw), **silver** (parsed, source-native), **gold** (OCSF) | P0 |

### 5.4 Source health and drift (`health`)

| ID | Requirement | Pri |
|---|---|---|
| FR-HLT-01 | Detect **silent sources** (no data for N times the expected interval) and alert | P0 |
| FR-HLT-02 | Detect **volume anomalies** per source (seasonal baseline) | P1 |
| FR-HLT-03 | Detect **schema drift**: new or removed fields, type changes, rising parse-failure rate, rising `unmapped` ratio | P1 |
| FR-HLT-04 | On drift, open a **remediation task** for the drift agent (FR-AGT-03) | P1 |
| FR-HLT-05 | Data quality score per source (parse success, OCSF validity, timestamp skew, completeness of required fields) | P1 |

### 5.5 Lake and storage (`lake`)

| ID | Requirement | Pri |
|---|---|---|
| FR-LAK-01 | Store data as **Apache Iceberg** tables on S3-compatible object storage with a REST catalog | P0 |
| FR-LAK-02 | Partition by tenant, OCSF class and event date. Compaction and snapshot expiry run on a schedule | P0 |
| FR-LAK-03 | Retention policies per table and tenant (for example, hot 30d in ClickHouse, warm 1y in Iceberg, raw archive 7y) | P1 |
| FR-LAK-04 | **Hot tier** for fast detections and search (ClickHouse) holding gold data for a configurable window | P0 |
| FR-LAK-05 | Data can be read by any Iceberg-compatible engine (Trino, Spark, DuckDB, ClickHouse) with no lock-in | P0 |

### 5.6 Search (`search`)

| ID | Requirement | Pri |
|---|---|---|
| FR-SRC-01 | SQL search across hot (ClickHouse) and warm (Iceberg) storage through one endpoint | P0 |
| FR-SRC-02 | **Federated search** against external stores (Splunk, Sentinel, Elastic/OpenSearch, Snowflake, Databricks, S3) through adapters, with results merged into a common shape | P1 |
| FR-SRC-03 | A pipe-style query language (simplified, PRQL-based or KQL-like) that compiles to SQL | P2 |
| FR-SRC-04 | Saved searches, query history, result export, and notebook-style investigations | P1 |
| FR-SRC-05 | Query cost guardrails: scanned-bytes estimate, time-range limits, concurrency quotas | P1 |

### 5.7 Detection engineering (`detect`)

| ID | Requirement | Pri |
|---|---|---|
| FR-DET-01 | **Detection-as-code** in **Sigma** (YAML) with OSDF extensions: severity model, risk score, entity fields, correlation membership, tuning exceptions, test cases, data dependencies | P0 |
| FR-DET-02 | **Compile** each rule to many backends with pySigma: ClickHouse SQL (P0), Trino/Iceberg SQL (P1), Splunk SPL, Sentinel KQL, Elastic ES\|QL/Lucene (P1). Unsupported constructs fail loudly | P0 |
| FR-DET-03 | **Execution modes**: scheduled (SQL on hot store), streaming (per-event match in the pipeline for simple rules), and **deploy-to-SIEM** (push the compiled rule to an external SIEM via API) | P0 scheduled, P1 others |
| FR-DET-04 | **Detection CI**: each rule has positive and negative test events. CI runs them on every change and blocks merge on failure | P0 |
| FR-DET-05 | **Lifecycle states**: draft, test, staging (shadow, alerts not routed), production, deprecated. Promotion is gated by tests and metrics | P1 |
| FR-DET-06 | **Signals and correlation**: low-fidelity rules emit *signals*. Correlation rules (sequence, threshold, multi-tactic per entity in a window, risk-score sum) emit *alerts* | P1 |
| FR-DET-07 | **MITRE ATT&CK coverage map**: by technique, the rules deployed, the data available, and the gaps. It is computed from rule tags and the data-to-detection graph | P1 |
| FR-DET-08 | **Data-dependency checking**: a rule declares the OCSF classes and fields it needs. The platform flags rules whose data is missing or degraded | P1 |
| FR-DET-09 | **Content import**: SigmaHQ rules, plus an "armory" registry of community packs | P1 |
| FR-DET-10 | **Detection health**: alert volume, true/false-positive rate from triage outcomes, last fired, execution errors and latency | P1 |
| FR-DET-11 | **Exceptions/tuning** as code (allowlists scoped per rule, entity and expiry), separate from rule logic | P1 |

### 5.8 Security knowledge graph (`graph`)

| ID | Requirement | Pri |
|---|---|---|
| FR-GRF-01 | Model **sources ↔ OCSF classes/fields ↔ detections ↔ ATT&CK techniques ↔ threat actors/CTI** | P1 |
| FR-GRF-02 | Model **entities** (users, hosts, IPs, cloud resources) and their relations as observed in alerts, for triage pivots | P2 |
| FR-GRF-03 | Queryable by agents through MCP tools (for example, "which detections cover T1078 and is their data healthy?") | P1 |

### 5.9 Agents (`agents`)

All agents share these rules: they use only registered tools, every action is
logged, they never write to production directly (they open a **change
proposal** such as a Git PR or a ticket), and they include evidence and test
results with each proposal.

| ID | Agent | Requirement | Pri |
|---|---|---|---|
| FR-AGT-01 | **Onboarding agent** | Given sample logs or a source endpoint: identify the format and product, generate a parser (VRL), an OCSF mapping, test fixtures and a route, run them in test mode, and open a PR with a pass/fail and coverage report | P0 |
| FR-AGT-02 | **Cost optimization agent** (the first agent to build, because it serves the primary use case) | Find the most expensive sources and routes in the `cost_ledger`. Analyze which fields and event types detections, searches and dashboards actually read. Propose reductions (drop fields, dedup, sample, aggregate to metrics, re-tier to lake-only) as a PR that includes the what-if simulation (FR-CST-08), $/month saved and the detection-safety check (FR-CST-07) | P0 |
| FR-AGT-03 | **Drift remediation agent** | When drift is detected, diff the samples, propose a parser/mapping patch, re-run tests, and open a PR | P1 |
| FR-AGT-04 | **Detection engineering agent** | Given CTI (URL, report or STIX) or a technique ID: extract TTPs, check coverage, draft Sigma rules with tests, compile them to the target backends, backtest on lake data (hit count and sample), and open a PR | P0 (basic), P1 (backtest) |
| FR-AGT-05 | **Tuning agent** | Use triage outcomes to find noisy rules, propose exceptions or logic changes, and show the backtest before and after | P1 |
| FR-AGT-06 | **Search agent** | Turn natural language into a query (SQL for OSDF and SPL/KQL for federated targets), explain the query, run it with guardrails, and summarize the results | P0 |
| FR-AGT-07 | **Triage agent** | For each alert: gather context (related events, entity history, asset/identity, TI), decide a verdict (benign / suspicious / malicious / needs-human), set a confidence and severity, write an evidence-backed summary, and recommend next steps. Write the outcome back as an alert annotation | P0 (basic), P1 (full) |
| FR-AGT-08 | **Investigation agent** | Multi-step hunt from an alert or hypothesis. It builds a timeline and entity graph, produces a report, and can be resumed by a human | P2 |
| FR-AGT-09 | **Blueprints** | Declarative workflows that chain agents and deterministic steps (for example, CTI ingest → detect agent → CI → human approval → deploy → monitor), with retries, timeouts and human-in-the-loop gates | P1 |
| FR-AGT-10 | **Copilot chat** | A chat UI and API that sees the platform's tools (MCP), the live configuration and the docs | P1 |
| FR-AGT-11 | **Agent evaluation** | Golden datasets and automated evals per agent (parser accuracy, OCSF mapping accuracy, rule test pass rate, triage precision and recall against labeled alerts, NL→SQL execution accuracy). Results are tracked over time and per model | P0 |
| FR-AGT-12 | **Model routing** | Any OpenAI-compatible or Anthropic-compatible endpoint, local open-weight models (vLLM/Ollama), per-agent model selection, and fallback | P0 |

### 5.10 MCP and APIs

| ID | Requirement | Pri |
|---|---|---|
| FR-API-01 | Every platform capability is reachable through a versioned REST/gRPC API (OpenAPI spec) | P0 |
| FR-API-02 | **MCP servers** (split by domain, see §5.11) expose platform tools: `search`, `get_alert`, `list_sources`, `get_source_health`, `get_schema`, `test_pipeline`, `compile_rule`, `backtest_rule`, `coverage_for_technique`, `cost_report`, `simulate_pipeline`, `cost_check`, `propose_change`, and others | P0 |
| FR-API-03 | MCP client support, so agents can call external MCP servers (ticketing, TI, cloud) through an allowlist | P1 |
| FR-API-04 | A CLI (`osdf`) for GitOps workflows: validate, test, compile, deploy, replay | P0 |
| FR-API-05 | Webhook and Kafka outputs for alerts to SOAR and case management (DFIR-IRIS, Shuffle, Jira, ServiceNow) | P0 webhook, P1 others |

### 5.11 Agentic-native platform: MCP servers, skills and tools (secondary use case)

| ID | Requirement | Pri |
|---|---|---|
| FR-AGN-01 | **Domain-split MCP servers** instead of one monolith: `osdf-data` (search, schema, lake, result handles), `osdf-pipeline` (sources, routes, test, simulate, propose), `osdf-detect` (rules, compile, test, backtest, coverage), `osdf-alerts` (alerts, context, triage write-back, feedback), `osdf-cost` (ledger, savings, cost check), `osdf-admin` (restricted: fleet, deployments). Each server can be deployed, scaled, permissioned and versioned on its own | P0 (data, alerts, detect, cost), P1 (others) |
| FR-AGN-02 | Implement the **current MCP specification** (2026-07-28 at the time of writing): stateless servers behind standard HTTP load balancing, the extensions framework, hardened OAuth authorization. Pin the protocol version and test SDK compatibility in CI. Keep stdio transport for local/dev use | P0 |
| FR-AGN-03 | **Long-running operations** (backtests, replays, simulations, large hunts) run as asynchronous MCP tasks (or a job handle plus polling where a client lacks support). They are backed by Temporal and resumable | P1 |
| FR-AGN-04 | **Human approval inside the agent loop**: tools that need a human decision (deploy, auto-close, large replay) ask through the MCP client (elicitation) when the client supports it. Otherwise they return `approval_required` with a link to the proposal | P1 |
| FR-AGN-05 | **Agent-first tool design** (see architecture §8.8). Task-shaped tools; JSON-schema inputs and structured outputs; descriptions that state when to use and when not to use each tool; pagination plus `max_tokens`/`max_rows` limits; **result handles** for large result sets; `dry_run` on every write; idempotency keys; errors that name a fix | P0 |
| FR-AGN-06 | **MCP resources** for read-mostly context: OCSF class "schema cards" (fields, descriptions, example values, query snippets), source catalog entries, detection docs, ATT&CK techniques, runbooks. Subscriptions or notifications fire on new alerts, drift events and deployments, so agents can react | P1 |
| FR-AGN-07 | **MCP prompts** for common entry points (for example, `/triage <alert>`, `/onboard <sample>`, `/reduce-cost <source>`, `/hunt <technique>`) | P1 |
| FR-AGN-08 | **Agent Skills library**: SOC procedures packaged as `SKILL.md` folders (open Agent Skills format) with scripts, templates and reference files. Examples: onboarding a source, OCSF mapping, Sigma authoring, cost reduction review, triage playbooks per alert family, hunts per ATT&CK tactic, and incident write-ups. Skills reference OSDF MCP tools by name and load by progressive disclosure | P0 (5 skills), P1 (library) |
| FR-AGN-09 | **Skills as content**: skills live in `osdf-content` Git, ship inside packs, are versioned and signed, and pass CI (lint, script sandbox tests, and evals showing the skill improves task success). They are distributed to OSDF agents and exportable to any skills-compatible client | P1 |
| FR-AGN-10 | **Code-execution mode**: a typed `osdf` Python SDK, generated from the same tool schemas, runs in the validator sandbox. Agents can filter and join large results in code instead of passing rows through the model context. Network-less, time- and memory-limited | P1 |
| FR-AGN-11 | **Tool discovery at scale**: support clients that use tool search / deferred loading. Keep each server's tool count small (≤ 15–20). Publish a catalog of all tools and skills, with descriptions and examples | P1 |
| FR-AGN-12 | **MCP gateway**: one governed entry point for all OSDF MCP servers *and* allowlisted third-party servers (for example, a SIEM vendor's MCP server, EDR, ticketing, TI). It handles authentication, per-tool authorization (OPA), rate limits, token/cost budgets, audit, tool-definition pinning (hash) to stop silent tool changes, and output sanitization | P0 (OSDF servers), P1 (third-party) |
| FR-AGN-13 | **Agent identity**: every agent, internal or external, has its own OAuth client or workload identity. Tokens are audience-bound per MCP server, scoped to tenant, tools and autonomy level, and short-lived. Agents never reuse a human's session | P0 |
| FR-AGN-14 | **A2A interoperability**: OSDF agents (triage, onboarding, cost optimization, detection) are published as A2A agents with signed agent cards, so external orchestrators can delegate to them. Blueprints can delegate steps to allowlisted external A2A agents | P2 |
| FR-AGN-15 | **Agent observability and cost**: per-agent and per-tool traces (OpenTelemetry GenAI semantic conventions plus Langfuse), token and tool-call cost written to the `cost_ledger`, and tool-level success and error rates | P0 |
| FR-AGN-16 | **Tool and skill evals**: eval suites check that agents pick the right tool and skill, call it with valid arguments and finish the task. They run per model and per client (OSDF agents, Claude, other MCP clients) and gate CI | P1 |
| FR-AGN-17 | **Bring-your-own-agent conformance**: a documented contract and test kit so that a customer's agent framework can connect, authenticate, discover tools and skills, and pass a reference task suite | P2 |

### 5.12 UI

| ID | Requirement | Pri |
|---|---|---|
| FR-UI-01 | Source inventory and health dashboard | P0 (Grafana), P1 (native) |
| FR-UI-02 | Visual pipeline/route editor with live preview (it reads and writes the same YAML as Git) | P1 |
| FR-UI-03 | Detection catalog, ATT&CK heatmap, and detection health | P1 |
| FR-UI-04 | Alert queue with the triage agent's verdict, evidence and feedback buttons (agree/disagree) | P0 (minimal) |
| FR-UI-05 | Agent activity log and change-proposal review | P1 |
| FR-UI-06 | Search workbench and copilot chat | P1 |

---

## 6. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-PERF-01 | Throughput | One pipeline worker (4 vCPU) sustains ≥ 50k EPS of syslog parse + OCSF map + 2 destinations. The design scales horizontally to ≥ 1M EPS / 10+ TB/day |
| NFR-PERF-02 | Latency | Ingest to hot-store query p95 ≤ 30 s. Streaming detection p95 ≤ 5 s. Scheduled detection interval ≥ 1 min |
| NFR-PERF-03 | Search | Hot 24 h queries p95 ≤ 5 s on 1 TB/day. Warm 30-day lake queries finish within minutes |
| NFR-REL-01 | Durability | At-least-once delivery from the collector to the lake. Raw archive durability is that of the object store |
| NFR-REL-02 | Availability | Data plane keeps flowing if the control plane is down (workers run their last known good config) |
| NFR-REL-03 | Backpressure | Any destination outage is absorbed by Kafka retention (≥ 24 h configurable). No data loss for the retained window |
| NFR-SEC-01 | AuthN/Z | OIDC SSO, RBAC with resource scopes (tenant, source, pipeline, detection), service accounts for agents with least privilege |
| NFR-SEC-02 | Encryption | TLS everywhere (mTLS between agents/workers and the control plane), encryption at rest in object storage and databases |
| NFR-SEC-03 | Secrets | No secrets in Git. External secret store references (Vault-compatible such as OpenBao, or Kubernetes secrets with SOPS) |
| NFR-SEC-04 | Audit | Immutable audit log of every human and agent action (who, what, before/after, approval), retained ≥ 1 year |
| NFR-SEC-05 | Supply chain | Signed images (cosign), SBOMs, pinned dependencies, SLSA level 2+ builds |
| NFR-AI-01 | Agent safety | Agents run with scoped tool permissions; no free-form shell or network access; changes only through proposals; prompt-injection defences on all data-derived content (log data is untrusted input) |
| NFR-AI-02 | Data residency | Option to run fully air-gapped with local models. PII is masked before any data goes to an external LLM (configurable policy) |
| NFR-AI-05 | MCP security | Follow the NSA MCP security design guidance (May 2026) and the OWASP Top 10 for Agentic Applications: least-privilege tool scopes, approval gates for consequential actions, input/output screening, pinned tool definitions, full audit of tool calls. Third-party MCP servers and skills are treated as supply-chain dependencies (review, pin, scan) |
| NFR-AI-06 | Context efficiency | Tool responses default to a token-bounded size (for example, ≤ 4k tokens) with handles for the rest. Total tool-definition load of the default OSDF agent set stays ≤ 10k tokens through domain split and deferred loading |
| NFR-AI-03 | Observability | Every LLM call is traced (prompt, tools, tokens, latency, cost, model) and linked to the agent run and the proposal |
| NFR-AI-04 | Determinism | Agent output that becomes config is always validated by deterministic tests before a human sees it |
| NFR-TEN-01 | Multi-tenancy | Logical tenant isolation (tenant_id on every record, per-tenant tables/partitions, RBAC). MSSP mode with tenant-scoped content packs |
| NFR-OPS-01 | Deployability | One-command local stack (Docker Compose). Production via Helm on Kubernetes. Single-node "appliance" mode for small sites |
| NFR-OPS-02 | Observability | All services emit OpenTelemetry metrics, logs and traces. A Grafana dashboard ships for each component |
| NFR-OPS-03 | Upgrades | Rolling upgrades of the data plane with no data loss. Config schema migrations are versioned |
| NFR-OPS-04 | GitOps | All config (pipelines, routes, detections, packs, blueprints) lives in Git. The UI is a Git client. Drift between Git and runtime is detected |
| NFR-LIC-01 | Licensing | Runtime dependencies use OSI-approved licenses (Apache-2.0, MIT, BSD, MPL-2.0, LGPL, AGPL/GPL acceptable for separate services). No source-available or BSL/SSPL components on the default path. OSDF code itself is Apache-2.0 |
| NFR-COST-01 | Efficiency | Cost/GB targets: lake storage ≤ object storage cost plus about 10% compute overhead. Documented sizing guide |
| NFR-COST-02 | Transformation efficiency | Pipeline compute ≤ 1 vCPU per 5k EPS for parse + OCSF map + 2 destinations (sustained). Measured and published per pack |
| NFR-COST-03 | No LLM in the per-event path (by default) | Exception: an opt-in, rate-capped, budgeted runtime AI step on low-volume routes only (ai-data-optimization.md, mode D). LLMs run only at design time (generating parsers, rules and reductions) and per alert or question, never per event. Runtime transformation is deterministic VRL/OTTL. This keeps transformation cost linear in CPU and not in tokens |
| NFR-COST-04 | LLM spend control | Per-agent and per-tenant token budgets, caching, smaller or local models for routine steps. Agent cost is reported in the cost ledger (FR-CST-12) |
| NFR-COST-05 | Right-sized footprint | A single-node appliance runs ≤ 50 GB/day on ≤ 16 vCPU / 64 GB RAM. Optional components (Trino, Temporal, Flink) can be disabled for small installs |

---

## 7. Data and content standards

- **Schema:** OCSF (current stable 1.x). Store the `ocsf_version` on every event.
- **Detections:** Sigma rules spec v2 + Sigma correlation rules + OSDF
  extension fields under `x-osdf`.
- **Threat intel:** STIX 2.1 / TAXII 2.1. MITRE ATT&CK through its STIX bundle.
- **Telemetry:** OpenTelemetry (OTLP) for platform self-observability and
  as a log ingest protocol.
- **Fleet management:** OpAMP (OpenTelemetry agent management protocol).
- **Agent tools:** Model Context Protocol (MCP), current spec revision
  (2026-07-28 at the time of writing), with tools, resources, prompts, async tasks and elicitation.
- **Agent procedures:** the Agent Skills format (`SKILL.md`, agentskills.io).
- **Agent-to-agent:** A2A protocol (Linux Foundation) with signed agent cards.
- **Agent telemetry:** OpenTelemetry GenAI semantic conventions.
- **Table format:** Apache Iceberg (v2+), Parquet files, with an Iceberg REST catalog.

---

## 8. MVP definition (what "initial implementation up and running" means)

> **Superseded for scope and priority by [`mvp-scope.md`](mvp-scope.md)**:
> an MVP with a full user experience, on a single hosting platform, with
> OpenTelemetry-first ingestion and the connectors framework. The list below
> is kept as the original technical baseline.

The MVP is done when, on one machine with `docker compose up`:

1. Syslog, file and HTTP sources flow through Kafka into a pipeline worker.
   The worker parses at least **3 source types** (Linux auth/sshd, Windows
   Security events as JSON, AWS CloudTrail) into **OCSF**, and writes to
   **ClickHouse** (hot) and **Iceberg on S3-compatible storage**
   (bronze/gold).
2. Pipelines, routes and parsers are YAML in Git. `osdf test` runs the
   fixtures, and `osdf deploy` hot-reloads the workers.
3. At least **10 Sigma rules** compile to ClickHouse SQL, pass CI tests, run on
   a schedule, and write alerts to an `alerts` table plus a webhook.
4. The **onboarding agent** takes a sample of a new log type and opens a PR with a
   working parser, OCSF mapping and tests that pass CI.
5. The **detection agent** turns an ATT&CK technique ID or a short CTI text
   into a Sigma rule with tests in a PR.
6. The **triage agent** annotates each new alert with a verdict, confidence
   and evidence. An analyst can mark agree/disagree in a minimal UI.
7. The **search agent** answers natural-language questions with SQL over hot
   and warm data.
8. **Domain MCP servers** (`osdf-data`, `osdf-alerts`, `osdf-detect`,
   `osdf-cost`) expose the tools above through the **MCP gateway** with
   per-agent identity and audit. **Five Agent Skills** ship in a pack. An
   **external MCP client** completes a triage task and a cost-review task using
   them. An eval harness reports accuracy per agent.
9. Grafana shows source health (silent-source alert), volume in/out
   (reduction %) and pipeline errors.
10. **Cost reduction is measurable end to end:** a rate card is configured; the
    cost ledger records baseline and actual bytes per source/route/destination;
    a **savings dashboard** shows GB/day and $/month saved; and the **cost
    optimization agent** opens at least one reduction PR with a what-if
    simulation and a passing detection-safety check.

## 9. Success metrics

| Metric | MVP target | v1 target |
|---|---|---|
| Time to onboard a new standard log source | < 1 hour with the agent | < 15 min |
| Agent-generated parser passes tests on first PR | ≥ 60% | ≥ 85% |
| **Total cost of security data management vs baseline** (SIEM ingest + storage + pipeline compute + pipeline licenses + OSDF's own infra) | ≥ 25% lower on pilot sources | **≥ 40% lower** |
| SIEM-bound volume reduction on reference dataset | ≥ 30% | ≥ 50% |
| Detection coverage lost because of reduction | 0 techniques | 0 techniques |
| Storage compression ratio (raw text → Parquet/ZSTD) | ≥ 8× | ≥ 12× |
| Pipeline compute cost per TB processed | Measured and published | ≤ commercial-tool equivalent infra cost |
| Engineer hours per new source onboarded | ≤ 50% of baseline | ≤ 20% of baseline |
| Savings attributable to a specific source/route | 100% | 100% |
| Triage agent precision on labeled benign alerts (auto-close candidates) | ≥ 90% | ≥ 97% |
| False-negative rate of triage on labeled malicious alerts | ≤ 5% | ≤ 1% |
| NL→SQL execution accuracy on eval set | ≥ 70% | ≥ 90% |
| Detection rules with passing tests | 100% | 100% |

## 10. Open questions

0. **What is the cost baseline?** We need the SIEM pricing model (ingest $/GB,
   workload/compute units, or an enterprise flat license), current GB/day per
   source, retention requirements (compliance), and the current pipeline tool
   license cost. The pricing model decides which levers matter most. Under
   ingest pricing, volume reduction dominates. Under workload pricing, moving
   searches and detections to the lake matters more.

1. Is multi-tenancy (MSSP) a v1 requirement or v2? It affects table layout
   and RBAC from day one.
2. Which external SIEMs must be deploy targets first (Splunk, Sentinel, Elastic)?
3. Do policies allow sending security data to hosted LLM APIs, or must the
   system run on local models only? This drives GPU sizing.
4. Should we build a native UI in v1, or rely on Grafana plus a thin React app?
5. Must streaming detections handle stateful correlation in v1 (which needs
   Flink or similar), or are scheduled SQL correlations enough?
