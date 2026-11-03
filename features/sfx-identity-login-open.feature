# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-identity-login-open-port.v2 (provider
# sfx-identity-login-open.v2), written as Gherkin. The host's bundle binds it under that identity through the host's own declared
# providers (SDA D15); until the image that carries the bundle replaces the host now serving, the estate's copy
# serves as sfx-identity-login-open-port.v1 (provider sfx-identity-login-open). It signs a caller in against sfx-identity. The sources are the provider's
# declared program (providers/sfx-identity-login.dependency.json, operation open-session), the estate's declaration of it
# (DEPENDENCY sidefx:dependencies/sfx-identity-login, definition c5d37b8d, read on 2026-11-03 through
# sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), the capability that binds it (open-api-session),
# README.md and docs/finish estate-native sign-in through the declared API.md.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
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
#   attempt              one sign-in as sfx-identity records it: begun by begin_api_login, completed by complete_api_login
#   verifier             the principal's stored Argon2id tag of its password, with its salt
#   bearer               the 32 random bytes a successful sign-in gives the caller as its credential
#   bundle               the host's own declarations, pinned in this repo (answer-host-declared-read.feature)

@project:sfx-api
@status:proposed-for-review
Feature: A caller is signed in by a declared provider, and its secrets meet only inside it
  As the owner
  I want sign-in done by a declared provider capability against sfx-identity
  So that the estate signs callers in with no login host of its own, and no password, verifier or bearer leaves the
    provider except the bearer the caller is given

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: A sign-in is decided by sfx-identity and the declared derivation

    @status:probed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The right password opens a session
      Given a principal of sfx-identity and its password
      When open-api-session signs the caller in
      Then the provider answers AUTHENTICATED with the session id, the principal and the session's expiry
      And the bearer, which is the caller's credential from then on
      # sfx-platform's signed-in acceptance passed against sfx-api-test on 2026-10-31 (README.md, Next 4). No run id is
      # kept in this repo.

    @status:probed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: A wrong password is rejected
      When open-api-session signs a caller in with a password that does not derive the principal's verifier
      Then the provider answers AUTHENTICATION_REJECTED and no session is established
      # README.md, Verified: a refused sign-in, 1.5 s on WSL (0.56 s with the declaration cache) and a median 0.47 s of
      # server time on sfx-api-test.

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: A throttled attempt is refused as THROTTLED
      Given sfx-identity's begin_api_login does not allow the attempt
      When open-api-session signs the caller in
      Then the provider answers THROTTLED and no session is established
      # The program completes every attempt with sfx-identity's allowed flag (complete_api_login). See Q1.

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The password is checked with Argon2id under the declared parameters
      When the provider checks a password
      Then it derives the Argon2id tag of the password's UTF-8 bytes with these parameters:
        | parameter             | value                              |
        | salt                  | the principal's salt               |
        | memory                | 19456 KiB                          |
        | iterations            | 2                                  |
        | degree of parallelism | 1                                  |
        | tag length            | 32 bytes                           |
      And the password matches only when the tag's base64 equals the principal's verifier

  Rule: The derivation runs only on the declared libraries

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The libraries are fetched for each sign-in and loaded only when their digests are the declared ones
      When the provider signs a caller in
      Then it fetches these packages from nuget.org and loads each only when its SHA-256 is the declared one:
        | package                                 | version | SHA-256 (base64)                              |
        | Konscious.Security.Cryptography.Blake2  | 1.1.1   | 11hhi0zt984k0mVN6DD177PNVss7/IntkC1pq6VKUY8=  |
        | Konscious.Security.Cryptography.Argon2  | 1.3.1   | nhocunCPEKTaY1MoTkfRlrPaIDxUSLZKx4NWMNcxhVA=  |
      And a package with any other digest fails the sign-in
      And a sign-in fails when nuget.org cannot be reached
      # These are the libraries the former login host ran (the dependency's release member).

  Rule: The password, the verifier and the bearer meet only inside the provider

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: sfx-identity receives the attempt, the match and the bearer's hash, never a secret
      When the provider signs a caller in
      Then begin_api_login receives the realm, the identifier and the source
      And complete_api_login receives the attempt, whether it was allowed, whether the password matched, and the SHA-256
        of the bearer
      And neither receives the password, the derived tag or the bearer

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The bearer is 32 random bytes, and only its hash is kept
      When the provider mints a bearer
      Then the bearer is 32 bytes from the platform's cryptographic random source
      And sfx-identity keeps only its SHA-256

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: A bearer is answered with every disposition, and only an AUTHENTICATED one names a session
      When the provider answers AUTHENTICATION_REJECTED or THROTTLED
      Then its answer still holds a freshly minted bearer, which sfx-identity has registered to no session
      # The program mints the bearer before it knows the disposition. What reaches the caller is open-api-session's to
      # declare.

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The identity database's connection string reaches the provider through the delivery, never an observation
      Given open-api-session's earlier steps release the sfx-identity connection string from the vault
      When the provider opens its connection with it
      Then no observation of the delivery carries the connection string
      # SDA 870b483 keeps released credentials off the observation channel (issue #2).

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The step that signs a caller in honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                  | provider capability the step needs                                                       | result it must produce here                  | run evidence that proves it                                  |
        | open-api-session.login | sfx-identity-login-open-port.v2, provider sfx-identity-login-open.v2, port open-api-session-login | the disposition, the session and the bearer | the delivery's testimony for the cell of open-api-session.login, without its secrets |
      When a caller signs in
      Then the call produces the result its binding requires
      And acceptance finds the invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet. The port is as the estate declares it today (run 4d1c2e4f).

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a required call
      Given the accepted binding of open-api-session.login to sfx-identity-login-open-port.v2
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for open-api-session.login and identifies the missing or conflicting evidence

      Examples:
        | defect                                                         |
        | a provider tag differing from the binding only in case         |
        | a step whose port binds another platform capability            |
        | a program other than the one the host's bundle carries         |
        | evidence that holds the password, the tag or the bearer        |
        | an evidence gap that prevents attribution of the call          |

  Rule: The provider is declared up to the profile schema boundary

    @status:installed
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-identity-login.dependency.json declares the open-session program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And a kernel of a runtime the dependency declares no program for does not run the provider
      # Today the dependency declares csharp, and the host's kernel is the linux-x64 install named in sfx-api.config.json.
      # SDA's Python runtime refuses an undeclared language with PROVIDER_LANGUAGE_UNAVAILABLE
      # (adapters/declared_provider_operation.py:273-276 at SDA bcbdbec).

    @status:not-built
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    Scenario: The host runs the program its own bundle carries
      When open-api-session is answered from the host's bundle
      Then its port binding carries this repo's open-session program
      And no change to the estate's declaration of sfx-identity-login-open changes what the host runs
      # Today the program comes with open-api-session's declaration from the estate (definition c5d37b8d).
      # answer-host-declared-read.feature.
      # The delivery's run capability, the estate's run-declared-graph, binds each mechanic through its execute port's
      # overlayBindings and providers, which hold the estate's copy of this program (run c9be6b42). The host's own
      # binding waits on SDA: docs/request-sda-host-provider-bindings.md.

  Rule: Sign-in keeps its service levels

    @status:not-built
    @capability:open-api-session
    @provider:sfx-identity-login-open-port.v2
    @slo:sign-in-latency
    Scenario: A sign-in this provider answers has a latency objective
      Given the service level:
        | SLI                                                               | SLO target                  | baseline |
        | server time on sfx-api-test of a sign-in this provider answers    | set from its first baseline | none     |
      When open-api-session signs a caller in through this provider
      Then its server time is measured, and its target is set from that measurement
      # The record measures one refused sign-in, POST /sfx/v1/session with an empty identifier: 400 in 0.47 s and 0.46 s
      # (sign-in-refused-latency, docs/azure-test-2026-10-31.md). It does not show whether that refusal reached this
      # provider. Each attempt this provider answers fetches two packages from nuget.org and derives Argon2id (above).

# Open questions for the team. Each is a place where the record is unclear or pulls two ways.
#
# Q1. A throttled attempt still fetches both packages and derives the Argon2id tag (19456 KiB, 2 passes) before
#     complete_api_login refuses it, because the program cannot skip a step. Throttling exists to bound that work. Should
#     a throttled attempt be refused before the derivation?
