# Implementation installed in hosted-v4-b. Provider tests cover process death and UNKNOWN recovery.
# Live evidence: docs/hosted-execution-v4-2026-11-04/README.md; complete T1-T7 acceptance is still pending.
@component:sfx-api-host
Feature: Retain hosted execution attempts through declared host providers
  The request coordinator holds one deployment-wide admission and retains only
  non-secret evidence on the persistent host mount.

  @status:installed
  @capability:accept-hosted-execution-profile
  @provider:sfx-api-host-http-request-port.v1
  @provider:sfx-api-host-acceptance-record-port.v1
  Scenario: One provider owns admission until its terminal evidence is durable
    Given the profile binds the operator, probe principal, record path and provider module
    When the authenticated request invokes the coordinator
    Then the provider checks its actual kernel execution path and trusted context before releasing a secret
    And the shared record path supplies an exclusive operating-system file lock across request kernels and instances
    And a competing request returns ACCEPTANCE_BUSY without releasing the probe credential
    And the record provider flushes the RUNNING attempt before the first probe
    And the coordinator evaluates observations through its declared receipt expression
    And full schema and cross-field validation precede the terminal record
    And the record provider flushes the exact terminal response bytes before the response is returned
    And every normal, failed, cancelled or killed coordinator releases admission ownership

  @status:installed
  @capability:read-hosted-execution-acceptance
  @provider:sfx-api-host-acceptance-record-port.v1
  Scenario: Readback preserves uncertainty across a process restart
    Given a retained RUNNING attempt survives its owning process
    When the pinned operator reads that attempt after its lock is released
    Then the record is UNKNOWN and never replayed
    And a terminal receipt retains its exact bytes, length, digest and identities
    And the read opens neither a vault credential nor another run

  @status:installed
  @capability:serve-http-request
  @provider:sfx-api-ingress-resolve-port.v2
  Scenario: The HTTP admission identity is separate from caller input
    Given the facade admits one raw HTTP request to one resident kernel
    Then it assigns that admission a requestExecutionId outside the raw request bytes
    And the declared ingress carries that identity to the authenticated interface
    And case-insensitive duplicate correlation or profile headers are rejected
    And the evaluator preserves that admission identity rather than minting an execution UUID
