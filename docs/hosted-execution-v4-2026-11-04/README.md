# Hosted execution version 4 deployment

Version 4 is deployed on `sfx-api-test`, and the updated existing CLI is installed. **Acceptance is UNFULFILLED.** The current `hosted-v4-c` image [diagnoses a credential-format mismatch](credential-diagnosis/README.md) at the host boundary. This report below preserves the initial `hosted-v4-b` deployment and its 401 investigation. All T1–T7 checks are typed precondition failures with empty run IDs. No probe was admitted and no credential was renewed, replaced, signed in or revoked by acceptance.

The owner renewed the entry through `store-credential`, and its non-disclosing receipt and deployed vault timestamp agree. Acceptance still received 401, including after a confirmed host restart. The remaining prerequisite is a stored API session that passes `/sfx/v1/session` for the dedicated principal. After that, run the supported acceptance command with a new attempt ID and verify a new ACCEPTED receipt and FULFILLED proof. This record does not certify successful probe execution, throughput or the 150-second measurement budget.

## Initial version 4 release and implementation

| Item | Deployed identity |
| --- | --- |
| Image | `bpmaiengineacr.azurecr.io/sfx-api@sha256:0704f06b6dc8edd8e0b1c1cd4488b77640b195adc696c2399ca5e620feb04b40` |
| Tag / ACR build | `sfx-api:hosted-v4-b` / `cab1` |
| Profile | version 4, `sha256:0b5856fbe48aa9dba5783631e969d6628f681707b6bdcfa762fb058ca65d8f8d` |
| Bundle, 29 documents | `sha256-base64:zC7Q9MeFV1P0cTC7CL65d8D95Z+CDJl2/MGoQsUYC3I=` |
| Kernel, SDA 29355da | `sha256:244e0129254e99752cf81d6df4026191d039dcaa8b8bcffcaff4baed9a74c1af` |
| Host files | `sha256:6412e84fd7cf29cd08a8f6c2b22a510b1aa94dd2b104bafc5c1dad08d1642c1b` |

The profile was observed live at 22:54:41 UTC. The configured App Service image, ACR tag digest and deployer's `SFX_API_IMAGE_DIGEST` setting [independently matched](deployment-verification.json) the receipt. `/home` storage is enabled. [Deployment pins](deployment-pins.json) were computed from the final image context; [rollout observations](rollout.json) retain the profile transition.

The host binds the new C# provider module through its declared HTTP and record ports. It owns the operator gate, dedicated probe credential release, deployment-wide admission, receipt validation and persistent attempt records. The HTTP facade supplies an actual admission UUID; declared ingress supplies authenticated caller context. The CLI adds discovery and request dispatch to the existing capability command, with strict schema/identity checks, bounded waits, evidence retention and independent readback. See [provider implementation](../../providers/hosted/README.md).

An initial `hosted-v4-a` image failed startup because the raw Base64 manifest-reader pin was stale. Version 3 was restored while the builder was corrected to update and verify both pin forms. The corrected `hosted-v4-b` passed the actual bundle-reader test before deployment. No acceptance evidence is claimed for the failed image.

## Real invocation and recovery evidence

The operator ran:

```powershell
sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user
```

