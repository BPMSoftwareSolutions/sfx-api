# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-identity-login-derive-port.v1 (provider
# sfx-identity-login-derive), written as Gherkin. It derives the Argon2id tag of a password and a salt under the sign-in's
# parameters. The sources are the provider's declared program (providers/sfx-identity-login.dependency.json, operation
# derive-tag), the estate's declaration of it (DEPENDENCY sidefx:dependencies/sfx-identity-login, definition c5d37b8d,
# read on 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), the capability that binds
# it (verify-password-derivation) and README.md, Verified.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate; README.md, Verified, records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider capability  a declared capability that a step of another capability binds; its program is declared in a
#                        DEPENDENCY, one program per runtime language, up to the profile schema boundary
#   provider binding     the declared provider capability a scenario needs, named by its identity, the result it must
#                        produce there, and the run evidence that proves it did
#   provider tag         @provider:<id> names one required provider capability, case for case, by the identity its port
#                        binding declares
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   bundle               the host's own declarations, pinned in this repo (answer-host-declared-read.feature)

@project:sfx-api
@status:proposed-for-review
Feature: A password's Argon2id tag is derived by a declared provider, as sign-in derives it
  As the owner
  I want the sign-in's derivation available as its own declared provider capability
  So that the derivation can be checked against a known vector without signing anyone in

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The tag is derived under the sign-in's parameters

    @status:proven
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: A known password and salt derive the known tag
      Given the password, the base64 salt and the expected tag verify-password-derivation declares
      When verify-password-derivation derives the tag
      Then the provider answers the base64 of the 32-byte Argon2id tag of the password's UTF-8 bytes
      And verify-password-derivation answers MATCHES
      # README.md, Verified: run 0c5c9150 of verify-password-derivation, executed by the facade's worker, completed in the
      # run store with output MATCHES read back.

    @status:installed
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: The parameters are the sign-in's
      When the provider derives a tag
      Then it uses these parameters, as sfx-identity-login-open does:
        | parameter             | value                |
        | salt                  | the salt it is given |
        | memory                | 19456 KiB            |
        | iterations            | 2                    |
        | degree of parallelism | 1                    |
        | tag length            | 32 bytes             |

    @status:installed
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: The libraries are loaded only when their digests are the declared ones
      When the provider derives a tag
      Then it fetches Konscious.Security.Cryptography.Blake2 1.1.1 and Konscious.Security.Cryptography.Argon2 1.3.1 from
        nuget.org and loads each only when its SHA-256 is the declared one
      And a package with any other digest fails the derivation
      # The digests are those of sfx-identity-login-open.feature.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: The step that derives the tag honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                              | provider capability the step needs                                                                          | result it must produce here | run evidence that proves it                                              |
        | verify-password-derivation.derive  | sfx-identity-login-derive-port.v1, provider sfx-identity-login-derive, port verify-password-derivation-derive | the tag                     | the delivery's testimony for the cell of verify-password-derivation.derive |
      When verify-password-derivation runs
      Then the call produces the tag its binding requires
      And acceptance finds the invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet. The port is as the estate declares it today (run 4d1c2e4f).

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a required call
      Given the accepted binding of verify-password-derivation.derive to sfx-identity-login-derive-port.v1
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for verify-password-derivation.derive and identifies the missing or conflicting
        evidence

      Examples:
        | defect                                                         |
        | a provider tag differing from the binding only in case         |
        | a step whose port binds another platform capability            |
        | a program other than the one the host's bundle carries         |
        | MATCHES answered without a derived tag in the delivery         |
        | an evidence gap that prevents attribution of the call          |

  Rule: The provider is declared up to the profile schema boundary

    @status:installed
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-identity-login.dependency.json declares the derive-tag program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And a kernel of a runtime the dependency declares no program for does not run the provider
      # Today the dependency declares csharp, and the host's kernel is the linux-x64 install named in sfx-api.config.json.
      # SDA's Python runtime refuses an undeclared language with PROVIDER_LANGUAGE_UNAVAILABLE
      # (adapters/declared_provider_operation.py:273-276 at SDA bcbdbec).

    @status:not-built
    @capability:verify-password-derivation
    @provider:sfx-identity-login-derive-port.v1
    Scenario: The host runs the program its own bundle carries
      When verify-password-derivation is answered from the host's bundle
      Then its port binding carries this repo's derive-tag program
      And no change to the estate's declaration of sfx-identity-login-derive changes what the host runs
      # Today the program comes with verify-password-derivation's declaration from the estate (definition c5d37b8d).
      # answer-host-declared-read.feature.
