# Canonical feature of the hosted execution profile, proposed for the owner's review, 2026-11-04.
# Tags, terms and the owner's direction are in features/README.md. As in the provider features of 2026-11-03,
# @capability and @provider are on each scenario.
# Sources:
# - the contract: contracts/hosted-execution-profile.v1.schema.json, this deployment's profile
#   contracts/sfx-api-hosted-csharp.v1.profile.json (sha256:53d88521d1767295fd4967ce3bcf90d3606b7e0b63e2c2c3ba66a5a685e6957b),
#   and the receipt contract contracts/hosted-execution-acceptance.v1.schema.json;
# - the consolidated host-consumer contract revision (2026-11-04), prepared for host review;
# - sfx-api.config.json, deploy/Dockerfile and SDA's DeclaredProviderResolver.cs at 29355da, read from the code.
#
# Identities:
#   read-hosted-execution-profile        answers the profile's exact bytes and digest from the host's bundle
#   accept-hosted-execution-profile      coordinates T1 to T7 on the request path and issues the receipt
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
# Slice 3 as built (2026-11-04), for the owner's review with the build:
# - accept-hosted-execution-profile runs authorize > vault (sfx-vault-host-read-port.v1) > reference > open
#   (sfx-vault-reference-carry-port.v1) > exchange (sfx-api-host-http-request-port.v1) > evaluate, on the request path,
#   routed POST /sfx/v1/hosted-execution/acceptance for callers user with input {principalId: $caller.principalId}.
# - authorize admits only principalId 00e053bd-b090-4ff9-be25-64089d170fb2 (staging-release-acceptance, identifier
#   staging-release-acceptance) and declares the plan; reference requires the vault entry SFX_API_ACCEPTANCE_SESSION.
#   Each leaves an admission code. A declared expression cannot fail its cell on this kernel (SDA
#   SemanticExecutionGraphMechanicProvider passes a refusing expression's input through), so the HTTPS program's first
#   step fails on any code but ADMITTED, before it opens an entry: the API answers 422 CELL_EXECUTION_FAILED naming
#   ACCEPTANCE_PRINCIPAL_REQUIRED or ACCEPTANCE_CREDENTIAL_NOT_PROVISIONED.
# - sfx-api-host-http-request opens the entry inside its own call (ADR-0019) and runs providers/host-acceptance.py under
#   /usr/bin/timeout --kill-after=5 175 with an environment that holds only the stored session and SFX_API_IMAGE_DIGEST. The
#   script attests the deployment (hostFilesDigest over serve.py, sfx-api.config.json, start.sh, kernel-host.json and
#   the provider authority, in that order; the bundle pin checked against the deployed manifest; the kernel root it
#   runs in), confirms GET /sfx/v1/session names the acceptance principal, submits T4, T1, T2, T5, T6 and T3 at once,
#   follows each stream to its end frame, reads state and output, measures T4, then submits the three T7 holds. It never
#   signs in and never revokes the stored session, which stays in it.
# - The image digest is the App Service setting SFX_API_IMAGE_DIGEST, which the deployer sets to the digest it deploys.
#   A host without it fails the exchange step and issues no receipt.
# - T6's settingsDigest is the SHA-256 of read-api-host-configuration's literal answer as canonical JSON (keys sorted,
#   no whitespace, UTF-8), read by the configuration probe from the deployed bundle with the request wait and the
#   waiting runs.
# - evaluate derives each check from the client's observations with the profile's and the receipt schema's values,
#   and answers the receipt; without the client's observations or an established deployment it answers 422 with
#   ACCEPTANCE_CLIENT_FAILED or ACCEPTANCE_DEPLOYMENT_UNESTABLISHED. T7's arithmetic covers exactly the three holds.
# - Run admission refuses accept-hosted-execution-profile (ADMISSION_REQUEST_PATH_ONLY, admit-api-run-live.feature): a
#   run's input could claim any principal. The client also reads the kernel it runs under from /proc and uses the
#   session only on the request path, so T7's coordinatorExecutionPath and coordinatorWorkerSlots are measured; elsewhere it
#   answers ACCEPTANCE_NOT_ON_REQUEST_PATH and no receipt.
# - Known limit: a failure of the program itself (vault open, start of the child) fails the request with no receipt.

@project:sfx-api
@status:proposed-for-review
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
    Scenario: Only the dedicated acceptance principal starts the coordinator
      Given a trusted declaration in the pinned host bundle resolves staging-release-acceptance to its existing immutable principalId
      When a live user session requests POST /sfx/v1/hosted-execution/acceptance
      Then the coordinator compares its authenticated principalId to that declared principalId before releasing a credential
      And a different principal, missing binding, expired session or unauthenticated caller is refused before any probe
      And a principal name or id supplied in the request body cannot grant admission
      # The host's existing session resolution yields caller kind user. This declaration adds no machine-bearer resolver.

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    @provider:sfx-vault-host-read-port.v1
    @provider:sfx-vault-reference-carry-port.v1
    Scenario: The coordinator uses the dedicated acceptance principal's stored session
      Given the operator stored that principal's session with store-credential under SFX_API_ACCEPTANCE_SESSION
      When the admitted coordinator releases it at the declared credential pointer
      Then it confirms through HTTPS that GET /sfx/v1/session names the declared staging-release-acceptance principalId
      And it uses that session for the probes, event streams and readback belonging to that principal
      And it never signs in, never revokes the stored session and preserves the existing own-runs visibility
      And the session never reaches source, testimony, observations, the receipt or caller-controlled input
      # The owner, 2026-11-04: "The standard process was used. Stick to it." Store run 876426ad answered
      # CREDENTIAL_STORED for SFX_API_ACCEPTANCE_SESSION at 19:15:04 UTC. Profile version 3 replaced version 2's password
      # sign-in, which no owner approval covered.

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
        | the host vault has no SFX_API_ACCEPTANCE_SESSION entry    |
        | the stored session is rejected: expired or revoked       |
        | the stored session names a different principalId         |
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
      Given a child that writes 393216 repetitions of the 16 UTF-8 bytes of "aé€😀abcdef", 6291456 bytes in all
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
      And every probe run belongs to the dedicated acceptance principal bound by that host bundle
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

    @status:installed
    @capability:accept-hosted-execution-profile
    @provider:sfx-api-host-http-request-port.v1
    @provider:read-run-state
    @provider:sfx-vault-host-read-port.v1
    @provider:sfx-vault-reference-carry-port.v1
    Scenario: Each step honors its provider binding, proved by the run
      Given these steps depend on these provider bindings:
        | calls                                     | provider capability the step needs                                   | result it must produce here                          | run evidence that proves it                    |
        | acceptance session release               | sfx-vault-host-read-port.v1 and sfx-vault-reference-carry-port.v1      | the stored session at the declared credential pointer | credential-release disposition without its value |
        | acceptance session check                 | sfx-api-host-http-request-port.v1                                    | the stored session names the bound principal           | session-check disposition and principalId without bearer |
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
