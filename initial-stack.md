# Initial Stack: one service per category, portability first

- Status: Decided for MVP stand-up (v0.1)
- Date: 2026-10-14
- Implements: [`zero-cost-mvp.md`](zero-cost-mvp.md) (lean profile, $0) and [`mvp-scope.md`](mvp-scope.md)

This is the **bill of materials** for standing up the first running Fibrik
service. There's exactly **one choice per category**. Every choice is judged
first on **portability**: the whole service must move between any
Kubernetes, any cloud or a laptop **without code changes**, only different
values files. If a choice has to change, record an ADR and update this table.

## 0. Portability rules (apply to every choice)

1. **One deployable artifact everywhere:** a single Helm chart of
   multi-arch (arm64 + amd64) OCI images. The same chart runs on the Mac mini, in
   CI and on the free cloud VM. No Compose-only or cloud-only paths.
2. **Only open interfaces between components:** Kubernetes API, S3 API,
   Iceberg REST, OTLP, OpAMP, PostgreSQL wire protocol, ClickHouse SQL/HTTP,
   Prometheus remote write, OIDC, MCP, OCI image/registry spec, Git.
3. **No provider-specific managed services in the core.** Cloud-specific
   services are allowed only as *ingestion sources* (S3, Blob, GCS) or as
   optional add-ons outside the core chart (for example, a CDN or edge workers).
4. **Infrastructure-specific code lives in one place:** OpenTofu modules per
   provider. Nothing in application code or the Helm chart names a cloud.
5. **CI logic in `make` targets.** CI workflow files only call `make`, so the
   CI provider can be swapped.
6. **Proven portability:** every release deploys the same chart to three
   different targets (§8).

## 1. Hosting and infrastructure

| Category | Choice | Portable via | Moves to (no code change) |
|---|---|---|---|
| Compute host ($0) | **Oracle Cloud Always Free: one `VM.Standard.A1.Flex` (2 OCPU / 12 GB), Ubuntu 24.04 arm64** | A plain Linux VM; nothing OCI-specific runs on it | Any VM or bare metal, or the Mac mini |
| Kubernetes distribution | **k3s** | CNCF-conformant Kubernetes | EKS, AKS, GKE, OKE, any conformant cluster |
| Infrastructure as code | **OpenTofu** (OCI module first) | Provider modules isolated under `deploy/tofu/<provider>` | Add an `aws`/`azure`/`gcp` module; the chart is unchanged |
| Application packaging | **Helm chart** (`fibrik`) with profiles `values-free.yaml`, `values-standard.yaml` | Helm + Kubernetes API | Any cluster |
| GitOps deploy | **Flux** | Runs on any cluster, pulls from any Git host | Any cluster / Git host |
| Secrets | **SOPS + age** in Git | Plain files + open tool | Any cluster; swap the age key for a cloud KMS key later without changing the app |
| Persistent volumes | **Kubernetes PVCs** (k3s local-path) | Kubernetes `StorageClass` | Any CSI driver (EBS, Azure Disk, PD, OCI BV) |
| Object storage (lake + archive) | **S3 API**, served by the host cloud's S3-compatible endpoint (OCI Object Storage on the free host) | S3 API + Fibrik storage adapter | Any S3 or S3-compatible store; native ADLS/GCS adapters are post-MVP |
| Backups | **CronJobs: `pg_dump` + `clickhouse-backup` → the same S3 bucket** | S3 API | Any S3 target |

## 2. Network and identity

