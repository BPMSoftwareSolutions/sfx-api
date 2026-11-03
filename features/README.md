# Canonical features of sfx-api

Proposed for the owner's review, 2026-11-02. These seventeen files replace the twelve feature files that were here at
`a57ebba`.

What this is: the behaviour of the sfx-api host as Gherkin, with one canonical feature per capability the host
declares or needs. The facade (`host/serve.py` with `deploy/`), the host's declared-read provider and the container's
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

Approved on 2026-11-01 (estate-live-observation-declared.feature): "The hosting facade holds connections and the
channel's buffer and does what the declared capabilities answer; it decides nothing itself."

## Tags

Status, one per scenario:

| Tag | Meaning |
| --- | --- |
| `@status:proven` | ran on sfx-api-test or against the estate, and the run or measurement is cited (none yet) |
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
| `@capability:<id>` | the capability under test. On a Feature it applies to every scenario |
| `@component:<id>` | the part of the host under test, where that part is not a capability |
| `@provider:<id>` | a capability the scenario depends on: one its capability's declaration invokes through `generic-capability-invocation.v1`, or one its directive has the facade invoke |
| `@binding:<id>` | a provider module the capability's declaration binds to a port, by its `providerId` |
| `@issue:<n>` | the sfx-api issue the feature answers |

The ids are as `declarations/` names them; they were not read from the estate for this write-up. On a Feature,
`@provider` and `@binding` name what the capability's declaration binds; they were not narrowed to the scenarios
whose runs invoke them.

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
| pinned bundle | the host's recorded declarations, pinned by the digest of their manifest |
| estate | the consumer's database of declarations and data. The host reaches it for the consumer's data and the consumer's capabilities |

## The features

| Feature | Under test | Scenarios | Approved | Paused | Installed | Not built | Unchecked |
| --- | --- | --: | --: | --: | --: | --: | --: |
| [host-facade](host-facade.feature) | the facade | 32 | 2 | | 16 | 16 | |
| [read-api-host-configuration](read-api-host-configuration.feature) | proposed capability | 4 | 1 | | 1 | 3 | |
| [host-declared-read-provider](host-declared-read-provider.feature) | the host's provider | 19 | | | 3 | 16 | |
| [serve-api-request](serve-api-request.feature) | serve-api-request | 2 | 1 | | 1 | 1 | |
| [admit-api-run-live](admit-api-run-live.feature) | admit-api-run-live | 5 | 1 | | 2 | 3 | |
| [project-api-run-events](project-api-run-events.feature) | proposed capability | 11 | 4 | | 3 | 7 | 1 |
| [open-api-run-stream](open-api-run-stream.feature) | open-api-run-stream | 6 | | | 1 | 5 | |
| [check-api-session](check-api-session.feature) | check-api-session | 3 | | | 2 | 1 | |
| [complete-api-run](complete-api-run.feature) | complete-api-run | 7 | 2 | | 2 | 5 | |
| [append-api-run-trace](append-api-run-trace.feature) | append-api-run-trace | 2 | | | 2 | | |
| [publish-estate-live-observation](publish-estate-live-observation.feature) | publish-estate-live-observation | 22 | 14 | 5 | 7 | 10 | 5 |
| [select-estate-live-observation](select-estate-live-observation.feature) | select-estate-live-observation | 4 | 2 | | 2 | 2 | |
| [subscribe-estate-live-observation](subscribe-estate-live-observation.feature) | subscribe-estate-live-observation | 23 | 14 | | 16 | 3 | 4 |
| [capture-estate-live-observation-facts](capture-estate-live-observation-facts.feature) | capture-estate-live-observation-facts | 2 | 2 | | | 2 | |
| [read-estate-drawing-changes](read-estate-drawing-changes.feature) | read-estate-drawing-changes | 13 | | | 6 | 2 | 5 |
| [capture-estate-live-observation](capture-estate-live-observation.feature) | capture-estate-live-observation | 13 | 2 | | 1 | 3 | 9 |
| [durable-credential-vault](durable-credential-vault.feature) | the container's vault | 4 | 4 | | 2 | | 2 |
| **Total** | | **172** | **49** | **5** | **67** | **79** | **26** |

