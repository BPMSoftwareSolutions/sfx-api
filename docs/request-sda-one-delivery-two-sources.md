# Request to SDA: one delivery, capabilities from two sources

Date: 2026-11-03. From: sfx-api. To: SDA.

Evidence: SDA source at `bcbdbec`, read in all three languages. Nothing was run.

## What sfx-api is building

The host binds a provider to `sda-kernel-declared-read-port.v1` (ADR-0020). It does what section 6, step 1 of
[request-host-selected-declared-read-provider.md](https://github.com/BPMSoftwareSolutions/scenario-driven-architecture/blob/bcbdbec/docs/request-host-selected-declared-read-provider.md)
describes:
- it answers the host's own capabilities from its pinned bundle, with the pin as their identity (D6);
- it passes every other read to `builtInRead` (D9).

Every delivery of this host reads capabilities from both sources:
- each host capability runs under `run-declared-graph`, which is the estate's;
- the frontdoor, `serve-api-request`, is the bundle's, and it dispatches to the consumer's capabilities, which are the estate's;
- an observed run also reads `read-observation-projection`, which is the estate's.

## What the kernels do

Section 6, step 1 says coherence is per capability: "It answers all reads for one capability from one place, so they
share one set of identity fields". Each kernel instead holds one identity across every capability a delivery reads.
A capability with any other identity is refused with `DATABASE_AUTHORITY_NOT_COHERENT`.

| Language | Where the identity is fixed for the delivery | Where another identity is refused |
| --- | --- | --- |
| C# | `InvocationBoot.cs:97-100` reads the delivered capability and its mechanics. `:298` and `:321` carry those mechanics into `run-declared-graph`. `DeclaredOperationCarrier.cs:129-131` and `RequestNamedCapabilityInvocationProvider.cs:148` carry them into every later capability. | `AuthorityRead.cs:109-117`: the carried mechanics are checked against each capability's authority. |
| Python | `invocation_boot.py:639` and `:648`; `declared_operation_carrier.py:107-109` | `authority_read.py:138-143` |
| TypeScript | `invocation-boot.mjs:246`: the identity is the `execution-delivery` read's own | `invocation-boot.mjs:238-240`, and `authority-read.mjs:61-67` for carried mechanics |

So, with the host's provider bound:
- **C# and Python.** A delivery of a bundle capability, which carries the pin, is refused when it reads
  `run-declared-graph`, which carries the session's identity.
- **TypeScript.** A delivery of a bundle capability is refused against the identity of the `execution-delivery` read,
  which `builtInRead` answers.

## Why conformance passes

`DeclaredReadPortConformanceTests.cs` never runs a delivery whose capabilities come from two sources:
- the delivery tests answer every capability, `run-declared-graph` included, from one source under one pin;
- `A_provider_routes_each_read_to_its_bundle_or_through_the_delivery_session` mixes only `execution-delivery`, and
  then reads one capability on its own, outside a delivery.

## Requested

A delivery may read capabilities from different sources:
- coherence holds among one capability's own reads: its authority, closure, resolver map and mechanics;
- a capability is never checked against the mechanics, or the identity, of a capability from another source;
- each capability reports its own source's identity.

Conformance, in each language: one delivery of a capability answered from a pinned source, which runs under
`run-declared-graph` answered through `builtInRead` and dispatches a request-named capability also answered through
`builtInRead`. Its outcome equals the same delivery served entirely by the built-in reads, and each capability reports
its own source's identity.
