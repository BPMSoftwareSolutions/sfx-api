# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of verify-password-derivation, which checks the sign-in's password derivation against
# an independent Argon2id test vector, written as Gherkin. The sources are its declaration
# (declarations/10-verify-password-derivation.dsl; the estate's compiled graph source, read on 2026-11-03 through
# sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), docs/finish estate-native sign-in through the declared
# API.md and README.md, Verified.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider binding     the declared provider capability a scenario needs, named by its identity, the result it must
#                        produce there, and the run evidence that proves it did
#   provider tag         @provider:<id> names one required provider capability, case for case, by the identity its binding
#                        declares
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   test vector          a throwaway password and salt, and the Argon2id tag an independent implementation derives from them

@project:sfx-api
@status:proposed-for-review
Feature: The sign-in's password derivation is checked against an independent vector
  As the owner
  I want the declared derivation checked against a tag computed by another implementation
  So that sign-in's Argon2id is known to be the standard one, without signing anyone in

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The vector is the declaration's, and the tag is the provider's

    @status:proven
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v2
    Scenario: The declared derivation matches the vector
      Given the throwaway password, salt and expected tag the vector step declares
      When verify-password-derivation runs with input {}
      Then the derive provider derives the tag
      And the answer is MATCHES because the tag equals the expected base64
      # README.md, Verified: run 0c5c9150, executed by the facade's worker, completed with output MATCHES read back.

    @status:installed
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v2
    Scenario: A different tag is a mismatch, and the tag is shown
      When the derived tag differs from the expected one
      Then the answer is MISMATCH with the derived tag
      # declarations/10, the answer step.

    @status:installed
    @capability:verify-password-derivation
    Scenario: The input holds nothing
      When verify-password-derivation is invoked with any member
      Then its input contract refuses it
      # verify-password-derivation-request.v1: an object with no properties allowed.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v2
    Scenario: The derivation honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                              | provider capability the step needs                                       | result it must produce here | run evidence that proves it                       |
        | verify-password-derivation.derive  | sfx-identity-login-derive-port.v2, provider sfx-identity-login-derive.v2   | the tag                     | the delivery's testimony for that cell            |
      When verify-password-derivation runs
      Then the call produces the tag its binding requires
      # Nothing checks provider bindings yet.
