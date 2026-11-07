# Canonical features of sfx-api

Proposed for the owner's review, 2026-11-02. Seventeen files replaced the twelve feature files that were here at
`a57ebba`. On 2026-11-03 the declared-read provider's feature became a provider capability's,
answer-host-declared-read.feature. Five more were added for the host's other provider capabilities, eleven for the
capabilities the ingress and the frontdoor invoke that had none, and one for the bundle-read provider. Those eighteen follow the owner's example
(`.tmp/tmp_data.txt`): each file carries its own status tags and terms, and each scenario names the entry capability and
every provider it invokes.

What this is: the behaviour of the sfx-api host as Gherkin, with one canonical feature per capability the host
declares or needs, its provider capabilities included. The facade (`host/serve.py` with `deploy/`) and the container's
vault each get one too. Each behaviour is stated once. Where the host does something different today, the scenario
states what it must do. Its status says whether that is built, and a finding tag says how today's host departs from it.

The features live in this repo, not in the estate. The host's own behaviour is not part of the estate it serves.

## The owner's direction

Given on 2026-11-02 in the session that wrote these files. It is not yet retained anywhere else.

1. "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
   while everything else is declared up to the profile schema boundary via SEJ."
2. "The problem I have is that not all the behavior is clearly canonicalized in .feature files. That means we most
   likely have hidden authority, fallbacks, and misaligned scenarios. We need all the behavior accounted for in
   .feature files."
3. "I think the smart thing to do is to not make the serve.py apart of the estate. We don't circular hosting. The
   estate is for the consumer so that means the consumer can own the host in its estate. However, we do have the
   ability to declare the capabilities in SEJ (semantic executable JSON), and keep them in this repo. The SEJ can be
   resolved by the kernel without being apart of the estate."
4. "The features need to be canonicalized and written up like this."

Given on 2026-11-03:

5. "providers are declared capabilities as well."
6. "You'll need to create feature files for the capability providers because they are capabilities as well with
   scenarios"
7. "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary."
8. "that's why I gave you this ... example to follow accurately."
9. "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
   strategies"

Approved on 2026-11-01 (estate-live-observation-declared.feature): "The hosting facade holds connections and the
channel's buffer and does what the declared capabilities answer; it decides nothing itself."

Approved to build on 2026-11-03: the owner committed these features in `4826b9f` and, given the plan to build on them,
said "Let's proceed and get this work done." The same day, the host's declarations were settled as never declared into
the estate: "The host's declarations shouldn't go into the estate at all. They ship inside the new image, from this
repo, in the one deploy", answered "Okay, that's better." The provider's feature, now answer-host-declared-read.feature,
was corrected to that.

## Tags

Status, one per scenario:

| Tag | Meaning |
| --- | --- |
| `@status:proven` | ran on sfx-api-test or against the estate, and the run is cited |
| `@status:probed` | ran on its own against the estate or sfx-api-test; README.md, Verified, records it without a run id |
| `@status:installed` | the host or its declarations do this today. Read from `host/serve.py`, `deploy/` or `declarations/` at `a57ebba`, or from SDA at `93a7a56`, not from a run |
| `@status:unchecked` | showing it needs a run, and this repo cites none |
| `@status:not-built` | the owner's direction or an approved scenario requires it, and nothing implements it yet |

Approval:

| Tag | Meaning |
| --- | --- |
| `@approved:2026-11-01` | the owner approved the scenario on that date. Its comment names the feature it came from, and its steps keep their exact words |
| `@paused:2026-11-01` | the owner paused it. Nothing in it is built or accepted until the owner resumes it |
| no approval tag | proposed for the owner's review in this canonicalization |

`@deferred` and `@phase-2` keep the meaning they had in estate-live-observation.feature. The `@decided` scenarios of
estate-live-observation-declared.feature carry `@approved:2026-11-01`, and their comments say they were decided.

Findings, where today's host departs from the scenario:

