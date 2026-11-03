# Canonical feature of capture-estate-live-observation, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/24-capture-estate-live-observation.dsl, declared before any approval; estate-live-observation-
# acceptance.feature, a draft; estate-live-observation-declared.feature (approved 2026-11-01) for the two acceptance
# scenarios it held.

@project:sfx-api
@capability:capture-estate-live-observation
@provider:http-exchange
@binding:sda-declared-read-graph-provider.v1
@status:proposed-for-review
Feature: The channel is accepted by capabilities declared in the estate
  As the owner
  I want every channel scenario accepted by a declared capability run through the estate against the deployed host
  So that the runs are the evidence, and nothing is verified from outside the estate

  How it emerged: on 2026-11-01 the channel's verification ran from scripts outside the estate: a stand-in kernel and
  host suites, engine harnesses, checks that ran the legacy subscribers' code, timing and topology probes, declaration
  generators and a re-implemented CLI wrapper. The owner stopped it: that is tool smuggling, and none of it counts.

  Background:
    Given the deployed host https://sfx-api-test.azurewebsites.net
    And acceptance capabilities declared in the estate and invoked with the installed sfx-api client

  Rule: Every acceptance is a run of a declared capability, and nothing is verified from outside the estate

    @status:not-built
    Scenario: Every acceptance is a run of a declared capability
      When a scenario is accepted
      Then a declared acceptance capability executed it as a run through the estate
      And that run's id and outcome are recorded on the tracker task the scenario belongs to
      # From estate-live-observation-acceptance.feature. capture-estate-live-observation is declared (declarations/24)
      # before that draft's approval; no acceptance run is recorded.

    @status:unchecked
    Scenario: Nothing is verified from outside the estate
      Then no scenario is accepted by a script, harness, stand-in kernel, probe or generator that runs outside the estate
      And the scratch tooling used on 2026-11-01 is not used again
      # From the acceptance draft.

    @status:unchecked
    Scenario: Declarations are authored and declared without outside tools
      Then each declaration is written as its .dsl file
      And it is declared with the installed sfx-api client
      And no generator produces a declaration
      # From the acceptance draft.

    @status:installed
    Scenario: An acceptance capability reads the channel with a bounded subscription
      Then it subscribes as subscribe-estate-live-observation.feature describes a bounded subscription
      # From the acceptance draft. capture-estate-live-observation reaches the host over http-exchange.

  Rule: What the acceptance capabilities accept

    @status:unchecked
    Scenario: Live publication is accepted through the deployed host
      When an acceptance capability subscribes with a bound and admits a run through POST /sfx/v1/runs
      Then the run's records arrive within the bound, from its run-start to its run-end, in the order written
      And their positions are contiguous, and each record is framed as the observer's
      # From the acceptance draft.

    @status:unchecked
    Scenario: Replay, resume and refusal are accepted through the deployed host
      When an acceptance capability subscribes with since, with Last-Event-ID, without a session, and with a refused selector
      Then it receives the replay after that position, the resumption, the 401, and the 400 the observer gave
      # From the acceptance draft.

    @status:unchecked
    Scenario: A run's output is accepted as readable when its run-end arrives
      When an acceptance capability receives a run's run-end
      Then GET /api/circuit/v1/runs/{runId}/output, read at once, answers that run's output
      # From the acceptance draft; it accepts complete-api-run.feature's approved scenario.

    @status:unchecked
    Scenario: The record is accepted against what each legacy subscriber reads
      When an acceptance capability has a run's records from the channel
      Then each record passes a declared check of what the legacy subscribers read from it:
        | subscriber         | what it reads                                                                                                                        |
        | machine watchers   | api.runId, or the run id inside runId; api.subject.capabilityId; nested invocation payloads; kind run-end                             |
        | Explorer           | runId; observationKey; kind run-start, observation or run-end; the graph capture payload; run-end exitCode                            |
        | Estate Live        | seq contiguous from since; receivedAt; api.runId; api.cursor; api.eventId as urn:sfx-api:run-event:<run>:<cursor>; api.recordedAt     |
        | Fractal Lab bridge | seq contiguous; an observationKey on every record; kind                                                                              |
      # From the acceptance draft.

    @status:unchecked
    Scenario: A machine watcher creates a file authored from another session
      Given the sfx-workspace-watcher router running on this machine
      When an acceptance capability authors a file through author-workspace-file for the watched workspace
      Then the file is created at its path
      And its bytes match the delivery's digest
      # From the acceptance draft.

  Rule: Declared rules are conformed on retained runs

    @status:not-built
    @provider:publish-estate-live-observation
    Scenario: A declared capability's rules are conformed on a retained run
      Given a run retained in the run store
      When a conformance capability reads its events and invokes publish-estate-live-observation with them
      Then each publication is checked against the declared expectations: its record, its frame and its window effect
      And the fixture is the retained run, with no fixture file
      # From the acceptance draft. No conformance capability is declared.

    @status:unchecked
    Scenario: A changed rule shows with no facade change
      When publish-estate-live-observation is re-declared with a changed summary rule
      Then the next records an acceptance capability receives follow the new rule
      And the facade was not changed or redeployed
      # From the acceptance draft; it accepts publish-estate-live-observation.feature's approved scenario.

  Rule: The acceptance scenarios the owner approved

    @approved:2026-11-01
    @status:not-built
    @finding:misaligned
    Scenario: The live observation scenarios pass at every level
      When the build is complete
      Then the scenarios of estate-live-observation.feature pass against the stand-in kernel
      And they pass with real kernels against the estate
      And the legacy subscribers' own code accepts the records: the Explorer, Estate Live, the machine watchers and the Fractal Lab bridge
      # Word for word from estate-live-observation-declared.feature. The owner stopped stand-in-kernel verification on
      # 2026-11-01 (no tool smuggling); the acceptance draft replaces this scenario once it is approved. The scenarios of
      # estate-live-observation.feature are now in publish-, subscribe-, complete-api-run and
      # capture-estate-live-observation-facts.feature.

    @approved:2026-11-01
    @status:unchecked
    Scenario: The live observation scenarios pass on staging
      When the build is deployed to sfx-api-test
      Then the scenarios of estate-live-observation.feature pass there
      And a machine watcher on this machine, signed in with its installed session, creates a file authored from another session
      # Word for word from estate-live-observation-declared.feature.
