-- name: ListEnabledResourceTypes :many
SELECT *
FROM resource_types
WHERE is_enabled = true
ORDER BY code ASC;

-- name: GetResourceTypeByCode :one
SELECT *
FROM resource_types
WHERE code = $1;
