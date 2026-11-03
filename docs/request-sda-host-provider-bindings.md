# Request to SDA: the host's own provider bindings, in the delivery's run capability

Date: 2026-11-03. From: sfx-api. To: SDA.

Evidence:
- SDA source at `1bd400e`, read.
- The estate's `run-declared-graph`, read on 2026-11-03 through `sql-database-reader`, run
  `c9be6b42-cb95-a56b-420f-03535ada4133`.

Status: answered by SDA `05ff751`, on main since 2026-11-03, and verified on the estate (below).
- **D13, amended.** The configured capability runs through `run-declared-graph`, never through the capability the
  `execution-delivery` read names.
- **D14, amended.** SDA's own registry declares the built-in read step's overlay rule.
- **D15.** The host's provider authority declares `overlayBindings` and `declaredProviders`, which the runner uses
  alongside its own. A mechanic or profile both declare is refused.

The conformance runs one shared fixture shaped like the estate. sfx-api now declares the bundle reader, and its five
providers under `.v2` identities, in `providers/host-provider-authority.json`. A same-name redeclaration would be refused,
and retiring the estate's `.v1` copies first would break the host now serving.

### Run on the estate with `05ff751`: answered

A kernel built from a clean clone of SDA `05ff751` (linux-x64, artifact
`eb80040182f6dbb5e3922022598ea097b5789020d7382d9027ee8aab357d5c9d`) ran on WSL against the estate. It used sfx-api's
provider authority, its bundle, and the new facade with all six kernels.
- The facade listened after 10 to 14 s, in three starts.
- Every request was answered as the host now serving answers it:
  - `GET /sfx/v1/nope`: 404 `OPERATION_NOT_DECLARED`;
  - `GET /sfx/v1/session` and `GET /sfx/v1/runs/abc` without a session: 401 `CALLER_REQUIRED`;
  - `POST /sfx/v1/session` with an empty identifier: 400 `LOGIN_INPUT_INVALID`.
- `outcome.evidence.authorities` named the host's pin for each bundle capability and the session's snapshot for
  `run-declared-graph`.

A warm envelope still makes four more database queries with the port bound than without it:
[request-sda-warm-envelope-round-trips.md](request-sda-warm-envelope-round-trips.md).

### Run on the estate with that working tree: one D15 gap left

These runs used a kernel built locally from a copy of SDA's working tree (artifact
`691b0b74c5fb540a7eb01277c631958ca161edabd0c0e224a536384f39f31666`), on WSL against the estate, with sfx-api's
provider authority and bundle.
- **`read-api-host-configuration` answered `terminated`, `completed`.** The estate has never held that capability.
  `outcome.evidence.authorities` named the host's pin for it and the session's snapshot for `run-declared-graph`.
  That proves D13, D14 and the bundle reader's D15 binding.
- **The new facade started all six kernels, each admitted the bundle, and it listened after 10 s.**
- **Every HTTP request through `serve-http-request` failed.** It is answered from the bundle and binds the host's
  `sfx-api-ingress-resolve-port.v2`. The kernel logged
  `SEMANTIC_EXECUTION_GRAPH_OVERLAY_BINDING_MISSING: 'sfx-api-ingress-resolve-port.v2'`, and the facade answered the
  declared 502.

The execute port merges the registry's rules (`ResolvePlan`, `declaredOverlayBindings`). `InvocationBoot.GraphIdentity`
realizes the delivery's overlay from the runner's `overlayBindings` alone, so a delivered capability that binds a host
mechanic fails there. The D15 conformance only binds a host mechanic inside the capability at the port, never in the
delivered capability, so it passes.

**Requested:**
- Every place a delivery realizes an overlay, `GraphIdentity` and its Python and Node equivalents included, uses the
  registry's overlay rules alongside the runner's.
- Conformance: a delivered capability that binds a host-declared mechanic.
- Conformance: a `declaredProviders` entry that is a declared program (`type`, `method: ".ctor"`, `assembly`,
  `factory`, `operations` with `program`), the form every host provider takes.

## What sfx-api has declared

- `answer-host-declared-read` is the declared capability the host binds at the port through D12 and D13.
- It reads bundle documents with the host's declared provider `sfx-api-host-bundle-read`: mechanic
  `sfx-api-host-bundle-read-port.v1`, DEPENDENCY `sidefx:dependencies/sfx-api-host-bundle`, program in
  sfx-api `providers/sfx-api-host-bundle.dependency.json`.
