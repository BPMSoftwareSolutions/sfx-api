# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of answer-host-declared-read, the host's declared-read provider, written as Gherkin. It
# is the provider capability the host binds to SDA's sda-kernel-declared-read-port.v1. It answers the kernel's reads of
# the host's own declarations from the host's pinned bundle, and passes every other read to the delivery's own estate
# session. It replaces host-declared-read-provider.feature. The sources are SDA 93a7a56 (docs/request-host-selected-
# declared-read-provider.md; rules D1-D8 in kernel/semantic-authority/execution/declared-read-port.semantic-authority.json;
# ADR-0020 as rewritten), SDA bcbdbec (rule D9, the pass-through to the delivery's own session), SDA 2f0b9b4, which reverted
# cd4fcf5's kernel-owned bundle, and the estate's declared reads (the boot data-access authority
# sda-kernel-boot-data-access.v1, read on 2026-11-03 through sql-database-reader, run 343ae7d4-289f-a4d7-ba32-2126393631d4).
# Kernel source lines are at SDA bcbdbec.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:installed      SDA or the estate does this today (read from the installed definition, not from a run)
#   @status:not-built      the owner's direction requires it; nothing implements it yet
#
# Terms:
#   provider capability  a declared capability that a port binds; it is declared up to the profile schema boundary, and
#                        the host writes no provider code
#   provider binding     the declared provider capability a scenario needs, named by its identity, the result it must
#                        produce there, and the run evidence that proves it did
#   provider tag         @provider:<id> names one required provider capability, case for case, by the identity its binding
#                        declares
#   capability tag       @capability:<id> identifies the entry capability under test. Provider dependencies have their
#                        own tags.
#   declared read        one read the kernel makes for a delivery, sent to the bound provider as declared-read-request.v1
#                        {readId, input, options} and answered as declared-read-result.v1 {recordsets, snapshotId,
#                        projectionDigest, viewDefinitionDigest}
#   owned capability     a capability the bundle's manifest lists: one the host serves and this repo declares
#   bundle               the host's own declarations in SEJ, kept in this repo under authorities/host-bundle/ and pinned
#   pin                  the SHA-256 digest of the bundle's manifest, held in the provider's binding
#   builtInRead          the kernel's built-in read on the delivery's own session, pin and impersonation (SDA D9); it is
#                        the kernel's, not a declared capability

