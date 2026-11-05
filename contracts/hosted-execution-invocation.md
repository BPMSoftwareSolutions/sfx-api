# Hosted execution invocation: version 5 payloads and protocol

**Version 5 deployed and accepted live.** All T1-T7 checks passed; the [retained delivery proof](../docs/hosted-execution-v5-2026-11-04/README.md) is FULFILLED. The owner directed removal of the added acceptance-session dependency. The profile pin is `sha256:9760b6001d84576090a47a1ac02a4db5d728fdb1aea8cbef66b57376ff152f33`. Acceptance uses the existing signed-in operator session end to end, without separate credentials. The [host handoff](hosted-execution-review.md) records completion obligations; the [version 4 record](../docs/hosted-execution-v4-2026-11-04/README.md) remains historical.

## Data contracts

All object schemas are closed: required fields must exist and unknown fields are refused. Parse JSON with duplicate-key rejection before schema validation and enforce date-time formats. Cross-field equality and actual evidence provenance are verified at runtime; a valid JSON shape alone is not a receipt of execution.

| Boundary | Authoritative schema | Complete example |
| --- | --- | --- |
| Deployment promises, identity bindings and invocation obligations | [profile](hosted-execution-profile.v1.schema.json) | [version 5 profile](sfx-api-hosted-csharp.v1.profile.json) |
| CLI acceptance input and POST body | [request](hosted-execution-acceptance-request.v1.schema.json) | [request.json](examples/hosted-execution-v5/request.json) |
| Internal coordinator input, constructed only by trusted host ingress | [context](hosted-execution-acceptance-context.v1.schema.json) | [trusted-context.json](examples/hosted-execution-v5/trusted-context.json) |
| T1–T7 receipt, including invocation identity | [acceptance receipt](hosted-execution-acceptance.v1.schema.json) | [ACCEPTED](examples/hosted-execution-v5/receipt-accepted.json), [REJECTED](examples/hosted-execution-v5/receipt-rejected.json) |
| Failure when no receipt was returned | [invocation error](hosted-execution-invocation-error.v1.schema.json) | [unsupported client](examples/hosted-execution-v5/error-unsupported-client.json), [missing session](examples/hosted-execution-v5/error-missing-session.json), [unknown response](examples/hosted-execution-v5/error-unknown-response.json) |
| Retained attempt lookup input | [read request](hosted-execution-acceptance-read-request.v1.schema.json) | [read-request.json](examples/hosted-execution-v5/read-request.json) |
| Retained attempt lookup result | [read result](hosted-execution-acceptance-read-result.v1.schema.json) | [receipt available](examples/hosted-execution-v5/read-result-receipt.json), [running](examples/hosted-execution-v5/read-result-running.json), [unknown](examples/hosted-execution-v5/read-result-unknown.json), [failed](examples/hosted-execution-v5/read-result-failed.json), [not found](examples/hosted-execution-v5/read-result-not_found.json) |
| Live caller-to-host-to-caller fulfillment evidence | [delivery proof](hosted-execution-delivery-proof.v1.schema.json) | [delivery-proof-fulfilled.json](examples/hosted-execution-v5/delivery-proof-fulfilled.json) |

Every linked example is **synthetic test data**. No example authorizes deployment or claims that acceptance ran. Negative payload examples and their expected rejection reasons are in [the fixture guide](examples/hosted-execution-v5/README.md).

## Supported invocation and wire shape

The host must publish client support for the existing surface:

```powershell
sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user
```

The updated client discovers the active supported profile before invoking acceptance. It first invokes the existing `read-hosted-execution-profile` capability, verifies its returned text/digest and schema, and selects the declared request route. Discovery completes before the coordinator starts. The profile origin must equal the authenticated CLI origin. Unsupported routing is a typed failure; the client must not fall through to a worker run.

The acceptance input and POST body are exactly:

```json
{}
```

The HTTPS request is:

