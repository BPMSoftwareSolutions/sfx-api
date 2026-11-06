@project:sfx-api @approved:2026-11-05
Feature: Prepare bounded content reads from trusted HTTP caller bindings
  @status:unchecked @capability:sfx-api-content-selection
  Scenario: A source read carries only validated selectors
    Given an operation declared in sej/content-api.v1.json
    When the provider prepares its request
    Then the principal comes from the authenticated API caller
    And artifact, digest, collection, revision, limit and cursor are validated
    And a refused selection dispatches only its explicit API refusal
    And no client-supplied principal or arbitrary URL is accepted

  @status:unchecked @capability:sfx-api-content-selection
  @provider:sfx-api-content-receipts @provider:sfx-api-content-retained-reference @provider:sfx-api-content-projection
  Scenario: Nested reads preserve only their own request continuation
    Given generic invocation returns a result without the parent's input fields
    When the declared content providers advance through the read sequence
    Then the selection and previous reads are bound to the HTTP host's unique request ID
    And the request ID and execution path come only from trusted route bindings
    And copies of root input preserve the request continuation
    And equal selectors, graph IDs and principals cannot acquire another request's continuation
    And each stage is consumed once within the request timeout
    And projection or cancellation removes the continuation
    And bounded capacity and timed cleanup limit abandoned requests
