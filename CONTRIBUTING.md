# Contributing to Fibrik

Thanks for your interest in Fibrik, the Open Security Data Fabric for Agentic
AI. The project is at the **specification stage**. The most useful
contributions right now are reviews of the design, real-world requirements,
and (soon) connectors.

## Ways to contribute

| What | How | Where to start |
|---|---|---|
| **Review the design** | Open an issue or a PR commenting on a specific section | [`requirements.md`](requirements.md), [`architecture.md`](architecture.md), [`mvp-scope.md`](mvp-scope.md) |
| **Share a requirement or use case** | Open an issue describing your SOC data problem, data sources, volumes and SIEM pricing model | Issues → "Use case" |
| **Propose a connector** | Open an issue with the source name, how it delivers data (syslog, API, bucket, webhook…) and a sanitized sample | [`connectors-framework.md`](connectors-framework.md) |
| **Build a connector** | Once the connector CLI ships, most connectors need no code: one `connector.yaml` + mapping + samples | [`connectors-framework.md`](connectors-framework.md) §3 and §6 |
| **Write an Agent Skill** | A `SKILL.md` folder describing a SOC procedure using Fibrik tools | [`architecture.md`](architecture.md) §8.9 |
| **Improve docs** | Fix errors, outdated facts (free tiers, vendor features and specs change often) or unclear wording | Any `.md` file |

## Ground rules

1. **Open source only.** Proposed dependencies must use an OSI-approved license
   that is suitable for SaaS use. No SSPL/BSL components on the default path (see
   `requirements.md`, NFR-LIC).
2. **Portability first.** Core components may depend only on open interfaces
   (Kubernetes, S3 API, Iceberg REST, OTLP, OpAMP, OIDC, MCP). Cloud-specific
   services belong in ingestion connectors or optional add-ons (`initial-stack.md`, §0).
3. **Cost is the primary use case.** Changes should keep transformation cost
   CPU-bound. No per-event LLM calls in the default path (`ai-data-optimization.md`).
4. **No real customer data.** Samples and fixtures must be synthetic or
   sanitized. Never commit secrets, tokens or personal data.
5. **Cite sources** for factual claims about vendors, standards or free tiers,
   and say when a claim is a vendor claim or unverified.

## Making a change

1. Fork the repo and create a branch: `git checkout -b docs/clarify-cost-ledger`.
2. Keep each PR focused on one topic. For design changes, update every
   document the change touches (requirements ↔ architecture ↔ plan) so they
   stay consistent.
3. Significant design decisions get an ADR row in `architecture.md` §11.
4. Open a pull request describing **what** changed and **why**, with links to
   any sources.

## Connector contributions (preview)

When the `fibrik connector` CLI is available, the flow will be:

```bash
fibrik connector new my-source --engine http_pull   # or otel_receiver / object_storage
fibrik connector validate
fibrik connector test                               # offline: samples → OCSF golden files
```

Connectors are reviewed against the checks in `connectors-framework.md` §6.2
and published with a trust tier (official, verified or community).

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
