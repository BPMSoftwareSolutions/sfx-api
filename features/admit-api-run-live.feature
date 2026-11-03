# Canonical feature of admit-api-run-live, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/11-admit-api-run-live.dsl; host/serve.py at a57ebba, read from the code and not run; the record
# api-runs-hosted.feature it replaces in part; estate-live-observation-kernel-sampling.feature (approved). Its
# idempotency and the rest of its declaration are not accounted for yet: features/README.md.

@project:sfx-api
@capability:admit-api-run-live
@provider:sql-database-reader
@status:proposed-for-review
Feature: A run is admitted with its whole plan declared
  As anyone admitting a run through POST /sfx/v1/runs
  I want the run's admission to declare everything that happens to it, from its execution to its end
  So that the facade carries the run out step by step and decides none of it

  Rule: The run's plan is declared in its execute-run directive

    @approved:2026-11-01
    @status:installed
    Scenario: A run's delivery asks to be sampled, as declared data
      When admit-api-run composes a run's envelope
      Then the envelope carries observation {"sample": true, "ref": "<runId>"}
      And the host does not add or change it
      # Word for word from estate-live-observation-kernel-sampling.feature. declarations/11 composes it.

    @status:not-built
    @finding:hidden-authority
    Scenario: The directive declares the run's whole plan
      When admit-api-run-live answers execute-run
      Then the directive declares the run's envelope and its sampling
      And the capability that shapes the run's events (project-api-run-events.feature)
      And its trace capability, its completion capability and its fact capture
      And, for each of them, whether its execution is published
      And the response the client receives, complete as declared
      # At a57ebba declarations/11 declared the envelope, its observation, its trace and its completion. The event shape,
      # the fact capture and the publication of each step were host/serve.py's (api-runs-hosted record; see
      # publish-estate-live-observation.feature for the approved publication decision). The revised declarations/11
      # (authored 2026-11-02) declares all of them in sfx-api-host-directive.v1, the run's own execution published and no
      # other, and the 202 as respond.raw (host-facade.feature).

  Rule: A run is answered at once and executed in admission order

    @status:not-built
    @finding:hidden-authority
    Scenario: An admitted run is answered at once and waits for a worker within a declared bound
      When the kernel answers execute-run
      Then the facade answers the directive's response and queues the run
      And the workers take runs in the order they were queued
      And a run the declared bound has no room for is answered with the declared refusal (read-api-host-configuration.feature)
      And that run ends failed with the declared delivery answer, so the run store does not keep it admitted
      # host/serve.py:503-511, 517-519 and 657-658 queue without a bound. The run store registered the run before the
      # facade sees its directive, so a run the facade cannot queue still has to end. read-api-host-configuration
      # declares runs.queue: 64 waiting, the 503 RUN_QUEUE_FULL refusal and the delivery answer the run ends with.

    @status:installed
    Scenario: A run is executed once, whatever the directive repeats
      When execute-run names a run the facade already holds
      Then the run is not queued again, and the directive's response is still answered
      # host/serve.py:505-506. Whether a repeated admission names the same run is admit-api-run-live's idempotency.

  Rule: The facade holds a run only while it is live

    @status:not-built
    @finding:hidden-authority
    Scenario: The facade holds the runs it is executing or that wait
      Then the facade holds every run that is executing or waiting
      And it holds no run once its end is published; an ended run is read from the run store (open-api-run-stream.feature)
      # host/serve.py:508-510 also holds up to 64 ended runs (runs.retained), the oldest let go first. That stays until a
      # run's stream can replay the store's trace (open-api-run-stream.feature); meanwhile the number is declared, as
      # read-api-host-configuration's runs.retainedEnded.

  Rule: Admission keeps its service levels

    @status:installed
    @slo:run-capacity
    Scenario: Two runs execute at once
      Given the service level:
        | SLI                        | SLO target  | baseline                                                       |
        | runs executing at once     | 2           | 2 workers, each about 350 MB on the shared plan (README.md, Next 2) |
      When more than two runs are admitted
      Then two execute and the rest wait for a worker
      # sfx-api.config.json workers.instances 2.

    @status:not-built
    @slo:run-capacity
    Scenario: At most 64 runs wait for a worker
      Given the service level:
        | SLI                     | SLO target            | baseline |
        | runs waiting for a worker | at most 64 (proposed) | none   |
      When runs are admitted faster than the workers end them
      Then no more than 64 wait at once
      # declarations/25 runs.queue. What a run admitted at the bound receives is "An admitted run is answered at once and
      # waits for a worker within a declared bound". The number has no record behind it (read-api-host-configuration.feature).
