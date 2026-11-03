# Canonical feature of publish-estate-live-observation, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/19-publish-estate-live-observation.dsl; host/serve.py at a57ebba, read from the code and not
# run; estate-live-observation.feature and estate-live-observation-declared.feature (approved 2026-11-01);
# estate-live-observation-failures.feature (paused 2026-11-01); the record estate-live-observation-hosted.feature.
# The legacy behaviour the approved scenarios restore is the hosted observer before the cutover: sfx-platform 094951f^
# (live-circuit/dispatch-pair/observe-server.mjs, live-circuit/circuit/observer-record.mjs and observer-publisher.mjs,
# deploy/sda-kernel/api.mjs and gateway.mjs).

@project:sfx-api
@capability:publish-estate-live-observation
@status:proposed-for-review
Feature: Every execution in the estate is published into one observation channel
  As anyone watching the estate from any machine
  I want every capability invocation and live execution published into one channel, framed as the legacy observer
  framed it
  So that what I watch is the estate's work as it happens, whoever asked for it

  Rule: Every capability execution in the estate is observable

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: Every capability execution is observable, however its caller receives the answer
      Given a subscriber on GET /events
      When a capability executes in the estate, whether admitted as a run or answered within the request
      Then the subscriber, on any machine, receives that execution as it happens
      And it receives the execution's start, each observation as the kernel writes it, and its end, in the order they were written
      And the host's own bookkeeping around runs and streams is published only as declared, by default not
      # Word for word from estate-live-observation.feature. Runs are published. Requests are not: ff44a75
      # (2026-11-01) switched them off "for now" with host data observation.requests false, because the channel fell
      # minutes behind. Publishing them again needs the channel to keep up.

    @approved:2026-11-01
    @status:unchecked
    Scenario: A frontier model invoking a capability is observable from another machine
      Given a subscriber on machine A
      When an agent on machine B invokes a capability through the sfx-api CLI
      Then the subscriber receives that invocation, named by its capability
      # Word for word from estate-live-observation.feature.

    @approved:2026-11-01
    @status:unchecked
    Scenario: A nested invocation is observable inside its run
      When a run invokes another capability, an MCP tool or a provider
      Then the subscriber receives the nested invocation's records inside the parent run
      # Word for word from estate-live-observation.feature.

    @approved:2026-11-01
    @deferred
    @status:not-built
    Scenario: A capability executed by a local kernel is observable
      When a developer runs a capability with the local sfx launcher
      Then a subscriber on any other machine receives that execution
      # Word for word from estate-live-observation.feature, where the owner deferred it. Needs an authenticated publish
      # endpoint on the host and an SDA launcher change.

    @approved:2026-11-01
    @status:installed
    Scenario: Only a producer can publish
      When a browser or an unauthenticated caller posts records to the channel
      Then it is refused and nothing is published
      # Word for word from estate-live-observation.feature. No interface operation publishes, so a post to the channel
      # resolves to no operation and is refused.

    @approved:2026-11-01
    @phase-2
    @status:not-built
    Scenario: Records reach subscribers promptly
      Then a record reaches a subscriber within <N> seconds of being written, at the median
      # Word for word from estate-live-observation.feature. The legacy observer measured about 1.5 s. The owner sets
      # the number in phase 2.

  Rule: The facade publishes through this capability and appends what it answers

    @approved:2026-11-01
    @status:installed
    Scenario: The facade publishes an execution through publish-estate-live-observation
      When an execution writes events
      Then the facade reserves their channel positions in order
      And it calls publish-estate-live-observation with the channel, the execution and each batch of events
      And it appends each answered frame to the channel unchanged
      # Word for word from estate-live-observation-declared.feature.

    @status:installed
    Scenario: The facade publishes in batches within the declared bounds
      When events are queued for the channel
      Then the publisher takes up to the declared batch of them, in position order
      And it invokes publish-estate-live-observation with {channel, events: [{seq, receivedAt, execution, event}]}, where
        receivedAt is the time the facade received the event and execution is absent for a drawing change
      # host/serve.py:425-444. The bounds are host data today (runs.feedBatchEvents 200, runs.feedBatchBytes 1 MiB):
      # read-api-host-configuration.feature.

    @approved:2026-11-01
    @status:installed
    Scenario: The facade keeps the run windows publish answers
      When publish-estate-live-observation answers a window effect for an event
      Then the facade opens, closes or adds a graph to that run's window exactly as answered
      And it applies no window rule of its own
      # Word for word from estate-live-observation-declared.feature. Which frames a selection writes from a window is
      # select-estate-live-observation.feature. declarations/19 (authored 2026-11-02) also names, in every effect of an
      # execution's event from its start to its end, the window the frame belongs to.

    @approved:2026-11-01
    @status:installed
    Scenario: Each record is the observer record
      Then each record has, in this order: seq, observationKey, receivedAt, kind, runId, api, glyph, cls, text, payload
      And kind is run-start, observation or run-end
      And runId names the run, and api names the run event, its cursor, its times, its execution root and its capability
      And within one x-observer-instance, seq increases by one with no gaps
      # Word for word from estate-live-observation.feature. The one exception to the last step is a batch this
      # capability did not frame (below).

  Rule: What is published, and under which name, is declared

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: Whether the host's own bookkeeping is published is declared, and by default it is not
      Given the declared default
      When the facade rechecks a session, retains a run's trace, completes a run, captures its facts,
        or publishes, selects or subscribes on the channel
      Then none of those executions is published to the channel
      When a directive is re-declared to publish its trace retention, completion or fact capture
      Then those executions are published, and the facade was not changed or redeployed
      # Steps word for word from estate-live-observation-declared.feature, decided 2026-11-01; its user story and the
      # option kept open are in that file at a57ebba. The default holds today, but no directive declares whether its
      # execution is published: host/serve.py leaves those executions unpublished by attaching no execution to their
      # kernels (:195-197, 295, 371, 530, 547, 555). The channel's own publish is never published, since publishing it
      # would publish itself without end.

    @approved:2026-11-01
    @status:installed
    Scenario: The record's text follows the declared summary, by default without shape notes
      Given the declared default
      Then a record's text is the observer's summary without its in=, out=, req=, rsp= and model= shape notes
      When publish-estate-live-observation is re-declared with the shape notes
      Then the next published records carry them, and the facade was not changed or redeployed
      # Steps word for word from estate-live-observation-declared.feature, decided 2026-11-01. The summary is a table of
      # rules declared in this capability. The re-declaration has not been run.

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: A request's execution is published as the frontdoor's, with the resolved capability inside it
      Given the declared default
      When a client's request executes on a request kernel
      Then the subscriber receives an execution of serve-http-request with the resolved capability as its nested invocation
      # Steps word for word from estate-live-observation-declared.feature, decided 2026-11-01. Requests are not
      # published today (observation.requests false).

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: A synchronous execution is published like a run
      When a capability executes within an HTTP request on a request kernel
      Then its events are published through publish-estate-live-observation, as a run's are
      # Word for word from estate-live-observation-declared.feature.

    @status:not-built
    @finding:misaligned
    Scenario: Which requests are published, and the name of each, are declared
      Then which requests are published is declared per interface operation
      And publish-estate-live-observation names each request's execution
      # The decided scenario above says both. host/serve.py:627-628 publish every request or none on one host data
      # switch, and name each request's execution themselves: a new uuid, with capability {"subject":
      # "serve-http-request"}. Not declared on 2026-11-02: requests stay unpublished, declared as
      # read-api-host-configuration's channel.requests.published false. Publishing them per operation needs a request's
      # envelope to ask for its observations under a declared ref; that comes with switching requests back on, which
      # waits for the channel to keep up (ff44a75).

    @status:not-built
    @finding:misaligned
    Scenario: A request's execution carries the frontdoor's observations
      When a request's execution is published
      Then it carries the frontdoor's observations and its nested invocation, as a run's execution carries its own
      # Switched back on, a request's execution would carry only run.started and run.exited: a request's envelope asks
      # for no observations, and request kernels no longer run with SIDEFX_OBSERVE (host/serve.py:166-168, 316-325,
      # 627-633; ff44a75 and 1ac2d0f).

    @approved:2026-11-01
    @status:unchecked
    Scenario: A change to a declared rule needs no facade change
      Given the facade deployed
      When a rule of publish-estate-live-observation is re-declared, such as a summary glyph
      Then the next published frames follow the new rule
      And the facade was not changed or redeployed
      # Word for word from estate-live-observation-declared.feature.

  Rule: A failed execution is observed like any other, and a failure of the channel shows

    @paused:2026-11-01
    @status:installed
    @finding:misaligned
    Scenario: Records the publish capability did not frame are a gap
      When publish-estate-live-observation refuses a batch, or answers it with something that is not its frames
      Then the next record a subscriber receives has a seq past that batch's positions
      And the host log names the positions that were not published
      # Word for word from estate-live-observation-failures.feature, which the owner paused. host/serve.py:445-451 does
      # it anyway.

    @paused:2026-11-01
    @status:unchecked
    Scenario: A run whose capability fails is observed to its end
      When a run's capability fails
      Then the subscriber receives the run's records up to its run-end
      And the run-end carries the failure, with a non-zero exitCode
      # Word for word from estate-live-observation-failures.feature.

    @paused:2026-11-01
    @status:unchecked
    Scenario: A run whose kernel fails is observed to its end
      When the kernel executing a run fails, or answers with something that is not a delivery
      Then the subscriber receives the run's run-end, carrying the failure, with a non-zero exitCode
      And GET /api/circuit/v1/runs/{runId}/output answers that failure
      # Word for word from estate-live-observation-failures.feature.

    @paused:2026-11-01
    @status:not-built
    Scenario: A request whose capability fails is observed
      Given request executions are published
      When a request's resolved capability fails
      Then the subscriber receives the request's execution of serve-http-request, with the failed invocation inside it
      And its end carries the failure
      # Word for word from estate-live-observation-failures.feature.

    @paused:2026-11-01
    @status:not-built
    Scenario: A request refused before any capability is resolved is observed
      Given request executions are published
      When a request is refused before any capability is resolved
      Then the subscriber receives the request's execution of serve-http-request, ended with the refusal
      # Word for word from estate-live-observation-failures.feature.
