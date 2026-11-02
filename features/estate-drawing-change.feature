# DRAFT for owner approval, 2026-11-01. Nothing in this feature is built until it is approved.
# Source: sfx-api issue #7 (sfx-platform, 2026-11-02). Related: #2.
# @decision marks a scenario that needs the owner's decision; its description holds the user stories.

Feature: A circuit's drawing change is published on the Estate stream
  When a committed change alters a circuit's drawing, the estate live observation channel carries a small, typed
  drawing-change record with the circuit's identity and its new presentationDigest, so that an open Estate view
  redraws it with one scenario read, without a run, a timer or a manual refresh in the client.

  User story: As someone watching the estate in Estate, I want a circuit I am looking at to redraw when its
  declaration changes, so that I see the estate as it is now, even if nobody runs that capability again.

  How it emerged: the platform reuses a drawing until a run admission reports a new authority revision
  (sfx-platform live-circuit/circuit/circuit-scene.js). A committed edit that no run follows is never seen. The
  estate already knows when anything commits: declaration_generation, SQL Server change tracking on the 50 tables
  definitions are read from (sfx-embody sql/migrations/declare-declaration-generation.sql), moves on every committed
  write by any writer and never on a rolled-back one. presentationDigest is the SHA-256 of the drawing that
  read-live-scenario-circuit renders, so a new digest is known only by reading the drawing again.

  Declared, in the estate:
    - read-estate-drawing-changes: given the generation last seen, answers the current generation and, for each
      circuit whose drawing may have changed since, its estate, namespace, capability, scenario, whether it is the
      default selection, and its presentationDigest read through read-live-scenario-circuit.
    - publish-estate-live-observation, re-declared: frames a drawing change as a record of kind drawing-change with
      no run, and no effect on the run windows.
  The facade, transport only: it invokes read-estate-drawing-changes at the interval the host data declares, keeps
  the generation it answered as an opaque cursor, and appends each change it answered to the channel.

  Background:
    Given the estate host https://sfx-api-test.azurewebsites.net
    And a signed-in subscriber on GET /sfx/v1/estate-execution/stream

  # The decisions

  @decision
  Scenario: A commit is noticed by the estate's generation, from any writer
    User story (recommended): As the owner, I want every committed drawing change announced, whoever committed it, so
    that Estate never shows a stale drawing because the edit came from a migration, another host or a local kernel
    instead of an API run.

    Benefit: the generation already moves on every commit and only on a commit, so nothing is missed and nothing is
    announced for a rolled-back write. Reading it is one cheap query.

    The option kept open: notice only the changes committed by runs this host executes. That needs no interval, but
    misses every other writer.

    How it stays configurable: the interval is host data (default 2 seconds), and the generation read is declared.

    When a write that changes a circuit's drawing commits
    Then the change is announced within the declared interval plus the time to read the drawing again

  @decision
  Scenario: Only the circuits the commit can have changed are read again
    User story (recommended): As the owner, I want a commit to cost reading only the drawings it can have changed, so
    that announcing changes stays cheap however large the estate grows.

    Benefit: the change tables name the rows each commit changed; read-estate-drawing-changes maps them to the
    capabilities whose declarations changed and to every capability whose circuit references a changed declaration
    (port, provider, contract, mechanic or scenario), then reads only those drawings. Reading every drawing again
    takes seconds per circuit across hundreds of circuits.

    The option kept open: a changed presentation procedure changes every drawing; it is announced by re-reading every
    circuit once, as a declared full pass.

    How it stays configurable: the mapping is the declared reader's statement, re-declared like any other.

    When a commit changes one capability's declaration
    Then that capability's drawings are read again, and those of the circuits that reference it
    And no other drawing is read

  # What is published

  Scenario: The record is small and typed
    Then a drawing change is a channel record of kind drawing-change, with no runId
    And its payload is estate-drawing-change.v1 {estateId, namespaceId, capabilityId, scenarioId, defaultSelection, presentationDigest, generation}
    And it carries no drawing and no run evidence, and no run is admitted for it

  Scenario: The default selection and explicit selections are covered
    When a commit changes a capability's drawing
    Then a drawing-change record is published for its root scenario with defaultSelection true
    And one for each other scenario of the capability whose drawing changed, with defaultSelection false

  Scenario: The advertised digest is the one a scenario read returns
    When a subscriber receives a drawing-change record
    Then GET /sfx/v1/circuits/{capabilityId}/scenario for that selection returns the record's presentationDigest
    And that holds through the API's declared read cache when the cache is served

  Scenario: A subscriber can tell an unchanged drawing
    When a commit leaves a read drawing's presentationDigest as it was
    Then its record carries the same digest the subscriber already holds, so the subscriber reads nothing

  Scenario: A missed change is recovered on reconnect
    Given a subscriber that disconnected before a drawing-change record
    When it reconnects with since set to the cursor before that record
    Then the same record is replayed, in order, as every other record is

  Scenario: The stream's authorization is unchanged
    Then drawing-change records reach the signed-in subscribers that every other record reaches, and no one else

  # Proof on sfx-api-test, as issue #7 asks

  Scenario: Accepted on staging
    Given an acceptance capability subscribed with a bound (estate-live-observation-bounded-subscription.feature)
    And one operational circuit's presentationDigest read through the scenario GET
    When one edit that changes that circuit's drawing is committed
    Then the acceptance capability receives its drawing-change record with the new digest
    And one scenario GET returns that new digest
    And a subscription resumed from the cursor before the record receives the same record
    And the circuit identity, both digests, the cursor and the record's shape are attached to issue #7
