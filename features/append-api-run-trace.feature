# Canonical feature of append-api-run-trace, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/14-append-api-run-trace.dsl; host/serve.py at a57ebba, read from the code and not run; the record
# api-runs-hosted.feature it replaces in part.

@project:sfx-api
@capability:append-api-run-trace
@provider:sql-database-reader
@binding:sfx-api-run-trace-encode
@status:proposed-for-review
Feature: A run's trace is retained in the run store
  As the owner of a run
  I want every event of the run retained, in order, when it ends
  So that the run reads the same from its trace as it did live

  Rule: The facade sends the run's events in order, in chunks within the declared bounds

    @status:installed
    Scenario: The trace is retained in contiguous chunks
      When a run ends
      Then the facade sends its events, run.exited included, to the directive's trace capability in contiguous chunks
      And each chunk is {runId, firstCursor, lastCursor, recordCount, events} within the declared chunk bounds
      # host/serve.py:328-339 and 543-554. The bounds are host data today (runs.traceChunkBytes 512 KiB,
      # runs.traceChunkEvents 2000): read-api-host-configuration.feature.

    @status:installed
    Scenario: The first chunk not appended stops the trace
      When append-api-run-trace answers a chunk with anything but APPENDED
      Then no later chunk is sent
      And the completion's latestCursor is the last cursor appended
      # host/serve.py:543-554.

  Rule: The trace keeps its service levels

    @status:proven
    @slo:trace-chunk
    Scenario: A run's trace is retained in chunks of at most 2000 events and 524288 bytes
      Given the service level:
        | SLI                               | SLO target                                          | baseline      |
        | events and bytes per trace chunk  | at most 2000 events and 524288 bytes of their JSON  | run f8a01553  |
      When a run's trace is retained
      Then each chunk holds at most 2000 events, whose compact JSON totals at most 524288 bytes
      # Run f8a01553: 4 chunks to cursor 43, read back by the legacy decoder identical to the stream (README.md, Verified).
      # The encoding of each chunk: sfx-api-run-trace-encode.feature.
