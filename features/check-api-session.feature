# Canonical feature of check-api-session, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: declarations/15-check-api-session.dsl; sidefx-api-interface.v1 callers.user; host/serve.py at a57ebba, read
# from the code and not run; the record api-runs-hosted.feature it replaces in part.

@project:sfx-api
@capability:check-api-session
@provider:sql-database-reader
@status:proposed-for-review
Feature: An open stream ends when its session can no longer be confirmed
  As the owner of the estate
  I want every open stream of a session caller rechecked as the interface declares
  So that a revoked or expired session stops receiving the estate within the declared interval

  Rule: A stream's session is rechecked at the declared interval

    @status:installed
    Scenario: A session caller's stream is rechecked at the interval its directive declares
      Given a session caller's open run stream or channel subscription
      Then the facade invokes check-api-session at the interval the stream directive's recheck declares
      # sidefx-api-interface.v1 declares callers.user.sessionRecheckMilliseconds 5000; host/serve.py:357-379.

    @status:installed
    Scenario: Anything but LIVE ends the stream
      When check-api-session answers anything but LIVE, or its delivery fails
      Then the stream ends
      # host/serve.py:357-379. The frame it ends with: open-api-run-stream.feature and
      # subscribe-estate-live-observation.feature.

    @status:not-built
    @finding:hidden-authority
    Scenario: Whether streams share a recheck is declared
      Then whether streams with the same recheck input share one answer for one interval is declared with the recheck
      # host/serve.py:357-379 share it on their own: one answer serves every stream with the same input until the
      # interval passes. The interface declares the interval, not the sharing. declarations/12 and 21 now declare
      # recheck.shared true with the recheck.
