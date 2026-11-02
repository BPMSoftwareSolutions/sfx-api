# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.
# Source: SDA aa32214, "Emit observations asynchronously so a slow reader never stops execution" (CI run 41369364916),
# and its host binding in scenario-driven-architecture docs/request-delivery-observation-sampling.md, sections 5 and 12.

Feature: A run's observations are complete under the kernel's asynchronous emission
  From SDA aa32214 the kernel writes observations from its own queue, so a run's answer no longer waits for them, and a
  full queue drops them and counts what it dropped. The host ends a run at its closing frame, not when the kernel goes
  quiet, so every observation the kernel wrote reaches the channel, and a gap shows on the run's end.

  User story: As anyone observing the estate, I want every observation of a run to arrive before its run-end, and a run
  that lost observations to say so, so that what I watch is the whole run or visibly not.

  How it emerged: the host waits for the kernel to be quiet for 50 ms (Kernel.quiet) before it ends a run. That is a
  guess, and under asynchronous emission it would lose a run's last observations and miss every drop.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net

  Scenario: The kernel and the host change go live together
    Then the kernel is pinned to SDA aa32214 in the same deploy as this feature's host change, never before it

  Scenario: A run's delivery asks to be sampled, as declared data
    When admit-api-run composes a run's envelope
    Then the envelope carries observation {"sample": true, "ref": "<runId>"}
    And the host does not add or change it

  Scenario: The host's own deliveries are not sampled
    Then worker kernels run without SIDEFX_OBSERVE, so a delivery without the member is not sampled
    And the trace and completion the host invokes around a run write no observations

  Scenario: A run ends at its closing frame
    Given the kernel answers a run before its observations are all written
    When the observation-stream-closed.v1 frame with the run's ref arrives
    Then every record between the run's opening and closing frames is published as the run's
    And only then is the run's run-end published
    And the host never ends a run on silence: Kernel.quiet is removed

  Scenario: A run that lost observations says so on its run-end
    When a run's closing frame carries dropped 3 and records 40
    Then the run's run-end carries capture {"records": 40, "dropped": 3}
    And the host log names the run and the 3 dropped records

  Scenario: A run whose stream never closed says so on its run-end
    When the kernel ends without the run's closing frame
    Then the run's run-end is published when the kernel's stream ends
    And it carries capture {"complete": false}

  Scenario: The queue bounds are host data
    Then the kernel's queue bounds are its defaults (512 records, 1 MiB, a 2000 ms drain) until the host data sets them

  Scenario: Accepted on staging
    When author-workspace-file runs from a CLI session
    Then a machine watcher on GET /events creates the file, as elo-watchers-restored was accepted
    And the run's run-end carries capture {"records": <n>, "dropped": 0}
