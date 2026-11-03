# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of read-run-graphs, the capability GET /sfx/v1/runs/{runId}/graph resolves to, written
# as Gherkin. The sources are its declaration (declarations/04-run-views.sql and sej/read-run-graphs.sej.json; the
# estate's compiled graph source, read on 2026-11-03 through sql-database-reader, run
# 4d1c2e4f-db9b-ae32-f716-377c0a781c08) and sidefx-api-interface.v1 (operation read-run-graph).
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider capability  a declared capability that a step of another capability binds or invokes
#   provider binding     the declared provider capability a scenario needs, named by its identity, the result it must
#                        produce there, and the run evidence that proves it did
#   provider tag         @provider:<id> names one required provider capability, case for case
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   run store            sfx-identity's evidence schema, where a run is registered, traced and completed

@project:sfx-api
@status:proposed-for-review
Feature: A caller reads the graphs of its own run
  As a caller of the declared API
  I want to read the execution graphs a run stored
  So that I can see what the run executed after it ended

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)
  "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
  strategies" (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The run store answers, and only the run's graphs are passed on

    @status:installed
    @capability:read-run-graphs
    @provider:read-run-evidence
    Scenario: The run's owner reads its graphs
      Given a run the caller admitted
      When read-run-graphs reads it with the caller's principalId and the runId
      Then read-run-evidence answers READ
      And read-run-graphs answers only status, runId and graphs
      # sej/read-run-graphs.sej.json. README.md, Next 2: the run store does not yet hold the graphs per execution root.

    @status:installed
    @capability:read-run-graphs
    @provider:read-run-evidence
    Scenario: Any other answer of the run store is passed on unchanged
      When read-run-evidence answers anything but READ, such as another principal's run or no such run
      Then read-run-graphs answers what the run store answered

    @status:installed
    @capability:read-run-graphs
    Scenario: The input names a run and nothing else
      When read-run-graphs is invoked with members other than runId and principalId, or without runId
      Then its input contract refuses it
      # read-run-graphs-request.v1: required runId, additionalProperties false.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:read-run-graphs
    @provider:read-run-evidence
    Scenario: The read honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                | provider capability the step needs                                   | result it must produce here         | run evidence that proves it                               |
        | read-run-graphs.read | read-run-evidence, in sidefx:capabilities, through generic invocation | the run store's answer for the run  | the nested execution of read-run-evidence and its outcome |
      When a caller reads a run's graphs
      Then the call produces the result its binding requires
      And acceptance finds the nested invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet.

  Rule: Reading a run's graphs keeps its service levels

    @status:not-built
    @capability:read-run-graphs
    @provider:read-run-evidence
    @slo:dispatched-request-latency
    Scenario: Reading a run's graphs has a latency objective
      Given the service level:
        | SLI                                                             | SLO target                   | baseline |
        | server time on sfx-api-test of GET /sfx/v1/runs/{runId}/graph   | set from its first baseline  | none     |
      When a caller reads a run's graphs through the frontdoor
      Then its server time is measured, and its target is set from that measurement
