# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of resolve-http-request, which reads a raw request the way the API ingress reads it,
# without serving it, written as Gherkin. The sources are its declaration (declarations/08-resolve-http-request.dsl; the
# estate's compiled graph source, read on 2026-11-03 through sql-database-reader, run
# 4d1c2e4f-db9b-ae32-f716-377c0a781c08) and README.md, Verified.
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

@project:sfx-api
@status:proposed-for-review
Feature: A raw request can be read as the ingress reads it, without serving it
  As the owner
  I want to see what the API ingress reads from a raw request
  So that the ingress can be checked against known requests without answering them

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The read is the ingress provider's, answered as it is

    @status:probed
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: A raw request is answered as the ingress reads it
      Given the raw text of a request in resolve-http-request-request.v1 {contractId, raw}
      When resolve-http-request reads it
      Then it answers the ingress provider's members for that request, and serves nothing
      # README.md, Verified: 6 of 6 against values computed outside the kernel. What each member holds:
      # sfx-api-ingress-resolve.feature.

    @status:installed
    @capability:resolve-http-request
    Scenario: The input is a raw request and nothing else
      When resolve-http-request is invoked without raw, or with any member but contractId and raw
      Then its input contract refuses it

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:resolve-http-request
    @provider:sfx-api-ingress-resolve-port.v2
    Scenario: The read honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                         | provider capability the step needs                                  | result it must produce here | run evidence that proves it                 |
        | resolve-http-request.ingress  | sfx-api-ingress-resolve-port.v2, provider sfx-api-ingress-resolve.v2  | the request's members       | the delivery's outcome, that cell's result  |
      When a raw request is read
      Then the call produces the result its binding requires
      # Nothing checks provider bindings yet.
