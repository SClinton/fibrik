# Connectors Framework: extensible, community-built, low effort

- Status: Draft v0.1
- Date: 2026-10-14
- Related: [`mvp-scope.md`](mvp-scope.md) (ADR-19: OpenTelemetry-first ingestion), [`requirements.md`](requirements.md) §5.1

## 1. Goals

1. **Most connectors need no code.** A community member should be able to add
   a new source by writing **one YAML manifest + sample data**, in an
   afternoon, without knowing Go, Kubernetes or Fibrik internals.
2. **One connector package covers the whole job:** collect → parse → normalize to
   OCSF → reduction presets → cost estimate → UI form → tests → docs.
3. **Built on OpenTelemetry**, so the framework reuses the ~100+ existing OTel
   receivers instead of reinventing them. When OTel can't do something, the
   framework provides **generic engines** (HTTP API polling, object storage,
   message queues) that are configured, not coded.
4. **Code is the exception**, with a small, well-documented SDK, plus AI help
   to write it.
5. **Safe to share.** Community connectors are validated, tested, signed and
   sandboxed, with clear trust tiers.

## 2. Connector levels (what you write depends on the source)

| Level | When | What the author writes | Skills needed | Expected share of connectors |
|---|---|---|---|---|
| **L0 Template** | An existing OTel receiver already handles the protocol (syslog, OTLP, HEC, Kafka, files, Windows events, Event Hubs, Pub/Sub…) | `connector.yaml` that references the receiver + parser/mapping + samples | YAML | ~50% |
| **L1 Declarative engine** | REST/GraphQL APIs, object storage buckets, queues: anything that fits a generic engine | `connector.yaml` using the `http_pull`, `object_storage` or `queue` engine (auth, pagination, cursor, formats) | YAML + reading API docs | ~40% |
| **L2 Script** | Odd APIs that need small custom logic (signing, multi-step auth, unusual pagination) | One Python file implementing 2–3 hooks, run in a sandbox by the `http_pull` engine | A little Python | ~8% |
| **L3 Native receiver** | High-throughput or binary protocols | A Go OTel receiver (standard OTel component), added to the OCB distribution | Go + OTel | ~2% |

The **parser + OCSF mapping** part is the same at every level: the Fibrik mapping
DSL (YAML), with optional VRL. The onboarding agent can generate it (FR-AGT-01).

## 3. The connector package

```
connectors/okta-system-log/
  connector.yaml          # manifest: metadata, engine/receiver, config schema, outputs
  parse/
    mapping.yaml          # OCSF mapping DSL (compiled to VRL)
    parser.vrl            # optional, only if the DSL isn't enough
  presets/
    reduction.yaml        # suggested reductions + tier defaults, with expected savings
  samples/
    raw/*.json            # real (sanitized) sample events
    expected/*.ocsf.json  # expected OCSF output (golden files)
  mock/
    responses/*.json      # recorded API responses for offline tests (L1/L2)
  docs/README.md          # setup steps, required permissions, screenshots
  icon.svg
  CHANGELOG.md
```

### 3.1 Manifest example: L1 HTTP API connector (no code)

```yaml
apiVersion: fibrik.connectors/v1
kind: Connector
metadata:
  id: okta-system-log
  name: Okta System Log
  version: 1.0.0
  vendor: Okta
  category: identity
  maintainers: [ "@community-user" ]
  tier: community            # official | verified | community
  ocsf_classes: [3002, 3001, 6003]
spec:
  engine: http_pull
  config_schema:             # JSON Schema → auto-generated UI form + validation
    type: object
    required: [domain, api_token]
    properties:
      domain:    { type: string, title: "Okta domain", examples: ["acme.okta.com"] }
      api_token: { type: string, title: "API token", format: secret }
      poll_interval: { type: string, default: "60s" }
  http_pull:
    request:
      method: GET
      url: "https://{{ config.domain }}/api/v1/logs"
      headers: { Authorization: "SSWS {{ secret config.api_token }}" }
      params: { since: "{{ cursor.last_published | default(now_minus('1h')) }}", limit: 1000 }
    pagination: { type: link_header, rel: next }
    records: "$[*]"                       # JSONPath to the event array
    cursor:
      field: published                    # checkpoint = max(published)
      store: durable                      # survives restarts (OTel storage extension)
    rate_limit: { respect_headers: [X-Rate-Limit-Remaining, X-Rate-Limit-Reset] }
    retry: { on: [429, 500, 502, 503], backoff: exponential, max: 5m }
  outputs:
    source_type: okta:system_log
    topic: "raw.{{ tenant }}.okta-system-log"
  parse:
    mapping: parse/mapping.yaml
  presets: presets/reduction.yaml
  permissions_required: [ "okta.logs.read" ]
  cost_profile: { avg_event_bytes: 1800, typical_events_per_user_day: 40 }
```

