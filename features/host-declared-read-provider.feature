# Canonical feature of the host's declared-read provider, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md. The provider is not a capability: it is the provider
# the host binds to the kernel's port sda-kernel-declared-read-port.v1.
# Sources: SDA 93a7a56 (docs/request-host-selected-declared-read-provider.md; rules D1-D8 in
# kernel/semantic-authority/execution/declared-read-port.semantic-authority.json; ADR-0020 as rewritten), SDA bcbdbec
# (rule D9, the pass-through to the delivery's own session) and SDA 2f0b9b4, which reverted cd4fcf5's kernel-owned
# bundle. Kernel source lines are at SDA 93a7a56 unless a comment names bcbdbec.

@project:sfx-api
@component:host-declared-read-provider
@status:proposed-for-review
Feature: The host's own declarations are answered from its pinned bundle
  As the owner
  I want the host's own declarations kept in this repo, pinned, and answered to the kernel from there
  So that the estate's front door does not take its own definition from the estate it serves

  "We don't circular hosting. The estate is for the consumer so that means the consumer can own the host in its estate.
  However, we do have the ability to declare the capabilities in SEJ (semantic executable JSON), and keep them in this
  repo. The SEJ can be resolved by the kernel without being apart of the estate." (the owner, 2026-11-02)

  Rule: The kernel sends every declared read to the host's provider and chooses no source

    @status:not-built
    Scenario: Every declared read of a delivery reaches the host's provider
      Given the host's provider authority binds sda-kernel-declared-read-port.v1 to the host's provider
      When a kernel carries any delivery
      Then each of its declared reads reaches the provider as declared-read-request.v1 {readId, input, options}
      And the kernel answers none of them from a source of its own
      # The kernel side is SDA 93a7a56, rules D1, D2 and D5; the host binds no provider yet. The reads are
      # capability-authority, capability-closure, scenario-resolver-map, mechanic-definitions, execution-delivery and
      # provider-authority.

    @status:not-built
    Scenario: The provider runs in the deployed kernel
      Then the provider is a .NET type that the C# kernel loads from the host's provider authority
      # MechanicRegistry.cs:224-238 loads a host provider with Assembly.LoadFrom. The deployed kernel is C#.

    @status:installed
    Scenario: The kernel's own session reads stay the kernel's
      Then reuse-generation, the kernel's graph statement reads and its declared changes never reach the provider
      # SDA 93a7a56 D7 (KV-001). DatabaseResidentSession.cs:242-244 reads reuse-generation through a data access the
      # provider is not bound to.

  Rule: The host's own capabilities are answered from the bundle, and only they are

    @status:not-built
    Scenario: The bundle's manifest declares what it owns
      Then the manifest lists as owned every capability the host serves that declarations/ and sej/ declare
      And it owns no acceptance capability, which is the estate's: capture-estate-live-observation and
        record-api-host-authority
      And which reads the bundle answers is decided by that list, not by code in the provider
      # The API interface is owned as part of serve-api-request's declaration: serve-api-request.feature and
      # declarations/27. An acceptance capability runs through the estate, so its run is the evidence
      # (capture-estate-live-observation.feature).

    @status:not-built
    Scenario: A read for an owned capability is answered from the bundle
      When a delivery runs a capability the manifest owns
      Then the provider answers each of that capability's reads from the bundle
      And the delivery's evidence names the pin as its snapshotId and projectionDigest
      # SDA 93a7a56 D6.

    @status:not-built
    Scenario: A read for an owned capability that the bundle lacks fails
      When a read is for a capability the manifest owns, and the bundle holds no answer for that read and input
      Then that read fails, and its delivery with it
      And the provider never answers it from the estate instead

    @status:not-built
    Scenario: Every other read is answered from the estate, in the delivery's own session
      When a read is for a capability the manifest does not own: the consumer's, a run's, or one a request dispatches,
        such as read-ui-page for GET /sfx/v1/pages
      Then the provider passes it to the kernel's built-in read, builtInRead, which answers it in the delivery's own
        estate session, pin and impersonation
      # SDA bcbdbec, rule D9: the provider's context carries builtInRead, the same declared-read-request.v1 answered by
      # the kernel's built-in reads on the delivery's own data access; "the host needs no estate reader of its own". It
      # serves only reads the boot data-access authority declares (DATA_ACCESS_READ_NOT_DECLARED:<readId> otherwise). In
      # the C# kernel the provider binds a BuiltInDeclaredRead parameter.

    @status:not-built
    Scenario: SDA's boot authority is answered from the estate and never pinned
      When a read is execution-delivery or provider-authority
      Then the provider passes it to builtInRead
      And the bundle never holds it
      # SDA's advice, 2026-11-02: both are SDA's own boot authority kept in the estate, and pinning them would freeze
      # SDA's authority inside the host.

    @status:installed
    Scenario: One capability is answered from one source
      When a capability's reads report different identities
      Then the kernel refuses it with DATABASE_AUTHORITY_NOT_COHERENT
      # AuthorityRead.cs:110-117.

  Rule: The bundle is admitted before the host listens

    @status:not-built
    Scenario: A bundle that does not match its pin stops the host
      When the provider finds the manifest does not match its pin, or a document missing, malformed or not matching its
        digest
      Then the host does not listen
      And it never serves the host's operations from the estate instead
      # Every kernel starts before the facade listens: host-facade.feature.

  Rule: The bundle is recorded from this repo's declarations and changes only by a deploy

    @status:not-built
    @provider:http-exchange
    Scenario: A recording is driven by a declared capability, never by a script
      When the bundle is recorded
      Then record-api-host-authority, declared in the estate, exercises every operation the bundle owns against a host
        whose provider records, every operation of sidefx-api-interface.v1 included
      And no script, harness or probe outside the estate drives it
      # A proposed capability; nothing declares it yet. It reaches the host over http-exchange, as
      # capture-estate-live-observation does.

    @status:not-built
    Scenario: A recording keeps every read it forwarded, across every kernel
      When the provider records
      Then it passes each read to builtInRead and keeps the read, its exact input and its answer
      And every kernel's recording adds to one bundle, one document per read and input
      And a read recorded with two different answers is refused, and no bundle is written
      # A provider loads in each kernel process, and the host runs four kinds of kernel.

    @status:not-built
    Scenario: A recording writes the bundle into this repo, and its digest becomes the pin
      When a recording completes
      Then the bundle's manifest and documents are written under authorities/host-bundle/
      And the digest of the manifest becomes the pin in the provider's configuration

    @status:not-built
    Scenario: A recording does the work the host will do
      Then each recorded operation runs against the estate the host serves, as it will be served
      And it writes what that operation writes: a sign-in opens a session, a completion completes its run, a trace is
        retained

    @status:not-built
    Scenario: The host serves only what its pin names
      When a host declaration is re-declared and the bundle is not recorded again
      Then the host serves the pinned declaration
      And the change is served once it is recorded, pinned and deployed

    @status:not-built
    Scenario: The kernel, the provider, the bundle and the pin go out in one deploy
      Then none of them goes out without the others

  Rule: The provider reaches the estate only through the delivery's own session

    @status:not-built
    Scenario: The provider holds no estate connection or credential of its own
      Then every read the provider does not answer from the bundle goes to builtInRead
      And the provider opens no connection to the estate and holds no credential
      And no secret is in the bundle, the provider authority or the provider's configuration
      # SDA bcbdbec, D9 and section 6 of the request: a second reader in the host "would run on another connection,
      # outside the delivery's pin and impersonation". The earlier draft of this scenario had the provider read the estate
      # with the credential its binding's credentialPointers name (SDA 93a7a56 request, section 3.2); D9 replaces that.

  Rule: The estate stays required for every delivery until SDA moves the kernel's session

    @status:installed
    Scenario: Every delivery opens the kernel's estate session
      Then each delivery begins the kernel's own estate session: connect, pin, authority read, reuse read, impersonation
      And no delivery is answered while the estate is unreachable
      # SDA 93a7a56 D7 (KV-001); ResidentDelivery.cs:90. D9 (bcbdbec) leaves the session with the kernel: "Later. KV-001
      # moves the session itself to the host. builtInRead then goes with it." Moving it is SDA's.

    @status:not-built
    Scenario: A host operation that queries no data is answered with the estate unreachable
      Given SDA's KV-001 step has put the kernel's session behind a host-bound port
      When the estate is unreachable
      Then a host operation that queries no data is answered from the bundle
