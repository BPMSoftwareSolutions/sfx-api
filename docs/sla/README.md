# sfx-api service levels and change admission

**Status:** effective 2026-11-07. [features/README.md](../../features/README.md)'s "Service levels" keeps the
performance strategies and points here for the objectives.

This directory applies sfx-platform's `docs/sla` discipline (at `2df87d8`) to the host. The discipline has five parts:
1. a versioned agreement mirrored by a catalogue with immutable snapshots;
2. an append-only ledger of qualified observations;
3. baselines qualified rather than assumed;
4. deterministic change admission;
5. an audit of the tools that touch the evidence.

| File | Purpose |
| --- | --- |
| [host-sla.md](host-sla.md) | The host's component agreement: scope, definitions, objectives, measurement rules, responses, claims, obligations and the capabilities owed. |
| [slo-catalogue.json](slo-catalogue.json) | The machine-readable objectives, each with the feature scenarios that state its target. |
| [catalogues/](catalogues/) | Retained catalogue snapshots. The current catalogue is byte-identical to its snapshot. |
| [measurement-contract.md](measurement-contract.md) | The observation envelope `sfx-api.sli-observation.v1`, the host build identity and the release-transaction record. |
| [ledger/](ledger/) | Observations projected from the retained record. Corrections append; earlier records are never edited. |
| [baselines/README.md](baselines/README.md) | Which retained records were projected, pinned by commit and SHA-256, and why each is eligible, unverified or not projected. |
| [change-admission.md](change-admission.md) | What counts as a host implementation change, what sfx-api supplies to an assessment, and the candidate on main (`ea4b012`) that no release has carried. |
| [host-primitive-inventory.v1.json](host-primitive-inventory.v1.json) | The host's primitives at `f97bd66`, the last source before the content candidate, and how an extension is qualified. |
| [tool-audit-2026-11-07.md](tool-audit-2026-11-07.md) | Every repository and scratch tool that touched the host's build or evidence, with its status. |

## How it maps to sfx-platform

| sfx-platform `docs/sla` | Here |
| --- | --- |
| `product-contract.md` | Cited, not copied. It is product-wide and governs both repositories. |
| `product-sla.md` | `host-sla.md`. sfx-platform's agreement excludes the API's availability, latency and authentication, and lists what sfx-api owes. |
| `slo-catalogue.json`, `catalogues/` | The same, keyed by the features' `@slo` ids. |
| `measurement-contract.md` | The same envelope, adapted to a host: an API-only environment, a `hostBuild` binding, `quantiles` and `host` attribution. |
| `ledger/`, `baselines/` | The same. Original records are pinned in place by commit and digest rather than copied. |
| `change-admission.md`, `change-admission-policy.v1.json` | Applied, not mirrored: the policy is sfx-embody's. |
| `primitive-inventory.v1.json` | `host-primitive-inventory.v1.json`. |
| `content-delivery-boundary.v1.json` | Cited. sfx-api is its accountable owner. |
| `git-comparison-receipt.md`, `tools/reconcile/`, `tools/slo/` | Not adopted. They are sfx-platform's tools, and here measurement, comparison and reporting must be declared capabilities ([host-sla.md §11](host-sla.md#11-measurement-capabilities-owed)). |
| `scratch-tool-audit-2026-11-07.md` | `tool-audit-2026-11-07.md`. |

## The discipline in practice

1. **A target lives in a feature scenario.** The catalogue mirrors it and names the scenario. A target with no scenario
   is proposed.
2. **Every release is an observation.** A deploy record adds a `release-integrity` observation with the full host build
   identity and the release probe set's responses, sign-in included.
3. **Every latency sample keeps its requests.** A table of percentiles alone is unverified.
4. **Diagnostics are not evidence.** WSL, stand-in kernels and scratch replays never count toward staging.
5. **"Proven" is not "met".** A scenario that once ran is not attainment. Only qualified observations over a window
   are.
6. **Ledger records are immutable.** A correction is a new record with `supersedes`, a reason and a later
   `recordedAt`.
7. **Catalogue changes are versioned.** Any change bumps the version, adds a snapshot, and never re-scores a closed
   window.
8. **No scratch tool produces evidence.** Until the owed capabilities exist, observations are projected by hand from
   retained evidence, and no attainment report is issued.

## What the record shows

No objective is met. The full table is in [host-sla.md §3.3](host-sla.md#33-what-the-record-shows-today); the main
points:
- One observation is eligible: the 2026-10-31 public test.
- `frontdoor-warm-latency` and `sign-in-refused-latency`, which features/README.md marks proven, rest on summaries
  without their requests.
- The ba0cdb4 sample at 22:16 on 2026-11-03 exceeded both latency maxima.
- Two releases ended stranded with sign-in broken: 5eb18bf, and the one `ccb82ed` replaced.
