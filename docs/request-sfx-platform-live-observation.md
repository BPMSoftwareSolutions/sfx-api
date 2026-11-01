# Request to sfx-platform: finish live observation on the declared API

Date: 2026-11-01. From: sfx-api. To: the sfx-platform maintainers.

Goal: the owner observes executions on the staging web and the desktop as before the cutover. The Explorer animates a
run as it executes and replays the latest run of a circuit, and Estate Live shows runs started from any client.

## Where things stand

| Piece | Owner | State on 2026-11-01 |
| --- | --- | --- |
| The live observation channel at `GET /events` and `GET /sfx/v1/estate-execution/stream` | sfx-api | Live on `sfx-api-test` since sfx-api `d442242` (run selectors since `0f652da`). A run's events reach a subscriber within seconds. |
| The staging web routes `GET /events` to sfx-api; `/workspace/execution` answers `globalObserver: true`; the Explorer connects when configured | sfx-platform | Done in sfx-platform `6d4092f`, deployed: `sidefx-web-staging` reports that revision and answers `GET /events` with 401 `SIGN_IN_REQUIRED` when signed out, where it answered 404 before. |
| Estate Live on `/workspace/estate-execution/stream` | sfx-platform | Bound in #82. |
| The acceptance tools' event identity checks | sfx-platform | **Requested, section 3.** |
| Signed-in acceptance on the staging web and the desktop | sfx-platform | **Requested, section 4.** |

## 1. Boundary

- **sfx-api** serves the channel, its subscription rules and its record, through declared capabilities
  (`subscribe-estate-live-observation`, `select-estate-live-observation`, `publish-estate-live-observation`). The
  contract is section 2. Every run sfx-api executes is published, from any client on any machine.
- **sfx-platform** carries the browser's and the desktop's requests to it with the signed-in session, and owns the
  Explorer, Estate Live and their acceptance.

## 2. The contract sfx-api serves

Features: [features/estate-live-observation.feature](../features/estate-live-observation.feature) (approved
2026-11-01).

**Subscription.** `GET /events`, or the same query on `GET /sfx/v1/estate-execution/stream`.
- Session required, as cookie `__Host-sfx-session` or bearer. Without one: 401 `CALLER_REQUIRED`.
- `since=<seq>` or `Last-Event-ID` replays the retained channel after that position. Without either, only new records.
- `run=current` (or `last`), narrowed by `graphId=graph:<capability>` to the latest run that captured that graph;
  `run=<n>`, the nth retained run; `run=next`, the next run to start. Each keeps to that run.
- `run=03` and other refused selectors: 400 `{"error":"invalid_run"}`; a refused `since`: 400 `{"error":"invalid_since"}`.

**Stream.** `text/event-stream` with an `x-observer-instance` header that names the channel; a new instance began a
new sequence. Frames: `retry: 3000`, the replay, `: replay-complete`, then `id: <seq>` with one `data:` line per
record, `: keep-alive` while quiet, and `: session-ended` at the session's expiry or a failed recheck.

**Record.** The legacy observer's members in its order:
`{seq, observationKey, receivedAt, kind, runId, api, glyph, cls, text, payload}`.
- `kind` is `run-start`, `observation` or `run-end`; `seq` is contiguous within an instance.
- `observationKey` is `sfx-observer:<channel>:<seq>`.
- **Changed from the legacy host:** `runId` is `sfx-api:<run>`, and `api.eventId` is
  `urn:sfx-api:run-event:<run>:<cursor>`. They were `sda-api:<run>` and `urn:sda-api:run-event:<run>:<cursor>`.
- `api` also carries `runId` (the bare run id), `cursor`, `kind`, `occurredAt`, `recordedAt`, `rootExecutionId` and
  `subject {capabilityId, namespaceId}`.
- A run's `run-end` is published only after its output is stored, so `GET /sfx/v1/runs/{runId}/output` (also served at
  the legacy `GET /api/circuit/v1/runs/{runId}/output`) answers as soon as `run-end` arrives.

**Not on the channel for now:** executions answered within a request (`serve-http-request`). sfx-api built them and
switched them off, because publishing every request put the channel minutes behind its runs. They return when the
channel keeps up, and they will name `serve-http-request` with the resolved capability as a nested invocation.

## 3. Requested: accept the sfx-api event identity in the acceptance tools

These checks still assert the legacy SDA API identities, so they fail against every record sfx-api serves. Estate Live
already accepts both prefixes (`live-circuit/circuit/estate-live.mjs:60`); the tools should do the same.

| File | Line | Asserts | Should accept |
| --- | --- | --- | --- |
| `tools/live-circuit/acceptance-evidence.mjs` | 95, 140 | `eventId === urn:sda-api:run-event:<run>:<cursor>` | `urn:sfx-api:run-event:<run>:<cursor>` as well |
| `tools/live-circuit/acceptance-evidence.mjs` | 170, 177 | `record.runId === 'sda-api:' + runId` | `'sfx-api:' + runId`, or `record.api.runId === runId` |
| `tools/live-circuit/durable-snapshot.mjs` | 45 | `urn:sda-api:run-event:` | `urn:sfx-api:run-event:` as well |
| `tools/live-circuit/estate-evidence.mjs` | 34 | `urn:sda-api:run-event:` | `urn:sfx-api:run-event:` as well |

## 4. Requested: signed-in acceptance

sfx-api cannot hold a user's session, so these need a signed-in sfx-platform run.

```gherkin
Feature: The owner observes executions on the staging web and the desktop

  Background:
    Given a signed-in session on https://sidefx-web-staging.azurewebsites.net, and on the desktop

  Scenario: The Explorer animates a run as it executes
    Given the Explorer open on a circuit
    When that circuit's capability is run from the CLI on another machine
    Then the Explorer animates its cells and edges while it executes, without its run id being entered

  Scenario: The Explorer replays the latest run of its circuit
    When Replay is pressed after the run ended
    Then the Explorer replays that run (GET /events?run=current&graphId=graph:<capability>)

  Scenario: Estate Live shows a run started from another client
    Given Estate open
    When a run is started from the CLI on another machine
    Then it appears in Live without its run id being entered and without the page creating runs

  Scenario: Signed out, nothing is observed
    When GET /events is opened signed out
    Then the answer is 401 SIGN_IN_REQUIRED
```

Please record each scenario's result and the run ids you used. A failure that points at the channel, such as a missing
record, a gap in `seq`, or a record that differs from section 2, goes back to sfx-api on its issue tracker, with the
run id and the `x-observer-instance` value.
