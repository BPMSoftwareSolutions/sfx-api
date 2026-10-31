# Azure test deployment — 2026-10-31

The independent API is running at https://sfx-api-test.azurewebsites.net.
No sfx-platform endpoint or consumer routing was changed.

- Runtime source: `de4ac25` (two bootstrap fixes on `b12a7e5`).
- Image: `bpmaiengineacr.azurecr.io/sfx-api@sha256:dbe0814fb08fdfdca4ac3005cbbbfb1f95fde63c9331308ac993c1add5ba3c18`.
- ACR build: `caa4`, succeeded.
- Kernel: `9f78e78d16b5da117162e35f9611386f560ddd2c6e12130ef2285d2564372b4b`, unchanged.
- System identity: `73360b59-e259-482f-90da-8f1658400a02`; AcrPull on `bpmaiengineacr` and Key Vault Secrets User on `aiengine-kv-20260406`.
- The three explicitly approved `sfx-api-credential-vault*` secrets were written and their App Service references resolved. Values were held in memory, never in command arguments or temporary files.
- HTTPS is required. Container logging is enabled.

Two cold-start defects were observed directly in Azure. COPY created root-owned
parents of the vault directories, so startup failed with `Permission denied`.
The Dockerfile now creates those directories as the runtime user before COPY.
Then `secret-tool` reported that `/org/freedesktop/secrets/collection/login` did
not exist. An isolated local test with dummy values reproduced that empty input
leaves the collection absent, while an empty line creates it. Startup now passes
that empty line to gnome-keyring. No API or estate behavior changed.

[Public test evidence](azure-test-2026-10-31/public-test.json) records:
unknown operation 404; anonymous session 401; authenticated session 200; one
`say-hello-world` run completed; the same endpoint returned its completed state,
`hello-world-greeting.v1` output and estate retention record. The test session
was revoked afterward.

Run: `ba94da98-9684-491a-a2b0-3f370e0b8db6`.
This proves deployment, authentication, execution and stored output read-back.
It does **not** establish complete observed execution evidence: the retained
record has `captureStatus: incomplete`, `traceComplete: false`, cursor 0 and no
graphs. Trace capture/event streaming, machine callers and the other documented
migration gaps remain open. This deployment is a test endpoint, not a platform
cutover or a replacement acceptance verdict.

## Redeploy with a resident kernel and the declaration cache (2026-10-31, later)

- Runtime source: `32a5aeb`. The host keeps one resident kernel (`instances: 1`; the plan is a shared
  4 GB P0v3 whose memory averaged 57 to 67% before the change).
- Image: `bpmaiengineacr.azurecr.io/sfx-api@sha256:f32450fa95369041934ed64d5b9163a114b7e050eba9020600c0cc0079be0a10`
  (tag `sfx-api:32a5aeb`). ACR build: `caa7`, succeeded.
- Kernel: `3988169345c45bb057763ed8fa57b9b5b0c24814c546da32401b63b2848ac224` (SDA `3296bc1`), which
  caches capability definitions per declared generation. The estate declares that generation since
  sfx-embody `declare-declaration-generation` (change tracking on the 50 tables the definition reads
  depend on).

Sequential requests from a workstation, alternating `GET /sfx/v1/nope` (404) and `GET /sfx/v1/session`
without a credential (401). Server time is time to first byte minus the TLS handshake; nearest-rank
percentiles.

| | Before (`dbe0814f`, a kernel per request) | After (`f32450fa`) |
| --- | --- | --- |
| Requests | 8 | 30, after the kernel's first request |
| Server time p50 | 4.74 s | 0.88 s |
| Server time p95 | 7.00 s | 3.35 s |
| Server time min / max | 4.46 / 7.00 s | 0.81 / 4.04 s |
| A refused sign-in (`POST /sfx/v1/session`, empty identifier) | 2.18 s | 0.47 s |

- The first request after the swap waited out the image pull and container start (the client gave up
  at 150 s); the next took 13.8 s, including the kernel's start; the following requests took about
  1.1 s.
- 25 of the 30 took 0.81 to 1.05 s. Five took 1.2 to 4.0 s. They are not cache refreshes: the
  generation did not move during the sample (change-tracking version 2 since 19:51 UTC). The plan's
  CPU was 10 to 12% at the time. The facade does not record the kernel's evidence, so their cause is
  open.
- Plan memory stayed at 59% with the resident kernel (64% while the old and new containers
  overlapped during the swap).

## Asynchronous runs (2026-10-31, later)

- Runtime source: `64f3a28`. Image `bpmaiengineacr.azurecr.io/sfx-api@sha256:fd1fd6d43b54ff0f18ce26382d4ad4b88af26f25b049b64e123aa05f0eaf2e97`
  (tag `sfx-api:64f3a28`), ACR build `caa8`, succeeded. Same kernel `39881693`. The site
  started on the new image at 21:38:47 UTC; its warm-up probe paid the kernel start.
- The facade adds a worker pool (one resident kernel, `SIDEFX_OBSERVE=1`, started by the first run)
  and acts on host directives (README, The host, Runs).
- Declared: `admit-api-run-live`, `open-api-run-stream`, `complete-api-run`, then the interface switch
  (definition `263343`, run `48000499`). The live interface equalled the last declared one before the
  switch, and the switch changes only `admit-run` and `stream-run-events`. Rollback: re-declare
  definition `253230`'s semantics (`git show ef32bda:authorities/sidefx-api-interface.v1.json`).
- After the switch, without a session: `POST /sfx/v1/runs` and `GET /sfx/v1/runs/x/events/stream`
  401 `CALLER_REQUIRED`, `GET /sfx/v1/nope` 404, a refused sign-in 400 in 0.47 s.
- Not yet run: the signed-in journey over HTTP (sign in, admit, stream, reconnect, read back).

## Run traces, the session rule and Idempotency-Key (2026-10-31, later)

- Runtime source: `26aeb9d`. Image `bpmaiengineacr.azurecr.io/sfx-api@sha256:6a01942195d470108647d075c2616c89b06fe7b9fc65be9b00c4e2d963f0f3b1`
  (tag `sfx-api:26aeb9d`), ACR build `caa9`, succeeded; serving since 22:19:42 UTC.
- The worker retains each run's trace in the run store before completing it, and a session caller's
  stream ends at the session's expiry or the first failed `check-api-session` recheck (README, The host,
  Runs).
- Declared: the trace encoding provider chain and `append-api-run-trace`, the revised
  `complete-api-run`, `check-api-session`, the revised stream and admission, the ingress with
  `headers.idempotency-key`, `serve-http-request` carrying `headers` (its text input re-applied 28 s
  later), the frontdoor binding `$header.`, and the interface (definition `263423`).
- After the changes, without a session: 404, 401 for the session, runs, the stream and the details
  read (an `Idempotency-Key` header included), a refused sign-in 400 in 0.46 s.
- Not yet run: the signed-in journey over HTTP.
