@project:sfx-api @approved:2026-11-05
Feature: Deliver original owned HTML bytes in a non-executable API carrier
  @status:unchecked @capability:read-api-content-body
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:sfx-api-content-projection
  Scenario: The selected owner and revision are rechecked on every body read
    Given an authenticated principal and an exact immutable source revision
    When GET /sfx/v1/content/artifacts/{artifactId}/revisions/{revision}/body is read
    Then ownership, digest, length and UTF-8 are checked again
    And content-bytes.v1 carries the original bytes as canonical Base64
    And the privileged API serves JSON rather than executable HTML
    And a mismatch or a body larger than 8 MiB returns an explicit refusal
