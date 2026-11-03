# Request to SDA: what a frontdoor-only host needs from the resident kernel

Date: 2026-11-03. From: sfx-api. To: SDA.

## The owner's direction

`host/serve.py` holds only a frontdoor facade, with no mechanics. Everything else is declared up to the profile schema
boundary.

## Why the host still holds a runtime

About 500 of the 716 code lines in `serve.py` are a runtime: a run executor, a stream server, an in-memory event log, a
session recheck timer and a drawing poller. Each holds state or time that outlives one envelope. They are in the host
because the resident kernel cannot do four things. The first three are from SDA's source; the fourth is unverified:

1. **It serves one envelope at a time.** The resident loop reads an envelope, answers it and then reads the next, over
   one session (`ResidentDelivery.cs:52`). A stream or a run holds its kernel for as long as it lasts, so the host runs a
   kernel for each kind of concurrent work and supervises them.
2. **It answers each envelope with one line** (`ResidentDelivery.cs:140`). A run stream or the estate stream answers
   over minutes, so the host writes their frames itself.
3. **It keeps no work after an envelope answers.** A run admitted by a request executes after the request's 202. SDA's
   concurrency design puts detached work outside its first profile
   (`docs/declaration-controlled-concurrency-design-2026-09-21.md:58`), so the host queues runs and executes them on
   worker kernels.
4. **It may not keep a declared provider's state between envelopes.** The live observation channel's log and the run
   queue must outlive every envelope and be shared by concurrent ones.

## Requested

1. **Concurrent envelopes.**
   - A resident kernel accepts envelopes that carry an envelope id.
   - It executes them concurrently, each in its own pinned session.
   - They share the process's runtime, declaration cache and plan cache.
   - It answers each one tagged with its id. The bound on envelopes at once is declared.
2. **Answers in parts.**
   - A delivery may answer declared parts before its final answer, such as a response head and then body chunks.
   - Each part is tagged with the envelope id and written as soon as the delivery produces it.
   - The final answer ends the delivery.
3. **Detached deliveries.**
   - A delivery may start a declared capability that keeps executing after the delivery has answered, owned by the
     kernel process.
   - Its observations and outcome go to the declared capabilities its declaration names (the run's events, trace and
     completion), not to the host.
   - Its bound is declared.
4. **Process-scoped provider state.**
   - A declared provider's instance can live as long as the kernel process and be shared by its concurrent envelopes.
     The channel's log and the run queue are such providers.
   - If the kernel already keeps provider instances this way, please say so and point to the rule.
5. **Conformance, in all three kernels:**
   - two envelopes in flight answer independently;
   - a streamed delivery's parts arrive before its final answer, in order;
   - a detached delivery completes after its starting envelope answered, and its outcome reaches the declared
     capability;
   - a process-scoped provider's state is seen by a later envelope and by a concurrent one.

## What the host does once these exist

`serve.py` becomes the frontdoor and nothing else:
1. Start one kernel and deliver the host's start capability.
2. Listen.
3. Hand each request's raw bytes to the kernel as one envelope.
4. Write each part the kernel answers, in order, until the final answer.
5. Exit when the kernel exits.

Everything else moves into the host's bundle as declared capabilities and providers:
- **Runs:** admission, then detached execution, events, trace and completion.
- **The run and estate streams:** answers in parts. Their keep-alives and session rechecks are declared recurrence
  within the delivery.
- **The live observation channel:** a process-scoped provider.
- **The drawing poll:** a detached, recurring delivery that the start capability begins.
