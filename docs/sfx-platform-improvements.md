# sfx-platform on the declared API: the improvements to make

Date: 2026-11-01. From: sfx-api. For: the sfx-platform maintainers, to plan and drive their work.

## Purpose

The goal this serves: every capability execution in the estate is observable live, from any machine, including the
capabilities a frontier model invokes through the estate. sfx-api publishes executions to one channel and serves the
estate's declared reads. sfx-platform's clients (the staging web, the desktop and their tools) subscribe to that channel
and read through those operations.

Since the cutover to the declared API (sfx-platform #78), parts of sfx-platform still assume the removed legacy host:
its paths, its identities and its tooling. This document lists each one that remains, as found in sfx-platform `main`
at `e0ee866` on 2026-11-01. It covers tracked source only; artifacts, docs and desktop builds are excluded.

Every item gives its evidence (file and line, a probe, a run id or a declaration), the change it needs, and how to check
it is done. Items marked **needs a contract** cannot start until sfx-platform states what it needs from sfx-api. The
owner sets the priority; the order below is by effect on the goal.

The channel's contract, and the facts about what sfx-api serves today, are in
[request-sfx-platform-live-observation.md](request-sfx-platform-live-observation.md), sections 1 and 2.

## Summary

| Item | What | Kind | Blocks the goal |
| --- | --- | --- | --- |
| P1 | Signed-in acceptance of live observation | acceptance | Yes: nothing has confirmed the Explorer and Estate Live on staging |
| P2 | Acceptance tools assert the legacy identities | defect | Yes: the tools fail against every record sfx-api serves |
| P3 | `estate-evidence.mjs` calls the removed `/v1/runs` | defect | Yes: the tool and its two callers fail before checking anything |
| P4 | Test fixtures emit the legacy identities | test gap | Indirectly: tests pass on identities the host never serves |
| P5 | The provider inspection selection answers 501 | needs a contract | A desktop feature is missing |
| P6 | The desktop project read answers 501 | needs a contract | A desktop feature is missing |
| P7 | Records built in the client carry the legacy run prefix | naming | No functional effect found |
| P8 | The legacy machine token variable is still accepted | cleanup | No |

## P1. Signed-in acceptance of live observation

**Evidence.** sfx-platform `6d4092f`, deployed to `sidefx-web-staging`, routes `GET /events` to sfx-api, answers
`globalObserver: true`, and has the Explorer connect when configured. A probe on 2026-11-01 got
`401 {"error":"SIGN_IN_REQUIRED"}` on `GET /events`, with header `x-sfx-frontend-revision: 6d4092f…`. No signed-in
session has been through it yet, and sfx-api never holds a user's session.

**Change.** Run steps A1 to A6 of [request-sfx-platform-live-observation.md](request-sfx-platform-live-observation.md),
section 4, on the staging web and the desktop.

**Done when.** Each step passes, with its run ids and `x-observer-instance` recorded. Step A4 also confirms the one
channel behaviour not yet verified (F8 there): a `run=current&graphId=` subscription writes only that run's records.

## P2. The acceptance tools assert the legacy identities

**Evidence.** sfx-api writes run event ids as `urn:sfx-api:run-event:<run>:<cursor>` (`host/serve.py`,
`Execution.append`), and channel records with `runId` `sfx-api:<run>` (declaration 19). These assertions expect the
legacy forms, so they fail on the first record:

| File:line | Reaches | Asserts | Fails with |
| --- | --- | --- | --- |
| `tools/live-circuit/acceptance-evidence.mjs:95` | `<origin>/workspace/runs/<run>/events/stream` (lines 71, 87) | `urn:sda-api:run-event:<run>:<cursor>` | `EXECUTION_EVENT_IDENTITY` |
| `tools/live-circuit/acceptance-evidence.mjs:140` | The installed CLI's `sfx-api-run-evidence.v1` record (line 129) | the same | `EXECUTION_EVENT_IDENTITY` |
| `tools/live-circuit/acceptance-evidence.mjs:170, 177` | `<origin>/events` (line 154) | `runId === 'sda-api:' + runId` | `DELIVERY_TERMINAL_MISSING`, at its timeout |
| `tools/live-circuit/durable-snapshot.mjs:45` | `<origin>/workspace/runs/<run>/events/stream` (lines 6, 32) | `urn:sda-api:run-event:` | assertion failure on the first event |

**Change.** Assert the sfx-api forms. Where both hosts must still be read, accept both, as
`live-circuit/circuit/estate-live.mjs:60` does. For a channel record, `record.api.runId === runId` checks the run
without depending on the prefix.

**Done when.** Each tool passes against `sidefx-web-staging` with a signed-in session and a run admitted for the check.

## P3. `estate-evidence.mjs` calls the removed `/v1/runs`

**Evidence.** `tools/live-circuit/estate-evidence.mjs:14` fetches `<origin>/v1/runs…`, the legacy SDA API path. A probe
on 2026-11-01 got `404 {"error":{"code":"OPERATION_NOT_DECLARED"}}` from `sfx-api-test` and `404 {"error":"NOT_FOUND"}`
from `sidefx-web-staging`. Its callers are `tools/live-circuit/estate-live-acceptance.mjs` and
`tools/live-circuit/verify-acceptance-evidence-browser.mjs`.

**Change.** Either read runs through `<origin>/workspace/runs/<run>…`, as `acceptance-evidence.mjs` does, and apply P2 to
line 34; or retire the tool and both callers.

**Done when.** Outside `docs/` and `artifacts/`, every match of `git ls-files | xargs grep -n "/v1/runs"` is a
`/sfx/v1/runs` path.

## P4. Test fixtures emit the legacy identities

**Evidence.** These fixtures build events with `urn:sda-api:run-event:…`, which sfx-api never serves:
- `live-circuit/circuit/estate-fixture.mjs:64`;
- `live-circuit/circuit/verify-estate-live.mjs:14`, which converts one frame to `urn:sfx-api:` at line 117 and leaves the
  rest;
- `tools/live-circuit/flight-fixture.mjs:33`;
- `tools/live-circuit/verify-acceptance-evidence-browser.mjs:27`.

So the tests prove the legacy identity paths, not the one the host serves.

**Change.** Emit `urn:sfx-api:run-event:<run>:<cursor>` and `sfx-api:<run>`. Keep a legacy case only where a reader must
still accept both.

**Done when.** The fixtures emit the sfx-api forms, and the suites that use them pass.

## P5. The provider inspection selection answers 501 (needs a contract)

**Evidence.** `clients/api/workspace.mjs:146` answers `/workspace/provider-inspection` with
`501 PROVIDER_SELECTION_READ_NOT_DECLARED`. Its comment says provider-by-id exists, which sfx-api serves as
`GET /sfx/v1/providers/{providerId}/inspection` (`read-provider-inspection`). It also says the desktop's selection needs
the backend to bind that provider to the requested circuit detail and snapshot digest, and sfx-api declares no such
read.

**Change.** sfx-platform specifies the read the desktop needs: its inputs (circuit detail, snapshot digest, provider),
its answer, and its refusals. sfx-api then declares it, and sfx-platform maps `/workspace/provider-inspection` to it.

**Done when.** The desktop's provider selection answers 200 with the bound inspection for a known circuit detail.

## P6. The desktop project read answers 501 (needs a contract)

**Evidence.** `desktop/src/project-service.mjs:156` answers `POST /api/desktop/projects/read` with
`501 PROJECT_READ_NOT_DECLARED` whenever the session is the declared API (`sessionApi === 'declared'`). The estate has the
capability `read-project-tracker`, but sfx-api's interface declares no operation for it.

**Change.** sfx-platform specifies the project read the desktop needs: the answer its `project-read` job builds with
`snapshot()` for a legacy session (line 157).
sfx-api then declares an operation for it, and the desktop maps to that operation instead of answering 501.

**Done when.** The desktop's project view reads the tracker's projects on the declared API.

## P7. Records built in the client carry the legacy run prefix (naming)

**Evidence.**
- `live-circuit/circuit/observer-record.mjs:11` builds `runId: sda-api:<run>`. It is used by
  `live-circuit/circuit/flight-client.mjs:88` to replay a flight's retained runs into Estate Live's store.
- `live-circuit/circuit/observe-panel.js:137` builds `observationKey: sda-api:<eventId>`.

No functional effect was found. Estate Live keys runs on `api.runId` and accepts both event-id prefixes
(`estate-live.mjs:60`), and the flight's records go into a store of their own. But a record built in the client differs
from the same run's record on the channel (`sfx-api:<run>`).

**Change.** Use `sfx-api:<run>`, so that the client and the channel name a run the same way.

**Done when.** No tracked source builds `sda-api:`.

## P8. The legacy machine token variable is still accepted (cleanup)

**Evidence.** `clients/api/sfx-api.mjs:38, 132, 143` accept `SDA_API_TOKEN` as well as `SFX_API_TOKEN` for machine mode.

**Change.** The owner decides whether to keep the alias. If not, remove it and its mention in the help text.

**Done when.** The help text and the code name the same variables.

## Not in sfx-platform

These are listed so that they are not mistaken for sfx-platform work:
- Executions answered within a request are not on the channel: sfx-api switched them off (`ff44a75`). sfx-api closes this.
- The Fractal Lab bridge (`fractal-lab-providers`, `telemetry/bridge-sfx-observer.mjs`) subscribes to `<observer>/events`
  without a session, so the hosted channel answers it 401. This is fractal-lab-providers' change.
- Executions on a local kernel are deferred by the owner.

## Reporting back

A finding that points at sfx-api goes to sfx-api with its evidence: the run id, the `x-observer-instance` value, and the
request and answer. That covers a record that differs from the contract, a selector answer that differs, or a missing
operation.
