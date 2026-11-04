# Credential-format diagnosis

The live host identified the immediate failure as **ACCEPTANCE_SESSION_FORMAT_INVALID**. The value released from `SFX_API_ACCEPTANCE_SESSION` does not satisfy the API ingress's declared session-bearer format. This diagnosis exposes no credential value, prefix, length or hash.

The owner's standard `store-credential` operation succeeded: run `110ccb93-b9a2-ef24-fbe9-b7e74b40b528` returned `CREDENTIAL_STORED`, and the deployed vault entry timestamp matched. Storage does not issue or convert a credential into an API session. The acceptance adapter's expectation that the stored value is an already-issued API bearer is the additional dependency introduced by the host implementation.

## Where the dependency entered

- The original profile draft `62da685` did not require a coordinator credential.
- The host amendments assumed machine authentication. Commit `1be9e95` records that this assumption was wrong: ingress resolved only user sessions.
- `2089ecf` introduced dedicated-principal password sign-in. Its co-author trailer names Claude Opus 5.5.
- `db00da1`, also co-authored by Claude Opus 5.5, replaced that unapproved password flow with `SFX_API_ACCEPTANCE_SESSION`, interpreted as a stored API session. The recorded reason was to follow the owner's standard `store-credential` process and stop password sign-in.
- The current v4 implementation retained that interpretation and made the coordinator callable from the operator's existing session. No successful v3 coordinator invocation was recorded. This first end-to-end exercise exposed an unverified integration.

The earlier diagnosis treated 401 as a reason to renew the entry and asked the owner to test its bearer manually. Neither request established the cause. The host now distinguishes incompatible credential format from a correctly shaped bearer rejected by authentication. The manual API-check request is withdrawn; the unresolved credential integration remains host work. This does not authorize treating the opaque stored value as a password, signing in, or changing the pinned probe principal.

## Live evidence

Image `sfx-api:hosted-v4-c`, ACR build `cab2`, is deployed at `sha256:5c42825278f3f9ba781c55e0507fe2ea50a9eba853c7ad4e0d11083c75d33285`. [Startup evidence](container-startup.log) confirms readiness at `2026-11-04T23:14:41.8362828Z`. The profile remains version 4 at its unchanged digest. [All deployment pins](deployment-pins.json) match the actual receipt and final image context, including the Dockerfile's kernel-host.json overlay.

The supported installed CLI ran attempt `3043cd09-ffe9-454e-a4e5-f0dfd58c1010`, following profile discovery run `0708cafb-d6c2-42d8-f21d-5354e190400c`. It returned exit 2 and the [REJECTED receipt](receipt.json). All T1–T7 checks report the typed format failure, with no admitted probe runs. [Independent readback](readback.json) verifies the exact bytes, and the [delivery proof](delivery-proof.json) is UNFULFILLED. No credential was changed by this diagnostic.

Four new boundary tests passed, including canonical session encodings, format refusal without disclosure or HTTP dispatch, valid-format authentication refusal and wrong-principal refusal. The 22 provider checks passed against the regenerated bundle, and the new failure validates against the existing receipt contract. The earlier 26 contract and 37 client checks remain recorded in the parent deployment report.

The evidence establishes the format mismatch. It does not identify what kind of secret was stored, prove its expiry or revocation, or establish successful T1–T7 acceptance.
