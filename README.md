# sfx-api

The declared API, deployed by itself. There is no frontdoor code: every mechanic up to the
profile schema boundary is SEJ (`sej-pure.v2`), and the kernel resolves it.

## The frontdoor graph

| Stage | Mechanic | Declared as |
| --- | --- | --- |
| receive | listen, read the request | HTTP-serving provider port, past the boundary: native calls only |
| identify | verify the bearer or session carrier | identity provider port: the caller `{kind, principalId}` or null |
| interface | read `sidefx:authorities/sidefx-api-interface.v1` | declared read |
| resolve | match the operation, admit the caller, bind the input | SEJ `resolve-request` in [frontdoor.sej.v1.json](frontdoor.sej.v1.json) |
| dispatch | run the operation's capability | `generic-capability-invocation.v1` |
| respond | compose `api-response.v1` (status, headers, body) | SEJ `compose-response`, then the HTTP-serving port writes it |

`resolve-request` takes `{request, interface, caller}`. The request is the HTTP-serving
provider's native output: `method`, `segments` (the path split on `/`), `query`, `headers` and
`body` text. It answers either `api-response.v1` for a refusal (404 `OPERATION_NOT_DECLARED`,
401 `CALLER_REQUIRED`, 403 `CALLER_NOT_ADMITTED`) or `api-resolution.v1` with the operation's
kind, its capability and its bound input (`dispatchRequest`), following the interface's
`inputTemplate` (`$path.`, `$query.`, `$caller.`, `$body`; an absent value omits its member).

## What the rows need

- Each operation in `sidefx-api-interface.v1` declares `segments`: its full path by position,
  with a parameter as `{"param": "<name>"}`. For `GET /sfx/v1/runs/{runId}`:
  `{"0": "", "1": "sfx", "2": "v1", "3": "runs", "4": {"param": "runId"}}`.
- Operations whose kind is `run`, `admission` or `command` resolve here, but their dispatch
  (the run window and event streams) is not declared yet.

## Kernel

`sfx-api.config.json` selects the installed kernel by digest. The kernel runs the frontdoor
capability; nothing else runs in this deployment.
