# Hosted execution contract for host review

This consolidates the consumer's three requested corrections into the existing draft. The host can review and implement this revision as one change. No capability has been installed and no deployment acceptance is claimed here.

The profile remains version 1 because it has not been adopted. Its exact UTF-8/LF bytes now have digest `sha256:7c555f52f36a6060453451a79092a2ecc34a653fcb0c4b871fe991305b4da804`. This replaces the unadopted draft with digest `sha256:b387ad0c7321c6a1e4bbf063b54009ed3e917f8609de884f811d0eca01390efd`. The receipt schema and canonical feature pin the new digest. Git attributes preserve JSON line endings across Windows and Linux checkouts.

## The agreed execution boundary

| Concern | Concrete contract |
| --- | --- |
| Coordinator | The host interface declares authenticated `POST /sfx/v1/hosted-execution/acceptance` on the request path, bound to `accept-hosted-execution-profile`. It holds zero worker slots and uses the existing request deadline. |
| Worker probes | `probe-hosted-execution` supplies the ordinary checks and the three T7 holds. `probe-hosted-execution-language-refusal` isolates the Python-only T3 binding from every other closure. Both are private acceptance fixtures. |
| Probe admission | A declared `sfx-api-host-http-request-port.v1` program submits the probes through the deployed HTTPS `POST /sfx/v1/runs` route. That lets the facade consume the admission directive and queue them. |
| T4 readback | The same HTTP provider fetches the completed T4 run's `/output` through the public endpoint without redirects. It decodes the JSON string at `/output/payload`, then counts and hashes its UTF-8 bytes. A direct call to `serve-http-request` cannot supply this evidence. |
| T7 concurrency | In a measurement window with both workers available, the request coordinator submits three 5-second holds without waiting for completion. It retains their execution intervals and computes overlap from those intervals, excluding its own execution. |
| Failure before measurement | A check returns `kind: EXECUTION_ERROR`, `status: FAILED`, a real attempt identity and a typed error. It supplies only actual admitted run IDs and no invented observations. The receipt is `REJECTED`. |
| Complete measurement | `kind: OBSERVED` retains the existing typed observations. Every `PASSED` check must still meet all schema thresholds. A measured mismatch is `FAILED` with a finding. |

The result schema accepts both failure forms for every check. A precondition or admission failure may have no worker run ID. Execution, collection and verification errors require an admitted run ID. If deployment identity cannot be established, the capability fails without issuing an acceptance receipt.

## Host implementation scope

1. Implement the profile reader and the request-path acceptance entry in the host's declared bundle/interface.
2. Declare the child-process and HTTPS providers through the profile schema boundary, using the existing authentication mechanism. Retain the isolated Python-only negative-control provider.
3. Declare the private probe capabilities and the coordinator. T6 reads effective configuration; T7 establishes execution concurrency. T3's expected failed run is a passing refusal observation.
4. Derive measurements and dispositions from the actual executions. Verify each cited admission and require terminal evidence for passing checks, including capability, inputs and deployment identity. Failed checks retain known admission and attempt evidence when execution or collection could not finish. Match T4's URL to its payload run and T7's interval IDs to its three hold runs. Use half-open intervals `[startedAt, endedAt)` for overlap.
5. Parse receipts with duplicate-key rejection before Draft 2020-12 validation, with date-time format assertions enabled. Verify the deployer's image identity and the evaluator's bundle, kernel and host-file identities against the tested deployment.
6. Deploy the host bundle and run the declared checks against `sfx-api-test`. Produce the first real receipt. The consumer then proves the renderer and both objectives against that receipt's deployment and profile pins.

The schemas enforce structure, complete check coverage and pass thresholds. The declared runtime supplies and verifies evidence provenance, cross-field run references and interval calculations. Local synthetic fixtures do not attest to the deployment.

## Local regression checks

```powershell
python -m pip install -r contracts/tests/requirements.txt
python -B -m unittest discover -s contracts/tests -v
```

The suite validates both schemas and the profile, checks the exact profile pin and Unicode payload digest, repeats the original negative cases, rejects in-process T4 and worker-occupied T7 claims, and exercises early failures for all seven checks. It also refuses duplicate keys and malformed timestamps. These are authoring checks only; the deployed implementation remains declared capability work owned by the host.

Files for review are [the feature](../features/hosted-execution-profile.feature), [the profile](sfx-api-hosted-csharp.v1.profile.json), [the profile schema](hosted-execution-profile.v1.schema.json), [the receipt schema](hosted-execution-acceptance.v1.schema.json), and [the regression suite](tests/test_hosted_execution_contract.py).

## Host review, 2026-11-04

The host accepts this revision, with four amendments. They give the profile digest
`sha256:7c555f52f36a6060453451a79092a2ecc34a653fcb0c4b871fe991305b4da804`, which the receipt schema and the feature
pin.

| Amendment | Why | Where |
| --- | --- | --- |
| Only the interface's machine caller may invoke the coordinator (`admittedCallers: ["machine"]`) | The probes act with the machine caller's authority, which sees all runs. A user session must not start them. | profile `acceptance.coordinator`, feature |
| The probes authenticate as the machine caller with `host-machine-credential`, released at a declared credential pointer | "The existing authentication mechanism" names the interface's `callers.machine`. The credential reaches no testimony, observation or receipt. | profile `acceptance.coordinator.probeAuthority` |
| The request path declares `kernels: 2`, and the coordinator requires at least 2; T6 checks it | The coordinator holds one request kernel while its own HTTPS calls need another. With one, its calls would be refused `REQUEST_KERNEL_BUSY` after 30 s. | profile `executionPaths.request`, `acceptance.coordinator.requestKernelsRequired`, receipt T6 |
| The coordinator has a 150 s budget, and waits on probes by reading each run's event stream to its end frame | It must issue its receipt before the 195 s delivery bound ends it. Declared programs have no loop or sleep, so a stream read is how it waits. | profile `acceptance.coordinator.budgetMs` and `probeCompletion`, feature |

The regression suite adds `test_coordinator_authority_and_capacity`, and all 11 tests pass. `git diff --check` is
clean. Nothing was deployed.
