# Qualification of the retained record

sfx-api's measurements before this agreement live in narrative deploy records under `docs/`. They are not copied here.
Each one is pinned by its commit and the SHA-256 of its committed bytes (`git show <commit>:<path>`). That gives the
byte identity sfx-platform gets by copying its v1 records into `baselines/v1/`, without a second copy that could drift.
Each [ledger](../ledger/) projection cites its source this way.

Qualification was recorded on 2026-11-07. It is not a new measurement, and it makes no attainment claim for any date
before the agreement takes effect.

## Projected

Every source below is pinned at commit `f97bd66d201fae591f7f83f34772f7658cb457ea`.

| Source | SHA-256 | Projections | Disposition | Reason |
| --- | --- | --- | --- | --- |
| `docs/azure-test-2026-10-31/public-test.json` | `f45ffd23…47c9` | `api-availability`, 2 samples | **eligible** | Retained per-check JSON with origin, start time, status, code and client time. The two anonymous checks match the route set. The signed-in checks are outside it. |
| `docs/azure-test-2026-10-31.md` | `ebf9bf37…49df` | `frontdoor-warm-latency` and `sign-in-refused-latency` on `f32450fa` | unverified | Summary figures only, with no per-request record and no sample time. These figures set both targets. |
| `docs/azure-test-2026-11-03.md` | `a3458229…04f7` | on 5eb18bf: `frontdoor-warm-latency`, `sign-in-refused-latency` and `release-integrity`; on ba0cdb4: `frontdoor-warm-latency` at 22:16 and 22:19, and `api-availability` at 22:16; `plan-memory` before and after the 5eb18bf swap | unverified | Summaries at minute precision or with a bound on the time, and no metrics export. The 22:16 sample exceeded both latency maxima, and 4 of its 30 requests were refused by host capacity. Plan memory was 78% before the swap. The ba0cdb4 section names no kernel or bundle pin. |
| `docs/signin-outage-2026-11-05.md` | `ed75ffc9…f87f` | `explicit-failure`; `release-integrity` on `9b626f66…` and on ccb82ed | unverified | The 503 bytes, the swap time of the stranded release and the probe responses of ccb82ed are not retained. The record says itself that the outage window "is not established". |

## Not projected

| Source | Why |
| --- | --- |
| The 2026-11-04 releases `ec953c9`, `2089ecf`, `21e7499` and `db00da1` (`docs/azure-test-2026-11-04.md`, `18c39316…d9ac`) | Each was verified with `GET /sfx/v1/nope` and route probes, with no sign-in. All four precede `24e8d51`, where sign-in broke again, so the record establishes no sign-in outcome for them. Projecting them would score them against a probe set they could not know. 5eb18bf, the stranded release and ccb82ed are projected because the record establishes their sign-in outcome. |
| `2089ecf`'s admission defect (same record) | It let a caller start the coordinator as a run with any `principalId`, and was live from about 17:26 to 17:41 UTC. No objective here covers authority containment, an invariant of the product contract. A candidate objective for it is the owner's call. |
| The T4 payload run `af211d49` and the hosted-execution receipts (`docs/hosted-execution-v4-2026-11-04/`, `docs/hosted-execution-v5-2026-11-04/`) | They are acceptance of the hosted execution profile under its own contract (`features/hosted-execution-profile.feature`), not samples of an objective in this catalogue. |
| `docs/hosted-probe-readback-2026-11-04.json` | The consumer's diagnostics of two unfinished runs. |
| README.md, "Verified" (WSL, stand-in kernels) | Outside the governed environment. These are diagnostics under host-sla.md §4, rule 9. |
| features/README.md, "Service levels" objectives table at `f97bd66` | A table of statuses derived from the records above. It is not evidence itself, and it now points to the catalogue. |

The ledger shows every withheld record and its reason. None of them counts as a good sample or as an exclusion. If a
later qualification finds independent evidence, it appends a correction with that evidence and a new recording time.
It never edits these sources or the earlier projections.
