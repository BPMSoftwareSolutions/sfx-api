# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-api-run-trace-encode-port.v1 (provider
# sfx-api-run-trace-encode), written as Gherkin. It encodes each chunk of a run's events as the run store's trace chunk.
# The sources are the provider's declared program (providers/sfx-api-run-trace.dependency.json, operation encode-chunk),
# the estate's declaration of it (DEPENDENCY sidefx:dependencies/sfx-api-run-trace, definition da5ee4ad, declared by run
# 310be6b8 and read on 2026-11-03 through sql-database-reader, run 4d1c2e4f-db9b-ae32-f716-377c0a781c08), the capability
# that binds it (append-api-run-trace) and README.md, Verified.
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
#   chunk                a contiguous run of a run's events, from firstCursor to lastCursor
#   bundle               the host's own declarations, pinned in this repo (answer-host-declared-read.feature)

@project:sfx-api
@status:proposed-for-review
Feature: A run's trace is encoded by a declared provider, as the run store's other writers encode it
  As the owner
  I want each chunk of a run's events encoded by a declared provider capability
  So that the trace the host retains reads back with every decoder of the run store, and the facade encodes nothing

  The owner's directions (features/README.md, "The owner's direction"):
  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: A chunk of events is encoded as the run store's trace chunk

    @status:proven
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: A chunk is encoded, and it reads back as the events that were streamed
      Given a chunk of a run's events with its runId, firstCursor, lastCursor and recordCount
      When append-api-run-trace encodes the chunk
      Then content is the events as one JSON array, in UTF-8, brotli-compressed, as base64
      And digest is the SHA-256 of content, as base64
      And runId, firstCursor, lastCursor and recordCount are answered as given
      # README.md, Verified: run f8a01553, executed by the facade, retained as 4 chunks to cursor 43; its 43 events were
      # read back by the legacy decoder identical to the stream.

    @status:probed
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: Every decoder of the run store reads the chunk
      When a chunk the provider encoded is decoded by .NET's brotli decoder and by the legacy evidence store's decoder
      Then both read the same events
      # README.md, Verified: "encode-chunk through the kernel's own resolver, decoded by .NET and by the legacy evidence
      # store's decoder".

    @status:not-built
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: The compression level is declared by its meaning
      Then the program names the brotli compression level the trace is written at in words every runtime reads alike
      # Finding: the program passes the number 0 to System.IO.Compression.BrotliStream, which .NET binds to
      # CompressionLevel.Optimal. A runtime that reads 0 as a brotli quality would compress at quality 0. The chunk still
      # decodes, and its digest is of what was written.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: The step that encodes a chunk honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                        | provider capability the step needs                                                                      | result it must produce here | run evidence that proves it                                        |
        | append-api-run-trace.encode  | sfx-api-run-trace-encode-port.v1, provider sfx-api-run-trace-encode, port append-api-run-trace-encode   | the encoded chunk           | the delivery's testimony for the cell of append-api-run-trace.encode |
      When a run's trace is retained
      Then each call produces the chunk its binding requires
      And acceptance finds each invocation attributed to that step within the same delivery
      # Nothing checks provider bindings yet. The port is as the estate declares it today (run 4d1c2e4f).

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a required call
      Given the accepted binding of append-api-run-trace.encode to sfx-api-run-trace-encode-port.v1
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for append-api-run-trace.encode and identifies the missing or conflicting evidence

      Examples:
        | defect                                                         |
        | a provider tag differing from the binding only in case         |
        | a step whose port binds another platform capability            |
        | a program other than the one the host's bundle carries         |
        | a chunk encoded by the facade instead of the provider          |
        | an evidence gap that prevents attribution of the call          |

  Rule: The provider is declared up to the profile schema boundary

    @status:installed
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-api-run-trace.dependency.json declares the encode-chunk program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And a kernel of a runtime the dependency declares no program for does not run the provider
      # Today the dependency declares csharp, and the host's kernel is the linux-x64 install named in sfx-api.config.json.
      # SDA's Python runtime refuses an undeclared language with PROVIDER_LANGUAGE_UNAVAILABLE
      # (adapters/declared_provider_operation.py:273-276 at SDA bcbdbec).

    @status:not-built
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    Scenario: The host runs the program its own bundle carries
      When append-api-run-trace is answered from the host's bundle
      Then its port binding carries this repo's encode-chunk program
      And no change to the estate's declaration of sfx-api-run-trace-encode changes what the host runs
      # Today the program comes with append-api-run-trace's declaration from the estate (definition da5ee4ad).
      # answer-host-declared-read.feature.

  Rule: The trace is encoded in bounded chunks

    @status:proven
    @capability:append-api-run-trace
    @provider:sfx-api-run-trace-encode-port.v1
    @slo:trace-chunk
    Scenario: A chunk holds at most 2000 events and 524288 bytes of events
      Given the service level:
        | SLI                               | SLO target                                          | baseline      |
        | events and bytes per trace chunk  | at most 2000 events and 524288 bytes of their JSON  | run f8a01553  |
      When append-api-run-trace hands the provider a chunk
      Then the chunk holds at most 2000 events, whose compact JSON totals at most 524288 bytes
      But an event larger than 524288 bytes on its own is a chunk of its own
      # host/serve.py chunks(), from traceChunkEvents and traceChunkBytes (sfx-api.config.json; declarations/25 runs.trace).
      # Run f8a01553 was retained as 4 chunks to cursor 43 (README.md, Verified).
