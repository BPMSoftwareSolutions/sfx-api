@project:sfx-api @approved:2026-11-05
Feature: Publish bounded document rendering profiles
  @status:unchecked @capability:sfx-api-content-projection
  Scenario: Static documents keep original bytes with JavaScript disabled
    Given an authorized UTF-8 HTML revision
    When offline dependency inspection finishes
    Then article version 1 is selected by default
    And script-dependent behavior is explicitly reported as disabled
    And incomplete dependencies prevent full preview availability

  @status:unchecked @capability:sfx-api-content-projection
  Scenario: The retained topology renderer can use only its reviewed script
    Given principal-owned successful producer provenance
    And its renderer identity and digest match the image-owned profile declaration
    And exactly one executable inline script matches the declared script digest
    When the descriptor is projected
    Then interactive-document version 1 names only that script digest
    And an additional or changed executable script cannot inherit that permission
    And isolated delivery enforces the profile using HTTP CSP and sandbox