### 3.2 Manifest example: L0 OTel receiver template

```yaml
apiVersion: fibrik.connectors/v1
kind: Connector
metadata: { id: paloalto-firewall-syslog, name: Palo Alto NGFW (syslog), version: 1.2.0, category: network, tier: verified }
spec:
  engine: otel_receiver
  otel_receiver:
    type: syslog
    template: |
      syslog/{{ instance }}:
        protocol: rfc5424
        tcp: { listen_address: "0.0.0.0:{{ config.port }}", tls: {{ config.tls | to_yaml }} }
  config_schema:
    type: object
    properties:
      port: { type: integer, default: 6514 }
      tls:  { $ref: "fibrik://schemas/tls" }
  outputs: { source_type: "pan:firewall" }
  parse: { mapping: parse/mapping.yaml }
  presets: presets/reduction.yaml      # e.g. drop "allow" traffic logs to the lake tier
```

### 3.3 L2 script hooks (Python, sandboxed)

```python
# connectors/odd-vendor/hooks.py — loaded by the http_pull engine only if the manifest declares `hooks: hooks.py`
def sign_request(req, config, secrets):      # optional: custom auth/signing
    req.headers["X-Signature"] = hmac_sha256(secrets["key"], req.body_or_url())
    return req

def next_page(resp, state):                  # optional: custom pagination
    token = resp.json().get("meta", {}).get("continuation")
    return {"params": {"continuation": token}} if token else None

def extract_records(resp):                   # optional: custom record extraction
    return resp.json()["data"]["events"]
```

The hooks run in a sandbox with no file system, no outbound network except
through the engine's HTTP client (which enforces the manifest's allowed
hosts), and CPU/memory/time limits. They use pure functions with a
stable, versioned signature.

## 4. Generic engines

All engines run inside the **Fibrik OTel Collector distribution** as custom OTel
receivers (written in Go once, by the core team). That keeps every connector
"an OTel connector", managed over OpAMP like the rest of the fleet.

| Engine | Purpose | Key capabilities |
|---|---|---|
| `otel_receiver` | Wraps any receiver in the distribution | Templated config, schema-driven form, health from receiver metrics |
| `http_pull` | REST/GraphQL polling | Auth (API key, basic, OAuth2 client credentials, JWT, AWS SigV4, Azure AD, Google service account), pagination (link header, cursor, offset, page token), JSONPath extraction, durable cursors, rate limits, retries, allowed-hosts list, optional L2 hooks |
| `object_storage` | **AWS S3, Azure Blob/ADLS Gen2, Google Cloud Storage** | Notification-driven ingest + backfill (see §5) |
| `queue` | Cloud queues/streams not already covered | SQS, Azure Storage Queues / Service Bus, GCP Pub/Sub (pull), with the same formats as `object_storage` |
| `webhook` | Push from SaaS | HTTPS endpoint per connector instance, signature verification (HMAC/JWT), replay protection |

## 5. Cloud storage services as ingestion points (AWS, Azure, Google)