| Tag | Meaning |
| --- | --- |
| `@finding:hidden-authority` | the host decides it in code, in host data the code interprets, or by its platform's default |
| `@finding:fallback` | the host recovers silently, retries, or puts a default in place of an answer |
| `@finding:misaligned` | an approved scenario or the owner's direction says otherwise, or it was built against a feature that is not approved |

Dependencies:

| Tag | Meaning |
| --- | --- |
| `@capability:<id>` | the entry capability under test. On a Feature it applies to every scenario |
| `@component:<id>` | the part of the host under test, where that part is not a capability |
| `@provider:<id>` | one required provider capability, case for case, by the identity its binding declares: a capability a step invokes through `generic-capability-invocation.v1`, a platform capability a port binds (such as `sfx-api-ingress-resolve-port.v1`), or a capability a directive has the facade invoke |
| `@binding:<id>` | a provider module the capability's declaration binds to a port, by its `providerId` (2026-11-02 features only) |
| `@issue:<n>` | the sfx-api issue the feature answers |
| `@slo:<id>` | the service level the scenario states, by its id in "Service levels" below |

In the six provider features of 2026-11-03, as in the owner's example, `@capability` and `@provider` are on each
scenario. Each provider's ids were read from the estate's compiled declarations (run `4d1c2e4f`). In the features of
2026-11-02 they are still on the Feature, as `declarations/` names them, and were not narrowed to the scenarios whose
runs invoke them.

## Service levels

Each feature calls out the service levels of what it covers, as scenarios tagged `@slo:<id>`, so that a later change
cannot lose a performance strategy without failing one.

| Term | Meaning |
| --- | --- |
| SLI | service level indicator: what is measured, where, and how |
| SLO | service level objective: the target an SLI must meet |
| SLA | service level agreement: a bound the API commits to its callers. Here, the bound App Service puts on every request and the answer the API gives at it |
| baseline | the measurement a target was set from |

Every target is set from the record. Each holds what a measurement showed after a performance change, and its baseline
is cited. A target with no measurement behind it is marked proposed and is the owner's to confirm.

The performance strategies the targets keep:

