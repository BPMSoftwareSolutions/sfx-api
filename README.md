# sfx-api: the declared SideFX API

This repository serves the declared SideFX HTTP API at `https://sfx-api-test.azurewebsites.net/sfx/v1`.
The browser, desktop and installed operator CLI are clients maintained in [sfx-platform](https://github.com/BPMSoftwareSolutions/sfx-platform).
The CLI admits declaration writers through this same API. The former composite staging slot is stopped.

The interface, ingress, frontdoor and provider declarations live in the estate database. The kernel reads
that authority at execution time. Rebuild the image for changes to the hosting facade, kernel or container.

## How the declared API works

Every mechanic up to the profile schema boundary, the HTTP ingress included, is declared into the
estate (SEJ `sej-pure.v2` and our own dependency programs), and the kernel resolves it. The host is a
facade for hosting ([host/serve.py](host/serve.py)): it hands the raw request to a resident kernel
and writes back the raw response the kernel resolves.

## Structure

| Path | What it is |
| --- | --- |
| [host/serve.py](host/serve.py) | The hosting facade: the platform's HTTP server bound to a pool of resident kernels, each request one `serve-http-request` envelope (Python standard library) |
| [providers/sfx-api-ingress.dependency.json](providers/sfx-api-ingress.dependency.json) | The DEPENDENCY `sfx-api-ingress`: the ingress mechanics as C# programs the kernel's resolver runs (`resolve-request`, `compose-response`) |
| [authorities/sidefx-api-interface.v1.json](authorities/sidefx-api-interface.v1.json) | The interface as declared (`sidefx:authorities/sidefx-api-interface.v1`); a change is declared with `model-declare-semantic-object` |
| [sej/serve-api-request.sej.json](sej/serve-api-request.sej.json) | The frontdoor's SEJ: identify the caller, prepare the interface read, resolve the request, compose the response |
| [sej/answer-api-response.sej.json](sej/answer-api-response.sej.json) | Returns the refusal it is given, so refusals take the answer path |
| [sej/resolve-api-request.sej.json](sej/resolve-api-request.sej.json) | The resolve stage as a standalone capability, for verification |
| [sej/compose-api-response.sej.json](sej/compose-api-response.sej.json) | The respond stage as a standalone capability, for verification |
| [sej/read-run-state.sej.json](sej/read-run-state.sej.json), [sej/read-run-output.sej.json](sej/read-run-output.sej.json), [sej/read-run-graphs.sej.json](sej/read-run-graphs.sej.json) | The run views: each reads the run's evidence (`read-run-evidence`) and selects its slice |
| [sej/admit-api-run.sej.json](sej/admit-api-run.sej.json) | Run admission: register the run, run the capability and stage its output, carry the run id, complete the run |
| [declarations/01-sej-pure-overlay-bindings.sql](declarations/01-sej-pure-overlay-bindings.sql) | Binds the 14 `sej-pure.v2` operators the graph runner (`run-declared-graph-execute`) lacked |
| [declarations/02-resolve-and-compose.sql](declarations/02-resolve-and-compose.sql) | Declares `resolve-api-request` and `compose-api-response` |
| [declarations/03-serve-api-request.sql](declarations/03-serve-api-request.sql) | Declares `segments` on the interface operations, the frontdoor's SEJ, `answer-api-response` and `serve-api-request` |
| [declarations/04-run-views.sql](declarations/04-run-views.sql) | Resolves the run operations to the run store (`read-run-state`, `read-run-output`, `read-run-graphs`, `read-run-trace-chunks`) and answers 404 for a `NOT_FOUND` outcome |
| [declarations/05-admit-run.sql](declarations/05-admit-run.sql) | Resolves `admit-run` to `admit-api-run` and declares its first version |
| [declarations/06-admit-run-staged.sql](declarations/06-admit-run-staged.sql) | Admission with staged output (requires sfx-identity migration `007-run-output-stage` in sfx-dal) |
| [declarations/07-serve-http-request.dsl](declarations/07-serve-http-request.dsl) | The DSL of `serve-http-request`, the declared HTTP ingress |
| [declarations/08-resolve-http-request.dsl](declarations/08-resolve-http-request.dsl) | The DSL of `resolve-http-request`: the ingress read alone, without serving |
| [declarations/11-admit-api-run-live.dsl](declarations/11-admit-api-run-live.dsl), [12-open-api-run-stream.dsl](declarations/12-open-api-run-stream.dsl), [13-complete-api-run.dsl](declarations/13-complete-api-run.dsl) | Asynchronous runs: admission that answers an `execute-run` host directive, the stream directive for a run of the caller, and the completion the host invokes when a run ends (The host, Runs) |
| [sfx-api.config.json](sfx-api.config.json) | Host data: the selected kernel, the kernel commands of the request pool and the run workers, the run bounds, the HTTP address |
| [providers/sfx-identity-login.dependency.json](providers/sfx-identity-login.dependency.json) | The DEPENDENCY `sfx-identity-login`: sign-in against sfx-identity with Argon2id (`open-session`, `derive-tag`) |
| [deploy/Dockerfile](deploy/Dockerfile), [deploy/start.sh](deploy/start.sh) | The declared API's container: the host, the admitted kernel and the host facts the declared vault providers read; no credential material |

Each SEJ file is the authority of one capability namespace (`sidefx:capability:<file name>`).

## The ingress

`serve-http-request` is the declared HTTP ingress. Its input is the raw request as the facade
received it (`{contractId: serve-http-request-request.v1, raw}`; the kernel binds the text input at
`raw`), its output the raw HTTP/1.1 response. Its stages:

1. **read** (inline SEJ): the raw request text.
2. **ingress** (`sfx-api-ingress-resolve-port.v1`, the DEPENDENCY operation `resolve-request`): the
   method, the path split on `/` and decoded, the decoded query as JSON text, the body, and the session
   digest of the credential carrier. The carriers are `Authorization: Bearer` and, without one, the
   `__Host-sfx-session` cookie, each base64 of 32 bytes; the digest is SHA-256 of SHA-256 of the
   bytes, the same digest sfx-identity keeps for the session. The bearer is read and digested inside
   this one program and never returned. It also reads the client source (`X-Client-IP`, else the
   first `X-Forwarded-For` entry).
3. **prepare** (inline SEJ): the frontdoor's input `{request: {method, segments, query, body},
   caller}`, the caller `{sessionDigest}` when a carrier was presented and `null` otherwise.
4. **frontdoor** (`generic-capability-invocation.v1`): `serve-api-request`.
5. **shape** (inline SEJ): status, content type, body and the declared reason phrases; a frontdoor
   that does not answer `api-response.v1` is 502 `FRONTDOOR_RESPONSE_INVALID`.
6. **respond** (`sfx-api-ingress-compose-port.v1`, the operation `compose-response`): the status
   line, `Content-Type`, `Content-Length` (the UTF-8 byte count of the body), `Cache-Control: no-store`,
   `Connection: close` and the body.

The ingress mechanics are ours, declared up to the profile schema boundary in the estate's provider
chain: the DEPENDENCY `sidefx:dependencies/sfx-api-ingress` (definition `a8d6f423`), the mechanics
`sfx-api-ingress-resolve-port.v1` and `sfx-api-ingress-compose-port.v1`, the PROVIDERs
`sfx-api-ingress-resolve` (`13c047d6`) and `sfx-api-ingress-compose` (`f07ed911`), and their entries
and overlay bindings on the graph runner `run-declared-graph-execute`. The kernel's resolver runs the
programs; no SDA provider, contract or engine beyond the transformation port is named.

`resolve-http-request` runs the read and ingress stages alone and returns what the ingress reads:
how the API reads a request, without serving it.

## The frontdoor

`serve-api-request` is the frontdoor as one declared capability, its stages in sequence:

0. **identify** (SEJ `serve-identify-prepare`, `sql-database-reader` on sfx-identity, SEJ
   `serve-identify-lift`): `identity.resolve_api_session` resolves the session the caller's digest
   names (`{kind: user, principalId, sessionId}`, the digest as base64 or hexadecimal, sfx-dal
   migration `010-api-session-digest-base64`) and carries the request; a digest in neither form
   resolves no caller, and a caller presented without a digest passes through.
1. **prepare** (SEJ `serve-prepare-interface-read`): the read request for `sql-database-reader`.
2. **interface** (`generic-capability-invocation.v1`): `sql-database-reader` returns the interface
   authority `sidefx:authorities/sidefx-api-interface.v1` together with the request and caller. A
   dispatch answers only its own envelope, so the read carries them.
3. **resolve** (SEJ `serve-resolve-request`): matches the request against the declared operations by
   their `segments`, admits the caller against the operation's `callers` and binds the input from
   the interface's `inputTemplate` (`$path.`, `$query.`, `$caller.`, `$body`). A refusal (404
   `OPERATION_NOT_DECLARED`, 401 `CALLER_REQUIRED`, 403 `CALLER_NOT_ADMITTED`), or an operation kind
   with no declared dispatch (501 `OPERATION_DISPATCH_NOT_DECLARED`), goes to `answer-api-response`.
4. **dispatch** (`generic-capability-invocation.v1`): runs the operation's capability.
5. **respond** (SEJ `serve-compose-response`): `api-response.v1`. A declared outcome is 200 with the
   outcome as the body, or 404 when its `status` is `NOT_FOUND`; a refusal `{code, message}` is 404
   for `*_NOT_FOUND`, 409 for `*_SNAPSHOT_CHANGED` and `*_NAMESPACE_REQUIRED`, and 422 otherwise.

The run operations read the run store in sfx-identity. `read-run`, `read-run-output` and
`read-run-graph` are views that read the run's evidence and select one slice (`{status, runId,
run|output|graphs}`); `read-run-events` reads its trace chunks. A dispatch answers only its own
envelope, so each view names its slice itself and the request's filters stop at the dispatch: the
graph view returns every execution root, the events view every chunk. A caller without a principal
(machine) reads `NOT_FOUND` until machine runs are captured. `read-run-delivery` (the store holds no
delivery) answers 501. `admit-run` and `stream-run-events` resolve to the asynchronous run
capabilities (The host, Runs).

`admit-run` (`POST /sfx/v1/runs`) resolves to `admit-api-run-live` (The host, Runs). Until
2026-10-31 it resolved to the synchronous `admit-api-run`, which is still declared, a fan-out:

1. **root**: the run store registers the run under the caller's session (`evidence.register_run` in
   sfx-identity) and mints its id.
2. **execute** leg: the kernel runs the admitted capability, and the run store stages its output under
   its SHA-256 digest (`evidence.stage_run_output`); the leg settles only the digest.
3. **carry** leg: the run id, admission time and capability.
4. **join**: the run store completes the run from the staged output (`evidence.complete_staged_run`);
   the answer is `{status: COMPLETED, runId, state, admittedAt, traceComplete}`.

A dispatch answers only its own envelope, so the run id reaches the completion on its own leg; a join
carries a leg outcome only up to 16 KB (the kernel's `SettlementOutcomePayloadByteBound`), so the
output travels by digest. A fan-out edge joins one scenario's outcome to the next one's input, so the
capability has one contract for both. The run is admitted synchronously and completed with trace
cursor 0 (`TRACE_INCOMPLETE`) until the kernel's observation channel reaches the run's trace. A
caller without a live session (machine) is refused `EVIDENCE_SESSION_REQUIRED`. The idempotency key
is not honored yet: the input template carries no headers.

`read-circuit-catalog` (`GET /sfx/v1/circuits`) dispatches `list-capabilities`, the capability behind
the kernel's `capability list` command. `read-capability-graph` still answers 501: compile is a kernel
operation on the target's own graph, not a capability the dispatch can run.

The Estate reads (2026-11-01) serve the Estate pane without creating runs, under
`/sfx/v1/estate-execution/`:

| Path | Capability | Input |
| --- | --- | --- |
| `scopes` | `read-api-estate-scopes` ([16](declarations/16-read-api-estate-scopes.dsl)) | the caller principal |
| `topology` | `read-estate-execution-topology` | 500 capabilities, 2000 relationships |
| `activity` | `read-estate-execution-activity` | `estate`, `start`, `end`, `asOf`, `capabilityId`, `sourceId` from the query |
| `coverage` | `read-estate-execution-coverage` | none |
| `provenance` | `read-estate-execution-provenance` | 200 instances, `capabilityId` from the query |
| `revision` | `read-estate-execution-revision` | 200 instances, `capabilityId` from the query |

`scopes` answers `estate-scopes.v1`: the principal, the estate the topology reader selects when its scope
is readable (`{id: "estate:34", label, revision, scopeId: "sidefx:capabilities", read: true}`), and where
retained and live activity are read. The other five are the estate's declared readers with the legacy
circuit host's inputs, each answering its own `estate-*-result.v1`; the activity reader refuses an
empty, reversed or longer than 24-hour interval itself. The circuit host admitted each reader as a run,
polled it and composed the five into `estate-declared-readers.v1`; the client composes them now. One
declared read cannot: a fan-out join carries a leg outcome only up to 16 KB (topology is about 110 KB
and provenance 160 KB), and the activity, provenance and revision readers use INSERT...EXEC inside, so
no statement can capture them. The activity reader reads `model.execution_fact`, which the legacy
host's capture writes; runs this host executes are not captured there yet.

The estate's live observation channel is the legacy observer's publish/subscribe channel
([features/estate-live-observation.feature](features/estate-live-observation.feature)). Every event of
every run this host executes is published into it, and any signed-in session subscribes from any
machine at `GET /events`, as the observer served it, or at `GET /sfx/v1/estate-execution/stream`. Both
resolve to `subscribe-estate-live-observation`
([21](declarations/21-subscribe-estate-live-observation.dsl)), which confirms the caller session and
answers the host directive `stream-estate`. The host reserves each event's position in one sequence and
asks `publish-estate-live-observation` ([19](declarations/19-publish-estate-live-observation.dsl)), in
batches on a kernel of its own, for the frame every subscriber then writes unchanged:

    id: 58
    data: {"seq":58,"observationKey":"sfx-observer:<channel>:58","receivedAt":"…","kind":"run-start","runId":"sfx-api:<run>","api":{"eventId":"urn:sfx-api:run-event:<run>:2","cursor":2,"kind":"run.started","recordedAt":"…","runId":"<run>","subject":{"capabilityId":"…","namespaceId":"sidefx:capabilities"}},"glyph":"▶","cls":"run","text":"pid=…","payload":{…}}

The record is the observer's `{seq, observationKey, receivedAt, kind, runId, api, glyph, cls, text,
payload}`. The stream opens with `retry: 3000`, replays the published frames after `since` (or
`Last-Event-ID`; without either, none), writes `: replay-complete`, then each new frame as it is
published, with `: keep-alive` while quiet. `run=current` (narrowed by `graphId`), `run=<n>` and
`run=next` follow one run: the host keeps the run windows publish's window effects describe, and
`select-estate-live-observation` ([20](declarations/20-select-estate-live-observation.dsl)) chooses the
window whose frames the stream writes; a refused `run` or `since` answers 400. Each request this host
answers is published as well, as an execution of `serve-http-request` with the capability it resolved
to as its nested invocation (`observation.requests` in the host data). The `x-observer-instance` header names the channel: a host
restart begins a new sequence. A run's `run-end` is published only once its completion stored its
output, which `GET /api/circuit/v1/runs/{runId}/output`, the legacy path, also reads. The stream ends
with `: session-ended` at the session expiry or at the first `check-api-session` recheck that cannot
confirm it.

## The host

[host/serve.py](host/serve.py) is a facade for hosting. The platform's HTTP server (Python's
`ThreadingHTTPServer`: the accept loop, a thread per connection, the request head) receives a
request; the facade's one method, bound to each HTTP method, takes a kernel from a pool of resident
kernels, sends it the request as the platform read it (the request line, the header block, and the
body by its declared length) as one `sfx-command-delivery.v1` envelope invoking `serve-http-request`
with text input, and writes the kernel's resolved response to the connection. The kernels keep
running between requests (`--resident-envelopes`: one envelope per line on stdin, one delivery per
line on stdout), so a request pays no kernel start. The facade's only state is that pool and its only
handling is the kernels' lifecycle: a kernel starts on first use, and one that exits or does not
answer within `answerTimeoutMs` is stopped and started again for its next request. Routes, callers,
refusals and responses stay declared. It runs on the Python standard library: nothing is installed
or built.

    KernelEntry --resident-envelopes --config kernel-host.json --timeout 225000

The command, the pool size (`instances`), the answer bound and the envelope's request are host
data in [sfx-api.config.json](sfx-api.config.json). Each kernel holds about 260 to 350 MB, so the pool
is one kernel: `sfx-api-test` shares a 4 GB plan whose memory already averages 57 to 67%. A request
waits for a free kernel, and a client that gives up still holds its kernel until the kernel answers.
A kernel that fails writes no delivery: the platform closes the connection without a response (the
front end answers 502), and the kernel's error reaches the host's stderr. `--timeout` bounds each
delivery at 225 s, not the kernel's life (App Service stops a request at 230 s). The 8 MiB
standard-input bound of a per-request kernel is not established for a resident envelope.

### Runs

A run outlives the request that admits it, so its answer cannot be one response. For a run the kernel
answers a **host directive** instead: a response of type `application/vnd.sfx.host-directive+json`,
written only by the declared capabilities the interface resolves the run operations to. The facade
does what the directive says and decides nothing itself:

- `execute-run` (from `admit-api-run-live`): answer the directive's response (202 with the run), then
  queue the run's `observe` envelope for a worker kernel. The workers are a second pool of resident
  kernels, started on first use. The envelope asks the kernel for the run's observations
  (`observation: {sample: true, ref: <runId>}`, delivery-observation.v1); nothing else a worker runs
  is observed. Each `SFX_OBSERVATION` line the worker writes for the run becomes the run's next event
  (`{eventId, cursor, at, kind, payload, rootExecutionId?}`, kind the record's `observationType`, else
  `observation`) and reaches every listener as it is written. The kernel writes them from a queue of
  its own, so they end at its `observation-stream-closed.v1` frame for the run, which can come after
  its answer; the host waits for that frame, or for the kernel's stream to end, never for silence.
  Lifecycle events frame them: `run.admitted`, `run.started` and `run.exited` with the state, exit
  code, failure and `capture` (`{records, dropped}` from the closing frame, or `{complete: false}`
  when the stream ended without one). When the run ends, the worker retains its events
  through the directive's trace capability (`append-api-run-trace`), contiguous chunk by chunk within
  `traceChunkBytes` and `traceChunkEvents`, then invokes its completion capability
  (`complete-api-run`) with the last retained cursor, and only then ends the run. A refused chunk stops
  the trace there; the completion then records the shorter trace, and the store marks it incomplete.
- `stream-run` (from `open-api-run-stream`): answer server-sent events in the legacy framing:
  `id: <cursor>`, `event: <kind>`, `data: <event>`, every event after the cursor (`?after=`, else
  `Last-Event-ID`), then each new event as it arrives, a `: keepalive` comment while the run is quiet,
  and `event: end` with `{runId, state, cursor}` once the run has ended and been completed. A run this
  host does not hold ends at once with the state the run store holds. A session caller's stream ends
  with `event: session-ended` (`{runId, cursor}`) at the session's expiry, or at the first recheck
  that cannot confirm the session: `check-api-session`, every `recheckMilliseconds` the interface
  passes (5000, as `callers.user.sessionRecheckMilliseconds` declares), one answer per session per
  interval shared by its streams.
- `respond` (a replayed idempotency key): answer the directive's response and execute nothing.

The idempotency key is the `Idempotency-Key` header (the ingress returns it as
`headers.idempotency-key`, `serve-http-request` carries `headers` to the frontdoor, and the interface
binds `$header.idempotency-key`) or the body's `idempotencyKey`; both given, they must agree
(`IDEMPOTENCY_KEY_CONFLICT`). The same key from the same caller names the same run.

The trace is the run store's encoding, as its other writers write it: each chunk is the events as one
JSON array, UTF-8, brotli-compressed, with the SHA-256 of the compressed bytes. The encoding is a
declared program, the DEPENDENCY `sidefx:dependencies/sfx-api-run-trace`
([providers/sfx-api-run-trace.dependency.json](providers/sfx-api-run-trace.dependency.json), `encode-chunk`:
`BrotliStream` and `SHA256Managed`), bound as the PROVIDER `sfx-api-run-trace-encode` on the graph
runner; Python's standard library has no brotli.

The worker command (with a longer `--timeout`, one hour), the worker count and the run bounds
(`retained` ended runs kept for reconnects, `maxEvents` per run, `eventPayloadBytes` before a record
is cut to its key members, `traceChunkBytes` and `traceChunkEvents`, `keepaliveSeconds`) are host
data. A worker kernel adds about 350 MB once the first run starts it.

Live since 2026-10-31 on `sfx-api-test` (image `fd1fd6d4`, commit `64f3a28`, then image `6a019421`,
commit `26aeb9d`, for the trace and the session rule): `admit-api-run-live`, `open-api-run-stream`,
`complete-api-run`, `append-api-run-trace` and `check-api-session` are declared
([declarations/11](declarations/11-admit-api-run-live.dsl) to [15](declarations/15-check-api-session.dsl)),
and the interface resolves `admit-run` and `stream-run-events` to them (definition `263423`; definition
`253230` resolved `admit-run` to the synchronous `admit-api-run`, and re-declaring it rolls back).
Verified:

- the facade against a stand-in kernel, 22 checks: 202 at admission, events delivered as written over
  2 s, another request answered during a run, resume by `Last-Event-ID` and `after`, a replayed key
  executing nothing, a failed run, keepalives;
- the capabilities against the estate, 16 checks: the execute-run directive with its 202 answer and
  observe envelope, a replayed key answering the same run without execute-run, the same key for another
  capability refused `IDEMPOTENCY_KEY_CONFLICT`, a caller without a live session refused
  `EVIDENCE_SESSION_REQUIRED`, the owner's stream directive and another principal's `NOT_FOUND`, and
  run `0c5c9150` of `verify-password-derivation` executed by the facade's worker, streamed live (43
  events, its graph capture among them) and completed in the run store (`completed`, exit 0, output
  `MATCHES` read back);
- `sfx-api-test` after the switch, without a session: `POST /runs` and the stream answer 401
  `CALLER_REQUIRED`, as before;
- the trace and session rule: the facade against the stand-in, 7 more checks (chunks 1-4, 5-8, 9 and
  `latestCursor` 9; a refused chunk stopping at cursor 4; a directive without trace; a stream ending
  `session-ended` at expiry after 2.00 s; two streams ending at the first failed recheck with 3
  rechecks, not 6); `encode-chunk` through the kernel's own resolver, decoded by .NET and by the legacy
  evidence store's decoder; against the estate, chunks appended, an overlap refused
  (`EVIDENCE_CHUNK_OVERLAP`), a chunk after completion refused (`EVIDENCE_RUN_CLOSED`), and run
  `f8a01553` executed by the facade, streamed through three live `check-api-session` rechecks, retained
  as 4 chunks to cursor 43 and completed with its trace complete, its 43 events read back by the
  legacy decoder identical to the stream;
- the header: the ingress program through the kernel's resolver (present, case, padding, absent,
  quotes and backslashes, a longer header name), and the resolve stage through the kernel's SEJ engine
  (every other operation resolves identically; the admission binds the header).

The signed-in journey over HTTP (sign in, admit, stream, reconnect, read back) needs a session and has
not run yet.

The bearer enters only the kernel's ingress provider, which digests it and never returns it: the
frontdoor, sfx-identity and every run see `{sessionDigest}`, which `identity.validate_session` does
not accept, so nothing past the ingress carries a verification handle. The bearer text appears neither
in the kernel's observations (`SIDEFX_OBSERVE=1`) nor in the delivered envelope's testimony; with
resident kernels, a random bearer appeared in none of a request's 55 observation lines. Machine
callers have no carrier yet (EV-014).

    wsl -d Ubuntu --exec sh -c 'cd /mnt/c/lab/repos/sfx-api && python3 host/serve.py sfx-api.config.json'

## Deploying

The image is built in the registry from a context of [deploy/Dockerfile](deploy/Dockerfile),
[deploy/start.sh](deploy/start.sh), [host/](host/), [sfx-api.config.json](sfx-api.config.json) and the
admitted kernel install under `kernel/`, assembled at a short path (the kernel's authority tree
exceeds the Windows path limit under a deep directory):

    az acr build --registry bpmaiengineacr --image sfx-api:<commit> --build-arg KERNEL_DIGEST=<digest> --file <context>\Dockerfile <context>

The image holds no credential material. The host and the kernel live under `/opt/sfx`; `/home` is
App Service's persistent storage (`WEBSITES_ENABLE_APP_SERVICE_STORAGE` true), where the sealed vault
and the keyring stay across restarts, so a credential stored with `store-credential` survives every
deploy, as on the legacy host. `start.sh` begins as root, establishes `/home/sjones` on that mount and
drops to `sjones`. It writes the sealed vault only when `/home` has none, and the key record and the key
at every start, from three App Service settings that reference Key Vault secrets
(`sfx-api-credential-vault`, `sfx-api-credential-vault-key-record`, `sfx-api-credential-vault-key` in
`aiengine-kv-20260406`). It puts the key into a gnome-keyring under the reference the declared vault
providers read, with the session bus and the keyring's control socket under `/tmp` (a Unix socket cannot
live on the storage share), and starts the host on port 8787 (`WEBSITES_PORT`). The test app is `sfx-api-test` on the plan
`ASP-sidefxgroup-ad2e`; its system identity pulls from the registry (`AcrPull`) and reads the vault
(`Key Vault Secrets User`).

## Declaring

Use the installed operator CLI to sign in with `sfx-api login --endpoint https://sfx-api-test.azurewebsites.net`.
Check the selected endpoint with `sfx-api whoami --json`. Writer admissions use `POST /sfx/v1/runs`;
read the result and evidence with `sfx-api run <id> --json --events`.
Run `890c91f6-d6c9-966d-203b-e7c3ae8729d4` executed a no-op writer through this path after the old slot was stopped.
[Platform cutover receipt](https://github.com/BPMSoftwareSolutions/sfx-platform/pull/78)

Run the files in [declarations/](declarations/) in order against the estate database. Each runs in one
transaction through installed writers (`model.declare_port_provider_binding`,
`model.declare_transformation`, `model.declare_semantic_object`,
`model.apply_capability_from_dsl`); nothing commits unless every statement succeeds. A declaration
embeds the SEJ files as they were when it was written; a changed SEJ file needs its declaration
rewritten. A declaration that revises an existing transformation passes its current definition
digest (`@expected_digest`). 01 to 05 were applied to the estate on 2026-10-30.

06 was applied through the declared-change runner (`apply-declared-change`, kinds
`transformation-declaration` and `capability-from-dsl`), the route for writer calls: it executes on
`sql-server-client`'s execute operation, which reads every result set. `sql-database-reader` returns
only the first result set and needs its result column to be JSON text, so it cannot run a script whose
writers return result sets of their own; it does run an sfx-identity migration whose first result set
is its JSON `value` (sfx-dal `007-run-output-stage`, dry run first with its rollback twin).

Since 06 every change is declared through the estate rather than a file run by hand: transformations
and capabilities through `apply-declared-change`, the interface through `model-declare-semantic-object`
from [authorities/sidefx-api-interface.v1.json](authorities/sidefx-api-interface.v1.json) after
checking that the live interface still equals the last declared one, and sfx-identity migrations
through `sql-database-reader` on `sfx-identity-database`.

The ingress (2026-10-30) was declared the same way, each row read back before the next cites it:

1. The DEPENDENCY from [providers/sfx-api-ingress.dependency.json](providers/sfx-api-ingress.dependency.json)
   (`model-declare-semantic-object`), then per operation its mechanic
   (`model-declare-platform-capability`), its PROVIDER on the stored DEPENDENCY digest
   (`model-declare-provider-identity`, labelled with `model-set-definition-label`), and its runner
   entry and overlay binding (`model-declare-port-provider-binding`; a read of the runner counts both).
2. The capabilities from [declarations/07-serve-http-request.dsl](declarations/07-serve-http-request.dsl)
   and [declarations/08-resolve-http-request.dsl](declarations/08-resolve-http-request.dsl)
   (the legacy CLI: `sfx-api capability author --dsl <file>`).
3. Their text input (`capability-interface-change`: `inputType text`, `inputPath raw`). The DSL
   declares JSON inputs only, and a DSL declaration resets the input, so this follows every
   re-declaration. The kind took a type other than JSON and a path once it was re-registered
   (`change-kind-registration`, the adapter on `model.declare_capability_interface`'s own
   `@input_path`).

A change to an ingress program is a revision of that chain, because the kernel runs the copy of the
program in the runner's provider entry, and the PROVIDER and the runner each pin a digest. The query
decoding fix (2026-10-31) went in this order, through the legacy CLI:

1. `model-declare-semantic-object`: the DEPENDENCY, now definition `e8813515` (run `dcd49b97`).
2. `model-declare-provider-identity` with `expected_digest` set to the current definition: the PROVIDER
   `sfx-api-ingress-resolve` with the new program, `dependency.definitionDigest` and
   `profile.sourceAuthorityDigest` set to the new DEPENDENCY, and `profile.profileDigest` recomputed
   (`sha256:` and the SHA-256 of the compact JSON of the profile without `profileDigest`, members in
   their order). Now `8051eab0` (run `f4d8d411`).
3. `model-set-definition-label`: the new definition labelled with the PROVIDER's name (run `e833fd52`).
4. `model-declare-port-provider-binding` on `sidefx:capability:run-declared-graph/run-declared-graph-execute`:
   the provider entry (the new program, `sourceProviderDefinitionDigest` the new PROVIDER) and the overlay
   binding (`providerProfileDigest` the new profile). It upserts only those two elements (run
   `4b9349de`); a read of the runner before and after showed nothing else changed.

`sfx-api-ingress-compose` was left as it is: its program did not change, and it still cites the
DEPENDENCY definition `39ffb87e`, which remains in the estate.

The same chain carried the `Idempotency-Key` header (2026-10-31, later): DEPENDENCY `a8d6f423` (run
`b165fbbe`), PROVIDER `13c047d6` (run `f7a66840`), its label (`99ef3788`) and runner binding
(`c2481b51`). Then `serve-http-request` was declared again to carry `headers` to the frontdoor, with its
text input re-applied at once (`f254cb85`, 28 s between the two), the frontdoor's
`serve-resolve-request` revised through `apply-declared-change` (`transformation-declaration`,
`expectedDigest` the current definition; now `de026dfa`, run `b836bf17`) to bind `$header.`, and only
then the interface mapping `$header.idempotency-key` (definition `263423`, run `a4add720`). That order
matters: before the frontdoor knew `$header.`, the interface's template would have bound the literal
string to every admission.

A new provider follows the same chain from the start: the trace encoding's DEPENDENCY
`sfx-api-run-trace` (`da5ee4ad`, run `310be6b8`), its mechanic `sfx-api-run-trace-encode-port.v1`
(`model-declare-platform-capability`, run `d52680e6`), the PROVIDER `sfx-api-run-trace-encode`
(`ada61f18`, run `d6b9ef21`, without `expected_digest`), its label (`bcbaabda`) and runner binding
(`010bc1ee`).

## Verified

The facade over real HTTP on WSL, each request one kernel run of `serve-http-request` (6 of 6, run
concurrently in 15.2 s; one request alone 6.8 s):

| Request | Answer |
| --- | --- |
| `GET /sfx/v1/session`: no credential, an unknown bearer, a malformed bearer | 401 `CALLER_REQUIRED` |
| `GET /sfx/v1/runs/{run}` with an unknown session cookie | 401 `CALLER_REQUIRED` |
| `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` |
| `POST /sfx/v1/runs` with a JSON body, no credential | 401 `CALLER_REQUIRED` |

Every answer carried `Content-Type: application/json; charset=utf-8`, `Connection: close` and a
`Content-Length` equal to its body's bytes. The ingress read (`resolve-http-request`, 6 of 6) against
values computed outside the kernel:

| Raw request | Read |
| --- | --- |
| `POST /sfx/v1/runs?limit=2&cursor=a%20b`, a random bearer, a JSON body | the session digest equals SHA-256 of SHA-256 of the bearer bytes; query `{limit: "2", cursor: "a b"}`; the body |
| `GET /sfx/v1/runs/abc/output`, the session cookie among others | the cookie's digest |
| a bearer and a session cookie | the bearer's digest |
| a malformed bearer; no carrier | not carried |
| text that is not HTTP | empty members |

The owner's live session digest, as base64, resolves the owner through the frontdoor
(`GET /sfx/v1/session` 200, kind `user`); an unknown base64 digest is 401. A path segment holding an
encoded slash (`%2F`) is split there: the ingress decodes the path before it splits it.

One kernel start is about 1.6 s and the ingress read alone 2.4 s; a request through the frontdoor is
6.7 to 7.3 s.

With resident kernels (2026-10-31, WSL, kernel `9f78e78d`, over real HTTP): a kernel's first request
6.4 to 7.0 s, then 3.8 to 4.1 s; four concurrent requests over two kernels 9.5 s; a refused sign-in
1.5 s; 30 abandoned requests queued the next request 68 s and left the kernels healthy. A warm
`GET /sfx/v1/nope` (4.6 s with observations on) spends about 1.0 s before its first delivery phase,
1.8 s reading the definitions of its five capabilities (`serve-http-request`, `serve-api-request`,
`sql-database-reader` twice, `answer-api-response`) from the estate, 0.7 s in the two SQL reads and
1.1 s executing.

Kernel `39881693` (SDA `3296bc1`) reports what each envelope resolves (`outcome.evidence.declarations`).
Warm, on WSL against the estate, `GET /sfx/v1/nope`, `GET /sfx/v1/session` and
`GET /sfx/v1/capabilities` each resolve the same 15 definitions, all read from the estate: 2.8 to
3.0 s of a 3.6 to 3.9 s kernel window, with session setup 0.25 to 0.29 s. That is about the earlier
1.0 s and 1.8 s together. The reads cross from WSL to Azure SQL; from `sfx-api-test` each costs less.

Since the estate declared `declaration_generation` (2026-10-31, sfx-embody
`sql/migrations/declare-declaration-generation.sql`: change tracking on the 50 tables those reads
depend on), the kernel holds the 15 definitions per generation. On WSL against the estate:

| | Before | After |
| --- | --- | --- |
| A warm request over HTTP (two kernels) | 3.8 to 4.1 s | 1.10 to 1.32 s |
| Definition resolution in a warm envelope | 2.8 to 3.0 s, 15 reads | 0.3 to 20 ms, 0 reads |
| A refused sign-in | 1.5 s | 0.56 s |

Cached and uncached envelopes answered identically (response, graph digests, every cell's outcome).
A rolled-back write left the generation and the next envelope stayed warm; a committed write moved it,
and the next envelope read its definitions once and was warm again. On `sfx-api-test` (one resident
kernel, image `f32450fa`), 30 sequential requests took a median 0.88 s of server time (4.74 s with a
kernel per request) and a refused sign-in 0.47 s (2.18 s); see
[docs/azure-test-2026-10-31.md](docs/azure-test-2026-10-31.md). Each kernel's first two requests
still read: the first starts the kernel (5 to 6 s) and the second refreshes once more (about 3 s),
because the kernel's first envelope reports a different generation for the same estate.

`serve-api-request` end to end on the WSL kernel `9f78e78d`, each a real run against the estate:

| Request | Answer |
| --- | --- |
| `GET /sfx/v1/providers/sfx-vault-file-host/inspection` (machine) | 200, `provider-inspection.v1` READ, 11 result sets (18.5 s) |
| `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` (4.6 s) |
| `GET /sfx/v1/providers/x/inspection` (no caller) | 401 `CALLER_REQUIRED` (4.5 s) |
| `GET /sfx/v1/retained-runs/r1` (machine) | 403 `CALLER_NOT_ADMITTED` (5.0 s) |
| `GET /sfx/v1/runs/abc` (machine) | 501 `OPERATION_DISPATCH_NOT_DECLARED` (4.7 s) |

The run operations, for a completed run of a user (10 of 10, run concurrently in 25.8 s):

| Request | Answer |
| --- | --- |
| `GET /sfx/v1/runs/{run}` (user) | 200, run state `completed`, exit code 0 |
| `GET /sfx/v1/runs/{run}/output` (user) | 200, the run's `project-tracker-result.v1` |
| `GET /sfx/v1/runs/{run}/graph` (user) | 200, one graph, root `execution:graph:read-project-tracker` |
| `GET /sfx/v1/runs/{run}/events` (user) | 200, one trace chunk, last cursor 19 |
| `GET /sfx/v1/runs/{missing}` (user) | 404, `NOT_FOUND` |
| `GET /sfx/v1/runs/{run}` (machine) | 404, `NOT_FOUND` (no principal) |
| `GET /sfx/v1/retained-runs/{run}` (user) | 200, `read-run-evidence` READ, capture complete |
| `GET /sfx/v1/runs/{run}/delivery` (user) | 501 `OPERATION_DISPATCH_NOT_DECLARED` |
| `GET /sfx/v1/providers/sfx-vault-file-host/inspection` (machine) | 200, 11 result sets |
| `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` |

Admission, admitting `read-project-tracker` (a 46 KB output) for a user with a live session (5 of 5):

| Request | Answer |
| --- | --- |
| `POST /sfx/v1/runs` (user, session) | 200, `COMPLETED`, run `cee9eb91`, state `completed` (11.0 s) |
| `GET /sfx/v1/runs/{run}` | 200, state `completed`, output available |
| `GET /sfx/v1/runs/{run}/output` | 200, the run's `project-tracker-result.v1` (1 project, 10 tasks) |
| `GET /sfx/v1/retained-runs/{run}` | 200, the caller's session, capture `incomplete` (no trace yet) |
| `POST /sfx/v1/runs` (user, no session) | 422 `EVIDENCE_SESSION_REQUIRED` |

The earlier host (resident kernels, the digest computed in the host) over real HTTP and the identity
stage (7 of 7), and the catalog:

| Request | Answer |
| --- | --- |
| frontdoor, caller `{sessionDigest}` of a live session | resolves the session's principal; `GET /sfx/v1/runs/{run}` 200 |
| frontdoor, a pre-resolved caller | passes through; 200 |
| frontdoor, no caller | 401 `CALLER_REQUIRED` |
| HTTP: no credential, an unknown bearer, an unknown session cookie, a malformed bearer | 401 `CALLER_REQUIRED` |
| HTTP: `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` |
| `GET /sfx/v1/circuits` (user) | 200, 730 capabilities (6.6 s) |

The digest formula is checked against SQL Server's (`HASHBYTES` twice over 32 zero bytes equals
SHA-256 twice). A warm resident kernel answered in about 4.7 s: the frontdoor's reads each open the
vault and a connection.

Each run starts a kernel process; the times include its start. The resolve and respond stages also
passed 15 of 15 cases as standalone capabilities: matching, nested payload binding, user-only
operations, `$body`, every refusal and the four response mappings.

What the kernel's SEJ taught the declaration, each found by a run:

- A transformation on the transformation port is one expression: `call` to another transformation
  does not resolve, so each stage composes its parts with `let`.
- `lookup` does not index arrays and `object-entries` takes objects only, so the request path is
  read by position (`segments.0` to `segments.9`, by static path) into an object first.
- `matches` matches the whole string, so a suffix test is `^.*_NOT_FOUND$`.
- An expression that fails returns the cell input unchanged, so a check compares the declared
  answer, never only that the run completed.
- Every operator needs an overlay binding on the graph runner (`01-sej-pure-overlay-bindings.sql`).

## Local testing

The local runtime for the declared API is WSL Ubuntu, with the same host facts as its container
(`sfx-api-test`) and as the legacy staging host: user `sjones`, `HOME=/home/sjones`, `secret-tool`
and the vault at `~/.local/share/sfx/vault/vault.json`. The estate's declared vault providers run
there unchanged, so every capability runs locally as it does on Azure.

- **Kernel:** built and installed from `C:\lab\repos\scenario-driven-architecture`
  (`ScenarioKernel install --rid linux-x64 --estate C:\lab\repos\sfx-embody`) and placed at
  `/opt/sfx/kernel/<digest>/` with its entry executable, as in the container. The digest and that
  root are in [sfx-api.config.json](sfx-api.config.json).
- **Vault:** the vault file holds the estate's credentials, `SFX_ESTATE_DATABASE` and
  `SFX_IDENTITY_DATABASE` among them; the key record
  `~/.local/share/sfx/credential-vault-keys/0f2fb3b5….json` names its `vaultId`. A credential is
  provisioned into this machine's vault (`KernelEntry.exe provision --reference-name <name>`) and the
  vault copied into WSL (`wsl -d Ubuntu --exec cp "/mnt/c/Users/<user>/AppData/Local/sfx/vault/vault.json"
  /home/sjones/.local/share/sfx/vault/vault.json`); both vaults share one `vaultId`.
- **Key:** the Secret Service item `service sfx-credential-vault key 0f2fb3b502843c274efcadf4856f631a`
  in `Default_keyring`. The keyring has a blank password, so gnome-keyring stores it unencrypted and it
  never locks: runs need no unlock after WSL restarts. The key is then protected by the Windows account
  and disk encryption only.
- **Run:** pipe a raw HTTP request into the facade's command in the install root, for example
  `printf 'GET /sfx/v1/nope HTTP/1.1\r\nHost: x\n\n' | ./KernelEntry capability invoke serve-http-request --input - --input-type text --json --config kernel-host.json`
  (`resolve-http-request` reads the same request without serving it), or an `sfx-command-delivery.v1`
  envelope into `./KernelEntry --stdin-envelope --config kernel-host.json`, for example
  `{"deliveryType":"sfx-command-delivery.v1","operation":"invoke","request":{"object":"capability","verb":"invoke","subject":"serve-api-request","input":"<request JSON>","inputType":"json"}}`.

The Windows kernel is not a local runtime for these providers: it denies child processes (a job
object, in every isolation profile) and runs at low integrity, and the providers' key release is a
`secret-tool` process.

## Next

1. **Deployment:** [the declared API's Azure app `sfx-api-test` is live](docs/azure-test-2026-10-31.md),
   with its role grants, approved Key Vault bootstrap and authenticated execution/read-back verified.
   The staging browser and the signed-in Windows CLI use this API.
2. **Asynchronous runs and their live stream** (The host, Runs): live on `sfx-api-test` with the
   retained trace, the session rule on streams and the `Idempotency-Key` header; signed-in
   browser observation and run read-back passed on staging. Then: the graphs per execution root in the run store, machine runs
   (EV-014), and more than one worker (each adds about 350 MB on the shared plan).
3. **The capability graph:** compile is a kernel operation, not a capability.
4. **Session operations:** sign-in (`POST /sfx/v1/session`), session read and sign-out are served;
   sfx-platform's signed-in acceptance (2026-10-31) passed against `sfx-api-test`.
5. **Performance:** resident kernels removed the kernel start (a warm request is about 3.9 s on WSL;
   `sfx-api-test` runs one resident kernel). With the declaration cache (SDA `3296bc1`) and the
   estate's `declaration_generation`, a warm request is about 1.1 s on WSL and a median 0.88 s of
   server time on `sfx-api-test`, with one request in six taking 1.2 to 4.0 s for a reason not yet
   recorded (the facade keeps no kernel evidence). What remains: the frontdoor's two SQL reads each
   open the vault and a connection; session setup is 0.27 to 0.34 s, including the generation read;
   each kernel's second request refreshes once more than it needs to; the declared read cache is not
   served; and a client that gives up still holds a kernel until it answers.
