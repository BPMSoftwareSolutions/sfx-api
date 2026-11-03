# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of read-api-estate-scopes, the capability GET /sfx/v1/estate-execution/scopes
# resolves to, written as Gherkin. The sources are its declaration (declarations/16-read-api-estate-scopes.dsl; the
# estate's compiled graph source, read on 2026-11-03 through sql-database-reader, run
# 4d1c2e4f-db9b-ae32-f716-377c0a781c08) and sidefx-api-interface.v1 (operation read-estate-scopes).
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider tag         @provider:<id> names one required provider capability, case for case, by the identity its binding
#                        declares
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   estate scope         an estate a caller may open in Estate, with how its retained and live activity are read

@project:sfx-api
@status:proposed-for-review
Feature: A signed-in caller reads the estates it may open
  As a signed-in caller of the declared API
  I want to read which estates I may open in Estate and how their activity is read
  So that Estate opens only an estate whose scope I can read

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)
  "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
  strategies" (2026-11-03)

  Rule: The scopes are read in one declared read, and no run is created

    @status:installed
    @capability:read-api-estate-scopes
    @provider:sda-embodiment-plan-port.v1
    Scenario: The caller reads its estate scopes
      Given the caller's principal
      When read-api-estate-scopes reads
      Then it answers estate-scopes.v1 with the principal, each readable estate (id, label, revision, scopeId, read) and
        whether its retained and live activity are available
      # declarations/16: one SQL read through the declared-read graph provider, on the estate's topology reader with its
      # smallest bounds, only for the estate the topology reader selects.

    @status:installed
    @capability:read-api-estate-scopes
    Scenario: Reading the scopes creates no run
      When read-api-estate-scopes reads
      Then no run is registered in the run store
      # declarations/16 intent: "No run is created".

  Rule: Reading the scopes keeps its service levels

    @status:not-built
    @capability:read-api-estate-scopes
    @slo:dispatched-request-latency
    Scenario: Reading the scopes has a latency objective
      Given the service level:
        | SLI                                                                     | SLO target                   | baseline |
        | server time on sfx-api-test of GET /sfx/v1/estate-execution/scopes      | set from its first baseline  | none     |
      When a signed-in caller reads its scopes through the frontdoor
      Then its server time is measured, and its target is set from that measurement
