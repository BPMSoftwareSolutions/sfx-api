# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of serve-http-request, the declared HTTP ingress of the API, written as Gherkin. The
# hosting facade hands it every raw request and writes back the raw response it answers. The sources are its declaration
# (declarations/07-serve-http-request.dsl; the estate's compiled graph source, read on 2026-11-03 through
# sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), README.md (Declaring, Verified) and
# docs/azure-test-2026-10-31.md.
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
#   raw request          the request line, header block and body as the facade received them, as text

@project:sfx-api
@status:proposed-for-review
Feature: Every raw HTTP request is answered by one declared capability
  As the owner
  I want the facade to hand every raw request to serve-http-request and write back what it answers
  So that reading, routing, answering and writing a request are all declared, and the facade holds only the connection

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

  Rule: A raw request goes in, and a raw response comes out

    @status:probed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    @provider:serve-api-request
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: A request is read, answered by the frontdoor, and written back
      Given the raw text of a request other than a sign-in
      When serve-http-request serves it
      Then the ingress provider reads it, serve-api-request answers it, and the compose provider writes the response
      And serve-http-request answers that raw HTTP/1.1 response as text
      # README.md, Verified: GET /sfx/v1/nope 404, GET /sfx/v1/session without a credential 401, POST /sfx/v1/runs without
      # a credential 401, each with Content-Type, Connection: close and a Content-Length equal to its body's bytes.

    @status:probed
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    @provider:open-api-session
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: POST /sfx/v1/session signs the caller in
      Given the raw text of POST /sfx/v1/session with a login body
      When serve-http-request serves it
      Then it invokes open-api-session with the login, not serve-api-request
      And it answers the sign-in's disposition with these statuses:
        | disposition              | status |
        | AUTHENTICATED            | 200    |
        | AUTHENTICATION_REJECTED  | 401    |
        | THROTTLED                | 429    |
      # serve-http-request-prepare routes exactly POST with segments "", "sfx", "v1", "session"; serve-http-request-shape
      # maps the dispositions. sfx-platform's signed-in acceptance passed against sfx-api-test (README.md, Next 4).

    @status:installed
    @capability:serve-http-request
    Scenario: The input is the raw request as text
      Then serve-http-request's input is serve-http-request-request.v1 {contractId, raw} and its CLI input is text at raw
      # Today the text input is a separate declared change, re-applied after every re-declaration, because a DSL
      # declaration resets the input (README.md, Declaring, step 3). In the bundle it is part of the declaration.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:serve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    @provider:serve-api-request
    @provider:open-api-session
    @provider:sfx-api-ingress-compose-port.v2
    Scenario: Each step of a request honors its binding, proved by the run
      Given these steps depend on these provider bindings:
        | calls                          | provider capability the step needs                                         | result it must produce here      | run evidence that proves it                                        |
        | serve-http-request.ingress     | sfx-api-ingress-resolve-port.v2, provider sfx-api-ingress-resolve.v2         | the request's members            | the delivery's testimony for that cell                             |
        | serve-http-request.frontdoor   | serve-api-request, or open-api-session for POST /sfx/v1/session           | the api-response.v1, or the sign-in's answer | the nested execution and its outcome, in outcome.evidence.authorities |
        | serve-http-request.respond     | sfx-api-ingress-compose-port.v2, provider sfx-api-ingress-compose.v2         | the raw HTTP/1.1 response        | the delivery's testimony for that cell                             |
      When a request is served
      Then each call produces the result its binding requires
      And acceptance finds each invocation attributed to its step within the same delivery
      # Nothing checks provider bindings yet. outcome.evidence.authorities: SDA 60aefbb (D10).

  Rule: Serving a request keeps the API's service levels

    @status:proven
    @capability:serve-http-request
    @slo:frontdoor-warm-latency
    Scenario: A warm request is served within the frontdoor's latency objective
      When a request kernel that has answered a request before serves 30 sequential requests on sfx-api-test
      Then their server time is at most 0.88 s at p50 and 3.35 s at p95
      # docs/azure-test-2026-10-31.md (image f32450fa): every one of them went through serve-http-request.

    @status:proven
    @capability:serve-http-request
    @slo:sign-in-refused-latency
    Scenario: A refused sign-in is answered within its objective
      Given the service level:
        | SLI                                              | SLO target      | baseline                        |
        | server time of a refused sign-in on sfx-api-test | at most 0.47 s  | 0.47 s and 0.46 s (2026-10-31)  |
      When POST /sfx/v1/session with an empty identifier is served
      Then it is answered 400 within 0.47 s of server time
      # docs/azure-test-2026-10-31.md: 400 in 0.47 s (image f32450fa) and 0.46 s (image 26aeb9d). The record does not show
      # which step refused it.
