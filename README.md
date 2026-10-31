# sfx-api

The declared API, deployed by itself. There is no frontdoor code: every mechanic up to the
profile schema boundary is SEJ (`sej-pure.v2`), declared into the estate, and the kernel
resolves it.

## Structure

| Path | What it is |
| --- | --- |
| [sej/serve-api-request.sej.json](sej/serve-api-request.sej.json) | The frontdoor's SEJ: prepare the interface read, resolve the request, compose the response |
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
| [sfx-api.config.json](sfx-api.config.json) | The selected kernel (the local runtime) |

Each SEJ file is the authority of one capability namespace (`sidefx:capability:<file name>`).

## The frontdoor

`serve-api-request` is the frontdoor as one declared capability, five stages in sequence:

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

The request is the HTTP-serving provider's native output: `method`, `segments` (the path split on
`/`), `query`, `headers` and `body` text.

## Declaring

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

## Verified

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

The local runtime is WSL Ubuntu, the staging host's twin: user `sjones`, `HOME=/home/sjones`,
`secret-tool` and the vault at `~/.local/share/sfx/vault/vault.json`. The estate's declared vault
providers run there unchanged, so every capability runs locally as it does on staging.

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
- **Run:** pipe an `sfx-command-delivery.v1` envelope into
  `./KernelEntry --stdin-envelope --config kernel-host.json` in the install root, for example
  `{"deliveryType":"sfx-command-delivery.v1","operation":"invoke","request":{"object":"capability","verb":"invoke","subject":"serve-api-request","input":"<request JSON>","inputType":"json"}}`.

The Windows kernel is not a local runtime for these providers: it denies child processes (a job
object, in every isolation profile) and runs at low integrity, and the providers' key release is a
`secret-tool` process.

## Next

1. **HTTP-serving provider:** receive the request and send the response, native calls only, feeding a
   kernel that stays running instead of one process per request.
2. **Identity provider:** the caller from the bearer or session carrier.
3. **Deployment:** the kernel and the HTTP-serving provider on their own App Service.
4. **The run's trace and event stream:** the kernel's observation channel forwarded to a declared sink
   that appends trace chunks; then admission through the workflow workers (asynchronous), the
   idempotency key (`$header.` in the input template) and machine runs (EV-014).
5. **Dispatch of `command` operations** (the circuit catalog and the capability graph).
