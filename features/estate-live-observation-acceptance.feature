# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.
# It replaces how the estate live observation features were to be verified. On 2026-11-01 that verification ran from
# scripts outside the estate: a stand-in kernel and host suites, engine harnesses, checks that ran the legacy
# subscribers' code, timing and topology probes, declaration generators, and a re-implemented CLI wrapper. That is tool
# smuggling, and none of it counts. On approval, this feature replaces the scenario "The live observation scenarios
# pass at every level" in estate-live-observation-declared.feature.
# @decision marks a scenario that needs the owner's decision; its description holds the user stories.

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

  @decision
  Scenario: An acceptance capability reads the channel for a bounded time
    User story (recommended): As an agent or a frontier model observing the estate through a capability, I want to
    subscribe for a bounded time and receive what was published in it, so that I can watch the estate without holding
    a connection open, and so that the estate can accept its own live observation.

    How it emerged: an acceptance capability reaches the host through sda-governed-http-exchange-port.v1, the estate's
    HTTP exchange. It makes one HTTPS exchange bounded by time and by size. A server-sent stream does not end on its
    own, so the exchange ends timed-out and keeps none of what it received.

    Benefit: the bound is declared in subscribe-estate-live-observation, and the facade only ends the stream when the
    directive says, so the exchange completes with every frame published within the bound. No SDA change is needed.
    It is the same subscription the observer offered, with an end the caller chooses.

    The option kept open: SDA extends the governed exchange to keep a stream's bytes when its time bound ends. That is
    SDA's workspace, and it would serve every streamed read in the estate. User story: As a capability author, I want
    any HTTP stream the estate reads to return what arrived by its deadline, so that no host needs a bounded variant.

    How it stays configurable: the bound is a selector subscribe-estate-live-observation declares, alongside since and
    run, so its name, limits and default are re-declarations.

    Given the declared bound selector
    When an acceptance capability opens GET /events with a bound of 30 seconds
    Then the stream ends after 30 seconds with every frame published in that time
    And the exchange completes with them

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

  # Failures

  @decision
  Scenario: A failure is accepted only where the estate can produce it
    User story (recommended): As the product owner, I want every accepted failure to be one the estate really
    produced, and the failures it cannot produce listed as not accepted, so that "accepted" never rests on a stand-in.

    How it emerged: the facade's failure handling was verified with a stand-in kernel that failed on purpose (a kernel
    that exits before beginning an envelope, a publish that is refused). The estate cannot make a real kernel crash
    or refuse on request.

    Benefit: the evidence is real. A failing run, a refused selector, an ended session and a refused capability are
    produced through the estate and accepted.

    The option kept open: declare fault capabilities, for example a publish variant that refuses for one named
    execution, so that more failures can be produced on purpose. User story: As the product owner, I want the
    channel's gap handling shown on staging, so that I can trust it before it happens.

    How it stays configurable: a fault capability is a declaration; adding one adds an accepted failure.

    Then a run that fails, a refused selector, an ended session and a refused capability are accepted through declared capabilities
    And a kernel crash and a publish the kernel does not answer are recorded on the tracker as not accepted
