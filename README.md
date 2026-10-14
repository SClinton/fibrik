# Fibrik

**Open Security Data Fabric for Agentic AI.** Route, reduce and normalize security data with OpenTelemetry, OCSF and MCP. Keep the signal, cut the SIEM cost.

Project name: **Fibrik** (formerly the working name "OpenSOC Data Fabric"). Repository: `SClinton/fibrik`.

This folder holds the research and specification for an open source platform
that offers the core capabilities of four commercial products:

| Product | What it is | What we take from it |
|---|---|---|
| **Cribl** (Stream, Edge, Search, Lake, Copilot, Guard) | A vendor-neutral telemetry pipeline and data management suite | Routing, reduction and transformation pipelines; edge agent fleet; replay from cheap storage; search in place; a control plane for many worker groups |
| **BindPlane** (BindPlane server, BDOT Collector; being acquired by Dynatrace) | An OpenTelemetry-native control plane for large collector fleets, managed over OpAMP; Google's recommended pipeline for SecOps | OpAMP fleet management at large scale, staged rollouts, edge processing with the OTel Collector, full-pipeline blueprints, AI log-type detection and parser assignment, in-stream threat-intel enrichment |
| **Databahn** (Smart Edge, Highway, Cruz, Reef) | A "security data fabric" with AI-assisted data engineering | Agentless collection, schema-drift handling, AI-built parsers and OCSF/ECS mapping, PII masking, a context/graph layer that AI can query |
| **Anvilogic** (AgenticSecOps platform, Armory, Monte Copilot) | An agentic detection engineering and triage layer over existing SIEMs and data lakes | Detection-as-code decoupled from storage, rules compiled to many query languages, MITRE ATT&CK coverage, federated search, onboard/search/detect/investigate agents, blueprints that chain agents |

## Primary use case

**Cut the total cost of managing and transforming security data**: SIEM
ingest and license fees, storage, transformation compute, commercial
pipeline-tool licenses, and the engineering hours spent onboarding and
maintaining sources. The target is ≥ 40% lower net cost against a measured
baseline, with no loss of detection coverage. This is requirement G0 in
`requirements.md`. Cost metering is designed in from the first phase
(architecture §5.7), and the plan delivers measurable savings at milestone M3,
before the detection and agent work.

## Secondary use case

**An agentic-native SOC data platform.** Every capability is exposed through
domain-split **MCP servers** with tools designed for agents. SOC procedures
ship as portable **Agent Skills** (`SKILL.md`). All agents, whether Fibrik's own,
the customer's, third-party assistants or vendor agents over **A2A**, go
through one gateway with per-agent identity, policy, budgets and audit. See
requirements GA and §5.11, and architecture §8.6–§8.11.

## Current direction (latest decisions)

- **MVP = a working product with a UI** on a **single hosting platform**,
  with **OpenTelemetry-first ingestion** and an **extensible, community-friendly
  connectors framework**, including **AWS S3, Azure Blob/ADLS and Google Cloud
  Storage** as ingestion points. See `mvp-scope.md` and `connectors-framework.md`.
- **Portability first:** one Helm chart and multi-arch images run unchanged on
  kind (CI), k3d (Mac mini) and k3s (free cloud VM), using only open interfaces.
  The concrete one-service-per-category stack is in `initial-stack.md`.
- **$0 upfront:** the MVP is built and hosted on free tiers: OCI Always Free
  ARM64 + k3s for processing; **Cloudflare** (Pages for the UI, Workers for
  webhook ingestion, R2, Tunnel, Access) and **GitHub** (Pages for the
  docs/catalog/demo site, Actions, GHCR) for the edge and project
  infrastructure; AWS/Azure/GCP free allowances for storage-ingestion
  tests. See `zero-cost-mvp.md`.
- **AI data optimization:** Gemini (and other LLMs, provider-agnostic) design
  data flows, remove unneeded storage and generate transformations. They act as
  compilers and analysts, never per event. See `ai-data-optimization.md`.
- **Post-MVP:** a SaaS/BYOC hosting model across clouds, and compute offload to
  Snowflake/Databricks. See `saas-byoc-and-compute-offload.md`.

## Documents

1. [`requirements.md`](requirements.md): competitive capability analysis, then
   functional and non-functional requirements (with IDs and MVP priority).
