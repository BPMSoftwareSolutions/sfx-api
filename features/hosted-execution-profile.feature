# Canonical feature of the hosted execution profile, proposed for the owner's review, 2026-11-04.
# Tags, terms and the owner's direction are in features/README.md.
# Sources:
# - the contract: contracts/hosted-execution-profile.v1.schema.json, this deployment's profile
#   contracts/sfx-api-hosted-csharp.v1.profile.json, and the receipt contract
#   contracts/hosted-execution-acceptance.v1.schema.json;
# - the consumer's review of the first draft (2026-11-04), whose five changes the contract carries;
# - sfx-api.config.json, deploy/Dockerfile and SDA's DeclaredProviderResolver.cs at 29355da, read from the code.

@project:sfx-api
@capability:read-hosted-execution-profile
@status:proposed-for-review
Feature: The host declares what it promises the capabilities it executes
  As a consumer that declares capabilities and their providers
  I want the host's execution promises as a versioned contract I can read, check by digest and require
  So that I meet my obligations to it, and the host proves its own with receipts bound to what it deployed

  "Contracts are serious and need to be durable. Not just spoken. Contracts have schema (JSON) and structure." (the
  owner, 2026-11-04)

  Rule: The profile is a declared, versioned contract that consumers can read

    @status:not-built
    Scenario: The deployment answers its profile
      When a consumer reads the host's execution profile
      Then it receives sfx-api-hosted-csharp version 1 under contract hosted-execution-profile.v1, valid against its schema
      And the answer names the profile's digest, the SHA-256 of its exact bytes
      # The profile is a document of the host's bundle, answered by read-hosted-execution-profile under the bundle's pin.

    @status:not-built
    Scenario: A change to any promise is a new profile version
      When the host changes a promise, a bound or an executable
      Then the profile has a new profileVersion and a new digest, and a consumer requirement naming the old one no longer
        matches

  Rule: H1 and H2, a run executes in the profile's language

    @status:installed
    Scenario: This deployment executes every run in C#
      Then every kernel of this deployment runs the C# kernel from SDA 29355da
      # sfx-api.config.json: every kind of kernel runs ./KernelEntry from one linux-x64 install root.

    @status:installed
    Scenario: A provider with no entry for the profile's language is refused
      Given a run whose closure has a provider with no csharp entry
      When the run reaches that provider
      Then the run fails with PROVIDER_LANGUAGE_UNAVAILABLE, naming the provider, its declared language and csharp
      # SDA DeclaredProviderResolver.cs:28-47. The renderer's first hosted flight was refused this way.

  Rule: H3, a provider program may start the profile's executables, and they work as declared

    @status:not-built
    Scenario Outline: An executable works under the worker identity with a cleared environment
      When a csharp provider program on a worker starts <executable> with an empty environment
      Then it runs as user sjones, uid 1000
      And <works>

      Examples:
        | executable             | works                                                                                                  |
        | /usr/local/bin/python3 | it reports CPython 3.12, SOABI cpython-312-x86_64-linux-gnu, Linux x86_64 and glibc 2.17 or later      |
        | /usr/local/bin/python3 | it can load wheels tagged py3-none-any, cp38-abi3-manylinux_2_17_x86_64 and cp312-cp312-manylinux_2_17_x86_64 |
        | /usr/bin/timeout       | it is GNU timeout: 124 when the child ended on termination, 137 when it had to be killed                |

    @status:not-built
    Scenario: Temporary storage is usable by a child
      When a child of a csharp provider program creates, writes, reads and deletes a file under /tmp
      Then each operation succeeds, and /tmp has at least 64 MiB free

    @status:not-built
    Scenario: timeout ends a child that ignores termination
      Given a child that ignores SIGTERM
      When it runs under /usr/bin/timeout --kill-after=2 2
      Then timeout exits 137 no earlier than 4 s and within 5 s
      And no process of the child remains

  Rule: Each execution path has published bounds

    @status:installed
    Scenario Outline: A capability's execution is bounded by its path
      When a capability executes on the <path> path
      Then <bounds>

      Examples:
        | path    | bounds                                                                                                   |
        | request | it waits at most 30 s for a free kernel, its delivery is bounded at 195 s, its answer at 198 s, within App Service's 230 s |
        | worker  | its delivery is bounded at 3600 s and its answer at 3605 s; 2 runs execute at once and 64 may wait        |
      # sfx-api.config.json and read-api-host-configuration (declarations/25).

  Rule: H4, a capability's answer reaches the caller unchanged

    @status:not-built
    Scenario: A large Unicode answer keeps its exact bytes
      Given a provider that answers 6291456 UTF-8 bytes, multi-byte characters included, with their SHA-256
      When its run's output is read through the API
      Then the output's UTF-8 bytes have the SHA-256 the provider declared

  Rule: Acceptance holds only for what was deployed

    @status:not-built
    Scenario: The checks run on every deployment the profile is promised for
      When the image, the bundle, the kernel or the profile changes
      Then T1 to T4 run again on the deployed host
      And their receipt, valid against hosted-execution-acceptance.v1, names the profile, image, bundle and kernel digests
      And the receipt is ACCEPTED only when every check passed

    @status:not-built
    Scenario: A consumer's acceptance names the profile it ran against
      When a consumer proves its capability on this host
      Then its evidence names the profile digest and the image digest of an ACCEPTED receipt
      # The renderer's proof: nh3 imported and exercised on a worker, both objectives FULFILLED. The consumer owns it
      # (consumerObligations C1 to C3 in the profile).
