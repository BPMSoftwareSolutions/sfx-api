# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of revoke-api-session, the capability POST /sfx/v1/session/logout resolves to, written
# as Gherkin. The sources are its declaration (sej/revoke-api-session.sej.json; the estate's compiled graph source, read
# on 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), sidefx-api-interface.v1
# (operation sign-out) and README.md, Next 4.
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

@project:sfx-api
@status:proposed-for-review
Feature: A signed-in caller signs out
  As a signed-in caller of the declared API
  I want to end my session
  So that its bearer or cookie is refused from then on

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

  Rule: sfx-identity revokes the session the caller holds

    @status:probed
    @capability:revoke-api-session
    @provider:sql-database-reader
    Scenario: A signed-in caller's session is revoked
      Given a caller resolved to a principal and its live session
      When revoke-api-session runs with that principalId and sessionId
      Then sql-database-reader runs [identity].revoke_api_session on sfx-identity-database with them
      And revoke-api-session answers what sfx-identity answered
      # README.md, Next 4: sign-out is served, and sfx-platform's signed-in acceptance (2026-10-31) passed against
      # sfx-api-test. No run id is kept.

    @status:installed
    @capability:revoke-api-session
    @provider:sql-database-reader
    Scenario: sfx-identity's answer is passed on as JSON
      When sql-database-reader answers the procedure's value
      Then revoke-api-session answers the value parsed as JSON when it is text, the value when it is an object, and the
        reader's whole result otherwise
      # sej/revoke-api-session.sej.json, revoke-api-session-lift.

    @status:installed
    @capability:revoke-api-session
    Scenario: The input names a principal and a session and nothing else
      When revoke-api-session is invoked without principalId or sessionId, or with any other member
      Then its input contract refuses it
      # revoke-api-session-request.v1: required principalId and sessionId, additionalProperties false.

    @status:installed
    @capability:revoke-api-session
    Scenario: A revoked session's open streams end at their next recheck
      Given a session with a run stream or a channel subscription open
      When the session is revoked
      Then each of those streams ends at its next check-api-session recheck
      # check-api-session answers ENDED for a revoked session (check-api-session.feature). The streams end within one
      # session-recheck interval, 5000 ms.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:revoke-api-session
    @provider:sql-database-reader
    Scenario: The revocation honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                     | provider capability the step needs                                         | result it must produce here      | run evidence that proves it                                 |
        | revoke-api-session.revoke | sql-database-reader, in sidefx:capabilities, on sfx-identity-database        | revoke_api_session's value       | the nested execution of sql-database-reader and its outcome |
      When a caller signs out
      Then the call produces the result its binding requires
      And acceptance finds the nested invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet.

  Rule: Signing out keeps its service levels

    @status:not-built
    @capability:revoke-api-session
    @provider:sql-database-reader
    @slo:dispatched-request-latency
    Scenario: Signing out has a latency objective
      Given the service level:
        | SLI                                                             | SLO target                   | baseline |
        | server time on sfx-api-test of POST /sfx/v1/session/logout      | set from its first baseline  | none     |
      When a signed-in caller signs out through the frontdoor
      Then its server time is measured, and its target is set from that measurement
