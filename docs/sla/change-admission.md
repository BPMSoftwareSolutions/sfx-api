# Host change admission

**Version:** 1.0, effective 2026-11-07. **Lifecycle owner:** sfx-embody.

sfx-platform's change admission contract and its policy data apply to the host as written:
- `docs/sla/change-admission.md` v1.0;
- `docs/sla/change-admission-policy.v1.json` (sha256 of its bytes: `8f1157b9…1839`).

Both are cited at sfx-platform `2df87d8`, not copied: the policy is sfx-embody's, and a copy here would drift. This
document states only what that contract leaves to the host:
- what counts as a host implementation change;
- what sfx-api supplies to an assessment;
- the candidate on main that no recorded release has carried.

It issues no disposition. Assessments, authority and acceptance stay with the estate and identity, and a local result
is never admission.

## What changes the host

A change is a **host implementation change** when it changes the image a release serves, which is the `imageDigest` of
the host build identity. At `ea4b012`, `tools/prepare-hosted-image.ps1` and `deploy/Dockerfile` build the image from
these inputs:

| Input | In the image as |
| --- | --- |
| `host/` | the facade |
| `deploy/Dockerfile`, `deploy/start.sh`, `deploy/kernel-host.json` | the container and the kernel's boot configuration |
| `sfx-api.config.json` | the facade's settings |
| `authorities/host-bundle/` | the pinned bundle: the manifest and every capability document |
| `providers/host-provider-authority.json` | the provider authority that pins the bundle |
| `providers/hosted/` | `Sfx.HostedProviders.dll` (built from its sources), `validate.py`, `requirements.txt` |
| `providers/content/` | `package.py` and `requirements.txt`, with the Python dependencies the Dockerfile installs from it |
| `contracts/*.json`, `contracts/*.py` | the copied contracts and the receipt validator |
| the admitted kernel directory | the kernel, by digest |
| `tools/build-content-release.py` | projects the content declarations into the bundle during the build, so its output is in the image |
| `tools/build-hosted-release.py` | writes bundle documents and the manifest during the build, so its output is in the image |

`providers/content/` and `tools/build-content-release.py` entered in `ea4b012`.

**The pinned bundle is host implementation.** The host's declarations ship only inside the image, "from this repo, in
the one deploy" ([features/README.md](../../features/README.md)). A change to a bundle document is therefore a host
build change. Whenever a covered accepted product change requires one, it counts as `host` in that change's
`requiredImplementationChanges`.

Two rules converge here:
- The product contract requires the host to "resolve the declared contract without host branches interpreting domain
  fields or selecting business workflows".
- The owner's direction keeps the estate for the consumer.

Domain meaning in the bundle would violate the boundary. Every later change to that meaning would also consume
change-independence allowance. The bundle holds the host's own semantics: the frontdoor, sessions, runs, streams, the
channel, and the host's acceptance of itself. That last sentence is my reading of the two rules together; no
scenario states it yet.

**Supporting work** (sfx-platform admission rule 5) delivers no product behaviour, so it is outside the change unit,
but only with a scope receipt fixed before classification. In this repo that covers:
- `features/`: a feature states behaviour and delivers none;
- the records under `docs/`, including this directory;
- tools that put nothing in the image.

A change that mixes supporting work and product behaviour keeps the product change in scope.

## The six rules, applied to the host

| Platform rule | What it means here |
| --- | --- |
| 1. Boundary integrity precedes budget | No allowance or exception lets the facade, a provider or a bundle document hold domain routing, lifecycle, eligibility, recovery or fulfillment. Such meaning moves to the estate. |
| 2. Qualify against supported primitives | A new port, directive verb or facade behaviour is an extension. It is qualified against [host-primitive-inventory.v1.json](host-primitive-inventory.v1.json) by that inventory's five steps. A new capability composed from existing primitives is not an extension. |
| 3. Assign delivery ownership | The content delivery host is sfx-api's ([content-delivery-boundary.v1][cdb]). Its reuse gate binds before a second mechanism is kept: "read existing published delivery and generated-page contracts before retaining or creating a second mechanism". |
| 4. Count consistently | A feature, an ordinary fix, an invariant or security repair, a primitive extension and a protocol revision all count as `implementation-change` when they change the host build for a covered accepted product change. The 2026-11-05 sign-in repair (`ccb82ed`) is one, if its product change is in scope. |
| 5. Fix scope before classification | The scope receipt names the candidate's files and behaviours before its outcome is known. Units are not split afterwards. |
| 6. Only relevant obligations govern | A candidate's acceptance names its affected surfaces first. An unrelated historical gap, such as the unverified latency samples, does not block it. |

