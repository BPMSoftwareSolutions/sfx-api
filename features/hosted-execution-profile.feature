# Canonical feature of the hosted execution profile, revision 5, 2026-11-04.
# Version 5 removes the separate acceptance credential at the owner's direction.
# Version 5 is deployed. Attempt 2693926c-0714-4c75-989d-ded69182e3ef passed T1-T7.
# Exact receipt/readback and FULFILLED proof: docs/hosted-execution-v5-2026-11-04/README.md.
# Tags, terms and the owner's direction are in features/README.md. As in the provider features of 2026-11-03,
# @capability and @provider are on each scenario.
# Sources:
# - the contract: contracts/hosted-execution-profile.v1.schema.json, this deployment's profile
#   contracts/sfx-api-hosted-csharp.v1.profile.json (sha256:9760b6001d84576090a47a1ac02a4db5d728fdb1aea8cbef66b57376ff152f33),
#   and the receipt contract contracts/hosted-execution-acceptance.v1.schema.json;
# - the consolidated host-consumer contract revision (2026-11-04), prepared for host review;
# - sfx-api.config.json, deploy/Dockerfile and SDA's DeclaredProviderResolver.cs at 29355da, read from the code.
#
# Identities:
#   read-hosted-execution-profile        answers the profile's exact bytes and digest from the host's bundle
#   accept-hosted-execution-profile      coordinates T1 to T7 on the request path and issues the receipt
#   read-hosted-execution-acceptance     reads non-secret retained attempt evidence through the authenticated request path
#   sfx-api-host-acceptance-record-port.v1 persists and reads attempt evidence without credential material
#   probe-hosted-execution               executes T1, T2, T4, T5, T6 or a T7 hold on a worker
#   probe-hosted-execution-language-refusal
#                                        executes the isolated Python-only T3 negative control on a worker
#   sfx-api-host-http-request-port.v1    provider sfx-api-host-http-request: sends authenticated HTTPS requests to the
#                                        profile's deployed endpoint and reads their complete responses, without redirects
#   sfx-api-host-child-process-port.v1   provider sfx-api-host-child-process: starts an executable of the profile with
#                                        declared arguments and an empty environment, and answers its exit code, its
#                                        standard output and its elapsed time
#   sfx-api-acceptance-python-only-port.v1
#                                        provider sfx-api-acceptance-python-only: declared only for python, so a csharp
#                                        worker must refuse it
#
# Current revision 5 implementation:
# - host/serve.py assigns requestExecutionId at actual kernel admission; declared ingress carries it with the
#   authenticated caller into the pinned provider. Mixed-case duplicate correlation/profile headers are refused.
# - providers/hosted/HostedAcceptance.cs implements the declared HTTP and record ports. Configuration owns the
#   operator/probe bindings, plan and receipt expression. Persistent /home stores RUNNING and exact terminal bytes.
# - The exclusive OS-held lock is shared across request kernels; process death releases ownership. An abandoned
#   RUNNING record becomes UNKNOWN. Readback opens no credential and submits no probe.
# - Full published receipt validation precedes terminal persistence. The existing sfx-platform CLI discovers the
#   profile, dispatches once, retains evidence and independently checks readback before constructing a proof.
# - hostFilesDigest extends the historical five-file order with Sfx.HostedProviders.dll, hosted/validate.py and
#   contracts/validate-hosted-execution-receipt.py. Image and bundle pins are in the deployment record.
# - Version 4 retains historical negative, busy and restart evidence. Version 5 has a real ACCEPTED receipt
#   and independently verified FULFILLED proof; T7 scheduling and UTF-8 payload transport passed live.
#
Feature: The host declares what it promises the capabilities it executes
  As a consumer that declares capabilities and their providers
  I want the host's execution promises as a versioned contract I can read, check by digest and require
  So that I meet my obligations to it, and the host proves its own with receipts bound to what it deployed

  "Contracts are serious and need to be durable. Not just spoken. Contracts have schema (JSON) and structure." (the
  owner, 2026-11-04)

  Rule: The profile is a declared, versioned contract that consumers can read

    @status:installed
    @capability:read-hosted-execution-profile
    Scenario: The deployment answers its profile
      When a consumer reads the host's execution profile
      Then it receives the profile's exact bytes, valid against hosted-execution-profile.v1
      And the digest it receives is the SHA-256 of those bytes
      # The profile is a document of the host's bundle, so it is served under the bundle's pin (answer-host-declared-read).

    @status:not-built
    @capability:read-hosted-execution-profile
    Scenario: A change to any promise is a new profile version
      When the host changes a promise, a bound or an executable
      Then the profile has a new profileVersion and a new digest
      And the receipt contract that accepts it pins the new digest

  Rule: H1, H2 and H5 hold today, read from the code and the configuration

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario: This deployment executes every run in C#
      Then every kernel of this deployment runs the C# kernel from SDA 29355da
      # sfx-api.config.json: every kind of kernel runs ./KernelEntry from one linux-x64 install root.

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario: A provider with no entry for the profile's language is refused
      Given a run whose closure has a provider with no csharp entry
      When the run reaches that provider
      Then the run fails with PROVIDER_LANGUAGE_UNAVAILABLE, naming the provider, its declared language and csharp
      # SDA DeclaredProviderResolver.cs:28-47. The renderer's first hosted flight was refused this way.

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario Outline: A capability's execution is bounded by its path
      When a capability executes on the <path> path
      Then <bounds>

      Examples:
        | path    | bounds                                                                                                   |
        | request | it waits at most 30 s for a free kernel, its delivery is bounded at 195 s and its answer at 198 s, within App Service's 230 s |
        | worker  | its delivery is bounded at 3600 s and its answer at 3605 s; 2 runs execute at once and 64 may wait        |
      # sfx-api.config.json and read-api-host-configuration (declarations/25).

  Rule: The acceptance capability runs every check of the pinned profile and derives each disposition

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario: A measured probe is converted to the typed receipt form
      Given a probe returns status MEASURED with its probe name and measured fields
      When the evaluator projects the fields required by that check's observed schema
      Then it supplies kind OBSERVED, the actual runIds and those observations to the receipt check
      And it sets PASSED only after the observed values meet the schema's pass conditions
      And the raw probe's status and probe metadata are not copied into observed
      # MEASURED is a probe disposition, not an acceptance decision. The coordinator owns this declared projection.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: The coordinator holds a request kernel and leaves both workers available
      Given the host's declared interface binds POST /sfx/v1/hosted-execution/acceptance to this capability on the request path
      When the authenticated acceptance request executes
      Then its coordinator holds no worker slot and stays within the request path's delivery bound
      And worker probes are submitted by authenticated HTTPS POST /sfx/v1/runs to the profile's endpoint
      And their state and output are read by HTTPS GET through that endpoint
      And the facade consumes each admission's execute-run directive and queues its probe
      And no in-process invocation of admit-api-run-live substitutes for submitting a probe through the facade
      # The host's existing authentication applies. Credentials are never copied into the acceptance receipt.
      # The coordinator's request executionId is distinct from the admitted worker runIds it cites.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: The existing operator starts acceptance and the invoking session owns its probes
      Given the profile and pinned host bundle bind host-acceptance-operator to 565de6d4-ebcd-408b-9359-04d21dc62183
      And probe execution uses that same authenticated operator identity
      When a live user session requests POST /sfx/v1/hosted-execution/acceptance
      Then the coordinator compares its ingress-authenticated principalId to the operator binding before releasing a credential
      And a different principal, missing binding, expired session or unauthenticated caller is refused before any probe
      And a principal name or id supplied in the request body cannot grant admission
      And the operator does not switch accounts, enter an acceptance password or provision another probe bearer
      And probe ownership and own-runs visibility remain with the invoking operator
      # The host's existing session resolution yields caller kind user. This declaration adds no machine-bearer resolver.

  Rule: The host delivers and proves the complete supported invocation, not just a coordinator that assumes one

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:read-hosted-execution-profile
    @provider:serve-http-request
    Scenario: The existing capability command reaches the declared request route
      Given the host publishes and installs a versioned sfx-api client that supports this profile's invocation descriptor
      And the existing operator CLI session resolves to the profile's host-acceptance-operator binding
      And the existing CLI already has its ordinary authenticated user session
      When the operator or its authorized agent executes this existing command surface:
        """
        sfx-api capability observe accept-hosted-execution-profile --input '{}' --input-type json --json --auth user
        """
      Then the client reads read-hosted-execution-profile through the existing declared capability mechanism
      And it verifies the returned profile text's exact UTF-8 digest, schema and supported invocation descriptor before dispatch
      And the profile endpoint must equal the authenticated CLI origin, so no bearer can be forwarded to a different origin
      And discovery finishes and releases its run before the coordinator request starts
      And the client generates one UUID attemptId and sends it as X-SFX-Acceptance-Attempt-Id
      And it sends the verified digest as X-SFX-Hosted-Profile-Digest
      And it sends exactly one authenticated HTTPS POST with body {} to the verified profile's acceptance route without redirects
      And it uses the existing operator bearer only in that request's Authorization header
      And the interface validates the empty-body contract and attempt header and binds caller identity from ingress
      And it normalizes header names case-insensitively and refuses duplicate correlation or profile-digest headers
      And it builds hosted-execution-acceptance-context.v1 from those headers, the authenticated caller and its actual request identity
      And it refuses PROFILE_CHANGED before credential release if the request's expected digest differs from its active profile
      And the request dispatches accept-hosted-execution-profile on the request path holding zero worker slots
      And it never submits this coordinator to POST /sfx/v1/runs, including through a wrapper capability
      And neither a new CLI verb, a consumer-authored script nor a manually copied bearer is required
      # The host owns the client publication, declared dispatch mapping, interface and provider implementation.
      # Discovery uses the existing installed reader; a URI, principal, credential or dispatch target in input is refused.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:read-hosted-execution-profile
    @provider:serve-http-request
    Scenario Outline: An invocation prerequisite is refused before it can become hidden manual work
      Given <defect>
      When the supported client attempts acceptance
      Then it returns a non-secret hosted-execution-invocation-error.v1 with <code> at <stage>
      And no password prompt, account switch, machine fallback, credential overwrite or coordinator worker run occurs
      And the request is not automatically retried

      Examples:
        | defect                                      | code                              | stage     |
        | the profile reader cannot be reached        | PROFILE_DISCOVERY_FAILED           | discovery |
        | the returned profile digest does not match  | PROFILE_IDENTITY_MISMATCH          | discovery |
        | the client cannot honor the declared route  | CLIENT_DISPATCH_UNSUPPORTED        | discovery |
        | the caller has no live operator session     | CALLER_REQUIRED                   | caller    |
        | the caller resolves to another principal    | ACCEPTANCE_PRINCIPAL_REQUIRED      | caller    |
        | the body or correlation header is invalid   | ACCEPTANCE_REQUEST_INVALID        | dispatch  |
        | the profile changed after client discovery  | PROFILE_CHANGED                   | dispatch  |
        | a coordinator is already active             | ACCEPTANCE_BUSY                   | dispatch  |
      # An older client that tries /runs is refused by ADMISSION_REQUEST_PATH_ONLY; it is not a supported deliverable.
      # The client update and a fresh live invocation, not merely that refusal, close CLIENT_DISPATCH_UNSUPPORTED.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:serve-http-request
    @provider:sfx-api-host-http-request-port.v1
    Scenario: One coordinator runs at a time without obstructing its own requests
      Given one admitted acceptance request is still executing
      When a second acceptance request arrives
      Then the host's deployment-wide admission promptly refuses it as ACCEPTANCE_BUSY without waiting for the first or opening the probe credential
      And it leaves the second request kernel available for the first coordinator's probe API calls
      And the host releases admission ownership on success, failure and termination
      And T7 is run in a measurement window with both workers available as its existing precondition requires
      # Attempt identifiers correlate evidence; they do not promise deduplication or exactly-once execution.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: Acceptance needs no additional credential provisioning
      Given the operator is signed in through the existing CLI
      When an authorized acceptance invocation begins
      Then the host reuses that request session for its probes and own-run reads
      And no host-vault entry or dedicated acceptance account is required
      And the host validates the session and operator identity before admitting probes
      And an expired, revoked or mismatched session produces an explicit typed failure
      And the provider never signs in, stores a session, revokes it or discloses its value

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:serve-http-request
    Scenario: The caller receives a typed terminal result and an uncertain response never authorizes completion
      When the supported client completes an acceptance invocation
      Then a schema-valid ACCEPTED receipt is returned as JSON with process exit code 0
      And a schema-valid REJECTED receipt is preserved and returned as JSON with process exit code 2
      And a known failure without a receipt returns hosted-execution-invocation-error.v1 outcome FAILED with process exit code 1
      And a timeout, lost connection or incomplete response after possible dispatch returns outcome UNKNOWN with process exit code 3
      And UNKNOWN retains the original attemptId, has no fabricated receipt and never automatically repeats the POST
      And the host investigates the retained attempt before any explicit retry with a new attemptId
      And the client preserves a received receipt before any subsequent validation or cleanup failure
      And the client bounds discovery and the coordinator HTTP exchange separately by the profile's client wait limits
      And the coordinator still stops measuring by 150 s within the unchanged 195000 ms delivery and 198000 ms answer bounds
      # No failure branch revokes the invoking session. A new attempt is not evidence that the previous one was cancelled.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:serve-http-request
    @provider:read-run-state
    Scenario: Completion requires the live command, received receipt and independent evidence readback
      Given the host executes the supported command from the actual operator session against its deployed profile
      When the client receives the completed coordinator response through HTTPS
      Then the receipt includes the actual attemptId, request executionId, route and ingress-authenticated operator binding
      And invocation.expectedProfileDigest equals the receipt profileDigest and the client's verified request header
      And invocation.requestExecutionId equals evaluator.executionId and neither is a replacement UUID invented by the evaluator
      And the receipt's probe principal matches the trusted operator binding and every probe belongs to that principal
      And the host retains the returned receipt and a hosted-execution-delivery-proof.v1 naming the client version and artifact digest
      And the proof's attemptId, exchange.attemptId and receipt.invocation.attemptId all identify the same actual request
      And a declared read of the retained receipt artifact yields exactly its byteLength and SHA-256 and the embedded receipt value
      And verification rechecks the actual deployment pins, invoked capability, inputs, terminal runs and T4 and T7 evidence
      And FULFILLED requires an ACCEPTED receipt with every T1 through T7 PASSED and a valid live delivery proof
      And a returned REJECTED receipt has an UNFULFILLED delivery proof even when invocation itself worked
      And a missing invocation, unknown transport outcome, schema fixture or local diagnostic cannot mark the host work fulfilled
      And any change to the profile, image, bundle, kernel or host files requires new live acceptance and delivery evidence
      # Schemas enforce shape and pass thresholds. The host verifier resolves artifacts and actual run/deployment identity.
      # The consumer independently checks the supplied evidence; it is not required to implement the invocation client.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-acceptance-record-port.v1
    Scenario: An admitted attempt and its terminal receipt survive a lost response and a host restart
      When the host admits an authorized acceptance request
      Then it persists attemptId, actual requestExecutionId and profileDigest before submitting any probe
      And it refuses ACCEPTANCE_RECORD_UNAVAILABLE without probes if it cannot retain that initial record
      And it persists the exact UTF-8 receipt bytes and their digest before returning the receipt to the caller
      And a failed terminal write is an explicit failure and cannot produce FULFILLED evidence
      And records survive restarts until explicit owner retirement
      And after a restart a previously RUNNING attempt that cannot be established as still active is UNKNOWN
      And no restart replays an uncertain attempt or turns it into successful acceptance
      And request diagnostics, credentials, passwords and session bearers are excluded from retained records

    @status:installed
    @capability:read-hosted-execution-acceptance
    @provider:serve-http-request
    @provider:sfx-api-host-acceptance-record-port.v1
    Scenario: The same operator retrieves a retained attempt without a new acceptance run
      Given a supported client and the existing operator session
      When it invokes read-hosted-execution-acceptance with only an attemptId UUID
      Then declared dispatch sends an authenticated HTTPS GET to /sfx/v1/hosted-execution/acceptance/{attemptId}
      And ingress checks the same pinned operator identity without trusting an identity in input
      And the host returns hosted-execution-acceptance-read-result.v1 for that attempt only
      And it returns RUNNING, UNKNOWN, FAILED, RECEIPT_AVAILABLE or NOT_FOUND without inventing an execution or a receipt
      And RECEIPT_AVAILABLE includes the original receiptBytesBase64, byte length, SHA-256 and parsed receipt value
      And the verifier decodes those bytes and checks their identity, digest and equality with the returned receipt
      And the read neither opens the probe session nor admits probes nor exposes other runs
      And NOT_FOUND after an uncertain POST remains missing evidence and does not authorize automatic replay
      # The read request contract accepts only attemptId; routing and authorization are host declarations.

  Rule: The coordinator measures the host under the invoking operator authority

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: The coordinator reuses the session of its authenticated invocation
      Given the existing CLI authenticated the operator's request
      When declared ingress receives that request on the request kernel
      Then it retains the bearer only in request-scoped provider memory outside graph values
      And it binds consumption to the host-generated requestExecutionId
      And only that acceptance invocation can consume it once
      And another request clears any unconsumed credential
      And duplicate Authorization headers cannot establish a probe session
      And HTTPS GET /sfx/v1/session must confirm the pinned operator principal
      And the same session serves the probes, event streams and own-run readback
      And the session never reaches source, testimony, observations or retained evidence
      And a credential in a caller-controlled body cannot substitute for the authenticated header
      # Owner direction: remove the added acceptance-session dependency or make it frictionless.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario Outline: Acceptance cannot proceed without its declared session authority
      Given <defect>
      When the coordinator tries to establish or use its acceptance session
      Then it submits no further probes and reports an explicit authentication or credential failure
      And unfinished checks are FAILED through the typed execution-error form when a receipt can be issued
      And it never falls back to a machine token or another principal

      Examples:
        | defect                                                  |
        | the invocation-scoped session is absent or already consumed    |
        | the invoking value is not in the API session bearer format  |
        | the invoking session is rejected: expired or revoked       |
        | the invoking session names a different principalId         |
        | the acceptance session expires or is revoked during the run |

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: The coordinator needs a second request kernel and finishes within its budget
      Given the request path runs 2 kernels, as the profile declares
      When the coordinator holds one of them for the whole acceptance
      Then each of its own HTTPS calls is answered by another request kernel
      And it waits for each probe by reading that run's event stream until its end frame
      And it stops measuring by 150 s and issues the receipt, a check it could not finish FAILED as an execution error
      # With one request kernel, the coordinator's own calls would wait behind it until the declared 30 s and be refused
      # REQUEST_KERNEL_BUSY. The 195 s delivery bound would end the coordinator itself with no receipt.

    @status:installed
    @capability:probe-hosted-execution
    @provider:sfx-api-host-child-process-port.v1
    Scenario Outline: A check measures what its promise needs
      When the coordinator submits a <check> probe to a worker
      Then its observations are <observed>
      And the check is PASSED only when they meet the profile, as hosted-execution-acceptance.v1 states

      Examples:
        | check | observed                                                                                                       |
        | T1    | the run's language; under the worker identity with an empty environment, CPython's path, implementation, version, SOABI, machine, glibc version and loadable wheel tags; create, write, read and delete of a file under /tmp, and its free bytes |
        | T2    | timeout --kill-after=2 2 around a child that ignores SIGTERM: its exit code, elapsed time, the child's pid, and whether any process of it remains |
        | T5    | timeout's first version line; timeout 2 around a child that stops on SIGTERM: its exit code, elapsed time, the child's pid, and whether any process of it remains |

    @status:installed
    @capability:probe-hosted-execution
    @provider:sfx-api-host-child-process-port.v1
    @provider:read-api-host-configuration
    Scenario: T6 reads the deployed settings
      When the T6 worker probe reads the deployed sfx-api.config.json and read-api-host-configuration's answer
      Then it observes their digests, the request wait, the delivery and answer bounds, the worker count and the waiting queue
      And those settings must match the profile
      # T6 compares settings and proves no behavior. Its evidence is "configuration" in the profile.

    @status:installed
    @capability:probe-hosted-execution-language-refusal
    @provider:sfx-api-acceptance-python-only-port.v1
    Scenario: T3 observes the refusal of a provider with no csharp entry
      When the coordinator submits this isolated Python-only probe through the deployed run API
      Then T3 observes the error code, the provider, its declared language and the runtime language the run answered
      And this expected failed probe is evaluated as a passing T3 observation
      # The Python-only binding belongs only to this probe's closure. It is absent from the coordinator's closure.

    @status:installed
    @capability:probe-hosted-execution
    @provider:sfx-api-host-child-process-port.v1
    Scenario: T4 produces the declared payload on a worker
      Given a child that writes 393216 repetitions of the 16 UTF-8 bytes of "aÃƒÆ’Ã‚Â©ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ°Ã…Â¸Ã‹Å“Ã¢â€šÂ¬abcdef", 6291456 bytes in all
      When the T4 probe returns
      Then its declared result is a JSON object with that string in its payload member

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    Scenario: T4 measures a large Unicode answer through the API
      Given the T4 worker run completed and retained its payload result
      When the coordinator makes an authenticated HTTPS GET to the profile's endpoint at /sfx/v1/runs/{runId}/output
      Then the HTTP provider reads the complete response from the deployed route without following redirects
      And T4 records its method, URL, HTTP status, transport and payload pointer
      And it decodes /output/payload from the response JSON as a string and encodes that string as UTF-8
      And its expected and received byte counts and SHA-256 digests match the fixture in the receipt schema
      And a nested call to serve-http-request, a localhost request, a redirect or a truncated response cannot pass T4
      # JSON envelope bytes, JSON escaping and HTTP framing are excluded from the payload digest.
      # The URL's runId must be the T4 runId verified by the evaluator, not another run with the same payload.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    @provider:read-run-state
    Scenario: T7 measures the worker path's concurrency
      Given both workers are available and no unrelated workload is submitted during this measurement
      And the coordinator executes on the request path and holds zero worker slots
      When it submits three 5-second hold probes through the deployed HTTPS run API without waiting for any to finish
      Then it reads the three distinct completed runs' execution start and end instants in admission order
      And T7 retains those intervals and derives admitted, maxConcurrent and thirdStartedAfterAnEnd from them
      And exactly two probes overlap and the third starts only after one of the first two ends
      And its runIds contain exactly those three probes, excluding the coordinator's request execution
      # A worker running the coordinator does not count as a second probe. Non-overlapping intervals cannot pass.
      # Missing or invalid intervals produce EXECUTION_ERROR; measured concurrency below or above two produces FAILED.

    @status:installed
    @capability:probe-hosted-execution
    @provider:sfx-api-host-child-process-port.v1
    Scenario: A T7 probe holds one worker
      When a T7 hold probe begins executing on its assigned worker
      Then it holds that worker for 5 seconds and returns

    @status:installed
    @capability:sfx-api-host-http-request-port.v1
    Scenario: The HTTP provider exercises the deployed route
      When its declared program receives an allowed probe admission, state or output request
      Then it sends the request through HTTPS to the profile's endpoint and answers the response status and complete body
      And it reports connection, deadline, incomplete-body or decoding failure explicitly
      # Its implementation is declared through the profile schema boundary, using the host's normal authentication.
      # A caller-provided observation or a direct capability return is never substituted for the HTTP response.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:read-run-state
    Scenario: The evaluator verifies the runs it cites and the deployment it ran on
      When accept-hosted-execution-profile issues a receipt
      Then every runId the receipt cites comes from an actual admission on this deployment
      And every PASSED check cites terminal runs with verified capability, inputs and measurements
      And every probe run belongs to the invoking operator bound by that host bundle
      And a failed check preserves its known admission and attempt evidence when execution or collection could not finish
      And it verifies the coordinator's request executionId separately from the worker runIds
      And T4's URL names its verified payload run and T7's intervals name exactly its three verified hold runs
      And it derives T7's concurrency from valid intervals, treating intervals as start-inclusive and end-exclusive
      And the receipt names the bundle's pin, the kernel install root that ran it, and the digest over the deployed host
        files, which the evaluator reads itself
      And it names the image digest the deployer recorded, which the host cannot attest about itself

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario Outline: A check that cannot obtain observations fails without inventing them
      Given a check encounters <failure>
      When the coordinator records that check
      Then it uses kind EXECUTION_ERROR, status FAILED, an attemptId and a typed error with stage, code and message
      And it lists only real admitted runIds, which may be empty for precondition or admission failure
      And it omits observed entirely and the complete receipt is REJECTED

      Examples:
        | failure                                      |
        | its child executable cannot start            |
        | probe admission is refused before a run exists |
        | its output request times out or is truncated  |
        | its probe output cannot be decoded           |
        | a prerequisite prevents that check from running |
      # A complete measurement that misses a threshold instead uses kind OBSERVED, status FAILED and a finding.
      # Complete passing observations remain mandatory for every PASSED check. Errors cannot authorize acceptance.
      # If deployment identity itself cannot be established, the capability fails and issues no acceptance receipt.

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario Outline: A receipt that does not prove the profile is refused
      When a receipt <defect>
      Then parsing or validation against hosted-execution-acceptance.v1 refuses it, and it authorizes nothing

      Examples:
        | defect                                                             |
        | is ACCEPTED with a check that FAILED                               |
        | leaves out a check of the profile, or adds one the profile lacks   |
        | repeats a check's key                                              |
        | has kind OBSERVED with observations that are missing, untyped or extra |
        | is PASSED on observations that do not meet the profile             |
        | is REJECTED although every check passed                            |
        | names another profile digest                                       |
        | marks an EXECUTION_ERROR as PASSED or ACCEPTED                       |
        | combines an EXECUTION_ERROR with invented observed values           |
        | claims T4 passed using an in-process or localhost response          |
        | claims T7 passed with a worker occupied by the coordinator          |
      # Local authoring regression cases are in contracts/tests/test_hosted_execution_contract.py.
      # Duplicate-key rejection happens before schema validation; date-time format assertions are enabled.

    @status:not-built
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    @provider:read-run-state
    @provider:read-hosted-execution-profile
    @provider:serve-http-request
    @provider:sfx-api-host-acceptance-record-port.v1
    Scenario: Each step honors its provider binding, proved by the run
      Given these steps depend on these provider bindings:
        | calls                                     | provider capability the step needs                                   | result it must produce here                          | run evidence that proves it                    |
        | client route discovery                    | read-hosted-execution-profile                                        | exact pinned profile text and supported dispatch descriptor | discovery read and digest verification |
        | acceptance request and attempt readback    | serve-http-request                                                   | authenticated request-path dispatch and typed response | actual request identity, route and caller context |
        | retain attempt and terminal receipt bytes  | sfx-api-host-acceptance-record-port.v1                                 | durable non-secret attempt and exact receipt bytes before response | write disposition, attempt identity and receipt digest |
        | read retained acceptance attempt          | sfx-api-host-acceptance-record-port.v1                                 | typed read-result for the named attempt without credentials | declared read and matching decoded bytes |
        | acceptance session release               | sfx-api-ingress-resolve-port.v2      | the invoking session at the declared credential pointer | request UUID binding and non-disclosure evidence |
        | acceptance session check                 | sfx-api-host-http-request-port.v1                                    | the invoking session names the bound principal           | session-check disposition and principalId without bearer |
        | probe admission and output/state HTTP reads | sfx-api-host-http-request-port.v1, provider sfx-api-host-http-request | deployed HTTPS response or explicit transport failure | HTTP provider testimony in the coordinator's request |
        | the runs every check cites                | read-run-state                                                       | run state and available evidence; terminal intervals for passing checks | the nested deliveries' testimony |
      When accept-hosted-execution-profile runs
      Then every call produces the result its binding requires
      And the probe scenarios above separately prove their child-process, settings and Python-only provider bindings

  Rule: Acceptance holds only for what was deployed

    @status:not-built
    @capability:accept-hosted-execution-profile
    Scenario: The checks run again whenever what they cover changes
      When the image, the bundle, the kernel, the host files or the profile changes
      Then T1 to T7 run again on the deployed host, and a new receipt is issued
      And only an ACCEPTED receipt naming the current digests authorizes a consumer to rely on the profile
      And host completion additionally requires the supported invocation and a new verified delivery proof for those digests

    @status:installed
    @capability:accept-hosted-execution-profile
    Scenario: Free temporary storage is a measurement at acceptance, not a reservation
      Then T1's free bytes hold when the receipt was issued, and concurrent runs share them
      And a consumer whose child finds too little space fails visibly (consumer obligation C4)

    @status:not-built
    @capability:accept-hosted-execution-profile
    Scenario: A consumer's acceptance names the profile it ran against
      When a consumer proves its capability on this host
      Then its evidence names the profile digest and the image digest of an ACCEPTED receipt
      # The renderer's proof: nh3 imported and exercised on a worker, and both objectives FULFILLED. The consumer owns it
      # (consumer obligations C1 to C4 in the profile).
