# Canonical feature of open-api-run-stream, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/12-open-api-run-stream.dsl; host/serve.py at a57ebba, read from the code and not run; the record
# api-runs-hosted.feature it replaces in part.

@project:sfx-api
@capability:open-api-run-stream
@provider:sql-database-reader
@status:proposed-for-review
Feature: A run's events stream as declared
  As the owner of a run
  I want GET /sfx/v1/runs/{runId}/events/stream to send the run's events exactly as its declaration frames them
  So that what a client reads from a run stream is declared, as the channel's frames already are

  Rule: The stream starts where the declaration says

    @status:not-built
    @finding:hidden-authority
    Scenario: The stream's first event is the one the directive declares
      When a client opens a run stream, with or without after or a Last-Event-ID
      Then the stream-run directive declares the cursor the stream starts after
      And the facade starts there
      # host/serve.py:671-674 choose it themselves: the directive's after, else a Last-Event-ID made of digits, else the
      # start, and a cursor below 0 is 0. Declared in declarations/12 from after and the Last-Event-ID header, which the
      # ingress now returns (providers/sfx-api-ingress.dependency.json) and the interface binds as $header.last-event-id
      # (sej/serve-api-request.sej.json). A Last-Event-ID with leading zeros is not read: SEJ reads a number only
      # through parse-json, which refuses one.

  Rule: Every frame the facade writes is declared

    @status:not-built
    @finding:hidden-authority
    @provider:project-api-run-events
    Scenario: Every frame of a run stream is declared, as stream-estate's are
      When the facade streams a run
      Then the head, the opening comment, the keep-alive and the end frame of a run the facade does not hold are the ones
        the directive declares
      And each event's frame, and the end frame of a run the facade holds, are the ones project-api-run-events answered
      And the facade writes nothing that is not declared
      # host/serve.py:681-711 frame it themselves: 200 with the directive's Content-Type, Cache-Control no-cache no-store,
      # X-Accel-Buffering no and Connection close; ": sfx-api run event stream"; "id: <cursor>", "event: <kind>",
      # "data: <event>"; ": keepalive" after runs.keepaliveSeconds (15); event: end {runId, state, cursor}.
      # subscribe-estate-live-observation declares every frame of stream-estate. Declared in declarations/12 and 26; the
      # keep-alive interval is read-api-host-configuration's streams.keepaliveMilliseconds.

    @status:not-built
    @finding:hidden-authority
    @provider:check-api-session
    Scenario: A session's end is a declared frame
      When a session caller's session ends during a run stream
      Then the stream ends with the frame the directive declares for a session's end
      # host/serve.py:704-708 and 716-719 compose event: session-ended {runId, cursor} themselves. declarations/12
      # declares the frame with {cursor} where the facade puts the last cursor it wrote, the one value only the stream
      # knows.

  Rule: A run that has ended, or that the store does not hold

    @status:not-built
    @finding:fallback
    Scenario: An ended run's stream replays its retained trace and ends with its state
      When a client opens the stream of a run that has ended
      Then it receives the run's retained events after its start cursor, then the declared end frame with the run's state
      # host/serve.py:674-675, 685 and 710 hold up to 64 ended runs in memory; for a run they no longer hold, the
      # stream ends at once with the directive's state, else "unknown". Not declared yet: replaying the store's trace
      # needs a declared decode of its brotli chunks, and the DEPENDENCY sfx-api-run-trace has only encode-chunk. Until
      # it does, read-api-host-configuration declares how many ended runs the facade keeps (runs.retainedEnded 64), and
      # declarations/12 declares the end frame, with the stored state, for a run the facade does not hold.

    @status:installed
    Scenario: A run the caller does not own is not found
      When a client opens the stream of a run it does not own
      Then the answer is NOT_FOUND
      # declarations/12: the run store confirms the run belongs to the caller.

  Rule: The caller's session bounds the stream

    @status:not-built
    @finding:fallback
    @provider:check-api-session
    Scenario: An expiry the facade cannot read ends the stream at once
      When the directive's session expiresAt is not an ISO 8601 instant
      Then the stream ends at once, as at a session's end
      # host/serve.py:342-354, 677, 689 and 704 take it as no expiry, so the stream ends only at a recheck that fails,
      # and never on the session when the directive declares no recheck. The same holds for stream-estate (:734, 772,
      # 787): subscribe-estate-live-observation.feature.
