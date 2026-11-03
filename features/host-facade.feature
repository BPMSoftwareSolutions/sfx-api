# Canonical feature of the hosting facade, proposed for the owner's review, 2026-11-02. Re-derived on 2026-11-03 from the
# facade deployed at 5eb18bf.
# Tags, terms and the owner's direction are in features/README.md. The facade is not a capability, so it names no
# @capability; a scenario that depends on a declared capability names it as @provider.
# Sources:
# - host/serve.py, deploy/start.sh, deploy/Dockerfile and sfx-api.config.json at 5eb18bf, read from the code;
# - the facade's runs on WSL against the estate, where a scenario says so (README.md, Verified);
# - the record hosting-facade.feature it replaces, and the approved features named in the comments.

@project:sfx-api
@component:host-facade
@status:proposed-for-review
Feature: The host is a facade
  As the owner
  I want host/serve.py to be only the frontdoor: hand each request to the kernel and write back what it answers
  So that every meaning and every mechanic the host acts on is declared, and none is written in the host

  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (the owner, 2026-11-02)

  "move everything in serve.py to declaration and only include a frontdoor facade (no mechanics) in serve.py." (the
  owner, 2026-11-03)

  Approved 2026-11-01 in estate-live-observation-declared.feature: "The hosting facade holds connections and the
  channel's buffer and does what the declared capabilities answer; it decides nothing itself."

  How it turned:
  - b12a7e5 cut host/serve.py to 33 lines that handed each request to the declared ingress and wrote back its answer.
  - 64f3a28 took it to 289 lines, with a run model, event shape, lifecycle, outcome, completion input, responses and
    stream framing of its own.
  - At a57ebba it was 803 lines.
  - At 5eb18bf it is 927 lines, 716 of them code. Every response, frame and setting it writes is declared, but about 500
    of those lines are a runtime that outlives an envelope: a run executor, a stream server, the live observation
    channel, session rechecks and the drawing poll. The first rule below holds the owner's direction for that runtime;
    the others describe the facade as it is.

  Rule: The facade is the frontdoor and nothing else

    @status:not-built
    @finding:hidden-authority
    Scenario: The facade holds no runtime of its own
      Then host/serve.py starts the kernel, listens, hands each request's bytes to it and writes back each part it answers
      And it holds no run, stream, channel, session recheck or poll of its own
      # At 5eb18bf it holds a run executor (host/serve.py:214-421), a stream server (:439-495, 778-893), the live
      # observation channel (:510-616) and the drawing poll (:619-654). They move into declarations once the kernel can
      # serve concurrent envelopes, answer in parts, keep work after its envelope and keep a provider's state for the
      # life of its process (docs/request-sda-frontdoor-only-host.md).

  Rule: The container starts the host as its runtime user

    @status:installed
    Scenario: The container prepares the runtime user's home on the persistent mount, then drops to that user
      When the container starts as root
      Then start.sh creates /home/sjones on the mounted /home, owned by sjones with mode 700
      And it runs the host as sjones with HOME /home/sjones
      # deploy/start.sh:9-16; deploy/Dockerfile:12 creates sjones with uid 1000.

    @status:installed
    Scenario: The container does not start without its three vault settings
      When SFX_CREDENTIAL_VAULT_B64, SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 or SFX_CREDENTIAL_VAULT_KEY is unset
      Then start.sh exits before the host starts
      # deploy/start.sh:17-19.

    @status:installed
    Scenario: The vault's key record and key come from the settings at every start
      Then start.sh writes the key record from SFX_CREDENTIAL_VAULT_KEY_RECORD_B64 at every start
      And it stores SFX_CREDENTIAL_VAULT_KEY in the keyring at every start
      # deploy/start.sh:5-6 states the rule; :25 and :34 carry it out. The vault itself is seeded only when /home has
      # none: durable-credential-vault.feature.

    @status:installed
    Scenario: No kernel inherits the vault settings
      Then start.sh removes the three settings from the environment before the host starts
      And every kernel runs with the environment the host then has
      # deploy/start.sh:35; host/serve.py:134.

  Rule: A kernel and the host change that needs it go out together

    @approved:2026-11-01
    @status:installed
    Scenario: The kernel and the host change go live together
      Then the kernel is pinned to SDA aa32214 in the same deploy as this feature's host change, never before it
      # Word for word from estate-live-observation-kernel-sampling.feature, where "this feature" is the closing-frame
      # change (project-api-run-events.feature). Deployed with sfx-api 1ac2d0f. At 5eb18bf the kernel is SDA 29355da's,
      # deployed with the facade and the bundle it needs.

  Rule: The facade's own configuration says only how to listen and how to start and supervise kernels

    @status:installed
    Scenario: The facade reads its configuration from the path it is given
      When the host starts
      Then it reads its configuration from its first argument, with no default path
      # host/serve.py:56; deploy/start.sh:36 passes /opt/sfx/sfx-api.config.json.

    @status:installed
    Scenario: The configuration holds the listener and the kernels, and nothing else
      Then the facade's configuration holds http.host and http.port, the kernel install root, and for each kind of
        kernel its command, its number of instances and its answer bound
      And every other setting the facade acts on is declared and read at start (read-api-host-configuration.feature)
      # sfx-api.config.json at 5eb18bf. The facade carries out read-api-host-configuration's answer as its settings
      # (host/serve.py:901-916).

    @status:installed
    Scenario: The configuration names the kernel once
      Then the kernel the facade runs is named only by its install root, which carries its digest
      # sfx-api.config.json kernel.root; no other member names the kernel.

  Rule: Every request reaches the declared ingress as the client sent it

    @status:installed
    Scenario: The facade holds each connection on a thread of its own
      Then the facade serves each connection on a thread of its own, as HTTP/1.1, on its configured http.host and http.port
      # host/serve.py:715, 929; sfx-api.config.json 0.0.0.0:8787; deploy/Dockerfile exposes 8787.

    @status:installed
    @provider:serve-http-request
    Scenario: Every method reaches the ingress
      When a client sends a request with any method
      Then the facade hands it to serve-http-request, and the client receives what the ingress answers
      # host/serve.py:717-721 answers every do_<method> with the same handler.

    @status:not-built
    @finding:misaligned
    @provider:serve-http-request
    Scenario: A body is read up to the declared byte cap
      When a request's body is longer than the interface's requestByteCap, or is sent chunked
      Then the facade reads no more of it
      And the client receives the ingress's declared refusal
      # sidefx-api-interface.v1 declares limits.requestByteCap 16777216. host/serve.py:724-725 reads as many bytes as
      # Content-Length says, with no bound, and takes a chunked body's bytes as the next request on the connection.
      # 3584e29 refused a body over bodyByteCap with 413; b12a7e5 removed the bound.

    @status:not-built
    @finding:fallback
    @provider:serve-http-request
    Scenario: No byte of a request is changed before the ingress reads it
      When a request's line, headers or body hold bytes that are not UTF-8
      Then the ingress receives those bytes unchanged
      # host/serve.py:724-725 decodes the request as UTF-8 and replaces each invalid byte with U+FFFD. The request
      # envelope's inputType text cannot carry such bytes; whether the kernel takes a byte input was not checked.

    @status:installed
    Scenario: A request waits for a free request kernel within a declared bound
      Given every request kernel is busy
      When a request arrives
      Then it waits at most the declared wait (read-api-host-configuration.feature)
      And past it the client receives the declared busy refusal, and no kernel takes the request
      # host/serve.py:726-729 waits request.waitMilliseconds, declared as 2000, then writes request.busy. A client that
      # gives up still holds its kernel until the kernel answers: "A request kernel is released when its client goes".

  Rule: The facade writes exactly what the kernel answers

    @status:probed
    @provider:serve-http-request
    Scenario: A response that is not a directive is written unchanged
      When the ingress answers a response that is not application/vnd.sfx.host-directive+json
      Then the facade writes its bytes to the connection unchanged
      # host/serve.py:737-743. On WSL against the estate the facade answered 404 OPERATION_NOT_DECLARED, 401
      # CALLER_REQUIRED and 400 LOGIN_INPUT_INVALID as the kernel answered them (README.md, Verified).

    @status:installed
    @provider:serve-http-request
    Scenario: A directive's response is written as declared
      When a directive answers execute-run or respond
      Then the response the client receives, its status line, headers and body, is the one its declaration composed
      # host/serve.py:755-763 writes respond.raw unchanged. declarations/11 composes execute-run's and respond's response
      # in full.

    @status:installed
    Scenario: A delivery that answers no response is answered with the declared failure response
      When the request kernel's delivery carries no response
      Then the client receives the failure response the host declares (read-api-host-configuration.feature)
      # host/serve.py:737-738 writes request.failure, which declarations/25 declares in full.

    @status:installed
    Scenario Outline: A directive the facade cannot carry out is refused
      When the kernel answers <directive>
      Then the client receives the declared failure response
      And the host log names the directive

      Examples:
        | directive                                                                 | where host/serve.py refuses it |
        | a directive other than execute-run, stream-run, stream-estate or respond | :756-757                       |
        | a directive whose body is not JSON, or names another contract             | :744-750                       |
        | a directive with no respond                                               | :755-757                       |
        | a run, stream or subscription the facade cannot carry out                 | :751-760                       |
      # host/serve.py:772-776 logs the directive's contract and kind, and writes request.failure.

    @status:installed
    Scenario: A response that says Connection close closes the connection
      When the facade has written a response that is not a stream and says Connection close
      Then it closes the connection
      # host/serve.py:765-770.

    @status:installed
    Scenario: A client that disconnects ends its stream quietly
      When a client disconnects from a run stream or the channel
      Then the facade stops writing to it and logs nothing
      # host/serve.py:813, 892.

  Rule: The facade starts, feeds and supervises kernels, and the kernels decide what they answer

    @status:installed
    Scenario: Four kinds of kernel run in one install root
      Then the facade runs two request kernels, two run workers, one channel publisher and one drawing reader
      And each runs in the configured kernel install root with its own command
      # host/serve.py:134, 901-904; sfx-api.config.json kernel.instances 2, workers 2, publisher 1 and drawings 1: six
      # kernels, four of them from the start. The owner chose the set on 2026-11-03: two request kernels, so that the
      # Explorer's concurrent reads are not refused REQUEST_KERNEL_BUSY behind one; workers that start on their first run;
      # and the host's bookkeeping on the drawing reader's kernel. Before it, image 5eb18bf ran one request kernel and a
      # bookkeeping kernel of its own, all six from the start.

    @status:installed
    Scenario: Bookkeeping never borrows a request kernel
      Then session rechecks, run selections, and a run's events, trace, completion and facts run on the drawing reader's
        kernel
      And no request waits behind them, and none of them waits behind a request
      # host/serve.py:204-211 and 619-654 take that kernel from one queue, so bookkeeping and the drawing poll never
      # deliver to it at once. A recheck can wait behind a drawing poll, about 1 s on WSL.

    @status:installed
    Scenario: The request kernels, the publisher and the drawing reader admit the host's bundle before the facade listens
      When the host starts
      Then it starts the request kernels, the publisher and the drawing reader before it binds its port
      And a kernel that refuses the host's bundle stops the host (answer-host-declared-read.feature)
      And a run worker starts on its first run
      # host/serve.py:901-916, then 929; a worker is started by host/serve.py:371-421. Image 5eb18bf started all six
      # kernels before listening. Its first, cold start on sfx-api-test stopped before listening: a kernel ran past its
      # 58 s bound admitting the bundle while six kernels started on one vCPU. The next start admitted all six within
      # 19 s (docs/azure-test-2026-11-03.md).

    @status:not-built
    Scenario: A cold start admits every kernel within its answer bound
      When the host starts from a newly pulled image on its plan's one vCPU
      Then every kernel admits the host's bundle within its answer bound, and the host listens on its first start
      # On 2026-11-03 the first start after the swap failed this way and cost about 50 s of 503s
      # (docs/azure-test-2026-11-03.md). Four kernels now admit at start instead of six.

    @status:installed
    Scenario: Each kind of kernel has its answer bound
      Then the facade waits 228 s for a request kernel bounded at 225 s, 3605 s for a worker bounded at 3600 s, and
        58 s for the publisher and the drawing reader, each bounded at 55 s
      # sfx-api.config.json answerTimeoutMs, and --timeout in each command.

    @status:installed
    @finding:fallback
    Scenario: An envelope a kernel never read is written to a new kernel, once
      When writing an envelope to a kernel fails because the kernel has ended
      Then the facade starts a new kernel and writes the envelope to it, once
      # host/serve.py:97-106. The kernel never read the envelope, so it cannot have begun it.

    @status:installed
    Scenario: An envelope a kernel may have begun is never delivered again
      When a kernel answers a failure that is not a timeout, and exits
      Then the delivery fails with that failure
      And the envelope is not delivered to another kernel
      # host/serve.py:97-126 writes an envelope again only when writing it failed. A kernel that ends after reading it
      # answers KERNEL_EXITED.

    @status:installed
    Scenario Outline: A kernel that does not answer fails its delivery
      When a kernel <does>
      Then the delivery answers <code>
      And the next envelope starts a new kernel

      Examples:
        | does                              | code           |
        | overruns its answer bound         | KERNEL_TIMEOUT |
        | ends its output without an answer | KERNEL_EXITED  |
      # host/serve.py:107-126; a kernel that does not answer is stopped.

    @status:installed
    Scenario: A kernel whose answer is not JSON is stopped
      When a kernel writes an answer line that is not JSON
      Then the delivery answers KERNEL_ANSWER_INVALID
      And that kernel is stopped, so no later line it writes is read as another envelope's answer
      # host/serve.py:114-123.

  Rule: The facade fans in what kernels write, as they wrote it

    @status:installed
    Scenario: A kernel's diagnostics reach the host log unchanged
      When a kernel writes a diagnostic line that is not an observation
      Then the host log carries that line
      # host/serve.py:165-172.

    @status:installed
    Scenario: A delivery without an outcome is logged whole
      When a delivery carries no outcome
      Then the host log names its subject and carries its whole error
      # host/serve.py:128-130.

    @status:installed
    Scenario: An observation belongs to the execution its delivery's declared ref names
      When a kernel writes an observation line
      Then it belongs to the execution named by its delivery's declared observation ref
      And a line that no declared ref names is not published
      # host/serve.py:165-192 gives a line to the run expecting the ref that its stream's opening frame names. The ref is
      # declared: admit-api-run-live.feature.

    @approved:2026-11-01
    @status:installed
    Scenario: The host's own deliveries are not sampled
      Then worker kernels run without SIDEFX_OBSERVE, so a delivery without the member is not sampled
      And the trace and completion the host invokes around a run write no observations
      # Word for word from estate-live-observation-kernel-sampling.feature; built in 1ac2d0f. At 5eb18bf the host's own
      # deliveries carry no observation member (host/serve.py:197-201).

    @status:installed
    Scenario: The host log carries no request
      Then the facade writes no log line for a request it answers
      # The platform's access log line is written only by send_response, which host/serve.py never calls. A request's
      # execution is observed on the channel: publish-estate-live-observation.feature.

  Rule: The facade keeps the host's service levels

    @status:installed
    @slo:request-answer-bound
    Scenario: No request outlives App Service's 230 s bound
      Given the service level:
        | SLI                                          | SLA                                  | baseline                                                   |
        | time from a request's receipt to its answer  | every request answered within 230 s  | each kernel's answer bound: 228000 ms for a request kernel |
      When the facade receives a request
      Then it writes the request's answer within 230 s of receiving it: its kernel's answer, the declared busy response or
        the declared failure response
      # A request waits at most the declared 2000 ms for a free kernel, and its kernel answers within 228 s or its delivery
      # fails ("A request waits for a free request kernel within a declared bound", "Each kind of kernel has its answer
      # bound").

    @status:proven
    @slo:no-kernel-start-on-request
    Scenario: No request pays a kernel start once the host listens
      Given the service level:
        | SLI                                                  | SLO target | baseline                                                                       |
        | kernel starts a request pays after the host listens  | none       | the first request after the f32450fa swap took 13.8 s, the kernel's start included |
      When the host has started listening
      Then no request waits for a kernel to start
      # The facade starts its request kernels before it listens ("The request kernels, the publisher and the drawing
      # reader admit the host's bundle before the facade listens"). A run's first execution pays its worker's start; the
      # request that admitted it does not. On sfx-api-test on 2026-11-03, after the site started, no request paid a
      # kernel start (docs/azure-test-2026-11-03.md). docs/azure-test-2026-10-31.md: on the 64f3a28 site, App Service's
      # warm-up probe paid the kernel start.

    @status:not-built
    @slo:abandoned-request-release
    Scenario: A request kernel is released when its client goes
      Given the service level:
        | SLI                                                     | SLO target                            | baseline                                                  |
        | time a request kernel stays held after its client goes  | free when the client goes (proposed)  | 30 abandoned requests queued the next request 68 s (WSL)  |
      When a client gives up on a request its kernel is still answering
      Then that kernel is free for the next request at once
      # README.md, Verified and Next 5: "a client that gives up still holds a kernel until it answers". Freeing a kernel
      # mid-envelope means stopping it, which costs a kernel start: features/README.md, Q2.

    @status:not-built
    @slo:frontdoor-tail-explained
    Scenario: Every slow warm request names where its time went
      Given the service level:
        | SLI                                                                | SLO target            | baseline                               |
        | warm requests over 1.05 s whose delivery evidence names the cause  | every one (proposed)  | 5 of 30 took 1.2 to 4.0 s, cause open  |
      When a warm request takes longer than 1.05 s
      Then the delivery's evidence names the phase its time went to
      # docs/azure-test-2026-10-31.md: "The facade does not record the kernel's evidence, so their cause is open."

    @status:probed
    @slo:plan-memory
    Scenario: The host keeps the plan's memory within its objective
      Given the service level:
        | SLI                                                 | SLO target              | baseline                                         |
        | memory of the App Service plan while the host runs  | at most 64% (proposed)  | 59% with one resident kernel, 64% during a swap  |
      When the host runs its kernels on the shared plan
      Then the plan's memory stays within the target
      # docs/azure-test-2026-10-31.md. Each run worker adds about 350 MB (README.md, Next 2). On 2026-11-03, with
      # a57ebba's host, the plan's hourly average memory was 65 to 82% over a day, peaking at 90%. At 5eb18bf the six
      # kernels measured 1068 MiB at start and 1172 MiB after use on WSL (README.md, Verified). On sfx-api-test the plan
      # ran at 77 to 78% before the 5eb18bf swap, peaked at 92% during it, and held 60% afterwards
      # (docs/azure-test-2026-11-03.md). That is before any run has grown a worker.
