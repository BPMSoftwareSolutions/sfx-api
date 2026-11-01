# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.
# It replaces how the estate live observation features were to be verified. On 2026-11-01 that verification ran from
# scripts outside the estate: a stand-in kernel and host suites, engine harnesses, checks that ran the legacy
# subscribers' code, timing and topology probes, declaration generators, and a re-implemented CLI wrapper. That is tool
# smuggling, and none of it counts. On approval, this feature replaces the scenario "The live observation scenarios
# pass at every level" in estate-live-observation-declared.feature.
# Split on 2026-11-01 at the owner's request: how a capability reads the channel for a bounded time is
# estate-live-observation-bounded-subscription.feature, and how the channel behaves when something fails is
# estate-live-observation-failures.feature (paused).

Feature: Estate live observation accepted through declared capabilities
  The approved scenarios of estate-live-observation.feature and estate-live-observation-declared.feature are accepted
  by capabilities declared in the estate, executed through the estate against the deployed host. Their runs are the
  evidence. Nothing is verified from outside the estate.

  Background:
    Given the deployed host https://sfx-api-test.azurewebsites.net
    And acceptance capabilities declared in the estate and invoked with the installed sfx-api client

  # The rules

  Scenario: Every acceptance is a run of a declared capability
    When a scenario is accepted
    Then a declared acceptance capability executed it as a run through the estate
    And that run's id and outcome are recorded on the tracker task the scenario belongs to

  Scenario: Nothing is verified from outside the estate
    Then no scenario is accepted by a script, harness, stand-in kernel, probe or generator that runs outside the estate
    And the scratch tooling used on 2026-11-01 is not used again

  Scenario: Declarations are authored and declared without outside tools
    Then each declaration is written as its .dsl file
    And it is declared with the installed sfx-api client
    And no generator produces a declaration

  # Reading the channel from the estate

  Scenario: An acceptance capability reads the channel with a bounded subscription
    Then it subscribes as estate-live-observation-bounded-subscription.feature describes

  # What is accepted

  Scenario: Live publication is accepted through the deployed host
    When an acceptance capability subscribes with a bound and admits a run through POST /sfx/v1/runs
    Then the run's records arrive within the bound, from its run-start to its run-end, in the order written
    And their positions are contiguous, and each record is framed as the observer's

  Scenario: Replay, resume and refusal are accepted through the deployed host
    When an acceptance capability subscribes with since, with Last-Event-ID, without a session, and with a refused selector
    Then it receives the replay after that position, the resumption, the 401, and the 400 the observer gave

  Scenario: A run's output is readable when its run-end arrives
    When an acceptance capability receives a run's run-end
    Then GET /api/circuit/v1/runs/{runId}/output, read at once, answers that run's output

  Scenario: The record is accepted against what each legacy subscriber reads
    When an acceptance capability has a run's records from the channel
    Then each record passes a declared check of what the legacy subscribers read from it:
      | subscriber          | what it reads                                                                                              |
      | machine watchers    | api.runId, or the run id inside runId; api.subject.capabilityId; nested invocation payloads; kind run-end   |
      | Explorer            | runId; observationKey; kind run-start, observation or run-end; the graph capture payload; run-end exitCode   |
      | Estate Live         | seq contiguous from since; receivedAt; api.runId; api.cursor; api.eventId as urn:sfx-api:run-event:<run>:<cursor>; api.recordedAt |
      | Fractal Lab bridge  | seq contiguous; an observationKey on every record; kind                                                       |

  Scenario: A machine watcher creates a file authored from another session
    Given the sfx-workspace-watcher router running on this machine
    When an acceptance capability authors a file through author-workspace-file for the watched workspace
    Then the file is created at its path
    And its bytes match the delivery's digest

  # Declared rules, conformed on retained runs

  Scenario: A declared capability's rules are conformed on a retained run
    Given a run retained in the run store
    When a conformance capability reads its events and invokes publish-estate-live-observation with them
    Then each publication is checked against the declared expectations: its record, its frame and its window effect
    And the fixture is the retained run, with no fixture file

  Scenario: A changed rule shows with no facade change
    When publish-estate-live-observation is re-declared with a changed summary rule
    Then the next records an acceptance capability receives follow the new rule
    And the facade was not changed or redeployed
