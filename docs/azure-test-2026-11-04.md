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

## The swap to `ec953c9`

- **Image:** `bpmaiengineacr.azurecr.io/sfx-api@sha256:518fd40b254536f8b138bd21c348660f117a38ad8eacaa31989b324acef1fee0`
  (tag `sfx-api:ec953c9`), ACR build `caav`. Kernel `244e0129`, unchanged. The bundle is unchanged too: 26 documents
  under the pin `mCfYS9h8kuu6JogMcXTrlFC6Yps0TjGaYdcBrKhJyKM=`, all checked against the manifest in the build context.
- **Replaced:** `sfx-api:f2bf96f` (`sha256:06902c4c…`), which is the rollback.
- **Before the swap:** the site answered 0 to 5 requests a minute from 16:00 to 16:19 UTC, and no run was being
  followed.
- **The swap:**
  - 16:20:30, the image was set;
  - 16:20:58, the image was pulled;
  - 16:21:14, the warm-up probe succeeded after 15.4 s and the site started;
  - 16:21:36, the previous container stopped.

  Every probe of `GET /sfx/v1/nope`, one each 10 s from 16:20:46 to 16:25:46, answered 404 `OPERATION_NOT_DECLARED`.
  There was no outage.

## T4 through the deployed run API

The operator's CLI ran `sfx-api capability observe probe-hosted-execution` with `{"check":"payload"}`, signed in as
principal `565de6d4`. The run was `af211d49-1972-ac88-d0f1-def9c5e62d0a`.

| | |
| --- | --- |
| Run | `completed`, exit code 0, from 16:26:48.620 to 16:26:57.816 UTC |
| Client | started 16:26:45 and returned at 16:28:08, so 83 s, of which the run took 9 s |
| Payload, as observed | 6,291,456 UTF-8 bytes, `sha256:9afa6a901fd5ea4d49cb734d1f88e73a9c73c7449773e0f98b6f90159d1cdadc` |
| Read back with `sfx-api run --json --events` | 19 events, no gaps; the output payload had the same byte count and digest |

Both figures match the probe's declared `payloadBytes` and `payloadSha256`, and the profile's `maximumResultBytes`.

This is operator diagnostic evidence through the installed client, not an acceptance receipt: the coordinator's own
authenticated `GET /sfx/v1/runs/{runId}/output` establishes T4 (hosted-execution-profile.feature). The 74 s between
the run's end and the client's return is not yet broken down. The coordinator's whole budget is 150 s, so that time
counts against it.

## Slice 3: the acceptance coordinator (`21e7499`)

- **Image:** `bpmaiengineacr.azurecr.io/sfx-api@sha256:9fb211e1275195bc876261b410ea41a4b46cf4809c8a18904991d9f017d3432f`
  (tag `sfx-api:21e7499`), ACR build `caax`. Kernel `244e0129`, unchanged. The bundle holds 27 documents under the pin
  `CwjJy9jhaiO4MnlpvgRgI4upKe3Z2Jx8ax7uUtkGXBo=`, all checked against the manifest in the build context.
- **Replaced:** `sfx-api:2089ecf` (`sha256:8fffef2a…`), live from about 17:26 to 17:41 UTC. It let a caller start the
  coordinator as a run with any `principalId` in the run's input. `21e7499` refuses that admission. The vault held no
  acceptance password while `2089ecf` was live, so the coordinator could not sign in. The rollback is `sfx-api:ec953c9`
  (`sha256:518fd40b…`).
- **The deployer's record of the image:** the App Service setting `SFX_API_IMAGE_DIGEST`, set to the digest above at
  17:37:39 UTC, before the image. Each deploy now restarts twice: once for the setting, once for the image. The
  setting was first set at 17:23:11, for `2089ecf`.
- **The swaps:** the image was set at 17:39:59 UTC, and the site started at 17:41:28. Every probe of
  `GET /sfx/v1/nope` answered 404 through both restarts of each deploy, so there was no outage.

Checked on the deployed host after the swap:

| Check | Result |
| --- | --- |
| `POST /sfx/v1/hosted-execution/acceptance`, unauthenticated | 401 `CALLER_REQUIRED`: the route is declared |
| `read-hosted-execution-profile`, run `c2716df8` | profile version 2, `sha256:a27ac5f5…`, and the text it answers hashes to that digest |
| `accept-hosted-execution-profile` admitted as a run | refused `ADMISSION_REQUEST_PATH_ONLY` |
| `probe-hosted-execution` `configuration`, run `70fd87a4` | `settingsDigest` `sha256:2daac7e0…`, request 2 kernels, 30000 / 195000 / 198000 ms; worker 3600000 / 3605000 ms, 2 at once, 64 waiting |

Not checked yet: the coordinator itself. It needs the vault entry `sfx-api-acceptance-password`, which is not
provisioned, and a caller signed in as `staging-release-acceptance`.
