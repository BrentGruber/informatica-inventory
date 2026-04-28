-- name: UpsertServiceAccount :one
INSERT INTO service_accounts (
  environment_id,
  external_id,
  name,
  username,
  principal_type,
  is_admin,
  is_active,
  credential_ref,
  metadata_json,
  first_seen_at,
  last_seen_at
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, now(), now()
)
ON CONFLICT (environment_id, name)
DO UPDATE SET
  external_id = EXCLUDED.external_id,
  username = EXCLUDED.username,
  principal_type = EXCLUDED.principal_type,
  is_admin = EXCLUDED.is_admin,
  is_active = EXCLUDED.is_active,
  credential_ref = EXCLUDED.credential_ref,
  metadata_json = EXCLUDED.metadata_json,
  last_seen_at = now()
RETURNING *;

-- name: ListServiceAccountsByEnvironment :many
SELECT *
FROM service_accounts
WHERE environment_id = $1
ORDER BY name ASC;

-- name: GetAdminServiceAccountByEnvironment :one
SELECT *
FROM service_accounts
WHERE environment_id = $1
  AND is_admin = true
  AND is_active = true
ORDER BY last_seen_at DESC, id DESC
LIMIT 1;
