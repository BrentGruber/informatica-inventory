-- name: UpsertEnvironment :one
INSERT INTO environments (
  external_id,
  name,
  description,
  region,
  organization_id,
  organization_name,
  status,
  base_url,
  metadata_json,
  first_seen_at,
  last_seen_at,
  last_synced_at
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9,
  now(), now(), $10
)
ON CONFLICT (external_id)
DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  region = EXCLUDED.region,
  organization_id = EXCLUDED.organization_id,
  organization_name = EXCLUDED.organization_name,
  status = EXCLUDED.status,
  base_url = EXCLUDED.base_url,
  metadata_json = EXCLUDED.metadata_json,
  last_seen_at = now(),
  last_synced_at = EXCLUDED.last_synced_at
RETURNING *;

-- name: ListEnvironments :many
SELECT *
FROM environments
ORDER BY name ASC;

-- name: GetEnvironmentByExternalID :one
SELECT *
FROM environments
WHERE external_id = $1;
