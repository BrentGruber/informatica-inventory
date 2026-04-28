-- name: CreateSyncError :one
INSERT INTO sync_errors (
  sync_run_id,
  sync_task_id,
  environment_id,
  resource_type_id,
  resource_id,
  error_class,
  error_code,
  message,
  details_json,
  created_at
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, now()
)
RETURNING *;

-- name: ListSyncErrorsByRun :many
SELECT *
FROM sync_errors
WHERE sync_run_id = $1
ORDER BY created_at DESC;
