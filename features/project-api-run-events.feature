# Canonical feature of project-api-run-events, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# A proposed capability; nothing declares it yet. It takes over the run event shape host/serve.py composes, as
# project-api-estate-events shapes the channel's frames for the facade to write unchanged.
# Sources: host/serve.py at a57ebba, read from the code and not run; the record api-runs-hosted.feature it replaces in
# part; estate-live-observation-kernel-sampling.feature (approved) for the run's end.

@project:sfx-api
@capability:project-api-run-events
@status:proposed-for-review
Feature: A run's events are shaped by a declared projection
  As anyone reading a run's events, live, from its trace or on the channel
  I want every event of a run shaped by one declaration
  So that a run stream, the trace and the channel carry the same events, and the facade composes none of them

  Rule: The facade hands what it observed to the projection and keeps what it answers

    @status:not-built
    @finding:hidden-authority
    Scenario: Each observation becomes the event the projection answers
      When a run's kernel writes an observation line
      Then the facade gives it the line, its byte count, the time the facade received it and how many events the run holds
      And project-api-run-events answers the run event at the run's next cursor, counting from 1: its eventId, kind,
        payload and rootExecutionId
      And it answers the event's run stream frame
      And the facade keeps that event and its frame as answered
      # host/serve.py:67-68 and 218-230 compose {eventId, cursor, at, kind, payload, rootExecutionId} themselves, with
      # eventId urn:sfx-api:run-event:<runId>:<cursor>. Estate Live reads api.eventId in exactly that form
      # (capture-estate-live-observation.feature), so the projection declares it. Declared in
      # declarations/26-project-api-run-events.dsl (authored 2026-11-02, not yet declared into the estate).

    @status:not-built
    @finding:hidden-authority
    Scenario: A run's lifecycle events are the projection's
      When the facade admits a run, starts it on a worker, or sees it end
      Then it hands the projection what it observed: the admission time; the start time and the kernel's pid; the end
        time, the delivery's answer as it came, the kernel's closing frame and the number of observations dropped
      And project-api-run-events answers run.admitted, run.started and run.exited
      And run.exited carries the run's state, exit code and failure, which the projection decides from the delivery's
        answer, and the run stream's end frame
      # host/serve.py:258, 521-523 and 533-536 name and shape these events themselves, and settle() (:273-280) decides
      # the outcome. The outcome is decided here, not by complete-api-run, because run.exited is in the trace and the
      # trace is appended before the completion: the run store refuses a chunk after completion (EVIDENCE_RUN_CLOSED,
      # README.md:306). complete-api-run stores the outcome run.exited carries (complete-api-run.feature).

    @status:not-built
    @finding:hidden-authority
    Scenario: An observation's kind is declared
      Then the kind of a run event is the one project-api-run-events answers
      # host/serve.py:241, 247 take the observationType, else "observation".

    @status:not-built
    @finding:fallback
    Scenario: A line that is not JSON becomes the declared malformed event
      When a run's kernel writes an observation line that is not JSON
      Then the run's next event is the one project-api-run-events declares for it
      # host/serve.py:236-240 make it observation.malformed {line: its first 1024 characters}. declarations/26 declares
      # observation.malformed {line}, or {truncated: true, byteLength} past 1024 characters: SEJ has no operator that
      # cuts a string.

    @status:not-built
    @finding:fallback
    Scenario: A large observation is cut as declared
      When an observation is larger than the declared largest whole observation
      Then its event carries what project-api-run-events declares for an observation that size
      # host/serve.py:242-246 keep observationType, testimonyType, graphId, rootExecutionId, cellId, phase and status as
      # {truncated: true, byteLength}, and count the line's characters against a byte bound (runs.eventPayloadBytes).

    @status:not-built
    @finding:hidden-authority
    Scenario: A run keeps at most the declared number of events
      When a run holds the declared number of events
      Then its further observations are dropped and counted, and the count is on its run.exited
      And its lifecycle events are still kept
      # host/serve.py:233-235, 535; the bound is runs.maxEvents (50000) in host data.

  Rule: A run ends at its closing frame

    @approved:2026-11-01
    @status:installed
    Scenario: A run ends at its closing frame
      Given the kernel answers a run before its observations are all written
      When the observation-stream-closed.v1 frame with the run's ref arrives
      Then every record between the run's opening and closing frames is published as the run's
      And only then is the run's run-end published
      And the host never ends a run on silence: Kernel.quiet is removed
      # Word for word from estate-live-observation-kernel-sampling.feature; built in 1ac2d0f, which removed quiet().

    @approved:2026-11-01
    @status:installed
    Scenario: A run that lost observations says so on its run-end
      When a run's closing frame carries dropped 3 and records 40
      Then the run's run-end carries capture {"records": 40, "dropped": 3}
      And the host log names the run and the 3 dropped records
      # Word for word from estate-live-observation-kernel-sampling.feature.

    @approved:2026-11-01
    @status:installed
    Scenario: A run whose stream never closed says so on its run-end
      When the kernel ends without the run's closing frame
      Then the run's run-end is published when the kernel's stream ends
      And it carries capture {"complete": false}
      # Word for word from estate-live-observation-kernel-sampling.feature.

    @status:not-built
    @finding:hidden-authority
    Scenario: A run's end waits for its closing frame within a declared bound
      Given the run's kernel stays running
      When the run's closing frame has not arrived the declared time after the run's answer
      Then the run's run-end is published, carrying capture {"complete": false}
      And the worker takes its next run
      # host/serve.py:161-174 wait without a bound while the kernel lives, and the worker takes no other run.

    @approved:2026-11-01
    @status:unchecked
    Scenario: Accepted on staging
      When author-workspace-file runs from a CLI session
      Then a machine watcher on GET /events creates the file, as elo-watchers-restored was accepted
      And the run's run-end carries capture {"records": <n>, "dropped": 0}
      # Word for word from estate-live-observation-kernel-sampling.feature. No run of this acceptance is cited in this
      # repo.
