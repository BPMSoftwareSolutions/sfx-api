# Canonical feature of read-api-host-configuration, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# A proposed capability; nothing declares it yet. It gives the settings the facade acts on a declared home, so that
# sfx-api.config.json says only how to listen and how to start kernels (host-facade.feature).

@project:sfx-api
@capability:read-api-host-configuration
@status:proposed-for-review
Feature: The facade's settings are declared
  As the owner
  I want every setting the facade acts on declared with the host's other declarations
  So that a change to one is a re-declaration and a new pin, never a change to the facade's code or to host data it
  interprets

  Rule: The facade reads its declared settings once, before it listens

    @status:not-built
    Scenario: The settings are read at start and held for the process's life
      When the host starts
      Then the facade invokes read-api-host-configuration once, before it binds its port
      And it holds the answer for as long as it runs
      And an answer that is refused, or a delivery that fails, stops the host

    @status:not-built
    @finding:hidden-authority
    Scenario Outline: What the settings declare
      Then the answer declares <setting>

      Examples:
        | setting                                                                               | held today in                                                                         |
        | the envelope each request is handed to serve-http-request in                          | sfx-api.config.json request                                                           |
        | how many events a run keeps, and the largest observation it keeps whole               | sfx-api.config.json runs.maxEvents (50000) and runs.eventPayloadBytes (1 MiB)         |
        | the bounds of a trace chunk                                                           | runs.traceChunkBytes (512 KiB) and runs.traceChunkEvents (2000)                       |
        | how often a quiet run stream is kept alive                                            | runs.keepaliveSeconds (15)                                                            |
        | how many frames and bytes the channel retains, and how many it publishes in one batch | runs.feedEvents (20000), runs.feedBytes (32 MiB), runs.feedBatchEvents (200), runs.feedBatchBytes (1 MiB) |
        | how many admitted runs may wait for a worker                                          | nowhere: the queue has no bound (host/serve.py:503-511)                               |
        | how many ended runs the facade keeps for reconnects, until a stream replays the trace | runs.retained (64)                                                                    |
        | the capability that publishes the channel, and whether request executions are published | observation.publish and observation.requests (false)                                 |
        | the drawing read, its interval and its page size                                      | drawings.capabilityId, intervalMilliseconds (2000) and limit (20)                     |
        | the kernel's observation queue bounds                                                 | nowhere: the kernel's defaults hold                                                   |
        | the failure response for a delivery that answers none                                 | host/serve.py:639-643                                                                 |
        | how long a request waits for a free request kernel, and the busy refusal              | nowhere: a request waits without a bound (host/serve.py:625)                          |
      # Declared in declarations/25-read-api-host-configuration.dsl (authored 2026-11-02, not yet declared into the
      # estate), every value held today kept as it is. Two values are new. The 2 s wait is what App Service's 230 s
      # leaves after the facade's 228 s answer bound for a request kernel (README.md:227, sfx-api.config.json). The 64
      # waiting runs is a proposed number with no record behind it. The busy, queue-full and delivery-failure responses
      # are 503 REQUEST_KERNEL_BUSY, 503 RUN_QUEUE_FULL and today's 502 KERNEL_DELIVERY_FAILED, each with its
      # Content-Length.

    @approved:2026-11-01
    @status:installed
    Scenario: The queue bounds are host data
      Then the kernel's queue bounds are its defaults (512 records, 1 MiB, a 2000 ms drain) until the host data sets them
      # Word for word from estate-live-observation-kernel-sampling.feature. The host data that sets them is this
      # capability's answer. Nothing sets them today, so the defaults hold.

    @status:not-built
    Scenario: A changed setting is a re-declaration and a new pin
      When a setting is re-declared, and the host's bundle is recorded again, pinned and deployed
      Then the facade acts on the new setting
      And no facade code and no facade configuration changed
