# Canonical feature of read-estate-drawing-changes, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md.
# Sources: sfx-api issue #7 (sfx-platform, 2026-11-02; related: #2); declarations/23-read-estate-drawing-changes.dsl and
# its grant; estate-drawing-change.feature, a draft, built in be754e1 and 94c66c6 before any approval; host/serve.py at
# a57ebba, read from the code and not run; the record estate-live-observation-hosted.feature.

@project:sfx-api
@capability:read-estate-drawing-changes
@binding:sda-declared-read-graph-provider.v1
@issue:7
@status:proposed-for-review
Feature: A circuit's drawing change is published on the channel
  As someone watching the estate in Estate
  I want a circuit I am looking at to redraw when its declaration changes
  So that I see the estate as it is now, even if nobody runs that capability again

  When a committed change alters a circuit's drawing, the channel carries a small, typed drawing-change record with the
  circuit's identity and its new presentationDigest, so that an open Estate view redraws it with one scenario read,
  without a run, a timer or a manual refresh in the client.

  How it emerged: the platform reuses a drawing until a run admission reports a new authority revision (sfx-platform
  live-circuit/circuit/circuit-scene.js), so a committed edit that no run follows is never seen. The estate's
  declaration_generation moves on every committed write by any writer and never on a rolled-back one (sfx-embody
  sql/migrations/declare-declaration-generation.sql). presentationDigest is the SHA-256 of the drawing that
  read-live-scenario-circuit renders, so a new digest is known only by reading the drawing again.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a signed-in subscriber on GET /sfx/v1/estate-execution/stream

  Rule: A committed drawing change is noticed by the estate's generation

    @status:installed
    @finding:misaligned
    Scenario: A commit is noticed by the estate's generation, from any writer
      When a write that changes a circuit's drawing commits
      Then the change is announced within the declared interval plus the time to read the drawing again
      # From estate-drawing-change.feature, where it waited on the owner's decision; built in 94c66c6.

    @status:unchecked
    @finding:misaligned
    Scenario: Only the circuits the commit can have changed are read again
      When a commit changes one capability's declaration
      Then that capability's drawings are read again, and those of the circuits that reference it
      And no other drawing is read
      # From the draft, where it waited on the owner's decision. The mapping is the declared reader's statement
      # (declarations/23); it was not checked against this scenario for this write-up.

  Rule: The drawing-change record is small and typed

    @capability:publish-estate-live-observation
    @status:installed
    @finding:misaligned
    Scenario: The record is small and typed
      Then a drawing change is a channel record of kind drawing-change, with no runId
      And its payload is estate-drawing-change.v1 {estateId, namespaceId, capabilityId, scenarioId, defaultSelection, presentationDigest, generation}
      And it carries no drawing and no run evidence, and no run is admitted for it
      # From the draft; publish-estate-live-observation frames it (declarations/19, built in 94c66c6).

    @status:not-built
    @finding:hidden-authority
    Scenario: Each change is appended as the read answered it
      When read-estate-drawing-changes answers a change
      Then the facade appends the change to the channel as the read answered it
      # host/serve.py:587-590 compose the event themselves: {eventId, at, kind: "drawing.changed", payload}, with eventId
      # urn:sfx-api:drawing-change:<generation>:<namespaceId>:<capabilityId>:<scenarioId> and at the host's clock. The
      # draft says the facade "appends each change it answered". declarations/23 (authored 2026-11-02) answers each
      # change as that event, without at: publish-estate-live-observation takes recordedAt from receivedAt
      # (declarations/19).

    @status:unchecked
    @finding:misaligned
    Scenario: The default selection and explicit selections are covered
      When a commit changes a capability's drawing
      Then a drawing-change record is published for its root scenario with defaultSelection true
      And one for each other scenario of the capability whose drawing changed, with defaultSelection false
      # From the draft.

    @status:unchecked
    @finding:misaligned
    Scenario: The advertised digest is the one a scenario read returns
      When a subscriber receives a drawing-change record
      Then GET /sfx/v1/circuits/{capabilityId}/scenario for that selection returns the record's presentationDigest
      And that holds through the API's declared read cache when the cache is served
      # From the draft.

    @status:unchecked
    @finding:misaligned
    Scenario: A subscriber can tell an unchanged drawing
      When a commit leaves a read drawing's presentationDigest as it was
      Then its record carries the same digest the subscriber already holds, so the subscriber reads nothing
      # From the draft.

    @status:installed
    @finding:misaligned
    Scenario: A missed change is recovered on reconnect
      Given a subscriber that disconnected before a drawing-change record
      When it reconnects with since set to the cursor before that record
      Then the same record is replayed, in order, as every other record is
      # From the draft. A drawing change is a channel record like any other: subscribe-estate-live-observation.feature.

    @status:installed
    @finding:misaligned
    Scenario: The stream's authorization is unchanged
      Then drawing-change records reach the signed-in subscribers that every other record reaches, and no one else
      # From the draft.

  Rule: The facade reads drawing changes at the declared interval and keeps the cursor it was answered

    @status:installed
    @finding:misaligned
    Scenario: The reader starts with the host and reads at the declared interval
      When the host starts
      Then the facade invokes read-estate-drawing-changes with no cursor
      And then again every declared interval, for the declared page of changes
      And it logs one line for each read that moves the generation or reads drawings
      # host/serve.py:575-604. The interval and page are host data today (drawings.intervalMilliseconds 2000, limit 20):
      # read-api-host-configuration.feature.

    @status:installed
    @finding:misaligned
    Scenario: The cursor advances only once every change of a read is framed
      When a read answers changes
      Then the cursor advances only once the channel has framed every one of them, waiting up to the reader's answer
        bound (58 s)
      And otherwise the same read is made again after the interval, and a read that is not settled is followed at once
      # host/serve.py:591-604.

    @status:not-built
    @finding:fallback
    Scenario: A failed read is logged every time and read again at the next interval
      When read-estate-drawing-changes answers anything but READ
      Then the host log names the answer
      And the facade reads again at the next interval
      # host/serve.py:578-585 log the answer only when it differs from the last one.

  Rule: Issue #7 is accepted on sfx-api-test

    @status:unchecked
    @finding:misaligned
    @provider:capture-estate-live-observation
    Scenario: Accepted on staging
      Given an acceptance capability subscribed with a bound (subscribe-estate-live-observation.feature)
      And one operational circuit's presentationDigest read through the scenario GET
      When one edit that changes that circuit's drawing is committed
      Then the acceptance capability receives its drawing-change record with the new digest
      And one scenario GET returns that new digest
      And a subscription resumed from the cursor before the record receives the same record
      And the circuit identity, both digests, the cursor and the record's shape are attached to issue #7
      # From the draft. No acceptance run is cited in this repo.

  Rule: Drawing changes keep their service levels

    @status:installed
    @slo:drawing-poll
    Scenario: Drawing changes are read every 2000 ms, at most 20 at a time
      Given the service level:
        | SLI                                         | SLO target                           | baseline |
        | interval and size of a drawing-change read  | every 2000 ms, at most 20 changes    | declared |
      When the host reads drawing changes
      Then it reads at most 20 changes every 2000 ms
      # sfx-api.config.json drawings.intervalMilliseconds and drawings.limit today; declarations/25 drawings.
