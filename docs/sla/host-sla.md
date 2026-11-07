# sfx-api host service level agreement

**Status:** governing host component agreement, version 1.0, effective 2026-11-07 at 20:41:59 UTC. **Owner:** sfx-api.

This component agreement sits under the product boundary and lifecycle contract, version 1.1
(sfx-platform `docs/sla/product-contract.md` at `2df87d8`, `sha256:1d8f6f56…439d`). That contract names sfx-api as
the owner of admission at the consumer → host API boundary. sfx-platform's own agreement covers the browser, desktop,
CLI and installer. It excludes "the declared API's availability, latency and authentication decisions (sfx-api)"
(product-sla.md §1) and lists what sfx-api owes (§9). [content-delivery-boundary.v1][cdb] makes sfx-api the
accountable owner of the content delivery host. No tool measures the API origin today. sfx-platform's tracker reads
`apiOrigin` only to validate an environment field (`tools/slo/catalogue.mjs:35`). This agreement fills that gap.

The objectives are mirrored in [slo-catalogue.json](slo-catalogue.json).

**Authority.** In this repo only an approved feature gives a behaviour authority ([features/README.md](../../features/README.md)).
Each objective here names the scenarios that state its target. Where a scenario disagrees with this agreement or the
catalogue, the scenario wins: correct both documents together and bump their versions. The three objectives of §3.1
have no scenario yet. Each derives from the governing document named with it, and its scenarios are written with the
probe capability's feature (§11).

**A target is not a claim that it is met.** Attainment comes only from qualified ledger observations, and it is stated
per objective, source, environment, host build and window. A scenario's `@status:proven` means that a run once showed
the behaviour. It is not attainment.

## 1. Parties and scope

### Covered surfaces (owned by sfx-api)

| Surface | What it includes |
| --- | --- |
| Declared API | Every route the interface declares on the governed origin: refusals, sign-in, session read and revocation, run admission, run streams, run read-back, the estate live channel and the hosted-execution acceptance route. |
| Host build | The image: the facade (`host/serve.py`, `deploy/`), `sfx-api.config.json`, the pinned bundle, the provider authority, the hosted providers, the content provider (`providers/content/`, from `ea4b012`), the copied contracts and the admitted kernel. Its identity is the host build identity (§2). Its primitives are inventoried in [host-primitive-inventory.v1.json](host-primitive-inventory.v1.json). |
| Host release | Each release transaction that binds a host build to the governed site. |
| Content delivery host | Assigned by [content-delivery-boundary.v1][cdb]. It has four operations: issue a private view, redeem a private view, read a document and its declared assets, and resolve a public address. Its candidate is on main at `ea4b012`, committed on 2026-11-06 at 00:01 UTC, before this agreement took effect. No deploy record names it. Its 11 features carry `@approved:2026-11-05`, and all 20 of their scenarios are `@status:unchecked`. Being on main is not admission: its first release is a host implementation change ([change-admission.md](change-admission.md)). Its objectives join under §10 when it is promoted. |

### Governed environment

**staging:** `https://sfx-api-test.azurewebsites.net`. The App Service plan is `ASP-sidefxgroup-ad2e`, P0v3, shared,
with one vCPU ([azure-test-2026-11-03](../azure-test-2026-11-03.md)). WSL runs, stand-in kernels and scratch replays
form a separate environment that is not governed. Their results are diagnostics and never count toward the governed
summary. Declaring a production environment is a change under §10.

### Not covered

Exclusions do not cancel delivery obligations under the product contract.

- sfx-platform's surfaces: the hosted browser, the desktop, the installed CLI and installer publication.
- The kernel's mechanics (scenario-driven-architecture).
- The estate's declarations, its lifecycle and the accepted-change register (sfx-embody).
- Identity facts (sfx-dal).
- Provider effects implemented outside this repo (sfx-providers).
- Azure App Service itself. An outage it causes is excluded only with attribution evidence that matches the sample.
  A container start that the host pays for is the host's own failure, as on 2026-11-03.
- Demo capabilities.

## 2. Definitions

**Host-attributed failure.** A request the host did not answer as declared. That covers a timeout, a connection
failure, a generic or blank 5xx, or an unexpected status or code. It also covers a refusal caused by the host's own
capacity (`REQUEST_KERNEL_BUSY`, or a 503 while its container starts), and a named dependency failure when the record
shows the dependency was healthy.

