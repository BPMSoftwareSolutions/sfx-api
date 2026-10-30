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
| [declarations/01-sej-pure-overlay-bindings.sql](declarations/01-sej-pure-overlay-bindings.sql) | Binds the 14 `sej-pure.v2` operators the graph runner (`run-declared-graph-execute`) lacked |
| [declarations/02-resolve-and-compose.sql](declarations/02-resolve-and-compose.sql) | Declares `resolve-api-request` and `compose-api-response` |
| [declarations/03-serve-api-request.sql](declarations/03-serve-api-request.sql) | Declares `segments` on the interface operations, the frontdoor's SEJ, `answer-api-response` and `serve-api-request` |
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
   outcome as the body; a refusal `{code, message}` is 404 for `*_NOT_FOUND`, 409 for
   `*_SNAPSHOT_CHANGED` and `*_NAMESPACE_REQUIRED`, and 422 otherwise.

The request is the HTTP-serving provider's native output: `method`, `segments` (the path split on
`/`), `query`, `headers` and `body` text.

## Declaring

Run the files in [declarations/](declarations/) in order against the estate database. Each runs in one
transaction through installed writers (`model.declare_port_provider_binding`,
`model.declare_transformation`, `model.declare_semantic_object`,
`model.apply_capability_from_dsl`); nothing commits unless every statement succeeds. A declaration
embeds the SEJ files as they were when it was written; a changed SEJ file needs its declaration
rewritten. All three were applied to the estate on 2026-10-30.

## Verified

`serve-api-request` end to end on the WSL kernel `9f78e78d`, each a real run against the estate:

| Request | Answer |
| --- | --- |
| `GET /sfx/v1/providers/sfx-vault-file-host/inspection` (machine) | 200, `provider-inspection.v1` READ, 11 result sets (18.5 s) |
| `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` (4.6 s) |
| `GET /sfx/v1/providers/x/inspection` (no caller) | 401 `CALLER_REQUIRED` (4.5 s) |
| `GET /sfx/v1/retained-runs/r1` (machine) | 403 `CALLER_NOT_ADMITTED` (5.0 s) |
| `GET /sfx/v1/runs/abc` (machine) | 501 `OPERATION_DISPATCH_NOT_DECLARED` (4.7 s) |

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
- **Vault:** the vault file holds the estate's credentials, `SFX_ESTATE_DATABASE` among them; the key
  record `~/.local/share/sfx/credential-vault-keys/0f2fb3b5….json` names its `vaultId`.
- **Key:** the Secret Service item `service sfx-credential-vault key 0f2fb3b502843c274efcadf4856f631a`
  in the login keyring. The keyring locks when WSL restarts and a run waits until it is unlocked.
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
3. **Keyring unlock at start** in WSL, as staging unlocks its own.
4. **Deployment:** the kernel and the HTTP-serving provider on their own App Service.
5. **Dispatch of `run`, `admission` and `command` operations.**