2. [`architecture.md`](architecture.md): the target architecture, the open
   source stack, data flows, agent design and the key decisions.
3. [`execution-plan.md`](execution-plan.md): a phased plan from an empty repo
   to a running MVP on a laptop, then to a production pilot. It includes a
   walking-skeleton `docker compose` setup and exit criteria for each phase.
4. [`mvp-scope.md`](mvp-scope.md): **authoritative MVP scope**. User
   journeys, UX requirements, prioritized requirements (Must/Should/Post),
   single-platform and OTel-first decisions, and a 16-week timeline.
5. [`connectors-framework.md`](connectors-framework.md): the extensible
   connector package format, generic engines (including S3/Blob/GCS
   ingestion), developer tooling and community registry.
6. [`saas-byoc-and-compute-offload.md`](saas-byoc-and-compute-offload.md):
   requirements assessment for managed BYOC hosting on AWS/Azure/GCP/OCI and
   for offloading processing to Snowflake/Databricks (post-MVP).
7. [`zero-cost-mvp.md`](zero-cost-mvp.md): how to build and run the MVP on
   free tiers with $0 upfront cost: platform choice, lean profile memory
   budget, free services, and guardrails against surprise bills.
8. [`ai-data-optimization.md`](ai-data-optimization.md): using Gemini and other
   LLMs to optimize data flows, eliminate unneeded storage and generate
   transformations, without per-event LLM cost.
9. [`initial-stack.md`](initial-stack.md): **the bill of materials**. One
   specific service per category, chosen for portability, with the
   portability proof matrix and a day-by-day plan for the first week.

## Research caveats

- The vendor research uses public material: product docs, release notes,
  press coverage and analyst write-ups, current as of October 2026. Much of
  the Databahn and Anvilogic detail comes from marketing and third-party
  coverage, not technical docs. Numbers such as "50% SIEM volume reduction" or
  "98% triage accuracy" are **vendor claims, not independently verified**.
- Open source projects change licenses (Redis, Elasticsearch, MinIO, Redpanda
  and HashiCorp tools have all done so). Before you adopt anything,
  check every component's license against the policy in `requirements.md`
  (NFR-LIC).

## Sources

