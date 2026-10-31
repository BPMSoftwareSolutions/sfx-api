capability open-api-session
intent: Open a user session by declared password verification against sfx-identity, through our own providers: the host vault file is read (sfx-vault-file), the identity database credential is opened (sfx-vault-secret-service) and the sign-in port verifies the password and completes the login (sfx-identity-login). The answer carries the bearer, session, principal and expiry only for an authenticated session; the password stays in the program and never reaches SQL.
outcome: open-api-session-result.v1 with status AUTHENTICATED, tokenType Bearer, token, sessionId, principalId and expiresAt, or the refusal disposition
inquiry: Does this password open a session for this identifier?
input contract open-api-session-request.v1 {"type":"object","additionalProperties":false,"required":["login","password"],"properties":{"login":{"type":"object","additionalProperties":false,"required":["realm","identifier","sourceKey"],"properties":{"realm":{"type":"string"},"identifier":{"type":"string"},"sourceKey":{"type":"string"}}},"password":{"type":"string","minLength":1,"maxLength":1024}}}
output contract open-api-session-result.v1 {"type":"object","additionalProperties":true,"required":["status"],"properties":{"status":{"type":"string"},"tokenType":{"type":"string"},"token":{"type":"string"},"sessionId":{"type":"string"},"principalId":{"type":"string"},"expiresAt":{"type":"string"}}}
cli display outcome as json
scenario open-api-session root terminal
given: the host vault, the identity database credential SFX_IDENTITY_DATABASE and the sign-in mechanics
when: the host vault file is read, the identity database credential is opened, and the sign-in port verifies the password and completes the login
then: the outcome is AUTHENTICATED with the bearer, session, principal and expiry, or the refusal disposition
operation open-api-session.vault kind invoke-port port open-api-session-vault
operation open-api-session.credential kind invoke-port port open-api-session-credential
operation open-api-session.open kind invoke-port port open-api-session-open
operation open-api-session.login kind invoke-port port open-api-session-login
operation open-api-session.answer kind invoke-port port open-api-session-answer
platform bind open-api-session-vault
platform: sfx-vault-host-read-port.v1
config: {"providerId":"sfx-vault-file-host","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-vault-file"}}
platform bind open-api-session-credential
platform: sfx-identity-credential-port.v1
config: {"providerId":"sfx-identity-database-credential","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-database"}}
platform bind open-api-session-open
platform: sfx-vault-reference-open-port.v1
config: {"providerId":"sfx-vault-secret-service-reference","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-vault-secret-service"}}
platform bind open-api-session-login
platform: sfx-identity-login-open-port.v1
config: {"providerId":"sfx-identity-login-open","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-login"}}
platform bind open-api-session-answer
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"disposition"},"right":{"op":"literal","value":"AUTHENTICATED"}},"then":{"op":"object","fields":{"status":{"op":"literal","value":"AUTHENTICATED"},"tokenType":{"op":"literal","value":"Bearer"},"token":{"op":"path","path":"token"},"sessionId":{"op":"path","path":"sessionId"},"principalId":{"op":"path","path":"principalId"},"expiresAt":{"op":"path","path":"expiresAt"}}},"else":{"op":"object","fields":{"status":{"op":"path","path":"disposition"}}}}}
