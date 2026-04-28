-- name: UpsertResource :one
INSERT INTO resources (
  environment_id,
  resource_type_id,
  external_id,
  external_key,
  name,
  display_name,
  path,
  folder_path,
  status,
  subtype,
  description,
  version,
  created_by,
  updated_by,
  created_at_source,
  updated_at_source,
  first_seen_at,
  last_seen_at,
  last_synced_at,
  is_deleted,
  summary_json,
  detail_json
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
  $12, $13, $14, $15, $16, now(), now(), $17, $18, $19, $20
)
ON CONFLICT (environment_id, resource_type_id, external_id)
DO UPDATE SET
  external_key = EXCLUDED.external_key,
  name = EXCLUDED.name,
  display_name = EXCLUDED.display_name,
  path = EXCLUDED.path,
  folder_path = EXCLUDED.folder_path,
  status = EXCLUDED.status,
  subtype = EXCLUDED.subtype,
  description = EXCLUDED.description,
  version = EXCLUDED.version,
  created_by = EXCLUDED.created_by,
  updated_by = EXCLUDED.updated_by,
  created_at_source = EXCLUDED.created_at_source,
  updated_at_source = EXCLUDED.updated_at_source,
  last_seen_at = now(),
  last_synced_at = EXCLUDED.last_synced_at,
  is_deleted = EXCLUDED.is_deleted,
  summary_json = EXCLUDED.summary_json,
  detail_json = EXCLUDED.detail_json
RETURNING *;

-- name: ListResourcesByEnvironmentAndType :many
SELECT *
FROM resources
WHERE environment_id = $1
  AND resource_type_id = $2
  AND is_deleted = false
ORDER BY name ASC;

-- name: GetResourceByExternalID :one
SELECT *
FROM resources
WHERE environment_id = $1
  AND resource_type_id = $2
  AND external_id = $3;