Many security logs land in cloud storage first: CloudTrail, VPC/NSG flow logs,
load balancer and WAF logs, CDN logs, SaaS exports, EDR bulk exports and log
archives. The `object_storage` engine makes all three clouds first-class
ingestion points.

| | **AWS S3** | **Azure Blob Storage / ADLS Gen2** | **Google Cloud Storage** |
|---|---|---|---|
| New-object notification | S3 Event Notifications → SQS (directly or via SNS/EventBridge) | Event Grid `BlobCreated` → Storage Queue or Event Hubs | Pub/Sub notifications for Cloud Storage (`OBJECT_FINALIZE`) |
| Auth (preferred) | IAM role (IRSA / Pod Identity); cross-account `AssumeRole` with external ID | Entra Workload ID / managed identity; SAS only as a fallback | Workload Identity / service account impersonation |
| Backfill | List by prefix + time window | List by container/prefix + time window | List by prefix + time window |
| Typical sources | CloudTrail, VPC Flow Logs, ALB/NLB, CloudFront, WAF, GuardDuty exports, Security Lake (OCSF Parquet) | Activity/Diagnostic logs archive, NSG/VNet flow logs, Defender exports, Entra exports | Cloud Audit Logs sinks, VPC Flow Logs sinks, Cloud Armor, SCC exports |
| MVP priority | **Must** | **Must** | **Must** |

### 5.1 Engine capabilities (FR-CON-OBJ)

| ID | Requirement |
|---|---|
| FR-CON-OBJ-01 | **Notification mode** (default): consume the provider's notification queue, fetch new objects, process them, then acknowledge. **Polling mode** fallback (list by prefix with a high-water mark) where notifications can't be configured |
| FR-CON-OBJ-02 | **Backfill**: ingest a historical time range or prefix, with throttling, progress reporting in the UI, and cost estimate (GET/LIST request cost + egress) before starting |
| FR-CON-OBJ-03 | **Formats**: NDJSON, JSON arrays with a records path (for example CloudTrail `Records[*]`), CSV/TSV with header detection, space-delimited (for example VPC/ALB logs), Parquet (for example Security Lake), Avro; compression: gzip, zstd, snappy, bzip2, zip |
| FR-CON-OBJ-04 | **Exactly-once-ish**: object-level checkpoints (bucket, key, etag/version, byte offset), so re-delivered notifications don't duplicate events, and large objects resume after a crash |
| FR-CON-OBJ-05 | **Large-object streaming**: stream-decompress and split without loading whole objects into memory. Parallel fetches with a configurable concurrency |
| FR-CON-OBJ-06 | **Filters before download**: prefix/suffix/regex on keys, and size limits, so unneeded objects are never fetched (saves cost) |
| FR-CON-OBJ-07 | **Cross-account / cross-subscription / cross-project** access using the platform's workload identity and role assumption. No static keys by default |
| FR-CON-OBJ-08 | **Region awareness**: warn when the bucket is in a different region or cloud than the collector (egress cost), and show the estimated monthly egress in the connector form |
| FR-CON-OBJ-09 | **Setup helper**: the UI generates the notification/IAM setup for each cloud (OpenTofu snippet + CLI commands + least-privilege policy JSON) |
| FR-CON-OBJ-10 | **Post-ingest actions** (optional): tag, move or delete processed objects, if the customer wants Fibrik to own a landing bucket |

Build note: check the existing OTel contrib receivers for S3 and Azure Blob
(their stability levels and feature coverage) before you build. Reuse or
contribute upstream where they fit. Build the Fibrik `object_storage` receiver
for the gaps (notification handling for all three clouds, formats,
checkpoints, backfill), with one code path and three provider adapters.

### 5.2 Connector packs built on this engine (MVP)

| Pack | Cloud | Priority |
|---|---|---|
| `aws-cloudtrail-s3` | AWS | Must |
| `aws-vpc-flow-s3` | AWS | Must |
| `azure-activity-blob` (Activity/Diagnostic logs archive) | Azure | Must |
| `azure-flow-logs-blob` (NSG/VNet flow logs) | Azure | Should |
| `gcp-audit-gcs` (Audit Logs sink) | Google Cloud | Must |
| `gcp-vpc-flow-gcs` | Google Cloud | Should |
| `generic-ndjson-bucket` / `generic-csv-bucket` | All three | Must |
| `aws-security-lake-parquet` (already OCSF) | AWS | Should |

