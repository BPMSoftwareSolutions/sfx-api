# Delivery authority: sfx-platform/docs/ov3-content/content-delivery-contract.v1.json 1.1.0.
# Owner: "The proposed API bindings look great to me. I approve. Let's go!"
@project:sfx-api @approved:2026-11-05
Feature: Read the signed-in principal's retained HTML library
  @status:unchecked @capability:read-api-content-library
  @provider:sfx-api-content-selection @provider:read-owned-html-source @provider:read-principal-html-receipts @provider:sfx-api-content-projection
  Scenario: An authenticated GET lists immutable HTML summaries without admitting a job
    Given the ingress has resolved a user principal
    When GET /sfx/v1/content/artifacts resolves through the declared interface
    Then the source reader receives that principal from the caller binding
    And at most 100 content-summary.v1 records return in content-library.v1
    And count, cursor and partial family coverage are explicit
    And no POST /runs or producer invocation occurs
    And a summary makes no claim that its dependency manifest was inspected

  @status:unchecked @capability:read-api-content-library @provider:sfx-api-content-selection
  Scenario: A cursor from another principal or collection is refused
    Given the cursor names a different principal or collection scope
    When the list request is prepared
    Then it returns CONTENT_CURSOR_INVALID without a source read

  # Completed root producer receipts join owned addresses. Nested producer
  # receipt coverage remains required; the library therefore reports partial.
