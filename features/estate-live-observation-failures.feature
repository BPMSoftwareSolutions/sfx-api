# Written 2026-11-01 at the owner's request and PAUSED by the owner: nothing in it is built or accepted until the
# owner resumes and approves it.
# It collects how the channel behaves when something fails. Each outcome is deterministic. The failures that
# estate-live-observation.feature already approves are not repeated here: a subscriber without a session (401), a
# refused selector (400), a session that ends (": session-ended"), a browser or unauthenticated publisher (refused),
# and a host restart (a new x-observer-instance).

Feature: Estate live observation when something fails
  A failed execution is observed like any other execution, and a failure of the channel itself shows to its
  subscribers.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a subscriber on GET /events

  # An execution fails: it is observed

  Scenario: A run whose capability fails is observed to its end
    When a run's capability fails
    Then the subscriber receives the run's records up to its run-end
    And the run-end carries the failure, with a non-zero exitCode

  Scenario: A run whose kernel fails is observed to its end
    When the kernel executing a run fails, or answers with something that is not a delivery
    Then the subscriber receives the run's run-end, carrying the failure, with a non-zero exitCode
    And GET /api/circuit/v1/runs/{runId}/output answers that failure

  Scenario: A request whose capability fails is observed
    Given request executions are published
    When a request's resolved capability fails
    Then the subscriber receives the request's execution of serve-http-request, with the failed invocation inside it
    And its end carries the failure

  Scenario: A request refused before any capability is resolved is observed
    Given request executions are published
    When a request is refused before any capability is resolved
    Then the subscriber receives the request's execution of serve-http-request, ended with the refusal

  # The channel fails: subscribers can tell

  Scenario: Records the publish capability did not frame are a gap
    When publish-estate-live-observation refuses a batch, or answers it with something that is not its frames
    Then the next record a subscriber receives has a seq past that batch's positions
    And the host log names the positions that were not published
    # The one exception to "seq increases by one with no gaps" in estate-live-observation.feature.
