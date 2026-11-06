@project:sfx-api @approved:2026-11-05
Feature: Read the exact private HTML revision
  @status:unchecked @capability:read-api-content-revision
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: The owner reads a digest-pinned revision
    Given the caller owns the selected HTML address
    When GET /sfx/v1/content/artifacts/{artifactId} selects a revision
    Then the original byte length, SHA-256 and UTF-8 encoding are verified
    And offline inspection returns the title, language and dependency manifest
    And unresolved dependencies are explicit
    And no script or network request is executed by inspection
    And private delivery and publication availability are stated separately

  @status:unchecked @capability:read-api-content-revision
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: Another principal cannot read the revision
    Given the selected address is not owned by the caller
    When the revision is read
    Then no metadata or bytes are returned and HTTP 404 is explicit
