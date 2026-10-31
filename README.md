# sfx-api: the declared SideFX API

This repository is **the new SideFX API**: the HTTP API declared as
`sidefx:authorities/sidefx-api-interface.v1`, served by a hosting facade and the kernel, and deployed
as the Azure app `sfx-api-test`. **It is not the legacy `sfx-api` CLI.** The two only share a name.

## Two different things are called sfx-api

| | **The declared API** (this repository) | **The legacy `sfx-api` CLI** (not in this repository) |
| --- | --- | --- |
| What it is | The new HTTP API: every operation declared in the estate, served by [host/serve.py](host/serve.py) and the kernel | An installed command-line client: `sfx-api capability observe ...`, `sfx-api capability author ...`, `sfx-api run ...`, `sfx-api login` |
| Its code | This repository | Elsewhere. Nothing here builds, configures, ships or depends on it |
| Where it runs | Azure App Service `sfx-api-test` (`https://sfx-api-test.azurewebsites.net`, image `bpmaiengineacr.azurecr.io/sfx-api`), and locally on WSL | The developer's machine. It calls **the legacy staging host**, `https://sidefx-staging-fyfhb9gubneqbpaz.eastus2-01.azurewebsites.net` |
| Its role | The product being built; API callers (sfx-platform) will migrate to the declared API (this repo) from the legacy staging host | An operator tool only: today it is how declarations are written into the estate database and how runs are read |

They share one thing: **the staging estate database** (and sfx-identity). The declared API's
interface, ingress, frontdoor and providers are rows in that database. The legacy CLI is how those
rows are written today: its requests run on the legacy staging host, whose kernel calls the estate's
writers. The declared API's kernel reads the same rows on every request, so a declaration is live in
`sfx-api-test` at once, with no rebuild. The image is rebuilt only when [host/](host/),
[sfx-api.config.json](sfx-api.config.json), [deploy/](deploy/) or the kernel change.

The words used below:

- **the declared API**: this repository and what it serves (`sfx-api-test` on Azure, the facade on WSL);
- **the legacy CLI**: the installed `sfx-api` command;
- **the legacy staging host**: the existing staging API that the legacy CLI calls;
- **the estate database**: the staging estate database both of them read.

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
| [sfx-api.config.json](sfx-api.config.json) | Host data: the selected kernel, the kernel command the facade runs, the HTTP address |
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
chain: the DEPENDENCY `sidefx:dependencies/sfx-api-ingress` (definition `39ffb87e`), the mechanics
`sfx-api-ingress-resolve-port.v1` and `sfx-api-ingress-compose-port.v1`, the PROVIDERs
`sfx-api-ingress-resolve` (`d06badff`) and `sfx-api-ingress-compose` (`f07ed911`), and their entries
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
delivery) and `stream-run-events` (the HTTP-serving provider streams) answer 501.

`admit-run` (`POST /sfx/v1/runs`, the body `{object, operation, subject, namespace, input}`) is
`admit-api-run`, a fan-out:

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

The command, the pool size (`instances`, 2), the answer bound and the envelope's request are host
data in [sfx-api.config.json](sfx-api.config.json). Each kernel holds about 260 to 350 MB. A request
waits for a free kernel, and a client that gives up still holds its kernel until the kernel answers.
A kernel that fails writes no delivery: the platform closes the connection without a response (the
front end answers 502), and the kernel's error reaches the host's stderr. `--timeout` bounds each
delivery at 225 s, not the kernel's life (App Service stops a request at 230 s). The 8 MiB
standard-input bound of a per-request kernel is not established for a resident envelope.

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

The image holds no credential material. `start.sh` writes the sealed vault, its key record and its key
from three App Service settings that reference Key Vault secrets (`sfx-api-credential-vault`,
`sfx-api-credential-vault-key-record`, `sfx-api-credential-vault-key` in `aiengine-kv-20260406`), puts
the key into a container-only gnome-keyring under the reference the declared vault providers read, and
starts the host on port 8787 (`WEBSITES_PORT`). The test app is `sfx-api-test` on the plan
`ASP-sidefxgroup-ad2e`; its system identity pulls from the registry (`AcrPull`) and reads the vault
(`Key Vault Secrets User`).

## Declaring

Declarations go into the estate database, not into `sfx-api-test`. Today they are written through
the legacy CLI, whose requests run on the legacy staging host. A command below that begins `sfx-api`
is the legacy CLI. The declared API has no command-line client of its own, and none of these commands
calls `sfx-api-test`.

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
  `~/.local/share/sfx/kernel/<digest>/` with its entry executable. The digest is in
  [sfx-api.config.json](sfx-api.config.json).
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
   sfx-platform still calls the legacy staging host; moving it to the declared API is still open.
2. **The run's trace and event stream:** the kernel's observation channel forwarded to a declared sink
   that appends trace chunks; then admission through the workflow workers (asynchronous), the
   idempotency key (`$header.` in the input template) and machine runs (EV-014).
3. **The capability graph:** compile is a kernel operation, not a capability.
4. **Session operations:** sign-in (`open-api-session`, `POST /sfx/v1/session`: its providers and
   sfx-identity migration 011 are declared; the capability and its ingress route are not), session
   runs. Session read and sign-out are served.
5. **Performance:** resident kernels removed the kernel start (a warm request is about 3.9 s on WSL;
   `sfx-api-test` still runs the per-request facade until it is redeployed). What remains: the kernel
   reads every capability's definition from the estate on each invocation (five per request, about
   1.8 s); the frontdoor's two SQL reads each open the vault and a connection (about 0.7 s); about
   1.0 s before a request's first delivery phase is unexplained; the declared read cache is not
   served; and a client that gives up still holds a kernel until it answers.