## 6. Developer experience: the "no heavy lift" path

### 6.1 Tooling
```bash
fibrik connector new okta-system-log --engine http_pull   # scaffold from a template
fibrik connector new --from-openapi okta-openapi.yaml     # draft a manifest from an OpenAPI spec
fibrik connector new --from-sample events.json            # AI drafts mapping.yaml from samples
fibrik connector validate                                 # schema, references, secrets hygiene
fibrik connector test                                     # offline: mock responses → parse → OCSF golden files
fibrik connector run --live --config dev.yaml             # local run in Compose against the real API
fibrik connector package && fibrik connector publish        # sign and open a PR to the registry
```

- **Local dev in one command:** `fibrik dev up` starts a minimal stack (collector +
  Kafka + Vector + ClickHouse + UI) on a laptop. The connector appears in the
  local UI catalog with its generated form.
- **Generated UI:** the form, validation, help text and secret handling come
  from `config_schema`. Authors never write frontend code.
- **Offline tests by default:** recorded mock responses or sample objects, so
  CI doesn't need vendor credentials. A `--record` mode captures responses
  (with secrets/PII scrubbing) from a real run.
- **AI assistance:** the `build-connector` Agent Skill and the onboarding
  agent read the vendor's API docs, OpenAPI spec or sample events. They draft
  the manifest, mapping, fixtures and README as a PR, and the human reviews it.
  This is the same proposal flow as the rest of Fibrik.
- **Docs:** a 15-minute tutorial per level, a cookbook (pagination patterns,
  auth types, formats) and a gallery of reference connectors.

### 6.2 Community registry and governance

| Aspect | Design |
|---|---|
| Registry | A public Git repo (`fibrik-connectors`) + an index published as an OCI artifact. Self-hosted mirrors are supported for air-gapped customers |
| Trust tiers | **Official** (core team maintains them), **Verified** (passed review and conformance, with a named maintainer and SLA for fixes), **Community** (passes automated checks). The UI shows the tier, and admins can restrict installs by tier |
| Automated CI for every PR | Manifest lint, JSON-Schema validation, offline tests, OCSF validation of golden outputs, secret scanning, license check of samples, sandbox test for L2 hooks, size/performance smoke test |
| Signing | Sigstore/cosign signatures on released packages. The platform verifies them before install |
| Versioning | SemVer. Manifest `apiVersion` compatibility matrix. Deprecation warnings in the UI. Upgrades arrive as proposals with a diff |
| Ownership | `maintainers` in the manifest; CODEOWNERS; stale-connector policy (unmaintained ones move to Community after N months without fixes) |
| Contribution recognition | Contributor credits in the catalog UI. "Good first connector" issues seeded from a most-wanted list |
| Telemetry back to authors (opt-in) | Anonymous install counts and error-rate buckets per connector version, so maintainers know what breaks |

### 6.3 Security for community connectors
- L0/L1 connectors are **data, not code**. They are rendered into OTel/engine
  config by the platform, so they can't execute arbitrary code.
- L2 hooks run in a sandbox: no network except through the engine's HTTP
  client restricted to the manifest's `allowed_hosts`, no file system, and resource limits.
- L3 native receivers are only accepted at Official/Verified tier, after code
  review, and ship inside the signed Fibrik distribution.
- Secrets are always references (`format: secret`) to the platform secret
  store, never stored in manifests. CI rejects literals that look like secrets.
- Sample data must be sanitized (CI runs a PII/secret scanner on `samples/`).
- Connector manifests and READMEs are untrusted content for agents. The
  onboarding agent treats them as data (architecture §8.4).

## 7. Functional requirements (FR-CON)

