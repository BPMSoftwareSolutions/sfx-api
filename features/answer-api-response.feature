# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of answer-api-response, the capability that answers an API response as it is given,
# written as Gherkin. serve-http-request, serve-api-request and admit-api-run invoke it. The sources are its declaration
# (declarations/03-serve-api-request.sql and sej/answer-api-response.sej.json; the estate's compiled graph source, read
# on 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08) and README.md, Verified.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
#   @status:installed      the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   api-response.v1      {contractId: "api-response.v1", status: <integer>, contentType?, body?}: the answer the
#                        frontdoor composes for every request

@project:sfx-api
@status:proposed-for-review
Feature: An API response is answered exactly as it is given
  As the owner
  I want one declared capability that answers an api-response.v1 unchanged
  So that a capability that has composed its response can end with it, without a response rule of its own

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "We need all the behavior accounted for in .feature files." (2026-11-02)

  Rule: The response is answered unchanged

    @status:installed
    @capability:answer-api-response
    Scenario: An api-response.v1 is answered as it is given
      Given an api-response.v1 with an integer status
      When answer-api-response answers it
      Then its answer is the input, unchanged
      # sej/answer-api-response.sej.json: the expression {"op":"path","path":""}.

    @status:installed
    @capability:answer-api-response
    Scenario: Anything but an api-response.v1 is refused
      When answer-api-response is invoked without contractId "api-response.v1" or without an integer status
      Then its input contract refuses it
      # answer-api-response-request.v1: required contractId (const api-response.v1) and status (integer).

  Rule: Answering a response keeps the frontdoor's service levels

    @status:probed
    @capability:answer-api-response
    @slo:warm-definitions
    Scenario: Its definition is not read again in a warm envelope
      When a warm envelope ends a request with answer-api-response
      Then the kernel resolves answer-api-response without reading its definition again
      # README.md, Verified: a warm GET /sfx/v1/nope read the definitions of five capabilities, answer-api-response among
      # them, before the declaration cache, and none after it.