Findings: 25 hidden authority, 15 fallbacks and 29 misaligned.

Proposed capabilities these features name:
- `read-api-host-configuration`: the facade's declared settings, read once at start (declarations/25);
- `project-api-run-events`: the run event shape (declarations/26);
- `record-api-host-authority`: the declared capability that drives a recording of the host's bundle. Not declared: it
  records through the host's provider, which is not built.

## The declarations

Authored on 2026-11-02 to align with these features. They are files in this repo only:
- none has been declared into the estate, recorded into the host's bundle or run;
- each `config` line was checked only to parse as JSON;
- the facade does not follow them yet, so every scenario they serve keeps its status;
- they go out with the facade change, the provider, the bundle and the pin, in one deploy (host-declared-read-provider.feature).

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
- **`record-api-host-authority`.** Waits on the host's provider.

The frontdoor's live DSL, with its identify stage, was declared without being committed. declarations/27 is rebuilt from declarations/03 and README.md's stage list. Compare it with the live declaration before declaring it.

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
| host-declared-read-provider.feature | draft, uncommitted | host-declared-read-provider |

Every approved, paused and draft scenario is in exactly one canonical feature. The three records described what the host
did. Their scenarios now say what it must do, and the code they cited is in the comments.

## Not yet accounted for

These capabilities are declared in this repo, or have their SEJ here, but have no canonical feature yet. Their
behaviour is in their declarations and in the top-level README.md, not in a feature:
- serve-http-request (07), apart from what host-facade.feature says the facade hands it;
- resolve-http-request (08);
- open-api-session (09);
- verify-password-derivation (10);
- read-api-estate-scopes (16);
- serve-api-request (03; now declarations/27 and sej/serve-api-request.sej.json), apart from its interface and the
  legacy output path;
- answer-api-response (03);
- resolve-api-request and compose-api-response (02);
- read-run-state, read-run-output and read-run-graphs (04);
- admit-api-run (05, 06);
- admit-api-run-live's idempotency (11);
- the SEJ-pure overlay bindings (01);
- read-api-session and revoke-api-session (sej/).

Two more gaps:
- **The provider programs.** `providers/sfx-api-ingress.dependency.json`, `sfx-api-run-trace.dependency.json` and `sfx-identity-login.dependency.json` (bearer digest, trace encoding, password derivation) are not accounted for either.
- **The retired capabilities.** open-api-estate-stream (17) and project-api-estate-events (18) were removed from declarations/ on 2026-11-02. Their estate rows are retired by a declared change (subscribe-estate-live-observation.feature).

## What waits on SDA

- **The kernel's estate session behind a host-bound port.** This is SDA's next KV-001 step. Until it ships, every delivery needs the estate. SDA bcbdbec (rule D9) closed the other half: the provider now passes a read through `builtInRead`, in the delivery's own session, pin and impersonation, and needs no estate reader or credential of its own (host-declared-read-provider.feature).
- **A byte input.** Whether the kernel takes a byte input, so a request's bytes reach the ingress unchanged, has not been checked (host-facade.feature).

## What waits on sfx-dal

- **A scalar output.** `evidence.stage_run_output` stages only an object or an array: it reads `JSON_QUERY(@input, '$.output')`, which is NULL for a scalar (identity migration 007). Until it stages any JSON value, complete-api-run keeps only objects and arrays (complete-api-run.feature).
- **The runs this host admitted and never completed.** The runtime role has no SELECT on `evidence`, and `evidence.list_runs` lists one principal's runs (identity migration 002). Completing lost runs at start needs a procedure that lists a writer's unfinished runs (complete-api-run.feature).

## Open questions

Each is a place where the record is unclear or pulls two ways.

**Q1.** What does a run's subscriber receive when complete-api-run fails?
- The approved "A run's end is published only after its output is stored" holds run.exited back until completion succeeds.
- Held back for good, every stream of that run stays open.
- Today the facade publishes it anyway (host/serve.py:555-558), so subscribers see a run-end whose output is not stored.
