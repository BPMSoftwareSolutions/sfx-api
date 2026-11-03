# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of open-api-session, the sign-in serve-http-request invokes for POST /sfx/v1/session,
# written as Gherkin. The sources are its declaration (declarations/09-open-api-session.dsl; the estate's compiled graph
# source, read on 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), README.md (Next 4,
# Verified) and docs/azure-test-2026-10-31.md.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider capability  a declared capability that a step of another capability binds or invokes
#   provider binding     the declared provider capability a scenario needs, named by its identity, the result it must
#                        produce there, and the run evidence that proves it did
#   provider tag         @provider:<id> names one required provider capability, case for case, by the identity its binding
#                        declares
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   host vault           the sealed vault on the container's persistent /home (durable-credential-vault.feature)

@project:sfx-api
@status:proposed-for-review
Feature: A caller signs in with a password and receives a bearer
  As a caller of the declared API
  I want to sign in with my identifier and password
  So that I hold a bearer for my session

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)
  "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
  strategies" (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The sign-in opens the identity database through the host vault, then the sign-in provider decides

    @status:probed
    @capability:open-api-session
    @provider:sfx-vault-host-read-port.v1
    @provider:sfx-identity-credential-port.v1
    @provider:sfx-vault-reference-carry-port.v1
    @provider:sfx-identity-login-open-port.v2
    Scenario: The right password opens a session and answers the bearer
      Given a login {realm, identifier, sourceKey} and its password
      When open-api-session signs the caller in
      Then the host vault is read, the SFX_IDENTITY_DATABASE credential is opened from it, and the sign-in provider runs
      And the answer is status AUTHENTICATED, tokenType Bearer, the token, sessionId, principalId and expiresAt
      # sfx-platform's signed-in acceptance passed against sfx-api-test on 2026-10-31 (README.md, Next 4). No run id is kept.

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: A refusal is answered as its disposition
      When the sign-in provider answers AUTHENTICATION_REJECTED or THROTTLED
      Then open-api-session answers that disposition as its status, with no token
      # The answer step: only AUTHENTICATED carries tokenType and token. The statuses serve-http-request writes for them:
      # serve-http-request.feature.

    @status:installed
    @capability:open-api-session
    Scenario: The input is a login and a password, and nothing else
      When open-api-session is invoked without login or password, or a login without realm, identifier or sourceKey
      Then its input contract refuses it
      # open-api-session-request.v1, additionalProperties false at both levels.

    @status:installed
    @capability:open-api-session
    @provider:sfx-vault-reference-carry-port.v1
    Scenario: The repo declares the sign-in the estate runs
      Then declarations/09 binds the step open-api-session.open to the provider the live declaration binds
      # The live declaration binds sfx-vault-reference-carry-port.v1 (provider sfx-vault-secret-service-reference-carry).
      # declarations/09 said sfx-vault-reference-open-port.v1 until 2026-11-03, when it was corrected to the live binding.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:open-api-session
    @provider:sfx-vault-host-read-port.v1
    @provider:sfx-identity-credential-port.v1
    @provider:sfx-vault-reference-carry-port.v1
    @provider:sfx-identity-login-open-port.v2
    Scenario: Each step of a sign-in honors its binding, proved by the run
      Given these steps depend on these provider bindings:
        | calls                        | provider capability the step needs                                                        | result it must produce here             | run evidence that proves it                           |
        | open-api-session.vault       | sfx-vault-host-read-port.v1, provider sfx-vault-file-host                                 | the host vault                          | the delivery's testimony for that cell, without secrets |
        | open-api-session.credential  | sfx-identity-credential-port.v1, provider sfx-identity-database-credential               | the SFX_IDENTITY_DATABASE reference     | the delivery's testimony for that cell, without secrets |
        | open-api-session.open        | sfx-vault-reference-carry-port.v1, provider sfx-vault-secret-service-reference-carry      | the opened connection string, released  | the delivery's testimony for that cell, without secrets |
        | open-api-session.login       | sfx-identity-login-open-port.v2, provider sfx-identity-login-open.v2                        | the disposition, session and bearer     | the delivery's testimony for that cell, without secrets |
      When a caller signs in
      Then each call produces the result its binding requires
      And acceptance finds each invocation attributed to its step within the same delivery
      # Nothing checks provider bindings yet. The vault, credential and carry providers are the estate's (their
      # dependencies are not in this repo); the sign-in provider is this repo's (sfx-identity-login-open.feature).

  Rule: Sign-in keeps its service levels

    @status:not-built
    @capability:open-api-session
    @slo:sign-in-latency
    Scenario: A sign-in has a latency objective
      Then a sign-in's server time on sfx-api-test is measured, and its target is set from that measurement
      # The refusal the record measured: sign-in-refused-latency (serve-http-request.feature).
