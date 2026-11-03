# Canonical feature of serve-api-request, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# It accounts for what the earlier features said of the frontdoor, and for where it reads its interface. The rest of
# its declaration (declarations/03-serve-api-request.sql, sej/serve-api-request.sej.json) is not accounted for yet:
# features/README.md, "Not yet accounted for".

@project:sfx-api
@capability:serve-api-request
@provider:sql-database-reader
@provider:answer-api-response
@status:proposed-for-review
Feature: The frontdoor serves the declared API
  As anyone calling the API
  I want each request resolved by the declared interface and answered by the capability it names
  So that the API means what its declaration says and nothing the host adds

  Rule: The interface is the host's own authority, answered from the host's bundle

    @status:not-built
    @finding:misaligned
    Scenario: The frontdoor's interface is part of its declaration
      When the frontdoor serves a request
      Then it resolves the request against sidefx-api-interface.v1 as its own declaration carries it
      And it reads no interface from the estate
      # Today serve-api-request.prepare and .interface read the interface from the estate as data on every request,
      # through sql-database-reader (README.md:87-89; declarations/03-serve-api-request.sql:13, 22). The host's own
      # definition is then read from the estate it serves, against the owner's direction. As a graph statement read it
      # never reaches the host's provider (SDA 93a7a56 D7). Carried in the frontdoor's declaration, it is a declared read
      # the bundle answers (host-declared-read-provider.feature). Authored 2026-11-02: sej/serve-api-request.sej.json
      # carries the interface in serve-carry-interface, which replaces serve-prepare-interface-read, and
      # declarations/27-serve-api-request.dsl drops the interface read. authorities/sidefx-api-interface.v1.json moved
      # into that SEJ. The live frontdoor's DSL, with its identify stage, was declared without being committed, so
      # declarations/27 is rebuilt from declarations/03 and README.md's stage list, and must be compared with the live
      # declaration before it is declared.

  Rule: The interface routes the paths the legacy clients use

    @approved:2026-11-01
    @status:installed
    Scenario: The legacy output path answers the run's output
      When a client reads GET /api/circuit/v1/runs/{runId}/output
      Then the frontdoor resolves it to read-run-output for the caller
      # Word for word from estate-live-observation-declared.feature. sidefx-api-interface.v1 resolves that path to
      # read-run-output.
