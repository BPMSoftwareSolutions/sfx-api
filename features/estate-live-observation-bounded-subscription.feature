# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.
# Split out of estate-live-observation-acceptance.feature at the owner's request, so that it can be prioritized on its
# own.

Feature: Bounded subscription to the estate live observation channel
  A subscriber can subscribe for a bounded time. The stream ends at the bound with every frame published in that time,
  so a caller that cannot hold a connection open, such as a capability executed in the estate, can still observe it.

  User story: As an agent or a frontier model observing the estate through a capability, I want to subscribe for a
  bounded time and receive what was published in it, so that I can watch the estate without holding a connection open.

  How it emerged: a capability reaches the host through the estate's HTTP exchange (sda-governed-http-exchange-port.v1),
  which makes one HTTPS exchange bounded by time. A server-sent stream does not end on its own, so the exchange times
  out and keeps none of what it received. The estate's own acceptance capabilities read the channel this way.

  How it stays configurable: the bound is a selector that subscribe-estate-live-observation declares, alongside since
  and run, so its name is a re-declaration. The option kept open: SDA extends the governed exchange to keep a stream's
  bytes when its time bound ends. That would serve every streamed read in the estate, and it is SDA's workspace.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a signed-in session

  Scenario: A bounded subscription ends at its bound
    When I open GET /events with a bound of 30 seconds
    Then the stream closes 30 seconds after it opened
    And every frame published in that time arrived before it closed

  Scenario Outline: A bound combines with the other selectors
    When I open GET /events?<selector> with a bound of 30 seconds
    Then <what arrives> until the bound

    Examples:
      | selector    | what arrives                                                                  |
      | since=120   | the retained records after 120, then ": replay-complete", then live records   |
      | run=current | the most recent run from its run-start, then only that run's records          |

  Scenario: Without a bound nothing changes
    When I open GET /events without a bound
    Then the stream stays open until the session ends, as it does today

  Scenario: A bound that is not a positive whole number of seconds is refused
    When I open GET /events with a bound of 0, -5 or 1.5 seconds
    Then the answer is 400 with {"error":"invalid_bound"}