- Attempt: `5f8d64d2-7922-4436-84fb-3f303991212a`; request execution: `9d8775ef-6a86-47ea-bb49-2a20e8a3f30f`.
- Discovery run: `968a15ef-21ab-0b05-0451-03604b291034`. The coordinator itself used the request path.
- [Receipt](receipt.json): REJECTED at 22:55:19 UTC, `ACCEPTANCE_SESSION_REJECTED` for every check. Operator `565de6d4-ebcd-408b-9359-04d21dc62183` and dedicated probe binding `00e053bd-b090-4ff9-be25-64089d170fb2` remain separate.
- [Independent readback](readback.json): exactly 3,322 UTF-8 bytes, `sha256:3a78d42d0ce9fa2983efef3d642b9a15cce4de66e930fe125f5378490bea2ec7`.
- [Delivery proof](delivery-proof.json): UNFULFILLED, identifying the actual installed client artifact used for this invocation. The receipt and proof are unchanged historical bytes.
- [Negative checks](negative.json): unauthenticated caller 401, changed profile 409, body identity 400, duplicate correlation 400; all typed errors.
- [Concurrent requests](busy.json): attempt `b5ca2486-d709-4a88-90de-616ee2d865da` returned 409 `ACCEPTANCE_BUSY` in 1,174 ms while attempt `cf76de54-a624-4198-a413-f2ce2a10d223` ran and returned a credential-rejected receipt. These were separate diagnostic invocations after the original attempt was known terminal.
- App Service restart completed startup at 22:58:34 UTC. [Post-restart readback](readback-after-restart.json) and [CLI readback](readback-cli.json) match the original receipt bytes. The CLI read used discovery run `c8acdaae-d1e2-3131-6323-501a187677b5` and exited 0. [Restart check](restart-check.json) records the read time and byte comparison.

Readback uses the supported command with `--input '{"attemptId":"5f8d64d2-7922-4436-84fb-3f303991212a"}'` and capability `read-hosted-execution-acceptance`. It neither opens the probe credential nor restarts acceptance. Process death to UNKNOWN recovery is covered by local cross-process provider tests; no live interrupted coordinator is claimed here.

## Renewal investigation

The owner confirmed renewal, then supplied run `110ccb93-b9a2-ef24-fbe9-b7e74b40b528`. An [independent API read](renewal-readback.json) returned `CREDENTIAL_STORED` at `2026-11-04T23:01:02.4658373Z`. Read-only [host vault metadata](vault-renewal-metadata.json) shows that same timestamp for `SFX_API_ACCEPTANCE_SESSION`. No credential value was opened or retained by that metadata inspection.

The fresh installed-CLI attempt `36c62ea2-a748-41b8-8e55-8d5e55e2bb29` still returned [REJECTED](after-renewal/receipt.json) with a verified [UNFULFILLED proof](after-renewal/delivery-proof.json), and the CLI exited 2. The operator's existing session independently passed the same Python HTTPS transport, returning its expected principal and HTTP 200.

To rule out request-kernel caching, the host was restarted and new-container readiness was confirmed at `2026-11-04T23:06:01.8748798Z`. A new supported-CLI attempt `836cc941-934b-4f17-a06b-2c1773cb8d07` again received 401 at the probe-session precondition: [receipt](after-renewal-restart/receipt.json), [readback](after-renewal-restart/readback.json), [delivery proof](after-renewal-restart/delivery-proof.json), [startup log](after-renewal-restart/container-startup.log). All deployment pins still match, and all probe run-ID arrays remain empty. Each preceding attempt was known terminal before the next diagnostic invocation; no uncertain POST was automatically replayed.

The 401 response did not distinguish an expired, revoked, malformed or otherwise invalid session. The subsequent [host-side diagnostic](credential-diagnosis/README.md) establishes incompatible bearer format. The request for the owner to perform a manual API check was withdrawn. No account switch, password helper or substitute principal has been added to acceptance.

## Validation

The contract suite passed 26 tests; provider integration checks passed 22; the client suite passed 37, including installed Windows launcher checks. The 19 synthetic example payloads remain contract fixtures. A final client regression additionally preserves received receipt bytes before schema/identity verification, without producing a proof for invalid evidence; its updated installation is recorded in [client-installation.json](client-installation.json).

```powershell
python -B contracts/validate-hosted-execution-receipt.py docs/hosted-execution-v4-2026-11-04/receipt.json
python -B contracts/validate-hosted-execution-receipt.py docs/hosted-execution-v4-2026-11-04/readback.json
python -B contracts/validate-hosted-execution-receipt.py docs/hosted-execution-v4-2026-11-04/delivery-proof.json --receipt-artifact docs/hosted-execution-v4-2026-11-04/receipt.json
```

These checks establish valid rejected evidence, not fulfillment. A valid host-vault probe session and a successful full live acceptance remain required.