## What sfx-api supplies to an assessment

| Assessment fact (policy) | sfx-api's evidence |
| --- | --- |
| `integration` | The pinned commit of the candidate and of main. This repo has no comparison collector (see below). |
| `ownership` | The owning feature and the binding readback of each port the candidate adds or changes. |
| `primitives` | The candidate's change against the host primitive inventory at the target build, with a qualification receipt for any extension. |
| `evidence` | Acceptance of the candidate's own scenarios on the governed host, recorded under [the measurement contract](measurement-contract.md). |
| `release` | The candidate's affected surfaces against open `release-integrity` responses ([host-sla.md §5](host-sla.md#5-allowance-and-response)). |
| `implementation` | `consumer-host-kernel` when the image changes for the product behaviour, with the before and after `imageDigest`. |

sfx-platform's Git comparison collector (`tools/reconcile/reconcile.mjs`) is not adopted. It is that repository's tool,
and here a comparison used as evidence must be a declared capability (host-sla.md §4 rule 10). Until one exists, the
`integration` fact for an sfx-api candidate is the pinned commits alone.

## The candidate on main, 2026-11-07

Main is at `ea4b012` ("Serve owned HTML packages and explicit publication through declared API"), committed on
2026-11-06 at 00:01 UTC, before this agreement took effect. The latest release in the record is `ccb82ed`
([signin-outage-2026-11-05](../signin-outage-2026-11-05.md)), and no deploy record names `ea4b012`. Being on main does
not admit it: its first release to the governed site is the change these rules govern. The rows below are facts, not
dispositions, and nothing in this directory touches the candidate.

| Candidate | Recorded state | What admission needs first |
| --- | --- | --- |
| Content delivery host, `ea4b012` | **Added:** 17 bundle capability documents (`publish-api-content`, `update-` and `withdraw-api-content-publication`, `read-api-published-content`, `resolve-api-published-content-path` and twelve other content reads and resolves), which brings the manifest to 45. Also added: 11 features, `providers/content/`, `providers/hosted/ContentProjection.cs`, `providers/hosted/PublicationProjection.cs`, `sej/content-api.v1.json` and `tools/build-content-release.py`. The provider authority adds 7 ports, none of them in the host primitive inventory: `sfx-api-content-selection-port.v1`, `sfx-api-content-receipts-port.v1`, `sfx-api-content-retained-reference-port.v1`, `sfx-api-content-projection-port.v1`, `sfx-api-content-package-port.v1`, `sfx-api-publication-selection-port.v1` and `sfx-api-publication-answer-port.v1`. All 11 features carry `@approved:2026-11-05`, and all 20 of their scenarios are `@status:unchecked`. **Changed in the same commit:** `serve-api-request` routes the content operations, and `HostedProviders.csproj` compiles the two projections. `sej/resolve-api-request.sej.json` changes the permission for a request with no caller: it was the literal `false`, and it is now whether the operation's `callers` include `anonymous`. `providers/host-acceptance.py`, and its copy in `accept-hosted-execution-profile`'s observation program, add the two content files to the host-files digest. `deploy/Dockerfile` refuses a `KERNEL_DIGEST` that is not 64 hexadecimal characters, which is not content. | A scope receipt, which also says whether the Dockerfile check is in the unit (rule 5). A boundary assessment of each capability against the boundary's four operations: publication eligibility and state belong to sfx-embody, and `resolve-public-address` allows "no publishing, withdrawal, repair or inferred lifecycle transition". The same assessment covers the change for requests with no caller (rule 1). A record that the reuse gate was satisfied. Qualification of the 7 new ports. Acceptance of the 20 scenarios on the governed host. The promotion gate's receipts. If its product change is in scope, it is classified `implementation-change` with `host`. |

For its own tree, sfx-platform assessed the earlier `deploy/content` gateway as "`OBLIGATION_REQUIRED`; sfx-api owns
reuse qualification and published host binding under the specified boundary; estate policy must be extracted before
promotion". That is sfx-platform's assessment of its own tree. It is not a disposition of this candidate.

[cdb]: https://github.com/BPMSoftwareSolutions/sfx-platform/blob/2df87d8702ec334b8962bb299cc637bddf3b0f03/docs/sla/content-delivery-boundary.v1.json
