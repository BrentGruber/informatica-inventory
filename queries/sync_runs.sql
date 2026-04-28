-- name: CreateSyncRun :one
INSERT INTO sync_runs (
  run_type,
  status,
  environment_id,
  resource_type_id,
  triggered_by,
  workflow_id,
  workflow_run_id,
  started_at,
  stats_json,
  error_summary
)
VALUES (
  $1, $2, $3, $4, $5, $6, $7, now(), $8, $9
)
RETURNING *;

-- name: CompleteSyncRun :one
UPDATE sync_runs
SET status = $2,
    finished_at = now(),
    stats_json = $3,
    error_summary = $4
WHERE id = $1
RETURNING *;

-- name: ListRecentSyncRuns :many
SELECT *
FROM sync_runs
ORDER BY started_at DESC
LIMIT $1;