**Named refusal.** A response with an uppercase code that names the unavailable operation. The host's recorded
examples are `OPERATION_NOT_DECLARED`, `CALLER_REQUIRED`, `LOGIN_INPUT_INVALID`, `AUTHENTICATION_REJECTED`,
`REQUEST_KERNEL_BUSY`, `ADMISSION_REQUEST_PATH_ONLY` and `ACCEPTANCE_BUSY`.

**Host build identity.** Five values: `sourceCommit`, `imageDigest`, `bundlePin`, `kernelDigest` and
`hostFilesDigest`.
- `bundlePin` is the manifest's SHA-256 (base64) that the provider authority pins.
- `hostFilesDigest` is the "Host files" digest that `tools/prepare-hosted-image.ps1` prints from the verified build
  context. From `ea4b012` that digest also covers `providers/content/package.py` and
  `providers/content/requirements.txt`, so digests from before and after that commit are not computed over the same
  files.

**Release transaction.** One attempt to serve a new image on the governed site. It starts when `SFX_API_IMAGE_DIGEST`
is set, "the deployer's record of the image" ([azure-test-2026-11-04](../azure-test-2026-11-04.md)). It ends when the
release probe set has passed on the new digest, or when the previous digest serves again.

**Release probe set.** Every route of `api-availability`. Every release therefore probes a sign-in through
`open-api-session`, because "a frontdoor probe passes while sign-in is down"
([signin-outage-2026-11-05](../signin-outage-2026-11-05.md)).

**Stranded release.** A release transaction that ends with the site serving a digest that failed or skipped the release
probe set and was not restored. Fixing forward with a later release does not unstrand it.

**Sample.** For a bound objective, one run of the measurement its unit states, for example 30 sequential requests. Each
request's time is retained. A summary of percentiles without the requests behind it is not a sample.

**Window.** Rolling 30 or 90 days, evaluated at the report's as-of time.

**Observation.** An immutable record under the [measurement contract](measurement-contract.md).

## 3. Objectives

### 3.1 Derived from the governing documents

None of these three has a scenario yet. Each follows from the source named with it, and its windows are the platform's
for the same kind of objective.

| ID | Objective | SLI | Target | Window |
| --- | --- | --- | --- | --- |
| `api-availability` | API availability | Correct answers ÷ (correct answers + host-attributed failures) over the anonymous route set | ≥ 99.5% | 30 days |
| `explicit-failure` | Explicit failure | Failures answered with a named refusal whose named cause holds ÷ failures observed | 100% | 30 days |
| `release-integrity` | Release integrity | Release transactions ending accepted or restored ÷ release transactions | 100% | 90 days |

**`api-availability`**
- **Unit:** one probe sample of one route on the governed origin:
  - `GET /sfx/v1/nope` → 404 `OPERATION_NOT_DECLARED`;
  - `GET /sfx/v1/session` with no caller → 401 `CALLER_REQUIRED`;
  - `POST /sfx/v1/session` with an empty identifier → 400 `LOGIN_INPUT_INVALID`;
  - `POST /sfx/v1/session` with an identifier no principal has → 401 `AUTHENTICATION_REJECTED`;
  - `POST /sfx/v1/hosted-execution/acceptance` with no caller → 401 `CALLER_REQUIRED`.
- **Probe rules:** the probe never signs in with a real identity. Every route, including the sign-in refusals, goes
  through the same declared capabilities that a real caller's request does.
- **Good:** the expected status and code, within `request-answer-bound`.
- **Bad:** any host-attributed failure.
- **Excluded:** a named refusal with independent attribution evidence. That evidence must name the dependency's owner
  and match the sample's route and time. A code alone is not attribution.
- **Deploy windows are not excluded.** The 50 s outage of the 2026-11-03 swap spends this budget.
- **Basis for 99.5%:** the hosted browser holds PLT-BROWSER-AVAILABILITY at 99.5% over 30 days, and it depends on this
  API for sign-in, sessions and runs. The API must hold at least as much. No measurement of the API origin exists yet.
- **Route set:** the routes the deploy records already probe, plus the sign-in refusal through `open-api-session`.
  The 2026-11-05 outage showed that a frontdoor probe alone passes while sign-in is down.
- **Measurement status:** not built (§11).

**`explicit-failure`**
- **Unit:** one observed failure of a request to the declared API.
- **Good:** a named refusal whose named cause the record does not contradict.
- **Bad:** a generic or blank error, a timeout with no code, a substituted result, or a code that blames a dependency
  shown to be healthy.