@project:sfx-api
@status:proposed-for-review
Feature: The host's own declarations are answered from its pinned bundle, by a declared provider
  As the owner
  I want the host's own declarations kept in this repo, pinned, and answered to the kernel by a declared provider
  So that the estate's front door does not take its own definition from the estate it serves

  The owner's directions (features/README.md, "The owner's direction"):
  "I think the smart thing to do is to not make the serve.py apart of the estate. We don't circular hosting. The estate
  is for the consumer so that means the consumer can own the host in its estate. However, we do have the ability to
  declare the capabilities in SEJ (semantic executable JSON), and keep them in this repo. The SEJ can be resolved by the
  kernel without being apart of the estate." (2026-11-02)
  "Remember, there was JSON in SDA Kernel before estate database." (2026-11-02)
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: The provider is declared, and the kernel sends it every declared read

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The provider is a declared capability, bound at the profile schema boundary
      Then answer-host-declared-read is declared in SEJ in this repo
      And the host's provider authority binds sda-kernel-declared-read-port.v1 with one eventPorts entry: SDA's generic
        capability-invocation provider in its configured form, with answer-host-declared-read's graph source as the
        entry's configuration
      And the host writes no provider code in any runtime language
      # SDA 1bd400e, D12 and D13: the kernel passes the entry's configuration to the provider unchanged, and the configured
      # form (InvokeConfiguredCapability in C#) runs the graph source, with the read request as its input, through the
      # delivery's run capability, on the delivery's data access without the port. A host provider module was written on
      # 2026-11-03 and removed the same day: "providers are declared capabilities as well."
      # Declared in providers/host-provider-authority.json. Run locally on 2026-11-03 against the estate, kernel b6872d49
      # (SDA 1bd400e): the delivery's first read failed PLATFORM_MECHANIC_NOT_DECLARED:execute-declared-capability:
      # read-execution-capability-authority, because the estate's execution-delivery names the delivery wrapper, not a
      # graph runner. With no provider bound, the same kernel answered verify-password-derivation MATCHES. Waits on SDA:
      # docs/request-sda-host-provider-bindings.md.

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: The host's own provider bindings come from the host
      When the delivery's run capability realizes answer-host-declared-read or a capability the bundle owns
      Then its mechanics are bound by the overlay rules and provider entries the host declares, for the host's own
        mechanics: the bundle-read provider, the built-in read step and the host's five providers
      And the estate's run capability keeps every other rule unchanged
      # The estate's run-declared-graph binds each mechanic from its execute port's overlayBindings (110 rules) and
      # providers (61 entries), the host's five among them as the estate declares them, and has no rule for
      # sfx-api-host-bundle-read-port.v1 or sda-kernel-built-in-read.v1 (run c9be6b42; SDA 1bd400e,
      # SemanticExecutionGraphExecutionProvider.cs ResolvePlan). Waits on SDA: docs/request-sda-host-provider-bindings.md.
      # SDA D15 (working tree after 1bd400e) lets the host's provider authority declare overlayBindings and
      # declaredProviders. providers/host-provider-authority.json declares the bundle reader and the host's five
      # providers under v2 identities; D14 now realizes the built-in read step from SDA's own registry.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: Every declared read of a delivery reaches the provider
      Given the host's provider authority binds sda-kernel-declared-read-port.v1 to answer-host-declared-read
      When a kernel carries any delivery
      Then each of its declared reads reaches the provider as declared-read-request.v1
      And the kernel answers none of them from a source of its own
      # SDA 93a7a56, rules D1, D2 and D5. The reads are capability-authority, capability-closure, scenario-resolver-map,
      # mechanic-definitions, execution-delivery and provider-authority (DeclaredReadPort.cs, AuthorityRead.cs).

    @status:installed
    Scenario: The kernel's own session reads stay the kernel's
      Then reuse-generation, the kernel's graph statement reads and its declared changes never reach the provider
      # SDA D7 (KV-001). DatabaseResidentSession.cs reads reuse-generation through a data access the provider is not bound
      # to.

  Rule: An owned capability is answered from the bundle, and only owned capabilities are

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The bundle's manifest declares what it owns
      Then the manifest lists as owned every capability the host serves that this repo declares
      And it owns no acceptance capability, which is the estate's: capture-estate-live-observation
      And which reads the bundle answers is the manifest's list, not a rule of the provider's
      # The API interface is owned as part of serve-api-request's declaration (serve-api-request.feature, declarations/27).
      # An acceptance capability runs through the estate, so its run is the evidence (capture-estate-live-observation.feature).

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: Each of an owned capability's reads is answered from the bundle, under the pin
      When a delivery runs a capability the manifest owns
      Then the provider answers these reads of it from the bundle:
        | read                  | answered with                                                                         |
        | capability-authority  | one row: capability_id, scenario_id, namespace_id, graph_source, cli_configuration   |
        | capability-closure    | the capability's invocation closure rows                                             |
        | scenario-resolver-map | the capability's resolver rows, where the bundle holds them                          |
        | mechanic-definitions  | the bundle's mechanic definition rows                                                |
      And each answer's snapshotId, projectionDigest and viewDefinitionDigest are the pin
      # The row columns are the resultMapping the estate's boot data-access authority declares (run 343ae7d4). SDA D6: a
      # delivery reports the pin as its evidence. AuthorityRead.cs:109-117 refuses the four reads with
      # DATABASE_AUTHORITY_NOT_COHERENT unless they carry one identity.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: A read for an owned capability that the bundle lacks fails
      When a read is for a capability the manifest owns, and the bundle holds no answer for that read, namespace or scenario
      Then that read fails, and its delivery with it
      And the provider never answers it from the estate instead

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: Every other read is passed to the delivery's own session
      When a read is for a capability the manifest does not own: the consumer's, a run's, or one a request dispatches, such
        as read-ui-page for GET /sfx/v1/pages
      Then the provider passes the request unchanged to a step bound to SDA's built-in read step,
        sda-kernel-built-in-read.v1
      And builtInRead answers it in the delivery's own estate session, pin and impersonation
      # SDA 1bd400e, D14: the step sends a cell's declared-read-request.v1 to builtInRead, and refuses with
      # BUILT_IN_READ_NOT_BOUND anywhere but in the port's provider. D9: "the host needs no estate reader of its own". It
      # serves only reads the boot data-access authority declares (DATA_ACCESS_READ_NOT_DECLARED:<readId> otherwise).

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: SDA's boot authority is passed to the session and never pinned
      When a read is execution-delivery or provider-authority
      Then the provider passes it to builtInRead
      And the bundle never holds it
      # SDA's advice, 2026-11-02: both are SDA's own boot authority kept in the estate, and pinning them would freeze SDA's
      # authority inside the host.

    @status:installed
    Scenario: One capability is answered from one source
      When a capability's reads report different identities
      Then the kernel refuses it with DATABASE_AUTHORITY_NOT_COHERENT
      # AuthorityRead.cs:109-117.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: One delivery runs capabilities from the bundle and from the estate
      When a delivery runs a capability the manifest owns, under run-declared-graph, and that capability dispatches to a
        consumer's capability
      Then each capability is served from its own source and reports that source's identity
      And no capability is refused for carrying another source's identity
      # SDA 60aefbb (D10, 2026-11-03) allows it in all three kernels: coherence is per capability, and mechanics carried
      # from another capability stand in only when they share its identity. It answered
      # docs/request-sda-one-delivery-two-sources.md. Not built here: the host serves nothing from a bundle yet.

  Rule: The bundle is admitted before the host listens

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: A bundle that does not match its pin stops the host
      When the manifest does not match the pin, or a document is missing, malformed or does not match its digest
      Then the host does not listen
      And it never serves the host's operations from the estate instead
      # The kernel reads no document and checks no digest (SDA D13): the provider checks them itself, reading each document
      # through the bundle-read provider (sfx-api-host-bundle-read.feature). Every kernel starts before the facade listens
      # (host-facade.feature), and the facade's first delivery reads its configuration from an owned capability
      # (read-api-host-configuration.feature), so a mismatch fails that delivery and the host never listens.

  Rule: The bundle is this repo's own declarations in SEJ, and changes only by a deploy

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The host's capabilities are written in SEJ in this repo
      Then each capability the manifest owns is kept under authorities/host-bundle/ as its graph source, the SEJ the kernel
        compiles, written by hand like every other declaration of this repo
      And nothing outside this repo produces the bundle, and nothing compiles it from the estate
      # The kernel compiles a capability from its graph source: SDA's DeclaredCompileHarness.cs answers capability-authority
      # with the graph source as graph_source and no database. Nothing outside the estate compiles DSL: the installed
      # client's `capability author --dsl` submits a declared change to the estate.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The host's declarations are never declared into the estate
      When a host declaration changes in this repo
      Then nothing of it is declared into the estate
      And the host already serving keeps serving as it was until the image that carries the change replaces it
      # Today's host reads its declarations from the estate on every delivery, so a host declaration declared there would
      # change the host already serving, before its facade could follow it.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The bundle's digest is the pin
      Then the manifest names the SHA-256 digest of every document of the bundle
      And the SHA-256 digest of the manifest is the pin, which answer-host-declared-read's graph source names
      # The graph source is the binding's configuration, so the pin goes out with the provider authority (SDA D13: "the
      # graph source is the binding's data, and pinning it is the host's").

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The host serves only what its pin names
      When a host declaration changes in this repo and the pin does not
      Then the host serves the pinned declaration
      And the change is served once it is pinned and deployed
      # SDA D11 (60aefbb): the declaration cache serves a provider's earlier answers under the estate's generation and the
      # envelope's pin, so "a host that changes what its provider serves restarts the kernels it serves". The one deploy
      # restarts them.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The kernel, the provider, the bundle and the pin go out in one deploy
      Then none of them goes out without the others

  Rule: The provider reaches the estate only through the delivery's own session

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: The provider holds no estate connection or credential of its own
      Then every read the provider does not answer from the bundle goes to builtInRead
      And the provider opens no connection to the estate and holds no credential
      And no secret is in the bundle, the provider authority or the provider's binding
      # SDA bcbdbec, D9 and section 6 of the request: a second reader in the host "would run on another connection, outside
      # the delivery's pin and impersonation". SDA's section 6 step 4 has a host record its bundle from the estate. This host
      # does not: its bundle is its own SEJ, so nothing of the host passes through the estate to make it.

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: Each declared read honors the provider binding, proved by the delivery's evidence
      Given the kernel's reads depend on this provider binding:
        | calls                                          | provider capability they need                                                   | result it must produce here         | run evidence that proves it                                     |
        | every declared read of an owned capability     | answer-host-declared-read, bound to sda-kernel-declared-read-port.v1            | the bundle's answer, under the pin  | the capability's entry in outcome.evidence.authorities, naming the pin |
        | every other declared read                      | answer-host-declared-read, passing to builtInRead                               | the session's answer                | the capability's entry in outcome.evidence.authorities, naming the session's snapshot |
      When a delivery runs an owned capability that dispatches to a consumer's capability
      Then each read produces the answer its binding requires
      And outcome.evidence.authorities names the pin for the owned capability and the session's snapshot for the other
      # SDA D6, and D10 (60aefbb): a delivery reports every capability authority it read, with its own identity, its own
      # first, once each in read order, those it composed included.

  Rule: Each provider tag must agree with the accepted binding and the actual invocation

    @status:not-built
    @capability:answer-host-declared-read
    Scenario Outline: Provider acceptance fails when the evidence cannot prove a declared read
      Given the accepted binding of sda-kernel-declared-read-port.v1 to answer-host-declared-read
      When acceptance checks a delivery with <defect>
      Then provider acceptance fails for that read and identifies the missing or conflicting evidence

      Examples:
        | defect                                                                    |
        | an owned capability's read answered with the session's identity          |
        | a read of a capability the manifest does not own answered from the bundle |
        | a pin in the evidence other than the one in the provider's binding        |
        | a provider other than answer-host-declared-read bound to the port         |
        | an evidence gap that prevents attribution of the read                     |

  Rule: The estate stays required for every delivery until SDA moves the kernel's session

    @status:installed
    Scenario: Every delivery opens the kernel's estate session
      Then each delivery begins the kernel's own estate session: connect, pin, authority read, reuse read, impersonation
      And no delivery is answered while the estate is unreachable
      # SDA D7 (KV-001); ResidentDelivery.cs. D9 leaves the session with the kernel: "Later. KV-001 moves the session itself
      # to the host. builtInRead then goes with it." Moving it is SDA's.

    @status:not-built
    @capability:answer-host-declared-read
    Scenario: A host operation that queries no data is answered with the estate unreachable
      Given SDA's KV-001 step has put the kernel's session behind a host-bound port
      When the estate is unreachable
      Then a host operation that queries no data is answered from the bundle

  Rule: Answering from the bundle keeps the host's service levels

    @status:probed
    @capability:answer-host-declared-read
    @slo:warm-definitions
    Scenario: A warm envelope reads no owned declaration again
      Given the service level:
        | SLI                                        | SLO target | baseline                                        |
        | declaration reads made by a warm envelope  | none       | none, 0.3 to 20 ms (WSL, today's estate reads)  |
      When an envelope runs an owned capability its kernel has already answered from the bundle under the same pin
      Then the kernel resolves it without a read through the provider
      # SDA D11 (60aefbb): the declaration cache spanning a resident kernel's deliveries is keyed by the estate's declared
      # generation and the envelope's pin, and serves a bound provider's earlier answers under that key. The bundle keeps
      # the strategy of SDA 3296bc1; it does not turn a cached resolution into a provider call.
      # On SDA 29355da, warm on WSL against the estate, the bundle's serve-http-request resolved 13 declarations, all 13
      # reused and none read, and made 1 database query, the session's generation read, as the estate's does. Before D16
      # it made 6 queries, against 2 unbound (docs/request-sda-warm-envelope-round-trips.md). README.md, Verified.

    @status:not-built
    @capability:answer-host-declared-read
    @slo:frontdoor-warm-latency
    Scenario: The frontdoor's latency objective holds with the bundle
      When requests are answered with the host's declarations served from the bundle
      Then frontdoor-warm-latency holds: p50 at most 0.88 s and p95 at most 3.35 s on sfx-api-test
      # The baseline was measured with every declaration read from the estate (docs/azure-test-2026-10-31.md). On WSL, on
      # SDA 29355da with one resident kernel, a warm request took 0.86 s with the bundle and 1.03 s with the estate's
      # declarations. The facade with all six kernels answered at p50 0.78 s and p95 1.08 s over 20 warm requests.
      # sfx-api-test is not yet measured.

    @status:probed
    @slo:session-setup
    Scenario: The kernel's estate session costs at most 0.34 s per envelope, until KV-001
      Given the service level:
        | SLI                                             | SLO target                    | baseline                                      |
        | the kernel's estate session setup per envelope  | at most 0.34 s, until KV-001  | 0.25 to 0.34 s, the generation read included  |
      When an envelope begins the kernel's estate session
      Then its setup takes at most 0.34 s
      # README.md, Next 5 and Verified. The session stays the kernel's (D7); SDA's KV-001 moves it to the host.