| Strategy | What it bought | Evidence | Kept by |
| --- | --- | --- | --- |
| Resident kernels, started before the facade listens and serving one envelope per line | warm server time p50 from 4.74 s to 0.88 s, p95 from 7.00 s to 3.35 s | docs/azure-test-2026-10-31.md (image `dbe0814f`, a kernel per request, then `f32450fa`) | host-facade |
| The declaration cache per declared generation (SDA `3296bc1`, the estate's `declaration_generation`) | a warm envelope resolves its 15 definitions with no read: 0.3 to 20 ms, where it took 2.8 to 3.0 s | README.md, Verified (WSL, kernel `39881693`) | serve-api-request, answer-host-declared-read |
| Run workers apart from the request kernel | a request is answered while a run executes | README.md, Verified (the facade against a stand-in kernel, 22 checks) | host-facade, admit-api-run-live |
| Shared session rechecks | one recheck per interval serves every stream of a session: 3 rechecks, not 6 | README.md, Verified (stand-in) | check-api-session |
| Bounded channel batches and retention | a publish carries at most 200 events or 1 MiB; replay holds at most 20000 frames or 32 MiB | declarations/25 (today's values in sfx-api.config.json) | publish-, subscribe-estate-live-observation |
| The trace in bounded chunks | a run's trace is retained in chunks of at most 2000 events or 524288 bytes | run `f8a01553`: 4 chunks to cursor 43 (README.md, Verified) | append-api-run-trace, sfx-api-run-trace-encode |

The objectives, their targets, baselines and the scenarios that state them are in
[docs/sla/slo-catalogue.json](../docs/sla/slo-catalogue.json), under the host's service level agreement
([docs/sla/host-sla.md](../docs/sla/host-sla.md)). What the retained record supports for each is in
[host-sla.md §3.3](../docs/sla/host-sla.md#33-what-the-record-shows-today). A scenario's `@status:proven` is not attainment:
only qualified observations in [docs/sla/ledger/](../docs/sla/ledger/) are.

Performance debt the record names, with no target yet (README.md, Next 5): the frontdoor's two SQL reads each open the
vault and a connection; each kernel's second request refreshes once more than it needs to; the declared read cache is
not served.

## Terms

| Term | Meaning |
| --- | --- |
| facade | `host/serve.py` with `deploy/start.sh`. It holds connections, starts and supervises kernels, writes what they answer and fans in what they write |
| kernel | a resident `KernelEntry` process the facade starts. It takes `sfx-command-delivery.v1` envelopes |
| envelope | one delivery to a kernel: a request subject, its input and, for a sampled run, its observation member |
| directive | an answer of content type `application/vnd.sfx.host-directive+json` that tells the facade what to do: execute-run, stream-run, stream-estate or respond |
| run | an execution admitted by admit-api-run-live and executed by a run worker |
| run event | one entry of a run's events. A run stream sends it, the trace retains it and the channel publishes it |
| channel | the estate live observation channel at `GET /events` and `GET /sfx/v1/estate-execution/stream` |
| frame | one server-sent event the facade writes unchanged |
| position | a frame's seq on the channel, counting from 1 in each channel instance |
| run window | the positions of one run on the channel, as publish-estate-live-observation answers them |
| bookkeeping | the capabilities the facade executes around runs and streams: session rechecks, trace retention, completion, fact capture, and the channel's own publish, select and subscribe |
| host's own authority | the declarations of this repo's capabilities and the API interface |
| provider capability | a declared capability that a step of another capability binds; it is declared up to the profile schema boundary, its program in a DEPENDENCY, one per runtime language |
| pinned bundle | the host's own declarations in SEJ, kept in this repo and pinned by the digest of their manifest |
| estate | the consumer's database of declarations and data. The host reaches it for the consumer's data and the consumer's capabilities |

## The features

| Feature | Under test | Scenarios | Approved | Paused | Proven | Probed | Installed | Not built | Unchecked |
| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: |
| [host-facade](host-facade.feature) | the facade | 37 | 2 | | | 2 | 16 | 19 | |
| [read-api-host-configuration](read-api-host-configuration.feature) | proposed capability | 5 | 1 | | | | 1 | 4 | |
| [answer-host-declared-read](answer-host-declared-read.feature) | proposed provider capability | 25 | | | | 1 | 3 | 21 | |
| [sfx-api-host-bundle-read](sfx-api-host-bundle-read.feature) | proposed provider capability | 8 | | | | | | 8 | |
| [sfx-api-ingress-resolve](sfx-api-ingress-resolve.feature) | provider capability | 18 | | | 1 | 8 | 5 | 4 | |
| [sfx-api-ingress-compose](sfx-api-ingress-compose.feature) | provider capability | 9 | | | 1 | 1 | 4 | 3 | |
| [sfx-api-run-trace-encode](sfx-api-run-trace-encode.feature) | provider capability | 8 | | | 2 | 1 | 1 | 4 | |
| [sfx-identity-login-open](sfx-identity-login-open.feature) | provider capability | 14 | | | | 2 | 8 | 4 | |
| [sfx-identity-login-derive](sfx-identity-login-derive.feature) | provider capability | 7 | | | 1 | | 3 | 3 | |
| [serve-http-request](serve-http-request.feature) | serve-http-request | 6 | | | 2 | 2 | 1 | 1 | |
| [resolve-http-request](resolve-http-request.feature) | resolve-http-request | 3 | | | | 1 | 1 | 1 | |
| [serve-api-request](serve-api-request.feature) | serve-api-request | 4 | 1 | | 1 | 1 | 1 | 1 | |
| [answer-api-response](answer-api-response.feature) | answer-api-response | 3 | | | | 1 | 2 | | |
| [open-api-session](open-api-session.feature) | open-api-session | 6 | | | | 1 | 3 | 2 | |
| [verify-password-derivation](verify-password-derivation.feature) | verify-password-derivation | 4 | | | 1 | | 2 | 1 | |
| [read-api-session](read-api-session.feature) | read-api-session | 3 | | | | 1 | 1 | 1 | |
| [revoke-api-session](revoke-api-session.feature) | revoke-api-session | 6 | | | | 1 | 3 | 2 | |
| [read-api-estate-scopes](read-api-estate-scopes.feature) | read-api-estate-scopes | 3 | | | | | 2 | 1 | |
| [read-run-state](read-run-state.feature) | read-run-state | 5 | | | | 1 | 2 | 2 | |
| [read-run-output](read-run-output.feature) | read-run-output | 5 | | | 1 | | 2 | 2 | |
| [read-run-graphs](read-run-graphs.feature) | read-run-graphs | 5 | | | | | 3 | 2 | |
| [admit-api-run-live](admit-api-run-live.feature) | admit-api-run-live | 7 | 1 | | | | 3 | 4 | |
| [project-api-run-events](project-api-run-events.feature) | proposed capability | 12 | 4 | | | | 4 | 7 | 1 |
| [open-api-run-stream](open-api-run-stream.feature) | open-api-run-stream | 7 | | | | 1 | 1 | 5 | |
| [check-api-session](check-api-session.feature) | check-api-session | 4 | | | | 1 | 2 | 1 | |
| [complete-api-run](complete-api-run.feature) | complete-api-run | 7 | 2 | | | | 2 | 5 | |
| [append-api-run-trace](append-api-run-trace.feature) | append-api-run-trace | 3 | | | 1 | | 2 | | |
| [publish-estate-live-observation](publish-estate-live-observation.feature) | publish-estate-live-observation | 23 | 14 | 5 | | | 8 | 10 | 5 |
| [select-estate-live-observation](select-estate-live-observation.feature) | select-estate-live-observation | 4 | 2 | | | | 2 | 2 | |
| [subscribe-estate-live-observation](subscribe-estate-live-observation.feature) | subscribe-estate-live-observation | 25 | 14 | | | | 18 | 3 | 4 |
| [capture-estate-live-observation-facts](capture-estate-live-observation-facts.feature) | capture-estate-live-observation-facts | 2 | 2 | | | | | 2 | |
| [read-estate-drawing-changes](read-estate-drawing-changes.feature) | read-estate-drawing-changes | 14 | | | | | 7 | 2 | 5 |
| [capture-estate-live-observation](capture-estate-live-observation.feature) | capture-estate-live-observation | 13 | 2 | | | | 1 | 3 | 9 |
| [durable-credential-vault](durable-credential-vault.feature) | the container's vault | 4 | 4 | | | | 2 | | 2 |
| **Total** | | **309** | **49** | **5** | **11** | **26** | **116** | **130** | **26** |

Findings: 25 hidden authority, 15 fallbacks and 29 misaligned.

Proposed capabilities these features name:
- `read-api-host-configuration`: the facade's declared settings, read once at start (declarations/25);
- `project-api-run-events`: the run event shape (declarations/26);
- `answer-host-declared-read`: the host's declared-read provider, declared in SEJ in the host's bundle and bound to
  `sda-kernel-declared-read-port.v1` (answer-host-declared-read.feature). Not declared yet.
- `sfx-api-host-bundle-read`: the provider that reads a bundle document only under the digest the manifest names
  (sfx-api-host-bundle-read.feature). Not declared yet.

The five provider capabilities of 2026-11-03 are declared today: their programs are this repo's `providers/`, and the
estate holds each as a PROVIDER on its DEPENDENCY definition.

## The declarations

Authored on 2026-11-02 to align with these features. They are files in this repo only:
- none is declared into the estate, now or later: each goes into the host's bundle as its graph source, in SEJ
  (answer-host-declared-read.feature), and none has been run;
- each `config` line was checked only to parse as JSON;
- the facade does not follow them yet, so every scenario they serve keeps its status;
- they go out with the facade change, the provider, the bundle and the pin, in one deploy (answer-host-declared-read.feature).

| Declaration | Feature | What it now declares |
| --- | --- | --- |
| [25-read-api-host-configuration](../declarations/25-read-api-host-configuration.dsl) (new) | read-api-host-configuration | every setting of the outline, with today's values; a 2 s request wait; 64 waiting runs (a proposed number); the busy, queue-full and delivery-failure responses in full; the kernel's queue bounds as null, so its defaults hold |
| [26-project-api-run-events](../declarations/26-project-api-run-events.dsl) (new) | project-api-run-events | each run event and its run stream frame; the lifecycle events; the run's outcome on run.exited; the malformed and cut observations; maxEvents; the run stream's end frame |
| [11-admit-api-run-live](../declarations/11-admit-api-run-live.dsl) | admit-api-run-live | the run's whole plan: envelope, events, trace, completion and facts, each with whether it is published; the 202 in full |
| [12-open-api-run-stream](../declarations/12-open-api-run-stream.dsl) | open-api-run-stream, check-api-session | the starting cursor from after or Last-Event-ID; the head, opening, keep-alive, session-end and end frames; the shared recheck |
| [13-complete-api-run](../declarations/13-complete-api-run.dsl) | complete-api-run | what the run store keeps, composed from run.exited and the delivery's answer |
| [19-publish-estate-live-observation](../declarations/19-publish-estate-live-observation.dsl) | publish-, select-estate-live-observation, read-estate-drawing-changes | the window each frame belongs to; a drawing change's recordedAt from its receipt |
| [21-subscribe-estate-live-observation](../declarations/21-subscribe-estate-live-observation.dsl) | subscribe-estate-live-observation, check-api-session | the head with {instance}; the cursor from since, the selection or Last-Event-ID; a cursor beyond the latest position; the shared recheck |
| [23-read-estate-drawing-changes](../declarations/23-read-estate-drawing-changes.dsl) | read-estate-drawing-changes | each change as the channel event the facade appends |
| [27-serve-api-request](../declarations/27-serve-api-request.dsl) (new) and [sej/serve-api-request.sej.json](../sej/serve-api-request.sej.json) | serve-api-request | the interface carried in the frontdoor's own declaration (serve-carry-interface), with the Last-Event-ID bindings; no interface read |
| [providers/sfx-api-ingress.dependency.json](../providers/sfx-api-ingress.dependency.json) | open-api-run-stream, subscribe-estate-live-observation | resolve-request returns headers.last-event-id, as it returns idempotency-key |
| declarations/17 and 18 (removed) | subscribe-estate-live-observation | the superseded open-api-estate-stream and project-api-estate-events are out of the host's declarations; their estate rows remain |

Every directive is `sfx-api-host-directive.v1`, so the facade can refuse any other. What the facade does with each:

| Directive | From | It carries out |
| --- | --- | --- |
| execute-run | admit-api-run-live | write `respond.raw` and close the connection; queue `run`; execute `run.envelope`; hand what it observes to `run.events`; retain the trace through `run.trace`; complete through `run.completion`; capture through `run.facts`; publish only what is marked published |
| respond | admit-api-run-live | write `respond.raw` and close the connection |
| stream-run | open-api-run-stream | write `stream.head` and `stream.open`; start after `after`; write each event's frame from the projection; write `stream.keepalive` while quiet; write the projection's end frame, or `stream.end` for a run it does not hold; write `stream.sessionEnded`, with the last cursor in place of `{cursor}`, when the session ends |
| stream-estate | subscribe-estate-live-observation | write `head` with the channel instance in place of `{instance}`; replay after `after`, or every retained frame when `after` is beyond the latest position; write `frames` as declared; follow `select`; end at `bound` or at the session's end |

Not declared, and why:
- **Which requests are published, per operation.** Requests stay unpublished (`channel.requests.published` false). Publishing them per operation waits on switching requests back on (publish-estate-live-observation.feature).
- **An ended run's replay from the run store.** The trace is brotli-compressed, and the DEPENDENCY `sfx-api-run-trace` has only `encode-chunk`. A decode program must be declared first. Until then the facade keeps 64 ended runs, as declared.
- **A run the host lost, completed at start.** Waits on sfx-dal (below).
- **A scalar output stored.** Waits on sfx-dal (below).

The frontdoor's live DSL, with its identify stage, was declared without being committed. declarations/27 is rebuilt from declarations/03 and README.md's stage list. It is compared with the live declaration before its graph source goes into the bundle.

## Where the earlier features went

| Earlier file at `a57ebba` | It was | Now in |
| --- | --- | --- |
| estate-live-observation.feature | approved 2026-11-01 | publish-, subscribe-estate-live-observation, complete-api-run, capture-estate-live-observation-facts |
| estate-live-observation-declared.feature | approved 2026-11-01 | publish-, select-, subscribe-estate-live-observation, complete-api-run, capture-estate-live-observation-facts, serve-api-request, capture-estate-live-observation |
| estate-live-observation-kernel-sampling.feature | approved 2026-11-01 | host-facade, admit-api-run-live, project-api-run-events, read-api-host-configuration |
| durable-credential-vault.feature | approved 2026-11-01 | durable-credential-vault |
| estate-live-observation-failures.feature | paused 2026-11-01 | publish-estate-live-observation |
| estate-live-observation-acceptance.feature | draft | capture-estate-live-observation |
| estate-live-observation-bounded-subscription.feature | draft | subscribe-estate-live-observation |
| estate-drawing-change.feature | draft | read-estate-drawing-changes |
| hosting-facade.feature | record, uncommitted | host-facade, read-api-host-configuration |
| api-runs-hosted.feature | record, uncommitted | admit-api-run-live, project-api-run-events, open-api-run-stream, check-api-session, complete-api-run, append-api-run-trace, host-facade |
| estate-live-observation-hosted.feature | record, uncommitted | publish-, select-, subscribe-estate-live-observation, capture-estate-live-observation-facts, read-estate-drawing-changes |
| host-declared-read-provider.feature | draft, uncommitted | answer-host-declared-read |

Every approved, paused and draft scenario is in exactly one canonical feature. The three records described what the host
did. Their scenarios now say what it must do, and the code they cited is in the comments.

## Not yet accounted for

These are declared in this repo, or have their SEJ here, but no canonical feature states their behaviour yet:
- serve-api-request's stages (declarations/27 and sej/serve-api-request.sej.json), apart from its interface, the legacy
  output path and its service levels;
- admit-api-run-live's idempotency (11);
- the SEJ-pure overlay bindings (01).

These three are declared but nothing the host serves invokes them: no operation of the interface resolves to them and
no live capability names them (the estate's compiled declarations, run `4d1c2e4f`). They need either a feature or a
declared retirement:
- resolve-api-request and compose-api-response (02);
- admit-api-run (05, 06), the synchronous admission that admit-run resolved to before admit-api-run-live (definition
  `253230`, its rollback).

One more gap:
- **The retired capabilities.** open-api-estate-stream (17) and project-api-estate-events (18) were removed from declarations/ on 2026-11-02. Their estate rows are retired by a declared change (subscribe-estate-live-observation.feature).

## What waits on SDA

- **One delivery, two sources.** Answered by SDA `60aefbb` (2026-11-03, D10 and D11): coherence is per capability, a
  delivery reports `outcome.evidence.authorities`, and the declaration cache serves a provider's answers by generation
  and pin ([request](../docs/request-sda-one-delivery-two-sources.md); answer-host-declared-read.feature).
- **A declared capability bound to the declared-read port.** Answered by SDA `1bd400e` (2026-11-03, D12 to D14): the
  binding's configuration carries the capability's graph source, the configured generic invocation runs it on the
  delivery's session, and `sda-kernel-built-in-read.v1` is the built-in read step. The kernel checks no digest; the
  bundle's pin and its check are the host's ([request](../docs/request-sda-declared-provider-at-the-port.md);
  answer-host-declared-read.feature, sfx-api-host-bundle-read.feature).
- **The configured provider's runner and the host's own bindings.** Answered by SDA `05ff751` (2026-11-03, D13 to
  D15):
  - D13 runs the bound capability through `run-declared-graph`.
  - D14's step is realized from SDA's registry.
  - D15 lets the host declare its own overlay rules and providers, and every place a delivery realizes an overlay uses
    them.

  On the kernel built from `05ff751` (artifact `eb800401`), the new facade ran all six kernels on WSL against the
  estate. It answered every request as the host now serving answers it: 404 `OPERATION_NOT_DECLARED`, 401
  `CALLER_REQUIRED`, and 400 `LOGIN_INPUT_INVALID`. Every bundle capability was read under the pin.

  The host declares the bundle reader and its five providers under `.v2` identities
  (`providers/host-provider-authority.json`). The estate's `.v1` copies serve the host now running until the new image
  replaces it, then a declared change retires them ([request](../docs/request-sda-host-provider-bindings.md)).
- **Compiling each declared graph once.** Answered by SDA `9926177` (2026-11-03, rules P1 to P5, CI green). A resident
  kernel holds each compiled plan by the SHA-256 of its declared sources, within 32 MiB, for estate and bundle
  capabilities alike, and the C# compiler is faster.
  - Compiling and realizing the two frontdoor graphs fell from about 500 ms to about 45 ms per warm envelope.
  - The facade's warm p50 on WSL fell from 1.60 s to 1.22 s.
  - The six kernels' memory after use was 1283 MiB, against 1135 MiB before; on `29355da` it was 1172 MiB.
  - Lighter testimony waits on this measurement: executing the cells, testimony included, is now about 145 ms per warm
    envelope (README.md, Verified).
- **Warm envelopes with a provider at the port.** Answered by SDA `29355da` (2026-11-03, rule D16, CI green).
  - The command vocabulary is now read through the declaration cache.
  - The port provider's own reads are cached too, under a `built-in` scope, so a port answer is never served from them.
  - On its kernel (`244e0129`), a warm envelope makes 1 database query, bound or unbound: the session's generation read.
    It made 6 bound and 2 unbound before.
  - The facade's warm p50 on WSL is 0.78 s and its p95 1.08 s
    ([request](../docs/request-sda-warm-envelope-round-trips.md)).
- **The kernel's estate session behind a host-bound port.** This is SDA's next KV-001 step. Until it ships, every delivery needs the estate. SDA bcbdbec (rule D9) closed the other half: the provider now passes a read through `builtInRead`, in the delivery's own session, pin and impersonation, and needs no estate reader or credential of its own (answer-host-declared-read.feature).
- **A byte input.** Whether the kernel takes a byte input, so a request's bytes reach the ingress unchanged, has not been checked (host-facade.feature).

## What waits on sfx-dal

- **A scalar output.** `evidence.stage_run_output` stages only an object or an array: it reads `JSON_QUERY(@input, '$.output')`, which is NULL for a scalar (identity migration 007). Until it stages any JSON value, complete-api-run keeps only objects and arrays (complete-api-run.feature).
- **The runs this host admitted and never completed.** The runtime role has no SELECT on `evidence`, and `evidence.list_runs` lists one principal's runs (identity migration 002). Completing lost runs at start needs a procedure that lists a writer's unfinished runs (complete-api-run.feature).

## Open questions

Each is a place where the record is unclear or pulls two ways.

**Q1.** Settled 2026-11-03 from the approved scenarios. When complete-api-run fails, the run's run-end is not published,
its streams end when their session does, and the host log names the run and the answer (complete-api-run.feature). The
approved "A run's end is published only after its output is stored" and "A run's output is readable when its run-end
arrives" leave no other answer. Today the facade publishes it anyway (host/serve.py:555-558).

**Q2.** A client that gives up still holds its request kernel until the kernel answers: 30 abandoned requests queued the
next request 68 s (abandoned-request-release). Freeing the kernel at once means stopping it in the middle of an
envelope. That costs a kernel start (no-kernel-start-on-request), and the envelope is not retried, because an envelope
a kernel may have begun is never delivered again (host-facade.feature). Which holds when the two service levels meet?
