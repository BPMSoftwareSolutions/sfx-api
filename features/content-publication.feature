@project:sfx-api @approved:2026-11-05
Feature: Deliver explicit publication through estate-owned bindings
  @status:unchecked @capability:publish-api-content @capability:update-api-content-publication @capability:withdraw-api-content-publication
  Scenario: A caller publishes one reviewed immutable package
    Given caller-bound source ownership and an eligible existing SITE collection
    When the caller explicitly publishes, updates or withdraws a page
    Then the API verifies original bytes and the exact manifest before the writer
    And the estate writer atomically checks destination permission, path uniqueness and the expected revision
    And an idempotency key resolves to one durable intent and outcome
    And a rejected update preserves the prior publication

  @status:unchecked @capability:read-api-published-content
  Scenario: Anonymous delivery follows only an active publication
    Given an explicitly published immutable revision
    When its canonical public path or a declared dependency is read
    Then the resolver rechecks the active binding without an operator session
    And returns a verified byte carrier without private source or run identifiers
    And withdrawal denies the page and every dependency while retaining private originals

  @status:unchecked @capability:read-api-content-sites @capability:read-api-content-publications @capability:read-api-content-publication @capability:read-api-content-publication-history @capability:read-api-content-publication-request
  Scenario: Management reads remain caller-scoped and perform no admissions
    Given an authenticated caller
    When destinations, publication state, history or a prior write outcome are read
    Then only that caller's authorized records return
    And pagination, missing records and uncertain write outcomes are explicit
