Feature: Bind retained source bytes to principal-owned receipt evidence
  @approved:2026-11-05 @status:unchecked
  @capability:sfx-api-content-retained-reference @provider:read-retained-artifact
  Scenario: Read global retained bytes only after resolving the scoped receipt
    Given a declared receipt read has returned one matching authorized source
    When the selected digest and bounded byte length match the request
    Then the byte reader receives only that exact digest
    And projection verifies length, UTF-8 encoding and SHA-256 against the receipt
    And absent or mismatched receipt evidence returns no retained source bytes