- **Why the "named cause holds" condition:** [content-delivery-boundary.v1][cdb], which governs sfx-api, requires "a
  named failure with correlation and responsible owner". The platform's looser definition, under which any named
  refusal counts as good, covers the platform's surfaces. On 2026-11-05, sign-in answered `503 IDENTITY_UNAVAILABLE`
  while the identity service answered every live check. The cause was the host's own bundle.
- **Measurement status:** not built. Failures found in acceptance or reported as defects are recorded by hand.

**`release-integrity`**
- **Unit:** one release transaction.
- **Good:** one of two endings.
  - The new digest serves, it passed the release probe set, and its full host build identity is retained.
  - The previous digest was restored.
- **Bad:** a stranded release.
- **Basis:** two stranded releases. 5eb18bf served sign-in broken from 2026-11-03, and so did the releases built from
  `24e8d51` or later, until `ccb82ed`. Each passed a frontdoor-only probe.
- **Measurement status:** manual. Each deploy record under `docs/` states its swap and probes.

### 3.2 Stated by feature scenarios

These ids are the `@slo` ids that the features use. The target, unit and baseline of each are in the catalogue,
together with the scenarios that state it. No feature states a window, so each takes the platform's 90-day window for
objectives measured by sample or acceptance, with the "every qualified sample" rule of PLT-RELEASE-RECOVERY.

The two status columns use different vocabularies:
- **Measurement status** is how the SLI is measured today: `manual`, `declared` (a declared limit that no observation
  checks), `diagnostic-only` (outside the governed environment), `acceptance-only` or `not-built`.
- **features/README.md** is the scenario status that README's service-level table records.

| ID | Target | Measurement status | features/README.md |
| --- | --- | --- | --- |
| `frontdoor-warm-latency` | p50 ≤ 0.88 s, p95 ≤ 3.35 s per sample | manual | proven |
| `frontdoor-tail-explained` | every warm request over 1.05 s names its cause (proposed) | not-built | not-built |
| `warm-definitions` | 0 declaration reads per warm envelope | diagnostic-only | probed |
| `request-answer-bound` (SLA) | every request answered within 230 s | declared | installed |
| `no-kernel-start-on-request` | 0 kernel starts paid by a request after listening | manual | proven |
| `abandoned-request-release` | kernel released when the client goes (proposed) | not-built | not-built |
| `session-setup` | ≤ 0.34 s per envelope, until KV-001 | diagnostic-only | probed |
| `dispatched-request-latency` | unset; set from its first baseline | not-built | not-built |
| `sign-in-refused-latency` | 400 within 0.47 s | manual | proven |
| `sign-in-latency` | unset | not-built | not-built |
| `run-event-delivery` | events as observed; keep-alive within 15 s | diagnostic-only | probed |
| `session-recheck` | every 5000 ms, once per session | diagnostic-only | probed |
| `channel-batch` | ≤ 200 events and 1 MiB | declared | installed |
| `channel-retention` | ≤ 20000 frames and 32 MiB | declared | installed |
| `trace-chunk` | ≤ 2000 events and 524288 bytes | acceptance-only | proven |
| `run-events-bound` | ≤ 50000 events; ≤ 1 MiB per observation | declared | installed |
| `run-capacity` | 2 executing, 64 waiting (64 proposed) | declared | installed (2), not-built (64) |
| `plan-memory` | ≤ 64% (proposed) | manual | probed |
| `drawing-poll` | every 2000 ms, ≤ 20 changes | declared | installed |

### 3.3 What the record shows today

The [ledger](ledger/) projects every retained measurement behind these objectives. Each projection carries its
qualification ([baselines/README.md](baselines/README.md)). Under §4, here is what each objective can claim:

| Objective | Qualified evidence | Status |
| --- | --- | --- |
| `api-availability` | 1 eligible record (2 of 2 good, 2026-10-31); 1 unverified record (4 of 30 refused by host capacity, 2026-11-03 22:16) | incomplete |
| `explicit-failure` | 1 unverified bad record (2026-11-05) | incomplete |
| `release-integrity` | 3 unverified records: 5eb18bf bad, `9b626f66…` bad, ccb82ed good. Other releases from `24e8d51` on are unidentified. | incomplete |
| `frontdoor-warm-latency` | 4 unverified samples. The ba0cdb4 sample at 22:16 had p50 1.35 s and p95 3.63 s, above both maxima. | incomplete |
| `sign-in-refused-latency` | 2 unverified figures | incomplete |
| `plan-memory` | 2 unverified readings: 78% on a57ebba before the 5eb18bf swap (over 64%), 60% after it | incomplete |
| every other objective | none on the governed environment | unevaluated |

