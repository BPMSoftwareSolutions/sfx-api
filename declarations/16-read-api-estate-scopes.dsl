capability read-api-estate-scopes
intent: Read the estates a signed-in caller may open in Estate through the declared API: the estate the topology reader selects, when its scope is readable, with the caller principal and how its retained and live activity are read. No run is created: the topology reader runs inside this read, with the smallest bounds, only for the estate identity and scope.
outcome: estate-scopes.v1 with the principal, the readable estates (id, label, revision, scopeId, read) and the availability of retained and live activity
inquiry: Which estates may this caller open, and how is their activity read?
input contract read-api-estate-scopes-request.v1 {"type":"object","properties":{"principalId":{"type":"string"}}}
output contract estate-scopes.v1 {"type":"object","required":["contractId","status","estates"]}
cli display outcome as json
scenario read-api-estate-scopes root terminal
given: the caller principal
when: the topology reader reads the selected estate's identity and scope
then: the outcome is estate-scopes.v1 with the readable estates
operation read-api-estate-scopes.read kind invoke-port port read-api-estate-scopes-read
platform bind read-api-estate-scopes-read
platform: sda-embodiment-plan-port.v1
config: {"statement":"SET NOCOUNT ON; DECLARE @t TABLE(value nvarchar(max)); INSERT @t EXEC analysis.read_estate_execution_topology @input = N'{\"capabilityLimit\":1,\"relationshipLimit\":1}', @estate_model_pk = @estate_model_pk; DECLARE @topology nvarchar(max) = (SELECT TOP (1) value FROM @t); DECLARE @readable bit = CASE WHEN JSON_VALUE(@topology, '$.status') = N'READ' AND JSON_VALUE(@topology, '$.scope.read') = N'true' THEN 1 ELSE 0 END; SELECT (SELECT N'estate-scopes.v1' AS contractId, N'READ' AS status, JSON_VALUE(@input, '$.principalId') AS principalId, JSON_QUERY(CASE WHEN @readable = 1 THEN N'[' + JSON_MODIFY(JSON_MODIFY(JSON_QUERY(@topology, '$.estate'), '$.scopeId', JSON_VALUE(@topology, '$.scope.namespaceId')), '$.read', CONVERT(bit, 1)) + N']' ELSE N'[]' END) AS estates, JSON_QUERY(N'{\"available\":true,\"maximumIntervalMilliseconds\":86400000,\"reads\":{\"topology\":\"/sfx/v1/estate-execution/topology\",\"activity\":\"/sfx/v1/estate-execution/activity\",\"coverage\":\"/sfx/v1/estate-execution/coverage\",\"provenance\":\"/sfx/v1/estate-execution/provenance\",\"revision\":\"/sfx/v1/estate-execution/revision\"}}') AS retained, JSON_QUERY(N'{\"available\":false,\"stream\":\"/sfx/v1/estate-execution/stream\"}') AS live FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS value;","resultColumn":"value","providerId":"sda-declared-read-graph-provider.v1"}
