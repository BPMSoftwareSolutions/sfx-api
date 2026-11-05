# Hosted execution version 5: accepted live

**Version 5 is deployed and FULFILLED.** The installed CLI used the owner's
existing user session. All T1-T7 checks passed, the returned receipt is ACCEPTED,
and independent readback verified its exact bytes before the CLI issued the
[delivery proof](delivery-proof.json). No separate acceptance account, vault entry,
credential provisioning, account switch or session renewal was required.

The owner directed removal of the added acceptance-session dependency. Declared
ingress now retains the invoking request's session outside graph values and
binds its one-time consumption to the host-generated request UUID. The
coordinator validates the operator through HTTPS before submitting probes. It
never signs in, stores, renews or revokes a credential. Existing vault entries
were not changed.

## Live evidence

- Attempt: `2693926c-0714-4c75-989d-ded69182e3ef`.
- Request execution: `7374f182-489d-4e94-8404-a6cc8725dca8`.
- [Receipt](receipt.json): ACCEPTED; T1-T7 PASSED; executed at
  `2026-11-04T23:39:42.162Z`.
- [Readback](readback.json): RECEIPT_AVAILABLE; 12,626 exact UTF-8 bytes,
  `sha256:60e6423fcb4dbdf8ded90e1aca002b8ba613335bb972ade214059e9a71c5e15e`.
- [Retained host attempt](https://sfx-api-test.azurewebsites.net/sfx/v1/hosted-execution/acceptance/2693926c-0714-4c75-989d-ded69182e3ef): authenticated readback through the pinned operator.
- Initiator and probe principal: `565de6d4-ebcd-408b-9359-04d21dc62183`.
  Own-run authorization remains in effect.

The exact [discovery](discovery.json), [dispatch](dispatch.json), [attempt](attempt.json)
and [installed-client record](client-installation.json) are retained alongside
those artifacts. The supported command was:

```powershell
sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user
```

## Deployment

[Deployment pins](deployment-pins.json) agree across the completed ACR build,
configured App Service image, verified final image context, actual receipt and
independent readback. [Startup evidence](container-startup.log) records readiness
at `2026-11-04T23:37:43.3363342Z`.

| Artifact | Identity |
| --- | --- |
| imageDigest | `sha256:9b626f660c56a9089fc73f18ca6f270ca44213abc1e2fb2616e8980c7b23d6fa` |
| bundleDigest | `sha256-base64:FXzM/XtVovxt1M0Zu6Fb4e2QrYwbTes1+2tTin0DFwA=` |
| kernelArtifactDigest | `sha256:244e0129254e99752cf81d6df4026191d039dcaa8b8bcffcaff4baed9a74c1af` |
| hostFilesDigest | `sha256:82871ab7745a02d340d135672eb895fe4c4e7d0c76a0b4a0f7176859ebd9c6d7` |
| profileDigest | `sha256:9760b6001d84576090a47a1ac02a4db5d728fdb1aea8cbef66b57376ff152f33` |

Image tag `sfx-api:hosted-v5-a`, ACR run `cab3`. The kernel remains SDA 29355da.
The renderer's third-party packages remain consumer-owned.

The first client attempt during deployment cutover stopped at profile discovery,
before a coordinator POST was dispatched. Its [failure record](pre-dispatch-failure/error.json)
is retained. A fresh reader confirmed version 5 before the successful attempt.
No uncertain coordinator POST was automatically replayed.

## Validation and consumer handoff

26 contract tests (including 19 payload examples and required rejections), 33
native provider checks, 4 Python session-boundary tests and 37 client tests
passed. The provider checks cover single-use request binding, cross-request and
duplicate-header refusal, observation redaction, retained records and process
recovery. The local projected receipt and all three live evidence artifacts
passed full schema and identity validation. Local checks alone were not used to
claim fulfillment; the live proof above establishes it for these deployment pins.

The consumer agent received the exact receipt, independent readback, proof and
deployment pins. Its next work is to independently verify that evidence, record
and review the concrete C# renderer flight, obtain any required exact-digest
owner approval, and fulfill both original HTML objectives. Host acceptance does
not itself claim those consumer publications are complete.