- It passes the reads it does not own to the D14 step `sda-kernel-built-in-read.v1`.
- The host's other capabilities come from its bundle. They bind the host's five providers: ingress resolve and
  compose, trace encode, sign-in open and derive.

## Run on the estate: the configured form runs through the delivery wrapper, not a graph runner

Two local runs on 2026-11-03, against the estate. Both used the kernel built from SDA `1bd400e` (linux-x64, artifact
`b6872d49172f7909dc57b396203e676e0b9ba64a115bad77e0249315e31d6417`) on WSL, with the host's vault.
- **No provider bound.** `verify-password-derivation` answered `terminated`, `MATCHES`.
- **The host's provider authority bound** (sfx-api `providers/host-provider-authority.json`).
  `read-api-host-configuration` failed on the delivery's first declared read:
  `PLATFORM_MECHANIC_NOT_DECLARED:execute-declared-capability:read-execution-capability-authority`.

D13 runs the configured capability through the capability the `execution-delivery` read names. In the estate, that
read (run `9b147871`) names `execute-declared-capability`, the delivery wrapper, with its request and result
expressions. The wrapper is not a graph runner like `run-declared-graph`, so the graph source cannot run through it.
The conformance harness's `execution-delivery` names `run-declared-graph` (`DeclaredCompileHarness.cs`), so the tests
pass where the estate fails.

**Requested, first:** run the configured capability through the declared graph runner the delivery itself uses. In C#
that is `run-declared-graph`, the one `InvocationBoot` runs a capability's graph through. Conformance runs against a
harness whose `execution-delivery` names the estate's wrapper.

## What the delivery's run capability does with them

D13 runs the configured capability "through the delivery's run capability (the execution-delivery read names it)",
which is the estate's `run-declared-graph`. Its execute port, `sda-semantic-execution-graph-execution-port.v1`, has:
- `overlayBindings`: 110 rules, mechanic to provider profile;
- `providers`: 61 provider entries with their programs.

The five host providers are among both lists as the estate declares them. The estate's `sfx-api-ingress-resolve`
program has no `last-event-id`.

At `1bd400e`, a compiled graph without a `realizationOverlay` is realized from the runner's `overlayBindings`. A slot
whose mechanic has no rule fails with `SEMANTIC_EXECUTION_GRAPH_OVERLAY_BINDING_MISSING:<mechanicId>`
(`SemanticExecutionGraphExecutionProvider.cs`, `ResolvePlan`; `SemanticExecutionGraphOverlayProvider.cs`). Programs
are resolved from the runner's `providers` and the registry (`DeclaredProviderResolver.ResolveDeclaredProviders`). So:

1. `answer-host-declared-read` fails on both new mechanics, `sfx-api-host-bundle-read-port.v1` and
   `sda-kernel-built-in-read.v1`, because the estate's runner has no rule for either.
2. A host capability answered from the bundle still runs the estate's copies of the host's provider programs, so a
   provider change of the host's own, such as `last-event-id`, never reaches the host.
3. Giving the estate's runner those rules and programs would declare the host's providers into the estate, which the
   owner ruled out: "The host's declarations shouldn't go into the estate at all."

SDA's D13 conformance passed because its pass-through capability carries a compiled plan with its own
`realizationOverlay`, run by a test runner whose execute port has no configuration.

## Requested

1. **The host's provider bindings come from the host.** The host's provider authority declares overlay rules
   (mechanic to provider profile) and declared provider entries (programs per language), in the form the execute port
   takes in `overlayBindings` and `providers`. The delivery's run capability uses them for the mechanics they name,
   and the estate's runner keeps every other rule. A mechanic both name is a conflict, refused, never a silent override.
2. **The built-in read step is realized without the estate.** `sda-kernel-built-in-read.v1` is SDA's own step, so the
   kernel supplies its overlay rule, as it synthesizes contract admission's.
3. **Conformance, in all three kernels:**
   - a configured capability bound at the port, run through a runner that declares neither mechanic, reads a document
     through a host-declared provider and passes a read through the built-in read step;
   - a host provider entry replaces nothing in the estate's runner for any other mechanic.
