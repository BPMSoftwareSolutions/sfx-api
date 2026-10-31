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
