# sfx-api-test, 2026-11-03: the host served from its bundle

## What was deployed

- **Commit:** `5eb18bf`, branch `deploy/bundle-host-29355da`.
- **Image:** `bpmaiengineacr.azurecr.io/sfx-api@sha256:540bf6a968e0da2016dc5143a99e4cd06123369e35b3c7afeb79aa6477e8aded`
  (tag `sfx-api:5eb18bf`). ACR build `caaq`, succeeded.
- **Kernel:** `244e0129254e99752cf81d6df4026191d039dcaa8b8bcffcaff4baed9a74c1af`, from SDA `29355da` (CI green). Each
  declared graph is compiled once per process, and a warm envelope pays no extra round trips for the declared-read port.
- **Host:**
  - the facade that delivers `read-api-host-configuration` to all six kernels before it listens;
  - the provider authority that binds the declared-read port to `answer-host-declared-read`;
  - the bundle, with its manifest pinned at `1SOc/FEhT0S012t7URdaOIBCzkbTPdqi7q9S6igzV/8=`. All 24 documents were checked
    against the manifest in the build context.
- **Replaced:** image `sha256:4d63139135377f3e6fd4f78d23e21d6dc8669d8f56f4d175fa12d331d2660ee8`, tag `sfx-api:a57ebba`.
  Pointing the site back at it is the rollback. The estate's `.v1` providers still serve that image.

## The swap

The image was set at 21:29:40 UTC. The container logs and a probe of `GET /sfx/v1/nope` every 10 s:

| UTC | What happened |
| --- | --- |
| 21:30:08 to 21:31:06 | the old container answered, in about 1.0 s per probe |
| 21:31:08 | the new container's facade logged `a kernel did not answer read-api-host-configuration; the host does not listen`, and the container exited with code 1 after 60.1 s |
| 21:31:17 to 21:31:27 | App Service answered 503 |
| 21:31:40 | App Service started the same image again |
| 21:31:59 | the warm-up probe succeeded after 19 s |
| 21:32:00 | the site started, and a probe waiting since about 21:31:37 was answered |

The site was down for about 50 s.

On the first, cold start, six kernels admitted the bundle at once on the plan's one vCPU. At least one ran past its
58 s answer bound, and the facade stopped before listening, as its feature declares. The second start, from a warm
cache, admitted all six within 19 s. A cold start after every deploy can fail this way again.

## Measurements

Sequential requests from a workstation, as on 2026-10-31: alternating `GET /sfx/v1/nope` (404) and
`GET /sfx/v1/session` without a credential (401). Server time is time to first byte minus the TLS handshake, with
nearest-rank percentiles.

| | 2026-10-31 (`f32450fa`) | 2026-11-03 (`5eb18bf`) |
| --- | --- | --- |
| Requests | 30, after the kernel's first request | 30, 15 answered 404 and 15 answered 401 |
| Server time p50 | 0.88 s | 0.46 s |
| Server time p95 | 3.35 s | 0.57 s |
| Server time min / max | 0.81 / 4.04 s | 0.42 / 0.61 s |
| A refused sign-in (`POST /sfx/v1/session`, empty identifier) | 0.47 s | 0.19 s, 400 `LOGIN_INPUT_INVALID` |

No request took longer than 1.05 s.

The plan's memory and CPU (`ASP-sidefxgroup-ad2e`, P0v3), as 5-minute averages:

| UTC | Memory | CPU |
| --- | --- | --- |
| 21:19 to 21:28 | 77 to 78% | 8 to 9% |
| 21:29 to 21:33, the swap | 76% average, peaking at 92% | 25% average, peaking at 46% |
| 21:34 to 21:48 | 60% | 9 to 14% |

## Not checked here

Sign-in with a real identity, session reads, runs and streams need a signed-in caller. sfx-platform's signed-in
acceptance covers them.

## The second swap: two request kernels (`ba0cdb4`)

- **Image:** `sfx-api@sha256:99a620e393af50de6318b56539f148caaa12bc82e77a9bd1b5f64a81e926dab4` (tag `sfx-api:ba0cdb4`),
  ACR build `caar`.
- **Kernel set:** two request kernels, workers that start on their first run, and bookkeeping on the drawing reader's
  kernel. Four kernels admit at start.
- **The swap:** the image was set at 22:10:08 UTC and the site started at 22:10:57. Every probe answered through it, so
  there was no 503 this time.
- **Plan memory:** 68 to 70% just before the swap, after runs had grown the old container's workers; 58 to 60% after it.

| Sample (UTC) | Requests | Server time p50 / p95 / max | Refused |
| --- | --- | --- | --- |
| 22:16, while other clients were active | 30 sequential | 1.35 / 3.63 / 4.33 s | 4 answered 503 |
| 22:19, quiet | 30 sequential | 0.46 / 0.56 / 0.60 s | none |
| about 22:18 | bursts of 2, 4 and 6 at once | slowest 2.9 s | 2 of the 6 answered `REQUEST_KERNEL_BUSY` |

- **A second request kernel does not stop the busy refusals.** The plan has one vCPU, so two kernels running at once
  each run at about half speed, and the queue drains no faster. A request still waiting after the declared 2 s is
  refused.
- **The same refusals hit `5eb18bf`.** sfx-api-test answered 17 requests with a 5xx between 21:55 and 21:58, with plan
  CPU at 74 to 78%, while the Explorer followed a run. On the screen they showed as
  `Circuit unavailable (REQUEST_KERNEL_BUSY)`.
- **What the refusal samples miss.** They exercise no use case: no sign-in, run, stream or circuit read.