```http
POST /sfx/v1/hosted-execution/acceptance
Content-Type: application/json
Authorization: Bearer <existing operator session; injected from the secure client session store>
X-SFX-Acceptance-Attempt-Id: <new lowercase UUID>
X-SFX-Hosted-Profile-Digest: sha256:9760b6001d84576090a47a1ac02a4db5d728fdb1aea8cbef66b57376ff152f33

{}
```

Angle-bracket text describes runtime values; it is not literal input. The bearer never enters a JSON body, command argument, source file, trace or evidence artifact. The host normalizes HTTP header names case-insensitively, requires exactly one valid correlation UUID and expected profile digest, and refuses ambiguous duplicate headers. The attempt ID is correlation, not an idempotency or exactly-once claim. No automatic retry or redirect is permitted.

| Value | Authority/source | Check before probes |
| --- | --- | --- |
| Command input / POST body | Caller | Must be `{}`; identity, credentials, endpoint and execution-path members are refused. |
| `attemptId` | Client-generated correlation header | UUID; it grants no authority. |
| `expectedProfileDigest` | Client's verified discovery result | Must equal the active host profile or return `PROFILE_CHANGED`. |
| `caller.kind`, `caller.principalId` | Authenticated ingress | Must resolve to user `565de6d4-ebcd-408b-9359-04d21dc62183`, the pinned `host-acceptance-operator`. |
| `requestExecutionId`, `executionPath` | Actual host request admission | Request execution identity and `request`; never supplied by the body or invented by the evaluator. |
| Probe principal | Authenticated operator and pinned profile | `host-acceptance-operator`, `565de6d4-ebcd-408b-9359-04d21dc62183`; same principal as the initiator. |
| Probe bearer | Invocation-scoped provider memory | The existing authenticated request session; validated against the same pinned operator, never stored or returned. |

The host constructs the **internal context** from those sources. Its complete JSON shape is shown in [trusted-context.json](examples/hosted-execution-v5/trusted-context.json). That document is never a caller-supplied request body. Passing context schema validation is not authorization; the provider must still compare the authenticated caller against its trusted operator binding before releasing any credential.

The pinned operator gate protects initiation and readback. Probes use that same principal and ordinary own-run authorization. This revision removes the separate probe account and stored-session dependency at the owner's direction.

## No additional credential provisioning

Version 5 uses the existing operator session for the coordinator and all probes.
The host does not read `SFX_API_ACCEPTANCE_SESSION` and does not require a dedicated
acceptance account. The ordinary installed CLI login is sufficient.

Declared ingress holds the request bearer outside graph values, binds it to the
host's request UUID, and permits one use by that invocation. It registers the
bearer with observation redaction. The coordinator validates the session and
pinned operator through HTTPS before submitting probes. It never signs in,
stores, renews, revokes or returns a credential. Caller identity in a body cannot
replace the authenticated request context. Readback releases no credential.

## Responses and failures

| Result | JSON data contract | Client exit | Meaning |
| --- | --- | --- | --- |
| HTTP 200, valid `ACCEPTED` receipt | `hosted-execution-acceptance.v1` | 0 | T1–T7 passed; host fulfillment additionally requires the live delivery proof and verified retained evidence. |
| HTTP 200, valid `REJECTED` receipt | `hosted-execution-acceptance.v1` | 2 | Preserve and return the real failed checks. Host work is unfulfilled. |
| Known failure with no receipt | `hosted-execution-invocation-error.v1`, outcome `FAILED` | 1 | Preserve stage, typed code, observed HTTP status and actual identity if available. No receipt is fabricated. |
| Possibly dispatched request whose outcome was not received | Same error contract, outcome `UNKNOWN` | 3 | Keep the original attempt ID; query retained evidence and investigate before an explicit new attempt. A timeout does not cancel the remote work. |

The error's `httpStatus` is the status actually observed; 0 means no HTTP response was available. The host may have returned a typed error or the client may construct one after discovery, transport or validation failure. HTTP success alone never implies acceptance. If deployment identity is established and a check fails, prefer the ordinary REJECTED receipt with typed `EXECUTION_ERROR` checks; the invocation error applies when no receipt can be returned.

