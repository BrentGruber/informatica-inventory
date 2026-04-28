-- name: UpsertResourceRelationship :one
INSERT INTO resource_relationships (
  environment_id,
  from_resource_id,
  to_resource_id,
  relationship_type,
  directionality,
  metadata_json,
  first_seen_at,
  last_seen_at
)
VALUES (
  $1, $2, $3, $4, $5, $6, now(), now()
)
ON CONFLICT (from_resource_id, to_resource_id, relationship_type)
DO UPDATE SET
  directionality = EXCLUDED.directionality,
  metadata_json = EXCLUDED.metadata_json,
  last_seen_at = now()
RETURNING *;

-- name: ListOutgoingRelationships :many
SELECT *
FROM resource_relationships
WHERE from_resource_id = $1
ORDER BY relationship_type, to_resource_id;

-- name: ListIncomingRelationships :many
SELECT *
FROM resource_relationships
WHERE to_resource_id = $1
ORDER BY relationship_type, from_resource_id;
