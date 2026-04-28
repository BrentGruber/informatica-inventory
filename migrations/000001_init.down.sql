DROP INDEX IF EXISTS idx_sync_tasks_status;
DROP INDEX IF EXISTS idx_sync_runs_status;
DROP INDEX IF EXISTS idx_resource_relationships_to;
DROP INDEX IF EXISTS idx_resource_relationships_from;
DROP INDEX IF EXISTS idx_resources_detail_json;
DROP INDEX IF EXISTS idx_resources_external_key;
DROP INDEX IF EXISTS idx_resources_name;
DROP INDEX IF EXISTS idx_resources_environment_type;

DROP TABLE IF EXISTS sync_errors;
DROP TABLE IF EXISTS sync_tasks;
DROP TABLE IF EXISTS sync_runs;
DROP TABLE IF EXISTS resource_relationships;
DROP TABLE IF EXISTS resources;
DROP TABLE IF EXISTS resource_types;
DROP TABLE IF EXISTS service_accounts;
DROP TABLE IF EXISTS environments;