The error schema enforces stage/code combinations and forbids UNKNOWN from becoming FAILED or ACCEPTED by relabelling. `requestExecutionId` is null when unavailable. `receipt` is always null and `automaticRetry` is always false. Messages contain no credentials or copied request bodies. Before-authentication failures cannot claim a coordinator execution identity.

The 150 s measurement budget, 195000 ms request delivery bound and 198000 ms answer bound remain unchanged. Client discovery and the subsequent coordinator exchange each have a separate 230000 ms wait bound. A deployment-wide single-coordinator admission prevents two coordinators from consuming both request kernels; a competing attempt returns `ACCEPTANCE_BUSY` promptly and without credential release. Admission ownership is released on every termination path. The host arranges the existing T7 precondition of both workers being available; no consumer reservation mechanism is added.

## Retained evidence and recovery

The host's declared `sfx-api-host-acceptance-record-port.v1` persists attempt identity before probes and exact receipt UTF-8 bytes before the response. A failed record write is explicit and cannot produce fulfilled evidence. Records survive restarts until explicit owner retirement; a lost running attempt becomes UNKNOWN rather than being replayed or declared successful. Credential values and raw request diagnostics are never retained.

The host supplies this second capability through the same supported command surface:

```powershell
sfx-api capability observe read-hosted-execution-acceptance --input '{"attemptId":"11111111-1111-4111-8111-000000000011"}' --input-type json --json --auth user
```

The UUID above is synthetic. Declared dispatch maps the validated input to authenticated `GET /sfx/v1/hosted-execution/acceptance/{attemptId}` on the request path, with no body. Ingress applies the same pinned operator gate. Readback releases no probe credential and starts no probe. Its result is one of the five closed shapes linked above; it does not expose unrelated runs.

`RECEIPT_AVAILABLE` carries `receiptBytesBase64`, `receiptByteLength`, `receiptSha256` and the parsed `receipt`. The verifier strictly decodes Base64, checks the exact byte count/digest, parses JSON with duplicate-key rejection, compares the parsed value, and reconciles attempt, execution and profile identities. The artifact reference in a delivery proof must name this declared readback URL for the same attempt. NOT_FOUND after an uncertain POST means missing retained evidence, not proof of non-execution and not permission for automatic replay.

## Host fulfillment and rollout

The host publishes a compatible profile reader, interface/context bindings, provider programs, persistent record reader/writer, schemas and versioned client. A stale client or mixed profile is refused explicitly. The host reports installed client version/artifact digest and the actual deployed image, bundle, kernel and host-file pins. The client and profile schema must be available before the host claims the new invocation is supported.

To close the work, the host runs the supported command from the real operator session, obtains the receipt through the public HTTPS route, reads it back through the declared reader, verifies the actual probe executions and deployment pins, and retains `hosted-execution-delivery-proof.v1`. All attempt IDs must match; `invocation.requestExecutionId` must equal `evaluator.executionId`; T4 must name its actual payload run; T7's half-open intervals must name its three actual hold runs and justify its concurrency claims.

The proof can say FULFILLED only with an ACCEPTED receipt and verified live delivery/readback. A successfully delivered REJECTED receipt is UNFULFILLED. Fixtures, local diagnostics, an installed route, a JSON-schema pass, or a merely provisioned credential are insufficient. Changes to any covered deployment/profile pin invalidate the prior proof for the new deployment and require a fresh end-to-end execution. The host supplies the evidence; the consumer verifies it and then proves the renderer against those pins.

Local artifact validation is available without making an execution claim:

```powershell
python -B contracts/validate-hosted-execution-receipt.py <receipt.json>
python -B contracts/validate-hosted-execution-receipt.py <read-result.json>
python -B contracts/validate-hosted-execution-receipt.py <delivery-proof.json> --receipt-artifact <receipt.json>
```