| ID | Requirement | MVP |
|---|---|---|
| FR-CON-01 | Connector package format (`connector.yaml` + mapping + presets + samples + docs) with a published JSON Schema | Must |
| FR-CON-02 | `otel_receiver` engine (L0) for all receivers in the Fibrik OTel distribution | Must |
| FR-CON-03 | `object_storage` engine for **S3, Azure Blob/ADLS Gen2 and GCS** (§5) | Must |
| FR-CON-04 | `http_pull` engine (L1) with the common auth/pagination/cursor patterns | Must (lite: API key, OAuth2 client credentials, link/cursor/token pagination) |
| FR-CON-05 | `webhook` engine | Should |
| FR-CON-06 | `queue` engine (SQS, Storage Queues/Service Bus, Pub/Sub) | Should (the notification queues used by `object_storage` are Must) |
| FR-CON-07 | L2 sandboxed Python hooks | Post |
| FR-CON-08 | UI form generated from `config_schema`, with secret handling, inline validation and a test-connection step | Must |
| FR-CON-09 | `fibrik connector` CLI: new / validate / test / run / package | Must (new, validate, test); Should (run, package, publish) |
| FR-CON-10 | Offline test harness with mock responses and golden OCSF outputs | Must |
| FR-CON-11 | AI-assisted authoring (`build-connector` skill + onboarding agent) | Should |
| FR-CON-12 | Community registry, trust tiers, signing, CI pipeline | Should (registry repo + CI); Post (signing, tiers in UI, telemetry) |
| FR-CON-13 | Connector health in the sources UI (state, lag, cursor position, errors, last success) | Must |
| FR-CON-14 | Cost preview in the connector form (expected GB/day from `cost_profile`, egress estimate for storage connectors) | Must (lite) |
| FR-CON-15 | Setup helper that generates the cloud IAM + notification setup for storage connectors | Should |
| FR-CON-16 | L3 native receiver contribution guide + OCB distribution build pipeline | Post |

## 8. MVP connector catalog (updated)

Combining the OTel receivers (mvp-scope §5.1.1) with the framework:

| Category | Connectors | Level | MVP |
|---|---|---|---|
| Protocols | OTLP, syslog (TCP/UDP/TLS), Splunk HEC, Kafka, filelog, Windows Event Log | L0 | Must |
| **Cloud storage** | **AWS S3, Azure Blob/ADLS Gen2, Google Cloud Storage** (generic + CloudTrail, VPC flow, Azure Activity, GCP Audit packs) | L1 `object_storage` | **Must** |
| Cloud streams | Azure Event Hubs, GCP Pub/Sub, AWS CloudWatch Logs (as OTel receivers) | L0 | Must for the hosting platform's cloud, Should for the other two |
| SaaS APIs | Okta, Entra ID sign-ins (Graph), GitHub audit, Google Workspace | L1 `http_pull` | Should (2 reference connectors are Must, to prove the framework: Okta + GitHub audit) |
| Agents and forwarders | journald, Fluent Forward | L0 | Should |

## 9. Delivery plan inside the MVP timeline (mvp-scope §7)

| Weeks | Work |
|---|---|
| 1–4 | Package format + JSON Schema; `otel_receiver` engine; CLI new/validate/test; offline test harness |
| 4–7 | `object_storage` engine (S3, Blob, GCS) with notifications, formats, checkpoints; storage packs; generated UI forms; connector health |
| 7–10 | `http_pull` engine (lite) + Okta and GitHub reference connectors; cost preview; contribution guide + tutorial |
| 10–13 | Registry repo + CI; `build-connector` skill (Should); setup helper (Should) |
| 13–16 | Community beta: invite 5–10 external contributors to build one connector each, and measure time-to-first-connector (target: ≤ 4 hours for L0/L1) |

**Success metrics:** median time for a new contributor to build and merge an L0/L1 connector ≤ 4 hours; ≥ 90% of MVP-catalog connectors at L0/L1 (no code); ≥ 10 community connectors within 3 months of MVP release.