No objective is met. None can be called breached either, because no failure is qualified. features/README.md marks
`frontdoor-warm-latency` and `sign-in-refused-latency` proven, and that is attainment the record cannot support. The
README cites only the 5eb18bf sample, and its "proven" status omits the 22:16 sample that exceeded both maxima.

## 4. Measurement rules

Rules 1 to 7 are sfx-platform's (product-sla.md §4) applied to this host. Rules 8 to 10 are this agreement's own.

1. **Denominators are fixed in advance.** The unit is defined in §3 and in the catalogue. Splitting units, omitting
   difficult samples or excluding them afterwards is prohibited.
2. **Missing evidence is not success.** Missing coverage or unverified evidence reports *incomplete*. A group with no
   applicable observation reports *unevaluated*. Neither is *met*.
3. **Attribution is separate from explicitness.** A named code does not prove its cause. Exclusions need an owner, a
   reason and independent evidence. Corrections append a new observation with `supersedes` and never edit the old one.
4. **Sources and environments are separate.** Each ratio or bound is scoped to one objective, one source, one exact
   environment target set and one catalogue revision. Results from WSL or a stand-in never pool with staging.
5. **Event time and knowledge time differ.** `observedAt` selects the window; `recordedAt` decides what a report knew at
   its as-of time. When a record keeps only a bound on the event time, the observation states which bound it is and is
   unverified.
6. **Baseline evidence needs qualification.** Original records stay byte-identical at their pinned commit. Each
   projection cites those bytes and a reason ([baselines/README.md](baselines/README.md)).
7. **Reports are reproducible.** A report binds the catalogue digest, its as-of time and the digests of its inputs.
8. **Every observation binds the host build it measured.** Attainment is also stated per build, so a release that
   regresses a bound is visible against its digest. A null field in the build identity makes the observation
   unverified.
9. **A diagnostic is not evidence.** Scratch replays, stand-in kernels and WSL runs locate causes. They do not establish
   that the governed host met a target. This repo's records already say this of their own replays
   ([azure-test-2026-11-04](../azure-test-2026-11-04.md)).
10. **Measurement is declared.** The probes, the samplers and the ledger check are declared capabilities. A script in
    a scratch folder, or another repository's tool run from here, produces no evidence (§11). Until those capabilities
    exist, observations are projected by hand from retained evidence, and no attainment report is issued.

## 5. Allowance and response

- For a ratio objective below 100%, the allowance in a window is `floor(total × (1 − target))`.
- Objectives at 100% have no allowance.
- An exhausted allowance never permits a boundary violation, failed acceptance, retrospective exclusion or an
  attainment claim made with unknown coverage.

| Objective | Required response |
| --- | --- |
| `api-availability` | Releases are limited to fixes of the cause until the 30-day attainment is back above target. |
| `explicit-failure` | The affected route is not accepted. Its next release carries evidence that the correction holds. |
| `release-integrity` | No further release until the stranded transaction is explained and the release probe set covers what it missed. The fix is the first release allowed. |
| Bound objectives | A breaching sample is recorded bad against its host build. The next release of that build path carries a qualified sample within the bound, or the cause named (`frontdoor-tail-explained`). |
| Declared limits | An observed excess is a defect against its scenario. The next release carries the correction's evidence. |

**Change independence.** sfx-api does not own PLT-CHANGE-INDEPENDENCE. A covered accepted product change that required
a host build change counts against it, whether it was a feature, an ordinary fix or a security repair (sfx-platform
change-admission rule 4). [change-admission.md](change-admission.md) states what counts as a host change and what sfx-api
supplies for the measurement.

These responses apply to the affected surface and its declared obligations. An unrelated historical gap does not
create a blanket hold.

## 6. Reporting and review

- **Every deploy record** under `docs/` adds a `release-integrity` observation. It carries the full host build identity
  and the release probe set's retained responses. A record that leaves either out is unverified.
