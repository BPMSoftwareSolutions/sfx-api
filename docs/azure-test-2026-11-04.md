# sfx-api-test, 2026-11-04: the hosted execution profile

## The T4 payload runs were not completed

Two T4 payload runs did not finish:

- `4f13d52c-df30-5e0f-a4f3-3d8e7f64ab02` at 15:28 UTC, on image `sfx-api:2aaceba`;
- `0d55a327-610f-0b14-a1f1-67c862c6ae0b` at 15:56 UTC, on image `sfx-api:f2bf96f`. The consumer's diagnostics are in
  [hosted-probe-readback-2026-11-04.json](hosted-probe-readback-2026-11-04.json).

For both runs, the host log on sfx-api-test shows the same three lines:

```
[sfx-api kernel] project-api-run-events {"code": "KERNEL_EXITED"}
[sfx-api run <runId>] project-api-run-events answered null
[sfx-api run <runId>] its events stopped before its end; it is not completed
```

The worker did answer. The host lost the run when it handed the run's end to `project-api-run-events` on the drawing
reader's kernel.

**Cause.** `Kernel.deliver` encoded every envelope with Python's default `ensure_ascii`. Each character outside ASCII
became a `\uXXXX` escape, and a character outside the Basic Multilingual Plane became two. The T4 payload is 393216
repetitions of `aé€😀abcdef`: 16 UTF-8 bytes per repetition, 31 bytes once escaped. A run's end carries the worker's
whole delivery, so the escaped envelope was 12,190,331 bytes. The kernel reads at most 8 MiB per line
(`MaximumEnvelopeLineBytes`, SDA `ResidentDelivery.cs:55`). On a longer line it answers `INPUT_TOO_LARGE` and exits
with code 2.

**Why the log said KERNEL_EXITED.** The kernel exited before the whole line reached it, so the facade's write failed.
The facade then wrote the line to a new kernel, as if the first one had never read it. The new kernel refused it too,
and exited. The first kernel's `INPUT_TOO_LARGE` answer was never read. That breaks the approved scenario "An envelope
a kernel may have begun is never delivered again" (features/host-facade.feature).

**The fix.**

- The facade writes each envelope as UTF-8, with no character escaped that UTF-8 can carry. The T4 end is then
  6,292,091 bytes.
- A kernel that answers before it ends gives the delivery that answer, and the envelope goes to no other kernel.

The fix is in `host/serve.py`, scenario "An envelope reaches its kernel as one line of UTF-8". The response composer
already counts the body's UTF-8 bytes for `Content-Length` (`sfx-api-ingress.dependency.json`, `compose-response`).

A scratch replay on WSL against kernel `244e0129` is a diagnostic, not evidence. It sent the facade's envelope for the
T4 end both ways:

- escaped: refused `INPUT_TOO_LARGE`, exit 2;
- UTF-8: answered `run.exited`.

The check is T4 through the deployed run API.
