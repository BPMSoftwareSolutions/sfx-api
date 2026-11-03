# Request to SDA: a warm envelope pays no extra round trips for a provider at the declared-read port

Date: 2026-11-03. From: sfx-api. To: SDA.

Evidence:
- SDA source at `05ff751`, read.
- The kernel built from it: linux-x64, artifact `eb80040182f6dbb5e3922022598ea097b5789020d7382d9027ee8aab357d5c9d`.
- Runs on WSL against the estate, on 2026-11-03.

Status: open. Not blocking: see the impact below.

## What was measured

Setup:
- One resident kernel, given envelopes one at a time, as the sfx-api facade gives them.
- The same two requests through `serve-http-request`: `GET /sfx/v1/nope` (404) and `GET /sfx/v1/session` without a
  credential (401).
- 16 to 20 warm envelopes per configuration, after the first.
- Two kernel host configurations. One is unbound: the estate's `serve-http-request`. The other binds sfx-api's provider
  authority: the bundle's `serve-http-request`, answered at the port by `answer-host-declared-read`.

| Per warm envelope | Port unbound | Port bound |
| --- | --- | --- |
| `readSession.queries` | 2 | 6 |
| `evidence.declarations` | 15 resolved, 15 reused, 0 read | 12 resolved, 12 reused, 0 read |
| Kernel CPU (`/proc` utime + stime) | 652 to 842 ms | 670 to 731 ms |
| Wall time | 1169 to 1303 ms | 1508 to 1611 ms |

In one pair of envelopes:
- Both ran the same 120 cells and answered the same 374 KiB.
- `executeDeclaredGraph` took 801 ms unbound and 832 ms bound.
- The bound envelope's `processTotal` was 1619 ms, against 990 ms unbound.

The difference lies outside the graph, before the delivery's first phase. It is not CPU. It is four more round trips to
the estate's database per envelope, 77 to 85 ms each from WSL.

## What explains it in the source

This was found by reading the source, not by instrumenting it.

- **The command vocabulary is read on every envelope.** The resident loop builds its request without `CommandOperations`
  (`KernelEntry.cs:740`). So `CommandCarrier.ExecuteDatabaseCommandAsync` reads `sda-kernel-command-operations.v1` on
  every envelope, through `dataAccess.ReadAsync("provider-authority", …)` (`CommandCarrier.cs:264`), outside the
  declaration cache. With a provider bound, that read goes through the port.
- **A read through the port runs the configured capability on an uncached data access.**
  - The read uses `DataAccess.WithoutPort` (`DataAccess.cs:150`, `DeclaredReadPort.cs:66`).
  - Its `Declarations` is `DeclarationEnvelope.Uncached()` (`DataAccess.cs:103`).
  - So on every port read, `InvokeConfiguredCapability` reads the execution delivery from the database
    (`RequestNamedCapabilityInvocationProvider.cs:53`). The runner's declarations are read the same way.

## Requested

1. A warm envelope makes no read that the declaration cache could serve, whether or not a provider is bound at the port.
   That covers the configured capability's execution delivery and its runner's declarations, under the envelope's
   generation and pin.
   - Our addition: a port answer and a built-in answer for the same key must never be confused. The bundle's
     `serve-http-request` and the estate's `.v1` copy differ.
2. The resident loop reads the command vocabulary once per generation, not once per envelope.
3. Conformance, in all three kernels: a warm envelope makes the same number of database queries with a configured
   capability at the port as with the port unbound.

## Impact

- **On WSL:** the four round trips add about 0.34 s to every warm request. The facade's warm p50 was 1.60 s and its p95
  1.77 s, over 20 requests with all six kernels running.
- **On `sfx-api-test`:** the database is in the same region, so the same round trips should cost tens of milliseconds.
  `frontdoor-warm-latency` (p50 at most 0.88 s) is measured there after the deploy.
- **`warm-definitions` (declaration reads made by a warm envelope: none):** this SLO is not met while these reads remain,
  even though `evidence.declarations` reports 0 reads. The count covers only the delivery's own resolutions.
