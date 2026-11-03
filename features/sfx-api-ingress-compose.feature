# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-api-ingress-compose-port.v2 (provider
# sfx-api-ingress-compose.v2), written as Gherkin. The host's bundle binds it under that identity through the host's own declared
# providers (SDA D15); until the image that carries the bundle replaces the host now serving, the estate's copy
# serves as sfx-api-ingress-compose-port.v1 (provider sfx-api-ingress-compose). It writes the raw HTTP/1.1 response serve-http-request answers. The sources
# are the provider's declared program (providers/sfx-api-ingress.dependency.json, operation compose-response), the
# estate's declaration of it (DEPENDENCY sidefx:dependencies/sfx-api-ingress, definition 39ffb87e, read on 2026-11-03
# through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), the capability that binds it
# (serve-http-request) and README.md, Verified.
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
#   reasons              the status-to-reason-phrase map serve-http-request's shape stage declares and hands the provider
#   bundle               the host's own declarations, pinned in this repo (answer-host-declared-read.feature)

@project:sfx-api
@status:proposed-for-review
Feature: Every HTTP response is written by a declared provider, not by the facade
  As the owner
  I want the raw response of each request written by a declared provider capability
  So that the hosting facade writes what it is handed and composes no response of its own

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: A response is written whole, as declared

    @status:probed
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: A response is written with its status line, its headers and its body
      Given serve-http-request hands the provider a status, the reasons, a content type and a body
      When the provider writes the response
      Then it is "HTTP/1.1 <status> <reason>" followed by these headers, in this order:
        | header         | value                                    |
        | Content-Type   | the content type                         |
        | Content-Length | the number of UTF-8 bytes of the body    |
        | Cache-Control  | no-store                                 |
        | Connection     | close                                    |
      And then an empty line and the body
      # README.md, Verified: "Every answer carried Content-Type: application/json; charset=utf-8, Connection: close and a
      # Content-Length equal to its body's bytes."

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: The reason phrase is the one declared for the status
      Given the reasons serve-http-request declares
      When the provider writes a response of a status the reasons name
      Then the status line carries that reason
      # The program reads the reason from reasons at the status's text.

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: A status the reasons do not name is written with an empty reason
      When the provider writes a response of a status the reasons do not name
      Then the status line is "HTTP/1.1 <status> " with nothing after the space
      # Read from the program, not run. The reasons are serve-http-request's to declare in full.

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: A body is written as JSON text, or as it is when it is text
      When the body is an object or an array
      Then the provider writes it as JSON text
      But a body that is text is written as it is
      # The body parameter's encoding is json-text.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: The step that writes a response honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                       | provider capability the step needs                                                                | result it must produce here | run evidence that proves it                                     |
        | serve-http-request.respond  | sfx-api-ingress-compose-port.v2, provider sfx-api-ingress-compose.v2, port serve-http-request-respond | the raw HTTP/1.1 response   | the delivery's testimony for the cell of serve-http-request.respond |
      When a request is served
      Then the call produces the response its binding requires
      And acceptance finds the invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet. The port is as the estate declares it today (run 4d1c2e4f).

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a required call
      Given the accepted binding of serve-http-request.respond to sfx-api-ingress-compose-port.v2
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for serve-http-request.respond and identifies the missing or conflicting evidence

      Examples:
        | defect                                                         |
        | a provider tag differing from the binding only in case         |
        | a step whose port binds another platform capability            |
        | a program other than the one the host's bundle carries         |
        | a response written by the facade instead of the provider       |
        | an evidence gap that prevents attribution of the call          |

  Rule: The provider is declared up to the profile schema boundary

    @status:installed
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-api-ingress.dependency.json declares the compose-response program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And a kernel of a runtime the dependency declares no program for does not run the provider
      # Today the dependency declares csharp, and the host's kernel is the linux-x64 install named in sfx-api.config.json.
      # SDA's Python runtime refuses an undeclared language with PROVIDER_LANGUAGE_UNAVAILABLE
      # (adapters/declared_provider_operation.py:273-276 at SDA bcbdbec).

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: The host runs the program its own bundle carries
      When serve-http-request is answered from the host's bundle
      Then its port binding carries this repo's compose-response program
      And no change to the estate's declaration of sfx-api-ingress-compose changes what the host runs
      # Today the program comes with serve-http-request's declaration from the estate (definition 39ffb87e).
      # answer-host-declared-read.feature.
      # The delivery's run capability, the estate's run-declared-graph, binds each mechanic through its execute port's
      # overlayBindings and providers, which hold the estate's copy of this program (run c9be6b42). The host's own
      # binding waits on SDA: docs/request-sda-host-provider-bindings.md.

  Rule: Writing the response keeps the frontdoor's service levels

    @status:proven
    @capability:serve-http-request
    @provider:sfx-api-ingress-compose-port.v2
    @slo:frontdoor-warm-latency
    Scenario: Every response is written within the frontdoor's latency objective
      When serve-http-request writes each response through this provider
      Then the frontdoor's server time meets frontdoor-warm-latency: p50 at most 0.88 s and p95 at most 3.35 s on
        sfx-api-test
      # docs/azure-test-2026-10-31.md: this provider wrote each of the 30 responses measured. Its own step time is not
      # recorded: frontdoor-tail-explained (host-facade.feature).
