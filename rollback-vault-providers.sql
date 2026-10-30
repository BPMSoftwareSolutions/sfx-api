-- Rollback of declare-vault-providers.sql by generation selection (re-declaring old content reuses the old definition
-- and does not make it newest). The seven vault providers return to their previous generations, and
-- run-declared-graph-execute to its newest generation without the host dictionary (it keeps the SEJ overlay bindings).
SET XACT_ABORT ON;
BEGIN TRANSACTION;
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-secret-service', @definition_digest = '249595028851ff0bd99671729137c47a201ebc29cb7bdf48fdda1e27db7e6438';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-secret-service-reference', @definition_digest = '20eb902de82cb0d41df2f89706bc9f809dc7efc57a8510098c83cafe6fe3992f';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-secret-service-seal', @definition_digest = '8d057ec089f45aa7a5e80b388215e5c3a4d860b130e4780e3b70d6f5e90350d3';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-file', @definition_digest = '0121d9391da3c908cd08ebe70cd89207582f758f8d302c523d86289b350ae257';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-file-host', @definition_digest = '5006b788c308c5fce3424a2a1164f7ccf588c0391401370425c3a9ddccc5c8c1';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-file-reference', @definition_digest = '8dc35dacf45a18b3d7b94201f3183aa9e4f9266ef6d1725aa0f9f7fc71436342';
EXEC model.select_definition_generation @namespace = N'sidefx:providers', @declared_id = N'sfx-vault-file-host-write', @definition_digest = '7441e5590fab0309df510fad2169ba596abfa643aff516d35540d7a067148b00';
DECLARE @e bigint = (SELECT estate_model_pk FROM source.current_model WHERE singleton_id = 1);
DECLARE @port varchar(64) = (
  SELECT TOP (1) LOWER(CONVERT(varchar(64), d.definition_digest, 2))
  FROM model.semantic_object so
  JOIN model.identity_namespace n ON n.namespace_pk = so.namespace_pk
  JOIN model.semantic_object_definition d ON d.semantic_object_pk = so.semantic_object_pk
  JOIN model.estate_definition ed ON ed.semantic_object_definition_pk = d.semantic_object_definition_pk AND ed.estate_model_pk = @e
  JOIN source.content_object co ON co.content_object_pk = d.canonical_content_pk
  WHERE n.namespace_id = N'sidefx:capability:run-declared-graph' AND so.declared_id = N'run-declared-graph-execute'
    AND CONVERT(varchar(max), co.content_bytes) NOT LIKE '%hostRootName%'
    AND CONVERT(varchar(max), co.content_bytes) LIKE '%"mechanicId":"call"%'
  ORDER BY d.semantic_object_definition_pk DESC);
IF @port IS NULL THROW 51000, N'PREVIOUS_RUNNER_GENERATION_NOT_FOUND', 1;
SELECT @port AS runner_generation_selected;
EXEC model.select_definition_generation @namespace = N'sidefx:capability:run-declared-graph', @declared_id = N'run-declared-graph-execute', @definition_digest = @port;
COMMIT;