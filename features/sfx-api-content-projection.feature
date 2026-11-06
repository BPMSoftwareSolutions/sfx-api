@project:sfx-api @approved:2026-11-05
Feature: Project retained content without executing or rewriting it
  @status:unchecked @capability:sfx-api-content-projection
  Scenario: Offline inspection discovers exact package dependencies
    Given verified original bytes and an authorized asset catalog
    When the HTML5 and CSS token parsers inspect the content
    Then recursive stylesheets, escaped URLs and responsive candidates are inspected
    And only referenced catalog entries enter the manifest
    And external requests, missing bytes, path escape and unsupported active elements remain explicit findings
    And scripts are observed but never executed or approved for execution
    And the original bytes remain unchanged

  @status:unchecked @capability:sfx-api-content-projection
  Scenario: Inspection is bounded independently of the request lifetime
    Given the image-pinned parser and its fixed interpreter and program paths
    When the projection invokes inspection
    Then the child has no inherited application environment
    And inspection terminates within 30 seconds or returns an explicit failure
    And input is bounded to 32 MiB, source bytes to 8 MiB and assets to 256
    And output is bounded to 2 MiB
    And a timeout or malformed output is never an empty successful manifest
