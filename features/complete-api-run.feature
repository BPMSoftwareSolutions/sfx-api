# Canonical feature of complete-api-run, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/13-complete-api-run.dsl; host/serve.py at a57ebba, read from the code and not run; the record
# api-runs-hosted.feature it replaces in part; estate-live-observation.feature and estate-live-observation-declared.feature
# (approved).

@project:sfx-api
@capability:complete-api-run
@provider:sql-database-reader
@status:proposed-for-review
Feature: A run's outcome is decided and stored by its declaration
  As the owner of a run
  I want the run's state, exit code, failure and output decided by a declared capability and stored before its end is
  published
  So that a run's outcome means what its declaration says, and its output is readable when its run-end arrives

  Rule: The run's outcome is decided once, by declaration, and stored as decided

    @status:not-built
    @finding:hidden-authority
    @provider:project-api-run-events
    Scenario: The run's state, exit code and failure are decided by declaration and stored as decided
      When a run's delivery ends
      Then the facade hands project-api-run-events the delivery's answer as it came, and its run.exited carries the
        state, exit code and failure the projection decides (project-api-run-events.feature)
      And complete-api-run stores the state, exit code and failure that run.exited carries
      # host/serve.py:273-280 and 525-528 decide it themselves: completed with exitCode 0 only when the delivery
      # terminated and its result completed; otherwise failed with exitCode 1 and the first failure found in the
      # delivery's error, the result's failure and the outcome's error, else {code: RUN_FAILED, message: the
      # disposition}; a worker kernel that raises gives {code: RUN_KERNEL_FAILED}. The earlier draft of this scenario had
      # complete-api-run decide it, but run.exited is in the trace and the trace is appended before the completion, so
      # the outcome is decided before the completion runs. Declared in declarations/26 and 13 (authored 2026-11-02).

    @status:not-built
    @finding:hidden-authority
    Scenario: The completion's input is composed by its declaration
      Then complete-api-run receives the directive's declared completion input, the run's run.exited event, the
        delivery's answer as it came, and what the facade observed: the run's start time and the trace's last appended
        cursor
      And the facade decides none of the members it stores
      # host/serve.py:537-554 compose state, exitCode, startedAt, endedAt, failure, output and latestCursor themselves.
      # declarations/13 composes them in its prepare stage.

    @status:not-built
    @finding:fallback
    Scenario: A run's output is stored whatever its JSON type
      When a run's output is a string, a number, a boolean or null
      Then complete-api-run stores it as the run's output
      # host/serve.py:541-542 drop it. The input contract complete-api-run-request.v1 is {"type":"object"}. Waits on
      # sfx-dal: evidence.stage_run_output reads JSON_QUERY(@input, '$.output'), which is NULL for a scalar, and refuses
      # it EVIDENCE_OUTPUT_INVALID (identity migration 007-run-output-stage). Until then declarations/13 keeps an object
      # or an array, as host/serve.py does, and says so.

  Rule: A run's end is published only after its output is stored

    @approved:2026-11-01
    @status:installed
    Scenario: A run's end is published only after its output is stored
      When a run's execution ends
      Then the facade retains its trace and completes it first
      And only then publishes its run.exited event
      # Word for word from estate-live-observation-declared.feature.

    @approved:2026-11-01
    @status:installed
    Scenario: A run's output is readable when its run-end arrives
      When a run's run-end arrives
      Then GET /api/circuit/v1/runs/{runId}/output answers that run's output to its owner
      # Word for word from estate-live-observation.feature.

    @status:not-built
    @finding:misaligned
    Scenario: A run whose completion fails does not publish its end as if it had completed
      When complete-api-run answers anything but COMPLETED
      Then the run's run.exited is not published as a completed run's
      And the host log names the run and the answer
      # host/serve.py:555-558 log the answer and publish the run-end anyway. What a subscriber of that run receives
      # instead is open question Q1 in features/README.md.

  Rule: A run the host lost is completed, never left admitted

    @status:not-built
    @finding:fallback
    Scenario: A run the host stopped before it ended is completed as failed when the host starts
      Given a run the host admitted and had not ended when it stopped
      When the host starts again
      Then complete-api-run completes that run as failed, with a declared failure that names the restart
      # host/serve.py:495-511 hold runs and their queue in memory only, so no host executes or completes such a run and
      # the run store keeps it as admitted. Finding those runs needs a declared read of the runs this host admitted and
      # never completed; none is declared. Waits on sfx-dal: the run store grants the runtime role no SELECT on evidence,
      # and its only list, evidence.list_runs, lists one principal's runs (identity migration 002-run-evidence).
