# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-api-ingress-resolve-port.v2 (provider
# sfx-api-ingress-resolve.v2), written as Gherkin. The host's bundle binds it under that identity through the host's own declared
# providers (SDA D15); until the image that carries the bundle replaces the host now serving, the estate's copy
# serves as sfx-api-ingress-resolve-port.v1 (provider sfx-api-ingress-resolve). Every HTTP request the hosting facade receives is read by it. The sources
# are the provider's declared program (providers/sfx-api-ingress.dependency.json, operation resolve-request), the
# estate's declaration of it (DEPENDENCY sidefx:dependencies/sfx-api-ingress, definition a8d6f423, read on 2026-11-03
# through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), the two capabilities that bind it
# (serve-http-request, resolve-http-request) and README.md, Verified.
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
#   carrier              the caller's credential as presented: an Authorization bearer or the __Host-sfx-session cookie
#   bundle               the host's own declarations, pinned in this repo (answer-host-declared-read.feature)

@project:sfx-api
@status:proposed-for-review
Feature: Every HTTP request is read by a declared provider, not by the facade
  As the owner
  I want each raw request read into the members the frontdoor binds by a declared provider capability
  So that the hosting facade parses nothing, and a caller's credential is digested where it is read and goes no further

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The request is read as the facade received it

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: A request is read into the members the frontdoor binds
      Given a raw HTTP/1.1 request as the facade received it: the request line, the header block and the body
      When resolve-http-request reads it
      Then the provider answers method, segments, queryJson, body, carried, sessionDigest, source and headers
      # README.md, Verified: the ingress read through resolve-http-request, 6 of 6 against values computed outside the
      # kernel.

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: Text that is not an HTTP request reads as empty members
      Given text with no request line of the form "<METHOD> /<target> <version>"
      When resolve-http-request reads it
      Then every member is empty and carried is false
      # README.md, Verified: "text that is not HTTP: empty members".

  Rule: The target is decoded once

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The path is decoded before it is split
      Given the target /sfx/v1/runs/a%2Fb
      When resolve-http-request reads the request
      Then segments are "", "sfx", "v1", "runs", "a" and "b"
      # README.md, Verified: "A path segment holding an encoded slash (%2F) is split there: the ingress decodes the path
      # before it splits it."

    @status:installed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario Outline: The query is answered as JSON text, each key and value decoded once
      Given a target whose query is <query>
      When resolve-http-request reads the request
      Then queryJson is <queryJson>
      # The program's query steps. The first row was also probed (README.md, Verified).

      Examples:
        | query                  | queryJson                     |
        | limit=2&cursor=a%20b   | {"limit":"2","cursor":"a b"}  |
        | q=a+b                  | {"q":"a b"}                   |
        | flag                   | {"flag":""}                   |
        | =x&b=1                 | {"b":"1"}                     |
        | q=%22                  | {"q":"\""}                    |
        | q=%5C                  | {"q":"\\"}                    |
        | q=%01                  | {"q":"\u0001"}                |
        | a=1&a=2                | {"a":"1","a":"2"}             |

  Rule: The carrier is digested inside the provider and never answered

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: A bearer is digested twice
      Given the header "Authorization: Bearer <44 base64 characters of 32 bytes>"
      When resolve-http-request reads the request
      Then carried is true
      And sessionDigest is the base64 of SHA-256 of SHA-256 of the 32 bytes
      # README.md, Verified: the digest equals SHA-256 of SHA-256 of the bearer bytes; the formula is checked against SQL
      # Server's (HASHBYTES twice over 32 zero bytes).

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The session cookie is digested the same way
      Given a Cookie header holding __Host-sfx-session=<44 base64 characters of 32 bytes> among other cookies
      When resolve-http-request reads the request
      Then carried is true and sessionDigest is the cookie's digest
      # README.md, Verified: "the session cookie among others: the cookie's digest".

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: A bearer is read before a cookie
      Given a request with both a bearer and a session cookie
      When resolve-http-request reads it
      Then sessionDigest is the bearer's digest
      # README.md, Verified.

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: A malformed or missing carrier is not carried
      Given a bearer that is not 44 base64 characters of 32 bytes, or no carrier
      When resolve-http-request reads the request
      Then carried is false
      And sessionDigest is the digest of no carrier bytes, which names no session
      # README.md, Verified: "a malformed bearer; no carrier: not carried". The program digests the empty carrier rather
      # than answering no digest, so a reader must read carried first.

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The carrier itself is never answered
      When serve-http-request reads a request that carries a bearer or a session cookie
      Then no member of the provider's answer holds the bearer or the cookie's value
      # The program's value members (providers/sfx-api-ingress.dependency.json, resolve-request): the carrier is read and
      # digested inside the one program.

  Rule: The caller's source is read from the request

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The source is X-Client-IP, else the first X-Forwarded-For entry, else empty
      When serve-http-request reads a request
      Then source is the first token of X-Client-IP when the request has it
      And otherwise the first entry of X-Forwarded-For
      And otherwise empty
      # sfx-identity throttles sign-in by this source (begin_api_login, sfx-identity-login-open.feature). See Q1.

  Rule: Only the headers the interface binds are read

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: Idempotency-Key is read, trimmed, and empty when absent
      When resolve-http-request reads a request
      Then headers.idempotency-key is the first Idempotency-Key header's value, its name matched in any case
      And spaces and tabs around the value are dropped, and quotes and backslashes in it are kept
      And it is empty when the request has no Idempotency-Key header, even if a longer header name begins with it
      # README.md, Verified: "the header: the ingress program through the kernel's resolver (present, case, padding,
      # absent, quotes and backslashes, a longer header name)".

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: Last-Event-ID is read the same way
      When serve-http-request reads a request
      Then headers.last-event-id is the first Last-Event-ID header's value, trimmed, and empty when absent
      # This repo's program reads it (open-api-run-stream.feature, subscribe-estate-live-observation.feature). The
      # estate's declared provider, definition a8d6f423, does not; the host gets it only from its bundle (below).

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: No other header reaches the frontdoor
      When serve-http-request reads a request with any other headers
      Then headers holds only the headers the program declares
      # Definition a8d6f423 declares idempotency-key; this repo's program adds last-event-id.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: Each step that reads a request honors its binding, proved by the run
      Given these steps depend on these provider bindings:
        | calls                         | provider capability the step needs                                         | result it must produce here | run evidence that proves it                                    |
        | serve-http-request.ingress    | sfx-api-ingress-resolve-port.v2, provider sfx-api-ingress-resolve.v2, port serve-http-request-ingress    | the request's members       | the delivery's testimony for the cell of serve-http-request.ingress |
        | resolve-http-request.ingress  | sfx-api-ingress-resolve-port.v2, provider sfx-api-ingress-resolve.v2, port resolve-http-request-ingress  | the request's members       | the delivery's outcome, which is that cell's result            |
      When a request is served
      Then each call produces the result its binding requires
      And acceptance finds each invocation attributed to its step within the same delivery
      # Nothing checks provider bindings yet. The ports are as the estate declares them today (run 4d1c2e4f).

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a required call
      Given the accepted binding of serve-http-request.ingress to sfx-api-ingress-resolve-port.v2
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for serve-http-request.ingress and identifies the missing or conflicting evidence

      Examples:
        | defect                                                                      |
        | a provider tag differing from the binding only in case                      |
        | a step whose port binds another platform capability                         |
        | a program other than the one the host's bundle carries                      |
        | the right provider invoked only in another delivery or step                 |
        | a returned value that does not hold the request's members                   |
        | an evidence gap that prevents attribution of the call                       |

  Rule: The provider is declared up to the profile schema boundary

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-api-ingress.dependency.json declares the resolve-request program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And a kernel of a runtime the dependency declares no program for does not run the provider
      # Today the dependency declares csharp, and the host's kernel is the linux-x64 install named in sfx-api.config.json.
      # SDA's Python runtime refuses an undeclared language with PROVIDER_LANGUAGE_UNAVAILABLE
      # (adapters/declared_provider_operation.py:273-276 at SDA bcbdbec).

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The host runs the program its own bundle carries
      When serve-http-request is answered from the host's bundle
      Then its port binding carries this repo's resolve-request program
      And no change to the estate's declaration of sfx-api-ingress-resolve changes what the host runs
      # Today the program the host runs comes with serve-http-request's declaration from the estate (estateProvider in
      # its port binding, definition a8d6f423). answer-host-declared-read.feature.
      # The delivery's run capability, the estate's run-declared-graph, binds each mechanic through its execute port's
      # overlayBindings and providers, which hold the estate's copy of this program (run c9be6b42). The host's own
      # binding waits on SDA: docs/request-sda-host-provider-bindings.md.

  Rule: Reading the request keeps the frontdoor's service levels

    @status:proven
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    @slo:frontdoor-warm-latency
    Scenario: Every request is read within the frontdoor's latency objective
      Given the service level:
        | SLI                                                                            | SLO target                              | baseline                                  |
        | server time of a warm request on sfx-api-test, this provider's read included  | p50 at most 0.88 s, p95 at most 3.35 s  | p50 0.88 s, p95 3.35 s (image f32450fa)   |
      When serve-http-request reads each request through this provider
      Then the frontdoor's server time meets the target
      # docs/azure-test-2026-10-31.md: this provider read each of the 30 requests measured. Its own step time is not
      # recorded: frontdoor-tail-explained (host-facade.feature).

# Open questions for the team. Each is a place where the record is unclear or pulls two ways.
#
# Q1. source takes X-Client-IP, else X-Forwarded-For, as the request carries them, and sfx-identity throttles sign-in by
#     source. The record does not say whether App Service replaces a caller's own X-Client-IP. Should source come only
#     from a header App Service sets?
