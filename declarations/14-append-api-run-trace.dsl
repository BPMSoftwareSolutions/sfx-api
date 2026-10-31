capability append-api-run-trace
intent: Retain one contiguous chunk of the events of a run the declared API executes: the encode port (DEPENDENCY sfx-api-run-trace) writes the events as one brotli-compressed JSON array with its SHA-256, the encoding of the run store's other writers, and the run store appends it as the run's trace chunk for writer sfx-api (cursors contiguous, the run not yet completed).
outcome: status APPENDED with the run id, the chunk's cursors and its compressed size; a refused chunk answers its refusal
inquiry: Was this chunk of the run's trace retained?
input contract append-api-run-trace-request.v1 {"type":"object"}
output contract append-api-run-trace-result.v1 {"type":"object"}
cli display outcome as json
scenario append-api-run-trace root terminal
given: the run id, the first and last cursor, the record count and the events of one chunk
when: the chunk is encoded and the run store appends it
then: the outcome is the appended chunk
operation append-api-run-trace.encode kind invoke-port port append-api-run-trace-encode
operation append-api-run-trace.append-prepare kind invoke-port port append-api-run-trace-append-prepare
operation append-api-run-trace.append kind invoke-port port append-api-run-trace-append
operation append-api-run-trace.answer kind invoke-port port append-api-run-trace-answer
platform bind append-api-run-trace-encode
platform: sfx-api-run-trace-encode-port.v1
config: {"providerId":"sfx-api-run-trace-encode","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-api-run-trace"}}
platform bind append-api-run-trace-append-prepare
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"executionTarget":{"op":"literal","value":"sql-database-reader"},"executionNamespace":{"op":"literal","value":"sidefx:capabilities"},"executionScenario":{"op":"literal","value":"sql-database-reader"},"inputType":{"op":"literal","value":"json"},"dispatchRequest":{"op":"object","fields":{"dataSource":{"op":"literal","value":"sfx-identity-database"},"statement":{"op":"literal","value":"SET NOCOUNT ON; DECLARE @run_id varchar(128), @first bigint, @last bigint, @count int, @content64 nvarchar(max), @digest64 nvarchar(200); SELECT @run_id = runId, @first = firstCursor, @last = lastCursor, @count = recordCount, @content64 = content, @digest64 = digest FROM OPENJSON(@input) WITH (runId varchar(128) '$.runId', firstCursor bigint '$.firstCursor', lastCursor bigint '$.lastCursor', recordCount int '$.recordCount', content nvarchar(max) '$.content', digest nvarchar(200) '$.digest'); DECLARE @content varbinary(max) = CAST(N'' AS xml).value('xs:base64Binary(sql:variable(\"@content64\"))', 'varbinary(max)'); DECLARE @digest varbinary(32) = CAST(N'' AS xml).value('xs:base64Binary(sql:variable(\"@digest64\"))', 'varbinary(32)'); DECLARE @r TABLE(stored bit); INSERT @r EXEC evidence.append_trace_chunk @run_id = @run_id, @writer_id = 'sfx-api', @first_cursor = @first, @last_cursor = @last, @record_count = @count, @content_digest = @digest, @content = @content; SELECT (SELECT N'APPENDED' AS status, @run_id AS runId, @first AS firstCursor, @last AS lastCursor, DATALENGTH(@content) AS contentBytes FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS value;"},"resultColumn":{"op":"literal","value":"value"},"input":{"op":"path","path":""}}}}}}
platform bind append-api-run-trace-append
platform: generic-capability-invocation.v1
config: {"providerId":"generic-capability-invocation","authoritySource":"DATABASE","capabilityIdPath":"executionTarget","namespacePath":"executionNamespace","scenarioPath":"executionScenario","requestPath":"dispatchRequest","resultPath":"result","lineageMode":"retain-nested-execution"}
platform bind append-api-run-trace-answer
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"string"}},"then":{"op":"let","bindings":{"parsed":{"op":"try-parse-json","value":{"op":"path","path":"result.value"},"stripBom":true}},"value":{"op":"path","path":"value","from":"parsed"}},"else":{"op":"if","when":{"op":"equals","left":{"op":"type","value":{"op":"path","path":"result.value"}},"right":{"op":"literal","value":"object"}},"then":{"op":"path","path":"result.value"},"else":{"op":"path","path":"result"}}}}