- Cribl full-suite reference architecture: https://docs.cribl.io/reference-architectures/reference-arch-full-suite/
- Cribl Edge + Stream overlay architecture: https://docs.cribl.io/reference-architectures/cva-edge-stream-overlay/
- Cribl Functions reference: https://docs.cribl.io/docs/functions
- Cribl Search 4.17.0 release notes (lakehouse engines, AI investigations): https://docs.cribl.io/search/release-notes/release-v4170/
- Cribl Search 4.18.0 release notes (external MCP, Copilot Chat): https://docs.cribl.io/search/release-notes/release-v4180/
- Cribl Copilot press release: https://cribl.io/news/cribl-accelerates-data-management-productivity-with-ai-powered-copilot/
- Futurum on Cribl Guard and agentic roadmap: https://futurumgroup.com/insights/make-it-so-cribl-charts-a-course-for-the-agentic-frontier/
- Virtualization Review on Cribl Notebooks, BYO AI and MCP server: https://virtualizationreview.com/articles/2025/10/15/cribl-expands-ai-capabilities-with-notebooks-byoai-and-standalone-mcp-server.aspx
- BindPlane + OpAMP fleet management walkthrough: https://oneuptime.com/blog/post/2026-02-06-opamp-bindplane-gui-collector-fleet-management/markdown
- BindPlane OTel Collector (BDOT) project: https://awesome.ecosyste.ms/projects/github.com%2Fobserviq%2Fbindplane-otel-collector
- Dynatrace acquisition of BindPlane (NAND Research): https://nand-research.com/dynatrace-extends-observability-platform-with-bindplane-acquisition/
- BindPlane OP GA (TFiR): https://tfir.io/open-source-observability-solution-bindplane-op-now-generally-available/
- Use BindPlane with Google SecOps: https://docs.cloud.google.com/chronicle/docs/ingestion/use-bindplane-agent
- Google SecOps release notes (Data Processing pipelines): https://docs.cloud.google.com/chronicle/docs/release-notes
- BindPlane Pipeline Intelligence press release: https://www.businesswire.com/news/home/20251120235515/en/Bindplane-Rolls-Out-Pipeline-Intelligence-AI-Native-Automation-Frees-Enterprise-Teams-from-Manual-Telemetry-Management-as-AI-Data-Volumes-Explode
- Google SecOps community "What's new" (BindPlane blueprints, Global Intelligence): https://security.googlecloudcommunity.com/what-s-new-in-secops-91/what-s-new-in-google-secops-2026-08-24-8140
- Databahn on Unite.AI (funding, platform): https://www.unite.ai/atabahn-raises-17m-to-redefine-enterprise-data-pipelines/
- Databahn Cruz agentic AI launch: https://bigdatawire.com/this-just-in/databahn-launches-cruz-agentic-ai-to-optimize-and-simplify-data-engineering-and-management
- Blocks & Files on Databahn AI agents: https://blocksandfiles.com/2025/06/30/databahn-ai-agents
- Intellyx on Databahn AI-assisted pipelines: https://intellyx.com/2025/07/04/databahn-ai-assisted-security-log-pipelines/
- Databahn co-founder interview: https://pulse2.com/databahn-ai-profile-nithya-nareshkumar-interview/
- Databahn Highway on Microsoft Marketplace: https://marketplace.microsoft.com/en-us/product/databahnpub1.databahn-highway-ent
- Anvilogic homepage: https://anvilogic.com/
- Anvilogic agentic architecture: https://www.anvilogic.com/agentic-architecture
- Anvilogic AI agents solution guide: https://www.anvilogic.com/solutions/ai-agents-for-the-modern-soc
- Anvilogic detect solution guide: https://anvilogic.com/solution-guide-detect
- Anvilogic Monte Copilot docs: https://public-docs.anvilogic.com/anvilogic-free-trial/monte-copilot
- Anvilogic what's new: https://public-docs.anvilogic.com/whats-new/whats-new
- Anvilogic AI blueprints and federated search: https://techintelpro.com/news/cybersecurity/ai/anvilogic-launches-ai-blueprints-and-federated-search-for-secops
- Airframe third-party analysis of Anvilogic: https://www.airframe.ai/product/anvilogic-com/analysis
- MCP 2026-07-28 spec changes (AAIF migration guide): https://aaif.io/blog/mcp-2026-07-28-whats-changing-and-how-to-migrate
- MCP blog: https://blog.modelcontextprotocol.io/posts/index.xml
- MCP 2026-07-28 breaking changes: https://www.developersdigest.tech/blog/mcp-2026-07-28-breaking-changes
- Agent Skills overview (SKILL.md, progressive disclosure): https://atlan.com/know/ai-agent/ai-agent-skills/what-are-agent-skills/
- SKILL.md adoption across tools: https://noqta.tn/en/news/skill-md-open-standard-30-ai-coding-tools-adoption-2026
- MCP context bloat fixes (tool search, code mode, code execution): https://mcp.directory/blog/mcp-context-bloat-fix-2026-tool-search-code-mode-progressive-disclosure
- A2A protocol architecture: https://tyk.io/learning-center/a2a-protocol-architecture-and-technical-specification/
- Agent protocol stack (MCP, A2A, ACP) 2026: https://zuplo.com/blog/agent-protocol-stack-mcp-a2a-acp-2026
- NSA MCP security design considerations (press release): https://www.nsa.gov/Press-Room/Press-Releases-Statements/Press-Release-View/Article/4496698/
- NSA MCP guidance summary (Reed Smith): https://www.reedsmith.com/our-insights/blogs/viewpoints/102mvg9/nsa-publishes-security-guidance-on-designing-ai-systems-with-model-context-protoc/
- Microsoft Sentinel MCP server GA (Cloud Wars): https://cloudwars.com/ai/general-availability-of-sentinel-mcp-server-represents-shift-toward-agentic-soc-era/
- OCI Always Free resources: https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm
- InfoQ on OCI Always Free changes (Jul 2026): https://infoq.com/news/2026/07/oracle-cloud-free-tier-limits/
- LILAC LLM log parsing with adaptive cache: https://arxiv.org/pdf/2310.01796
- Tenzir FAQ (open source security pipeline reference point): https://docs.tenzir.com/explanations/faqs
