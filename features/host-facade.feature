# Canonical feature of the hosting facade, proposed for the owner's review, 2026-11-02.
# Tags, terms and the owner's direction are in features/README.md. The facade is not a capability, so it names no
# @capability; a scenario that depends on a declared capability names it as @provider.
# Sources: host/serve.py, deploy/start.sh, deploy/Dockerfile and sfx-api.config.json at a57ebba, read from the code and
# not run; the record hosting-facade.feature it replaces; the approved features named in the comments.

@project:sfx-api
@component:host-facade
@status:proposed-for-review
Feature: The host is a facade
  As the owner
  I want host/serve.py to hold connections, start and supervise kernels, and carry out what they answer
  So that every meaning the host acts on is declared and resolved by the kernel, and none is written in the host

  "If you take a look at the history of this serve.py, you'll noticed that the intention was for it to be a facade,
  while everything else is declared up to the profile schema boundary via SEJ." (the owner, 2026-11-02)

  Approved 2026-11-01 in estate-live-observation-declared.feature: "The hosting facade holds connections and the
  channel's buffer and does what the declared capabilities answer; it decides nothing itself."

  How it turned: b12a7e5 cut host/serve.py to 33 lines that handed each request to the declared ingress and wrote back
  its answer. 64f3a28 took it to 289 lines, with a run model, event shape, lifecycle, outcome, completion input,
  responses and stream framing of its own. At a57ebba it is 803 lines.

  Rule: The container starts the host as its runtime user

    @status:installed
    Scenario: The container prepares the runtime user's home on the persistent mount, then drops to that user
      When the container starts as root
      Then start.sh creates /home/sjones on the mounted /home, owned by sjones with mode 700
      And it runs the host as sjones with HOME /home/sjones
      # deploy/start.sh:9-16; deploy/Dockerfile:11 creates sjones with uid 1000.

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
      # deploy/start.sh:35; host/serve.py:148.

  Rule: A kernel and the host change that needs it go out together

    @approved:2026-11-01
    @status:installed
    Scenario: The kernel and the host change go live together
      Then the kernel is pinned to SDA aa32214 in the same deploy as this feature's host change, never before it
      # Word for word from estate-live-observation-kernel-sampling.feature, where "this feature" is the closing-frame
      # change (project-api-run-events.feature). Deployed with sfx-api 1ac2d0f.

  Rule: The facade's own configuration says only how to listen and how to start and supervise kernels

    @status:installed
    Scenario: The facade reads its configuration from the path it is given
      When the host starts
      Then it reads its configuration from its first argument, with no default path
      # host/serve.py:61; deploy/start.sh:36 passes /opt/sfx/sfx-api.config.json.

    @status:not-built
    @finding:hidden-authority
    Scenario: The configuration holds the listener and the kernels, and nothing else
      Then the facade's configuration holds http.host and http.port, the kernel install root, and for each kind of
        kernel its command, its number of instances and its answer bound
      And every other setting the facade acts on is declared and read at start (read-api-host-configuration.feature)
      # sfx-api.config.json also holds runs.*, observation.publish, observation.requests and drawings.capabilityId,
      # intervalMilliseconds and limit, which host/serve.py interprets: meaning held as host data.

    @status:not-built
    Scenario: The configuration names the kernel once
      Then the kernel the facade runs is named only by its install root, which carries its digest
      # kernel.digest, kernel.rid and contractId are in sfx-api.config.json but host/serve.py never reads them, and
      # kernel.digest can disagree with the digest in kernel.root.

  Rule: Every request reaches the declared ingress as the client sent it

    @status:installed
    Scenario: The facade holds each connection on a thread of its own
      Then the facade serves each connection on a thread of its own, as HTTP/1.1, on its configured http.host and http.port
      # host/serve.py:620, 803; sfx-api.config.json 0.0.0.0:8787; deploy/Dockerfile:20 exposes 8787.

    @status:not-built
    @finding:hidden-authority
    @provider:serve-http-request
    Scenario: Every method reaches the ingress
      When a client sends a request with any method
      Then the facade hands it to serve-http-request, and the client receives what the ingress answers
      # host/serve.py:800 handles GET, POST, PUT, PATCH and DELETE only. For HEAD, OPTIONS or any other method the
      # platform's server answers 501 with its own HTML body, and no kernel sees the request.

    @status:not-built
    @finding:misaligned
    @provider:serve-http-request
    Scenario: A body is read up to the declared byte cap
      When a request's body is longer than the interface's requestByteCap, or is sent chunked
      Then the facade reads no more of it
      And the client receives the ingress's declared refusal
      # sidefx-api-interface.v1 declares limits.requestByteCap 16777216. host/serve.py:624 reads as many bytes as
      # Content-Length says, with no bound, and takes a chunked body's bytes as the next request on the connection.
      # 3584e29 refused a body over bodyByteCap with 413; b12a7e5 removed the bound.

    @status:not-built
    @finding:fallback
    @provider:serve-http-request
    Scenario: No byte of a request is changed before the ingress reads it
      When a request's line, headers or body hold bytes that are not UTF-8
      Then the ingress receives those bytes unchanged
      # host/serve.py:623-624 decodes the request as UTF-8 and replaces each invalid byte with U+FFFD. The request
      # envelope's inputType text cannot carry such bytes; whether the kernel takes a byte input was not checked.

    @status:not-built
    @finding:hidden-authority
    Scenario: A request waits for a free request kernel within a declared bound
      Given every request kernel is busy
      When a request arrives
      Then it waits at most the declared wait (read-api-host-configuration.feature)
      And past it the client receives the declared busy refusal, and no kernel takes the request
      # host/serve.py:625 waits without a bound on one request kernel (kernel.instances 1), and a client that gives up
      # still holds the kernel until it answers. README.md measured 30 abandoned requests delaying the next one 68 s.

  Rule: The facade writes exactly what the kernel answers

    @status:installed
    @provider:serve-http-request
    Scenario: A response that is not a directive is written unchanged
      When the ingress answers a response that is not application/vnd.sfx.host-directive+json
      Then the facade writes its bytes to the connection unchanged
      # host/serve.py:644-649.

    @status:not-built
    @finding:hidden-authority
    @provider:serve-http-request
    Scenario: A directive's response is written as declared
      When a directive answers execute-run or respond
      Then the response the client receives, its status line, headers and body, is the one its declaration composed
      # host/serve.py:661-665 writes the status line with the platform's reason phrase and adds Content-Type,
      # Content-Length, Cache-Control no-store and Connection close itself. b12a7e5 made compose-response the declared
      # writer of every response. declarations/11 composes execute-run's and respond's response in full (respond.raw):
      # status line, Content-Type, Cache-Control no-store and Connection close, without Content-Length, so the body ends
      # where the connection closes. SEJ measures a string in characters, not UTF-8 bytes, and only compose-response, a
      # provider program, counts bytes.

    @status:not-built
    @finding:hidden-authority
    Scenario: A delivery that answers no response is answered with the declared failure response
      When the request kernel's delivery carries no response
      Then the client receives the failure response the host declares (read-api-host-configuration.feature)
      # host/serve.py:639-643 and 661-665 compose 502 {"error":{"code":"KERNEL_DELIVERY_FAILED"}} themselves.
      # declarations/25 declares that response in full as request.failure.

    @status:not-built
    @finding:fallback
    Scenario Outline: A directive the facade cannot carry out is refused
      When the kernel answers <directive>
      Then the client receives the declared failure response
      And the host log names the directive

      Examples:
        | directive                                                                 | what happens today (host/serve.py)          |
        | a directive other than execute-run, stream-run, stream-estate or respond | it is answered as respond (:650-659)        |
        | a directive whose body is not JSON                                        | the connection ends without an answer (:650) |
        | a directive with no respond                                               | the connection ends without an answer (:659) |
        | a directive naming a status the platform does not know                    | the connection ends without an answer (:664) |
      # Every directive declarations/11, 12 and 21 answer names its contract, sfx-api-host-directive.v1, so the facade
      # can refuse any other.

    @status:not-built
    @finding:hidden-authority
    Scenario: A response that says Connection close closes the connection
      When the facade has written a response that is not a stream and says Connection close
      Then it closes the connection
      # The platform's server keeps the connection for the client's next request unless the request asked to close
      # it: host/serve.py never sets close_connection (:648, 661-665).

    @status:installed
    Scenario: A client that disconnects ends its stream quietly
      When a client disconnects from a run stream or the channel
      Then the facade stops writing to it and logs nothing
      # host/serve.py:713, 797.

  Rule: The facade starts, feeds and supervises kernels, and the kernels decide what they answer

    @status:installed
    Scenario: Four kinds of kernel run in one install root
      Then the facade runs request kernels, run workers, one channel publisher and one drawing reader
      And each runs in the configured kernel install root with its own command
      # host/serve.py:147, 399, 570, 607-614; sfx-api.config.json kernel.instances 1 and workers.instances 2.

    @status:not-built
    @finding:hidden-authority
    Scenario: Bookkeeping never borrows a request kernel
      Then session rechecks and run selections run on a kernel of their own
      And no request waits behind a recheck or a selection, and no recheck or selection waits behind a request
      # host/serve.py:295 and 371 borrow a request kernel for them, so every open stream's recheck queues with requests
      # on the one request kernel.

    @status:not-built
    Scenario: Every kernel starts, and admits the host's bundle, before the facade listens
      When the host starts
      Then it starts every kind of kernel before it binds its port
      And a kernel that refuses the host's bundle stops the host (host-declared-read-provider.feature)
      # Today the drawing reader starts with the host, and the request kernel, the workers and the publisher start on
      # their first use (host/serve.py:399, 575-578, 607-616).

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
      # host/serve.py:112-121. The kernel never read the envelope, so it cannot have begun it.

    @status:not-built
    @finding:fallback
    Scenario: An envelope a kernel may have begun is never delivered again
      When a kernel answers a failure that is not a timeout, and exits
      Then the delivery fails with that failure
      And the envelope is not delivered to another kernel
      # host/serve.py:93-106 delivers it again, to a new kernel, when the kernel exits within 3 seconds, run envelopes
      # included, on d818720's reading that such a kernel had not begun it. No contract states that, and a run whose
      # kernel had begun would execute twice.

    @status:installed
    Scenario Outline: A kernel that does not answer fails its delivery
      When a kernel <does>
      Then the delivery answers <code>
      And the next envelope starts a new kernel

      Examples:
        | does                              | code           |
        | overruns its answer bound         | KERNEL_TIMEOUT |
        | ends its output without an answer | KERNEL_EXITED  |
      # host/serve.py:125-140; a kernel that overruns its bound is killed.

    @status:not-built
    @finding:fallback
    Scenario: A kernel whose answer is not JSON is stopped
      When a kernel writes an answer line that is not JSON
      Then the delivery answers KERNEL_ANSWER_INVALID
      And that kernel is stopped, so no later line it writes is read as another envelope's answer
      # host/serve.py:125-140 keeps the kernel running, so a later line it writes for this envelope is read as the next
      # envelope's answer.

  Rule: The facade fans in what kernels write, as they wrote it

    @status:installed
    Scenario: A kernel's diagnostics reach the host log unchanged
      When a kernel writes a diagnostic line that is not an observation
      Then the host log carries that line
      # host/serve.py:141-143.

    @status:not-built
    @finding:hidden-authority
    Scenario: A delivery without an outcome is logged whole
      When a delivery carries no outcome
      Then the host log names its subject and carries its whole error
      # host/serve.py:179-182 keeps the first 2000 characters of the error.

    @status:not-built
    @finding:hidden-authority
    Scenario: An observation belongs to the execution its delivery's declared ref names
      When a kernel writes an observation line
      Then it belongs to the execution named by its delivery's declared observation ref
      And a line that no declared ref names is not published
      # host/serve.py:195-197 gives it to whichever execution the facade has attached to that kernel when the line is
      # read, and drops it when none is attached. The ref is declared: admit-api-run-live.feature.

    @approved:2026-11-01
    @status:installed
    Scenario: The host's own deliveries are not sampled
      Then worker kernels run without SIDEFX_OBSERVE, so a delivery without the member is not sampled
      And the trace and completion the host invokes around a run write no observations
      # Word for word from estate-live-observation-kernel-sampling.feature; built in 1ac2d0f.

    @status:installed
    Scenario: The host log carries no request
      Then the facade writes no log line for a request it answers
      # The platform's access log line is written only by send_response, which host/serve.py never calls. A request's
      # execution is observed on the channel: publish-estate-live-observation.feature.
