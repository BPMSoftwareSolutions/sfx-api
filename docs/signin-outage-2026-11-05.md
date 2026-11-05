# sfx-api-test, 2026-11-05: sign-in answered 503, and the identity service was healthy

## What was wrong

`POST /sfx/v1/session` answered `503 {"status":"IDENTITY_UNAVAILABLE"}`. Everything else answered normally.

The identity service was not involved. Checked live, on the deployed host, before any change:

| Checked | Result |
| --- | --- |
| An existing session resolves (`whoami`: ingress, `check-api-session`, identity database) | `AUTHENTICATED`, principal `565de6d4`, session `ca674d69` |
| An estate database read (`list-principal-runs`, run `10ed8170`) | `READ`, 70,857 runs |
| The host vault and Argon2 derivation (`verify-password-derivation`, run `8d398554`) | `MATCHES` |
| The frontdoor (`GET /sfx/v1/nope`) | 404 `OPERATION_NOT_DECLARED` |

So the ingress, session resolution, the identity database, the host vault and the password derivation were all working.
Only opening a *new* session failed.

## The cause

Reproduced on WSL against the estate, delivering `open-api-session` to kernel `244e0129` with the deployed provider
authority and bundle. The answer:

```
CELL_EXECUTION_FAILED at cell:mechanic:open-api-session.login
"The ConnectionString property has not been initialized."
```

The same probe with the authority and bundle of `f2bf96f` and of `db00da1` answers `AUTHENTICATION_REJECTED`, which is
the correct answer for an identifier no principal has.

The host was serving **its own copy of `open-api-session`** from the pinned bundle instead of the estate's definition.
That copy's login step takes the identity database connection string as a plaintext input value. Since sfx-embody's
`vault-reference-passing.sql` (2026-11-02, ADR-0019), the estate's carry port hands the leaf an *unopened* reference
instead, and the leaf opens it inside its own call. The bundle's copy never receives a connection string, so
`SqlConnection` has none. `serve-http-request` maps that unusable result to 503 `IDENTITY_UNAVAILABLE`.

**How it came back.** This is the same failure as 2026-11-03 (`5eb18bf`). `f2bf96f` fixed it by removing
`open-api-session` from `authorities/host-bundle/manifest.json`, but left `capabilities/open-api-session.json` on
disk. `tools/build-hosted-release.py` rebuilds the manifest from
`sorted((BUNDLE/'capabilities').glob('*.json'))` — every JSON file in the directory. The first release build that ran
it listed the stale document again, and the host went back to serving its own sign-in.

The manifest went from 27 documents at `db00da1` to 29 at `4efe39d`: the new
`read-hosted-execution-acceptance`, and `open-api-session` re-listed.

Nothing in those commits targeted identity. The regression came from a manifest built by directory listing meeting a
document that was only unlisted, never deleted.

## The fix

`ccb82ed` deletes `authorities/host-bundle/capabilities/open-api-session.json`. The glob can no longer list it, so no
later release build can reintroduce this. The bundle holds 28 documents under the pin
`cYmRFVRLSrW+5H0igNDXEW9/IiS8GzM67WtrH+4d8Uw=`.

Built with the host's own pipeline (`tools/prepare-hosted-image.ps1`), which verified every document digest, the
startup manifest pin and the host-file digest `sha256:b4ec8cea…`.

- **Image:** `bpmaiengineacr.azurecr.io/sfx-api@sha256:417c9f0e8501c87f11e607c3e1848af247f29d6395a67c68a0ecfa6e19151a61`
  (tag `sfx-api:ccb82ed`), ACR build `cab5`.
- **Replaced:** `sha256:9b626f660c56a9089fc73f18ca6f270ca44213abc1e2fb2616e8980c7b23d6fa`, the rollback.
- `SFX_API_IMAGE_DIGEST` was set to the new digest at 01:32:53 UTC, then the image at 01:35:25. Every probe answered
  404 through both restarts; there was no outage.

Verified on the deployed host afterwards:

| Request | Answer |
| --- | --- |
| `POST /sfx/v1/session`, identifier no principal has | 401 `AUTHENTICATION_REJECTED` |
| `GET /sfx/v1/session`, no caller | 401 `CALLER_REQUIRED` |
| `POST /sfx/v1/hosted-execution/acceptance`, no caller | 401 `hosted-execution-invocation-error.v1`, stage `caller`, `CALLER_REQUIRED` |

## Still open

The window is not established. `f2bf96f` was the last deploy whose sign-in I verified, at 2026-11-04 15:22 UTC. The
deploys after it (`ec953c9`, `2089ecf`, `21e7499`, `db00da1`) were verified with `GET /sfx/v1/nope` and route probes,
not with a sign-in. The first release build to run `build-hosted-release.py` is where sign-in broke, and that is in
`24e8d51` or later.

**Every deploy should probe sign-in.** A frontdoor probe passes while sign-in is down.
