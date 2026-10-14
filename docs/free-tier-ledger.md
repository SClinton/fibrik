# Free-Tier Ledger

- Status: Started 2026-10-14 (week 1, day 1)
- Owner: project maintainers
- Implements: [`zero-cost-mvp.md`](../zero-cost-mvp.md) §1 rule 2, §7 and §9;
  [`initial-stack.md`](../initial-stack.md) §9 day 1

This ledger tracks every account, allowance, budget alert and credential that
the $0 MVP uses. **Target spend: $0.00.** Free tiers change without notice, so
each allowance is recorded twice: what our docs assumed, and what the
provider's own page said when we checked. If the two disagree, the confirmed
value wins and the design is re-checked against it.

Never put secret values in this file. Record only *where* a credential is kept.

## 1. Accounts

| Account | Purpose | Plan | Created | Created by | Billing card on file | Status |
|---|---|---|---|---|---|---|
| GitHub account `SClinton` | Source, issues, Actions, GHCR (`ghcr.io/sclinton/*`), Pages (`sclinton.github.io/fibrik`) | GitHub Free (public repos) | Existing | SClinton | | Active |
| Oracle Cloud tenancy | Primary MVP host (Ampere A1 + k3s) | **Free Tier only, never upgraded** | | | Yes (verification only) | Not created |
| Google AI Studio / Gemini API | First LLM provider (synthetic data only) | Free tier, **no billing account linked** | | | No | Not created |
| Google Cloud (storage test source) | GCS ingestion tests | Always Free | | | | Later (weeks 4–7) |
| AWS (storage test source) | S3 ingestion tests | Free plan, closes at 6 months | | | | Later (weeks 4–7) |
| Azure (storage test source) | Blob ingestion tests | Free account | | | | Later (weeks 4–7) |

### GitHub repositories

All Fibrik repositories, images, packages and sites live under the
`SClinton` personal account. There is no GitHub organization.

| Repo | Purpose | Visibility | Status |
|---|---|---|---|
| `SClinton/fibrik` | Platform code, Helm chart, specs | Public | Exists |
| `SClinton/fibrik-content` | Pipelines, detections, Agent Skills content | Public | Not created |
| `SClinton/fibrik-connectors` | Community connector registry | Public | Not created |

## 2. Allowances

Check each row against the provider's page at sign-up and fill in the
"Confirmed" columns. Re-check at every milestone (§5).

| Provider | Resource | Assumed in docs | Confirmed value | Confirmed on | Source |
|---|---|---|---|---|---|
| OCI | Ampere A1 compute | 2 OCPU / 12 GB (some tenancies 4 / 24) | | | https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm |
| OCI | Block storage (boot + block volumes) | ~200 GB total | | | same |
| OCI | Object storage (S3-compatible API) | Free allowance, size to confirm | | | same |
| OCI | Outbound data transfer | Free allowance, size to confirm | | | same |
| OCI | Idle reclamation rule | < 20% CPU, network and memory at p95 over 7 days | | | same |
| Gemini API | Flash requests per minute / per day | Free tier, limits to confirm | | | https://ai.google.dev/gemini-api/docs/rate-limits |
| Gemini API | Flash-Lite requests per minute / per day | Free tier, limits to confirm | | | same |
| Gemini API | Data use on free tier | May be used to improve Google products: **synthetic data only** | | | https://ai.google.dev/gemini-api/terms |
| GitHub | Actions minutes (public repos) | Unlimited on standard runners | | | https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions |
| GitHub | GHCR storage and bandwidth (public images) | Free | | | https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-packages/about-billing-for-github-packages |
| GitHub | Pages | 1 GB site, ~100 GB/month soft bandwidth | | | https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits |

## 3. Budget alerts

Every account with a payment method gets a **$1 monthly budget alert**. An
account with no payment method can't be billed; record that instead.

| Account | Alert type | Amount | Thresholds | Notifies | Set on | Verified (test email received) |
|---|---|---|---|---|---|---|
| Oracle Cloud | Budget on the root compartment | $1 / month | Actual 100%, forecast 100% | | | |
| GitHub `SClinton` | Budgets for Actions, Packages, Codespaces | $0, "stop usage" on | Alert at 100% | | | |
| Google (AI Studio project) | Not billable while no billing account is linked | — | — | — | | |

## 4. Credentials register

| Credential | Used by | Stored in | Rotation | Created on |
|---|---|---|---|---|
| Gemini API key | LiteLLM in `fibrik-api` (later) | Password manager now; SOPS + age in Git once the chart needs it | Every 90 days or on exposure | |
| OCI API signing key (for OpenTofu) | `deploy/tofu/oci` (day 4) | Password manager / local `~/.oci`, never in Git | On maintainer change | |

## 5. Review log

Review all allowances at each milestone, and quarterly after the MVP.

| Date | Reviewer | Spend to date | Changes found | Action taken |
|---|---|---|---|---|
| | | $0.00 | | |

## 6. Upgrade policy

- No account is upgraded from its free plan without a recorded decision
  (ADR) naming who approved it and the expected monthly cost.
- OCI: upgrading to pay-as-you-go removes idle reclamation but makes the
  tenancy billable. Don't do it without the $1 budget alert verified first.
- Google: don't link a billing account to the AI Studio project. Linking one
  moves the key to paid rates.
