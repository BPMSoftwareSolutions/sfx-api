# Request to sfx-platform: finish live observation on the declared API

Date: 2026-11-01. From: sfx-api. To: the sfx-platform maintainers.

Goal: every capability execution in the estate is observable live, from any machine, including the capabilities a
frontier model invokes through the estate. The estate publishes each execution to one channel, and any signed-in
subscriber anywhere receives it as it happens. The Explorer, Estate Live and the desktop are subscribers of that
channel. They show what it carries; they are not the goal.

Where the channel stands against that goal: it carries every run admitted through the API, from any client on any
machine, including an agent invoking a capability with the `sfx-api` CLI (F3). It does not carry executions answered
within a request: sfx-api switched those off (F9), and that gap is sfx-api's to close. It does not carry executions on a
local kernel, which the owner deferred.

This request asks sfx-platform for its part: its subscribers receive and show what the channel carries, and its
acceptance tools accept the channel's identities. Everything else sfx-platform still has to change for the declared
API is in [sfx-platform-improvements.md](sfx-platform-improvements.md).

Every statement below gives its evidence: a run id, a revision, a probe made on 2026-11-01, a declaration, or code at
a file and line. A statement without evidence is marked **not verified**.

Status: sfx-platform answered sections 3 and 4 in `67c8365`. Its record is
`docs/analysis/declared-observer-2026-11-01.md`, and the per-item results are in
[sfx-platform-improvements.md](sfx-platform-improvements.md) (P1 to P3).

## 1. Facts

| # | Fact | Evidence |
| --- | --- | --- |
| F1 | `sidefx-web-staging` serves sfx-platform `6d4092f`, which forwards `GET /events` to `sfx-api-test` and answers `/workspace/execution` with `globalObserver: true`. | Probe: `GET https://sidefx-web-staging.azurewebsites.net/events` answered `401 {"error":"SIGN_IN_REQUIRED"}` with header `x-sfx-frontend-revision: 6d4092f08eb41c599d48c418e4d012d96ded56fb`. Before `6d4092f` it answered `404 {"error":"NOT_FOUND"}`. |
| F2 | `sfx-api-test` serves the channel at `GET /events` and `GET /sfx/v1/estate-execution/stream`, and refuses a caller without a session. | Probe: both answered `401 {"error":{"code":"CALLER_REQUIRED"}}`. Deployed then: sfx-api `ff44a75`, image `sha256:567b6fce…`. Deployed now: sfx-api `1ac2d0f`, image `sha256:e130c20a…`, kernel from SDA `aa32214`; a run's run-end record also carries `payload.capture` (`{records, dropped}`). |
| F3 | A run's records reach a subscriber. | A workspace watcher (`sfx-embody` `tools/sfx-listener/watch.mjs`) subscribed to `GET /events` on `sfx-api-test`. Run `b0f093c4` (`author-workspace-file`) returned, and the watcher created the authored file 6.6 s later. |
| F4 | A run's `run-end` is published only after its output is stored. | Run `24830b03`: when its `run-end` arrived, the watcher read `GET /api/circuit/v1/runs/24830b03-e255-7aad-e5d7-f283e06aa442/output` and got 200 on the first attempt. |
| F5 | The subscription's selectors answer as declared. | Estate runs of `subscribe-estate-live-observation`. No selector: no cursor (`3c934aad`). `since=7`: replay after 7 (`bd99cb41`). `run=current&graphId=…`, `run=LAST`, `run=2`: replay from 0 with the selection (`cd659a0d`, `e0425083`, `cdf7ad49`). `run=next&since=7`: no replay (`c0901206`). `run=03`: 400 `invalid_run` (`67fe2a74`). `since=-1`: 400 `invalid_since` (`12f9a1be`). |
| F6 | The run window is chosen as the legacy observer chose it. | Estate runs `623b8efa` to `de672be8` of `select-estate-live-observation`: 7 of 7 cases chose the expected window. |
| F7 | The record is framed as declared. | Estate run `de0ca705` of `publish-estate-live-observation` framed a two-execution batch. Each record has `runId` `sfx-api:<execution>`, `kind` `run-start`/`observation`/`run-end`, `api.subject.capabilityId`, and a nested invocation's `capabilityId` in its payload. |
| F8 | The host writes only the selected run's records on a live `run=` subscription. | sfx-platform's step A4 (`67c8365`, `docs/analysis/declared-observer-2026-11-01.md`): `run=current&graphId=graph%3Averify-password-derivation` replayed exactly run `ec577b9d`'s 42 records, and a selected subscription kept open across run `5f6bd214` still held only those. |
| F9 | Executions answered within a request (`serve-http-request`) are **not** on the channel now. | sfx-api `ff44a75` sets `observation.requests: false` in `sfx-api.config.json`. |

## 2. The contract sfx-api serves

The declarations are the source. A record or answer that differs from them is an sfx-api defect.

- Subscription: [21-subscribe-estate-live-observation.dsl](../declarations/21-subscribe-estate-live-observation.dsl).
- Run window choice: [20-select-estate-live-observation.dsl](../declarations/20-select-estate-live-observation.dsl).
- Record and frame: [19-publish-estate-live-observation.dsl](../declarations/19-publish-estate-live-observation.dsl).
- Routes: `stream-observer-events` (`GET /events`), `stream-estate-events` (`GET /sfx/v1/estate-execution/stream`)
  and `read-observer-run-output` (`GET /api/circuit/v1/runs/{runId}/output`) in
  [authorities/sidefx-api-interface.v1.json](../authorities/sidefx-api-interface.v1.json).

