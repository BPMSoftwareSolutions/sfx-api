# Hosted execution: version 5 completion

Version 5 removes the separate acceptance-session prerequisite at the owner's
explicit direction: "This is not apart of my original design. Get it out of here
or make it frictionless." The existing signed-in CLI session initiates acceptance
and owns its probes. No acceptance account, vault entry, credential provisioning,
password helper, account switch or session renewal is added to this workflow.

The profile digest is
`sha256:9760b6001d84576090a47a1ac02a4db5d728fdb1aea8cbef66b57376ff152f33`.
**Version 5 is deployed and accepted live:** all T1-T7 checks passed and the
[verified delivery proof](../docs/hosted-execution-v5-2026-11-04/README.md) is FULFILLED. Version 4 and its rejected
attempts remain [historical evidence](../docs/hosted-execution-v4-2026-11-04/README.md).
Their schemas and profile are retained under `history/hosted-execution-v4/`.

The [joint OV3 completion plan](../docs/ov3-consumer-completion-2026-11-04.md)
connects host acceptance to the original renderer outcome. Host profile version
5 and consumer flight revision 4 are separate artifacts. The consumer agent owns
the C# provider binding and verified HTML publications. The host owns runtime
promises H1-H5, supported CLI invocation and complete live acceptance evidence.

## Invocation and authentication

The supported command remains:

```powershell
sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user
```

It discovers and verifies the exact profile, then invokes the declared POST
request route using the CLI's ordinary session. The pinned operator is
`565de6d4-ebcd-408b-9359-04d21dc62183`. Probe ownership is the same principal;
ordinary own-run authorization applies to probe streams and readback.

Declared ingress retains the authenticated request bearer in provider memory
outside graph values, keyed to the host-generated request execution UUID. Only
that invocation can consume it, once, with a bounded lifetime. Duplicate
Authorization headers cannot establish a probe session. A subsequent request
clears any unused credential. The kernel's observation redactor knows the bearer.
It is never returned, persisted in acceptance evidence, or supplied in a request
body. The coordinator confirms the session and principal through HTTPS before
admitting probes. It never signs in, stores or revokes a session.

The implementation is `authorize > exchange`; acceptance no longer has vault,
reference or vault-open operations. Existing stored vault values are unchanged.

## Completion obligations

1. Publish the profile, schemas, declared provider bindings and installed CLI as
   one compatible release. A stale client or changed profile fails explicitly.
2. Preserve the empty request body, trusted caller and actual request UUID,
   deployment-wide admission lock, bounded execution, and uncertain-outcome
   recovery without automatic replay.
3. Run T1-T7 through the deployed HTTPS API. Preserve typed errors and measured
   failures; do not fabricate observations or probe run IDs.
4. Persist exact receipt bytes before responding. Independently read the named
   attempt and verify its bytes, identities, deployment pins and all checks.
5. Deliver an ACCEPTED receipt and FULFILLED delivery proof from the supported
   installed CLI. Local tests and examples do not establish live fulfillment.
6. Give the consumer the receipt, readback, proof and deployment pins. The
   consumer then executes its approved renderer flight and independently proves
   both original HTML publications.

The [payload specification](hosted-execution-invocation.md) links every schema
and complete example. The [canonical feature](../features/hosted-execution-profile.feature)
defines acceptance behavior. Consumer obligations C1-C4 remain unchanged: declare
the hosted runtime, bound child execution and expose failures, carry pinned
packages, and handle shared temporary-space failures.
