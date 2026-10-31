capability check-api-session
intent: Confirm a caller session for the declared API: LIVE while the session is unrevoked and unexpired and its principal active, else ENDED. The hosting facade calls it at the declared recheck interval while a session caller's event stream is open, and ends the stream at the first answer that is not LIVE.
outcome: status LIVE with the session expiry, or ENDED
inquiry: Is this caller session still live?
input contract check-api-session-request.v1 {"type":"object"}
output contract check-api-session-result.v1 {"type":"object"}
cli display outcome as json
scenario check-api-session root terminal
given: a principal id and a session id
when: the identity store reads the session
then: the outcome is LIVE or ENDED
operation check-api-session.check-prepare kind invoke-port port check-api-session-check-prepare
operation check-api-session.check kind invoke-port port check-api-session-check
operation check-api-session.answer kind invoke-port port check-api-session-answer
platform bind check-api-session-check-prepare
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"executionTarget":{"op":"literal","value":"sql-database-reader"},"executionNamespace":{"op":"literal","value":"sidefx:capabilities"},"executionScenario":{"op":"literal","value":"sql-database-reader"},"inputType":{"op":"literal","value":"json"},"dispatchRequest":{"op":"object","fields":{"dataSource":{"op":"literal","value":"sfx-identity-database"},"statement":{"op":"literal","value":"SET NOCOUNT ON; DECLARE @principal_id uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@input, '$.principalId')); DECLARE @session_id uniqueidentifier = TRY_CONVERT(uniqueidentifier, JSON_VALUE(@input, '$.sessionId')); DECLARE @expires datetimeoffset(7) = (SELECT s.expires_at FROM [identity].session s JOIN [identity].principal p ON p.principal_id = s.principal_id WHERE s.session_id = @session_id AND s.principal_id = @principal_id AND s.revoked_at IS NULL AND s.expires_at > SYSUTCDATETIME() AND p.active = 1); SELECT (SELECT CASE WHEN @expires IS NULL THEN N'ENDED' ELSE N'LIVE' END AS status, @expires AS sessionExpiresAt FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) AS value;"},"resultColumn":{"op":"literal","value":"value"},"input":{"op":"path","path":""}}}}}}
platform bind check-api-session-check
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind check-api-session-answer
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"string"}},"then":{"op":"let","bindings":{"parsed":{"op":"try-parse-json","value":{"op":"path","path":"result.value"},"stripBom":true}},"value":{"op":"path","path":"value","from":"parsed"}},"else":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"object"}},"then":{"op":"path","path":"result.value"},"else":{"op":"path","path":"result"}}}}