What those declare, in short:
- **Session:** the cookie `__Host-sfx-session` or a bearer. Without one: `401 CALLER_REQUIRED`.
- **Selectors:** `since=<seq>` (or `Last-Event-ID`); `run=current` or `last`, with `graphId=graph:<capability>`;
  `run=<n>`; `run=next`. Refused: `400 {"error":"invalid_run"}` and `400 {"error":"invalid_since"}`.
- **Stream:** `text/event-stream`, with header `x-observer-instance`. Frames, in order: `retry: 3000`, the replay,
  `: replay-complete`, then `id: <seq>` with one `data:` line per record. `: keep-alive` while quiet;
  `: session-ended` at the session's expiry or a failed recheck.
- **Record:** `{seq, observationKey, receivedAt, kind, runId, api, glyph, cls, text, payload}`.
  - `observationKey` is `sfx-observer:<x-observer-instance>:<seq>`.
  - `runId` is `sfx-api:<run>`, where the legacy host wrote `sda-api:<run>`.
  - `api.eventId` is `urn:sfx-api:run-event:<run>:<cursor>`, where the legacy host wrote `urn:sda-api:run-event:…`.
  - `api.runId` is the bare run id.

## 3. Requested: the acceptance tools assert the legacy identities

Each row says which sfx-api path the code reaches and why it fails, so the failure is certain, not likely.

| File:line | Reaches | Asserts | Result against sfx-api |
| --- | --- | --- | --- |
| `tools/live-circuit/acceptance-evidence.mjs:95` | `<origin>/workspace/runs/<run>/events/stream` (lines 71, 87). The web forwards it to `sfx-api` `/sfx/v1/runs/<run>/events/stream`. | `eventId === urn:sda-api:run-event:<run>:<cursor>` | sfx-api writes `urn:sfx-api:run-event:<run>:<cursor>` (`host/serve.py`, `Execution.append`). Fails on the first event: `EXECUTION_EVENT_IDENTITY`. |
| `tools/live-circuit/acceptance-evidence.mjs:140` | The installed CLI's `sfx-api-run-evidence.v1` record (`requireCliExecution`, line 129), whose events the CLI reads from `sfx-api` | the same | The same failure, on the first event. |
| `tools/live-circuit/acceptance-evidence.mjs:170, 177` | `<origin>/events` (line 154) | `record.runId === 'sda-api:' + runId` | Records carry `runId` `sfx-api:<run>` (declaration 19). The filter never matches, so it fails `DELIVERY_TERMINAL_MISSING` at its timeout. |
| `tools/live-circuit/durable-snapshot.mjs:45` | `<origin>/workspace/runs/<run>/events/stream` (lines 6, 32) | `urn:sda-api:run-event:` | Fails on the first event. |
| `tools/live-circuit/estate-evidence.mjs:14` | `<origin>/v1/runs`, the removed SDA API host's path | (it fails before line 34's identity check) | Probe: `sfx-api-test` answers `/v1/runs` with `404 OPERATION_NOT_DECLARED`, and `sidefx-web-staging` with `404 NOT_FOUND`. It is used by `estate-live-acceptance.mjs` and `verify-acceptance-evidence-browser.mjs`. |

Requested:
1. Accept `urn:sfx-api:run-event:<run>:<cursor>` and `sfx-api:<run>` wherever the legacy forms are asserted, as
   `live-circuit/circuit/estate-live.mjs:60` already does for `eventId`.
2. For `estate-evidence.mjs`, either point it at `<origin>/workspace/runs`, as `acceptance-evidence.mjs` does, and
   apply item 1 to line 34, or retire it with its two callers.

## 4. Requested: signed-in acceptance

sfx-api never holds a user's session, so these steps need a signed-in run by sfx-platform. Use the capability
`verify-password-derivation`: it runs with input `{}`, and its graph is `graph:verify-password-derivation` (run
`f8a01553`'s trace). Record each step's result, the run ids and the `x-observer-instance` value.

| Step | Do | Expect |
| --- | --- | --- |
| A1 | Signed out: `GET https://sidefx-web-staging.azurewebsites.net/events` | `401 {"error":"SIGN_IN_REQUIRED"}` |
| A2 | Signed in: open `https://sidefx-web-staging.azurewebsites.net/circuit/explorer?capability=verify-password-derivation` | The browser opens `GET /events` (`circuit-runtime.js:410`), answered `200 text/event-stream` with an `x-observer-instance` header. |
| A3 | On another machine, as an agent would: `sfx-api capability observe verify-password-derivation --input "{}" --json`, which prints run id R | The Explorer receives R's records: `run-start` with `runId` `sfx-api:R`, the graph capture with `graphId` `graph:verify-password-derivation`, then `run-end`. |
| A4 | After R ends, press Replay | The browser opens `GET /events?run=current&graphId=graph%3Averify-password-derivation` (`circuit-runtime.js:410`). The stream replays R's records only, from `run-start` to `run-end`. This verifies F8. |
| A5 | Signed in: open `https://sidefx-web-staging.azurewebsites.net/circuit/estate`, then repeat A3 to get run R2 | R2 appears in Live without its id being entered. The browser log shows no `POST /workspace/runs` from the page. |
| A6 | Repeat A2 to A4 in the desktop app | As A2 to A4 |

If a step fails at the channel, send it to sfx-api with the step, the run id and the `x-observer-instance` value. That
covers a missing record, a gap in `seq`, a record that differs from section 2, or a selector answer that differs from
F5. Anything that passes the channel's contract but doesn't render belongs to sfx-platform.
