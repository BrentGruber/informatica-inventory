-- name: CreateSyncTask :one
INSERT INTO sync_tasks (
  sync_run_id,
  environment_id,
  resource_type_id,
  resource_id,
  task_key,
  status,
  attempt,
  started_at,
  finished_at,
  stats_json,
  error_message
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
)
RETURNING *;

-- name: MarkSyncTaskRunning :one
UPDATE sync_tasks
SET status = 'running',
    started_at = now(),
    error_message = NULL
WHERE id = $1
RETURNING *;

-- name: MarkSyncTaskCompleted :one
UPDATE sync_tasks
SET status = 'completed',
    finished_at = now(),
    stats_json = $2,
    error_message = NULL
WHERE id = $1
RETURNING *;

-- name: MarkSyncTaskFailed :one
UPDATE sync_tasks
SET status = 'failed',
    finished_at = now(),
    error_message = $2,
    stats_json = $3
WHERE id = $1
RETURNING *;

-- name: ListSyncTasksByRun :many
SELECT *
FROM sync_tasks
WHERE sync_run_id = $1
ORDER BY id ASC;
