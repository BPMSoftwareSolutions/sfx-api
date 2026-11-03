# Request to SDA: bind a declared capability to the declared-read port

Date: 2026-11-03. From: sfx-api. To: SDA.

Evidence: SDA source at `60aefbb`, read. Nothing was run.

Status: answered by SDA `1bd400e` (2026-11-03), rules D12 to D14, in all three kernels:
- **D12.** The port's binding declares a configuration, and the kernel passes it to the provider unchanged.
- **D13.** The generic capability-invocation provider's configured form runs the graph source carried in that
  configuration, through the delivery's run capability and on the delivery's data access without the port.
- **D14.** `sda-kernel-built-in-read.v1` is the built-in read step.

Item 2's digest-checked load was not adopted: the kernel reads no document and checks no digest, so pinning and the
check before the host listens stay the host's.

## What sfx-api is building

The owner's direction: "providers are declared capabilities as well", and the host declares "up to the profile schema
boundary". The host's declared-read provider is therefore a declared capability, `answer-host-declared-read`, in SEJ
in the host's pinned bundle. It is not provider code. It answers the reads of the host's own capabilities from the
bundle and passes every other read to `builtInRead` (D9). Its behaviour: sfx-api `features/answer-host-declared-read.feature`.

## What the port takes today

`rule.binding` in `kernel/semantic-authority/execution/declared-read-port.semantic-authority.json` binds the port with
an `eventPorts` entry naming `providerModule` and `providerExport`, a module or type. In each kernel, the port then calls
that export with configuration `{}`:
- `DeclaredReadPort.cs`, `ReadAsync`;
- `declared_read_port.py`, `read_through_declared_read_port`;
- `declared-read-port.mjs`.

No entry names a declared capability. The generic capability invocation provider cannot stand in either: with
configuration `{}` it has no capability to invoke.

## Requested

1. **A binding that names a declared capability.** The host's provider authority binds the port to a capability by its
   graph source, as a document and its SHA-256 digest (the host's pin), in place of a module and an export.
2. **The capability is loaded from that binding, never through the port.** Every one of its reads would otherwise reach
   the provider it is, so the kernel reads its declaration from the bound document, checked against the digest.
3. **`builtInRead` as a step.** The capability passes a read to the delivery's own session through a port its graph
   source can bind. D9 gives that pass-through to a provider's context, and a declared capability has none.
4. **The same in all three kernels**, as D8 requires, with conformance: a delivery served by a bound declared capability
   equals the same delivery served by the built-in reads; a document that does not match its digest stops the kernel
   before it serves; the capability's own reads never reach the port.