| Category | Choice | Portable via | Notes |
|---|---|---|---|
| Ingress, TLS, reverse proxy, UI static hosting | **Caddy** (in-cluster; automatic HTTPS with Let's Encrypt; serves the UI build) | Standard HTTP/ACME; a container | Needs a hostname pointing to the VM's public IP, with port 443 open. On the Mac mini, serves `localhost` |
| User SSO (OIDC provider) | **Dex** (in-cluster OIDC provider; GitHub as the first connector) | OIDC; Fibrik only speaks OIDC | Swap the upstream (Entra ID, Google, Okta, LDAP) by Dex config, or point Fibrik at any other OIDC IdP |
| Agent / machine identity | **Fibrik-issued OAuth 2.1 client credentials** (signed JWTs) | OAuth/OIDC standards; MCP authorization | Works for any MCP client |
| Webhook / HTTP ingestion | **Fibrik `webhook` engine inside the OTel collector** | HTTPS + standard signatures | No edge platform required |
| Project site, docs, connector catalog | **MkDocs Material static site** (published to GitHub Pages) | Static files | Any static host |

> **Changed for portability:** Cloudflare Tunnel, Access, Pages, Workers and R2
> are no longer in the initial stack. They remain documented as **optional
> add-ons** ([`zero-cost-mvp.md`](zero-cost-mvp.md) §4a) that can sit in front
> of the portable core without changing it.

## 3. Data plane

| Category | Choice | Portable via |
|---|---|---|
| Collection / connectors | **OpenTelemetry Collector**: custom OCB build `fibrik-otelcol` with Fibrik `object_storage`, `http_pull`, `webhook` receivers | OTLP, OpAMP, standard receivers |
| Fleet management | **OpAMP** (OTel supervisor + Fibrik fleet service on `opamp-go`) | Open protocol |
| Processing (parse, OCSF, reduce, route) | **Vector** | Single binary; config generated from Fibrik YAML |
| Buffering | **Disk buffers** (OTel `file_storage` + Vector disk buffers on PVCs) | Kubernetes PVCs; the Kafka API joins in the standard profile |
| Hot store, search, cost ledger | **ClickHouse** | SQL/HTTP; open source server |
| Lake format + catalog | **Apache Iceberg + Lakekeeper** | Iceberg REST catalog spec; Parquet files on S3 |
| Lake query | **ClickHouse Iceberg table functions** | Any Iceberg engine can read the same tables |
| Control-plane database | **PostgreSQL 17** (official image) | PostgreSQL wire protocol; any managed Postgres later |
| Schema | **OCSF** | Open schema |
| Template mining | **Drain3** | Library |

## 4. Application

| Category | Choice |
|---|---|
| Backend language and API | **Python 3.12 + FastAPI** (OpenAPI spec published) |
| Background jobs | **APScheduler** with a Postgres job store |
| Frontend | **React + TypeScript + Vite + shadcn/ui + Tailwind** (ECharts, Monaco) |
| Iceberg writes | **PyIceberg** |
| CLI | **Typer** (`fibrik …`, `fibrik connector …`) |
| Detection compiler (Should) | **pySigma** → ClickHouse SQL |

## 5. AI and agents

| Category | Choice | Portable via | Notes |
|---|---|---|---|
| LLM access layer | **LiteLLM** (in-process SDK) | One client for 100+ providers, including OpenAI-compatible and local endpoints | Change the model with config, not code |
| First LLM provider | **Google Gemini API** (Flash; Flash-Lite for labeling) | Behind LiteLLM | Free tier with **synthetic data only**. A local Ollama/vLLM endpoint or Vertex AI can be swapped in by config |
| Agent framework | **LangGraph** | Behind the Fibrik agent interface | |
| Tool protocol | **MCP: official Python SDK** | Open protocol; any MCP client | |
| Skills | **Agent Skills (`SKILL.md`)** | Open format; plain folders | |
| LLM and agent tracing | **OpenTelemetry GenAI conventions → ClickHouse** | OTLP | Any OTel backend can receive the same traces |

## 6. Engineering and operations

| Category | Choice | Portable via |
|---|---|---|
| Source control, issues | **GitHub** (public repos) | Git; issues exportable |
| CI | **GitHub Actions calling `make`** | Logic in Makefile + containers, so it can be moved to GitLab CI, Forgejo Actions, etc. |
| Container registry | **GHCR** | OCI registry spec; mirror to any registry |
| Image signing | **cosign** (keyless) | Sigstore standard |
| Platform metrics | **VictoriaMetrics** | Prometheus scrape/remote-write, PromQL |
| E2E tests | **Playwright** | Runs against any deployment URL |
| Local dev (Mac mini) | **k3d** (k3s in Docker) on **Colima** | Same Helm chart as production; no Compose path |
| Kubernetes in CI | **kind** | Conformant Kubernetes in CI for chart tests |
| UX design | **Penpot** | Open source; self-hostable |
| Test data | **OTRF Security-Datasets** + synthetic generators | Open data |

## 7. Storage ingestion test sources (one per cloud)

| Cloud | Service | Free basis (verify) |
|---|---|---|
| Google Cloud | **Cloud Storage (`us-central1`) + Pub/Sub notifications** | Always Free 5 GB in US regions |
| AWS | **S3 + SQS event notification** | New-account free plan credits (≤ 6 months) |
| Azure | **Blob Storage + Event Grid → Storage Queue** | Free account credit + 12-month services |

Each account gets a **$1 budget alert** on day 1.

## 8. Portability proof (CI and release gate)

Every release must pass the same E2E suite (ingest → normalize → cost
overview → recommendation → approve → search → copilot) with the **same chart
and images** on:

| Target | Where | Cost |
|---|---|---|
| **kind** (amd64) | GitHub Actions | $0 |
| **k3d** (arm64) | Mac mini | $0 |
| **k3s** (arm64) | OCI Always Free VM | $0 |

Post-MVP, add a managed Kubernetes target (EKS/AKS/GKE) to the matrix when
paid hosting starts. Only an OpenTofu module and a values file are added, with no
chart or code changes.

## 9. Stand-up order (first week)

| Day | Steps |
|---|---|
| 1 | Create GitHub org + repos (`fibrik`, `fibrik-content`, `fibrik-connectors`), Oracle Cloud (free-only), Google AI Studio key. Set budget alerts. Start `docs/free-tier-ledger.md` |
| 2 | Helm chart skeleton + `make` targets. kind in CI deploys Postgres, ClickHouse, Lakekeeper, VictoriaMetrics, Caddy, Dex. Multi-arch images to GHCR with cosign |
| 3 | Same chart on the Mac mini with k3d. Add `fibrik-otelcol` gateway + Vector + `fibrik-api`. A syslog line lands in ClickHouse and Iceberg (S3 bucket on the dev host: an OCI bucket or any S3-compatible endpoint) |
| 4 | OpenTofu OCI module: VM, volume, bucket, network rules (443 only). Install k3s and Flux; Flux pulls the same chart with `values-free.yaml`. Caddy obtains a TLS certificate |
| 5 | Dex with GitHub login in front of the UI. E2E smoke test passes on all three targets (§8). Docs site live on GitHub Pages |

**Exit for week 1:** identical chart and images running on kind, k3d and
OCI k3s; one event flows OTel → Vector → ClickHouse + Iceberg on each;
sign-in via Dex/GitHub. Total spend $0.00.

## 10. Decision record

- **ADR-23: Portability first for the initial stack.** Core services use
  open interfaces only. One Helm chart and multi-arch images everywhere.
  Cloud- or vendor-specific services are allowed only as ingestion sources or
  optional add-ons. Consequence: Caddy + Dex replace Cloudflare Tunnel/Access/Pages
  in the core, and k3d replaces Compose for local development.
