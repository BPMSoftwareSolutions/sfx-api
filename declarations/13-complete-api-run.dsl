capability complete-api-run
intent: Complete a run the declared API executed asynchronously: the hosting facade calls it when the worker kernel ends the run, and the run store stages the output by digest and completes the run (state, capability, exit code, failure and timing) for writer sfx-api.
outcome: status COMPLETED with the run id, its state and whether its trace is complete
inquiry: Was this run completed in the run store?
input contract complete-api-run-request.v1 {"type":"object"}
output contract complete-api-run-result.v1 {"type":"object"}
cli display outcome as json
scenario complete-api-run root terminal
given: the run id, admission time, capability, state, exit code, failure, timing and output of a run
when: the run store stages the output and completes the run
then: the outcome is the completed run
operation complete-api-run.complete-prepare kind invoke-port port complete-api-run-complete-prepare
operation complete-api-run.complete kind invoke-port port complete-api-run-complete
operation complete-api-run.answer kind invoke-port port complete-api-run-answer
platform bind complete-api-run-complete-prepare
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"executionTarget":{"op":"literal","value":"sql-database-reader"},"executionNamespace":{"op":"literal","value":"sidefx:capabilities"},"executionScenario":{"op":"literal","value":"sql-database-reader"},"inputType":{"op":"literal","value":"json"},"dispatchRequest":{"op":"object","fields":{"dataSource":{"op":"literal","value":"sfx-identity-database"},"statement":{"op":"literal","value":"SET NOCOUNT ON; DECLARE @staged TABLE(value nvarchar(max)); DECLARE @digest varchar(64) = NULL; IF JSON_QUERY(@input, '$.output') IS NOT NULL BEGIN INSERT @staged EXEC evidence.stage_run_output @input = @input; SET @digest = (SELECT TOP (1) JSON_VALUE(value, '$.outputDigest') FROM @staged); END; DECLARE @run nvarchar(max) = (SELECT JSON_VALUE(@input, '$.runId') AS runId, JSON_VALUE(@input, '$.state') AS state, JSON_QUERY(@input, '$.capability') AS capability, TRY_CONVERT(int, JSON_VALUE(@input, '$.exitCode')) AS exitCode, JSON_QUERY(@input, '$.failure') AS failure, JSON_VALUE(@input, '$.startedAt') AS startedAt, JSON_VALUE(@input, '$.endedAt') AS endedAt, CONVERT(bit, 0) AS partial, JSON_QUERY((SELECT CONVERT(bit, CASE WHEN @digest IS NULL THEN 0 ELSE 1 END) AS available FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS output FOR JSON PATH, WITHOUT_ARRAY_WRAPPER); DECLARE @complete nvarchar(max) = (SELECT JSON_VALUE(@input, '$.runId') AS runId, N'sfx-api' AS writerId, JSON_VALUE(@input, '$.admittedAt') AS admittedAt, @digest AS outputDigest, 0 AS latestCursor, JSON_QUERY(@run) AS run FOR JSON PATH, WITHOUT_ARRAY_WRAPPER); EXEC evidence.complete_staged_run @input = @complete;"},"resultColumn":{"op":"literal","value":"value"},"input":{"op":"path","path":""}}}}}}
platform bind complete-api-run-complete
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind complete-api-run-answer
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"string"}},"then":{"op":"let","bindings":{"parsed":{"op":"try-parse-json","value":{"op":"path","path":"result.value"},"stripBom":true}},"value":{"op":"path","path":"value","from":"parsed"}},"else":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"object"}},"then":{"op":"path","path":"result.value"},"else":{"op":"path","path":"result"}}}}
