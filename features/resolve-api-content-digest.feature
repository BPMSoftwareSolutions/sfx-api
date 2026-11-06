@project:sfx-api @approved:2026-11-05
Feature: Resolve retained content only through an authorization grant
  @status:unchecked @capability:resolve-api-content-digest
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: An owned address grants access to its exact retained digest
    Given an HTML address owned by the authenticated principal binds the requested digest
    When GET /sfx/v1/content/resolve reads that digest
    Then a retained-digest content-revision.v1 descriptor is returned
    And the descriptor never invents an artifact ID for the retained reference

  @status:unchecked @capability:resolve-api-content-digest
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: A digest without a caller grant reveals nothing
    Given the caller has no source grant for a retained digest
    When that digest is resolved
    Then the API returns HTTP 404 without reading the global byte store by digest alone

  @status:unchecked @capability:resolve-api-content-digest
  @provider:read-principal-html-receipts @provider:read-retained-artifact @provider:sfx-api-content-projection
  Scenario: A successful producer run grants its owner access to the retained page
    Given the authenticated principal owns a completed HTML producer run
    And its successful receipt binds the exact digest and byte length
    When that digest is resolved without an owned artifact address
    Then the receipt authorizes only those retained bytes
    And their reconstructed UTF-8 bytes must match the receipt's SHA-256
