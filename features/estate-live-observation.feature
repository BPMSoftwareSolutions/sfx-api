# Approved by the owner, 2026-11-01.
# The legacy behaviour it restores is the hosted observer as it ran before the cutover: sfx-platform 094951f^
# (live-circuit/dispatch-pair/observe-server.mjs, live-circuit/circuit/observer-record.mjs and observer-publisher.mjs,
# deploy/sda-kernel/api.mjs and gateway.mjs), and the subscribers built against it.
# @decision marks a scenario that needs the owner's decision before it is accepted.
# @deferred marks a scenario the owner deferred; it is not built in this feature's first phase.
# @phase-2 marks a scenario for the phase after the first phase works.

Feature: Estate live observation
  Every capability invocation and live execution in the estate is published into one observation channel,
  and anyone signed in can subscribe to it from any machine, as the legacy observer allowed.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a signed-in session on any machine

  # Publish: what is observable

  Scenario: Every capability execution is observable, however its caller receives the answer
    Given a subscriber on GET /events
    When a capability executes in the estate, whether admitted as a run or answered within the request
    Then the subscriber, on any machine, receives that execution as it happens
    And it receives the execution's start, each observation as the kernel writes it, and its end, in the order they were written
    And the host's own bookkeeping around runs and streams is published only as declared, by default not
    # Decided 2026-11-01 as declared configuration; see estate-live-observation-declared.feature.

  Scenario: A frontier model invoking a capability is observable from another machine
    Given a subscriber on machine A
    When an agent on machine B invokes a capability through the sfx-api CLI
    Then the subscriber receives that invocation, named by its capability

  Scenario: A nested invocation is observable inside its run
    When a run invokes another capability, an MCP tool or a provider
    Then the subscriber receives the nested invocation's records inside the parent run

  @deferred
  Scenario: A capability executed by a local kernel is observable
    When a developer runs a capability with the local sfx launcher
    Then a subscriber on any other machine receives that execution
    # Needs an authenticated publish endpoint on the host and an SDA launcher change.

  Scenario: Only a producer can publish
    When a browser or an unauthenticated caller posts records to the channel
    Then it is refused and nothing is published

  # Subscribe

  Scenario: Subscribe live
    When I open GET /events
    Then the answer is text/event-stream with an x-observer-instance header
    And it begins with "retry: 3000" and then ": replay-complete"
    And only records published after I subscribed arrive
    And ": keep-alive" arrives while the channel is quiet

  Scenario: Resume after a disconnect
    Given the last record I received was seq 120
    When I reconnect with GET /events?since=120, or with Last-Event-ID 120
    Then the retained records after 120 arrive, then ": replay-complete", then live records

  Scenario: The host restarted
    When I reconnect and the x-observer-instance header differs from the one I had
    Then I know the sequence restarted and records between the two may be missing

  Scenario Outline: Follow one run
    When I open GET /events?<selector>
    Then <replay>
    And afterwards only that run's records arrive

    Examples:
      | selector                           | replay                                                        |
      | run=current                        | the most recent run is replayed from its run-start            |
      | run=current&graphId=graph:<cap>    | the most recent run that captured that graph is replayed      |
      | run=2                              | the second retained run is replayed                           |
      | run=next                           | nothing is replayed, and the next run to start is followed    |

  Scenario Outline: A selector the observer refused is refused
    When I open GET /events?<query>
    Then the answer is 400 with {"error":"<error>"}

    Examples:
      | query    | error         |
      | run=03   | invalid_run   |
      | run=abc  | invalid_run   |
      | since=-1 | invalid_since |

  Scenario: Without a session
    When I open GET /events without a session
    Then the answer is 401

  Scenario: The session ends
    Given I am subscribed
    When my session expires or is revoked
    Then ": session-ended" arrives within 5 seconds and the stream closes

  Scenario: The same channel under the API prefix
    When I open GET /sfx/v1/estate-execution/stream with the same query
    Then I receive exactly what GET /events gives

  # The record

  Scenario: Each record is the observer record
    Then each record has, in this order: seq, observationKey, receivedAt, kind, runId, api, glyph, cls, text, payload
    And kind is run-start, observation or run-end
    And runId names the run, and api names the run event, its cursor, its times, its execution root and its capability
    And within one x-observer-instance, seq increases by one with no gaps

  # The end of a run

  Scenario: A run's output is readable when its run-end arrives
    When a run's run-end arrives
    Then GET /api/circuit/v1/runs/{runId}/output answers that run's output to its owner

  # The subscribers that must keep working

  Scenario: A machine watcher creates a file authored from another machine
    Given the sfx-workspace-watcher router running on machine A
    When author-workspace-file runs from machine B
    Then the file is created on machine A

  Scenario: The Explorer animates and replays a circuit live
    When a run of the open circuit executes
    Then the Explorer animates its cells and edges as they execute
    And Replay replays the latest run of that circuit

  Scenario: Estate Live shows a run started from another client
    When a run is started from another client
    Then Estate Live shows it, without its ID being entered and without creating any runs

  Scenario: The Fractal Lab bridge relays the channel
    Then it receives a contiguous sequence, with an observation key on every record

  # Retained

  Scenario: A finished run appears in Retained
    When a run completes
    Then its admission, and its return or failure, appear in the estate activity for its interval

  # Timeliness

  @phase-2
  Scenario: Records reach subscribers promptly
    Then a record reaches a subscriber within <N> seconds of being written, at the median
    # Legacy measured about 1.5 s. The owner sets the number in phase 2.
