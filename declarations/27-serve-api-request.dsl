capability serve-api-request
intent: The declared API frontdoor. It carries sidefx-api-interface.v1 in its own declaration (the SEJ serve-carry-interface), so it reads no interface from the estate it serves: identify the caller (identity.resolve_api_session on sfx-identity resolves the session the caller's digest names), carry the request and its caller with the interface, resolve the declared operation, admit the caller and bind its input in SEJ, run the operation's capability, and compose the api-response.v1. A refusal is answered as declared, through answer-api-response.
outcome: the api-response.v1 of the request: status, headers and body
inquiry: What does the frontdoor answer for this request?
input contract serve-api-request-request.v1 {"type":"object","additionalProperties":false,"required":["request"],"properties":{"request":{"type":"object"},"caller":{"type":["object","null"]}}}
output contract serve-api-request-result.v1 {"type":"object","additionalProperties":true,"required":["contractId","status"],"properties":{"contractId":{"const":"api-response.v1"},"status":{"type":"integer"}}}
cli display outcome as json
scenario serve-api-request root terminal
given: an HTTP request and its caller
when: the kernel identifies the caller, resolves the request against the interface its declaration carries, and runs the operation's capability
then: the outcome is the declared api-response.v1
operation serve-api-request.identify-prepare kind invoke-port port serve-api-request-identify-prepare
operation serve-api-request.identify kind invoke-port port serve-api-request-identify
operation serve-api-request.identify-lift kind invoke-port port serve-api-request-identify-lift
operation serve-api-request.carry kind invoke-port port serve-api-request-carry
operation serve-api-request.resolve kind invoke-port port serve-api-request-resolve
operation serve-api-request.dispatch kind invoke-port port serve-api-request-dispatch
operation serve-api-request.respond kind invoke-port port serve-api-request-respond
platform bind serve-api-request-identify-prepare
platform: sda-authority-transformation-port.v1
config: {"transformationAuthorityRef":"semantic-transformation.authority.json","transformationId":"serve-identify-prepare"}
platform bind serve-api-request-identify
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind serve-api-request-identify-lift
platform: sda-authority-transformation-port.v1
config: {"transformationAuthorityRef":"semantic-transformation.authority.json","transformationId":"serve-identify-lift"}
platform bind serve-api-request-carry
platform: sda-authority-transformation-port.v1
config: {"transformationAuthorityRef":"semantic-transformation.authority.json","transformationId":"serve-carry-interface"}
platform bind serve-api-request-resolve
platform: sda-authority-transformation-port.v1
config: {"transformationAuthorityRef":"semantic-transformation.authority.json","transformationId":"serve-resolve-request"}
platform bind serve-api-request-dispatch
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind serve-api-request-respond
platform: sda-authority-transformation-port.v1
config: {"transformationAuthorityRef":"semantic-transformation.authority.json","transformationId":"serve-compose-response"}