- **Every latency sample** retains each request's time and answer. A summary alone is unverified.
- **The monthly report** comes once the report capability exists (§11). It is generated per objective, source,
  environment, host build and window, with input digests. It is committed as `docs/sla/reports/<yyyy-mm>.md` together
  with the exact catalogue and ledger inputs. Until then no attainment is claimed anywhere.
- **features/README.md's "Service levels"** keeps the performance strategies, and points to the catalogue and §3.3
  for the objectives. Targets and their status then live in one place.

## 7. Breach response

A breach is recorded as an observation with `bad` outcomes and evidence. It is then handled with the product contract's
dispositions:

| Disposition | Use |
| --- | --- |
| Retryable | The failure cleared on retry under declared policy. It still counts. |
| Effect uncertain | A write may have happened without a response. Reconcile it under its existing identity before any repeat. |
| Dependency missing | The cause is in an uncovered component. Open its linked obligation with the owner, and record the exclusion with attribution evidence. |
| Authority required | The fix needs an authority sfx-api does not hold. Retain the work and name the missing authority. |
| Revision conflict | The objective changed under §10 while its window was open. Report both versions. |
| Cancelled | The objective was withdrawn under §10. Retain its history. |

## 8. What may be claimed

A report states attainment per objective, source, environment, host build and window, with counts and evidence
references. It does not state that the platform, the estate, the kernel or a capability met anything. None of the
following is attainment:
- a feature's `@status:proven`;
- a deploy record's narrative;
- a scratch replay;
- an architectural assessment.

## 9. Obligations between components

| Component | Obligation |
| --- | --- |
| sfx-api | Refuse unavailable operations with a named code. Keep session read, logout and revocation semantics stable. Provide stream cursors and gap signals. Provide run read-back by ID (platform §9). Supply the host build identity of every release for change measurement. Own the content delivery host's contract, authenticated admission, ticket and session transport, declared route resolution, security enforcement and deployment accountability ([content-delivery-boundary.v1][cdb]). |
| sfx-embody | Own the accepted-change register and its classifications. Own content selection, publication eligibility and state, rendering profiles, recovery and delivery acceptance. |
| sfx-dal | Own canonical principal, grant, audience and revocation facts. |
| scenario-driven-architecture | Execute the declared mechanics. KV-001 moves the kernel's estate session to the host and retires `session-setup`. |
| sfx-platform | Consume the API through published contracts. Its probe does not sample the API origin. |

## 10. Changing this agreement

- **What changes the version:** changing an objective, a window, a unit or an attribution rule. The change bumps both
  this document's version and the catalogue's, takes effect from a stated date, and never re-scores a closed window.
- **Catalogue snapshots:** retain each one under [catalogues/](catalogues/). The current catalogue must be
  byte-identical to its snapshot, and observations bind a snapshot's version and digest.
- **Adding a surface:** a new surface, such as the content delivery host, adds its objectives with their measurement
  status stated honestly.
- **Effective date:** version 1.0 took effect on 2026-11-07, the start of cumulative counting. Earlier records enter
  only as qualified baselines (§4, rule 6).

## 11. Measurement capabilities owed

None of these exists. Each is new behaviour, so its feature comes first and is built only after the owner approves it.

The probe follows the precedent of `probe-hosted-execution` and `accept-hosted-execution-profile`. It is a capability
declared in the host's bundle, it reaches the public routes through `sfx-api-host-http-request-port.v1`, and the operator
invokes it through the installed CLI on every release and on a schedule. When the host cannot answer, the invoking
client's own failure is the observation, recorded with that client's evidence.

| Capability | Serves |
| --- | --- |
| Probe of the governed origin | `api-availability`, `explicit-failure`, the release probe set |
| Latency sample that retains each request's server time and answer | `frontdoor-warm-latency`, `sign-in-refused-latency`, `dispatched-request-latency`, `sign-in-latency` |
| Delivery evidence on the governed host | `frontdoor-tail-explained`, `warm-definitions`, `session-setup`, `no-kernel-start-on-request` |
| Ledger check and report: shape, digests, snapshot identity, correction chains, attainment | §4 rules 1 to 8, §6 |

## Still open

features/README.md Q2 applies to two of these objectives. `abandoned-request-release` and `no-kernel-start-on-request`
cannot both hold when a client gives up in the middle of an envelope.

[cdb]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/2df87d8702ec334b8962bb299cc637bddf3b0f03/docs/sla/content-delivery-boundary.v1.json
