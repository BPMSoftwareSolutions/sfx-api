# Approved by the owner, 2026-11-01.
# It delivers features/estate-live-observation.feature through the declared capabilities the owner reviewed:
# publish-estate-live-observation, select-estate-live-observation, subscribe-estate-live-observation,
# capture-estate-live-observation-facts and check-api-session. The hosting facade (host/serve.py) is transport only.
# @decision marks a scenario that needs the owner's decision before it is accepted; its comment holds the recommendation.
# @decided marks a decision the owner made. A decision here is declared configuration: the decided setting is the
# declared default, and another setting is a re-declaration, never a facade change.
# Not in this feature: picking up SDA's C# kernel fix (37a745f) and the start.sh keyring race.

Feature: Estate live observation served through its declared capabilities
  The meaning of estate live observation is declared and resolved by the kernel. The hosting facade holds
  connections and the channel's buffer and does what the declared capabilities answer; it decides nothing itself.

  Background:
    Given the declared capabilities publish-estate-live-observation, select-estate-live-observation,
      subscribe-estate-live-observation, capture-estate-live-observation-facts and check-api-session
    And the hosting facade serving the estate host

  # Decisions

  @decided
  Scenario: Whether the host's own bookkeeping is published is declared, and by default it is not
    Decided 2026-11-01: the recommended setting, as declared configuration that can change later.

    User story: As someone watching the estate live from any machine, I want the channel to show
    the executions that people, agents and routers invoke, and not the host's own upkeep around them, so that
    what I see is the estate's work, and the channel does not fill with, or loop on, its own mechanics.

    How it emerged: you asked that every capability invocation and live execution in the estate be observable,
    and estate-live-observation.feature says so for every capability execution. The host itself executes
    capabilities to keep runs and streams going: check-api-session every 5 seconds for each open stream,
    append-api-run-trace for each chunk of a run's trace, complete-api-run and
    capture-estate-live-observation-facts once per run, and publish, select and subscribe for the channel
    itself. Read literally, the rule covers them too. They cannot all be published: each publish call is an
    execution, so publishing it would need another publish, without end.

    Benefit: the channel carries what was asked of the estate. Rechecks alone would add one execution every
    5 seconds for every open subscriber.

    The option kept open: publish the trace retention, completion and fact capture, but not the channel's own
    capabilities or the rechecks. User story: As the estate owner, I want to see the host's writes to the
    estate live, so that I notice when its bookkeeping fails or slows. That bookkeeping's failures already go
    to the host log, and Retained shows whether a run's facts arrived.

    How it stays configurable: each directive that has the facade execute a capability around a run or a
    stream (the run's trace, completion and fact capture; the stream's session recheck) also declares whether
    that execution is published, and the facade publishes as declared. The channel's own publish is the one
    execution never published, because publishing it would publish itself without end.

    Given the declared default
    When the facade rechecks a session, retains a run's trace, completes a run, captures its facts,
      or publishes, selects or subscribes on the channel
    Then none of those executions is published to the channel
    When a directive is re-declared to publish its trace retention, completion or fact capture
    Then those executions are published, and the facade was not changed or redeployed

  @decided
  Scenario: The record's text follows the declared summary, by default without shape notes
    Decided 2026-11-01: the recommended setting, as declared configuration that can change later.

    User story: As the estate owner, I want publishing to stay cheap enough for live observation
    to keep up, and I accept a shorter one-line summary that no subscriber parses.

    How it emerged: the restored record is the legacy observer's, and the observer added three display members,
    glyph, cls and text, for its own timeline page and console log. text joins the record's type, identities,
    phase, status and duration, then appends shape notes: in= and out= with each payload's contract and size,
    and req=, rsp= and model= for provider exchanges, every value clipped at 96 characters. Declaring it showed
    two costs. The kernel engine has no substring operation, so the clipping cannot be declared at all. And the
    kernel compiles every operation of a declared expression into the execution graph on every call: the first
    full port had 1,135 operations and took about 1.6 seconds a call; the declared publish has 266 operations
    and frames 43 events in 1.3 seconds. The shape notes would add roughly 110 operations. That is estimated,
    not measured.

    Benefit: publish stays at its current size. The Explorer, Estate Live, the machine watchers and the
    Fractal Lab bridge read kind, runId, observationKey, api and payload, never text, so nothing that works
    today changes.

    The option kept open: declare the shape notes, with values unclipped. User story: As someone reading the
    raw channel, I want each record's line to show what a cell took in and gave back, so that I can scan sizes
    without opening the payload. The payload holds the same facts.

    How it stays configurable: the summary is a table of rules declared in publish-estate-live-observation,
    and shape notes are more rules in that table.

    Given the declared default
    Then a record's text is the observer's summary without its in=, out=, req=, rsp= and model= shape notes
    When publish-estate-live-observation is re-declared with the shape notes
    Then the next published records carry them, and the facade was not changed or redeployed

  @decided
  Scenario: A request's execution is published as the frontdoor's, with the resolved capability inside it
    Decided 2026-11-01: the recommended setting, as declared configuration that can change later.

    User story: As someone watching the estate live, I want an API request to appear as what
    actually executed, the frontdoor serving that request with the capability it resolved inside it, so that
    the channel shows the estate as it ran, and a request that failed before resolving anything is visible too.

    How it emerged: "A synchronous execution is published like a run" does not say what the execution is
    called. Within a request, the request kernel executes serve-http-request, the frontdoor, and the
    capability the request resolves to, such as read-estate-execution-topology, executes nested inside it.
    A run is published under the capability it was admitted for; a request was admitted for no capability,
    so its name has to be chosen.

    Benefit: nothing has to be inferred. The frontdoor is what the facade asked the kernel to execute, and the
    resolved capability already arrives as the nested invocation the machine watchers and Estate Live
    recognize. Every request then appears on the channel, a subscriber's own GET /events included, and each
    carries the frontdoor's execution graph.

    The option kept open: publish a request under the capability it resolved to, and leave out requests that
    resolve to nothing. User story: As someone watching the estate live, I want a request to appear as the
    capability it asked for, so that I see the estate's reads by name. The name is then known only once the
    nested invocation is observed, after the request's start has been published.

    How it stays configurable: which requests are published, and at which observation altitude, is declared
    per interface operation, and publish-estate-live-observation names each execution.

    Given the declared default
    When a client's request executes on a request kernel
    Then the subscriber receives an execution of serve-http-request with the resolved capability as its nested invocation

  # Publish

  Scenario: The facade publishes an execution through publish-estate-live-observation
    When an execution writes events
    Then the facade reserves their channel positions in order
    And it calls publish-estate-live-observation with the channel, the execution and each batch of events
    And it appends each answered frame to the channel unchanged

  Scenario: The facade keeps the run windows publish answers
    When publish-estate-live-observation answers a window effect for an event
    Then the facade opens, closes or adds a graph to that run's window exactly as answered
    And it applies no window rule of its own

  Scenario: A synchronous execution is published like a run
    When a capability executes within an HTTP request on a request kernel
    Then its events are published through publish-estate-live-observation, as a run's are

  # Subscribe

  Scenario: A subscription is opened by subscribe-estate-live-observation
    When a client opens GET /events or GET /sfx/v1/estate-execution/stream
    Then the frontdoor resolves it to subscribe-estate-live-observation
    And the facade follows the answered directive: its frames, its replay, its keep-alive, its session recheck and its end

  Scenario: A followed run is chosen by select-estate-live-observation
    When a subscription selects a run
    Then the facade calls select-estate-live-observation with the selection and the retained windows, newest first
    And it writes only the chosen window's frames
    And for run=next it calls select again when a window opens

  # The end of a run

  Scenario: A run's end is published only after its output is stored
    When a run's execution ends
    Then the facade retains its trace and completes it first
    And only then publishes its run.exited event

  Scenario: A finished execution's facts are captured
    When a run is completed
    Then the facade calls capture-estate-live-observation-facts with the execution and its events
    And it reports the answer when it is not CAPTURED

  Scenario: The legacy output path answers the run's output
    When a client reads GET /api/circuit/v1/runs/{runId}/output
    Then the frontdoor resolves it to read-run-output for the caller

  # The facade carries no meaning

  Scenario: A change to a declared rule needs no facade change
    Given the facade deployed
    When a rule of publish-estate-live-observation is re-declared, such as a summary glyph
    Then the next published frames follow the new rule
    And the facade was not changed or redeployed

  Scenario: The facade's own observation meaning is removed
    Then host/serve.py holds no run window, graph or selection rule
    And the uncommitted run windows, graph detection and selection in host/serve.py are taken out

  # Acceptance and release

  Scenario: The live observation scenarios pass at every level
    When the build is complete
    Then the scenarios of estate-live-observation.feature pass against the stand-in kernel
    And they pass with real kernels against the estate
    And the legacy subscribers' own code accepts the records: the Explorer, Estate Live, the machine watchers and the Fractal Lab bridge

  Scenario: The live observation scenarios pass on staging
    When the build is deployed to sfx-api-test
    Then the scenarios of estate-live-observation.feature pass there
    And a machine watcher on this machine, signed in with its installed session, creates a file authored from another session

  Scenario: The superseded capabilities are retired
    Given the facade serves the channel through the declared capabilities
    When no operation resolves to open-api-estate-stream or project-api-estate-events
    Then both are retired
