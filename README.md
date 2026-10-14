# Agentic SOC Data Platform — Open Source Specification

Working name: **OpenSOC Data Fabric (OSDF)**.

This folder holds the research and specification for an open source platform
that offers the core capabilities of four commercial products:

| Product | What it is | What we take from it |
|---|---|---|
| **Cribl** (Stream, Edge, Search, Lake, Copilot, Guard) | A vendor-neutral telemetry pipeline and data management suite | Routing, reduction and transformation pipelines; edge agent fleet; replay from cheap storage; search in place; a control plane for many worker groups |
| **BindPlane** (BindPlane server, BDOT Collector; being acquired by Dynatrace) | An OpenTelemetry-native control plane for large collector fleets, managed over OpAMP; Google's recommended pipeline for SecOps | OpAMP fleet management at large scale, staged rollouts, edge processing with the OTel Collector, full-pipeline blueprints, AI log-type detection and parser assignment, in-stream threat-intel enrichment |
| **Databahn** (Smart Edge, Highway, Cruz, Reef) | A "security data fabric" with AI-assisted data engineering | Agentless collection, schema-drift handling, AI-built parsers and OCSF/ECS mapping, PII masking, a context/graph layer that AI can query |
| **Anvilogic** (AgenticSecOps platform, Armory, Monte Copilot) | An agentic detection engineering and triage layer over existing SIEMs and data lakes | Detection-as-code decoupled from storage, rules compiled to many query languages, MITRE ATT&CK coverage, federated search, onboard/search/detect/investigate agents, blueprints that chain agents |

## Documents

1. [`requirements.md`](requirements.md): competitive capability analysis, then
   functional and non-functional requirements (with IDs and MVP priority).
2. [`architecture.md`](architecture.md): the target architecture, the open
   source stack, data flows, agent design and the key decisions.
3. [`execution-plan.md`](execution-plan.md): a phased plan from an empty repo
   to a running MVP on a laptop, then to a production pilot. It includes a
   walking-skeleton `docker compose` setup and exit criteria for each phase.

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
- Tenzir FAQ (open source security pipeline reference point): https://docs.tenzir.com/explanations/faqs
