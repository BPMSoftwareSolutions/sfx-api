Feature: Select principal-owned retained HTML receipts
  @approved:2026-11-05 @status:unchecked
  @capability:sfx-api-content-receipts @provider:read-principal-html-receipts
  Scenario: Resolve a retained digest only after principal ownership is established
    Given the request carries the authenticated principal and an exact digest
    And no owned artifact address supplied that digest
    When the declared request asks for retained producer receipts
    Then only successful producer runs admitted for that principal qualify
    And a guessed digest or caller-supplied receipt grants no access
    And collection and artifact selections cannot widen into unrelated retained receipts
    And the response states that nested producer receipt coverage remains incomplete
