# Hosted execution contract: current state and responsibility

This is the **version 4 contract candidate for host review and implementation**, with exact profile digest `sha256:0b5856fbe48aa9dba5783631e969d6628f681707b6bdcfa762fb058ca65d8f8d`. It closes the missing invocation boundary in the canonical feature, typed profile, request/context contracts, receipt, error contract and delivery/readback contracts. The [payload and protocol specification](hosted-execution-invocation.md) contains the complete interface and links to schema-checked example payloads.

The host's [deployment record](../docs/azure-test-2026-11-04.md) still reports **version 3** on image `sfx-api:db00da1`, with profile digest `sha256:53d88521d1767295fd4967ce3bcf90d3606b7e0b63e2c2c3ba66a5a685e6957b`. This edit changes no deployed program, bundle, client or permission. Version 4 is not installed or accepted, and no live acceptance receipt is claimed.

The `.v1` filenames and contract identifiers denote the schema family. `profileVersion` identifies the promise revision. The JSON profile, receipt schema and feature remain the authority; this document describes their state and history.

## Where the dependencies entered

| Recorded revision | Coordinator and authority requirement |
| --- | --- |
| First version 1 draft, `62da685`, 2026-11-04 08:56 EST | No coordinator credential requirement. The scope was the host's execution promises and their acceptance evidence. |
| Revised version 1, `3e0f38e`, 10:05 EST | Added the request-path coordinator, `admittedCallers: ["machine"]`, `host-machine-credential`, two request kernels and a 150 s budget. The deployed ingress could not produce that machine caller. |
| Version 2, recorded in `1be9e95`, 11:01 EST | Replaced machine authority with the `staging-release-acceptance` user principal and password reference `sfx-api-acceptance-password`, followed by HTTPS sign-in. The consumer-side assistant also added a local password helper. That workflow is now retired. |
| Version 3, `db00da1`, 14:21 EST | Uses `SFX_API_ACCEPTANCE_SESSION`, provisioned by the standard `store-credential` capability. It checks the stored session through HTTPS `GET /sfx/v1/session`; it never signs in or revokes it. |

The password workflow was an implementation amendment, not an original renderer requirement. Recording an implementation choice in a profile does not establish that the owner requested the added operational burden. The current canonical feature records the owner's direction to use the standard credential process.

## Current authority boundary

Version 4 deliberately separates the two identities and closes the unfinished caller workflow:

1. `acceptance.coordinator.admittedCallers` binds **host-acceptance-operator** to the existing operator principal `565de6d4-ebcd-408b-9359-04d21dc62183`. Its existing authenticated CLI session initiates acceptance and reads its retained evidence.
2. `acceptance.coordinator.probeAuthority` continues to bind **staging-release-acceptance** to `00e053bd-b090-4ff9-be25-64089d170fb2`. Only the host provider releases `SFX_API_ACCEPTANCE_SESSION` for probes and their own-run readback.

This changes the acceptance initiator binding; it does not grant arbitrary signed-in users access, widen probe run visibility or authorize an identity supplied in a request body. The host must update the interface and provider gates together with the pinned profile. The deployed version 3 gate still refuses this operator until that implementation is published.

The host reports that store run `876426ad-0993-0e10-3386-433a07350202` returned `CREDENTIAL_STORED` for `SFX_API_ACCEPTANCE_SESSION`, and that a subsequent declared read returned the same non-disclosing receipt. This document does not retrieve or expose that session.

## Host completion work

The required supported entry is the **existing command surface** `sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user`. The host supplies the client support and declared dispatch to **`POST /sfx/v1/hosted-execution/acceptance`**. It also supplies `read-hosted-execution-acceptance` through the same command surface, dispatched to the declared request-path GET. No new CLI verb, consumer-authored script, password workflow or account switch is a prerequisite.

The host implementation checklist is concrete:

1. Publish the versioned client support for profile discovery, exact digest verification, origin binding and request-path dispatch for the two named capabilities. Unsupported descriptors fail before coordinator dispatch; admission to `/runs` stays forbidden for the coordinator.
2. Declare the interface's empty POST body, correlation/profile headers, trusted context mapping and pinned operator gate. The runtime request identity is carried into the receipt, not replaced by an evaluator-generated UUID. A profile change after discovery is refused before credential release.
3. Preserve the standard stored probe session and its dedicated identity. Check it before admitting probes. Missing, expired, revoked or mismatched credentials produce typed failures; renewal remains the host operator's standard `store-credential` responsibility.
4. Declare deployment-wide single-coordinator admission and release it on every termination path. Retain attempts and exact terminal receipt bytes through `sfx-api-host-acceptance-record-port.v1`, including restart and uncertain-outcome handling, before claiming a returned receipt.
5. Declare the authenticated, non-secret readback capability and its closed request/result contracts. It reads only the named acceptance attempt, never opens the probe credential, and does not imply access to other runs.
6. Update the receipt projection and client response handling for the published schemas. Preserve REJECTED receipts and typed failures; never automatically retry an uncertain POST or fabricate a receipt when none was obtained.
7. Rebuild and pin the interface, provider programs, profile reader, schemas and client as one verified release. The host supplies these as declared capability/program changes through its existing authoring process; the retired password script is not a substitute.
8. Execute the supported command from the actual operator session against the deployment, run T1–T7, independently read the retained receipt and reconcile every attempt, request, run and deployment identity. Deliver the real receipt and `hosted-execution-delivery-proof.v1`. Only a verified FULFILLED proof containing an ACCEPTED receipt closes this host work.

The canonical feature includes positive and negative scenarios for these obligations and provider bindings. The schemas enforce the payloads, identities, thresholds and result alternatives; the verifier also checks cross-field identity, interval arithmetic and retained artifact bytes. Local tests and the example JSON files are explicitly synthetic, not live evidence.

The 150 s budget is already a declared host acceptance constraint. The host's earlier successful T4 operator run took 83 s of client time; only a real coordinator run establishes whether all checks fit. If the coordinator cannot finish, its implementation needs correction or a concrete contract change; the consumer must not treat it as accepted.

Consumer obligations remain C1–C4: declare providers for the host runtime, bound child execution and expose failures, carry pinned third-party packages, and handle insufficient shared temporary space. Once the host proves its profile, the consumer proves the renderer and published artifacts against those deployment and profile pins. Building the host's invocation client is not an additional consumer obligation.

## Obsolete client retired

`tools/invoke-hosted-acceptance.ps1` now stops immediately with `HOSTED_ACCEPTANCE_PASSWORD_FLOW_RETIRED`. It prompts for no password, calls no API, changes no credential and does not revoke the stored session. Its regression check verifies this on installed PowerShell versions. Old instructions to run that file no longer start the version 2 workflow.

`contracts/validate-hosted-execution-receipt.py` validates received receipts, retained readback records and delivery proofs. It rejects duplicate keys, checks the current profile and schemas, reconciles execution/attempt/run references and T7 intervals, and checks exact artifact bytes. It does not issue receipts or independently establish live execution and deployment provenance.

## Existing evidence and checks

The [earlier operator diagnostics](../docs/hosted-probe-readback-2026-11-04.json) recorded T3's expected language refusal and a T4 run that had no persisted state or output. The host subsequently fixed the oversized escaped-JSON envelope and recorded successful T4 run `af211d49-1972-ac88-d0f1-def9c5e62d0a`: 6,291,456 UTF-8 bytes with the required digest. Those measurements are useful diagnostic evidence; they are not the outstanding version 3 coordinator receipt.

```powershell
python -B -m unittest discover -s contracts/tests -v
```

These tests validate contract authoring and the retired helper's lack of effects. Live host acceptance remains incomplete until the declared coordinator executes and its receipt is verified.
