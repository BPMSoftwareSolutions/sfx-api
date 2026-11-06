@project:sfx-api @approved:2026-11-05
Feature: Deliver authorized retained-digest HTML without a synthetic artifact ID
  @status:unchecked @capability:read-api-retained-content-body
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: The body read rechecks the digest grant and selected revision
    Given the authenticated principal has a source grant for a retained digest
    When GET /sfx/v1/content/retained/{contentDigest}/revisions/{revision}/body is read
    Then the selected digest and revision must agree
    And the principal grant is checked before the source bytes are returned
    And content-bytes.v1 carries verified canonical Base64 without executing HTML
