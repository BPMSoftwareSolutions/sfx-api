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

15 of 15 cases on the installed C# kernel (`41a58fdf`), each a real run of the declared
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

- Each operation in `sidefx-api-interface.v1` declares `segments`: its full path by position,
  a parameter as `{"param": "<name>"}`. For `GET /sfx/v1/runs/{runId}`:
  `{"0": "", "1": "sfx", "2": "v1", "3": "runs", "4": {"param": "runId"}}`. The verification
  supplied them in its input.
- `run`, `admission` and `command` operations resolve here; their dispatch (the run window and
  event streams) is not declared yet.

## Files

| File | What it is |
| --- | --- |
| `frontdoor.sej.v1.json` | the SEJ: `resolve-request` and `compose-response` |
| `declare-frontdoor.sql` | declares both transformations and both capabilities (installed writers, one transaction) |
| `declare-sej-overlay.sql` | binds the sej-pure.v2 operators the graph runner lacked |
| `sfx-api.config.json` | selects the installed kernel by digest |
