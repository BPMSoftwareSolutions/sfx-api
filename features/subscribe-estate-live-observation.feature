# Canonical feature of subscribe-estate-live-observation, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/21-subscribe-estate-live-observation.dsl; sidefx-api-interface.v1; host/serve.py at a57ebba,
# read from the code and not run; estate-live-observation.feature and estate-live-observation-declared.feature
# (approved 2026-11-01); estate-live-observation-bounded-subscription.feature (a draft); the record
# estate-live-observation-hosted.feature. The legacy behaviour the approved scenarios restore is the hosted observer
# before the cutover (sfx-platform 094951f^) and the subscribers built against it.

@project:sfx-api
@capability:subscribe-estate-live-observation
@provider:sql-database-reader
@status:proposed-for-review
Feature: Anyone signed in subscribes to the channel from any machine
  As anyone signed in, on any machine
  I want to subscribe to the estate's observation channel, resume it, and follow one run, as the legacy observer allowed
  So that the subscribers built against the observer keep working

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a signed-in session on any machine

  Rule: A subscription is opened by this capability, and the facade follows its directive

    @approved:2026-11-01
    @status:installed
    Scenario: A subscription is opened by subscribe-estate-live-observation
      When a client opens GET /events or GET /sfx/v1/estate-execution/stream
      Then the frontdoor resolves it to subscribe-estate-live-observation
      And the facade follows the answered directive: its frames, its replay, its keep-alive, its session recheck and its end
      # Word for word from estate-live-observation-declared.feature. sidefx-api-interface.v1 resolves both paths to it.

    @approved:2026-11-01
    @status:installed
    Scenario: Subscribe live
      When I open GET /events
      Then the answer is text/event-stream with an x-observer-instance header
      And it begins with "retry: 3000" and then ": replay-complete"
      And only records published after I subscribed arrive
      And ": keep-alive" arrives while the channel is quiet
      # Word for word from estate-live-observation.feature. declarations/21 declares the header and the frames.

    @approved:2026-11-01
    @status:installed
    Scenario: The same channel under the API prefix
      When I open GET /sfx/v1/estate-execution/stream with the same query
      Then I receive exactly what GET /events gives
      # Word for word from estate-live-observation.feature.

    @status:not-built
    @finding:fallback
    Scenario: The facade writes only the frames the directive declares
      When a stream-estate directive declares no opening, replay-end, session-end or keep-alive frame
      Then the facade writes nothing in its place
      # host/serve.py:757, 765, 784 and 790 write nothing for a missing opening, replay-end or session-end frame, but
      # write ": keepalive" for a missing keep-alive frame.

  Rule: A subscription needs a live session

    @approved:2026-11-01
    @status:installed
    Scenario: Without a session
      When I open GET /events without a session
      Then the answer is 401
      # Word for word from estate-live-observation.feature.

    @approved:2026-11-01
    @status:installed
    @provider:check-api-session
    Scenario: The session ends
      Given I am subscribed
      When my session expires or is revoked
      Then ": session-ended" arrives within 5 seconds and the stream closes
      # Word for word from estate-live-observation.feature. An expiry the facade cannot read:
      # open-api-run-stream.feature, which holds for stream-estate too (host/serve.py:734, 772, 787).

  Rule: A subscriber resumes where it left off, within what the channel retains

    @approved:2026-11-01
    @status:installed
    Scenario: Resume after a disconnect
      Given the last record I received was seq 120
      When I reconnect with GET /events?since=120, or with Last-Event-ID 120
      Then the retained records after 120 arrive, then ": replay-complete", then live records
      # Word for word from estate-live-observation.feature.

    @status:installed
    Scenario: The channel retains a declared number of frames and bytes
      Then the channel retains at most the declared frames and bytes, the oldest let go first
      And a closed run window is let go once its end is older than the oldest retained frame
      # host/serve.py:469-472. The bounds are host data today (runs.feedEvents 20000, runs.feedBytes 32 MiB):
      # read-api-host-configuration.feature.

    @status:installed
    Scenario: A since older than the retained frames replays what is retained
      When a subscriber resumes from a position older than the oldest retained frame
      Then it receives every retained frame
      And the jump in seq shows what was let go
      # host/serve.py:762-764 and 485-492. Within one instance seq has no gaps (publish-estate-live-observation.feature),
      # so the jump is the sign.

    @approved:2026-11-01
    @status:installed
    Scenario: The host restarted
      When I reconnect and the x-observer-instance header differs from the one I had
      Then I know the sequence restarted and records between the two may be missing
      # Word for word from estate-live-observation.feature.

    @status:installed
    Scenario: Each host start is a new channel instance
      When the host starts
      Then the channel's instance is a new uuid, and its positions count again from 1
      # host/serve.py:391, 396-398.

    @status:not-built
    @finding:fallback
    Scenario: A since from an earlier instance replays the new instance from its start
      Given the host restarted, and this instance's latest position is 40
      When a subscriber resumes with since 120 from the earlier instance
      Then it receives every frame this instance retains, then ": replay-complete", then live records
      # host/serve.py:762-764 and 776-779 send it nothing until this instance publishes position 121. ffe9e15 replayed
      # the new instance for such a cursor; d442242 dropped that. declarations/21 (authored 2026-11-02) declares
      # beyondLatest replay-retained.

  Rule: A subscriber can follow one run

    @approved:2026-11-01
    @status:installed
    @provider:select-estate-live-observation
    Scenario Outline: Follow one run
      When I open GET /events?<selector>
      Then <replay>
      And afterwards only that run's records arrive

      Examples:
        | selector                        | replay                                                     |
        | run=current                     | the most recent run is replayed from its run-start         |
        | run=current&graphId=graph:<cap> | the most recent run that captured that graph is replayed   |
        | run=2                           | the second retained run is replayed                        |
        | run=next                        | nothing is replayed, and the next run to start is followed |
      # Word for word from estate-live-observation.feature. The facade invokes select-estate-live-observation.

    @approved:2026-11-01
    @status:installed
    Scenario Outline: A selector the observer refused is refused
      When I open GET /events?<query>
      Then the answer is 400 with {"error":"<error>"}

      Examples:
        | query    | error         |
        | run=03   | invalid_run   |
        | run=abc  | invalid_run   |
        | since=-1 | invalid_since |
      # Word for word from estate-live-observation.feature. declarations/21 declares both refusals.

  Rule: A subscriber can subscribe for a bounded time

    @status:installed
    @finding:misaligned
    Scenario: A bounded subscription ends at its bound
      When I open GET /events with a bound of 30 seconds
      Then the stream closes 30 seconds after it opened
      And every frame published in that time arrived before it closed
      # From estate-live-observation-bounded-subscription.feature, a draft, built in 94c66c6 before any approval. A
      # capability reaches the host through the estate's governed HTTP exchange, which keeps nothing of a stream that
      # does not end on its own. The stream closes with no closing frame (host/serve.py:735-736, 793-794).

    @status:installed
    @finding:misaligned
    Scenario Outline: A bound combines with the other selectors
      When I open GET /events?<selector> with a bound of 30 seconds
      Then <what arrives> until the bound

      Examples:
        | selector    | what arrives                                                                |
        | since=120   | the retained records after 120, then ": replay-complete", then live records |
        | run=current | the most recent run from its run-start, then only that run's records        |
      # From the bounded-subscription draft, built in 94c66c6.

    @status:installed
    @finding:misaligned
    Scenario: Without a bound nothing changes
      When I open GET /events without a bound
      Then the stream stays open until the session ends, as it does today
      # From the bounded-subscription draft, built in 94c66c6.

    @status:installed
    @finding:misaligned
    Scenario: A bound that is not a positive whole number of seconds is refused
      When I open GET /events with a bound of 0, -5 or 1.5 seconds
      Then the answer is 400 with {"error":"invalid_bound"}
      # From the bounded-subscription draft, built in 94c66c6. declarations/21 declares the refusal.

  Rule: The subscribers built against the legacy observer keep working

    @approved:2026-11-01
    @status:unchecked
    Scenario: A machine watcher creates a file authored from another machine
      Given the sfx-workspace-watcher router running on machine A
      When author-workspace-file runs from machine B
      Then the file is created on machine A
      # Word for word from estate-live-observation.feature. estate-live-observation-kernel-sampling.feature records that
      # elo-watchers-restored was accepted; no run of it is cited in this repo.

    @approved:2026-11-01
    @status:unchecked
    Scenario: The Explorer animates and replays a circuit live
      When a run of the open circuit executes
      Then the Explorer animates its cells and edges as they execute
      And Replay replays the latest run of that circuit
      # Word for word from estate-live-observation.feature.

    @approved:2026-11-01
    @status:unchecked
    Scenario: Estate Live shows a run started from another client
      When a run is started from another client
      Then Estate Live shows it, without its ID being entered and without creating any runs
      # Word for word from estate-live-observation.feature.

    @approved:2026-11-01
    @status:unchecked
    Scenario: The Fractal Lab bridge relays the channel
      Then it receives a contiguous sequence, with an observation key on every record
      # Word for word from estate-live-observation.feature.

  Rule: This capability supersedes open-api-estate-stream and project-api-estate-events

    @approved:2026-11-01
    @status:not-built
    Scenario: The superseded capabilities are retired
      Given the facade serves the channel through the declared capabilities
      When no operation resolves to open-api-estate-stream or project-api-estate-events
      Then both are retired
      # Word for word from estate-live-observation-declared.feature. No operation of sidefx-api-interface.v1 resolves to
      # either. declarations/17 and 18 were removed from this repo on 2026-11-02, so the host's bundle will not hold
      # them; their rows stay in the estate until a declared retirement removes them.
