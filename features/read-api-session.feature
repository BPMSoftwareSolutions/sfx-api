# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of read-api-session, the capability GET /sfx/v1/session resolves to, written as
# Gherkin. The sources are its declaration (sej/read-api-session.sej.json; the estate's compiled graph source, read on
# 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), sidefx-api-interface.v1 (operation
# read-session) and README.md, Verified.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   caller               the principal and session the frontdoor resolved from the request's carrier
#                        (serve-api-request.feature)

@project:sfx-api
@status:proposed-for-review
Feature: A signed-in caller reads its own session
  As a signed-in caller of the declared API
  I want to read who the API takes me to be and when my session ends
  So that a client can show the session and renew it in time

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)
  "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
  strategies" (2026-11-03)

  Rule: The session read answers the caller the frontdoor resolved, and reads nothing else

    @status:probed
    @capability:read-api-session
    Scenario: A signed-in caller reads its session
      Given the frontdoor resolved the request's carrier to a user's live session
      When read-api-session answers
      Then it answers status READ with the caller's kind, principalId, sessionId and sessionExpiresAt
      # README.md, Verified: the owner's live session digest resolved through the frontdoor; GET /sfx/v1/session answered
      # 200 with kind user. No run id is kept.

    @status:installed
    @capability:read-api-session
    Scenario: The answer is taken from the resolved caller alone
      When read-api-session answers
      Then it reads no store and invokes no provider
      # sej/read-api-session.sej.json, read-api-session-answer: one object of the input's members. Who the caller is, and
      # a caller with no session (401 CALLER_REQUIRED), are the frontdoor's (serve-api-request.feature).

  Rule: The session read keeps its service levels

    @status:not-built
    @capability:read-api-session
    @slo:dispatched-request-latency
    Scenario: Reading the session has a latency objective
      Given the service level:
        | SLI                                                                     | SLO target                   | baseline |
        | server time on sfx-api-test of GET /sfx/v1/session for a signed-in user | set from its first baseline  | none     |
      When a signed-in caller reads its session through the frontdoor
      Then its server time is measured, and its target is set from that measurement
      # frontdoor-warm-latency measured GET /sfx/v1/session without a credential, which the frontdoor refuses with 401
      # before dispatching (docs/azure-test-2026-10-31.md).
