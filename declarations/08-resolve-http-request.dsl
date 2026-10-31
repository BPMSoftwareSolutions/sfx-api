capability resolve-http-request
intent: Read a raw HTTP request the way the declared API ingress reads it, without serving it. It returns the method, decoded path segments, query and body, whether a well-formed credential carrier was presented, and the session digest the ingress resolves the caller by. The bearer is read and digested inside the ingress provider and never returned.
outcome: the request as the API ingress reads it
inquiry: How does the API ingress read this raw HTTP request?
input contract resolve-http-request-request.v1 {"type":"object","additionalProperties":false,"required":["contractId","raw"],"properties":{"contractId":{"const":"resolve-http-request-request.v1"},"raw":{"type":"string"}}}
output contract resolve-http-request-result.v1 {"type":"object","additionalProperties":true}
cli display outcome as json
scenario resolve-http-request root terminal
given: a raw HTTP request
when: the ingress provider reads it
then: the outcome is the request as the ingress reads it
operation resolve-http-request.read kind invoke-port port resolve-http-request-read
operation resolve-http-request.ingress kind invoke-port port resolve-http-request-ingress
platform bind resolve-http-request-read
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"path","path":"raw"}}
platform bind resolve-http-request-ingress
platform: sfx-api-ingress-resolve-port.v1
config: {"providerId":"sfx-api-ingress-resolve","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-api-ingress"}}
