-- 23-read-estate-drawing-changes.grant.sql
--
-- Bootstrap grant for read-estate-drawing-changes (declarations/23-read-estate-drawing-changes.dsl), run once by a
-- database administrator of the estate database (sidefx). The capability maps the rows each commit changed to the
-- circuit drawings that read them through CHANGETABLE, which needs VIEW CHANGE TRACKING on each table it reads. The
-- estate's reader identity, sidefx_reader, does not have it: the capability answers FAILED with error 229 ("The VIEW
-- CHANGE TRACKING permission was denied on the object 'identity_namespace'", run e909dc95, 2026-11-02).
--
-- No estate-native path can grant it: the engineering-change writer refuses grant tokens by contract, the same gap
-- the estate tracks as ena-mechanic-execute-provisioning (BLOCKED 2026-10-17, docs/request-sda-declared-change-
-- provisioning.md in sfx-embody).
--
-- The grant changes no data and adds no write permission: VIEW CHANGE TRACKING exposes only the primary keys and
-- change versions of rows the reader can already SELECT. REVOKE VIEW CHANGE TRACKING ON ... FROM sidefx_reader
-- undoes it.
SET NOCOUNT ON;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.capability TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.capability_root_scenario TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.capability_scenario TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.capability_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.contract TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.contract_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.estate_capability TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.estate_definition TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.execution_authority TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.execution_authority_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.execution_operation TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.identity_namespace TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.mechanic_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.operation_mechanic TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.operation_port_invocation TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.operation_scenario_invocation TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.outcome_variant TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.port TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.port_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario_event TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario_input TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario_outcome TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario_outcome_contract TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.scenario_version TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.schema_object TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.semantic_object TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::model.semantic_object_definition TO sidefx_reader;
GRANT VIEW CHANGE TRACKING ON OBJECT::source.content_object TO sidefx_reader;
SELECT N'read_estate_drawing_changes_grant' AS result_set,
  (SELECT COUNT(*) FROM sys.database_permissions p JOIN sys.database_principals r ON r.principal_id=p.grantee_principal_id
   WHERE r.name=N'sidefx_reader' AND p.permission_name=N'VIEW CHANGE TRACKING' AND p.state=N'G') AS granted_tables;
