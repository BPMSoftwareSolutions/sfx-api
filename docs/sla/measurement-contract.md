# sfx-api SLI observation contract

**Version:** 1, effective 2026-11-07. **Consumer:** the ledger check and report owed by
[host-sla.md §11](host-sla.md#11-measurement-capabilities-owed). Until they exist, observations are projected by hand
from retained evidence.

This is sfx-platform's `sidefx.sli-observation.v2` (sfx-platform `docs/sla/measurement-contract.md` at `2df87d8`)
adapted to a host. Every field below that has the same name keeps the platform's meaning, and this contract states each
difference. Matching the platform's shape lets one checker read both ledgers later. It does not merge their ratios.

## Observation envelope

`sfx-api.sli-observation.v1`:

| Field | Meaning and constraint |
| --- | --- |
| `schema` | `sfx-api.sli-observation.v1`. |
| `observationId` | Stable identity of this immutable observation. An identical replay is idempotent; conflicting bytes under the same identity are refused. Projections from retained records use `baseline:<ledger file stem>`. |
| `eventId` | Stable identity of the measured event, independent of observation or retry. A release transaction's is `release:<imageDigest>`. It is unique per objective, source, environment and catalogue revision, except within an explicit correction chain. |
| `catalogueVersion`, `catalogueDigest` | The exact retained catalogue snapshot. **Difference:** the digest is the SHA-256 of the snapshot file's bytes. `docs/sla/.gitattributes` keeps those bytes exact through checkout. The platform hashes canonical JSON instead. |
| `environment` | The exact target set: `name` and `apiOrigin`. **Difference:** the platform's browser and desktop targets do not apply. Different sets never pool, even under the same name. |
| `hostBuild` | **Addition.** The host build identity that served the event: `sourceCommit`, `imageDigest`, `bundlePin`, `kernelDigest`, `hostFilesDigest` ([host-sla.md §2](host-sla.md#2-definitions)). A field the evidence does not retain is `null`, and the observation is then `unverified`. A field that did not exist yet, such as `bundlePin` before the bundle, is `null` with the reason stated. |
| `slo`, `source`, `subject` | A known objective from the catalogue. `source` is one of `acceptance`, `probe`, `release-record`, `retained-record` or `manual`. `subject` is a human description, never an identity. |
| `observedAt`, `recordedAt` | ISO timestamps with a time zone. Event time selects the window; recording time controls what a report knew at its as-of time. Recording cannot precede the event. When the evidence keeps only a bound on the event time, `observedAt` is that bound, the qualification reason names it, and the status is `unverified`. |
| `evidence` | A nonempty list of retained references: repository paths, commits and estate run ids. Checking their presence or shape does not authenticate them. |
| `qualification` | `{status, reason, evidence}`. `status` is `eligible`, `out-of-scope` or `unverified`. Demo evidence is out of scope. |
| `good`, `bad`, `excluded` | Nonnegative integer counts for ratio objectives. `bad` requires `attribution`: `host`, `dependency` or `unclassified`. **Difference:** `host` replaces the platform's `platform`. `excluded` requires `exclusion: {owner, reason, evidence}` and is allowed only for `api-availability`. |
| `value` | One nonnegative finite value for a bound objective with a single maximum. It cannot be combined with ratio counts. |
| `quantiles` | **Addition.** For a bound objective with several quantile maxima, such as `frontdoor-warm-latency`: `{p50, p95}` in the objective's unit. The sample is good only if every quantile is within its maximum. The quantiles must be computed from the sample's retained per-request values. A summary without them is `unverified`. |
| `baseline` | For a projection of a retained record: `{reference, commit, sha256}`. The SHA-256 is that of the committed bytes (`git show <commit>:<reference>`). |
| `detail` | Free structured context. Nothing is computed from it. |
| `supersedes`, `correctionReason` | An optional correction naming an earlier observation. It keeps the same event, source, environment, catalogue revision and event time, and is recorded later. Forks and missing predecessors are refused. |

An exclusion is allowed only with independent attribution that matches the sample's route, time and named dependency.
A response code alone is not attribution. A host capacity refusal, such as `REQUEST_KERNEL_BUSY` or a 503 while a
container starts, is attributed to `host` and never excluded.

Out-of-scope and unverified observations are displayed separately. They are never converted to exclusions or
successes. An unverified observation in a group prevents that group from reporting `met`.

## Release-transaction observation

`release-integrity` permits exactly one unit per observation: `good` 1 or `bad` 1. Its `eventId` is
`release:<imageDigest>` of the image released. Its `detail` carries:

- the swap timeline: `SFX_API_IMAGE_DIGEST` set, image set, each restart, site started;
- the release probe set's responses, retained as bytes or as a structured readback with status and code per route;
- the rollback digest, and whether it was used.

A release recorded without every `hostBuild` field or without the probe responses is `unverified`. A transaction
fixed forward by a later release stays `bad`. The later release is its own transaction.

## Host build identity for change independence

sfx-api does not hold the accepted-change register. The estate does (sfx-platform `measurement-contract.md`, "Canonical
accepted-change register"). For each accepted product change in scope, the estate's change observation carries
`buildIdentities.host: {before, after, evidence}`. sfx-api supplies those values:
- `before` and `after` are `imageDigest` values of releases recorded under this contract;
- `evidence` cites their `release-integrity` observations.

Whether a host build change was required by a given product change is the estate's classification, not this ledger's.
[change-admission.md](change-admission.md) states what changes the host build.

## Revision and reporting rules

- The current [slo-catalogue.json](slo-catalogue.json) is byte-identical to its snapshot in
  [catalogues/](catalogues/), and the check refuses drift.
- Each observation pins its snapshot, and different revisions never share a ratio.
- A report states `met` only with evaluated, eligible evidence and complete coverage.
- `breached` means an established failure exceeds the allowance.
- `incomplete` means missing qualification or coverage prevents a verdict.
- `unevaluated` means no applicable unit was observed.
- A closed report retains its exact inputs. A correction to it is a new, labelled report.
