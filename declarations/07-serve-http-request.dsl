capability serve-http-request
intent: The declared HTTP ingress of the API. The hosting facade hands it the raw request it received and writes back the response it answers, and the kernel resolves everything between them. It reads the method, decoded path segments, query and body of the request and the session digest of its credential carrier, where the bearer is read and digested inside the ingress provider and never leaves it. It runs the frontdoor serve-api-request and composes the raw HTTP/1.1 response.
outcome: the raw HTTP/1.1 response of the request
inquiry: What does the API answer for this raw HTTP request?
input contract serve-http-request-request.v1 {"type":"object","additionalProperties":false,"required":["contractId","raw"],"properties":{"contractId":{"const":"serve-http-request-request.v1"},"raw":{"type":"string"}}}
output contract serve-http-request-result.v1 {"type":"string"}
cli display outcome as json
scenario serve-http-request root terminal
given: a raw HTTP request as the hosting facade received it
when: the kernel resolves the request, runs the frontdoor and composes the response
then: the outcome is the raw HTTP/1.1 response
operation serve-http-request.read kind invoke-port port serve-http-request-read
operation serve-http-request.ingress kind invoke-port port serve-http-request-ingress
operation serve-http-request.prepare kind invoke-port port serve-http-request-prepare
operation serve-http-request.frontdoor kind invoke-port port serve-http-request-frontdoor
operation serve-http-request.shape kind invoke-port port serve-http-request-shape
operation serve-http-request.respond kind invoke-port port serve-http-request-respond
platform bind serve-http-request-read
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"path","path":"raw"}}
platform bind serve-http-request-ingress
platform: sfx-api-ingress-resolve-port.v1
config: {"providerId":"sfx-api-ingress-resolve","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-api-ingress"}}
platform bind serve-http-request-prepare
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"executionTarget":{"op":"literal","value":"serve-api-request"},"executionNamespace":{"op":"literal","value":"sidefx:capabilities"},"executionScenario":{"op":"literal","value":"serve-api-request"},"inputType":{"op":"literal","value":"json"},"dispatchRequest":{"op":"object","fields":{"request":{"op":"object","fields":{"method":{"op":"path","path":"method"},"segments":{"op":"path","path":"segments"},"query":{"op":"let","bindings":{"parsed":{"op":"try-parse-json","value":{"op":"path","path":"queryJson"}}},"value":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","from":"parsed","path":"value"}},"right":{"op":"literal","value":"object"}},"then":{"op":"path","from":"parsed","path":"value"},"else":{"op":"literal","value":{}}}},"body":{"op":"path","path":"body"}}},"caller":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"carried"},"right":{"op":"literal","value":true}},"then":{"op":"object","fields":{"sessionDigest":{"op":"path","path":"sessionDigest"}}},"else":{"op":"literal","value":null}}}}}}}
platform bind serve-http-request-frontdoor
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind serve-http-request-shape
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"let","bindings":{"response":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"result.contractId"},"right":{"op":"literal","value":"api-response.v1"}},"then":{"op":"path","path":"result"},"else":{"op":"object","fields":{"status":{"op":"literal","value":502},"headers":{"op":"literal","value":{"content-type":"application/json; charset=utf-8"}},"body":{"op":"object","fields":{"error":{"op":"object","fields":{"code":{"op":"literal","value":"FRONTDOOR_RESPONSE_INVALID"},"message":{"op":"path","path":"result.message"}}}}}}}}},"value":{"op":"object","fields":{"status":{"op":"path","from":"response","path":"status"},"contentType":{"op":"path","from":"response","path":"headers.content-type"},"body":{"op":"path","from":"response","path":"body"},"reasons":{"op":"literal","value":{"200":"OK","201":"Created","202":"Accepted","204":"No Content","400":"Bad Request","401":"Unauthorized","403":"Forbidden","404":"Not Found","405":"Method Not Allowed","409":"Conflict","413":"Content Too Large","415":"Unsupported Media Type","422":"Unprocessable Content","429":"Too Many Requests","500":"Internal Server Error","501":"Not Implemented","502":"Bad Gateway","503":"Service Unavailable","504":"Gateway Timeout"}}}}}}
platform bind serve-http-request-respond
platform: sfx-api-ingress-compose-port.v1
config: {"providerId":"sfx-api-ingress-compose","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-api-ingress"}}
