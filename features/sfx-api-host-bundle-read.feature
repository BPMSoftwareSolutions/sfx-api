# Review copy for the owner and the owner's team, 2026-11-03.
#
# What this file is: the behavior of the provider capability sfx-api-host-bundle-read-port.v1 (provider
# sfx-api-host-bundle-read), written as Gherkin. It reads one document of the host's pinned bundle for
# answer-host-declared-read and answers it only when its digest is the one the manifest names. The sources are SDA
# 1bd400e (rule D13: "The kernel reads no document and checks no digest: the graph source is the binding's data, and
# pinning it is the host's"; SDA's note to sfx-api: "Reading the bundle under authorities/host-bundle/ needs a file-read
# provider module that you bind; SDA ships none") and answer-host-declared-read.feature.
#
# Status tags:
#   @status:proven         ran against the estate or on sfx-api-test, and the run is cited
#   @status:probed         ran on its own against the estate or sfx-api-test; README.md records it without a run id
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
#   bundle               the host's own declarations in SEJ, under authorities/host-bundle/, and the manifest that names
#                        each document's SHA-256 digest
#   pin                  the SHA-256 digest of the manifest, named by answer-host-declared-read's graph source

@project:sfx-api
@status:proposed-for-review
Feature: A bundle document is read only when it is the document the pin names
  As the owner
  I want each document of the host's bundle read by a declared provider that checks its digest
  So that the host serves its own declarations exactly as pinned, or does not serve them

  The owner's directions (features/README.md, "The owner's direction"):
  "providers are declared capabilities as well." (2026-11-03)
  "Nothing ... dictates C# in the kernel. You decide by declaring up to the profile schema boundary." (2026-11-03)
  "our canonical features need to call out the SLO targets (SLA, SLI, etc.) so we don't lose our ... performance
  strategies" (2026-11-03)

  Provider acceptance applies to every scenario that invokes a provider. Each required provider has one @provider:<id>
  tag on that scenario. For each expected call, acceptance compares the tag with the accepted binding for that scenario
  and step, then reads the invocation and its returned outcome from the scenario run. Repeated calls to one tagged
  provider each need their own evidence. A probe establishes only the path it actually exercised.

  Rule: A document is answered only with the digest the manifest names

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: A document whose digest matches is answered
      Given the manifest names a document and its SHA-256 digest
      When answer-host-declared-read reads that document through the provider
      Then the provider answers the document's text
      # The program reads the file's bytes, digests them and keeps them only under the declared digest, as
      # sfx-identity-login's program keeps a package only under its declared digest (sfx-identity-login-open.feature).

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario Outline: A document that is not the pinned one fails the read
      When the provider reads a document that <defect>
      Then the read fails, and the delivery with it
      And nothing of the document is answered

      Examples:
        | defect                                             |
        | has another SHA-256 digest than the manifest names |
        | is missing                                         |
        | is not UTF-8 JSON                                  |

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: The manifest is read against the pin the same way
      When the provider reads the manifest
      Then it answers the manifest only when its SHA-256 digest is the pin answer-host-declared-read's graph source names

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: Only documents the manifest names are read
      When answer-host-declared-read reads for any capability
      Then the provider is given only the manifest or a document the manifest names, never a path a request carries
      # The document a read needs is found in the manifest by the read's capabilityId; a capability the manifest does not
      # own reads no document (answer-host-declared-read.feature).

  Rule: The provider reads files and nothing else

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: The provider holds no connection, credential or secret
      Then the provider opens no connection and holds no credential
      And it reads only files under the bundle's root, which hold no secret
      # answer-host-declared-read.feature: "no secret is in the bundle, the provider authority or the provider's binding".

  Rule: Every provider-dependent step names its provider binding and proves it

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: Each bundle read honors its binding, proved by the run
      Given this step depends on this provider binding:
        | calls                                     | provider capability the step needs                                         | result it must produce here  | run evidence that proves it               |
        | answer-host-declared-read's document read | sfx-api-host-bundle-read-port.v1, provider sfx-api-host-bundle-read        | the document, digest-checked | the cell's testimony in the delivery     |
      When a delivery reads an owned capability for the first time in a kernel
      Then the call produces the document its binding requires
      # Nothing checks provider bindings yet.

  Rule: The provider is declared up to the profile schema boundary

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    Scenario: Its program is declared for each runtime the host declares
      Then providers/sfx-api-host-bundle.dependency.json declares the read-document program for each runtime language the
        host's kernels run, and the host declares that language with its kernel in sfx-api.config.json
      And no module or type of the host's own implements it
      # SDA ships no file-read provider (its note to sfx-api, 2026-11-03).

  Rule: Reading the bundle keeps the host's service levels

    @status:not-built
    @capability:answer-host-declared-read
    @provider:sfx-api-host-bundle-read-port.v1
    @slo:warm-definitions
    Scenario: A warm envelope reads no bundle document
      When an envelope runs an owned capability its kernel has already answered under the same generation and pin
      Then the provider reads no document
      # SDA D11: the declaration cache serves the port provider's earlier answers under that key, so a document is read
      # once per kernel per key.
