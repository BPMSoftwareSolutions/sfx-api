# Legacy staging host and the declared API: endpoints and responses

Compared on 2026-10-31 to answer one question: what does sfx-platform have to change, and what does
the declared API still have to declare, before sfx-platform can stop calling the legacy staging host?

The terms follow the [README](../README.md): **the legacy staging host**
(`sidefx-staging-fyfhb9gubneqbpaz.eastus2-01.azurewebsites.net`) and **the declared API** (this
repository, `sfx-api-test.azurewebsites.net`). Shapes come from the code and authorities listed under
[Sources](#sources). Measured results come from the 2026-10-31 desktop probe, the direct HTTP
comparison and unauthenticated probes of both hosts on the same day.

## Summary

- **The migration is more than a prefix change.** sfx-platform's desktop, browser Explorer and
  `sfx-api` CLI call 28 legacy routes, counting `/api/circuit/v1/runs…` and the CLI's `/v1/runs…`
  once. 17 have a declared counterpart, and every one of those differs in path, response envelope
  or status codes. One more (`events/stream`) is declared but answers 501. The other 10 have no
  declared operation.
- **Run observation is the largest gap.** The declared API has no global `/events` feed and its run
  event stream answers 501. Admission is synchronous and records no trace (cursor 0). The Explorer's
  Observe panel and the desktop's estate monitoring are built on these.
- **The browser can't sign in safely yet.** `POST /sfx/v1/session` returns the bearer in the
  JSON body and sets no cookie. The legacy browser flow never exposes the bearer to script. The
  declared API also declares a same-origin rule for cookie writes but does not enforce it.
- **Query values were decoded incorrectly (fixed 2026-10-31).** The ingress left reserved characters
  percent-encoded, so `namespaceId=sidefx%3Acapabilities` failed. Clients that build queries with
  `URLSearchParams` encode the colon that way. The fix is declared; the signed-in acceptance requests
  are still to run. See [the query-decoding defect](#the-query-decoding-defect).
- **Machine callers have no carrier** (EV-014). Nothing that authenticates with `SDA_API_TOKEN`
  today can reach the declared API.
- **Three hosts are called "the new API".** See the next section.

## Which host serves `/sfx/v1`

| | Legacy staging host | Staging frontdoor | The declared API |
| --- | --- | --- | --- |
| Code | sfx-platform [`gateway.mjs`][gateway] and the identity, circuit and SDA hosts behind it | sfx-platform [`frontdoor.mjs`][frontdoor] (#66, merged 2026-10-30) | This repository: the interface rows resolved per request by the kernel (`serve-http-request`) |
| Reads `sidefx-api-interface.v1` | No | Yes, in Node | Yes, in the kernel |
| Live at | the legacy staging host | **Not live.** Staging runs release `composite-a010d9d…`, which predates #66, and answers `/sfx/v1/*` with its HTML 404 page (checked 2026-10-31) | `sfx-api-test` |
| Resolve kinds served | n/a | `capability`, `command`, `admission`, `run`; refuses `ingress`, so it has no sign-in | `capability`, `ingress`; `run` and `command` answer 501 |

The staging frontdoor and the declared API read the same rows but behave differently. The staging
frontdoor decodes queries with `URLSearchParams`, enforces the cookie-write rule, caches reads and
serves the event stream. The declared API does none of these yet. **This document compares the legacy
routes with the declared API on `sfx-api-test`.** The staging frontdoor is mentioned only where it
changes a conclusion.

## How each host is put together

**Legacy.** There is one public origin. The gateway on port 3000 routes by prefix:

| Prefix | Served by | Credential it accepts |
| --- | --- | --- |
| `/auth/v1/*` (nine routes, [`identity-policy.json`][identity-policy]) | identity host, loopback 8793 | user bearer; the private callbacks take the service key |
| `/api/circuit/v1/*`, `/events`, `/circuit/*`, `/`, downloads | circuit host, loopback 8787 ([`observe-server.mjs`][observe-server]) | the `__Host-sfx-session` cookie only ([`access-gate.mjs`][access-gate]); the desktop sends both bearer and cookie |
| `/v1/runs*` with a user bearer | circuit host ([`run-api.mjs`][run-api], CLI prefix) | user bearer |
| `/v1/*` with the machine token | SDA Run API, loopback 8799 ([`sda-api-v1.authority.json`][sda-api]) | `SDA_API_TOKEN` |
| `/procedure-extract/*` | retrieval, loopback 8791 | machine token |

**Declared API.** [`host/serve.py`](../host/serve.py) passes each raw request to one kernel run of
`serve-http-request`. The ingress reads the request. `POST /sfx/v1/session` goes to `open-api-session`,
and everything else goes to the frontdoor `serve-api-request`, which matches the interface operations,
admits the caller and dispatches. The carrier is `Authorization: Bearer` or the `__Host-sfx-session`
cookie, digested inside the ingress. There is no machine carrier.

## Endpoint map

In the Status column, **Served** means declared and answering. **501** means declared but answering
`OPERATION_DISPATCH_NOT_DECLARED`. **None** means no declared operation, answered with 404
`OPERATION_NOT_DECLARED`. In the Caller column, D is the desktop, B the browser Explorer and pages,
C the `sfx-api` CLI and M machine callers and tooling. `…` stands for `/api/circuit/v1` for cookie
callers and `/v1` for the CLI and machine callers.

### Sessions

| Legacy route | Caller | Declared API | Status | What changes |
| --- | --- | --- | --- | --- |
| `POST /auth/v1/login` | D, C | `POST /sfx/v1/session` | Served | Body gains `status`; no realm header |
| `POST /api/circuit/v1/session` | B | `POST /sfx/v1/session` | Served, not browser-safe | Legacy sets an HttpOnly cookie and never returns the bearer; declared returns the bearer and sets no cookie |
| `GET /auth/v1/session` | D, C | `GET /sfx/v1/session` | Served | `expiresAt` becomes `sessionExpiresAt`; no realm |
| `GET /api/circuit/v1/session` | B | `GET /sfx/v1/session` | Served | Signed out is 401, not 200 `{authenticated: false}` |
| `POST /auth/v1/logout` | D, C | `POST /sfx/v1/session/logout` | Served | |
| `POST /api/circuit/v1/session/logout` | B | `POST /sfx/v1/session/logout` | Served | No cookie is cleared |
| `GET /api/circuit/v1/session/runs` | B | — | None | The "your runs" list |
| `POST /auth/v1/enroll`, `/auth/v1/enrollment-provider/*`, `/api/operator/v1/*` | B (operator) | — | None | Operator enrollment |
| `POST /auth/v1/provider/{resolve,verify,establish}` | identity host only | — | Not needed | Private callbacks of the retired login host; sign-in is now `open-api-session` |

### Circuit and capability reads

| Legacy route | Caller | Declared API | Status | What changes |
| --- | --- | --- | --- | --- |
| `GET /api/circuit/v1/capabilities` | D, B | `GET /sfx/v1/circuits` | Served | A bare array instead of `{contractId, count, readAt, capabilities}` |
| `GET /api/circuit/v1/scenario?capabilityId=…` | B | `GET /sfx/v1/circuits/{capabilityId}/scenario` | Served | Capability id moves to the path; slides lack `svgDigest` and `imageUrl` |
| `GET /api/circuit/v1/capability-details?capabilityId=…` | B | `GET /sfx/v1/circuits/{capabilityId}/details` | Served | Non-`READ` statuses come back as 200 |
| `GET /api/circuit/v1/page?path=…` | B | `GET /sfx/v1/pages?path=…` | Served | Same parameters; `path` holds `/`, which hits the query defect |
| `GET /api/circuit/v1/crosswalk?crosswalkId=…` | B | `GET /sfx/v1/crosswalks/{crosswalkId}` | Served | Id moves to the path |
| `GET /api/circuit/v1/provider-inspection?capabilityId&namespaceId&scenarioId&detailId&expectedSnapshotDigest` | B | `GET /sfx/v1/providers/{providerId}/inspection` | Served | Selected by provider id; the client must find the provider in the scene and check its definition digest |
| `GET /v1/capabilities/{id}/graph` | M | `GET /sfx/v1/capabilities/{id}/graph` | 501 | Compile is a kernel operation, not a capability |
| `GET /api/circuit/v1/ui-registry` | B | — | None | Static shell data |
| `GET /api/circuit/v1/region?regionId=…` | B | — | None | The migration branch stops mounting regions |
| `GET /api/circuit/v1/home` | B | — | None | Host configuration |
| `GET /api/circuit/v1/execution` | D, B | — | None | Host configuration; the branch adapter answers it locally |

### Runs

| Legacy route | Caller | Declared API | Status | What changes |
| --- | --- | --- | --- | --- |
| `POST …/runs` | D, B, C, M | `POST /sfx/v1/runs` | Served | Answers 200 when the run ends, not 202 at admission; no machine callers |
| `GET …/runs/{runId}` | D, B, C | `GET /sfx/v1/runs/{runId}` | Served | Wrapped in `{status, runId, run}` |
| `GET …/runs/{runId}/output` | D, B, C | `GET /sfx/v1/runs/{runId}/output` | Served | Wrapped in `{status, runId, output}` |
| `GET …/runs/{runId}/graph[?rootExecutionId=]` | D, B | `GET /sfx/v1/runs/{runId}/graph` | Served | Every root in `graphs[]`; no selector |
| `GET …/runs/{runId}/events?after&limit&kinds` | B, C | `GET /sfx/v1/runs/{runId}/events` | Served | Retained trace chunks, no paging or filters; empty for runs the declared API admitted |
| `GET …/runs/{runId}/events/stream` | D, B | `GET /sfx/v1/runs/{runId}/events/stream` | 501 | |
| `GET /v1/runs/{runId}/evidence`, `GET /v1/evidence/{ref}` | M | — | None | The legacy resolver is itself a 501 stub |
| — | — | `GET /sfx/v1/retained-runs/{runId}`, `…/events` | Served, new | What the circuit host read privately from `/evidence/v1/runs/{id}` |
| — | — | `GET /sfx/v1/runs/{runId}/delivery` | 501, new | |

### Observation, estate and host

| Legacy route | Caller | Declared API | Status | What it is for |
| --- | --- | --- | --- | --- |
| `GET /events` (SSE; `run`, `since`, `graphId`) | D, B | — | None | The global observer: the Explorer's live circuit and the desktop's estate monitoring |
| `GET /api/circuit/v1/estate-execution/{scopes,snapshot}` | D, B | — | None | Estate execution views |
| `GET /healthz`, `/readyz` | D, B | — | None (404, checked) | Release label in the footer and the `release` UI source |
| `GET /internal/deployment`, `POST /procedure-extract/{json,excel}` | M | — | None | Deployment check, retrieval |

### Pages and downloads

`/`, `/circuit/*`, `/get-started`, `/operator*`, `/download*`, `/releases/desktop*`,
`/api/desktop/releases`, `/robots.txt` and `/favicon.ico` are web content. The declared API serves no
pages or files, so these stay on a web host. While the Explorer is served from another origin, every
declared API call from the page is cross-origin. The declared API sends no CORS headers, and a
cross-origin page can't use its cookie carrier. The API therefore has to be proxied under the page's
origin, as the staging gateway does for `/sfx/v1` since #66, or CORS has to be declared for bearer
callers.

## Response shapes side by side

### Sign-in

| | Legacy native `POST /auth/v1/login` | Legacy browser `POST /api/circuit/v1/session` | Declared `POST /sfx/v1/session` |
| --- | --- | --- | --- |
| Request | `{identifier, password}` | `{identifier, password}`, same-origin JSON | `{identifier, password}` |
| Success | 200 `{tokenType: "Bearer", token, sessionId, principalId, expiresAt}`, header `x-sfx-identity-realm` | 200 `{disposition: "AUTHENTICATED", sessionId, principalId, expiresAt, realm, identifier}` and `Set-Cookie: __Host-sfx-session=…; HttpOnly; Secure; SameSite=Strict` | 200 `{status: "AUTHENTICATED", tokenType: "Bearer", token, sessionId, principalId, expiresAt}` |
| Refusals | `{disposition}` | `{disposition}`: 400 `LOGIN_INPUT_INVALID`, 401, 403 `SAME_ORIGIN_JSON_REQUIRED`, 413, 429, 502, 503 | 400 `{status: "LOGIN_INPUT_INVALID"}`, 401 `{status: "AUTHENTICATION_REJECTED"}`, 429 `{status: "THROTTLED"}`, 503 `{status: "IDENTITY_UNAVAILABLE"}` |
| Realm | header | body | fixed to `sfx-ide-local` inside the ingress and not returned; the migration branch stores the endpoint as the realm |

### Session read and sign-out

| | Legacy | Declared |
| --- | --- | --- |
| Read, bearer | `GET /auth/v1/session`: 200 `{sessionId, principalId, expiresAt}` and the realm header; 401 when ended | `GET /sfx/v1/session`: 200 `{status: "READ", kind: "user", principalId, sessionId, sessionExpiresAt}`; 401 `{error: {code: "CALLER_REQUIRED"}}` |
| Read, cookie | `GET /api/circuit/v1/session`: always 200, `{authenticated: true, observeRequiresSession, sessionId, principalId, expiresAt, realm, identifier}` or `{authenticated: false, observeRequiresSession, disposition?}`; 503 when identity is down | same as bearer |
| Sign-out | native: 200 `{disposition: "REVOKED"}`, 401 when already ended. Browser: 200 `{disposition}` (`REVOKED`, `SESSION_ALREADY_ENDED` or `NOT_SIGNED_IN`), 503 `REVOCATION_UNCONFIRMED`, cookie cleared | `POST /sfx/v1/session/logout`: 200 with the result of `identity.revoke_api_session`. That body isn't pinned in this repository; the desktop probe recorded 200 |

### Catalog

Legacy returns `{contractId: "circuit-catalog.v1", count, readAt, capabilities: [...]}`, with an
`ETag` and 304 support. Declared returns the `list-capabilities` array alone. Both returned the same
740 capability identities on 2026-10-31.

### Scenario, details, page and crosswalk

The legacy circuit host passes the reader's document through, adds `source: "database"`, and for a
scenario adds `svgDigest` and an `imageUrl` data URI to each slide. It turns reader statuses into HTTP
errors (details `NOT_FOUND` and `NOT_SELECTED` become 404, `NAMESPACE_MISMATCH` becomes 409), answers
refusals as `{error: "CODE"}`, and refuses a document whose selection doesn't match the request
(`CIRCUIT_SELECTION_MISMATCH`).

The declared API returns the reader's document unchanged:

- 200 for every outcome except `status: "NOT_FOUND"`, which is 404. `NAMESPACE_MISMATCH`,
  `NOT_SELECTED`, `NOT_DECLARED` and `DEGRADED` all arrive as 200, so read `body.status`.
- A failed read is `{error: {code, message}}`: 404 when `message` ends in `_NOT_FOUND`, 409 for
  `_SNAPSHOT_CHANGED` or `_NAMESPACE_REQUIRED`, otherwise 422. `code` is often the generic
  `CELL_EXECUTION_FAILED`; the specific reason is in `message`.

### Provider inspection

| Legacy | Declared |
| --- | --- |
| `{providerId, definitionDigest, snapshotDigest, reader, readAt, resultSets}`; 409 `PROVIDER_DEFINITION_CHANGED` when the provider moved since the scene was read | `provider-inspection.v1`: `{status: "READ", resultSets: [{name, columns, rows}], identityResultSet, reader, …}`; no scene lookup or digest check |

### Admitting a run

| | Legacy | Declared |
| --- | --- | --- |
| Request | `{object: "capability", operation: "observe", subject, namespace?, input, callerSuppliedLabel?}`; any other `object` or `operation` is 400 | `{object, operation, subject, namespace, input}`; dispatched by `subject` and `namespace` alone, while `object` and `operation` are only recorded |
| Idempotency | `Idempotency-Key` honored, scoped per principal | Ignored |
| Answer | 202 at admission: `{runId, admissionRef, state: "admitted", capability, createdAt, cursor, retainedFrom, evictedCount, partial, output: {available, bytes, byteCap, overflow}, replayed?}`; cookie and CLI callers also get `evidencePersistence` and `estateCapture` | 200 when the run ends: `{status: "COMPLETED", runId, state, admittedAt, traceComplete}`; 422 `EVIDENCE_SESSION_REQUIRED` without a live session |
| Time bound | The client waits up to 630 s and reads the run while it executes | The whole request is bounded at 225 s (App Service stops at 230 s). A longer run loses its response, and with it the only copy of its run id |

### Run state, output and graph

| | Legacy | Declared |
| --- | --- | --- |
| State | The SDA run resource, flat, plus `evidencePersistence`; after capture, `{...run, persistence, trust}` from the evidence store. 404 `{error: "Run not found."}` | `{status: "READ", runId, run}`. For runs the declared API admitted, `run` is the record `admit-api-run` writes: `{runId, state, capability: {object, operation, subject}, exitCode, partial, output: {available}}`, with no timestamps, cursor or graphs. For runs the legacy host captured, `run` is the run resource it kept. 404 `{status: "NOT_FOUND"}` for a missing run, another principal's run, and every machine caller |
| Output | The scenario output document itself, `{contractId, payload}`; 409 when unavailable | `{status: "READ", runId, output: {contractId, payload}}` |
| Graph | One `execution-graph-captured.v1` projection `{observationType, graphId, canonicalGraphDigest, rootExecutionId?, cells, edges}`: the parent root by default, `?rootExecutionId=` selects another; 409 until captured | `{status: "READ", runId, graphs: [...]}`, every root |

### Events

| | Legacy | Declared |
| --- | --- | --- |
| Paged | `{runId, state, terminal, events, nextCursor, latestCursor, hasMore, retainedFrom, evictedCount, partial, gap?}`. Each event is `{eventId: "urn:sda-api:run-event:<runId>:<cursor>", cursor, at, recordedAt, occurredAt?, kind, payload, rootExecutionId?, admissionRef?, truncated?}`. Replay from the evidence store returns `{runId, events (at most 128), latestCursor, retainedFrom: 1, gap: null}`, or 409 while the retained trace is incomplete | `{status: "READ", runId, chunkCount, chunks}`: the trace chunks as the run store keeps them. Chunks the legacy host captured hold brotli-compressed JSON in base64 (`{firstCursor, lastCursor, recordCount, sha256, content}`, [`evidence-store.mjs`][evidence-store]), so the client has to decompress and verify them. `after`, `limit` and `kinds` are not read |
| Stream | SSE: `event: <kind>` with `data: <event>`, ending `event: end` with `{runId, state, cursor}` | 501 |

## Cross-cutting differences

| Topic | Legacy | Declared API |
| --- | --- | --- |
| Credentials | Circuit routes: cookie only. `/auth/v1`: bearer. `/v1`: machine token or user bearer | Bearer or the `__Host-sfx-session` cookie. No machine carrier (EV-014) |
| Cookie writes | Same-origin JSON enforced on every cookie POST | `cookieWrites: same-origin-json` is declared but not enforced: the ingress reads neither `Origin`, `Sec-Fetch-Site` nor `Content-Type`. Nothing sets the cookie on this origin today, so it can't be exploited yet; it must be enforced before anything does |
| Error bodies | Four shapes: `{error: "CODE"}` (circuit reads), `{disposition}` (sessions), `{error: "<sentence>"}` or `{disposition, error}` (run proxy), `{error: {code, message, details?}}` (SDA) | `{error: {code, message?}}` for refusals (no `message` on `OPERATION_NOT_DECLARED` or `CALLER_REQUIRED`), `{status}` for sign-in |
| Status of a declared outcome | Mapped to 404, 409 or 422 by the circuit host | 200 unless `status` is `NOT_FOUND` |
| Frontdoor refusals | — | 401 `CALLER_REQUIRED`, 403 `CALLER_NOT_ADMITTED`, 404 `OPERATION_NOT_DECLARED`, 501 `OPERATION_DISPATCH_NOT_DECLARED`, 502 `FRONTDOOR_RESPONSE_INVALID` |
| Unknown route | The gateway's HTML 404 page | JSON 404 `OPERATION_NOT_DECLARED` |
| Query decoding | `URLSearchParams` | Each key and value decoded once, `+` as a space, since 2026-10-31 (next section) |
| Read cache | 30 s server cache, shared in-flight reads, `ETag` and 304, `refresh=1` | `cache` and `refresh` are declared on six reads but nothing serves them: every response is `Cache-Control: no-store` without an `ETag`, and every request starts a kernel |
| Latency, 2026-10-31 | `/healthz` 0.18 s; session check 74 ms; region and execution reads 57 to 110 ms (none of these runs the kernel). Kernel-backed reads are fast on a 30 s cache hit; uncached reads were not measured. Sign-in about 5 s | 4.6 to 5.6 s for a refusal; catalog 6.6 s; provider inspection 18.5 s; admission takes as long as the run (11 s for a 46 KB output) |
| Time bounds | Reads 30 s, details and inspection 90 s, client run wait 630 s | 225 s per request, everything included |
| Request size | Observe body 1 MiB, sign-in 4 KiB | Kernel standard input 8 MiB (the interface declares 16 MiB) |
| Response headers | Vary by route | Always `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-store`, `Connection: close` |

## The query-decoding defect

Found 2026-10-31 by the [direct HTTP comparison][comparison] for `authenticate-ide-user`, with
nothing changed between rows except how the colon in `namespaceId` is written:

| Request | Legacy staging | Declared API |
| --- | --- | --- |
| Details, `sidefx%3Acapabilities` | 200 `READ`, 80 rows | 200 `NAMESPACE_MISMATCH` |
| Details, `sidefx:capabilities` | 200 `READ`, 80 rows | 200 `READ`, 80 rows |
| Scenario, `sidefx%3Acapabilities` | 200 `AVAILABLE`, 5 slides | 404 `CELL_EXECUTION_FAILED` |
| Scenario, `sidefx:capabilities` | 200 `AVAILABLE`, 5 slides | 200 `AVAILABLE`, 5 slides |

**Cause.** `resolve-request` reads the query with
`uri.GetComponents(UriComponents.Query, UriFormat.SafeUnescaped)` (the `query` bind in
[`providers/sfx-api-ingress.dependency.json`](../providers/sfx-api-ingress.dependency.json), arguments
`32` and `3`). `SafeUnescaped` decodes unreserved characters (`%20` becomes a space, as the README's
verification shows) but keeps RFC 3986 reserved characters encoded. `%3A` is confirmed. `%2F` follows
the same rule, so `path` on `/sfx/v1/pages` and `detailPointer` on scenarios should fail the same way,
since every `URLSearchParams` client encodes `/` there. `+` isn't read as a space either, while
legacy reads it as one.

**What the fix has to do.** Split the raw query on `&` and `=`, decode each key and value exactly
once as UTF-8 with `+` read as a space, then JSON-escape. The ingress program only calls constructors
and instance methods, never a static method such as `Uri.UnescapeDataString`. One way to work within
that:

1. Read the query `UriEscaped` (format `1`), so quotes, backslashes and control bytes inside values
   arrive as `%22`, `%5C` and `%00` to `%1F`.
2. Rewrite `%5C` to `%5C%5C`, `%22` to `%5C%22`, `%00` to `%1F` to `%5Cu00XX`, and `+` to `%20`.
3. Build the JSON members with the existing pair regex.
4. Decode the JSON text once, for example through a `System.Uri` instance and
   `GetComponents(…, UriFormat.Unescaped)`.

Each step needs a kernel run on WSL before the DEPENDENCY is declared again.

**Fixed 2026-10-31.** `resolve-request` now follows those steps, with members without a key and
empty members dropped (`&&`, a trailing `&` and `=x` used to make the query invalid JSON, losing all
of it). Before declaring, the program ran through the kernel's own resolver (`DeclaredProviderResolver`,
SDA `3296bc1`) on 25 targets against a reference decoder: the old program failed 16, six of them as
invalid JSON, and the new one none. It was then declared (README, Declaring), and the same 25 read
through `resolve-http-request` against the estate all match the reference.

**Acceptance.** The four requests above must return identical rows and slides for both spellings.
They need a signed-in session and have not been run since the fix. Read each of these through
`resolve-http-request` as well (done, all match): a `path` written `%2Fcircuit%2Fhome` and
written `/circuit/home`, and values containing `%26`, `%3D`, `%2B`, `+`, `%22`, `%5C` and `%C3%A9`.

## What the migration branch already does

sfx-platform's `codex/desktop-declared-session` has three commits on top of `origin/main` and isn't
merged:

- **Sign-in.** The desktop and CLI first send `GET /sfx/v1/session`. A 401 `CALLER_REQUIRED` selects
  the declared flow (`POST /sfx/v1/session`, `GET /sfx/v1/session` with `sessionExpiresAt`,
  `POST /sfx/v1/session/logout`), and a 404 keeps the legacy one. The stored profile records
  `sessionApi: "declared"` and uses the endpoint as the realm.
- **Reads.** [`desktop/src/declared-workspace.mjs`][adapter] keeps the packaged Explorer on its legacy
  contract. It maps the six circuit reads to `/sfx/v1` and wraps the catalog again. It also adds
  `svgDigest` and `imageUrl`, turns reader statuses back into legacy HTTP errors, and repeats the
  provider-inspection scene lookup and digest check. It answers `/session` and `/execution`
  (`globalObserver: false`) itself, forwards run routes to `/sfx/v1`, and answers anything else 501.
- **Explorer.** The global observer is dropped when `globalObserver` is false, and pages and the footer
  stop mounting declared regions.

The branch doesn't yet cover these:

- Run state, output and graph pass through unconverted. The Observe panel reads `result.state` and
  gets `{status, runId, run}`, which the [desktop compatibility probe][desktop-probe] also noted.
- After admission, the Observe panel opens the event stream, which answers 501.
- The adapter encodes queries with `URLSearchParams`, so it hits the query defect.
- Browser sign-in is unchanged.

## Before each client can move

**Declared API work** (this repository, all declarations), in the order the clients need it:

1. **Query decoding**, above: fixed and declared; the signed-in acceptance requests remain. Every
   circuit read with a namespace, page path or detail pointer depends on it.
2. **Run observation**: a trace for runs the declared API admits, and a run-scoped event stream or
   at least paged events with `after` (README "Next" item 2). Without it, Observe has no events in the
   desktop or browser, and the CLI's `--trace` gets nothing.
3. **Admission that fits long runs**: asynchronous admission, or a bound above the longest run, and
   the idempotency key.
4. **A "your runs" list**, the counterpart of `GET /api/circuit/v1/session/runs`.
5. **A machine carrier** (EV-014), for `--auth machine`, acceptance tooling and anything holding
   `SDA_API_TOKEN`.
6. **A browser session**, needed only if the browser Explorer moves: a cookie-setting sign-in that never
   returns the bearer to script, a signed-out session read, and enforcement of the same-origin rule for
   cookie writes.
7. **What has no counterpart and isn't planned in the README**: health and release identity, the global
   observer feed, estate execution reads and operator enrollment.
8. **A read cache**, or accepting about 5 s per read. The Explorer makes several reads per selection.

**sfx-platform work:**

- **Desktop.** Merge the branch's sign-in and adapter. Unwrap the `run`, `output` and `graphs`
  envelopes, and keep Observe usable without a stream until item 2 lands.
- **CLI.** Declared sessions work on the branch. Admission has to change from 202 and polling to the
  synchronous answer, and output has to be read from `{output}`. `--trace` has nothing to read and
  machine mode has no route.
- **Browser Explorer.** Stays on the legacy host until items 1, 2, 4 and 6 exist. It also needs the
  declared API under its own origin, or CORS, because the legacy host serves its pages.

**Recommendation.** Move the desktop and CLI first. They are bearer callers, declared sign-in already
works for them, and the branch adapter covers their reads once item 1 is fixed. Until item 8 is
addressed, each read takes about 5 s, and the desktop's Explorer will feel that. Keep the browser on
the legacy host until a browser session is declared.

## Sources

- **Legacy staging host.** sfx-platform `origin/main` [`72273b8`][platform]: [`gateway.mjs`][gateway],
  [`identity-policy.json`][identity-policy], [`observe-server.mjs`][observe-server],
  [`run-api.mjs`][run-api], [`identity-session.mjs`][identity-session], [`live-store.mjs`][live-store],
  [`evidence-store.mjs`][evidence-store], [`estate-host.mjs`][estate-host],
  [`region-host.mjs`][region-host], [`access-gate.mjs`][access-gate],
  [`circuit-host.json`][circuit-host]; scenario-driven-architecture
  [`sda-api-v1.authority.json`][sda-api].
- **Staging frontdoor.** sfx-platform [`frontdoor.mjs`][frontdoor] (#66).
- **Declared API.** This repository at `ae0f01d`:
  [`sidefx-api-interface.v1.json`](../authorities/sidefx-api-interface.v1.json),
  [`07-serve-http-request.dsl`](../declarations/07-serve-http-request.dsl),
  [`09-open-api-session.dsl`](../declarations/09-open-api-session.dsl), [`sej/`](../sej/),
  [`sfx-api-ingress.dependency.json`](../providers/sfx-api-ingress.dependency.json).
- **Migration branch.** sfx-platform `codex/desktop-declared-session` at `ef51f3f`.
- **Evidence.** The [direct HTTP comparison][comparison]; the desktop compatibility probe
  (`C:\lab\repos\sfx-platform\docs\analysis\desktop-api-compatibility-2026-10-31`, not committed); and
  unauthenticated `GET /sfx/v1/nope`, `GET /sfx/v1/session` and `GET /healthz` against both hosts on
  2026-10-31.

[platform]: https://github.com/BPMSoftwareSolutions/sfx-platform/tree/72273b8f5ac771d0fa01054042ad0983181f5d0b
[gateway]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/deploy/sda-kernel/gateway.mjs
[frontdoor]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/deploy/sda-kernel/frontdoor.mjs
[identity-policy]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/deploy/sda-kernel/identity-policy.json
[observe-server]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/dispatch-pair/observe-server.mjs
[run-api]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/run-api.mjs
[identity-session]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/identity-session.mjs
[live-store]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/live-store.mjs
[evidence-store]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/evidence-store.mjs
[estate-host]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/estate-host.mjs
[region-host]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/region-host.mjs
[access-gate]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/access-gate.mjs
[circuit-host]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/72273b8f5ac771d0fa01054042ad0983181f5d0b/live-circuit/circuit/circuit-host.json
[adapter]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/ef51f3f8587f8bc5d0bbbfc3fea1fc7f515602d2/desktop/src/declared-workspace.mjs
[comparison]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/ef51f3f8587f8bc5d0bbbfc3fea1fc7f515602d2/docs/analysis/standalone-api-comparison-2026-10-31.md
[desktop-probe]: #sources
[sda-api]: https://github.com/BPMSoftwareSolutions/scenario-driven-architecture/blob/a97847280ec04b33d83faf867fb12f5f8150cbaf/interfaces/sda-api/sda-api-v1.authority.json
