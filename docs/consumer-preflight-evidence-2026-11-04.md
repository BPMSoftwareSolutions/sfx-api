# Consumer combined preflight: evidence capture failure

Run `6ec9667d-0ed5-45ca-c6a6-a974ae277994` was dispatched once for consumer
engineering source
`sha256:7fc4837412782efa0401c8e031163611c492d8c10a30c1f147830fa436b50fe0`
in preflight mode. Its source combines the guarded compiler patch, 22 large
mapping checks, public capability recompilation and topology verification.

An authenticated state read returned the admitted run ID without a completed
run document; output was absent. At `2026-11-05T01:27:12.212Z`, the raw events
response was READ with `chunks: []` and omitted `lastCursor`. The CLI raised
`EVIDENCE_CURSOR_GAP` because it compared the absent cursor against zero. This
does not demonstrate a missing retained chunk or a successful preflight.

Read-only Azure log download established that the run had already stopped
without retained completion. These lines are from
`LogFiles/2026_11_05_ln0xsdlwk0001BW_default_docker.log`:

```text
2026-11-05T01:23:27.2797825Z [sfx-api kernel] project-api-run-events {"code": "SIDEFX_FAILURE", "message": "Lock request time out period exceeded."}
2026-11-05T01:23:27.2798355Z [sfx-api run 6ec9667d-0ed5-45ca-c6a6-a974ae277994] project-api-run-events answered null
2026-11-05T01:23:27.2959596Z [sfx-api kernel] publish-estate-live-observation {"code": "SIDEFX_FAILURE", "message": "Lock request time out period exceeded."}
2026-11-05T01:23:37.0627895Z [sfx-api run 6ec9667d-0ed5-45ca-c6a6-a974ae277994] its events stopped before its end; it is not completed
```

The local archive is `C:/tmp/sfx-host-run-diagnostics-20261104.zip`. No restart,
redeployment, credential change or resubmission was performed by the host agent.
The consumer's independent SQL activity read
`e2d23cad-40c7-8392-788d-74079a1f5575` found no long-running or blocked request.
Independent reads `cfaed4bd-9416-72fa-eeed-418a05d7b664` and
`60045992-bcd3-9c19-b028-130b114bc871` subsequently confirmed the compiler and
public declaration remained at their preflight baseline digests. The consumer
can prepare a different, shorter repair without assuming the unknown inner
outcome of this run.

`host/serve.py` marks projection broken when its declared bookkeeping capability
returns no valid answers, then withholds completion. This preserves the absence
of proof but leaves the admitted run unreadable as a completed outcome. The
long transaction's declaration locks are a plausible source of contention;
the logs establish the lock timeout, not its exact lock owner.

The consumer agent is keeping the guarded compiler mutation transaction short,
with public declaration recompilation in a separate declared step, and will
verify the already-tested generated mappings after commit. The original
combined run must remain without a claimed success. The host's prior version 5
acceptance remains evidence for its T1-T7 suite, not proof that this later
preflight completed.

## Bounded replacement rehearsal

The different, shortened source
`sha256:98041176a8531788630e1a0649229347b156f477d881105ea581217b0fc51b68`
contains only the compiler baseline guard, exact patch guard, ALTER and body
readback. Run `1b78025a-e8ab-0a36-be25-a104da0ae607` returned its normal retained
receipt with `APPLIED_AND_ROLLED_BACK`. Compiler read
`1d2441f6-fcdb-a9e1-77f0-46a47abfbd2e` confirmed the unchanged baseline afterward.
The previously passed large mapping checks and hosted render/verify evidence are
reused. The repair flight separates public declaration installation from the
compiler transaction; the original failed-capture run was not resubmitted.
