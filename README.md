# sfx-api

The declared API, deployed by itself. There is no frontdoor code: every mechanic up to the
profile schema boundary is SEJ (`sej-pure.v2`), and the kernel resolves it.

## The frontdoor graph

| Stage | Mechanic | Declared as | State |
| --- | --- | --- | --- |
| receive | listen, read the request | HTTP-serving provider port, past the boundary: native calls only | to build |
| identify | verify the bearer or session carrier | identity provider port: the caller `{kind, principalId}` or null | to build |
| interface | read `sidefx:authorities/sidefx-api-interface.v1` | declared read | exists |
| resolve | match the operation, admit the caller, bind the input | SEJ `resolve-request`, capability `resolve-api-request` | **verified** |
| dispatch | run the operation's capability | `generic-capability-invocation.v1` | to compose |
| respond | compose `api-response.v1` (status, headers, body) | SEJ `compose-response`, capability `compose-api-response` | **verified** |

`resolve-request` takes `{request, interface, caller}`. The request is the HTTP-serving
provider's native output: `method`, `segments` (the path split on `/`), `query`, `headers` and
`body` text. It answers `api-response.v1` for a refusal (404 `OPERATION_NOT_DECLARED`, 401
`CALLER_REQUIRED`, 403 `CALLER_NOT_ADMITTED`) or `api-resolution.v1` with the operation's kind,
its capability and its bound input (`dispatchRequest`), following the interface's
`inputTemplate` (`$path.`, `$query.`, `$caller.`, `$body`; an absent value omits its member).

`compose-response` takes `{result}`: a declared outcome answers 200 with the outcome as the body;
a refusal `{code, message}` answers 404 for `*_NOT_FOUND`, 409 for `*_SNAPSHOT_CHANGED` and
`*_NAMESPACE_REQUIRED`, and 422 otherwise.

## Verified on the kernel

15 of 15 cases on the installed C# kernel (`41a58fdf`; dispatch and SEJ rechecked on `b551c9ec`, SDA `a978472`), each a real run of the declared
capability: a provider inspection, a scenario read with query and nested payload binding, a
details read as a user, a page read, a user-only retained run as a user (resolved) and as a
machine (403), run events with an omitted query member, an admission with `$body`, no caller
(401), an unknown path and a wrong method (404), and the four response mappings.

What the kernel's SEJ taught the declaration (each found by a run):

- A capability transformation is one expression: `call` to another transformation does not
  resolve on the transformation port, so `resolve-request` composes its parts with `let`.
- `lookup` does not index arrays and `object-entries` takes objects only, so the request path
  is read by position (`segments.0` to `segments.9`, by static path) into an object first.
- `matches` matches the whole string, so a suffix test is `^.*_NOT_FOUND$`.
- An expression that fails returns the cell input unchanged, so a check compares the declared
  answer, never only that the run completed.
- Every operator needs an overlay binding on the graph runner
  (`run-declared-graph-execute`); `declare-sej-overlay.sql` binds the 14 sej-pure.v2 operators it
  lacked.

## What the rows still need

- Each operation in `sidefx-api-interface.v1` declares `segments` (declared 2026-10-30): its full
  path by position, a parameter as `{"param": "<name>"}`.
- `run`, `admission` and `command` operations resolve here; their dispatch (the run window and
  event streams) is not declared yet.

## The served frontdoor (verified end to end)

`serve-api-request` is the frontdoor as one declared capability, five stages in a sequence:

1. **prepare** (SEJ `serve-prepare-interface-read`): the read request for `sql-database-reader`.
2. **interface** (`generic-capability-invocation.v1`): `sql-database-reader` returns the interface
   authority together with the request and caller (a dispatch answers only its own envelope, so the
   read carries them).
3. **resolve** (SEJ `serve-resolve-request`): the verified resolution; a refusal, or an operation
   kind with no declared dispatch (501 `OPERATION_DISPATCH_NOT_DECLARED`), is dispatched to
   `answer-api-response`, which returns it.
4. **dispatch** (`generic-capability-invocation.v1`): the operation's capability.
5. **respond** (SEJ `serve-compose-response`): `api-response.v1`.

Verified 2026-10-30 on the WSL kernel `9f78e78d`, each a real run against the estate:

| Request | Answer |
| --- | --- |
| `GET /sfx/v1/providers/sfx-vault-file-host/inspection` (machine) | 200, `provider-inspection.v1` READ, 11 result sets (18.5 s) |
| `GET /sfx/v1/nope` | 404 `OPERATION_NOT_DECLARED` (4.6 s) |
| `GET /sfx/v1/providers/x/inspection` (no caller) | 401 `CALLER_REQUIRED` (4.5 s) |
| `GET /sfx/v1/retained-runs/r1` (machine) | 403 `CALLER_NOT_ADMITTED` (5.0 s) |
| `GET /sfx/v1/runs/abc` (machine) | 501 `OPERATION_DISPATCH_NOT_DECLARED` (4.7 s) |

Each run starts a kernel process; the times include its start.

Still to declare: the HTTP-serving provider (receive and send), the identity provider (the caller
from the bearer or session carrier), the dispatch of `run`, `admission` and `command` operations,
and the deployment.

## Local testing

The local runtime is WSL Ubuntu, the staging host's twin: user `sjones`, `HOME=/home/sjones`,
`secret-tool` and the vault at `~/.local/share/sfx/vault/vault.json`. Our declared vault
providers run there unchanged, so every capability runs locally as it does on staging.

- **Kernel:** built and installed from `C:\lab\repos\scenario-driven-architecture`
  (`ScenarioKernel install --rid linux-x64 --estate C:\lab\repos\sfx-embody`), then placed at
  `~/.local/share/sfx/kernel/<digest>/` with its entry executable. The digest is in
  `sfx-api.config.json`.
- **Vault:** the vault file holds the estate's credentials, `SFX_ESTATE_DATABASE` among them, and
  the key record under `~/.local/share/sfx/credential-vault-keys/0f2fb3b5....json` names its
  `vaultId`.
- **Key:** the vault key is the Secret Service item `service sfx-credential-vault key
  0f2fb3b502843c274efcadf4856f631a` in the login keyring. The keyring locks when WSL restarts;
  unlock it before a run.
- **Run:** pipe an `sfx-command-delivery.v1` envelope into
  `./KernelEntry --stdin-envelope --config kernel-host.json` in the install root.

Verified 2026-10-30: `read-provider-inspection` answers `READ` with 11 result sets through the
declared vault providers and dispatch, as on staging.

The Windows kernel is not a local runtime for these providers: it denies child processes (job
object, every isolation profile), runs at low integrity (no vault writes), and the providers'
key release is a `secret-tool` process.

## Files

| File | What it is |
| --- | --- |
| `frontdoor.sej.v1.json` | the SEJ: `resolve-request` and `compose-response` |
| `declare-frontdoor.sql` | declares both transformations and both capabilities (installed writers, one transaction) |
| `declare-sej-overlay.sql` | binds the sej-pure.v2 operators the graph runner lacked |
| `sfx-api.config.json` | selects the installed kernel by digest |
