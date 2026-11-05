# Synthetic payload examples

Every file here is authoring/test data. UUIDs beginning `11111111`, the `synthetic-fixture-only` client, and repeated-`a` deployment digests are deliberate fixtures. These documents do not show that the deployed host passed acceptance. Do not submit the context or receipt examples as if they were real evidence.

The current profile digest is real and keeps fixtures aligned with the contract candidate. The full shapes and their source/authority boundaries are described in [the protocol specification](../../hosted-execution-invocation.md).

Valid examples cover the empty request, trusted internal context, ACCEPTED and REJECTED receipts, known and uncertain invocation errors, every readback state, and the complete delivery proof. `receipt-accepted.json` is deliberately preserved byte-for-byte: the example delivery proof and Base64 readback record hash those exact UTF-8 bytes.

| Negative file | Required rejection |
| --- | --- |
| `invalid-request-identity.json` | The external body cannot supply identity. |
| `invalid-context-missing-attempt.json` | The trusted internal context must include its correlation ID. |
| `invalid-proof-swapped-attempt.json` | The proof and exchange cannot refer to different attempts. |
| `invalid-proof-no-readback.json` | Delivery alone cannot substitute for verified retained evidence. |
| `invalid-read-result-size.json` | The declared byte length must match decoded receipt bytes. |

`test_hosted_execution_invocation.py` validates the checked-in examples against their schemas and semantic checks, and requires the negative cases to be rejected. It also exercises omitted obligations, wrong identities, redirects, worker dispatch, password/account-switch regressions, uncertain outcomes, mismatched references and false concurrency arithmetic.
